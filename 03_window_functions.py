"""Window functions: ranking, running totals, moving averages, lag and lead."""
from pyspark.sql import Window
from pyspark.sql import functions as F

from common import books, get_spark, sales

spark = get_spark("window-functions")
orders = (sales(spark).join(books(spark), "book_id")
          .withColumn("revenue", F.col("quantity") * F.col("price"))
          .withColumn("sale_date", F.to_date("sale_date")))

daily = orders.groupBy("store", "sale_date").agg(F.round(F.sum("revenue"), 2).alias("revenue"))
by_store = Window.partitionBy("store").orderBy("sale_date")

(daily
 .withColumn("running_total", F.round(F.sum("revenue").over(by_store.rowsBetween(Window.unboundedPreceding, 0)), 2))
 .withColumn("moving_avg_3", F.round(F.avg("revenue").over(by_store.rowsBetween(-2, 0)), 2))
 .withColumn("previous_day", F.lag("revenue").over(by_store))
 .withColumn("next_day", F.lead("revenue").over(by_store))
 .orderBy("store", "sale_date")
 .show())

# best-selling book in each store
units = orders.groupBy("store", "title").agg(F.sum("quantity").alias("units"))
ranking = Window.partitionBy("store").orderBy(F.desc("units"), "title")
units.withColumn("rank", F.row_number().over(ranking)).filter(F.col("rank") == 1).show()
spark.stop()
