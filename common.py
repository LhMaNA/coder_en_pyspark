"""Shared helpers: a local Spark session and a small bookshop dataset used by every exercise."""
from pyspark.sql import SparkSession


def get_spark(app_name):
    """Local Spark session with a small number of shuffle partitions (enough for toy data)."""
    spark = (SparkSession.builder.appName(app_name).master("local[*]")
             .config("spark.sql.shuffle.partitions", "4").getOrCreate())
    spark.sparkContext.setLogLevel("ERROR")
    return spark


BOOKS = [
    (1, "The Silent Forest", "Fiction", 12.50, 2015),
    (2, "Data at Scale", "Technology", 39.90, 2021),
    (3, "Cooking with Herbs", "Cooking", 18.00, 2018),
    (4, "Northern Lights", "Fiction", 9.99, 2012),
    (5, "Learning Statistics", "Technology", 29.00, 2019),
    (6, "Mountain Trails", "Travel", 21.50, 2020),
    (7, "Coastal Roads", "Travel", 19.90, 2017),
]

SALES = [
    ("2024-03-01", 1, "Lyon", 2), ("2024-03-01", 2, "Paris", 1), ("2024-03-02", 3, "Paris", 4),
    ("2024-03-02", 1, "Nantes", 1), ("2024-03-03", 4, "Lyon", 3), ("2024-03-03", 2, "Lyon", 2),
    ("2024-03-04", 5, "Paris", 1), ("2024-03-04", 6, "Nantes", 2), ("2024-03-05", 1, "Paris", 5),
    ("2024-03-05", 7, "Lyon", 1), ("2024-03-06", 2, "Nantes", 3), ("2024-03-06", 3, "Lyon", 2),
    ("2024-03-07", 4, "Paris", 2), ("2024-03-07", 5, "Lyon", 1), ("2024-03-08", 6, "Paris", 2),
]


def books(spark):
    return spark.createDataFrame(BOOKS, ["book_id", "title", "category", "price", "year"])


def sales(spark):
    return spark.createDataFrame(SALES, ["sale_date", "book_id", "store", "quantity"])
