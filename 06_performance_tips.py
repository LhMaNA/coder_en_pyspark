"""Performance habits that matter on large tables."""
import time

from pyspark.sql import functions as F

from common import get_spark

spark = get_spark("performance-tips")
events = spark.range(0, 2000000).select(
    F.col("id"), (F.col("id") % 1000).alias("customer_id"), (F.rand(seed=1) * 100).alias("amount"))

# 1. Prefer built-in functions to Python UDFs: they run inside the JVM, without moving rows to Python.
start = time.time()
events.select(F.round(F.col("amount") * 1.2, 2).alias("amount_with_tax")).agg(F.sum("amount_with_tax")).collect()
print("built-in function: {:.1f} s".format(time.time() - start))

# 2. Cache a table only when it is reused by several actions.
customers = events.groupBy("customer_id").agg(F.sum("amount").alias("total")).cache()
print("customers:", customers.count(), "| top total:", customers.agg(F.max("total")).first()[0])
customers.unpersist()

# 3. Repartition once by the key used by later groupBy / window operations.
by_customer = events.repartition("customer_id")
print("partitions after repartition:", by_customer.rdd.getNumPartitions())

# 4. Read the physical plan to spot shuffles (Exchange) before running on the full data.
by_customer.groupBy("customer_id").count().explain()
spark.stop()
