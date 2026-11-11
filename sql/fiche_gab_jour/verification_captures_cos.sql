-- =====================================================================================================
-- VÉRIFICATION : que sont les « CAPTURE CARTE COS » ?
-- Hypothèse : une carte COS (one shot) est avalée normalement après le retrait, mais cette capture normale
-- seraient donc les cartes avalées SANS retrait (délai de 45 min dépassé, etc.).
--
-- Lecture du résultat (3 lignes) :
--   cas 1 = la carte capturée n'a fait AUCUN retrait COS abouti ce jour-là sur ce GAB  -> retrait raté (hypothèse confirmée)
--   cas 2 = la carte a fait un retrait COS AVANT la capture                            -> capture normale enregistrée
--   cas 3 = la carte a fait un retrait COS APRÈS la capture                            -> bizarre, à regarder
-- Si le cas 1 domine largement, « capture carte COS » = retrait COS raté, et nb_capture_capture_cos devient
-- un vrai signal de service client dans la fiche.
-- Période : août à octobre 2026 (modifier la liste IN dans les 2 WHERE).
-- =====================================================================================================
SELECT
    cas,
    COUNT(*)                                   AS nb_captures,
    ROUND(AVG(ecart_min), 1)                   AS ecart_moyen_min,
    PERCENTILE_APPROX(ecart_min, 0.5)          AS ecart_median_min,
    COUNT(DISTINCT num_automate)               AS nb_gab
FROM (
    SELECT
        c.num_automate,
        CASE WHEN r.num_carte IS NULL                      THEN '1. capture COS sans retrait COS de la même carte ce jour-là'
             WHEN c.sec_capture >= r.sec_dernier_retrait   THEN '2. retrait COS AVANT la capture (capture normale)'
             ELSE                                               '3. retrait COS APRÈS la capture' END AS cas,
        CASE WHEN r.num_carte IS NULL                      THEN NULL
             WHEN c.sec_capture >= r.sec_dernier_retrait   THEN (c.sec_capture - r.sec_dernier_retrait) / 60.0
             ELSE                                               (r.sec_premier_retrait - c.sec_capture) / 60.0 END AS ecart_min
    FROM (
        -- les captures de motif « capture carte COS »
        SELECT
            num_automate, num_carte, date_operation,
            CAST(SUBSTR(LPAD(CAST(heure_operation AS STRING), 6, '0'), 1, 2) AS INT) * 3600
          + CAST(SUBSTR(LPAD(CAST(heure_operation AS STRING), 6, '0'), 3, 2) AS INT) * 60
          + CAST(SUBSTR(LPAD(CAST(heure_operation AS STRING), 6, '0'), 5, 2) AS INT) AS sec_capture
        FROM `base`.`table_operations`
        WHERE TRIM(lib_ope) = 'Capture de Carte'
          AND UPPER(TRIM(lib_motif_capture_carte)) LIKE 'CAPTURE CARTE COS%'
          AND SUBSTR(date_operation, 3, 6) IN ('082026', '092026', '102026')
    ) c
    LEFT JOIN (
        -- les retraits COS aboutis, résumés par GAB x carte x jour
        SELECT
            num_automate, num_carte, date_operation,
            MIN(sec) AS sec_premier_retrait,
            MAX(sec) AS sec_dernier_retrait
        FROM (
            SELECT
                num_automate, num_carte, date_operation,
                CAST(SUBSTR(LPAD(CAST(heure_operation AS STRING), 6, '0'), 1, 2) AS INT) * 3600
              + CAST(SUBSTR(LPAD(CAST(heure_operation AS STRING), 6, '0'), 3, 2) AS INT) * 60
              + CAST(SUBSTR(LPAD(CAST(heure_operation AS STRING), 6, '0'), 5, 2) AS INT) AS sec
            FROM `base`.`table_operations`
            WHERE TRIM(lib_ope) = 'Retrait'
              AND CAST(top_annul AS INT) = 0
              AND SUBSTR(date_operation, 3, 6) IN ('082026', '092026', '102026')
        ) x
        GROUP BY num_automate, num_carte, date_operation
    ) r
      ON  c.num_automate   = r.num_automate
     AND c.num_carte      = r.num_carte
     AND c.date_operation = r.date_operation
) t
GROUP BY cas
ORDER BY cas
