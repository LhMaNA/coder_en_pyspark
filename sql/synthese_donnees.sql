SELECT LENGTH(TRIM(num_carte)) AS longueur,
       COUNT(*)                 AS nb_operations,
       COUNT(DISTINCT num_carte) AS nb_valeurs_distinctes
FROM
WHERE SUBSTR(date_operation, 3, 6) = '102026'
GROUP BY LENGTH(TRIM(num_carte))
ORDER BY nb_operations DESC
