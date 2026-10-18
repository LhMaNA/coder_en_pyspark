"""Catalogue des anomalies : registre des règles, règles directes (01 à 11), détection et synthèses.

Ajouter une anomalie = écrire une fonction décorée par `@regle("NN", "Nom")` qui reçoit
(donnees, seuils) et renvoie une table Spark (num_automate, date, valeur), ou None si elle ne s'applique pas.
Les règles « cachées » (12 à 17) sont dans `anomalies_cachees.py`.
"""
import time
from collections import namedtuple

import pandas as pd
from pyspark.sql import SparkSession, Window
from pyspark.sql import functions as F
from pyspark.sql import types as T

from .indicateurs import calculer_silences, grille_horaire
from .outils import (CLE_TERMINAL, centile, en_pandas, fenetre_jours_precedents, fenetre_meme_jour_semaine, fmt_nombre,
                     persister)

Regle = namedtuple("Regle", ["code", "nom", "fonction"])
REGLES = []
SCHEMA_EVENEMENTS = T.StructType([T.StructField(CLE_TERMINAL, T.StringType()), T.StructField("date", T.DateType()),
                                  T.StructField("type", T.StringType()), T.StructField("valeur", T.DoubleType())])


def regle(code, nom):
    """Décorateur : enregistre une règle d'anomalie dans le catalogue."""
    def enregistrer(fonction):
        REGLES.append(Regle(code, "{} {}".format(code, nom), fonction))
        return fonction
    return enregistrer


class DonneesAnalyse(object):
    """Tables partagées par les règles, et mémoire des calculs intermédiaires coûteux (calculés une fois)."""

    def __init__(self, ops, transactions, journees, conf, validite=None, referentiel=None, correspondance=None):
        self.ops = ops
        self.transactions = transactions
        self.journees = journees
        self.conf = conf
        self.validite = validite
        self.referentiel = referentiel
        self.correspondance = correspondance or {}
        self._memoire = {}
        self.journees_signalees = set()   # (num_automate, date) déjà signalées par une règle

    def colonne_presente(self, nom):
        """Vrai si la colonne `nom` existe dans la table d'origine."""
        return bool(self.correspondance.get(nom))

    @property
    def coupures_presentes(self):
        """Vrai si les colonnes nb1-nb4 existent (billets délivrés par cassette)."""
        return all(self.colonne_presente("nb{}".format(i)) for i in range(1, 5))

    @property
    def retraits(self):
        """Transactions de type retrait."""
        return self.transactions.filter(F.col("est_retrait") == 1)

    def memoriser(self, nom, calcul):
        """Renvoie le résultat de `calcul()`, calculé une seule fois puis gardé en mémoire."""
        if nom not in self._memoire:
            self._memoire[nom] = calcul()
        return self._memoire[nom]

    def resultat(self, nom):
        """Résultat déjà calculé sous ce nom (ou None s'il ne l'a pas été)."""
        return self._memoire.get(nom)

    def grille_horaire(self):
        """Retraits par terminal, jour et heure de la plage étudiée (heures vides comprises)."""
        options = self.conf["options"]
        return self.memoriser("grille_horaire", lambda: grille_horaire(
            self.retraits, self.journees, options["heure_debut_jour"], options["heure_fin_jour"],
            options["persister"]))

    def silences(self):
        """Pire silence de chaque journée terminal (voir indicateurs.calculer_silences)."""
        return self.memoriser("silences", lambda: persister(
            calculer_silences(self.grille_horaire(), self.journees), self.conf["options"]["persister"]))

    def groupes_pairs(self):
        """Groupe de pairs de chaque terminal (num_automate, groupe), ou None si la colonne est absente."""
        colonne = self.conf["options"]["groupe_pairs"]
        if self.referentiel is None or colonne not in self.referentiel.columns:
            return None
        return self.referentiel.select(CLE_TERMINAL, F.coalesce(F.col(colonne).cast("string"), F.lit("inconnu"))
                                       .alias("groupe"))


# ------------------------------------------------------------------ règles directes
@regle("01", "Silence anormal")
def regle_silence(donnees, seuils):
    """Heures consécutives sans retrait, improbables vu le rythme horaire du terminal et l'activité du jour."""
    return (donnees.silences().filter(F.col("proba_hasard") < seuils["silence_proba"])
            .select(CLE_TERMINAL, "date", F.col("silence_h").alias("valeur")))


@regle("02", "Journée sans opération (terminal très fréquenté)")
def regle_journee_sans_operation(donnees, seuils):
    """Aucune opération un jour où un terminal très fréquenté en fait habituellement."""
    journees = donnees.journees
    mediane = journees.groupBy(CLE_TERMINAL).agg(centile("retraits", 0.5).alias("mediane"))
    seuil = mediane.approxQuantile("mediane", [seuils["muet_quantile_parc"]], 0.001)[0]
    tres_frequentes = mediane.filter(F.col("mediane") >= seuil).select(CLE_TERMINAL)
    print("terminal très fréquentés : au moins {:.0f} retraits par jour -> {} terminal".format(
        seuil, fmt_nombre(tres_frequentes.count())))
    vie = journees.groupBy(CLE_TERMINAL).agg(F.min("date").alias("d0"), F.max("date").alias("d1"))
    habitude = (journees.groupBy(CLE_TERMINAL, F.dayofweek("date").alias("js"))
                .agg(centile("retraits", 0.5).alias("retraits_habituels")))
    calendrier = journees.select("date").distinct().withColumn("js", F.dayofweek("date"))
    attendus = (vie.join(tres_frequentes, CLE_TERMINAL).crossJoin(calendrier)
                .filter((F.col("date") > F.col("d0")) & (F.col("date") < F.col("d1")))
                .join(habitude, [CLE_TERMINAL, "js"])
                .filter(F.col("retraits_habituels") >= seuils["muet_retraits_habituels"]))
    return (attendus.join(journees.select(CLE_TERMINAL, "date"), [CLE_TERMINAL, "date"], "left_anti")
            .select(CLE_TERMINAL, "date", F.col("retraits_habituels").alias("valeur")))


@regle("03", "Rafale")
def regle_rafale(donnees, seuils):
    """Opérations en 10 minutes très au-dessus du niveau élevé habituel du terminal (99e centile)."""
    transactions = donnees.transactions
    habitude = transactions.groupBy(CLE_TERMINAL).agg(centile("nb_ope_5min", 0.99).alias("p99"))
    return (transactions.join(F.broadcast(habitude), CLE_TERMINAL)
            .filter((F.col("nb_ope_5min") >= seuils["rafale_min_10min"]) &
                    (F.col("nb_ope_5min") >= seuils["rafale_facteur"] * F.col("p99")))
            .groupBy(CLE_TERMINAL, "date").agg(F.max("nb_ope_5min").alias("valeur")))


@regle("04", "Même montant répété")
def regle_meme_montant(donnees, seuils):
    """Beaucoup de retraits du même montant en quelques minutes."""
    fenetre = (Window.partitionBy(CLE_TERMINAL, "montant").orderBy("t")
               .rangeBetween(0, seuils["meme_montant_fenetre_s"]))
    return (donnees.retraits.withColumn("meme_montant", F.count("*").over(fenetre))
            .filter(F.col("meme_montant") >= seuils["meme_montant_min"])
            .groupBy(CLE_TERMINAL, "date").agg(F.max("meme_montant").alias("valeur")))


def series_consecutives(retraits, condition):
    """Suites de retraits consécutifs d'un terminal qui remplissent `condition` (longueur = nb de retraits)."""
    fenetre = Window.partitionBy(CLE_TERMINAL).orderBy("t").rowsBetween(Window.unboundedPreceding, 0)
    marquee = (retraits.withColumn("dans_serie", condition.cast("int"))
               .withColumn("serie", F.sum(1 - F.col("dans_serie")).over(fenetre)))
    return (marquee.filter(F.col("dans_serie") == 1).groupBy(CLE_TERMINAL, "serie")
            .agg(F.min("date").alias("date"), (F.count("*") + 1).alias("longueur")))


@regle("05", "Inaboutis en série")
def regle_inaboutis_serie(donnees, seuils):
    """Retraits inaboutis consécutifs."""
    series = series_consecutives(donnees.retraits, (F.col("inabouti") == 1) & (F.col("inabouti_precedent") == 1))
    return (series.filter(F.col("longueur") >= seuils["inaboutis_serie_min"])
            .select(CLE_TERMINAL, "date", F.col("longueur").alias("valeur")))


@regle("06", "Captures hors réseau interne en série")
def regle_captures_serie(donnees, seuils):
    """Plusieurs captures hors réseau interne en moins d'une heure."""
    heure_glissante = Window.partitionBy(CLE_TERMINAL).orderBy("t").rangeBetween(-3600, 0)
    return (donnees.transactions.filter(F.col("est_capture_externe") == 1)
            .withColumn("captures_1h", F.count("*").over(heure_glissante))
            .filter(F.col("captures_1h") >= seuils["captures_heure_min"])
            .groupBy(CLE_TERMINAL, "date").agg(F.max("captures_1h").alias("valeur")))


@regle("07", "Afflux cartes étrangères")
def regle_cartes_etrangeres(donnees, seuils):
    """Pic horaire de cartes étrangères rares, très au-dessus de l'habitude horaire du terminal (90e centile)."""
    par_heure = (donnees.retraits.filter(F.col("est_etranger") == 1)
                 .groupBy(CLE_TERMINAL, "date", "heure").agg(F.count("*").alias("etrangers_heure")))
    habitude = par_heure.groupBy(CLE_TERMINAL).agg(centile("etrangers_heure", 0.9).alias("p90"))
    return (par_heure.join(F.broadcast(habitude), CLE_TERMINAL)
            .filter((F.col("etrangers_heure") >= seuils["etrangers_heure_min"]) &
                    (F.col("etrangers_heure") >= seuils["etrangers_facteur"] * F.col("p90")))
            .groupBy(CLE_TERMINAL, "date").agg(F.max("etrangers_heure").alias("valeur")))


@regle("08", "Nuit inhabituelle")
def regle_nuit(donnees, seuils):
    """Retraits entre 0 h et 5 h sur un terminal qui n'en fait presque jamais."""
    retraits = donnees.retraits
    part_nuit = retraits.groupBy(CLE_TERMINAL).agg(F.avg((F.col("heure") < 5).cast("int")).alias("part_0h_5h"))
    return (retraits.filter(F.col("heure") < 5).groupBy(CLE_TERMINAL, "date").agg(F.count("*").alias("valeur"))
            .join(F.broadcast(part_nuit), CLE_TERMINAL)
            .filter((F.col("valeur") >= seuils["nuit_min"]) & (F.col("part_0h_5h") <= seuils["nuit_part_max"]))
            .select(CLE_TERMINAL, "date", "valeur"))


@regle("09", "Carte expirée")
def regle_carte_expiree(donnees, seuils):
    """Retrait avec une carte dont la date de validité est dépassée."""
    if donnees.validite is None:
        return None
    return (donnees.validite.filter(F.col("mois_restants") < 0)
            .groupBy(CLE_TERMINAL, "date").agg(F.count("*").alias("valeur")))


@regle("10", "Volume journalier anormal")
def regle_volume(donnees, seuils):
    """Retraits du jour multipliés par rapport aux 8 mêmes jours de semaine ET aux 7 derniers jours."""
    meme_jour, derniers_jours = fenetre_meme_jour_semaine(), fenetre_jours_precedents()
    return (donnees.journees
            .withColumn("moy8", F.avg("retraits").over(meme_jour))
            .withColumn("et8", F.stddev("retraits").over(meme_jour))
            .withColumn("n8", F.count("retraits").over(meme_jour))
            .withColumn("moy7", F.avg("retraits").over(derniers_jours))
            .withColumn("valeur", F.col("retraits") / F.col("moy8"))
            .withColumn("ecart", (F.col("retraits") - F.col("moy8")) /
                        F.greatest(F.coalesce(F.col("et8"), F.lit(0.0)), F.sqrt(F.greatest(F.col("moy8"), F.lit(1.0)))))
            .filter((F.col("n8") >= 4) & (F.col("moy8") >= seuils["volume_habitude_min"]) &
                    (F.col("ecart") >= seuils["volume_ecart"]) & (F.col("valeur") >= seuils["volume_ratio"]) &
                    (F.col("retraits") >= seuils["volume_ratio"] * F.col("moy7")))
            .select(CLE_TERMINAL, "date", "valeur"))


@regle("11", "Montant moyen anormal")
def regle_montant_moyen(donnees, seuils):
    """Montant moyen du jour multiplié par rapport aux 8 mêmes jours de semaine."""
    meme_jour = fenetre_meme_jour_semaine()
    return (donnees.journees.filter(F.col("retraits") >= seuils["montant_retraits_min"])
            .withColumn("montant_moyen", F.col("montant") / F.col("retraits"))
            .withColumn("mm8", F.avg("montant_moyen").over(meme_jour))
            .withColumn("n8", F.count("montant_moyen").over(meme_jour))
            .withColumn("valeur", F.col("montant_moyen") / F.col("mm8"))
            .filter((F.col("n8") >= 4) & (F.col("valeur") >= seuils["montant_ratio"]))
            .select(CLE_TERMINAL, "date", "valeur"))


# ------------------------------------------------------------------ détection et synthèses
def detecter_anomalies(donnees, seuils, codes=None):
    """Applique les règles du catalogue (toutes, ou celles dont le code est dans `codes`).

    Renvoie une table Spark (num_automate, date, type, valeur, semaine, jour_semaine).
    """
    morceaux = []
    for r in sorted(REGLES, key=lambda r: r.code):
        if codes and r.code not in codes:
            continue
        debut = time.time()
        resultat = r.fonction(donnees, seuils)
        if resultat is None:
            print("{:<48} ignorée (données indisponibles)".format(r.nom))
            continue
        # Chaque règle est calculée et ramenée séparément : unir les 17 plans Spark avant exécution produit
        # un plan trop gros pour l'optimiseur. Les résultats (événements) sont petits.
        evenements_regle = en_pandas(resultat.select(CLE_TERMINAL, F.col("date").cast("date").alias("date"),
                                                     F.col("valeur").cast("double").alias("valeur")))
        evenements_regle["type"] = r.nom
        morceaux.append(evenements_regle)
        donnees.journees_signalees.update(zip(evenements_regle[CLE_TERMINAL].astype(str),
                                              pd.to_datetime(evenements_regle["date"]).dt.date))
        print("{:<48} {:>8} événements  {:>6.0f} s".format(r.nom, len(evenements_regle), time.time() - debut))
    if not morceaux:
        raise ValueError("Aucune règle n'a pu être appliquée.")
    tous = pd.concat(morceaux, ignore_index=True)[[CLE_TERMINAL, "date", "type", "valeur"]]
    tous[CLE_TERMINAL] = tous[CLE_TERMINAL].astype(str)
    spark = SparkSession.builder.getOrCreate()
    evenements = (spark.createDataFrame(tous, schema=SCHEMA_EVENEMENTS)
                  .withColumn("semaine", F.weekofyear("date")).withColumn("jour_semaine", F.dayofweek("date")))
    return persister(evenements, donnees.conf["options"]["persister"])


def synthese_par_type(evenements, nb_terminal, nb_jours, semaines_recurrence=4):
    """Fréquence, terminal touchés et récurrence de chaque anomalie ; et occurrences par type et par terminal."""
    recap = en_pandas(evenements.groupBy("type").agg(
        F.count("*").alias("evenements"),
        F.countDistinct(CLE_TERMINAL).alias("terminal_touches"),
        F.countDistinct(F.concat_ws("|", F.col(CLE_TERMINAL), F.col("date").cast("string"))).alias("journees_terminal"),
        F.countDistinct("date").alias("jours_concernes")))
    par_type_terminal = en_pandas(evenements.groupBy("type", CLE_TERMINAL).agg(
        F.countDistinct("semaine").alias("semaines"), F.count("*").alias("n")))
    recurrence = par_type_terminal.groupby("type").agg(
        occurrences_medianes_par_terminal=("n", "median"),
        pct_terminal_recurrents=("semaines", lambda semaines: 100 * (semaines >= semaines_recurrence).mean()))
    recap = recap.set_index("type").join(recurrence).sort_index()
    recap["pct_terminal_touches"] = 100 * recap["terminal_touches"] / max(nb_terminal, 1)
    recap["evenements_par_jour"] = recap["evenements"] / max(nb_jours, 1)
    return recap, par_type_terminal


def cooccurrences(evenements):
    """% des journées terminal de l'anomalie (ligne) qui présentent aussi l'anomalie (colonne)."""
    journees_type = evenements.select(CLE_TERMINAL, "date", "type").distinct()
    paires = en_pandas(journees_type.alias("a").join(journees_type.alias("b"), [CLE_TERMINAL, "date"])
                       .groupBy(F.col("a.type").alias("type_a"), F.col("b.type").alias("type_b")).count())
    matrice = paires.pivot(index="type_a", columns="type_b", values="count").fillna(0)
    diagonale = pd.Series([matrice.loc[t, t] for t in matrice.index], index=matrice.index)
    matrice = matrice.div(diagonale, axis=0) * 100
    for t in matrice.index:
        matrice.loc[t, t] = 0
    return matrice


def synthese_par_terminal(par_type_terminal, par_terminal, infos=("ville", "libelle_site", "retraits_par_jour_actif")):
    """Une ligne par terminal touché : nombre d'anomalies différentes, d'événements, et le détail par type."""
    occurrences = par_type_terminal.pivot(index=CLE_TERMINAL, columns="type", values="n").fillna(0)
    synthese = occurrences.copy()
    synthese["nb_anomalies_differentes"] = (occurrences > 0).sum(axis=1)
    synthese["evenements"] = occurrences.sum(axis=1)
    synthese["detail"] = occurrences.apply(
        lambda ligne: ", ".join("{} : {:.0f}".format(nom[3:], n) for nom, n in ligne.items() if n > 0), axis=1)
    colonnes = [c for c in infos if c in par_terminal.columns]
    synthese = synthese.join(par_terminal.set_index(CLE_TERMINAL)[colonnes])
    return synthese.sort_values(["nb_anomalies_differentes", "evenements"], ascending=False), occurrences


def exemples_par_type(evenements):
    """Le cas le plus marqué (|valeur| maximale) de chaque anomalie."""
    plus_marque = Window.partitionBy("type").orderBy(F.desc("force"))
    return en_pandas(evenements.withColumn("force", F.abs(F.col("valeur")))
                     .withColumn("rang", F.row_number().over(plus_marque)).filter(F.col("rang") == 1)
                     .select("type", CLE_TERMINAL, "date", "valeur").orderBy("type"))


def aide_au_choix(recap, part_trop_frequente=60, journees_trop_rares=20):
    """Classement indicatif des anomalies : fréquence et récurrence, avec repérage des extrêmes."""
    choix = recap[["journees_terminal", "pct_terminal_touches", "pct_terminal_recurrents", "evenements_par_jour"]].copy()
    choix["trop_frequente"] = choix["pct_terminal_touches"] > part_trop_frequente
    choix["trop_rare"] = choix["journees_terminal"] < journees_trop_rares
    choix["rang"] = (choix["journees_terminal"].rank(ascending=False)
                     + choix["pct_terminal_recurrents"].rank(ascending=False))
    return choix.sort_values("rang")
