-- =====================================================================================================
-- IMPACT D'UNE INVERSION DE CASSETTES 10 € / 20 € : combien de retraits, combien de clients, combien d'euros
-- Sur les données brutes, un GAB, une période.
-- Règle : l'inversion porte sur les cassettes 2 et 3 seulement : la cassette 2 (DÉCLARÉE 10 €) contient des billets de
--   20 €, la cassette 3 (déclarée 20 €) des billets de 10 €. Les cassettes 1 et 4 ne sont pas touchées.
--   Pour chaque retrait abouti :
--     billet sorti de la cassette 2 « 10 € » -> le client reçoit 10 € de trop  (il gagne, la banque perd)
--     billet sorti de la cassette 3 « 20 € » -> le client reçoit 10 € de moins (il perd, il est lésé)
--   gain du client = 10 € x billets cassette 2  ;  perte du client = 10 € x billets cassette 3  ;  net = gain - perte
--   Par sécurité, une cassette n'est comptée que si sa valeur déclarée est bien 10 € (cassette 2) ou 20 € (cassette 3).
-- À RÉGLER dans chaque requête (chercher « RÉGLAGE ») : le GAB et le début / la fin de la période (AAAA-MM-JJ HH:MM:SS).
-- Les 6 requêtes sont indépendantes :
--   1) la synthèse en retraits     2) la synthèse en clients (une carte = un client)
--   3) le détail heure par heure   4) la liste des clients, du plus gagnant au plus lésé
--   5) le détail de chaque transaction (ce que le client a demandé, les billets de chaque cassette, ce qu'il a reçu)
--   6) la synthèse jour par jour
-- =====================================================================================================

-- -----------------------------------------------------------------------------------------------------
-- 1) SYNTHÈSE EN RETRAITS
-- -----------------------------------------------------------------------------------------------------
SELECT
    COUNT(*)                                                         AS retraits_aboutis_sur_la_periode,
    SUM(CASE WHEN b10 + b20 > 0 THEN 1 ELSE 0 END)                   AS retraits_concernes,
    SUM(CASE WHEN b10 > 0 THEN 1 ELSE 0 END)                         AS retraits_avec_billets_cassette_2,
    SUM(CASE WHEN b20 > 0 THEN 1 ELSE 0 END)                         AS retraits_avec_billets_cassette_3,
    SUM(CASE WHEN b10 > b20 THEN 1 ELSE 0 END)                       AS retraits_client_gagnant,
    SUM(CASE WHEN b10 < b20 THEN 1 ELSE 0 END)                       AS retraits_client_lese,
    SUM(CASE WHEN b10 + b20 > 0 AND b10 = b20 THEN 1 ELSE 0 END)     AS retraits_neutres,
    SUM(10 * b10)                                                    AS euros_donnes_en_trop,
    SUM(10 * b20)                                                    AS euros_donnes_en_moins,
    SUM(10 * (b10 - b20))                                            AS perte_nette_banque_euros,
    ROUND(SUM(montant))                                              AS montant_demande_sur_la_periode
FROM (
    SELECT
        CONCAT(CAST(date_jour AS STRING), ' ', SUBSTR(h6, 1, 2), ':', SUBSTR(h6, 3, 2), ':', SUBSTR(h6, 5, 2)) AS horodatage,
        b10, b20, montant
    FROM (
        SELECT
            CASE WHEN CAST(date_operation AS STRING) LIKE '____-__-__%'
                 THEN TO_DATE(SUBSTR(CAST(date_operation AS STRING), 1, 10))
                 ELSE TO_DATE(FROM_UNIXTIME(UNIX_TIMESTAMP(LPAD(CAST(date_operation AS STRING), 8, '0'), 'ddMMyyyy')))
            END                                                                      AS date_jour,
            LPAD(CAST(heure_operation AS STRING), 6, '0')                            AS h6,
            CASE WHEN CAST(val_coupurek7_2 AS INT) = 10 THEN COALESCE(CAST(nb_billetsk7_2 AS INT), 0) ELSE 0 END AS b10,   -- cassette 2 (déclarée 10 €)
            CASE WHEN CAST(val_coupurek7_3 AS INT) = 20 THEN COALESCE(CAST(nb_billetsk7_3 AS INT), 0) ELSE 0 END AS b20,   -- cassette 3 (déclarée 20 €)
            CAST(montant_ope AS DOUBLE) / 100                                        AS montant
        FROM `base`.`table_operations_jointe`
        WHERE TRIM(CAST(num_automate AS STRING)) = '000000'                          -- RÉGLAGE : le GAB
          AND TRIM(lib_ope) IN ('Retrait', 'Autorisation-Retrait')
          AND COALESCE(CAST(top_annul AS INT), 0) <> 1                               -- retraits aboutis
    ) o
) t
WHERE horodatage >= '2026-01-01 12:00:00' AND horodatage < '2026-01-02 18:00:00'     -- RÉGLAGE : la période
;


-- -----------------------------------------------------------------------------------------------------
-- 2) SYNTHÈSE EN CLIENTS : chaque carte est un client ; un client est gagnant si, sur toute la période,
--    il a reçu plus qu'il n'a demandé, lésé s'il a reçu moins
-- -----------------------------------------------------------------------------------------------------
SELECT
    COUNT(*)                                                         AS clients_concernes,
    SUM(CASE WHEN net > 0 THEN 1 ELSE 0 END)                         AS clients_gagnants,
    SUM(CASE WHEN net > 0 THEN net ELSE 0 END)                       AS euros_gagnes_par_les_clients,
    SUM(CASE WHEN net < 0 THEN 1 ELSE 0 END)                         AS clients_leses,
    SUM(CASE WHEN net < 0 THEN -net ELSE 0 END)                      AS euros_perdus_par_les_clients,
    SUM(CASE WHEN net = 0 THEN 1 ELSE 0 END)                         AS clients_a_zero,
    SUM(net)                                                         AS perte_nette_banque_euros,
    SUM(CASE WHEN nb_retraits >= 2 THEN 1 ELSE 0 END)                AS clients_revenus_plusieurs_fois,
    MAX(net)                                                         AS plus_gros_gain_d_un_client
FROM (
    SELECT num_carte, COUNT(*) AS nb_retraits, SUM(10 * (b10 - b20)) AS net
    FROM (
        SELECT
            num_carte,
            CONCAT(CAST(date_jour AS STRING), ' ', SUBSTR(h6, 1, 2), ':', SUBSTR(h6, 3, 2), ':', SUBSTR(h6, 5, 2)) AS horodatage,
            b10, b20
        FROM (
            SELECT
                TRIM(CAST(num_carte AS STRING))                                          AS num_carte,
                CASE WHEN CAST(date_operation AS STRING) LIKE '____-__-__%'
                     THEN TO_DATE(SUBSTR(CAST(date_operation AS STRING), 1, 10))
                     ELSE TO_DATE(FROM_UNIXTIME(UNIX_TIMESTAMP(LPAD(CAST(date_operation AS STRING), 8, '0'), 'ddMMyyyy')))
                END                                                                      AS date_jour,
                LPAD(CAST(heure_operation AS STRING), 6, '0')                            AS h6,
                CASE WHEN CAST(val_coupurek7_2 AS INT) = 10 THEN COALESCE(CAST(nb_billetsk7_2 AS INT), 0) ELSE 0 END AS b10,   -- cassette 2
                CASE WHEN CAST(val_coupurek7_3 AS INT) = 20 THEN COALESCE(CAST(nb_billetsk7_3 AS INT), 0) ELSE 0 END AS b20    -- cassette 3
            FROM `base`.`table_operations_jointe`
            WHERE TRIM(CAST(num_automate AS STRING)) = '000000'                          -- RÉGLAGE : le GAB
              AND TRIM(lib_ope) IN ('Retrait', 'Autorisation-Retrait')
              AND COALESCE(CAST(top_annul AS INT), 0) <> 1
        ) o
    ) t
    WHERE horodatage >= '2026-01-01 12:00:00' AND horodatage < '2026-01-02 18:00:00' -- RÉGLAGE : la période
      AND b10 + b20 > 0
    GROUP BY num_carte
) c
;


-- -----------------------------------------------------------------------------------------------------
-- 3) HEURE PAR HEURE : pour voir quand l'inversion commence et finit (la veille et le lendemain inclus)
-- -----------------------------------------------------------------------------------------------------
SELECT
    date_jour,
    heure,
    COUNT(*)                                                         AS retraits_aboutis,
    SUM(b10)                                                         AS billets_cassette_2,
    SUM(b20)                                                         AS billets_cassette_3,
    ROUND(100 * SUM(b10) / GREATEST(SUM(b10 + b20), 1), 1)           AS part_billets_cassette_2_pct,
    SUM(10 * b10)                                                    AS euros_donnes_en_trop,
    SUM(10 * b20)                                                    AS euros_donnes_en_moins,
    SUM(10 * (b10 - b20))                                            AS perte_nette_banque_euros,
    COUNT(DISTINCT num_carte)                                        AS clients
FROM (
    SELECT
        TRIM(CAST(num_carte AS STRING))                                          AS num_carte,
        CASE WHEN CAST(date_operation AS STRING) LIKE '____-__-__%'
             THEN TO_DATE(SUBSTR(CAST(date_operation AS STRING), 1, 10))
             ELSE TO_DATE(FROM_UNIXTIME(UNIX_TIMESTAMP(LPAD(CAST(date_operation AS STRING), 8, '0'), 'ddMMyyyy')))
        END                                                                      AS date_jour,
        CAST(SUBSTR(LPAD(CAST(heure_operation AS STRING), 6, '0'), 1, 2) AS INT) AS heure,
        CASE WHEN CAST(val_coupurek7_2 AS INT) = 10 THEN COALESCE(CAST(nb_billetsk7_2 AS INT), 0) ELSE 0 END AS b10,   -- cassette 2
        CASE WHEN CAST(val_coupurek7_3 AS INT) = 20 THEN COALESCE(CAST(nb_billetsk7_3 AS INT), 0) ELSE 0 END AS b20    -- cassette 3
    FROM `base`.`table_operations_jointe`
    WHERE TRIM(CAST(num_automate AS STRING)) = '000000'                          -- RÉGLAGE : le GAB
      AND TRIM(lib_ope) IN ('Retrait', 'Autorisation-Retrait')
      AND COALESCE(CAST(top_annul AS INT), 0) <> 1
) o
WHERE date_jour BETWEEN '2025-12-31' AND '2026-01-03'                            -- RÉGLAGE : la veille et le lendemain inclus
GROUP BY date_jour, heure
ORDER BY date_jour, heure
;


-- -----------------------------------------------------------------------------------------------------
-- 4) LA LISTE DES CLIENTS (carte masquée), du plus gagnant au plus lésé
-- -----------------------------------------------------------------------------------------------------
SELECT
    num_carte,
    COUNT(*)                                                         AS nb_retraits,
    MIN(horodatage)                                                  AS premier_retrait,
    MAX(horodatage)                                                  AS dernier_retrait,
    ROUND(SUM(montant))                                              AS montant_demande,
    SUM(10 * b10)                                                    AS euros_recus_en_trop,
    SUM(10 * b20)                                                    AS euros_recus_en_moins,
    SUM(10 * (b10 - b20))                                            AS gain_net_du_client,
    CASE WHEN SUM(b10 - b20) > 0 THEN 'gagnant' WHEN SUM(b10 - b20) < 0 THEN 'lésé' ELSE 'à zéro' END AS bilan
FROM (
    SELECT
        num_carte,
        CONCAT(CAST(date_jour AS STRING), ' ', SUBSTR(h6, 1, 2), ':', SUBSTR(h6, 3, 2), ':', SUBSTR(h6, 5, 2)) AS horodatage,
        b10, b20, montant
    FROM (
        SELECT
            TRIM(CAST(num_carte AS STRING))                                          AS num_carte,
            CASE WHEN CAST(date_operation AS STRING) LIKE '____-__-__%'
                 THEN TO_DATE(SUBSTR(CAST(date_operation AS STRING), 1, 10))
                 ELSE TO_DATE(FROM_UNIXTIME(UNIX_TIMESTAMP(LPAD(CAST(date_operation AS STRING), 8, '0'), 'ddMMyyyy')))
            END                                                                      AS date_jour,
            LPAD(CAST(heure_operation AS STRING), 6, '0')                            AS h6,
            CASE WHEN CAST(val_coupurek7_2 AS INT) = 10 THEN COALESCE(CAST(nb_billetsk7_2 AS INT), 0) ELSE 0 END AS b10,   -- cassette 2
            CASE WHEN CAST(val_coupurek7_3 AS INT) = 20 THEN COALESCE(CAST(nb_billetsk7_3 AS INT), 0) ELSE 0 END AS b20,   -- cassette 3
            CAST(montant_ope AS DOUBLE) / 100                                        AS montant
        FROM `base`.`table_operations_jointe`
        WHERE TRIM(CAST(num_automate AS STRING)) = '000000'                          -- RÉGLAGE : le GAB
          AND TRIM(lib_ope) IN ('Retrait', 'Autorisation-Retrait')
          AND COALESCE(CAST(top_annul AS INT), 0) <> 1
    ) o
) t
WHERE horodatage >= '2026-01-01 12:00:00' AND horodatage < '2026-01-02 18:00:00'     -- RÉGLAGE : la période
  AND b10 + b20 > 0
GROUP BY num_carte
ORDER BY gain_net_du_client DESC
;


-- -----------------------------------------------------------------------------------------------------
-- 5) LE DÉTAIL DES TRANSACTIONS, une ligne par opération (retraits aboutis, inaboutis et captures), dans l'ordre :
--    ce que le client a demandé, les billets de chaque cassette, ce qu'il a VRAIMENT reçu avec l'inversion, l'écart,
--    et le temps depuis le retrait précédent de la même carte (retrait refait).
--    Montant reçu réellement = billets cassette 1 x valeur 1 + billets cassette 2 x 20 € + billets cassette 3 x 10 €
--                              + billets cassette 4 x valeur 4   (les cassettes 2 et 3 inversées)
-- -----------------------------------------------------------------------------------------------------
SELECT
    horodatage,
    num_carte,
    lib_ope,
    CASE WHEN inabouti = 1 THEN 'inabouti' WHEN lib_ope = 'Capture de Carte' THEN 'capture' ELSE 'abouti' END AS statut,
    montant                                                          AS montant_demande,
    CONCAT_WS('/', CAST(v1 AS STRING), CAST(v2 AS STRING), CAST(v3 AS STRING), CAST(v4 AS STRING)) AS plan_declare,
    n1                                                               AS billets_cassette_1,
    n2                                                               AS billets_cassette_2,
    n3                                                               AS billets_cassette_3,
    n4                                                               AS billets_cassette_4,
    n1 * v1 + n2 * v2 + n3 * v3 + n4 * v4                            AS montant_billets_declare,
    n1 * v1 + n2 * 20 + n3 * 10 + n4 * v4                            AS montant_recu_reellement,
    (n1 * v1 + n2 * 20 + n3 * 10 + n4 * v4) - (n1 * v1 + n2 * v2 + n3 * v3 + n4 * v4) AS ecart_client_euros,
    CASE WHEN n2 > n3 THEN 'gagnant' WHEN n2 < n3 THEN 'lésé' ELSE '' END AS bilan,
    ROUND((sec - LAG(sec) OVER (PARTITION BY num_carte ORDER BY sec)) / 60, 1) AS minutes_depuis_meme_carte
FROM (
    SELECT
        CONCAT(CAST(date_jour AS STRING), ' ', SUBSTR(h6, 1, 2), ':', SUBSTR(h6, 3, 2), ':', SUBSTR(h6, 5, 2)) AS horodatage,
        UNIX_TIMESTAMP(CONCAT(CAST(date_jour AS STRING), ' ', SUBSTR(h6, 1, 2), ':', SUBSTR(h6, 3, 2), ':', SUBSTR(h6, 5, 2))) AS sec,
        num_carte, lib_ope, inabouti, montant, v1, v2, v3, v4, n1, n2, n3, n4
    FROM (
        SELECT
            TRIM(CAST(num_carte AS STRING))                                          AS num_carte,
            TRIM(lib_ope)                                                            AS lib_ope,
            CASE WHEN COALESCE(CAST(top_annul AS INT), 0) = 1 THEN 1 ELSE 0 END      AS inabouti,
            CASE WHEN CAST(date_operation AS STRING) LIKE '____-__-__%'
                 THEN TO_DATE(SUBSTR(CAST(date_operation AS STRING), 1, 10))
                 ELSE TO_DATE(FROM_UNIXTIME(UNIX_TIMESTAMP(LPAD(CAST(date_operation AS STRING), 8, '0'), 'ddMMyyyy')))
            END                                                                      AS date_jour,
            LPAD(CAST(heure_operation AS STRING), 6, '0')                            AS h6,
            CAST(montant_ope AS DOUBLE) / 100                                        AS montant,
            COALESCE(CAST(val_coupurek7_1 AS INT), 0) AS v1, COALESCE(CAST(nb_billetsk7_1 AS INT), 0) AS n1,
            COALESCE(CAST(val_coupurek7_2 AS INT), 0) AS v2, COALESCE(CAST(nb_billetsk7_2 AS INT), 0) AS n2,
            COALESCE(CAST(val_coupurek7_3 AS INT), 0) AS v3, COALESCE(CAST(nb_billetsk7_3 AS INT), 0) AS n3,
            COALESCE(CAST(val_coupurek7_4 AS INT), 0) AS v4, COALESCE(CAST(nb_billetsk7_4 AS INT), 0) AS n4
        FROM `base`.`table_operations_jointe`
        WHERE TRIM(CAST(num_automate AS STRING)) = '000000'                          -- RÉGLAGE : le GAB
          AND TRIM(lib_ope) IN ('Retrait', 'Autorisation-Retrait', 'Capture de Carte')
    ) o
) t
WHERE horodatage >= '2026-01-01 12:00:00' AND horodatage < '2026-01-02 18:00:00'     -- RÉGLAGE : la période
ORDER BY horodatage
;


-- -----------------------------------------------------------------------------------------------------
-- 6) JOUR PAR JOUR : la même synthèse, une ligne par jour (retraits, clients, euros)
--    Un client est compté gagnant / lésé sur son bilan de la journée.
-- -----------------------------------------------------------------------------------------------------
SELECT
    date_jour,
    SUM(nb_retraits)                                                 AS retraits_aboutis,
    SUM(nb_retraits_concernes)                                       AS retraits_concernes,
    SUM(CASE WHEN nb_retraits_concernes > 0 THEN 1 ELSE 0 END)       AS clients_concernes,
    SUM(CASE WHEN net > 0 THEN 1 ELSE 0 END)                         AS clients_gagnants,
    SUM(CASE WHEN net < 0 THEN 1 ELSE 0 END)                         AS clients_leses,
    SUM(trop)                                                        AS euros_donnes_en_trop,
    SUM(moins)                                                       AS euros_donnes_en_moins,
    SUM(net)                                                         AS perte_nette_banque_euros,
    SUM(CASE WHEN nb_retraits_concernes >= 2 THEN 1 ELSE 0 END)      AS clients_revenus_plusieurs_fois
FROM (
    -- une ligne par client et par jour
    SELECT
        date_jour,
        num_carte,
        COUNT(*)                                                     AS nb_retraits,
        SUM(CASE WHEN b10 + b20 > 0 THEN 1 ELSE 0 END)               AS nb_retraits_concernes,
        SUM(10 * b10)                                                AS trop,
        SUM(10 * b20)                                                AS moins,
        SUM(10 * (b10 - b20))                                        AS net
    FROM (
        SELECT
            TRIM(CAST(num_carte AS STRING))                                          AS num_carte,
            CASE WHEN CAST(date_operation AS STRING) LIKE '____-__-__%'
                 THEN TO_DATE(SUBSTR(CAST(date_operation AS STRING), 1, 10))
                 ELSE TO_DATE(FROM_UNIXTIME(UNIX_TIMESTAMP(LPAD(CAST(date_operation AS STRING), 8, '0'), 'ddMMyyyy')))
            END                                                                      AS date_jour,
            CASE WHEN CAST(val_coupurek7_2 AS INT) = 10 THEN COALESCE(CAST(nb_billetsk7_2 AS INT), 0) ELSE 0 END AS b10,   -- cassette 2
            CASE WHEN CAST(val_coupurek7_3 AS INT) = 20 THEN COALESCE(CAST(nb_billetsk7_3 AS INT), 0) ELSE 0 END AS b20    -- cassette 3
        FROM `base`.`table_operations_jointe`
        WHERE TRIM(CAST(num_automate AS STRING)) = '000000'                          -- RÉGLAGE : le GAB
          AND TRIM(lib_ope) IN ('Retrait', 'Autorisation-Retrait')
          AND COALESCE(CAST(top_annul AS INT), 0) <> 1
    ) o
    WHERE date_jour BETWEEN '2025-12-31' AND '2026-01-03'                        -- RÉGLAGE : les jours
    GROUP BY date_jour, num_carte
) c
GROUP BY date_jour
ORDER BY date_jour
;
