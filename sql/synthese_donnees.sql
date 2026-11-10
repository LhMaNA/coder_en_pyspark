-- =====================================================================================================
-- SYNTHÈSE DES DONNÉES (Hive)
-- Remplacer `base`.`table_operations` par le nom réel de la table avant de lancer.
-- Une seule lecture de la table, GROUP BY simple, pas de COUNT(DISTINCT) global.
-- date_operation : texte ddMMyyyy ; heure_operation : HHMMSS ; montant_ope : en centimes.
-- =====================================================================================================

-- -----------------------------------------------------------------------------------------------------
-- REQUÊTE 1 : année x opération x réseau
-- Pour tester sur une seule année : ajouter WHERE SUBSTR(date_operation, 5, 4) = '2025'
-- -----------------------------------------------------------------------------------------------------
SELECT
    SUBSTR(date_operation, 5, 4)                         AS annee,
    lib_ope,
    top_annul,
    type_reseau,
    code_carte_privative,

    -- volumes
    COUNT(*)                                             AS nb_operations,
    ROUND(SUM(CAST(montant_ope AS DOUBLE)) / 100, 0)     AS montant_total_euros,
    ROUND(AVG(CAST(montant_ope AS DOUBLE)) / 100, 1)     AS montant_moyen_euros,
    MIN(CAST(montant_ope AS DOUBLE)) / 100               AS montant_min_euros,
    MAX(CAST(montant_ope AS DOUBLE)) / 100               AS montant_max_euros,

    -- tranches de montant (en euros)
    SUM(CASE WHEN CAST(montant_ope AS DOUBLE) = 0                        THEN 1 ELSE 0 END) AS nb_montant_0,
    SUM(CASE WHEN CAST(montant_ope AS DOUBLE) > 0     AND CAST(montant_ope AS DOUBLE) <= 2000  THEN 1 ELSE 0 END) AS nb_1_20,
    SUM(CASE WHEN CAST(montant_ope AS DOUBLE) > 2000  AND CAST(montant_ope AS DOUBLE) <= 5000  THEN 1 ELSE 0 END) AS nb_21_50,
    SUM(CASE WHEN CAST(montant_ope AS DOUBLE) > 5000  AND CAST(montant_ope AS DOUBLE) <= 10000 THEN 1 ELSE 0 END) AS nb_51_100,
    SUM(CASE WHEN CAST(montant_ope AS DOUBLE) > 10000 AND CAST(montant_ope AS DOUBLE) <= 20000 THEN 1 ELSE 0 END) AS nb_101_200,
    SUM(CASE WHEN CAST(montant_ope AS DOUBLE) > 20000                    THEN 1 ELSE 0 END) AS nb_plus_200,

    -- moment de la journée (heure_operation = HHMMSS)
    SUM(CASE WHEN SUBSTR(LPAD(CAST(heure_operation AS STRING), 6, '0'), 1, 2) BETWEEN '00' AND '05' THEN 1 ELSE 0 END) AS nb_nuit_0h_6h,
    SUM(CASE WHEN SUBSTR(LPAD(CAST(heure_operation AS STRING), 6, '0'), 1, 2) BETWEEN '06' AND '11' THEN 1 ELSE 0 END) AS nb_matin_6h_12h,
    SUM(CASE WHEN SUBSTR(LPAD(CAST(heure_operation AS STRING), 6, '0'), 1, 2) BETWEEN '12' AND '17' THEN 1 ELSE 0 END) AS nb_aprem_12h_18h,
    SUM(CASE WHEN SUBSTR(LPAD(CAST(heure_operation AS STRING), 6, '0'), 1, 2) BETWEEN '18' AND '23' THEN 1 ELSE 0 END) AS nb_soir_18h_24h,

    -- week-end (u = jour de la semaine, 6 = samedi, 7 = dimanche)
    SUM(CASE WHEN FROM_UNIXTIME(UNIX_TIMESTAMP(date_operation, 'ddMMyyyy'), 'u') IN ('6', '7') THEN 1 ELSE 0 END) AS nb_week_end,

    -- dates couvertes
    MIN(CONCAT(SUBSTR(date_operation, 5, 4), SUBSTR(date_operation, 3, 2), SUBSTR(date_operation, 1, 2))) AS premiere_date,
    MAX(CONCAT(SUBSTR(date_operation, 5, 4), SUBSTR(date_operation, 3, 2), SUBSTR(date_operation, 1, 2))) AS derniere_date

FROM `base`.`table_operations`
GROUP BY SUBSTR(date_operation, 5, 4), lib_ope, top_annul, type_reseau, code_carte_privative
ORDER BY annee, lib_ope, top_annul, nb_operations DESC;


-- -----------------------------------------------------------------------------------------------------
-- REQUÊTE 2 (facultative) : répartition des terminaux entre eux, par année
-- -----------------------------------------------------------------------------------------------------
SELECT annee,
       COUNT(*)                                   AS nb_terminaux,
       ROUND(AVG(nb_retraits), 0)                 AS moyenne_retraits_par_terminal,
       PERCENTILE_APPROX(nb_retraits, 0.10)       AS p10,
       PERCENTILE_APPROX(nb_retraits, 0.50)       AS mediane,
       PERCENTILE_APPROX(nb_retraits, 0.90)       AS p90,
       MAX(nb_retraits)                           AS max_retraits,
       ROUND(AVG(nb_jours_actifs), 0)             AS moyenne_jours_actifs,
       MIN(nb_jours_actifs)                       AS min_jours_actifs
FROM (
    SELECT SUBSTR(date_operation, 5, 4) AS annee,
           num_automate,
           SUM(CASE WHEN lib_ope <> 'Capture de Carte' AND CAST(top_annul AS INT) = 0 THEN 1 ELSE 0 END) AS nb_retraits,
           COUNT(DISTINCT date_operation) AS nb_jours_actifs
    FROM `base`.`table_operations`
    GROUP BY SUBSTR(date_operation, 5, 4), num_automate
) g
GROUP BY annee
ORDER BY annee;
