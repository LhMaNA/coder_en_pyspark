# Learning PySpark

Small, self-contained PySpark exercises. Each script builds its own toy dataset, so nothing has to be
downloaded: run it and read the output.

| Script | Topic |
|---|---|
| `01_dataframe_basics.py` | creating DataFrames, schemas, selecting, filtering, new columns |
| `02_aggregations.py` | `groupBy`, aggregate functions, pivot tables |
| `03_window_functions.py` | ranking, running totals, moving averages, `lag` / `lead` |
| `04_joins.py` | inner, left, anti and broadcast joins |
| `05_dates_and_strings.py` | parsing dates, date arithmetic, string cleaning, regular expressions |
| `06_performance_tips.py` | caching, partitioning, avoiding Python UDFs, reading the query plan |

## Running

```bash
pip install -r requirements.txt
python 01_dataframe_basics.py
```

The scripts use a local Spark session (`local[*]`) and only built-in Spark SQL functions, so they also run
on a cluster without changes.
