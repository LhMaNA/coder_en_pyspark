"""DataFrame basics: schema, select, filter, new columns, sorting."""
from pyspark.sql import functions as F

from common import books, get_spark

spark = get_spark("dataframe-basics")
df = books(spark)

df.printSchema()
df.show()

# select and rename columns
df.select("title", F.col("price").alias("price_eur")).show()

# filter rows: books after 2016 costing less than 25
df.filter((F.col("year") > 2016) & (F.col("price") < 25)).show()

# new columns: price with VAT, and a price band
priced = (df.withColumn("price_with_vat", F.round(F.col("price") * 1.055, 2))
          .withColumn("band", F.when(F.col("price") < 15, "cheap")
                      .when(F.col("price") < 30, "standard").otherwise("premium")))
priced.orderBy(F.desc("price")).show()

print("Number of books:", df.count())
spark.stop()
