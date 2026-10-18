"""Du catalogue d'anomalies au livrable métier : score de risque par terminal, niveau, raisons en clair,
regroupement des incidents de zone, jours particuliers et mesure de la qualité à partir des retours du métier.
"""
import numpy as np
import pandas as pd

from .outils import CLE_TERMINAL

# Gravité de chaque anomalie (1 = à surveiller, 2 = à traiter, 3 = urgent) ; modifiable via `gravites=`.
GRAVITES = {"01": 3, "02": 3, "03": 3, "04": 3, "05": 2, "06": 2, "07": 2, "08": 2, "09": 1, "10": 2, "11": 2,
            "12": 1, "13": 1, "14": 2, "15": 1, "16": 2, "17": 1, "18": 3, "19": 3, "20": 3, "21": 2, "22": 2,
            "23": 2, "24": 1, "25": 3, "26": 1}

# Phrase lisible de chaque anomalie ; {v} est la valeur qui a déclenché l'alerte.
PHRASES = {
    "01": "aucun retrait pendant {v:.0f} h alors que le terminal est habituellement actif",
    "02": "aucune opération de la journée (environ {v:.0f} retraits attendus)",
    "03": "rafale de {v:.0f} opérations en 10 minutes",
    "04": "{v:.0f} retraits du même montant en 5 minutes",
    "05": "{v:.0f} retraits inaboutis consécutifs",
    "06": "{v:.0f} cartes capturées (hors réseau interne) en moins d'une heure",
    "07": "{v:.0f} retraits de cartes étrangères rares en une heure",
    "08": "{v:.0f} retraits entre 0 h et 5 h sur un terminal qui n'en fait presque jamais",
    "09": "{v:.0f} retrait(s) avec une carte expirée",
    "10": "retraits multipliés par {v:.1f} par rapport à l'habitude",
    "11": "montant moyen multiplié par {v:.1f}",
    "12": "répartition horaire de la journée inhabituelle (divergence {v:.2f})",
    "13": "mélange des réseaux de cartes inhabituel (divergence {v:.2f})",
    "14": "activité à {v:.0%} de l'habitude alors que les terminaux comparables sont normaux",
    "15": "baisse progressive : activité des 4 dernières semaines à {v:.0%} des 8 précédentes",
    "16": "une heure habituellement active reste vide {v:.0%} des jours du mois",
    "17": "combinaison inhabituelle de plusieurs petits écarts (score {v:.2f})",
    "18": "une coupure n'est plus délivrée (cassette vide ou défaillante ?) sur {v:.0f} retraits",
    "19": "incident de zone : {v:.0f} terminal de la zone muets à la même heure",
    "20": "activité suspecte simultanée sur {v:.0f} terminal de la zone (attaque coordonnée ?)",
    "21": "{v:.0f} captures d'un même motif (carte volée, code faux, incident de lecture...), improbable",
    "22": "{v:.0%} d'inaboutis sur un seul réseau de cartes",
    "23": "le même délai entre deux retraits revient {v:.0f} fois en 30 min, improbable (script ?)",
    "24": "{v:.0f} retraits à une heure où le terminal n'opère presque jamais",
    "25": "même carte sur plusieurs terminaux à une vitesse impossible ({v:.0f} km/h)",
    "26": "retraits multipliés par {v:.1f} par rapport à l'année précédente",
}
SYMPTOMES_DE_ZONE = ("01", "02", "10", "12", "14")   # absorbés par un incident de zone (19) le même jour


def jours_particuliers(dates, autres_jours=()):
    """Jours fériés français (si la librairie holidays est disponible) et jours indiqués dans `autres_jours`."""
    particuliers = set(pd.to_datetime(list(autres_jours)).date)
    try:
        import holidays
        annees = sorted({d.year for d in dates})
        particuliers |= set(holidays.France(years=annees).keys())
    except ImportError:
        pass
    return particuliers


def phrase(type_anomalie, valeur):
    """Raison lisible d'une alerte."""
    modele = PHRASES.get(str(type_anomalie)[:2])
    try:
        return modele.format(v=valeur) if modele else str(type_anomalie)
    except (ValueError, TypeError):
        return str(type_anomalie)


def score_de_risque(evenements, date_analyse=None, fenetre_jours=28, gravites=None, autres_jours_particuliers=(),
                    seuils_niveaux=(3, 6)):
    """Une ligne par terminal alerté à `date_analyse` (par défaut le dernier jour) : score, niveau et raisons.

    score = somme des gravités des anomalies du jour x (1 + 0,1 x jours alertés sur `fenetre_jours`)
            x 0,5 si jour férié ou particulier.
    Les symptômes (silence, volume, forme horaire, écart aux pairs) d'un terminal pris dans un incident de zone
    sont regroupés dans l'alerte de zone. Niveaux : Modéré, Élevé (>= seuils_niveaux[0]), Critique (>= [1]).
    """
    gravites = dict(GRAVITES, **(gravites or {}))
    table = evenements.copy()
    table["date"] = pd.to_datetime(table["date"])
    table["code"] = table["type"].str[:2]
    date_analyse = pd.Timestamp(date_analyse) if date_analyse is not None else table["date"].max()
    du_jour = table[table["date"] == date_analyse].copy()
    if du_jour.empty:
        return pd.DataFrame()
    en_zone = set(du_jour.loc[du_jour["code"] == "19", CLE_TERMINAL])
    absorbe = du_jour[CLE_TERMINAL].isin(en_zone) & du_jour["code"].isin(SYMPTOMES_DE_ZONE)
    du_jour = du_jour[~absorbe]
    du_jour["gravite"] = du_jour["code"].map(gravites).fillna(1)
    du_jour["raison"] = [phrase(t, v) for t, v in zip(du_jour["type"], du_jour["valeur"])]
    debut = date_analyse - pd.Timedelta(days=fenetre_jours)
    recents = table[(table["date"] > debut) & (table["date"] <= date_analyse)]
    colonne_recurrence = "jours_alertes_{}j".format(fenetre_jours)
    recurrence = recents.groupby(CLE_TERMINAL)["date"].nunique().rename(colonne_recurrence)
    particulier = date_analyse.date() in jours_particuliers([date_analyse], autres_jours_particuliers)
    alertes = du_jour.groupby(CLE_TERMINAL).agg(
        gravite_totale=("gravite", "sum"), gravite_max=("gravite", "max"),
        nb_anomalies=("type", "nunique"),
        anomalies=("type", lambda types: ", ".join(sorted(set(types)))),
        raisons=("raison", lambda raisons: " ; ".join(raisons))).join(recurrence)
    alertes["score"] = (alertes["gravite_totale"] * (1 + 0.1 * alertes[colonne_recurrence])
                        * (0.5 if particulier else 1.0)).round(2)
    bas, haut = seuils_niveaux
    alertes["niveau"] = np.select([alertes["score"] >= haut, alertes["score"] >= bas], ["Critique", "Élevé"],
                                  "Modéré")
    alertes["date"] = date_analyse.date()
    alertes["jour_particulier"] = particulier
    alertes["avis_metier"] = ""   # à remplir par le métier : « vraie anomalie » ou « fausse alerte »
    return alertes.sort_values("score", ascending=False).reset_index()


def tableau_metier(alertes, par_terminal, colonnes_infos=("ville", "code_postal", "libelle_site")):
    """Tableau final pour l'Excel J-3 et Qlik : informations du terminal + niveau, score, raisons, avis_metier."""
    infos = [c for c in colonnes_infos if c in par_terminal.columns]
    colonnes = [CLE_TERMINAL, "date", "niveau", "score", "nb_anomalies", "raisons", "anomalies",
                alertes.columns[alertes.columns.str.startswith("jours_alertes")][0], "jour_particulier", "avis_metier"]
    return alertes[colonnes].merge(par_terminal[[CLE_TERMINAL] + infos], on=CLE_TERMINAL, how="left")[
        colonnes[:2] + infos + colonnes[2:]]


def precision_par_regle(evenements, retours):
    """Précision de chaque règle d'après les retours du métier.

    `retours` : DataFrame (num_automate, date, avis_metier) avec avis_metier = « vraie anomalie » ou
    « fausse alerte ». Renvoie, par type d'anomalie, le nombre d'alertes jugées et la part de vraies anomalies.
    """
    juges = retours.dropna(subset=["avis_metier"]).copy()
    juges = juges[juges["avis_metier"].astype(str).str.strip() != ""]
    juges["date"] = pd.to_datetime(juges["date"])
    juges["vraie"] = juges["avis_metier"].astype(str).str.lower().str.startswith("vrai")
    table = evenements.assign(date=pd.to_datetime(evenements["date"])).merge(
        juges[[CLE_TERMINAL, "date", "vraie"]], on=[CLE_TERMINAL, "date"])
    return (table.groupby("type")["vraie"].agg(alertes_jugees="size", precision="mean")
            .sort_values("precision"))


def selection_quotidienne(alertes, budget=30, niveaux=("Critique", "Élevé")):
    """Alertes réellement transmises au métier : niveaux retenus, puis les `budget` meilleurs scores.

    Le catalogue peut repérer beaucoup de journées atypiques ; le métier ne peut en traiter qu'une petite
    partie chaque jour. On ne transmet donc que les plus graves, dans la limite de sa capacité de traitement.
    """
    retenues = alertes[alertes["niveau"].isin(niveaux)] if niveaux else alertes
    return retenues.sort_values("score", ascending=False).head(budget)
