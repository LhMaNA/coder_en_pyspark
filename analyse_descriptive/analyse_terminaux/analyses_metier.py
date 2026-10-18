"""Ce que l'analyse apprend au métier, au-delà des alertes : saturation, besoin en billets, créneau de
maintenance, fiabilité et tendance, temps entre pannes, usage par rapport aux terminaux comparables.
"""
import numpy as np
import pandas as pd
from pyspark.sql import functions as F

from .outils import CLE_TERMINAL, centile, en_pandas

CODES_PANNE = ("01", "02", "05", "18", "19")       # silence, journée muette, inaboutis en série, cassette, zone
CODES_FIABILITE = ("01", "02", "05", "06", "18", "22")


def saturation_horaire(retraits, capacite_horaire=30):
    """Par terminal : retraits de l'heure la plus chargée (99e centile) et nombre d'heures à capacité.

    `capacite_horaire` : nombre de retraits qu'un terminal peut servir en une heure (environ 2 minutes par client).
    """
    par_heure = retraits.groupBy(CLE_TERMINAL, "date", "heure").agg(F.count("*").alias("n"))
    return en_pandas(par_heure.groupBy(CLE_TERMINAL).agg(
        centile("n", 0.99).alias("heure_chargee_p99"), F.max("n").alias("heure_max"),
        F.sum((F.col("n") >= capacite_horaire).cast("int")).alias("heures_a_capacite"),
        F.countDistinct("date").alias("jours")), max_lignes=200000).sort_values("heures_a_capacite", ascending=False)


def besoin_billets(ops):
    """Billets délivrés en moyenne par coupure (nb1-nb4), terminal et jour de semaine, et montant moyen délivré."""
    retraits = ops.filter(F.col("est_retrait") == 1)
    par_jour = retraits.groupBy(CLE_TERMINAL, "date", "jour_semaine").agg(
        F.sum("montant_billets").alias("montant_delivre"),
        *[F.sum("billets_nb{}".format(i)).alias("billets_nb{}".format(i)) for i in range(1, 5)])
    return en_pandas(par_jour.groupBy(CLE_TERMINAL, "jour_semaine").agg(
        F.avg("montant_delivre").alias("montant_moyen_delivre"),
        *[F.avg("billets_nb{}".format(i)).alias("billets_nb{}_par_jour".format(i)) for i in range(1, 5)]),
        max_lignes=2000000)


def creneau_maintenance(retraits, heure_debut=6, heure_fin=22):
    """Par terminal : l'heure de la plage [heure_debut, heure_fin[ la moins chargée en moyenne."""
    par_heure = en_pandas(retraits.filter(F.col("heure").between(heure_debut, heure_fin - 1))
                          .groupBy(CLE_TERMINAL, "heure").agg(F.count("*").alias("n")), max_lignes=2000000)
    jours = en_pandas(retraits.groupBy(CLE_TERMINAL).agg(F.countDistinct("date").alias("jours")), max_lignes=200000)
    table = (par_heure.pivot(index=CLE_TERMINAL, columns="heure", values="n")
             .reindex(columns=range(heure_debut, heure_fin)).fillna(0))
    table = table.div(jours.set_index(CLE_TERMINAL)["jours"].reindex(table.index), axis=0)
    return pd.DataFrame({"heure_la_plus_creuse": table.idxmin(axis=1),
                         "retraits_moyens_a_cette_heure": table.min(axis=1).round(2),
                         "heure_la_plus_chargee": table.idxmax(axis=1)})


def fiabilite(evenements, par_terminal, semaines_recentes=8):
    """Incidents (pannes, inaboutis, captures, cassettes) pour 1 000 retraits, et tendance récente.

    tendance = incidents par semaine sur les `semaines_recentes` dernières semaines / avant ; > 1 : se dégrade.
    """
    incidents = evenements[evenements["type"].str[:2].isin(CODES_FIABILITE)].copy()
    incidents["date"] = pd.to_datetime(incidents["date"])
    limite = incidents["date"].max() - pd.Timedelta(weeks=semaines_recentes)
    duree_avant = max((limite - incidents["date"].min()).days / 7, 1)
    table = incidents.groupby(CLE_TERMINAL).agg(incidents=("type", "size"),
                                           recents=("date", lambda d: (d > limite).sum()))
    table["tendance"] = ((table["recents"] / semaines_recentes) /
                         ((table["incidents"] - table["recents"]).clip(lower=1) / duree_avant)).round(2)
    table = table.join(par_terminal.set_index(CLE_TERMINAL)["retraits"])
    table["incidents_pour_1000_retraits"] = (1000 * table["incidents"] / table["retraits"].clip(lower=1)).round(2)
    return table.sort_values("incidents_pour_1000_retraits", ascending=False)


def temps_entre_pannes(evenements):
    """Par terminal touché : nombre de pannes (jours) et nombre moyen de jours entre deux pannes."""
    pannes = evenements[evenements["type"].str[:2].isin(CODES_PANNE)][[CLE_TERMINAL, "date"]].drop_duplicates()
    pannes = pannes.assign(date=pd.to_datetime(pannes["date"])).sort_values([CLE_TERMINAL, "date"])
    pannes["ecart"] = pannes.groupby(CLE_TERMINAL)["date"].diff().dt.days
    return (pannes.groupby(CLE_TERMINAL).agg(jours_de_panne=("date", "size"), jours_entre_pannes=("ecart", "mean"))
            .round(1).sort_values("jours_entre_pannes"))


def usage_par_rapport_aux_pairs(par_terminal, groupe="libelle_site", sous_utilise=0.3, sature=3.0):
    """Retraits par jour du terminal / médiane de son groupe : sous-utilisé (< 0,3) ou très sollicité (> 3)."""
    if groupe not in par_terminal.columns:
        return pd.DataFrame()
    table = par_terminal[[CLE_TERMINAL, groupe, "retraits_par_jour_actif"]].copy()
    table["mediane_groupe"] = table.groupby(groupe)["retraits_par_jour_actif"].transform("median")
    table["rapport_aux_pairs"] = (table["retraits_par_jour_actif"] / table["mediane_groupe"]).round(2)
    table["lecture"] = np.select([table["rapport_aux_pairs"] < sous_utilise, table["rapport_aux_pairs"] > sature],
                                 ["sous-utilisé : à déplacer ou à retirer ?", "très sollicité : à doubler ?"], "")
    return table[table["lecture"] != ""].sort_values("rapport_aux_pairs")
