# Notebooks (Dataiku, Python 3.6, pandas 1.1.5, sans bibliothèque supplémentaire)

| Notebook | Entrée | Rôle |
|---|---|---|
| `analyse_descriptive_fiche_jour.ipynb` | `fiche_gab_jour` (recette `sql/fiche_jour/fiche_jour_requete_unique.sql`), `voisins_gab` (`voisins.sql`) | Étape 1 : analyse descriptive du parc, familles métier par règles, détection statistique quotidienne (catalogue de règles), liste des GAB les plus atypiques avec diagnostic, carte du jour, Excel téléchargeable (photo du parc jour par jour) |
| `impact_manifestations_fiche_jour.ipynb` | `fiche_gab_jour` | Impact d'un événement sur des GAB (zone ou liste) : tri changé / inchangé, rupture, attendu contrefactuel, KPI avant / après / N-1, indisponibilité, manque à gagner |
| `etape_2_ml_detection_atypiques.ipynb` | idem étape 1 | Étape 2 (plus tard) : mêmes règles + Isolation Forest et familles k-means |

Seule la section 1 (réglages) de chaque notebook se modifie. Les cas de test (`CAS_TESTS`) sont à renseigner localement.
