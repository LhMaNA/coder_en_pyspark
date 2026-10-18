"""Calculs descriptifs : chaque fonction renvoie un tableau pandas (déjà agrégé) ou une table Spark réduite."""
import numpy as np
import pandas as pd
from pyspark.sql import SparkSession, Window
from pyspark.sql import functions as F

from .outils import CLE_TERMINAL, centile, en_nombre, en_pandas, fenetre_jours_precedents, persister, somme_si

JOURS_FR = {2: "lun", 3: "mar", 4: "mer", 5: "jeu", 6: "ven", 7: "sam", 1: "dim"}   # F.dayofweek
ORDRE_JOURS = ["lun", "mar", "mer", "jeu", "ven", "sam", "dim"]


# ------------------------------------------------------------------ qualité de la donnée brute
def qualite_colonnes(brut, nb_lignes):
    """Valeurs nulles et chaînes vides, colonne par colonne (une seule passe sur la table)."""
    mesures = []
    for colonne in brut.columns:
        mesures.append(F.sum(F.col(colonne).isNull().cast("int")).alias(colonne + "__null"))
        mesures.append(F.sum((F.trim(F.col(colonne).cast("string")) == "").cast("int")).alias(colonne + "__vide"))
    comptes = brut.agg(*mesures).collect()[0].asDict()
    qualite = pd.DataFrame([{"colonne": c, "nb_null": comptes[c + "__null"], "nb_vide": comptes[c + "__vide"]}
                            for c in brut.columns])
    qualite["pct_null"] = (100 * qualite["nb_null"] / nb_lignes).round(3)
    qualite["pct_vide"] = (100 * qualite["nb_vide"] / nb_lignes).round(3)
    return qualite.sort_values("pct_null", ascending=False)


def valeurs_prises(brut, colonne, nb_lignes, nb_max=40):
    """Valeurs les plus fréquentes d'une colonne, avec leur part."""
    valeurs = en_pandas(brut.groupBy(colonne).count().orderBy(F.desc("count")).limit(nb_max))
    valeurs["pct"] = (100 * valeurs["count"] / nb_lignes).round(3)
    return valeurs


def controle_formats(brut, date_op, heure_txt):
    """Dates, heures et montants invalides ; bornes des dates ; montant médian brut."""
    return brut.select(date_op.alias("date"), heure_txt.substr(1, 2).cast("int").alias("hh"),
                       heure_txt.substr(3, 2).cast("int").alias("mi"),
                       en_nombre("montant_ope").alias("montant_brut")).agg(
        F.sum(F.col("date").isNull().cast("int")).alias("dates_invalides"),
        F.min("date").alias("date_min"),
        F.max("date").alias("date_max"),
        F.sum(((F.col("hh") > 23) | F.col("hh").isNull()).cast("int")).alias("heures_invalides"),
        F.sum(((F.col("mi") > 59) | F.col("mi").isNull()).cast("int")).alias("minutes_invalides"),
        F.sum(F.col("montant_brut").isNull().cast("int")).alias("montants_non_numeriques"),
        F.sum((F.col("montant_brut") <= 0).cast("int")).alias("montants_nuls_ou_negatifs"),
        centile("montant_brut", 0.5).alias("montant_median_brut")).collect()[0].asDict()


# ------------------------------------------------------------------ volumes, rythmes, profils
def indicateurs_par_reseau(ops):
    """Retraits, montants, inaboutis et captures par réseau, comptés transaction par transaction."""
    est_retrait = F.col("est_retrait") == 1
    table = en_pandas(ops.groupBy("groupe_reseau", "cat_reseau").agg(
        F.sum("est_retrait").alias("retraits"),
        somme_si(F.col("type_op") == "RETRAIT_INTERNE").alias("retraits_interne"),
        somme_si(F.col("type_op") == "RETRAIT_EXTERNE").alias("retraits_externe"),
        somme_si(est_retrait, F.col("montant")).alias("montant"),
        F.sum("inabouti").alias("inaboutis"),
        F.sum("est_capture").alias("captures"),
        F.countDistinct(CLE_TERMINAL).alias("terminal")).orderBy(F.desc("retraits")))
    retraits = table["retraits"].replace(0, np.nan)
    table["pct_retraits"] = (100 * table["retraits"] / table["retraits"].sum()).round(3)
    table["montant_moyen"] = (table["montant"] / retraits).round(2)
    table["taux_inaboutis_pct"] = (100 * table["inaboutis"] / retraits).round(3)
    return table


def volumes_par_jour(ops):
    """Retraits, captures, inaboutis et terminal actifs par jour, avec jours fériés et écart au même jour de semaine."""
    jour = en_pandas(ops.groupBy("date").agg(
        F.sum("est_retrait").alias("retraits"), F.sum("est_capture").alias("captures"),
        F.sum("inabouti").alias("inaboutis"), F.countDistinct(CLE_TERMINAL).alias("terminal_actifs")))
    jour["date"] = pd.to_datetime(jour["date"])
    jour = jour.sort_values("date").set_index("date")
    try:
        import holidays
        feries = holidays.France(years=sorted(jour.index.year.unique()))
        jour["ferie"] = [d.date() in feries for d in jour.index]
    except ImportError:
        jour["ferie"] = False
    jour["jour_semaine"] = jour.index.dayofweek.map(dict(enumerate(ORDRE_JOURS)))
    habitude = jour.groupby("jour_semaine")["retraits"].transform(
        lambda serie: serie.rolling(9, center=True, min_periods=3).median())
    jour["ratio_vs_meme_jour"] = (jour["retraits"] / habitude).round(2)
    return jour


def croisement_jour_heure(retraits, nb_jours_par_semaine, valeur=None):
    """Matrice jour de semaine x heure : retraits moyens par jour, ou moyenne de la colonne `valeur`."""
    if valeur:
        table = en_pandas(retraits.groupBy("jour_semaine", "heure").agg(F.avg(valeur).alias("v")))
    else:
        table = en_pandas(retraits.groupBy("jour_semaine", "heure").count())
    table["jour"] = table["jour_semaine"].map(JOURS_FR)
    if not valeur:
        table["v"] = table["count"] / table["jour"].map(nb_jours_par_semaine)
    return table.pivot(index="jour", columns="heure", values="v").reindex(ORDRE_JOURS)


def profils_normalises(retraits, colonne, modalites, min_retraits=500):
    """Part des retraits de chaque terminal par modalité de `colonne` (terminal d'au moins `min_retraits` retraits)."""
    comptes = en_pandas(retraits.groupBy(CLE_TERMINAL, colonne).count())
    if colonne == "jour_semaine":
        comptes[colonne] = comptes[colonne].map(JOURS_FR)
    profils = comptes.pivot(index=CLE_TERMINAL, columns=colonne, values="count").reindex(columns=modalites).fillna(0)
    profils = profils[profils.sum(axis=1) >= min_retraits]
    return profils.div(profils.sum(axis=1), axis=0)


def carte_parc(journees, max_terminal=3000):
    """Matrice terminal x jour : log2(retraits / médiane du terminal pour ce jour de semaine), jours sans opération à 0."""
    volume = journees.groupby(CLE_TERMINAL)["retraits"].median().sort_values(ascending=False)
    terminal_retenus = volume.index[:max_terminal]
    jours = pd.date_range(journees["date"].min(), journees["date"].max())
    matrice = (journees[journees[CLE_TERMINAL].isin(terminal_retenus)]
               .pivot(index=CLE_TERMINAL, columns="date", values="retraits").reindex(index=terminal_retenus, columns=jours))
    vie = journees.groupby(CLE_TERMINAL)["date"].agg(["min", "max"]).reindex(terminal_retenus)
    dans_vie = np.array([(jours >= debut) & (jours <= fin) for debut, fin in zip(vie["min"], vie["max"])])
    matrice = matrice.where(~(matrice.isna() & dans_vie), 0)
    habitude = matrice.T.groupby(matrice.columns.dayofweek).transform("median").T
    return np.log2((matrice + 1) / (habitude + 1)).clip(-3, 3)


# ------------------------------------------------------------------ le parc de terminaux
def statistiques_par_terminal(ops):
    """Une ligne par terminal : durée de vie, volume, taux d'inaboutis, captures, cartes étrangères, nuit, montant."""
    est_retrait = F.col("est_retrait") == 1
    par_terminal = en_pandas(ops.groupBy(CLE_TERMINAL).agg(
        F.min("date").alias("premier_jour"), F.max("date").alias("dernier_jour"),
        F.countDistinct("date").alias("jours_actifs"),
        F.sum("est_retrait").alias("retraits"), F.sum("est_capture").alias("captures"),
        F.sum("est_capture_externe").alias("captures_externe"), F.sum("inabouti").alias("inaboutis"),
        somme_si(est_retrait, F.col("est_etranger")).alias("etrangers"),
        somme_si(est_retrait, F.col("est_nuit")).alias("retraits_nuit"),
        somme_si(est_retrait, F.col("montant")).alias("montant")), max_lignes=200000)
    for colonne in ("premier_jour", "dernier_jour"):
        par_terminal[colonne] = pd.to_datetime(par_terminal[colonne])
    retraits = par_terminal["retraits"].clip(lower=1)
    par_terminal["duree_jours"] = (par_terminal["dernier_jour"] - par_terminal["premier_jour"]).dt.days + 1
    par_terminal["taux_presence"] = par_terminal["jours_actifs"] / par_terminal["duree_jours"]
    par_terminal["retraits_par_jour_actif"] = par_terminal["retraits"] / par_terminal["jours_actifs"]
    par_terminal["taux_inaboutis_pct"] = 100 * par_terminal["inaboutis"] / retraits
    par_terminal["captures_pour_1000"] = 1000 * par_terminal["captures"] / retraits
    par_terminal["part_etrangers_pct"] = 100 * par_terminal["etrangers"] / retraits
    par_terminal["part_nuit_pct"] = 100 * par_terminal["retraits_nuit"] / retraits
    par_terminal["montant_moyen"] = par_terminal["montant"] / retraits
    return par_terminal


def filtrer_metropole(table, metropole):
    """Lignes dont les coordonnées sont en métropole."""
    return table[table["longitude"].between(*metropole["longitude"]) &
                 table["latitude"].between(*metropole["latitude"])]


def controles_geographiques(par_terminal, metropole):
    """Coordonnées absentes, nulles, hors métropole, multiples ou partagées."""
    lon, lat = par_terminal["longitude"], par_terminal["latitude"]
    en_metropole = filtrer_metropole(par_terminal, metropole)
    return pd.Series({
        "terminal sans coordonnées": int((lon.isna() | lat.isna()).sum()),
        "coordonnées à 0": int(((lon == 0) | (lat == 0)).sum()),
        "hors métropole (DOM-TOM ou erreur)": int(lon.notna().sum() - len(en_metropole)),
        "terminal avec plusieurs coordonnées": int((par_terminal["nb_coordonnees"] > 1).sum()),
        "coordonnées partagées par plusieurs terminaux": int(en_metropole.duplicated(["longitude", "latitude"],
                                                                               keep=False).sum()),
    }).to_frame("nb_TERMINAL")


# ------------------------------------------------------------------ montants, inaboutis, captures
def quantiles_montant(retraits, groupe=None, quantiles=(0.1, 0.25, 0.5, 0.75, 0.9)):
    """Quantiles du montant, globalement ou par `groupe` (une colonne par quantile)."""
    expression = centile("montant", "array({})".format(", ".join(str(q) for q in quantiles))).alias("q")
    if groupe is None:
        return pd.Series(retraits.select(expression).collect()[0]["q"], index=quantiles)
    table = en_pandas(retraits.groupBy(groupe).agg(expression).orderBy(groupe))
    return pd.DataFrame(table["q"].tolist(), index=table[groupe], columns=["p{:g}".format(100 * q) for q in quantiles])


def controles_montants(retraits):
    """Montants non multiples de 5 €, écarts avec les billets délivrés, retraits sans billet renseigné."""
    return retraits.agg(
        somme_si(F.round(F.col("montant") * 100) % 500 != 0).alias("non_multiples_de_5"),
        somme_si(F.abs(F.col("ecart_billets")) > 0.001).alias("ecart_avec_billets"),
        somme_si(F.col("montant_billets") == 0).alias("aucun_billet_renseigne")).collect()[0].asDict()


def taux_par(table, groupe, colonne):
    """Taux moyen (en %) de la colonne 0/1 `colonne` par `groupe`."""
    return en_pandas(table.groupBy(groupe).agg((100 * F.avg(colonne)).alias("taux"), F.count("*").alias("n"))
                     .orderBy(groupe))


def taux_captures(ops):
    """Captures interne et hors réseau interne, et leurs taux pour 1 000 retraits du même réseau."""
    comptes = ops.agg(F.sum("est_capture_interne").alias("captures_interne"),
                      F.sum("est_capture_externe").alias("captures_externe"),
                      somme_si(F.col("type_op") == "RETRAIT_INTERNE").alias("retraits_interne"),
                      somme_si(F.col("type_op") == "RETRAIT_EXTERNE").alias("retraits_externe")).collect()[0]
    return pd.DataFrame([
        {"reseau": "interne", "captures": comptes["captures_interne"],
         "pour_1000_retraits": 1000 * comptes["captures_interne"] / max(comptes["retraits_interne"], 1)},
        {"reseau": "hors réseau interne", "captures": comptes["captures_externe"],
         "pour_1000_retraits": 1000 * comptes["captures_externe"] / max(comptes["retraits_externe"], 1)}])


# ------------------------------------------------------------------ dynamique dans la journée
def grille_horaire(retraits_transactions, journees, heure_debut, heure_fin, actif_persistance=True):
    """Retraits par terminal, jour et heure (de `heure_debut` à `heure_fin`), heures vides comprises.

    Ajoute `taux_h`, le nombre moyen habituel de retraits du terminal à cette heure (semaine / week-end).
    """
    spark = SparkSession.builder.getOrCreate()
    heures = spark.range(heure_debut, heure_fin).select(F.col("id").cast("int").alias("heure"))
    comptes = retraits_transactions.groupBy(CLE_TERMINAL, "date", "heure").agg(F.count("*").alias("n"))
    grille = (journees.select(CLE_TERMINAL, "date").crossJoin(heures)
              .join(comptes, [CLE_TERMINAL, "date", "heure"], "left").fillna(0, subset=["n"])
              .withColumn("week_end", F.dayofweek("date").isin(1, 7).cast("int")))
    rythme = grille.groupBy(CLE_TERMINAL, "week_end", "heure").agg(F.avg("n").alias("taux_h"))
    return persister(grille.join(rythme, [CLE_TERMINAL, "week_end", "heure"]), actif_persistance)


def calculer_silences(grille, journees, jours_recents=28):
    """Pire silence de chaque journée terminal : heures consécutives sans retrait et probabilité de hasard.

    Le nombre attendu pendant le silence vient du rythme horaire du terminal, multiplié par :
    - son niveau récent (moyenne des `jours_recents` journées précédentes / moyenne de toute la période), ce
      qui suit la saison (station de ski l'été, littoral l'hiver) sans utiliser la journée elle-même ;
    - l'activité du jour hors silence, seulement à la baisse (journée creuse), jamais à la hausse : une hausse
      calculée sur les quelques heures restantes est trop instable pour les terminaux peu actifs.
    Probabilité = exp(-attendu) (loi de Poisson).
    """
    niveau = (journees.select(CLE_TERMINAL, "date", "retraits")
              .withColumn("recent", F.avg("retraits").over(fenetre_jours_precedents(jours_recents)))
              .withColumn("global", F.avg("retraits").over(Window.partitionBy(CLE_TERMINAL)))
              .select(CLE_TERMINAL, "date", F.coalesce(F.col("recent") / F.col("global"), F.lit(1.0)).alias("saison")))
    niveau_jour = grille.groupBy(CLE_TERMINAL, "date").agg(F.sum("n").alias("n_jour"), F.sum("taux_h").alias("taux_jour"))
    cumul = Window.partitionBy(CLE_TERMINAL, "date").orderBy("heure").rowsBetween(Window.unboundedPreceding, 0)
    blocs = (grille.withColumn("vide", (F.col("n") == 0).cast("int"))
             .withColumn("bloc", F.sum(1 - F.col("vide")).over(cumul))
             .filter(F.col("vide") == 1)
             .groupBy(CLE_TERMINAL, "date", "bloc")
             .agg(F.count("*").alias("silence_h"), F.min("heure").alias("debut_silence"),
                  F.sum("taux_h").alias("attendus_bruts"))
             .join(niveau_jour, [CLE_TERMINAL, "date"]).join(niveau, [CLE_TERMINAL, "date"]))
    hors_silence = F.col("saison") * (F.col("taux_jour") - F.col("attendus_bruts"))
    journee_creuse = F.when(hors_silence > 1, F.least(F.col("n_jour") / hors_silence, F.lit(1.0))).otherwise(1.0)
    pire = Window.partitionBy(CLE_TERMINAL, "date").orderBy(F.desc("retraits_attendus_pendant_silence"))
    return (blocs
            .withColumn("retraits_attendus_pendant_silence",
                        F.col("attendus_bruts") * F.col("saison") * journee_creuse)
            .withColumn("rang", F.row_number().over(pire)).filter(F.col("rang") == 1)
            .withColumn("proba_hasard", F.exp(-F.col("retraits_attendus_pendant_silence")))
            .join(journees.select(CLE_TERMINAL, "date", F.col("retraits").alias("retraits_jour")), [CLE_TERMINAL, "date"])
            .drop("rang", "bloc", "attendus_bruts", "saison"))


def tranches_delais(retraits_transactions):
    """Répartition des délais entre deux retraits successifs d'un même terminal."""
    bornes = [(10, "1. < 10 s"), (30, "2. 10-30 s"), (60, "3. 30-60 s"), (300, "4. 1-5 min"),
              (900, "5. 5-15 min"), (3600, "6. 15-60 min"), (10800, "7. 1-3 h"), (43200, "8. 3-12 h")]
    tranche = F.when(F.lit(False), F.lit(""))
    for borne, libelle in bornes:
        tranche = tranche.when(F.col("delai_precedente_s") < borne, libelle)
    table = en_pandas(retraits_transactions.filter(F.col("delai_precedente_s").isNotNull())
                      .groupBy(tranche.otherwise("9. >= 12 h").alias("delai")).count().orderBy("delai"))
    table["pct"] = (100 * table["count"] / table["count"].sum()).round(2)
    return table


def ecart_parc_jour_heure(retraits):
    """Matrice jour x heure du parc : log2(retraits / médiane des mêmes jour de semaine et heure)."""
    parc = en_pandas(retraits.groupBy("date", "heure").count())
    parc["date"] = pd.to_datetime(parc["date"])
    parc = parc.pivot(index="date", columns="heure", values="count").reindex(columns=range(24)).fillna(0).sort_index()
    habitude = parc.groupby(parc.index.dayofweek).transform("median")
    return np.log2((parc + 1) / (habitude + 1)).clip(-2, 2)


# ------------------------------------------------------------------ compléments pour les graphiques
def tranches_montants(retraits, pas=10, maximum=1500):
    """Nombre de retraits par tranche de `pas` euros (jusqu'à `maximum`)."""
    return en_pandas(retraits.filter(F.col("montant") <= maximum)
                     .groupBy((F.floor(F.col("montant") / pas) * pas).alias("tranche")).count().orderBy("tranche"))


def montants_frequents(retraits, nb_retraits, nb=25):
    """Montants les plus fréquents et leur part."""
    table = en_pandas(retraits.groupBy("montant").count().orderBy(F.desc("count")).limit(nb))
    table["pct"] = (100 * table["count"] / nb_retraits).round(2)
    return table


def ecarts_billets(retraits, nb=20):
    """Écarts (montant demandé - billets délivrés) les plus fréquents."""
    return en_pandas(retraits.filter(F.abs(F.col("ecart_billets")) > 0.001)
                     .groupBy(F.round("ecart_billets", 0).alias("ecart")).count()
                     .orderBy(F.desc("count")).limit(nb))


def repartition_reseaux(retraits, colonne_temps):
    """Part de chaque groupe de réseau par modalité de `colonne_temps` (mois, heure...), en %."""
    table = en_pandas(retraits.groupBy(colonne_temps, "groupe_reseau").count())
    table = table.pivot(index=colonne_temps, columns="groupe_reseau", values="count").fillna(0).sort_index()
    return 100 * table.div(table.sum(axis=1), axis=0)


def profils_reseaux(retraits, colonne_temps):
    """Profil de chaque réseau selon `colonne_temps` : part des retraits du réseau par modalité."""
    table = en_pandas(retraits.groupBy("groupe_reseau", colonne_temps).count())
    table = table.pivot(index=colonne_temps, columns="groupe_reseau", values="count").fillna(0)
    return table / table.sum()


def silences_debut_duree(silences_improbables, duree_max=15):
    """Matrice durée (h) x heure de début des silences improbables."""
    table = en_pandas(silences_improbables.groupBy(
        "debut_silence", F.least(F.col("silence_h"), F.lit(duree_max)).alias("duree")).count())
    if table.empty:
        return table
    return table.pivot(index="duree", columns="debut_silence", values="count").fillna(0).sort_index()


def delais_echelle_log(retraits_transactions):
    """Distribution des délais entre retraits successifs, par pas de 0,1 en log10(secondes)."""
    return en_pandas(retraits_transactions.filter(F.col("delai_precedente_s") > 0)
                     .groupBy(F.round(F.log10("delai_precedente_s"), 1).alias("log10_delai")).count()
                     .orderBy("log10_delai"))
