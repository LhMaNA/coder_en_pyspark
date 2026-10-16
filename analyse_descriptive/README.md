# Analyse descriptive de données de retraits

Analyse exploratoire d'un parc de terminaux de retrait, sans modèle, pour comprendre le comportement normal de chaque terminal et faire apparaître les comportements atypiques avant toute détection automatique.

## Notebooks

| Notebook | Données | Outil |
|---|---|---|
| `analyse_descriptive_operations.ipynb` | une ligne par opération (plusieurs centaines de millions de lignes) | PySpark |
| `analyse_descriptive_terminal_jour.ipynb` | une ligne par terminal et par jour | pandas |

### Opérations (PySpark)
- qualité de la donnée brute : valeurs manquantes, formats, doublons ;
- volumes dans le temps, saisonnalité, rythme jour x heure ;
- montants, réseaux de cartes, retraits inaboutis, captures de carte ;
- dynamique à l'intérieur de la journée : délais entre opérations, rafales, silences improbables ;
- vues heure par heure du parc et d'un terminal.

### Terminal-jour (pandas)
- qualité, cohérence et complétude du calendrier ;
- distributions, corrélations, saisonnalité ;
- part de variance entre terminaux et au sein d'un terminal, régularité hebdomadaire ;
- habitude glissante de chaque terminal et écart robuste (médiane, MAD) ;
- carte du parc (terminaux x jours), profils de comportement, fiche visuelle d'un terminal, ruptures de niveau.

## Environnement
Python 3.6, pandas 1.1.5, PySpark 2.3, matplotlib. Les notebooks lisent les données depuis un dataset Dataiku, ou depuis un CSV local (`CHEMIN_CSV_LOCAL`) pour la version terminal-jour.

Aucune donnée n'est incluse dans ce dépôt.
