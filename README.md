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

## Anomaly detection notebook

`detection_anomalies/detection_anomalies_spark.ipynb`: a self-contained PySpark notebook for anomaly detection
on transaction data (data quality, seasonality, rule-based detection, prioritisation, daily report). The
business rules block (network codes, dataset name) is left empty on purpose and must be filled in locally.

## Impact analysis notebook

`analyse_impact/impact_terminaux.ipynb`: a PySpark notebook that measures whether a small set of terminals changed
behaviour after an external event (stopped, reduced or increased activity), compared with each terminal's own
habit and with the same period of the previous year. `impact_terminaux_resultats_fictifs.ipynb` is the same
notebook executed on simulated data. The dataset name is left empty and must be filled in locally.

## Cash cassette incident detection

`detection_cassettes/`: detects rare cash-cassette incidents on terminals (swapped 10 € / 20 € cassettes,
wrong cassette configuration, jammed or empty cassette, repeated withdrawals by the same card). Each terminal is
compared hour by hour with its own habit over the previous four weeks; cassette loadings are dated from the
theoretical cash balance.

- `cassettes_terminal_heure.sql`: Hive recipe, one row per terminal, day and hour (table names are placeholders).
- `detection_cassettes.ipynb`: the notebook (the known-case block is left empty).
- `detection_cassettes_resultats_fictifs.ipynb`: the same notebook executed on simulated data.
