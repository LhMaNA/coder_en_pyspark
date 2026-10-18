"""Anomalies cachées (règles 12 à 17) : ce qu'aucun indicateur seul ne montre.

12  forme horaire de la journée inhabituelle (même si le total est normal)
13  mélange des réseaux de cartes inhabituel (même à volume normal)
14  décrochage ou emballement par rapport aux terminaux pairs le même jour
15  dérive lente sur plusieurs semaines, propre au terminal
16  trou horaire récurrent : une heure habituellement active reste vide un jour sur deux
17  combinaison de petits écarts simultanés (Isolation Forest sur les écarts robustes)
"""
import numpy as np
import pandas as pd
from pyspark.sql import SparkSession, Window
from pyspark.sql import functions as F

from .anomalies import regle
from .outils import CLE_TERMINAL, centile, en_pandas, fenetre_meme_jour_semaine

INDICATEURS_MULTIVARIES = {
    # indicateur : plancher de dispersion ("racine" = bruit de comptage, sinon part de la moyenne)
    "retraits": "racine", "inaboutis": "racine", "captures_externe": "racine", "etrangers": "racine",
    "retraits_nuit": "racine", "rafale": "racine", "montant_moyen": 0.1,
}


# ------------------------------------------------------------------ divergences de distribution
def divergence_jensen_shannon(observe, habituel, cles_jour, cles_habitude, modalite):
    """Divergence de Jensen-Shannon (log2, entre 0 et 1) entre la distribution du jour et l'habituelle.

    `observe` : cles_jour + [modalite, n] ; `habituel` : cles_habitude + [modalite, q] avec q sommant à 1.
    Les modalités absentes du jour comptent pour 0,5 x q (terme q.log2(q / (q/2)) / 2).
    """
    total = observe.groupBy(*cles_jour).agg(F.sum("n").alias("total"))
    jointe = (observe.join(total, cles_jour).withColumn("p", F.col("n") / F.col("total"))
              .join(habituel, cles_habitude + [modalite], "left").fillna(0.0, subset=["q"])
              .withColumn("m", (F.col("p") + F.col("q")) / 2))
    terme = (0.5 * F.col("p") * F.log2(F.col("p") / F.col("m"))
             + F.when(F.col("q") > 0, 0.5 * F.col("q") * F.log2(F.col("q") / F.col("m"))).otherwise(0.0))
    return (jointe.groupBy(*(cles_jour + ["total"]))
            .agg(F.sum(terme).alias("somme"), F.sum("q").alias("q_vue"))
            .withColumn("divergence", F.col("somme") + 0.5 * (1 - F.col("q_vue")))
            .drop("somme", "q_vue"))


def divergences_horaires(retraits):
    """Divergence de la forme horaire de chaque journée terminal par rapport à l'habitude (semaine / week-end)."""
    avec_type_jour = retraits.withColumn("week_end", F.dayofweek("date").isin(1, 7).cast("int"))
    observe = avec_type_jour.groupBy(CLE_TERMINAL, "date", "week_end", "heure").agg(F.count("*").alias("n"))
    habitude = observe.groupBy(CLE_TERMINAL, "week_end", "heure").agg(F.sum("n").alias("n_h"))
    habitude = (habitude.join(habitude.groupBy(CLE_TERMINAL, "week_end").agg(F.sum("n_h").alias("n_tot")),
                              [CLE_TERMINAL, "week_end"])
                .select(CLE_TERMINAL, "week_end", "heure", (F.col("n_h") / F.col("n_tot")).alias("q")))
    return divergence_jensen_shannon(observe, habitude, [CLE_TERMINAL, "date", "week_end"], [CLE_TERMINAL, "week_end"],
                                     "heure")


def divergences_reseaux(retraits):
    """Divergence du mélange des réseaux de chaque journée terminal par rapport à l'habitude du terminal."""
    observe = retraits.groupBy(CLE_TERMINAL, "date", "groupe_reseau").agg(F.count("*").alias("n"))
    habitude = observe.groupBy(CLE_TERMINAL, "groupe_reseau").agg(F.sum("n").alias("n_r"))
    habitude = (habitude.join(habitude.groupBy(CLE_TERMINAL).agg(F.sum("n_r").alias("n_tot")), CLE_TERMINAL)
                .select(CLE_TERMINAL, "groupe_reseau", (F.col("n_r") / F.col("n_tot")).alias("q")))
    return divergence_jensen_shannon(observe, habitude, [CLE_TERMINAL, "date"], [CLE_TERMINAL], "groupe_reseau")


def journees_divergentes(divergences, volume_min, nb_ecarts, divergence_min):
    """Journées dont la divergence dépasse la médiane du terminal + `nb_ecarts` écarts robustes (et un minimum)."""
    suffisantes = divergences.filter(F.col("total") >= volume_min)
    mediane = suffisantes.groupBy(CLE_TERMINAL).agg(centile("divergence", 0.5).alias("med"))
    avec_med = suffisantes.join(mediane, CLE_TERMINAL)
    mad = (avec_med.withColumn("dev", F.abs(F.col("divergence") - F.col("med")))
           .groupBy(CLE_TERMINAL).agg(centile("dev", 0.5).alias("mad")))
    seuil = F.greatest(F.lit(float(divergence_min)), F.col("med") + nb_ecarts * 1.4826 * F.col("mad"))
    return (avec_med.join(mad, CLE_TERMINAL).filter(F.col("divergence") >= seuil)
            .select(CLE_TERMINAL, "date", F.col("divergence").alias("valeur")))


@regle("12", "Forme horaire inhabituelle")
def regle_profil_horaire(donnees, seuils):
    """Répartition des retraits dans la journée très différente de l'habitude du terminal."""
    return journees_divergentes(donnees_divergences(donnees, "horaires"), seuils["profil_volume_min"],
                                seuils["profil_ecarts_robustes"], seuils["profil_divergence_min"])


@regle("13", "Mélange de réseaux inhabituel")
def regle_melange_reseaux(donnees, seuils):
    """Part des réseaux de cartes du jour très différente de l'habitude du terminal."""
    return journees_divergentes(donnees_divergences(donnees, "reseaux"), seuils["reseaux_volume_min"],
                                seuils["reseaux_ecarts_robustes"], seuils["reseaux_divergence_min"])


# ------------------------------------------------------------------ comparaison aux pairs
def ratios_habitude(journees, habitude_min):
    """Retraits du jour / moyenne des 8 mêmes jours de semaine précédents."""
    meme_jour = fenetre_meme_jour_semaine()
    return (journees.withColumn("moy8", F.avg("retraits").over(meme_jour))
            .withColumn("n8", F.count("retraits").over(meme_jour))
            .filter((F.col("n8") >= 4) & (F.col("moy8") >= habitude_min))
            .withColumn("ratio", F.col("retraits") / F.col("moy8")))


@regle("14", "Écart aux terminaux pairs")
def regle_ecart_pairs(donnees, seuils):
    """Le terminal décroche (ou s'emballe) alors que les terminaux de son groupe restent normaux ce jour-là."""
    groupes = donnees.groupes_pairs()
    if groupes is None:
        return None
    ratios = ratios_habitude(donnees.journees, seuils["pairs_habitude_min"]).join(groupes, CLE_TERMINAL)
    pairs = ratios.groupBy("groupe", "date").agg(centile("ratio", 0.5).alias("ratio_pairs"),
                                                 F.count("*").alias("nb_pairs"))
    decroche = (F.col("ratio") <= seuils["pairs_ratio_bas"]) & (F.col("ratio_pairs") >= seuils["pairs_ratio_normal"])
    emballe = ((F.col("ratio") >= seuils["pairs_ratio_haut"]) &
               (F.col("ratio_pairs") <= seuils["pairs_ratio_haut_pairs"]))
    return (ratios.join(pairs, ["groupe", "date"])
            .filter((F.col("nb_pairs") >= seuils["pairs_nb_min"]) & (decroche | emballe))
            .select(CLE_TERMINAL, "date", F.col("ratio").alias("valeur")))


@regle("15", "Dérive lente")
def regle_derive_lente(donnees, seuils):
    """Les 4 dernières semaines tombent sous 60 % des 8 précédentes, sans arrêt net, alors que les pairs tiennent."""
    semaine = F.date_trunc("week", F.col("date").cast("timestamp")).cast("date")
    completes = (donnees.journees.select("date").distinct().groupBy(semaine.alias("semaine")).count()
                 .filter(F.col("count") == 7).select("semaine"))
    hebdo = (donnees.journees.groupBy(CLE_TERMINAL, semaine.alias("semaine")).agg(F.sum("retraits").alias("ret"))
             .join(completes, "semaine"))
    recentes = Window.partitionBy(CLE_TERMINAL).orderBy("semaine").rowsBetween(-3, 0)
    reference = Window.partitionBy(CLE_TERMINAL).orderBy("semaine").rowsBetween(-11, -4)
    hebdo = (hebdo.withColumn("moy_rec", F.avg("ret").over(recentes))
             .withColumn("min_rec", F.min("ret").over(recentes))
             .withColumn("moy_ref", F.avg("ret").over(reference))
             .withColumn("n_ref", F.count("ret").over(reference))
             .filter((F.col("n_ref") >= 8) & (F.col("moy_ref") >= seuils["derive_reference_min"]))
             .withColumn("ratio", F.col("moy_rec") / F.col("moy_ref")))
    candidats = hebdo.filter((F.col("ratio") <= seuils["derive_ratio"]) &
                             (F.col("min_rec") / F.col("moy_ref") >= seuils["derive_semaine_min"]))
    groupes = donnees.groupes_pairs()
    if groupes is not None:
        pairs = (hebdo.join(groupes, CLE_TERMINAL).groupBy("groupe", "semaine")
                 .agg(centile("ratio", 0.5).alias("ratio_pairs")))
        candidats = (candidats.join(groupes, CLE_TERMINAL).join(pairs, ["groupe", "semaine"])
                     .filter(F.col("ratio_pairs") >= seuils["derive_pairs_min"]))
    premiere = Window.partitionBy(CLE_TERMINAL).orderBy("semaine")
    return (candidats.withColumn("rang", F.row_number().over(premiere)).filter(F.col("rang") == 1)
            .select(CLE_TERMINAL, F.col("semaine").alias("date"), F.col("ratio").alias("valeur")))


@regle("16", "Trou horaire récurrent")
def regle_trou_horaire(donnees, seuils):
    """Une heure habituellement active reste vide plus d'un jour sur deux dans le mois.

    L'attendu de l'heure ce mois-là = rythme annuel de l'heure x (activité du mois / activité moyenne de l'année),
    pour ne pas signaler la basse saison d'un terminal saisonnier.
    """
    grille = donnees.grille_horaire().withColumn("mois", F.trunc("date", "month"))
    taux = grille.groupBy(CLE_TERMINAL, "heure").agg(F.avg("n").alias("taux_annuel"))
    niveau_mois = grille.groupBy(CLE_TERMINAL, "mois").agg(F.avg("n").alias("niveau_mois"))
    niveau_annee = grille.groupBy(CLE_TERMINAL).agg(F.avg("n").alias("niveau_annee"))
    mensuel = (grille.groupBy(CLE_TERMINAL, "heure", "mois")
               .agg(F.count("*").alias("jours"), F.sum((F.col("n") == 0).cast("int")).alias("jours_vides"))
               .join(taux, [CLE_TERMINAL, "heure"]).join(niveau_mois, [CLE_TERMINAL, "mois"]).join(niveau_annee, CLE_TERMINAL)
               .withColumn("attendu", F.col("taux_annuel") * F.col("niveau_mois") / F.col("niveau_annee"))
               .withColumn("part_vide", F.col("jours_vides") / F.col("jours")))
    return (mensuel.filter((F.col("jours") >= seuils["trou_jours_min"]) &
                           (F.col("part_vide") >= seuils["trou_part_jours_vides"]) &
                           (F.col("attendu") >= seuils["trou_taux_horaire_min"]))
            .groupBy(CLE_TERMINAL, "mois").agg(F.max("part_vide").alias("valeur"))
            .select(CLE_TERMINAL, F.col("mois").alias("date"), "valeur"))


# ------------------------------------------------------------------ combinaisons de petits écarts
def donnees_divergences(donnees, nature):
    """Divergences horaires ou réseaux, calculées une seule fois et partagées entre les règles."""
    calculs = {"horaires": divergences_horaires, "reseaux": divergences_reseaux}
    return donnees.memoriser("divergences_" + nature, lambda: calculs[nature](donnees.retraits))


def ecarts_divergence(divergences, nom_colonne, dispersion_min=0.01):
    """Écart robuste de la divergence de chaque journée à la médiane du terminal : (div - médiane) / (1,4826 MAD)."""
    mediane = divergences.groupBy(CLE_TERMINAL).agg(centile("divergence", 0.5).alias("med"))
    avec_med = divergences.join(mediane, CLE_TERMINAL).withColumn("dev", F.abs(F.col("divergence") - F.col("med")))
    mad = avec_med.groupBy(CLE_TERMINAL).agg(centile("dev", 0.5).alias("mad"))
    echelle = F.greatest(1.4826 * F.col("mad"), F.lit(dispersion_min))
    return (avec_med.join(mad, CLE_TERMINAL)
            .select(CLE_TERMINAL, "date", ((F.col("divergence") - F.col("med")) / echelle).alias(nom_colonne)))


def caracteristiques_journalieres(donnees):
    """Écarts robustes de chaque journée terminal à son habitude (8 mêmes jours de semaine), en pandas.

    Colonnes z_<indicateur> pour INDICATEURS_MULTIVARIES, plus les divergences horaire et réseaux centrées.
    """
    meme_jour = fenetre_meme_jour_semaine()
    rafale = donnees.transactions.groupBy(CLE_TERMINAL, "date").agg(F.max("nb_ope_5min").alias("rafale"))
    table = (donnees.journees.join(rafale, [CLE_TERMINAL, "date"], "left").fillna(0, subset=["rafale"])
             .withColumn("montant_moyen", F.col("montant") / F.greatest(F.col("retraits"), F.lit(1)))
             .withColumn("n8", F.count("retraits").over(meme_jour)))
    colonnes_z = []
    for indicateur, plancher in INDICATEURS_MULTIVARIES.items():
        moyenne = F.avg(indicateur).over(meme_jour)
        dispersion = F.coalesce(F.stddev(indicateur).over(meme_jour), F.lit(0.0))
        minimum = (F.sqrt(F.greatest(moyenne, F.lit(1.0))) if plancher == "racine"
                   else F.greatest(plancher * moyenne, F.lit(1.0)))
        table = table.withColumn("z_" + indicateur, (F.col(indicateur) - moyenne) / F.greatest(dispersion, minimum))
        colonnes_z.append("z_" + indicateur)
    for nom, divergences in (("profil", donnees_divergences(donnees, "horaires")),
                             ("reseaux", donnees_divergences(donnees, "reseaux"))):
        table = table.join(ecarts_divergence(divergences, "z_" + nom), [CLE_TERMINAL, "date"], "left")
        colonnes_z.append("z_" + nom)
    resultat = en_pandas(table.filter(F.col("n8") >= 4).select(CLE_TERMINAL, "date", *colonnes_z), max_lignes=20000000)
    resultat[colonnes_z] = resultat[colonnes_z].fillna(0.0).clip(-10, 10)
    return resultat


def scores_multivaries(donnees, seuils):
    """Score d'atypicité de chaque journée terminal (Isolation Forest) et les 3 indicateurs les plus en cause."""
    try:
        from sklearn.ensemble import IsolationForest
    except ImportError:
        print("scikit-learn indisponible dans ce kernel : règle 17 ignorée.")
        return None
    table = caracteristiques_journalieres(donnees)
    colonnes = [c for c in table.columns if c.startswith("z_")]
    echantillon = table.sample(min(len(table), seuils["multivarie_echantillon"]), random_state=0)
    try:
        modele = IsolationForest(n_estimators=200, contamination="auto", behaviour="new", random_state=0)
    except TypeError:
        modele = IsolationForest(n_estimators=200, contamination="auto", random_state=0)
    modele.fit(echantillon[colonnes].values)
    table["score"] = -modele.score_samples(table[colonnes].values)
    valeurs = np.abs(table[colonnes].values)
    ordre = np.argsort(-valeurs, axis=1)[:, :3]
    noms = np.array([c[2:] for c in colonnes])
    table["explication"] = [", ".join("{} ({:+.1f})".format(noms[j], table[colonnes[j]].iat[i]) for j in ligne)
                            for i, ligne in enumerate(ordre)]
    return table


@regle("17", "Combinaison de petits écarts")
def regle_multivariee(donnees, seuils):
    """Journées dont la combinaison d'écarts est la plus rare, parmi celles qu'aucune autre règle n'a signalées."""
    scores = donnees.memoriser("scores_multivaries", lambda: scores_multivaries(donnees, seuils))
    if scores is None:
        return None
    deja_vues = [(str(g), d) in donnees.journees_signalees
                 for g, d in zip(scores[CLE_TERMINAL], pd.to_datetime(scores["date"]).dt.date)]
    candidates = scores[~pd.Series(deja_vues, index=scores.index)]
    retenues = candidates.nlargest(max(1, int(len(scores) * seuils["multivarie_part"])), "score")
    spark = SparkSession.builder.getOrCreate()
    return spark.createDataFrame(pd.DataFrame({CLE_TERMINAL: retenues[CLE_TERMINAL].astype(str).values,
                                               "date": pd.to_datetime(retenues["date"]).dt.date.values,
                                               "valeur": retenues["score"].astype(float).values}))
