-- =====================================================================================================
-- RÉSEAUX EXOTIQUES PAR MOIS (UnionPay, Diners, Amex, JCB), sur la fiche GAB x jour (rapide)
-- Une ligne par mois : pour chaque réseau, les retraits aboutis, le montant, les inaboutis, les captures,
-- et le nombre de GAB distincts qui en ont vu au moins un.
-- Remplacer `base`.`fiche_jour` par le nom du dataset de la fiche.
-- =====================================================================================================
SELECT
    annee,
    mois,
    COUNT(DISTINCT date_jour)                                        AS jours,
    -- UnionPay (réseau 10 + CUP)
    SUM(nb_ret_cup)                                                  AS upi_retraits,
    ROUND(SUM(montant_cup))                                          AS upi_montant_euros,
    SUM(nb_inab_cup)                                                 AS upi_inaboutis,
    SUM(nb_cap_cup)                                                  AS upi_captures,
    COUNT(DISTINCT CASE WHEN nb_ret_cup > 0 THEN num_automate END)   AS upi_gab_distincts,
    -- Diners (réseau 10 + DIN)
    SUM(nb_ret_diners)                                               AS diners_retraits,
    ROUND(SUM(montant_diners))                                       AS diners_montant_euros,
    SUM(nb_inab_diners)                                              AS diners_inaboutis,
    SUM(nb_cap_diners)                                               AS diners_captures,
    COUNT(DISTINCT CASE WHEN nb_ret_diners > 0 THEN num_automate END) AS diners_gab_distincts,
    -- Amex (réseau 07)
    SUM(nb_ret_amex)                                                 AS amex_retraits,
    ROUND(SUM(montant_amex))                                         AS amex_montant_euros,
    SUM(nb_inab_amex)                                                AS amex_inaboutis,
    SUM(nb_cap_amex)                                                 AS amex_captures,
    COUNT(DISTINCT CASE WHEN nb_ret_amex > 0 THEN num_automate END)  AS amex_gab_distincts,
    -- JCB (réseau 12)
    SUM(nb_ret_jcb)                                                  AS jcb_retraits,
    ROUND(SUM(montant_jcb))                                          AS jcb_montant_euros,
    SUM(nb_inab_jcb)                                                 AS jcb_inaboutis,
    SUM(nb_cap_jcb)                                                  AS jcb_captures,
    COUNT(DISTINCT CASE WHEN nb_ret_jcb > 0 THEN num_automate END)   AS jcb_gab_distincts,
    -- total des 4 réseaux (chaque retrait compté une seule fois) et part dans tous les retraits
    SUM(nb_ret_exotique)                                             AS exotiques_retraits,
    ROUND(SUM(montant_exotique))                                     AS exotiques_montant_euros,
    ROUND(100 * SUM(nb_ret_exotique) / SUM(nb_retraits), 3)          AS exotiques_part_des_retraits_pct
FROM `base`.`fiche_jour`
GROUP BY annee, mois
ORDER BY annee, mois
;
