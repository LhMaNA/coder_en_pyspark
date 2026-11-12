-- =====================================================================================================
-- RÉSEAUX EXOTIQUES (UnionPay/UPI, American Express, Diners, JCB) : combien, où, quand ?
-- Sur la fiche (une ligne par GAB et par jour), donc rapide. Deux requêtes indépendantes.
--   1) le niveau du parc, réseau par réseau : par jour en moyenne, le maximum, et combien de GAB-jours dépassent 3, 5, 10
--   2) les 40 GAB-jours les plus chargés, avec le nom du réseau, le nombre, et l'habitude du GAB (sa moyenne par jour
--      sur toute la période) : ce sont les candidats à notifier
-- Période : toute la fiche ; pour un mois, ajouter  AND annee = 2026 AND mois = 10  dans les WHERE.
-- =====================================================================================================

-- -----------------------------------------------------------------------------------------------------
-- 1) Niveau du parc par réseau exotique
-- -----------------------------------------------------------------------------------------------------
SELECT
    reseau,
    SUM(nb)                                                   AS retraits_total,
    ROUND(SUM(nb) / COUNT(DISTINCT date_jour), 2)             AS retraits_par_jour_parc,
    SUM(CASE WHEN nb > 0 THEN 1 ELSE 0 END)                   AS gab_jours_avec_au_moins_1,
    COUNT(DISTINCT CASE WHEN nb > 0 THEN num_automate END)    AS gab_concernes,
    SUM(CASE WHEN nb >= 3  THEN 1 ELSE 0 END)                 AS gab_jours_3_ou_plus,
    SUM(CASE WHEN nb >= 5  THEN 1 ELSE 0 END)                 AS gab_jours_5_ou_plus,
    SUM(CASE WHEN nb >= 10 THEN 1 ELSE 0 END)                 AS gab_jours_10_ou_plus,
    MAX(nb)                                                   AS maximum_sur_un_gab_jour
FROM (
    SELECT num_automate, date_jour, 'UnionPay (UPI)' AS reseau, nb_ret_cup    AS nb FROM `fiche_jour`
    UNION ALL
    SELECT num_automate, date_jour, 'American Express',        nb_ret_amex   FROM `fiche_jour`
    UNION ALL
    SELECT num_automate, date_jour, 'Diners',                  nb_ret_diners FROM `fiche_jour`
    UNION ALL
    SELECT num_automate, date_jour, 'JCB',                     nb_ret_jcb    FROM `fiche_jour`
) t
GROUP BY reseau
ORDER BY retraits_total DESC;


-- -----------------------------------------------------------------------------------------------------
-- 2) Les 40 GAB-jours les plus chargés en cartes exotiques, avec l'habitude du GAB
-- -----------------------------------------------------------------------------------------------------
SELECT
    t.num_automate,
    t.code_site_implantation,
    t.ville,
    t.date_jour,
    t.reseau,
    t.nb                                                     AS retraits_ce_jour,
    ROUND(h.moyenne_par_jour, 2)                             AS habitude_du_gab_par_jour,
    ROUND(t.nb / GREATEST(h.moyenne_par_jour, 0.05), 1)      AS fois_l_habitude,
    t.nb_retraits                                            AS retraits_du_jour_tous_reseaux
FROM (
    SELECT num_automate, code_site_implantation, ville, date_jour, nb_retraits, 'UnionPay (UPI)' AS reseau, nb_ret_cup AS nb FROM `fiche_jour`
    UNION ALL
    SELECT num_automate, code_site_implantation, ville, date_jour, nb_retraits, 'American Express', nb_ret_amex FROM `fiche_jour`
    UNION ALL
    SELECT num_automate, code_site_implantation, ville, date_jour, nb_retraits, 'Diners', nb_ret_diners FROM `fiche_jour`
    UNION ALL
    SELECT num_automate, code_site_implantation, ville, date_jour, nb_retraits, 'JCB', nb_ret_jcb FROM `fiche_jour`
) t
JOIN (
    -- habitude : moyenne par jour de chaque GAB pour chaque réseau, sur toute la période
    SELECT num_automate, 'UnionPay (UPI)' AS reseau, AVG(nb_ret_cup) AS moyenne_par_jour FROM `fiche_jour` GROUP BY num_automate
    UNION ALL
    SELECT num_automate, 'American Express', AVG(nb_ret_amex) FROM `fiche_jour` GROUP BY num_automate
    UNION ALL
    SELECT num_automate, 'Diners', AVG(nb_ret_diners) FROM `fiche_jour` GROUP BY num_automate
    UNION ALL
    SELECT num_automate, 'JCB', AVG(nb_ret_jcb) FROM `fiche_jour` GROUP BY num_automate
) h
  ON h.num_automate = t.num_automate AND h.reseau = t.reseau
WHERE t.nb >= 3
ORDER BY t.nb DESC, fois_l_habitude DESC
LIMIT 40
;

-- -----------------------------------------------------------------------------------------------------
-- 3) Rafales coordonnées : jours où plusieurs GAB d'un même département ont eu >= 5 retraits du même réseau
--    exotique (catalogue n° 20, attaque coordonnée). Une rafale isolée peut être un groupe de touristes ;
--    la même rafale sur 3 GAB du même département le même jour ressemble à une fraude organisée.
-- -----------------------------------------------------------------------------------------------------
SELECT
    date_jour,
    departement,
    reseau,
    COUNT(*)                                   AS nb_gab_en_rafale,
    SUM(nb)                                    AS retraits_cumules,
    CONCAT_WS(', ', COLLECT_LIST(num_automate)) AS gab
FROM (
    SELECT num_automate, date_jour, SUBSTR(LPAD(CAST(code_postal AS STRING), 5, '0'), 1, 2) AS departement, 'UnionPay (UPI)' AS reseau, nb_ret_cup AS nb FROM `fiche_jour`
    UNION ALL
    SELECT num_automate, date_jour, SUBSTR(LPAD(CAST(code_postal AS STRING), 5, '0'), 1, 2), 'American Express', nb_ret_amex FROM `fiche_jour`
    UNION ALL
    SELECT num_automate, date_jour, SUBSTR(LPAD(CAST(code_postal AS STRING), 5, '0'), 1, 2), 'Diners', nb_ret_diners FROM `fiche_jour`
    UNION ALL
    SELECT num_automate, date_jour, SUBSTR(LPAD(CAST(code_postal AS STRING), 5, '0'), 1, 2), 'JCB', nb_ret_jcb FROM `fiche_jour`
) t
WHERE nb >= 5
GROUP BY date_jour, departement, reseau
HAVING COUNT(*) >= 2
ORDER BY nb_gab_en_rafale DESC, retraits_cumules DESC
LIMIT 40
