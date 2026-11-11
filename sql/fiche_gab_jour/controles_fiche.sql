-- =====================================================================================================
-- CONTRÔLES DE COHÉRENCE DE LA FICHE : la table brute agrégée doit redonner EXACTEMENT les chiffres de la fiche
-- À lancer après la fiche sur octobre 2026 (fiche produite avec les deux filtres -- TEST).
-- Trois requêtes indépendantes, à lancer l'une après l'autre (chacune renvoie un petit tableau).
--   Contrôle 1 : totaux du mois, brut contre fiche (2 lignes, mêmes colonnes : tout doit être identique)
--   Contrôle 2 : GAB x jour, brut contre fiche : nombre de couples qui diffèrent (tout doit être à 0)
--   Contrôle 3 : les 30 premiers couples GAB x jour qui diffèrent, s'il y en a (pour comprendre)
-- Pour un autre mois : remplacer 102026 (brut) et mois = 10 / annee = 2026 (fiche) partout.
-- =====================================================================================================


-- -----------------------------------------------------------------------------------------------------
-- CONTRÔLE 1 : totaux du mois. Ligne « brut » = calcul direct sur la table brute ; ligne « fiche » = somme de la fiche.
-- -----------------------------------------------------------------------------------------------------
SELECT 'brut' AS source,
       COUNT(*)                                                                             AS nb_lignes,
       SUM(CASE WHEN TRIM(lib_ope) <> 'Capture de Carte' THEN 1 ELSE 0 END)               AS nb_retraits_tentes,
       SUM(CASE WHEN TRIM(lib_ope) <> 'Capture de Carte' AND COALESCE(CAST(top_annul AS INT), 0) = 0 THEN 1 ELSE 0 END) AS nb_retraits,
       SUM(CASE WHEN TRIM(lib_ope) = 'Retrait' AND COALESCE(CAST(top_annul AS INT), 0) = 0 THEN 1 ELSE 0 END)            AS nb_retraits_cos,
       SUM(CASE WHEN TRIM(lib_ope) <> 'Capture de Carte' AND CAST(top_annul AS INT) = 1 THEN 1 ELSE 0 END)                AS nb_inaboutis,
       SUM(CASE WHEN TRIM(lib_ope) = 'Capture de Carte' THEN 1 ELSE 0 END)                AS nb_captures,
       SUM(CASE WHEN TRIM(lib_ope) = 'Capture de Carte'
                 AND UPPER(TRIM(lib_motif_capture_carte)) LIKE 'CAPTURE CARTE COS%' THEN 1 ELSE 0 END) AS nb_capture_capture_cos,
       ROUND(SUM(CASE WHEN TRIM(lib_ope) <> 'Capture de Carte' AND COALESCE(CAST(top_annul AS INT), 0) = 0
                      THEN CAST(montant_ope AS DOUBLE) / 100 ELSE 0 END), 0)               AS montant_total,
       SUM(CASE WHEN TRIM(lib_ope) <> 'Capture de Carte' AND COALESCE(CAST(top_annul AS INT), 0) = 0
                THEN COALESCE(CAST(nb_billetsk7_1 AS INT), 0) + COALESCE(CAST(nb_billetsk7_2 AS INT), 0)
                   + COALESCE(CAST(nb_billetsk7_3 AS INT), 0) + COALESCE(CAST(nb_billetsk7_4 AS INT), 0) ELSE 0 END) AS nb_billets_total,
       SUM(CASE WHEN TRIM(lib_ope) <> 'Capture de Carte' AND COALESCE(CAST(top_annul AS INT), 0) = 0 THEN
                  CASE WHEN CAST(val_coupurek7_1 AS INT) = 20 THEN COALESCE(CAST(nb_billetsk7_1 AS INT), 0) ELSE 0 END
                + CASE WHEN CAST(val_coupurek7_2 AS INT) = 20 THEN COALESCE(CAST(nb_billetsk7_2 AS INT), 0) ELSE 0 END
                + CASE WHEN CAST(val_coupurek7_3 AS INT) = 20 THEN COALESCE(CAST(nb_billetsk7_3 AS INT), 0) ELSE 0 END
                + CASE WHEN CAST(val_coupurek7_4 AS INT) = 20 THEN COALESCE(CAST(nb_billetsk7_4 AS INT), 0) ELSE 0 END
                ELSE 0 END)                                                                 AS nb_billets_20,
       SUM(CASE WHEN TRIM(lib_ope) <> 'Capture de Carte' AND COALESCE(CAST(top_annul AS INT), 0) = 0
                 AND LPAD(TRIM(CAST(type_reseau AS STRING)), 2, '0') = '03' THEN 1 ELSE 0 END) AS nb_ret_interne,
       SUM(CASE WHEN TRIM(lib_ope) <> 'Capture de Carte' AND COALESCE(CAST(top_annul AS INT), 0) = 0
                 AND LPAD(TRIM(CAST(type_reseau AS STRING)), 2, '0') = '00' THEN 1 ELSE 0 END) AS nb_ret_cb,
       SUM(CASE WHEN TRIM(lib_ope) <> 'Capture de Carte' AND COALESCE(CAST(top_annul AS INT), 0) = 0
                 AND (CAST(SUBSTR(LPAD(CAST(heure_operation AS STRING), 6, '0'), 1, 2) AS INT) >= 22
                   OR CAST(SUBSTR(LPAD(CAST(heure_operation AS STRING), 6, '0'), 1, 2) AS INT) < 6) THEN 1 ELSE 0 END) AS nb_nuit_22h_6h,
       COUNT(DISTINCT TRIM(CAST(num_automate AS STRING)))                                   AS nb_gab,
       COUNT(DISTINCT date_operation)                                                       AS nb_jours
FROM `base`.`table_operations`
WHERE TRIM(lib_ope) IN ('Retrait', 'Autorisation-Retrait', 'Capture de Carte')
  AND date_operation LIKE '__102026'

UNION ALL

SELECT 'fiche' AS source,
       SUM(nb_lignes)                 AS nb_lignes,
       SUM(nb_retraits_tentes)        AS nb_retraits_tentes,
       SUM(nb_retraits)               AS nb_retraits,
       SUM(nb_retraits_cos)           AS nb_retraits_cos,
       SUM(nb_inaboutis)              AS nb_inaboutis,
       SUM(nb_captures)               AS nb_captures,
       SUM(nb_capture_capture_cos)    AS nb_capture_capture_cos,
       ROUND(SUM(montant_total), 0)   AS montant_total,
       SUM(nb_billets_total)          AS nb_billets_total,
       SUM(nb_billets_20)             AS nb_billets_20,
       SUM(nb_ret_interne)            AS nb_ret_interne,
       SUM(nb_ret_cb)                 AS nb_ret_cb,
       SUM(nb_nuit_22h_6h)            AS nb_nuit_22h_6h,
       COUNT(DISTINCT num_automate)   AS nb_gab,
       COUNT(DISTINCT CASE WHEN jour_sans_ligne = 0 THEN date_jour END) AS nb_jours
FROM `fiche_gab_jour`
WHERE annee = 2026 AND mois = 10;


-- -----------------------------------------------------------------------------------------------------
-- CONTRÔLE 2 : GAB x jour. On agrège la table brute par GAB et par jour, on joint à la fiche, on compte les écarts.
-- Attendu : nb_brut_sans_fiche = 0 (toute journée avec des opérations est dans la fiche),
--           nb_ecarts_retraits = 0, nb_ecarts_montant = 0, nb_ecarts_captures = 0.
--           nb_fiche_sans_brut = journées sans aucune opération (c'est normal : la fiche les complète à 0),
--           et il doit être égal à nb_jours_sans_ligne.
-- -----------------------------------------------------------------------------------------------------
SELECT
    COUNT(*)                                                                    AS nb_couples_gab_jour,
    SUM(CASE WHEN b.num_automate IS NULL THEN 1 ELSE 0 END)                     AS nb_fiche_sans_brut,
    SUM(CASE WHEN b.num_automate IS NULL AND f.jour_sans_ligne = 1 THEN 1 ELSE 0 END) AS nb_jours_sans_ligne,
    SUM(CASE WHEN f.num_automate IS NULL THEN 1 ELSE 0 END)                     AS nb_brut_sans_fiche,
    SUM(CASE WHEN b.num_automate IS NOT NULL AND f.num_automate IS NOT NULL
              AND b.nb_retraits <> f.nb_retraits THEN 1 ELSE 0 END)             AS nb_ecarts_retraits,
    SUM(CASE WHEN b.num_automate IS NOT NULL AND f.num_automate IS NOT NULL
              AND ABS(b.montant_total - f.montant_total) > 0.01 THEN 1 ELSE 0 END) AS nb_ecarts_montant,
    SUM(CASE WHEN b.num_automate IS NOT NULL AND f.num_automate IS NOT NULL
              AND b.nb_captures <> f.nb_captures THEN 1 ELSE 0 END)             AS nb_ecarts_captures,
    SUM(CASE WHEN b.num_automate IS NOT NULL AND f.num_automate IS NOT NULL
              AND b.nb_billets_total <> f.nb_billets_total THEN 1 ELSE 0 END)   AS nb_ecarts_billets
FROM (
    SELECT num_automate, date_jour, nb_retraits, montant_total, nb_captures, nb_billets_total, jour_sans_ligne
    FROM `fiche_gab_jour`
    WHERE annee = 2026 AND mois = 10
) f
FULL OUTER JOIN (
    SELECT
        TRIM(CAST(num_automate AS STRING)) AS num_automate,
        CAST(TO_DATE(FROM_UNIXTIME(UNIX_TIMESTAMP(LPAD(CAST(date_operation AS STRING), 8, '0'), 'ddMMyyyy'))) AS STRING) AS date_jour,
        SUM(CASE WHEN TRIM(lib_ope) <> 'Capture de Carte' AND COALESCE(CAST(top_annul AS INT), 0) = 0 THEN 1 ELSE 0 END) AS nb_retraits,
        SUM(CASE WHEN TRIM(lib_ope) <> 'Capture de Carte' AND COALESCE(CAST(top_annul AS INT), 0) = 0
                 THEN CAST(montant_ope AS DOUBLE) / 100 ELSE 0 END)                                                   AS montant_total,
        SUM(CASE WHEN TRIM(lib_ope) = 'Capture de Carte' THEN 1 ELSE 0 END)                                            AS nb_captures,
        SUM(CASE WHEN TRIM(lib_ope) <> 'Capture de Carte' AND COALESCE(CAST(top_annul AS INT), 0) = 0
                 THEN COALESCE(CAST(nb_billetsk7_1 AS INT), 0) + COALESCE(CAST(nb_billetsk7_2 AS INT), 0)
                    + COALESCE(CAST(nb_billetsk7_3 AS INT), 0) + COALESCE(CAST(nb_billetsk7_4 AS INT), 0) ELSE 0 END) AS nb_billets_total
    FROM `base`.`table_operations`
    WHERE TRIM(lib_ope) IN ('Retrait', 'Autorisation-Retrait', 'Capture de Carte')
      AND date_operation LIKE '__102026'
    GROUP BY TRIM(CAST(num_automate AS STRING)),
             CAST(TO_DATE(FROM_UNIXTIME(UNIX_TIMESTAMP(LPAD(CAST(date_operation AS STRING), 8, '0'), 'ddMMyyyy'))) AS STRING)
) b
  ON  f.num_automate = b.num_automate
 AND CAST(f.date_jour AS STRING) = b.date_jour;


-- -----------------------------------------------------------------------------------------------------
-- CONTRÔLE 3 : les 30 premiers couples GAB x jour en écart, pour voir d'où ça vient (à lancer seulement si le
-- contrôle 2 montre des écarts).
-- -----------------------------------------------------------------------------------------------------
SELECT
    COALESCE(f.num_automate, b.num_automate) AS num_automate,
    COALESCE(CAST(f.date_jour AS STRING), b.date_jour) AS date_jour,
    f.nb_retraits  AS retraits_fiche,  b.nb_retraits  AS retraits_brut,
    f.montant_total AS montant_fiche,  b.montant_total AS montant_brut,
    f.nb_captures  AS captures_fiche,  b.nb_captures  AS captures_brut,
    CASE WHEN f.num_automate IS NULL THEN 'absent de la fiche'
         WHEN b.num_automate IS NULL THEN 'absent du brut (journée à 0)'
         ELSE 'chiffres différents' END AS cas
FROM (
    SELECT num_automate, date_jour, nb_retraits, montant_total, nb_captures
    FROM `fiche_gab_jour`
    WHERE annee = 2026 AND mois = 10 AND jour_sans_ligne = 0
) f
FULL OUTER JOIN (
    SELECT
        TRIM(CAST(num_automate AS STRING)) AS num_automate,
        CAST(TO_DATE(FROM_UNIXTIME(UNIX_TIMESTAMP(LPAD(CAST(date_operation AS STRING), 8, '0'), 'ddMMyyyy'))) AS STRING) AS date_jour,
        SUM(CASE WHEN TRIM(lib_ope) <> 'Capture de Carte' AND COALESCE(CAST(top_annul AS INT), 0) = 0 THEN 1 ELSE 0 END) AS nb_retraits,
        SUM(CASE WHEN TRIM(lib_ope) <> 'Capture de Carte' AND COALESCE(CAST(top_annul AS INT), 0) = 0
                 THEN CAST(montant_ope AS DOUBLE) / 100 ELSE 0 END)                                                   AS montant_total,
        SUM(CASE WHEN TRIM(lib_ope) = 'Capture de Carte' THEN 1 ELSE 0 END)                                            AS nb_captures
    FROM `base`.`table_operations`
    WHERE TRIM(lib_ope) IN ('Retrait', 'Autorisation-Retrait', 'Capture de Carte')
      AND date_operation LIKE '__102026'
    GROUP BY TRIM(CAST(num_automate AS STRING)),
             CAST(TO_DATE(FROM_UNIXTIME(UNIX_TIMESTAMP(LPAD(CAST(date_operation AS STRING), 8, '0'), 'ddMMyyyy'))) AS STRING)
) b
  ON  f.num_automate = b.num_automate
 AND CAST(f.date_jour AS STRING) = b.date_jour
WHERE f.num_automate IS NULL OR b.num_automate IS NULL
   OR f.nb_retraits <> b.nb_retraits OR ABS(f.montant_total - b.montant_total) > 0.01 OR f.nb_captures <> b.nb_captures
LIMIT 30
