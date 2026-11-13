-- =====================================================================================================
-- CANDIDATS POUR LE CAS « EFFET WOW » DE LA PRÉSENTATION. Deux requêtes indépendantes, sur la fiche GAB x jour
-- (et la recette voisins_gab pour la seconde). Toute la période ; ajouter AND annee = 2026 pour un an.
--   A) Attaque coordonnée (catalogue n° 20) : le même jour, >= 3 GAB du même département avec >= 5 retraits du même
--      réseau étranger, alors que chacun n'en voit presque jamais (habitude < 0,5 par jour). Chaque GAB seul = un
--      groupe de touristes ; les trois ensemble = une tournée de cartes.
--   B) Incident de zone + report (n° 19 / 20 du catalogue voisins) : un jour où >= 3 GAB voisins (< 3 km) qui font
--      d'habitude >= 20 retraits sont tous à 0 ensemble, et le voisin resté debout qui a absorbé leurs clients.
-- =====================================================================================================

-- -----------------------------------------------------------------------------------------------------
-- A) Attaque coordonnée : date, département, réseau, GAB concernés, et l'habitude de chacun (pour la diapo)
-- -----------------------------------------------------------------------------------------------------
SELECT
    r.date_jour,
    r.departement,
    r.reseau,
    COUNT(*)                                                      AS nb_gab_en_rafale,
    SUM(r.nb)                                                     AS retraits_cumules,
    ROUND(MAX(h.habitude), 2)                                     AS habitude_max_par_jour,     -- si < 0,5 : aucun des GAB n'en voit d'habitude
    CONCAT_WS(' | ', COLLECT_LIST(CONCAT(r.num_automate, ' ', r.ville, ' : ', CAST(r.nb AS STRING),
                                         ' (hab ', CAST(ROUND(h.habitude, 2) AS STRING), ')'))) AS detail_gab
FROM (
    SELECT num_automate, ville, date_jour, SUBSTR(LPAD(CAST(code_postal AS STRING), 5, '0'), 1, 2) AS departement, 'UnionPay (UPI)' AS reseau, nb_ret_cup AS nb FROM `fiche_gab_jour`
    UNION ALL
    SELECT num_automate, ville, date_jour, SUBSTR(LPAD(CAST(code_postal AS STRING), 5, '0'), 1, 2), 'American Express', nb_ret_amex FROM `fiche_gab_jour`
    UNION ALL
    SELECT num_automate, ville, date_jour, SUBSTR(LPAD(CAST(code_postal AS STRING), 5, '0'), 1, 2), 'Diners', nb_ret_diners FROM `fiche_gab_jour`
    UNION ALL
    SELECT num_automate, ville, date_jour, SUBSTR(LPAD(CAST(code_postal AS STRING), 5, '0'), 1, 2), 'JCB', nb_ret_jcb FROM `fiche_gab_jour`
) r
JOIN (
    -- habitude par GAB et par réseau : moyenne par jour sur toute la fiche
    SELECT num_automate, 'UnionPay (UPI)' AS reseau, AVG(nb_ret_cup) AS habitude FROM `fiche_gab_jour` GROUP BY num_automate
    UNION ALL
    SELECT num_automate, 'American Express', AVG(nb_ret_amex) FROM `fiche_gab_jour` GROUP BY num_automate
    UNION ALL
    SELECT num_automate, 'Diners', AVG(nb_ret_diners) FROM `fiche_gab_jour` GROUP BY num_automate
    UNION ALL
    SELECT num_automate, 'JCB', AVG(nb_ret_jcb) FROM `fiche_gab_jour` GROUP BY num_automate
) h ON h.num_automate = r.num_automate AND h.reseau = r.reseau
WHERE r.nb >= 5
GROUP BY r.date_jour, r.departement, r.reseau
HAVING COUNT(*) >= 3
ORDER BY nb_gab_en_rafale DESC, habitude_max_par_jour ASC, retraits_cumules DESC
LIMIT 40
;

-- -----------------------------------------------------------------------------------------------------
-- B) Incident de zone : un GAB à 0 dont >= 2 voisins sont aussi à 0 le même jour (donc >= 3 GAB voisins à l'arrêt),
--    tous habitués à >= 20 retraits par jour ; et le voisin resté actif le plus en hausse ce jour-là (report)
-- -----------------------------------------------------------------------------------------------------
SELECT
    z.date_jour,
    z.num_automate                               AS gab_a_zero,
    z.ville,
    z.nb_voisins_a_zero,
    z.voisins_a_zero,
    rp.voisin                                    AS voisin_reste_actif,
    rp.nb_retraits                               AS ses_retraits_ce_jour,
    ROUND(rp.habitude, 1)                        AS son_habitude,
    ROUND(rp.nb_retraits / rp.habitude, 2)       AS ratio_report               -- > 1,5 : il a absorbé les clients
FROM (
    -- le GAB à 0 et ses voisins à 0 le même jour
    SELECT
        f.date_jour, f.num_automate, f.ville,
        COUNT(*)                                       AS nb_voisins_a_zero,
        CONCAT_WS(', ', COLLECT_LIST(fv.num_automate)) AS voisins_a_zero
    FROM `fiche_gab_jour` f
    JOIN (SELECT num_automate, AVG(nb_retraits) AS habitude FROM `fiche_gab_jour` GROUP BY num_automate) h
        ON h.num_automate = f.num_automate AND h.habitude >= 20
    JOIN `voisins_gab` v ON v.num_automate = f.num_automate
    JOIN `fiche_gab_jour` fv ON fv.num_automate = v.voisin AND fv.date_jour = f.date_jour AND fv.jour_sans_retrait = 1
    JOIN (SELECT num_automate, AVG(nb_retraits) AS habitude FROM `fiche_gab_jour` GROUP BY num_automate) hv
        ON hv.num_automate = fv.num_automate AND hv.habitude >= 20
    WHERE f.jour_sans_retrait = 1
    GROUP BY f.date_jour, f.num_automate, f.ville
    HAVING COUNT(*) >= 2
) z
LEFT JOIN (
    -- parmi les voisins restés actifs ce jour-là, celui dont les retraits sont le plus au-dessus de son habitude
    SELECT date_jour, num_automate, voisin, nb_retraits, habitude,
           ROW_NUMBER() OVER (PARTITION BY date_jour, num_automate ORDER BY nb_retraits / habitude DESC) AS rg
    FROM (
        SELECT f.date_jour, f.num_automate, v.voisin, fv.nb_retraits, h.habitude
        FROM `fiche_gab_jour` f
        JOIN `voisins_gab` v ON v.num_automate = f.num_automate
        JOIN `fiche_gab_jour` fv ON fv.num_automate = v.voisin AND fv.date_jour = f.date_jour AND fv.nb_retraits > 0
        JOIN (SELECT num_automate, AVG(nb_retraits) AS habitude FROM `fiche_gab_jour` GROUP BY num_automate) h
            ON h.num_automate = fv.num_automate AND h.habitude >= 10
        WHERE f.jour_sans_retrait = 1
    ) a
) rp ON rp.date_jour = z.date_jour AND rp.num_automate = z.num_automate AND rp.rg = 1
ORDER BY z.nb_voisins_a_zero DESC, ratio_report DESC
LIMIT 40
;
