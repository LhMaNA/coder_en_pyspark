"""Petits outils Spark / pandas réutilisés dans toute la librairie (compatibles Spark 2.3, Python 3.6)."""
from functools import reduce

from pyspark.sql import Window
from pyspark.sql import functions as F

CLE_TERMINAL = "num_automate"


def en_pandas(sdf, max_lignes=5000000):
    """Ramène un résultat Spark DÉJÀ AGRÉGÉ en pandas (les calculs portent sur toutes les lignes)."""
    pdf = sdf.limit(max_lignes).toPandas()
    if len(pdf) == max_lignes:
        print("Attention : résultat tronqué à {} lignes.".format(max_lignes))
    return pdf


def fmt_nombre(n):
    """12345678 -> '12 345 678'."""
    return "{:,.0f}".format(n).replace(",", " ")


def en_nombre(colonne):
    """Colonne texte ou numérique -> double (virgule décimale acceptée)."""
    return F.regexp_replace(F.trim(F.col(colonne).cast("string")), ",", ".").cast("double")


def centile(colonne, q):
    """Centile approché (expression SQL : compatible Spark 2.3). `q` peut être un nombre ou 'array(...)'."""
    return F.expr("percentile_approx({}, {})".format(colonne, q))


def somme_si(condition, valeur=1):
    """Somme de `valeur` sur les lignes où `condition` est vraie."""
    return F.sum(F.when(condition, valeur).otherwise(0))


def selon_correspondance(colonne, correspondance, defaut=None):
    """Expression CASE WHEN : valeur de `correspondance` pour chaque valeur de `colonne`."""
    expression = F.when(F.lit(False), F.lit(""))
    for cle, valeur in correspondance.items():
        expression = expression.when(colonne == cle, valeur)
    return expression.otherwise(defaut) if defaut is not None else expression


def fenetre_meme_jour_semaine(nb_semaines=8):
    """Les `nb_semaines` mêmes jours de semaine précédents, pour chaque terminal."""
    return (Window.partitionBy(CLE_TERMINAL, F.dayofweek("date")).orderBy("date")
            .rowsBetween(-nb_semaines, -1))


def fenetre_jours_precedents(nb_jours=7):
    """Les `nb_jours` journées actives précédentes, pour chaque terminal."""
    return Window.partitionBy(CLE_TERMINAL).orderBy("date").rowsBetween(-nb_jours, -1)


def ecart_robuste(colonne, reference, dispersion, plancher=1.0):
    """(valeur - référence) / max(dispersion, plancher) : écart exprimé en « écarts habituels »."""
    return (F.col(colonne) - F.col(reference)) / F.greatest(F.coalesce(F.col(dispersion), F.lit(0.0)),
                                                            F.lit(float(plancher)))


def union_toutes(tables):
    """Union de DataFrames Spark de même schéma (liste non vide)."""
    return reduce(lambda gauche, droite: gauche.union(droite), tables)


def persister(table, actif=True):
    """Persiste la table en mémoire / disque du cluster si `actif`."""
    from pyspark import StorageLevel
    return table.persist(StorageLevel.MEMORY_AND_DISK) if actif else table
