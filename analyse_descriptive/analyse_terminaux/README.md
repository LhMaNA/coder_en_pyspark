# analyse_terminaux

Librairie d'analyse descriptive et de détection d'anomalies des retraits terminal, au grain de la transaction.
Compatible Python 3.6, Spark 2.3, pandas 1.1, scikit-learn 0.21 (et versions plus récentes).

## Organisation

| Module | Rôle |
|---|---|
| `configuration.py` | **toutes** les valeurs modifiables : noms de colonnes, codes réseaux, options, seuils |
| `outils.py` | petits outils Spark / pandas (centile, fenêtres « 8 mêmes jours de semaine », conversions...) |
| `preparation.py` | lecture, correspondance des colonnes, typage, enrichissement des transactions, vue terminal x jour |
| `indicateurs.py` | calculs descriptifs (qualité, volumes, profils, parc, montants, silences...) |
| `anomalies.py` | registre des règles, règles directes 01 à 11, détection et synthèses |
| `anomalies_cachees.py` | règles 12 à 17 : forme horaire, mélange de réseaux, pairs, dérive lente, trou horaire, multivarié |
| `graphiques.py` | graphiques uniquement (aucun calcul) |
| `tests/` | tests automatiques (`python -m unittest discover -s analyse_terminaux/tests -t .`) |

## Installation dans Dataiku

1. Dans le projet : menu **</> → Libraries**.
2. Dans `lib/python`, créer un dossier `analyse_terminaux` et y déposer les fichiers `.py` (et le dossier `tests`).
3. Dans un notebook ou une recette du projet : `from analyse_terminaux import anomalies, preparation, ...`
   (le dossier `lib/python` est automatiquement visible).

## Adapter à une autre table ou à d'autres règles métier

Les valeurs par défaut de `configuration.py` sont **fictives** (format de la table de test). Ne modifier que la configuration, de préférence dans la cellule « Configuration » du notebook :

```python
from analyse_terminaux.configuration import configuration
conf = configuration(
    colonnes={"num_automate": "id_terminal"},                           # nom de la colonne dans la table
    metier={"codes_reseau": {"10": "Reseau national", "20": "Reseau international 1"}},   # codes réseaux
    seuils={"rafale_min_10min": 15},                      # seuils des anomalies
    options={"groupe_pairs": "ville"},                    # terminal comparables entre eux
)
```

## Ajouter une anomalie

Écrire une fonction dans `anomalies.py` (ou `anomalies_cachees.py`) décorée par `@regle` :

```python
@regle("18", "Mon anomalie")
def regle_mon_anomalie(donnees, seuils):
    """Ce que la règle détecte."""
    return (donnees.journees.filter(F.col("retraits") > seuils["mon_seuil"])
            .select("num_automate", "date", F.col("retraits").alias("valeur")))
```

Ajouter `"mon_seuil"` dans `SEUILS` (configuration.py). La règle est alors appliquée, résumée et cartographiée
automatiquement par le notebook.
