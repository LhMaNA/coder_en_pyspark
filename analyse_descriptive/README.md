# Analyse descriptive de données de retraits

Analyse exploratoire d'un parc de terminaux de retrait, pour comprendre le comportement normal de chaque terminal et faire apparaître les comportements atypiques.

## Contenu

| Élément | Données | Outil |
|---|---|---|
| `analyse_retraits_spark.ipynb` | une ligne par opération (plusieurs centaines de millions de lignes) | PySpark |
| `analyse_terminaux/` | librairie utilisée par le notebook (configuration, préparation, indicateurs, règles, graphiques) | PySpark, pandas |
| `analyse_descriptive_terminal_jour.ipynb` | une ligne par terminal et par jour | pandas |

### Opérations (PySpark)
- analyse au grain de la transaction : chaque opération garde sa ligne et reçoit ses indicateurs (délai depuis l'opération précédente, opérations dans les 5 minutes, montant répété, captures récentes) ;
- qualité de la donnée brute, volumes, saisonnalité, profils horaires et hebdomadaires, géographie du parc ;
- montants, réseaux de cartes, retraits inaboutis, captures, validité des cartes ;
- 26 règles d'anomalies, chacune comparant le terminal à sa propre habitude :
  - directes (silence improbable, journée sans opération, rafale, montant répété, inaboutis, captures, cartes étrangères rares, nuit, carte expirée, volume, montant moyen) ;
  - cachées (forme horaire et mélange de réseaux par divergence de Jensen-Shannon, écart aux terminaux pairs, dérive lente, trou horaire récurrent, combinaison de petits écarts par Isolation Forest) ;
  - avancées (cassette vide, incident de zone, attaque coordonnée, motif de capture, inaboutis concentrés sur un réseau, rythme trop régulier, heure morte, même carte sur plusieurs terminaux, écart à l'année précédente) ;
- priorisation : score de risque (gravité x récurrence), regroupement des incidents de zone, budget quotidien d'alertes ;
- apports métier : saturation, besoin en billets, créneau de maintenance, fiabilité, usage par rapport aux pairs.

### Terminal-jour (pandas)
- qualité, cohérence et complétude du calendrier ;
- distributions, corrélations, saisonnalité ;
- habitude glissante de chaque terminal et écart robuste (médiane, MAD) ;
- carte du parc (terminaux x jours), profils de comportement, ruptures de niveau.

## Configuration
Toutes les valeurs du notebook sont **fictives** : nom du dataset, noms des colonnes, codes réseau, libellés des opérations et des motifs de capture. Elles se remplacent dans la cellule « 1. Configuration » ; le reste du code ne change pas. Les seuils des règles sont dans `analyse_terminaux/configuration.py`.

## Environnement
Python 3.6, pandas 1.1, PySpark 2.3, scikit-learn, matplotlib. Le notebook lit les données depuis un dataset Dataiku (ou une table Hive). La librairie se place dans les Libraries du projet (`lib/python/analyse_terminaux`).

Aucune donnée n'est incluse dans ce dépôt.
