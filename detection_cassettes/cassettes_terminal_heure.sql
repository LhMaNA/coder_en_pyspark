-- =====================================================================================================
-- RECETTE : CASSETTES terminal x HEURE  (entrée du notebook detection_cassettes_terminal)
-- Une ligne par terminal, par jour et par heure ayant au moins un retrait abouti, sur la période choisie.
-- Source unique : la table des retraits (aucune jointure ; code regate = code_site_implantation).
-- Pour chaque position de cassette (1 à 4) : billets sortis, retraits qui l'ont utilisée, valeur déclarée.
-- Période : 8 semaines de référence + la période analysée (ici du 01/09/2026 au 08/11/2026).
-- Uniquement des comptes et des sommes ; la détection est faite dans le notebook.
-- Encaisse théorique (euros, chaîne '0000017190' = 17 190 EUR) : sert à dater les chargements du terminal et à vérifier
-- que l'encaisse baisse exactement du montant de chaque retrait.
-- ADAPTER : top_annul, nb_billetsk_7_1..4, val_coupurek_7_1..4, format de heure_operation (HHMMSS).
-- =====================================================================================================
SELECT
    x.num_automate,
    x.date_jour,
    x.h                                                                   AS heure,
    MAX(x.code_site_implantation)                                         AS code_site_implantation,   -- code regate

    COUNT(*)                                                              AS nb_retraits,
    SUM(x.montant)                                                        AS montant_total,
    SUM(CASE WHEN PMOD(CAST(ROUND(x.montant) AS INT), 20) = 10 THEN 1 ELSE 0 END) AS nb_montants_finissant_10,
    SUM(CASE WHEN x.ecart_meme_carte_sec <= 600 THEN 1 ELSE 0 END)        AS nb_retraits_repetes_10min,
    SUM(CASE WHEN ABS(x.montant - x.montant_billets) > 0.01 THEN 1 ELSE 0 END) AS nb_ecart_billets_montant,

    SUM(x.nb1) AS nb_billets_pos1, SUM(CASE WHEN x.nb1 > 0 THEN 1 ELSE 0 END) AS nb_retraits_pos1,
    MIN(CASE WHEN x.nb1 > 0 THEN x.val1 END) AS val_min_pos1, MAX(CASE WHEN x.nb1 > 0 THEN x.val1 END) AS val_max_pos1,
    SUM(x.nb2) AS nb_billets_pos2, SUM(CASE WHEN x.nb2 > 0 THEN 1 ELSE 0 END) AS nb_retraits_pos2,
    MIN(CASE WHEN x.nb2 > 0 THEN x.val2 END) AS val_min_pos2, MAX(CASE WHEN x.nb2 > 0 THEN x.val2 END) AS val_max_pos2,
    SUM(x.nb3) AS nb_billets_pos3, SUM(CASE WHEN x.nb3 > 0 THEN 1 ELSE 0 END) AS nb_retraits_pos3,
    MIN(CASE WHEN x.nb3 > 0 THEN x.val3 END) AS val_min_pos3, MAX(CASE WHEN x.nb3 > 0 THEN x.val3 END) AS val_max_pos3,
    SUM(x.nb4) AS nb_billets_pos4, SUM(CASE WHEN x.nb4 > 0 THEN 1 ELSE 0 END) AS nb_retraits_pos4,
    MIN(CASE WHEN x.nb4 > 0 THEN x.val4 END) AS val_min_pos4, MAX(CASE WHEN x.nb4 > 0 THEN x.val4 END) AS val_max_pos4,

    -- encaisse théorique : niveau dans l'heure, chargements (remontée de l'encaisse), incohérences
    MIN(x.encaisse)                                                       AS encaisse_min_heure,
    MAX(x.encaisse)                                                       AS encaisse_max_heure,
    SUM(CASE WHEN x.variation_encaisse > 0 THEN 1 ELSE 0 END)             AS nb_recharges,
    SUM(CASE WHEN x.variation_encaisse > 0 THEN x.variation_encaisse ELSE 0 END) AS montant_recharge,
    SUM(CASE WHEN x.variation_encaisse <= 0
              AND ABS(x.variation_encaisse + x.montant) > 0.5 THEN 1 ELSE 0 END) AS nb_incoherences_encaisse

FROM (
    SELECT
        o.*,
        o.sec - LAG(o.sec) OVER (PARTITION BY o.num_automate, o.date_jour, o.num_carte ORDER BY o.sec) AS ecart_meme_carte_sec,
        o.encaisse - LAG(o.encaisse) OVER (PARTITION BY o.num_automate ORDER BY o.date_jour, o.sec)    AS variation_encaisse
    FROM (
        SELECT
            num_automate,
            num_carte,
            code_site_implantation,                                                    -- code regate du terminal
            CASE WHEN CAST(date_operation AS STRING) LIKE '____-__-__%'
                 THEN TO_DATE(SUBSTR(CAST(date_operation AS STRING), 1, 10))
                 ELSE TO_DATE(FROM_UNIXTIME(UNIX_TIMESTAMP(LPAD(CAST(date_operation AS STRING), 8, '0'), 'ddMMyyyy')))
            END                                                                        AS date_jour,
            CAST(SUBSTR(LPAD(CAST(heure_operation AS STRING), 6, '0'), 1, 2) AS INT)   AS h,
            CAST(SUBSTR(LPAD(CAST(heure_operation AS STRING), 6, '0'), 1, 2) AS INT) * 3600
          + CAST(SUBSTR(LPAD(CAST(heure_operation AS STRING), 6, '0'), 3, 2) AS INT) * 60
          + CAST(SUBSTR(LPAD(CAST(heure_operation AS STRING), 6, '0'), 5, 2) AS INT)   AS sec,
            CAST(montant_ope AS DOUBLE) / 100                                          AS montant,
            CAST(REGEXP_REPLACE(CAST(encaisse_theorique AS STRING), '[^0-9]', '') AS DOUBLE) AS encaisse,   -- en euros
            COALESCE(CAST(nb_billetsk_7_1 AS INT), 0) AS nb1, CAST(val_coupurek_7_1 AS INT) / 100 AS val1,
            COALESCE(CAST(nb_billetsk_7_2 AS INT), 0) AS nb2, CAST(val_coupurek_7_2 AS INT) / 100 AS val2,
            COALESCE(CAST(nb_billetsk_7_3 AS INT), 0) AS nb3, CAST(val_coupurek_7_3 AS INT) / 100 AS val3,
            COALESCE(CAST(nb_billetsk_7_4 AS INT), 0) AS nb4, CAST(val_coupurek_7_4 AS INT) / 100 AS val4,
            (COALESCE(CAST(nb_billetsk_7_1 AS DOUBLE), 0) * COALESCE(CAST(val_coupurek_7_1 AS DOUBLE), 0)
           + COALESCE(CAST(nb_billetsk_7_2 AS DOUBLE), 0) * COALESCE(CAST(val_coupurek_7_2 AS DOUBLE), 0)
           + COALESCE(CAST(nb_billetsk_7_3 AS DOUBLE), 0) * COALESCE(CAST(val_coupurek_7_3 AS DOUBLE), 0)
           + COALESCE(CAST(nb_billetsk_7_4 AS DOUBLE), 0) * COALESCE(CAST(val_coupurek_7_4 AS DOUBLE), 0)) / 100
                                                                                       AS montant_billets
        FROM `base`.`table_operations`
        WHERE lib_ope IN ('Retrait', 'Autorisation-Retrait')
          AND CAST(top_annul AS INT) = 0                                               -- ADAPTER nom
    ) o
    WHERE o.date_jour BETWEEN '2026-09-01' AND '2026-11-08'                            -- ADAPTER période
) x
GROUP BY x.num_automate, x.date_jour, x.h
