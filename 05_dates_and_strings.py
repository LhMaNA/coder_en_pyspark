"""Dates and strings: parsing, date arithmetic, cleaning text, regular expressions."""
from pyspark.sql import functions as F

from common import get_spark

spark = get_spark("dates-and-strings")
raw = spark.createDataFrame(
    [("  alice MARTIN ", "05/01/2024", "alice.martin@example.com"),
     ("Bob durand", "17/02/2024", "bob_durand@example.org"),
     ("claire  petit", "29/02/2024", "not-an-email")],
    ["name", "signup", "email"])

clean = (raw
         .withColumn("name", F.initcap(F.regexp_replace(F.trim("name"), r"\s+", " ")))
         .withColumn("signup", F.to_date("signup", "dd/MM/yyyy"))
         .withColumn("weekday", F.date_format("signup", "EEEE"))
         .withColumn("days_since_signup", F.datediff(F.to_date(F.lit("2024-03-31")), "signup"))
         .withColumn("end_of_month", F.last_day("signup"))
         .withColumn("valid_email", F.col("email").rlike(r"^[\w.]+@[\w-]+\.[a-z]{2,}$"))
         .withColumn("domain", F.regexp_extract("email", r"@(.+)$", 1)))
clean.show(truncate=False)
spark.stop()
