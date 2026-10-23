"""Aggregations: groupBy, several aggregate functions at once, pivot."""
from pyspark.sql import functions as F

from common import books, get_spark, sales

spark = get_spark("aggregations")
orders = sales(spark).join(books(spark), "book_id").withColumn("revenue", F.col("quantity") * F.col("price"))

# one pass, several aggregates per category
(orders.groupBy("category")
 .agg(F.sum("quantity").alias("units"), F.round(F.sum("revenue"), 2).alias("revenue"),
      F.countDistinct("store").alias("stores"), F.round(F.avg("price"), 2).alias("avg_price"))
 .orderBy(F.desc("revenue"))
 .show())

# pivot: units sold per category (rows) and store (columns); listing the values avoids an extra Spark job
(orders.groupBy("category").pivot("store", ["Lyon", "Nantes", "Paris"]).agg(F.sum("quantity"))
 .fillna(0).orderBy("category").show())

# approximate quantiles are cheap on large data
print("Median quantity:", orders.approxQuantile("quantity", [0.5], 0.01))
spark.stop()
