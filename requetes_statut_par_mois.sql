SELECT
    from_unixtime(
        unix_timestamp(SUBSTR(CAST(timestamp_postage_mq AS STRING), 1, 19)) + 7200,
        'yyyy-MM'
    ) AS mois_heure_paris,
    statut,
    COUNT(*) AS nb_requetes
FROM ta_table
WHERE circuit = 'RVM'
  AND SUBSTR(CAST(timestamp_postage_mq AS STRING), 1, 19) >= '2026-06-30 22:00:00'
  AND SUBSTR(CAST(timestamp_postage_mq AS STRING), 1, 19) <  '2026-09-30 22:00:00'
GROUP BY
    from_unixtime(
        unix_timestamp(SUBSTR(CAST(timestamp_postage_mq AS STRING), 1, 19)) + 7200,
        'yyyy-MM'
    ),
    statut
ORDER BY mois_heure_paris, statut
