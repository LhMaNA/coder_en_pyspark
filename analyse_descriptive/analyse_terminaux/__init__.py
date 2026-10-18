"""Analyse descriptive et détection d'anomalies des retraits terminal, au grain de la transaction.

Modules :
    configuration      valeurs par défaut (colonnes, codes métier, options, seuils) et surcharges
    outils             petits outils Spark / pandas
    preparation        lecture, correspondance des colonnes, typage, enrichissement des transactions
    indicateurs        calculs descriptifs (qualité, volumes, profils, parc, silences...)
    anomalies          registre des règles, règles directes 01 à 11, détection et synthèses
    anomalies_cachees  règles 12 à 17 (forme horaire, réseaux, pairs, dérive, trous horaires, multivarié)
    anomalies_avancees règles 18 à 26 (cassettes, zone, attaque coordonnée, captures, réseaux, rythme...)
    priorisation       score de risque par terminal, niveau, raisons en clair, mesure de la qualité
    analyses_metier    saturation, besoin en billets, maintenance, fiabilité, pannes, usage vs pairs
    graphiques         graphiques (aucun calcul)

Compatible Python 3.6 / Spark 2.3 / pandas 1.1 / scikit-learn 0.21.
"""
from . import (analyses_metier, anomalies, anomalies_avancees, anomalies_cachees, configuration,  # noqa: F401
               graphiques, indicateurs, outils, preparation, priorisation)

__all__ = ["analyses_metier", "anomalies", "anomalies_avancees", "anomalies_cachees", "configuration",
           "graphiques", "indicateurs", "outils", "preparation", "priorisation"]
__version__ = "1.0.0"
