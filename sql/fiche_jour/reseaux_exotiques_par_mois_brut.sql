-- Réseaux exotiques par mois, sur les données brutes : retraits aboutis et montant (€)
SELECT
    mois,
    reseau_exotique,
    COUNT(*)              AS nb,
    ROUND(SUM(montant))   AS montant
FROM (
    SELECT
        SUBSTR(CAST(CASE WHEN CAST(date_operation AS STRING) LIKE '____-__-__%'
                         THEN TO_DATE(SUBSTR(CAST(date_operation AS STRING), 1, 10))
                         ELSE TO_DATE(FROM_UNIXTIME(UNIX_TIMESTAMP(LPAD(CAST(date_operation AS STRING), 8, '0'), 'ddMMyyyy')))
                    END AS STRING), 1, 7)                                       AS mois,
        CASE
            WHEN LPAD(TRIM(CAST(type_reseau AS STRING)), 2, '0') = '07' THEN 'Amex'
            WHEN LPAD(TRIM(CAST(type_reseau AS STRING)), 2, '0') = '12' THEN 'JCB'
            WHEN LPAD(TRIM(CAST(type_reseau AS STRING)), 2, '0') = '10'
             AND UPPER(TRIM(COALESCE(code_carte_privative, ''))) = 'CUP' THEN 'UnionPay'
            WHEN LPAD(TRIM(CAST(type_reseau AS STRING)), 2, '0') = '10'
             AND UPPER(TRIM(COALESCE(code_carte_privative, ''))) = 'DIN' THEN 'Diners'
        END                                                                     AS reseau_exotique,
        CAST(montant_ope AS DOUBLE) / 100                                       AS montant
    FROM `base`.`table_operations_jointe`
    WHERE TRIM(lib_ope) IN ('Retrait', 'Autorisation-Retrait')
      AND COALESCE(CAST(top_annul AS INT), 0) <> 1
) t
WHERE reseau_exotique IS NOT NULL
GROUP BY mois, reseau_exotique
ORDER BY mois, reseau_exotique
;
