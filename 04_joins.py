"""Joins: inner, left, anti and broadcast."""
from pyspark.sql import functions as F

from common import books, get_spark, sales

spark = get_spark("joins")
book_df, sale_df = books(spark), sales(spark)

# inner join: only books that were sold
sale_df.join(book_df, "book_id").select("sale_date", "title", "store", "quantity").show()

# left join: every book, with its total units (0 if never sold)
units = sale_df.groupBy("book_id").agg(F.sum("quantity").alias("units"))
book_df.join(units, "book_id", "left").fillna(0, subset=["units"]).orderBy(F.desc("units")).show()

# anti join: books never sold
book_df.join(sale_df, "book_id", "left_anti").show()

# broadcast join: send the small table to every executor instead of shuffling the large one
sale_df.join(F.broadcast(book_df), "book_id").explain()
spark.stop()
