-- =====================================================================================================
-- FICHE D'IDENTITÉ GAB x JOUR, en une seule requête (180 colonnes, voir dictionnaire_fiche_gab_jour.csv)
-- Entrées : table des opérations brutes + référentiel GAB final (sortie de la recette BAN)
-- Sortie  : une ligne par GAB et par jour, du premier jour d'opération du GAB jusqu'à la fin des données
--           (jusqu'à son dernier jour d'opération s'il est FERME), y compris les jours sans opération (0).
--           Les GAB présents dans les opérations mais absents du référentiel sont gardés (dans_referentiel = 0).
-- Lecture : la table des opérations est lue 2 fois : une fois pour les bornes de chaque GAB (3 colonnes,
--           GROUP BY GAB, rapide), une fois pour les agrégats. 3 fonctions de fenêtre au niveau opération.
-- Test    : ajouter AND date_operation LIKE '__102026' dans les 2 WHERE marqués -- TEST pour un seul mois.
-- Règles  : compteurs et sommes uniquement ; classification faite une fois au niveau opération ;
--           toutes les opérations gardées puis qualifiées ; aucune détection dans la fiche.
-- Unités  : montant_ope en centimes (/100) ; val_coupurek7_1..4 en euros ; encaisse_theorique en euros (texte).
-- Réseaux : d'après la synthèse réelle (août-oct. 2026). Code 10 = Trionis, précisé par le code privatif :
--   CUP = UnionPay (UPI, réseau chinois), DIN = Diners. Les codes privatifs sont gardés pour cela.
-- CPE et C24 = produits carte proposés aux porteurs : comptés dans 'interne' (réseau 03).
--   opérations COS apparaissent en capture -> ce motif correspond probablement aux retraits COS ratés (à vérifier).
-- =====================================================================================================
SELECT t.*
FROM (
    SELECT
        cal.num_automate,
        cal.date_jour,
        YEAR(cal.date_jour)                                                AS annee,
        MONTH(cal.date_jour)                                               AS mois,
        DAY(cal.date_jour)                                                 AS jour,
        PMOD(DATEDIFF(cal.date_jour, '1900-01-01'), 7) + 1                 AS jour_semaine,   -- 1 = lundi
        CASE WHEN PMOD(DATEDIFF(cal.date_jour, '1900-01-01'), 7) >= 5 THEN 1 ELSE 0 END AS week_end,

        -- infos GAB (code regate depuis les opérations, le reste depuis le référentiel final)
        cal.code_site_implantation,
        cal.statut_gab,
        cal.type_gab_e_i,
        cal.code_entite_de_gestion,
        cal.code_postal,
        cal.ville,
        cal.latitude,
        cal.longitude,
        cal.geopoint,
        cal.niveau_precision,
        cal.dans_referentiel,

        -- période d'activité et jours sans activité
        cal.date_premiere_ope,
        cal.date_derniere_ope,
        cal.fin_donnees,
        CASE WHEN a.cle_gab IS NULL THEN 1 ELSE 0 END                      AS jour_sans_ligne,
        CASE WHEN COALESCE(a.nb_retraits, 0) = 0 THEN 1 ELSE 0 END         AS jour_sans_retrait,

        -- 1. Volumes
        COALESCE(a.nb_lignes, 0) AS nb_lignes,
        COALESCE(a.nb_retraits_tentes, 0) AS nb_retraits_tentes,
        COALESCE(a.nb_retraits, 0) AS nb_retraits,
        COALESCE(a.nb_retraits_cos, 0) AS nb_retraits_cos,
        COALESCE(a.nb_retraits_horscos, 0) AS nb_retraits_horscos,
        COALESCE(a.nb_cartes_distinctes, 0) AS nb_cartes_distinctes,
        COALESCE(a.nb_ret_porteur, 0) AS nb_ret_porteur,

        -- 2. Montants
        COALESCE(a.montant_total, 0) AS montant_total,
        COALESCE(a.montant_somme_carres, 0) AS montant_somme_carres,
        a.montant_max,
        a.montant_min,
        COALESCE(a.montant_retraits_cos, 0) AS montant_retraits_cos,
        COALESCE(a.montant_retraits_horscos, 0) AS montant_retraits_horscos,
        COALESCE(a.nb_montant_le_20, 0) AS nb_montant_le_20,
        COALESCE(a.nb_montant_20_50, 0) AS nb_montant_20_50,
        COALESCE(a.nb_montant_50_100, 0) AS nb_montant_50_100,
        COALESCE(a.nb_montant_100_200, 0) AS nb_montant_100_200,
        COALESCE(a.nb_montant_plus_200, 0) AS nb_montant_plus_200,
        COALESCE(a.nb_montant_10_ou_30, 0) AS nb_montant_10_ou_30,

        -- 3. Inaboutis
        COALESCE(a.nb_inaboutis, 0) AS nb_inaboutis,
        COALESCE(a.nb_inaboutis_cos, 0) AS nb_inaboutis_cos,
        COALESCE(a.nb_inaboutis_horscos, 0) AS nb_inaboutis_horscos,
        COALESCE(a.nb_inaboutis_billets, 0) AS nb_inaboutis_billets,
        COALESCE(a.nb_billets_inferieurs_montant, 0) AS nb_billets_inferieurs_montant,
        COALESCE(a.montant_non_distribue, 0) AS montant_non_distribue,
        COALESCE(a.nb_billets_superieurs_montant, 0) AS nb_billets_superieurs_montant,
        COALESCE(a.montant_sur_distribue, 0) AS montant_sur_distribue,
        COALESCE(a.nb_retraits_sans_info_billets, 0) AS nb_retraits_sans_info_billets,
        COALESCE(a.nb_inaboutis_avec_billets, 0) AS nb_inaboutis_avec_billets,
        COALESCE(a.montant_billets_inaboutis, 0) AS montant_billets_inaboutis,
        COALESCE(a.nb_inaboutis_total, 0) AS nb_inaboutis_total,
        COALESCE(a.nb_inaboutis_nuit, 0) AS nb_inaboutis_nuit,
        COALESCE(a.somme_heures_inaboutis, 0) AS somme_heures_inaboutis,
        COALESCE(a.montant_inabouti, 0) AS montant_inabouti,

        -- 4. Captures de carte
        COALESCE(a.nb_captures, 0) AS nb_captures,
        COALESCE(a.nb_captures_cos, 0) AS nb_captures_cos,
        COALESCE(a.nb_captures_horscos, 0) AS nb_captures_horscos,
        COALESCE(a.nb_captures_nuit, 0) AS nb_captures_nuit,
        COALESCE(a.somme_heures_captures, 0) AS somme_heures_captures,
        COALESCE(a.nb_cartes_capturees, 0) AS nb_cartes_capturees,
        COALESCE(a.nb_capture_oubli_lecture, 0) AS nb_capture_oubli_lecture,
        COALESCE(a.nb_capture_capture_cos, 0) AS nb_capture_capture_cos,
        COALESCE(a.nb_capture_conserver_carte, 0) AS nb_capture_conserver_carte,
        COALESCE(a.nb_capture_carte_perdue, 0) AS nb_capture_carte_perdue,
        COALESCE(a.nb_capture_carte_volee, 0) AS nb_capture_carte_volee,
        COALESCE(a.nb_capture_autre_motif, 0) AS nb_capture_autre_motif,

        -- 5. Forme de la journée
        COALESCE(a.nb_0h_6h, 0) AS nb_0h_6h,
        COALESCE(a.nb_6h_9h, 0) AS nb_6h_9h,
        COALESCE(a.nb_9h_12h, 0) AS nb_9h_12h,
        COALESCE(a.nb_12h_14h, 0) AS nb_12h_14h,
        COALESCE(a.nb_14h_18h, 0) AS nb_14h_18h,
        COALESCE(a.nb_18h_22h, 0) AS nb_18h_22h,
        COALESCE(a.nb_22h_24h, 0) AS nb_22h_24h,
        COALESCE(a.nb_nuit_22h_6h, 0) AS nb_nuit_22h_6h,
        COALESCE(a.somme_heures_retraits, 0) AS somme_heures_retraits,
        a.heure_premier_retrait,
        a.heure_dernier_retrait,
        COALESCE(a.nb_heures_actives, 0) AS nb_heures_actives,
        a.plus_long_trou_min,
        COALESCE(a.nb_ope_heure_pic, 0) AS nb_ope_heure_pic,
        a.heure_pic,
        a.heure_pic_retraits,
        COALESCE(a.nb_retraits_heure_pic, 0) AS nb_retraits_heure_pic,
        COALESCE(a.montant_heure_pic, 0) AS montant_heure_pic,

        -- 6. Billets et cassettes
        COALESCE(a.nb_billets_5, 0) AS nb_billets_5,
        COALESCE(a.nb_billets_10, 0) AS nb_billets_10,
        COALESCE(a.nb_billets_20, 0) AS nb_billets_20,
        COALESCE(a.nb_billets_50, 0) AS nb_billets_50,
        COALESCE(a.nb_billets_100, 0) AS nb_billets_100,
        COALESCE(a.nb_billets_total, 0) AS nb_billets_total,
        COALESCE(a.montant_billets_distribues, 0) AS montant_billets_distribues,
        COALESCE(a.nb_retraits_100plus_sans_billet_50, 0) AS nb_retraits_100plus_sans_billet_50,
        COALESCE(a.nb_billets_pos1, 0) AS nb_billets_pos1,
        COALESCE(a.nb_retraits_pos1, 0) AS nb_retraits_pos1,
        a.val_min_pos1,
        a.val_max_pos1,
        COALESCE(a.nb_billets_pos2, 0) AS nb_billets_pos2,
        COALESCE(a.nb_retraits_pos2, 0) AS nb_retraits_pos2,
        a.val_min_pos2,
        a.val_max_pos2,
        COALESCE(a.nb_billets_pos3, 0) AS nb_billets_pos3,
        COALESCE(a.nb_retraits_pos3, 0) AS nb_retraits_pos3,
        a.val_min_pos3,
        a.val_max_pos3,
        COALESCE(a.nb_billets_pos4, 0) AS nb_billets_pos4,
        COALESCE(a.nb_retraits_pos4, 0) AS nb_retraits_pos4,
        a.val_min_pos4,
        a.val_max_pos4,
        COALESCE(a.nb_retraits_repetes_10min, 0) AS nb_retraits_repetes_10min,

        -- 7. Encaisse et chargements
        a.encaisse_debut,
        a.encaisse_fin,
        a.encaisse_min,
        a.encaisse_max,
        COALESCE(a.nb_recharges, 0) AS nb_recharges,
        COALESCE(a.montant_recharge, 0) AS montant_recharge,
        a.montant_max_chargement,
        a.heure_premier_chargement,
        a.encaisse_avant_chargement,
        COALESCE(a.baisse_encaisse_retraits, 0) AS baisse_encaisse_retraits,
        COALESCE(a.nb_incoherences_encaisse, 0) AS nb_incoherences_encaisse,

        -- 8. Réseaux de carte
        COALESCE(a.nb_ret_interne, 0) AS nb_ret_interne,
        COALESCE(a.montant_interne, 0) AS montant_interne,
        COALESCE(a.nb_inab_interne, 0) AS nb_inab_interne,
        COALESCE(a.nb_cap_interne, 0) AS nb_cap_interne,
        COALESCE(a.nb_ret_cb, 0) AS nb_ret_cb,
        COALESCE(a.montant_cb, 0) AS montant_cb,
        COALESCE(a.nb_inab_cb, 0) AS nb_inab_cb,
        COALESCE(a.nb_cap_cb, 0) AS nb_cap_cb,
        COALESCE(a.nb_ret_visa, 0) AS nb_ret_visa,
        COALESCE(a.montant_visa, 0) AS montant_visa,
        COALESCE(a.nb_inab_visa, 0) AS nb_inab_visa,
        COALESCE(a.nb_cap_visa, 0) AS nb_cap_visa,
        COALESCE(a.nb_ret_mastercard, 0) AS nb_ret_mastercard,
        COALESCE(a.montant_mastercard, 0) AS montant_mastercard,
        COALESCE(a.nb_inab_mastercard, 0) AS nb_inab_mastercard,
        COALESCE(a.nb_cap_mastercard, 0) AS nb_cap_mastercard,
        COALESCE(a.nb_ret_cos, 0) AS nb_ret_cos,
        COALESCE(a.montant_cos, 0) AS montant_cos,
        COALESCE(a.nb_inab_cos, 0) AS nb_inab_cos,
        COALESCE(a.nb_cap_cos, 0) AS nb_cap_cos,
        COALESCE(a.nb_ret_amex, 0) AS nb_ret_amex,
        COALESCE(a.montant_amex, 0) AS montant_amex,
        COALESCE(a.nb_inab_amex, 0) AS nb_inab_amex,
        COALESCE(a.nb_cap_amex, 0) AS nb_cap_amex,
        COALESCE(a.nb_ret_cup, 0) AS nb_ret_cup,
        COALESCE(a.montant_cup, 0) AS montant_cup,
        COALESCE(a.nb_inab_cup, 0) AS nb_inab_cup,
        COALESCE(a.nb_cap_cup, 0) AS nb_cap_cup,
        COALESCE(a.nb_ret_diners, 0) AS nb_ret_diners,
        COALESCE(a.montant_diners, 0) AS montant_diners,
        COALESCE(a.nb_inab_diners, 0) AS nb_inab_diners,
        COALESCE(a.nb_cap_diners, 0) AS nb_cap_diners,
        COALESCE(a.nb_ret_jcb, 0) AS nb_ret_jcb,
        COALESCE(a.montant_jcb, 0) AS montant_jcb,
        COALESCE(a.nb_inab_jcb, 0) AS nb_inab_jcb,
        COALESCE(a.nb_cap_jcb, 0) AS nb_cap_jcb,
        COALESCE(a.nb_ret_autre, 0) AS nb_ret_autre,
        COALESCE(a.montant_autre, 0) AS montant_autre,
        COALESCE(a.nb_inab_autre, 0) AS nb_inab_autre,
        COALESCE(a.nb_cap_autre, 0) AS nb_cap_autre,
        COALESCE(a.nb_ret_trionis, 0) AS nb_ret_trionis,
        COALESCE(a.montant_trionis, 0) AS montant_trionis,
        COALESCE(a.nb_inab_trionis, 0) AS nb_inab_trionis,
        COALESCE(a.nb_cap_trionis, 0) AS nb_cap_trionis,
        COALESCE(a.nb_ret_exotique, 0) AS nb_ret_exotique,
        COALESCE(a.montant_exotique, 0) AS montant_exotique,
        COALESCE(a.nb_inab_exotique, 0) AS nb_inab_exotique,
        COALESCE(a.nb_cap_exotique, 0) AS nb_cap_exotique,
        COALESCE(a.nb_ret_etranger_sur, 0) AS nb_ret_etranger_sur,
        COALESCE(a.montant_etranger_sur, 0) AS montant_etranger_sur,
        COALESCE(a.nb_inab_etranger_sur, 0) AS nb_inab_etranger_sur,
        COALESCE(a.nb_cap_etranger_sur, 0) AS nb_cap_etranger_sur,

        -- 9. Qualité des données
        COALESCE(a.nb_retraits_montant_zero, 0) AS nb_retraits_montant_zero,
        COALESCE(a.nb_retraits_montant_invalide, 0) AS nb_retraits_montant_invalide,
        COALESCE(a.nb_heure_invalide, 0) AS nb_heure_invalide,
        COALESCE(a.nb_retraits_sans_carte, 0) AS nb_retraits_sans_carte,
        COALESCE(a.nb_billets_valeur_inconnue, 0) AS nb_billets_valeur_inconnue

    FROM (
        -- ---------- calendrier : chaque GAB vu dans les opérations x chaque jour de sa période d'activité
        SELECT
            gr.num_automate,
            gr.code_site_implantation,
            gr.date_premiere_ope,
            gr.date_derniere_ope,
            gr.fin_donnees,
            gr.statut_gab,
            gr.type_gab_e_i,
            gr.code_entite_de_gestion,
            gr.code_postal,
            gr.ville,
            gr.latitude,
            gr.longitude,
            gr.geopoint,
            gr.niveau_precision,
            gr.dans_referentiel,
            DATE_ADD(gr.date_premiere_ope, p.pos) AS date_jour
        FROM (
        SELECT
            g.num_automate,
            g.code_site_implantation,
            g.date_premiere_ope,
            g.date_derniere_ope,
            g.fin_donnees,
            r.statut_gab,
            r.type_gab_e_i,
            r.code_entite_de_gestion,
            r.cd_pst_ok          AS code_postal,
            r.ville_ok           AS ville,
            r.latitude_finale    AS latitude,
            r.longitude_finale   AS longitude,
            r.geopoint_final     AS geopoint,
            r.niveau_precision,
            CASE WHEN r.num_automate IS NULL THEN 0 ELSE 1 END AS dans_referentiel,
            -- dernier jour du calendrier de ce GAB : fin des données, ou sa dernière opération s'il est FERME
            CASE WHEN COALESCE(r.statut_gab, '') = 'FERME' THEN g.date_derniere_ope ELSE g.fin_donnees END AS fin_calendrier
        FROM (
            -- bornes de chaque GAB (lecture légère de la table des opérations : 3 colonnes, GROUP BY GAB)
            SELECT
                b.num_automate,
                b.code_site_implantation,
                b.date_premiere_ope,
                b.date_derniere_ope,
                MAX(b.date_derniere_ope) OVER () AS fin_donnees      -- une ligne par GAB : fenêtre légère
            FROM (
                SELECT
                    TRIM(CAST(num_automate AS STRING)) AS num_automate,
                    MAX(TRIM(CAST(code_site_implantation AS STRING))) AS code_site_implantation,
                    MIN(CASE WHEN d BETWEEN '2024-01-01' AND CAST(CURRENT_DATE AS STRING) THEN d END) AS date_premiere_ope,
                    MAX(CASE WHEN d BETWEEN '2024-01-01' AND CAST(CURRENT_DATE AS STRING) THEN d END) AS date_derniere_ope
                FROM (
                    SELECT
                        num_automate,
                        code_site_implantation,
                        CAST(CASE WHEN CAST(date_operation AS STRING) LIKE '____-__-__%'
                                  THEN TO_DATE(SUBSTR(CAST(date_operation AS STRING), 1, 10))
                                  ELSE TO_DATE(FROM_UNIXTIME(UNIX_TIMESTAMP(LPAD(CAST(date_operation AS STRING), 8, '0'), 'ddMMyyyy')))
                             END AS STRING) AS d
                    FROM `base`.`table_operations`
                    WHERE TRIM(lib_ope) IN ('Retrait', 'Autorisation-Retrait', 'Capture de Carte')   -- TEST : AND date_operation LIKE '__102026'
                ) d0
                GROUP BY TRIM(CAST(num_automate AS STRING))
            ) b
            WHERE b.date_premiere_ope IS NOT NULL
        ) g
        LEFT JOIN `base`.`referentiel_gab` r
          ON TRIM(CAST(r.num_automate AS STRING)) = g.num_automate
        ) gr
        -- un jour par position, du premier jour d'opération au dernier jour du calendrier
        LATERAL VIEW POSEXPLODE(SPLIT(SPACE(DATEDIFF(gr.fin_calendrier, gr.date_premiere_ope)), ' ')) p AS pos, val
    ) cal

    LEFT JOIN (
        -- ---------- agrégats GAB x jour (lecture principale de la table des opérations)
        SELECT
            num_automate AS cle_gab,
            date_jour    AS cle_jour,
            COUNT(*) AS nb_lignes,
            SUM(CASE WHEN type_op <> 'CAP' THEN 1 ELSE 0 END) AS nb_retraits_tentes,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 THEN 1 ELSE 0 END) AS nb_retraits,
            SUM(CASE WHEN type_op = 'RI' AND inabouti = 0 THEN 1 ELSE 0 END) AS nb_retraits_cos,
            SUM(CASE WHEN type_op = 'RE' AND inabouti = 0 THEN 1 ELSE 0 END) AS nb_retraits_horscos,
            COUNT(DISTINCT CASE WHEN type_op <> 'CAP' THEN num_carte END) AS nb_cartes_distinctes,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND porteur = 1 THEN 1 ELSE 0 END) AS nb_ret_porteur,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 THEN montant ELSE 0 END) AS montant_total,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 THEN montant * montant ELSE 0 END) AS montant_somme_carres,
            MAX(CASE WHEN type_op <> 'CAP' AND inabouti = 0 THEN montant END) AS montant_max,
            MIN(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND montant > 0 THEN montant END) AS montant_min,
            SUM(CASE WHEN type_op = 'RI' AND inabouti = 0 THEN montant ELSE 0 END) AS montant_retraits_cos,
            SUM(CASE WHEN type_op = 'RE' AND inabouti = 0 THEN montant ELSE 0 END) AS montant_retraits_horscos,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND montant > 0 AND montant <= 20 THEN 1 ELSE 0 END) AS nb_montant_le_20,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND montant > 20 AND montant <= 50 THEN 1 ELSE 0 END) AS nb_montant_20_50,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND montant > 50 AND montant <= 100 THEN 1 ELSE 0 END) AS nb_montant_50_100,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND montant > 100 AND montant <= 200 THEN 1 ELSE 0 END) AS nb_montant_100_200,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND montant > 200 THEN 1 ELSE 0 END) AS nb_montant_plus_200,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND CAST(ROUND(montant) AS INT) IN (10, 30) THEN 1 ELSE 0 END) AS nb_montant_10_ou_30,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 1 THEN 1 ELSE 0 END) AS nb_inaboutis,
            SUM(CASE WHEN type_op = 'RI' AND inabouti = 1 THEN 1 ELSE 0 END) AS nb_inaboutis_cos,
            SUM(CASE WHEN type_op = 'RE' AND inabouti = 1 THEN 1 ELSE 0 END) AS nb_inaboutis_horscos,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND montant > 0 AND ABS(montant - montant_billets) > 0.01 THEN 1 ELSE 0 END) AS nb_inaboutis_billets,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND montant > 0 AND (nb1 + nb2 + nb3 + nb4) > 0 AND montant_billets < montant - 0.01 THEN 1 ELSE 0 END) AS nb_billets_inferieurs_montant,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND montant > 0 AND (nb1 + nb2 + nb3 + nb4) > 0 AND montant_billets < montant - 0.01 THEN montant - montant_billets ELSE 0 END) AS montant_non_distribue,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND montant > 0 AND montant_billets > montant + 0.01 THEN 1 ELSE 0 END) AS nb_billets_superieurs_montant,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND montant > 0 AND montant_billets > montant + 0.01 THEN montant_billets - montant ELSE 0 END) AS montant_sur_distribue,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND montant > 0 AND (nb1 + nb2 + nb3 + nb4) = 0 THEN 1 ELSE 0 END) AS nb_retraits_sans_info_billets,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 1 AND (nb1 + nb2 + nb3 + nb4) > 0 THEN 1 ELSE 0 END) AS nb_inaboutis_avec_billets,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 1 THEN montant_billets ELSE 0 END) AS montant_billets_inaboutis,
            SUM(CASE WHEN type_op <> 'CAP' AND (inabouti = 1 OR (montant > 0 AND ABS(montant - montant_billets) > 0.01)) THEN 1 ELSE 0 END) AS nb_inaboutis_total,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 1 AND (h >= 22 OR h < 6) THEN 1 ELSE 0 END) AS nb_inaboutis_nuit,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 1 THEN h ELSE 0 END) AS somme_heures_inaboutis,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 1 THEN montant ELSE 0 END) AS montant_inabouti,
            SUM(CASE WHEN type_op = 'CAP' THEN 1 ELSE 0 END) AS nb_captures,
            SUM(CASE WHEN type_op = 'CAP' AND cat_reseau IN ('cos', 'interne') THEN 1 ELSE 0 END) AS nb_captures_cos,
            SUM(CASE WHEN type_op = 'CAP' AND cat_reseau NOT IN ('cos', 'interne') THEN 1 ELSE 0 END) AS nb_captures_horscos,
            SUM(CASE WHEN type_op = 'CAP' AND (h >= 22 OR h < 6) THEN 1 ELSE 0 END) AS nb_captures_nuit,
            SUM(CASE WHEN type_op = 'CAP' THEN h ELSE 0 END) AS somme_heures_captures,
            COUNT(DISTINCT CASE WHEN type_op = 'CAP' THEN num_carte END) AS nb_cartes_capturees,
            SUM(CASE WHEN type_op = 'CAP' AND motif = 'oubli_lecture' THEN 1 ELSE 0 END) AS nb_capture_oubli_lecture,
            SUM(CASE WHEN type_op = 'CAP' AND motif = 'capture_cos' THEN 1 ELSE 0 END) AS nb_capture_capture_cos,
            SUM(CASE WHEN type_op = 'CAP' AND motif = 'conserver_carte' THEN 1 ELSE 0 END) AS nb_capture_conserver_carte,
            SUM(CASE WHEN type_op = 'CAP' AND motif = 'carte_perdue' THEN 1 ELSE 0 END) AS nb_capture_carte_perdue,
            SUM(CASE WHEN type_op = 'CAP' AND motif = 'carte_volee' THEN 1 ELSE 0 END) AS nb_capture_carte_volee,
            SUM(CASE WHEN type_op = 'CAP' AND motif = 'autre' THEN 1 ELSE 0 END) AS nb_capture_autre_motif,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h >= 0 AND h < 6 THEN 1 ELSE 0 END) AS nb_0h_6h,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h >= 6 AND h < 9 THEN 1 ELSE 0 END) AS nb_6h_9h,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h >= 9 AND h < 12 THEN 1 ELSE 0 END) AS nb_9h_12h,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h >= 12 AND h < 14 THEN 1 ELSE 0 END) AS nb_12h_14h,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h >= 14 AND h < 18 THEN 1 ELSE 0 END) AS nb_14h_18h,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h >= 18 AND h < 22 THEN 1 ELSE 0 END) AS nb_18h_22h,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h >= 22 AND h < 24 THEN 1 ELSE 0 END) AS nb_22h_24h,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND (h >= 22 OR h < 6) THEN 1 ELSE 0 END) AS nb_nuit_22h_6h,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 THEN h ELSE 0 END) AS somme_heures_retraits,
            MIN(CASE WHEN type_op <> 'CAP' THEN heure END) AS heure_premier_retrait,
            MAX(CASE WHEN type_op <> 'CAP' THEN heure END) AS heure_dernier_retrait,
            COUNT(DISTINCT CASE WHEN type_op <> 'CAP' THEN h END) AS nb_heures_actives,
            ROUND(GREATEST(COALESCE(MAX(ecart_sec), 0), COALESCE(MIN(sec), 0), 86400 - COALESCE(MAX(sec), 86400)) / 60, 1) AS plus_long_trou_min,
            FLOOR(GREATEST(SUM(CASE WHEN h = 0 THEN 1 ELSE 0 END) * 100 + 23, SUM(CASE WHEN h = 1 THEN 1 ELSE 0 END) * 100 + 22, SUM(CASE WHEN h = 2 THEN 1 ELSE 0 END) * 100 + 21, SUM(CASE WHEN h = 3 THEN 1 ELSE 0 END) * 100 + 20, SUM(CASE WHEN h = 4 THEN 1 ELSE 0 END) * 100 + 19, SUM(CASE WHEN h = 5 THEN 1 ELSE 0 END) * 100 + 18, SUM(CASE WHEN h = 6 THEN 1 ELSE 0 END) * 100 + 17, SUM(CASE WHEN h = 7 THEN 1 ELSE 0 END) * 100 + 16, SUM(CASE WHEN h = 8 THEN 1 ELSE 0 END) * 100 + 15, SUM(CASE WHEN h = 9 THEN 1 ELSE 0 END) * 100 + 14, SUM(CASE WHEN h = 10 THEN 1 ELSE 0 END) * 100 + 13, SUM(CASE WHEN h = 11 THEN 1 ELSE 0 END) * 100 + 12, SUM(CASE WHEN h = 12 THEN 1 ELSE 0 END) * 100 + 11, SUM(CASE WHEN h = 13 THEN 1 ELSE 0 END) * 100 + 10, SUM(CASE WHEN h = 14 THEN 1 ELSE 0 END) * 100 + 9, SUM(CASE WHEN h = 15 THEN 1 ELSE 0 END) * 100 + 8, SUM(CASE WHEN h = 16 THEN 1 ELSE 0 END) * 100 + 7, SUM(CASE WHEN h = 17 THEN 1 ELSE 0 END) * 100 + 6, SUM(CASE WHEN h = 18 THEN 1 ELSE 0 END) * 100 + 5, SUM(CASE WHEN h = 19 THEN 1 ELSE 0 END) * 100 + 4, SUM(CASE WHEN h = 20 THEN 1 ELSE 0 END) * 100 + 3, SUM(CASE WHEN h = 21 THEN 1 ELSE 0 END) * 100 + 2, SUM(CASE WHEN h = 22 THEN 1 ELSE 0 END) * 100 + 1, SUM(CASE WHEN h = 23 THEN 1 ELSE 0 END) * 100 + 0) / 100) AS nb_ope_heure_pic,
            CASE WHEN FLOOR(GREATEST(SUM(CASE WHEN h = 0 THEN 1 ELSE 0 END) * 100 + 23, SUM(CASE WHEN h = 1 THEN 1 ELSE 0 END) * 100 + 22, SUM(CASE WHEN h = 2 THEN 1 ELSE 0 END) * 100 + 21, SUM(CASE WHEN h = 3 THEN 1 ELSE 0 END) * 100 + 20, SUM(CASE WHEN h = 4 THEN 1 ELSE 0 END) * 100 + 19, SUM(CASE WHEN h = 5 THEN 1 ELSE 0 END) * 100 + 18, SUM(CASE WHEN h = 6 THEN 1 ELSE 0 END) * 100 + 17, SUM(CASE WHEN h = 7 THEN 1 ELSE 0 END) * 100 + 16, SUM(CASE WHEN h = 8 THEN 1 ELSE 0 END) * 100 + 15, SUM(CASE WHEN h = 9 THEN 1 ELSE 0 END) * 100 + 14, SUM(CASE WHEN h = 10 THEN 1 ELSE 0 END) * 100 + 13, SUM(CASE WHEN h = 11 THEN 1 ELSE 0 END) * 100 + 12, SUM(CASE WHEN h = 12 THEN 1 ELSE 0 END) * 100 + 11, SUM(CASE WHEN h = 13 THEN 1 ELSE 0 END) * 100 + 10, SUM(CASE WHEN h = 14 THEN 1 ELSE 0 END) * 100 + 9, SUM(CASE WHEN h = 15 THEN 1 ELSE 0 END) * 100 + 8, SUM(CASE WHEN h = 16 THEN 1 ELSE 0 END) * 100 + 7, SUM(CASE WHEN h = 17 THEN 1 ELSE 0 END) * 100 + 6, SUM(CASE WHEN h = 18 THEN 1 ELSE 0 END) * 100 + 5, SUM(CASE WHEN h = 19 THEN 1 ELSE 0 END) * 100 + 4, SUM(CASE WHEN h = 20 THEN 1 ELSE 0 END) * 100 + 3, SUM(CASE WHEN h = 21 THEN 1 ELSE 0 END) * 100 + 2, SUM(CASE WHEN h = 22 THEN 1 ELSE 0 END) * 100 + 1, SUM(CASE WHEN h = 23 THEN 1 ELSE 0 END) * 100 + 0) / 100) = 0 THEN NULL ELSE 23 - PMOD(GREATEST(SUM(CASE WHEN h = 0 THEN 1 ELSE 0 END) * 100 + 23, SUM(CASE WHEN h = 1 THEN 1 ELSE 0 END) * 100 + 22, SUM(CASE WHEN h = 2 THEN 1 ELSE 0 END) * 100 + 21, SUM(CASE WHEN h = 3 THEN 1 ELSE 0 END) * 100 + 20, SUM(CASE WHEN h = 4 THEN 1 ELSE 0 END) * 100 + 19, SUM(CASE WHEN h = 5 THEN 1 ELSE 0 END) * 100 + 18, SUM(CASE WHEN h = 6 THEN 1 ELSE 0 END) * 100 + 17, SUM(CASE WHEN h = 7 THEN 1 ELSE 0 END) * 100 + 16, SUM(CASE WHEN h = 8 THEN 1 ELSE 0 END) * 100 + 15, SUM(CASE WHEN h = 9 THEN 1 ELSE 0 END) * 100 + 14, SUM(CASE WHEN h = 10 THEN 1 ELSE 0 END) * 100 + 13, SUM(CASE WHEN h = 11 THEN 1 ELSE 0 END) * 100 + 12, SUM(CASE WHEN h = 12 THEN 1 ELSE 0 END) * 100 + 11, SUM(CASE WHEN h = 13 THEN 1 ELSE 0 END) * 100 + 10, SUM(CASE WHEN h = 14 THEN 1 ELSE 0 END) * 100 + 9, SUM(CASE WHEN h = 15 THEN 1 ELSE 0 END) * 100 + 8, SUM(CASE WHEN h = 16 THEN 1 ELSE 0 END) * 100 + 7, SUM(CASE WHEN h = 17 THEN 1 ELSE 0 END) * 100 + 6, SUM(CASE WHEN h = 18 THEN 1 ELSE 0 END) * 100 + 5, SUM(CASE WHEN h = 19 THEN 1 ELSE 0 END) * 100 + 4, SUM(CASE WHEN h = 20 THEN 1 ELSE 0 END) * 100 + 3, SUM(CASE WHEN h = 21 THEN 1 ELSE 0 END) * 100 + 2, SUM(CASE WHEN h = 22 THEN 1 ELSE 0 END) * 100 + 1, SUM(CASE WHEN h = 23 THEN 1 ELSE 0 END) * 100 + 0), 100) END AS heure_pic,
            CASE WHEN FLOOR(GREATEST(CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 0 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 0 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 23, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 1 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 1 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 22, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 2 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 2 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 21, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 3 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 3 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 20, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 4 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 4 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 19, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 5 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 5 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 18, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 6 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 6 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 17, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 7 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 7 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 16, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 8 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 8 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 15, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 9 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 9 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 14, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 10 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 10 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 13, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 11 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 11 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 12, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 12 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 12 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 11, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 13 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 13 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 10, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 14 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 14 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 9, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 15 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 15 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 8, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 16 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 16 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 7, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 17 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 17 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 6, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 18 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 18 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 5, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 19 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 19 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 4, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 20 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 20 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 3, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 21 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 21 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 2, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 22 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 22 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 1, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 23 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 23 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 0) / 10000000000) = 0 THEN NULL ELSE 23 - PMOD(GREATEST(CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 0 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 0 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 23, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 1 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 1 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 22, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 2 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 2 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 21, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 3 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 3 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 20, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 4 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 4 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 19, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 5 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 5 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 18, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 6 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 6 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 17, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 7 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 7 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 16, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 8 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 8 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 15, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 9 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 9 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 14, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 10 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 10 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 13, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 11 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 11 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 12, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 12 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 12 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 11, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 13 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 13 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 10, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 14 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 14 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 9, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 15 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 15 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 8, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 16 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 16 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 7, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 17 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 17 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 6, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 18 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 18 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 5, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 19 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 19 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 4, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 20 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 20 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 3, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 21 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 21 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 2, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 22 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 22 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 1, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 23 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 23 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 0), 100) END AS heure_pic_retraits,
            FLOOR(GREATEST(CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 0 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 0 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 23, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 1 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 1 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 22, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 2 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 2 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 21, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 3 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 3 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 20, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 4 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 4 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 19, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 5 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 5 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 18, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 6 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 6 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 17, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 7 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 7 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 16, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 8 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 8 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 15, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 9 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 9 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 14, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 10 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 10 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 13, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 11 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 11 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 12, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 12 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 12 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 11, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 13 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 13 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 10, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 14 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 14 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 9, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 15 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 15 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 8, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 16 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 16 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 7, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 17 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 17 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 6, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 18 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 18 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 5, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 19 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 19 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 4, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 20 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 20 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 3, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 21 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 21 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 2, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 22 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 22 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 1, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 23 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 23 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 0) / 10000000000) AS nb_retraits_heure_pic,
            FLOOR(PMOD(GREATEST(CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 0 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 0 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 23, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 1 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 1 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 22, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 2 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 2 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 21, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 3 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 3 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 20, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 4 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 4 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 19, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 5 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 5 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 18, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 6 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 6 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 17, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 7 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 7 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 16, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 8 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 8 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 15, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 9 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 9 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 14, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 10 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 10 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 13, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 11 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 11 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 12, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 12 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 12 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 11, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 13 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 13 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 10, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 14 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 14 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 9, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 15 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 15 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 8, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 16 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 16 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 7, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 17 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 17 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 6, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 18 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 18 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 5, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 19 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 19 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 4, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 20 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 20 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 3, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 21 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 21 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 2, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 22 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 22 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 1, CAST(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 23 THEN 1 ELSE 0 END) AS BIGINT) * 10000000000 + CAST(ROUND(SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND h = 23 THEN montant ELSE 0 END)) AS BIGINT) * 100 + 0), 10000000000) / 100) AS montant_heure_pic,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 THEN b5 ELSE 0 END) AS nb_billets_5,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 THEN b10 ELSE 0 END) AS nb_billets_10,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 THEN b20 ELSE 0 END) AS nb_billets_20,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 THEN b50 ELSE 0 END) AS nb_billets_50,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 THEN b100 ELSE 0 END) AS nb_billets_100,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 THEN nb1 + nb2 + nb3 + nb4 ELSE 0 END) AS nb_billets_total,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 THEN montant_billets ELSE 0 END) AS montant_billets_distribues,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND montant >= 100 AND b50 = 0 AND (val1 = 50 OR val2 = 50 OR val3 = 50 OR val4 = 50) THEN 1 ELSE 0 END) AS nb_retraits_100plus_sans_billet_50,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 THEN nb1 ELSE 0 END) AS nb_billets_pos1,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND nb1 > 0 THEN 1 ELSE 0 END) AS nb_retraits_pos1,
            MIN(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND nb1 > 0 THEN val1 END) AS val_min_pos1,
            MAX(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND nb1 > 0 THEN val1 END) AS val_max_pos1,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 THEN nb2 ELSE 0 END) AS nb_billets_pos2,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND nb2 > 0 THEN 1 ELSE 0 END) AS nb_retraits_pos2,
            MIN(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND nb2 > 0 THEN val2 END) AS val_min_pos2,
            MAX(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND nb2 > 0 THEN val2 END) AS val_max_pos2,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 THEN nb3 ELSE 0 END) AS nb_billets_pos3,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND nb3 > 0 THEN 1 ELSE 0 END) AS nb_retraits_pos3,
            MIN(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND nb3 > 0 THEN val3 END) AS val_min_pos3,
            MAX(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND nb3 > 0 THEN val3 END) AS val_max_pos3,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 THEN nb4 ELSE 0 END) AS nb_billets_pos4,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND nb4 > 0 THEN 1 ELSE 0 END) AS nb_retraits_pos4,
            MIN(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND nb4 > 0 THEN val4 END) AS val_min_pos4,
            MAX(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND nb4 > 0 THEN val4 END) AS val_max_pos4,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND num_carte IS NOT NULL AND ecart_meme_carte_sec BETWEEN 0 AND 600 THEN 1 ELSE 0 END) AS nb_retraits_repetes_10min,
            CAST(SUBSTR(MIN(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND encaisse IS NOT NULL THEN CONCAT(LPAD(CAST(sec AS STRING), 5, '0'), LPAD(CAST(CAST(encaisse AS BIGINT) AS STRING), 12, '0')) END), 6) AS DOUBLE) AS encaisse_debut,
            CAST(SUBSTR(MAX(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND encaisse IS NOT NULL THEN CONCAT(LPAD(CAST(sec AS STRING), 5, '0'), LPAD(CAST(CAST(encaisse AS BIGINT) AS STRING), 12, '0')) END), 6) AS DOUBLE) AS encaisse_fin,
            MIN(CASE WHEN type_op <> 'CAP' AND inabouti = 0 THEN encaisse END) AS encaisse_min,
            MAX(CASE WHEN type_op <> 'CAP' AND inabouti = 0 THEN encaisse END) AS encaisse_max,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND variation_encaisse > 0 THEN 1 ELSE 0 END) AS nb_recharges,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND variation_encaisse > 0 THEN variation_encaisse ELSE 0 END) AS montant_recharge,
            MAX(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND variation_encaisse > 0 THEN variation_encaisse END) AS montant_max_chargement,
            MIN(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND variation_encaisse > 0 THEN heure END) AS heure_premier_chargement,
            CAST(SUBSTR(MIN(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND variation_encaisse > 0 THEN CONCAT(LPAD(CAST(sec AS STRING), 5, '0'), LPAD(CAST(CAST(encaisse - variation_encaisse AS BIGINT) AS STRING), 12, '0')) END), 6) AS DOUBLE) AS encaisse_avant_chargement,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND variation_encaisse <= 0 THEN -variation_encaisse ELSE 0 END) AS baisse_encaisse_retraits,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND variation_encaisse <= 0 AND ABS(variation_encaisse + montant) > 0.5 THEN 1 ELSE 0 END) AS nb_incoherences_encaisse,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND cat_reseau = 'interne' THEN 1 ELSE 0 END) AS nb_ret_interne,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND cat_reseau = 'interne' THEN montant ELSE 0 END) AS montant_interne,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 1 AND cat_reseau = 'interne' THEN 1 ELSE 0 END) AS nb_inab_interne,
            SUM(CASE WHEN type_op = 'CAP' AND cat_reseau = 'interne' THEN 1 ELSE 0 END) AS nb_cap_interne,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND cat_reseau = 'cb' THEN 1 ELSE 0 END) AS nb_ret_cb,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND cat_reseau = 'cb' THEN montant ELSE 0 END) AS montant_cb,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 1 AND cat_reseau = 'cb' THEN 1 ELSE 0 END) AS nb_inab_cb,
            SUM(CASE WHEN type_op = 'CAP' AND cat_reseau = 'cb' THEN 1 ELSE 0 END) AS nb_cap_cb,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND cat_reseau = 'visa' THEN 1 ELSE 0 END) AS nb_ret_visa,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND cat_reseau = 'visa' THEN montant ELSE 0 END) AS montant_visa,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 1 AND cat_reseau = 'visa' THEN 1 ELSE 0 END) AS nb_inab_visa,
            SUM(CASE WHEN type_op = 'CAP' AND cat_reseau = 'visa' THEN 1 ELSE 0 END) AS nb_cap_visa,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND cat_reseau = 'mastercard' THEN 1 ELSE 0 END) AS nb_ret_mastercard,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND cat_reseau = 'mastercard' THEN montant ELSE 0 END) AS montant_mastercard,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 1 AND cat_reseau = 'mastercard' THEN 1 ELSE 0 END) AS nb_inab_mastercard,
            SUM(CASE WHEN type_op = 'CAP' AND cat_reseau = 'mastercard' THEN 1 ELSE 0 END) AS nb_cap_mastercard,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND cat_reseau = 'cos' THEN 1 ELSE 0 END) AS nb_ret_cos,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND cat_reseau = 'cos' THEN montant ELSE 0 END) AS montant_cos,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 1 AND cat_reseau = 'cos' THEN 1 ELSE 0 END) AS nb_inab_cos,
            SUM(CASE WHEN type_op = 'CAP' AND cat_reseau = 'cos' THEN 1 ELSE 0 END) AS nb_cap_cos,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND cat_reseau = 'amex' THEN 1 ELSE 0 END) AS nb_ret_amex,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND cat_reseau = 'amex' THEN montant ELSE 0 END) AS montant_amex,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 1 AND cat_reseau = 'amex' THEN 1 ELSE 0 END) AS nb_inab_amex,
            SUM(CASE WHEN type_op = 'CAP' AND cat_reseau = 'amex' THEN 1 ELSE 0 END) AS nb_cap_amex,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND cat_reseau = 'cup' THEN 1 ELSE 0 END) AS nb_ret_cup,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND cat_reseau = 'cup' THEN montant ELSE 0 END) AS montant_cup,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 1 AND cat_reseau = 'cup' THEN 1 ELSE 0 END) AS nb_inab_cup,
            SUM(CASE WHEN type_op = 'CAP' AND cat_reseau = 'cup' THEN 1 ELSE 0 END) AS nb_cap_cup,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND cat_reseau = 'diners' THEN 1 ELSE 0 END) AS nb_ret_diners,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND cat_reseau = 'diners' THEN montant ELSE 0 END) AS montant_diners,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 1 AND cat_reseau = 'diners' THEN 1 ELSE 0 END) AS nb_inab_diners,
            SUM(CASE WHEN type_op = 'CAP' AND cat_reseau = 'diners' THEN 1 ELSE 0 END) AS nb_cap_diners,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND cat_reseau = 'jcb' THEN 1 ELSE 0 END) AS nb_ret_jcb,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND cat_reseau = 'jcb' THEN montant ELSE 0 END) AS montant_jcb,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 1 AND cat_reseau = 'jcb' THEN 1 ELSE 0 END) AS nb_inab_jcb,
            SUM(CASE WHEN type_op = 'CAP' AND cat_reseau = 'jcb' THEN 1 ELSE 0 END) AS nb_cap_jcb,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND cat_reseau = 'autre' THEN 1 ELSE 0 END) AS nb_ret_autre,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND cat_reseau = 'autre' THEN montant ELSE 0 END) AS montant_autre,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 1 AND cat_reseau = 'autre' THEN 1 ELSE 0 END) AS nb_inab_autre,
            SUM(CASE WHEN type_op = 'CAP' AND cat_reseau = 'autre' THEN 1 ELSE 0 END) AS nb_cap_autre,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND cat_reseau IN ('cup', 'diners') THEN 1 ELSE 0 END) AS nb_ret_trionis,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND cat_reseau IN ('cup', 'diners') THEN montant ELSE 0 END) AS montant_trionis,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 1 AND cat_reseau IN ('cup', 'diners') THEN 1 ELSE 0 END) AS nb_inab_trionis,
            SUM(CASE WHEN type_op = 'CAP' AND cat_reseau IN ('cup', 'diners') THEN 1 ELSE 0 END) AS nb_cap_trionis,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND cat_reseau IN ('amex', 'cup', 'diners', 'jcb') THEN 1 ELSE 0 END) AS nb_ret_exotique,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND cat_reseau IN ('amex', 'cup', 'diners', 'jcb') THEN montant ELSE 0 END) AS montant_exotique,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 1 AND cat_reseau IN ('amex', 'cup', 'diners', 'jcb') THEN 1 ELSE 0 END) AS nb_inab_exotique,
            SUM(CASE WHEN type_op = 'CAP' AND cat_reseau IN ('amex', 'cup', 'diners', 'jcb') THEN 1 ELSE 0 END) AS nb_cap_exotique,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND cat_reseau IN ('cup', 'jcb') THEN 1 ELSE 0 END) AS nb_ret_etranger_sur,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 AND cat_reseau IN ('cup', 'jcb') THEN montant ELSE 0 END) AS montant_etranger_sur,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 1 AND cat_reseau IN ('cup', 'jcb') THEN 1 ELSE 0 END) AS nb_inab_etranger_sur,
            SUM(CASE WHEN type_op = 'CAP' AND cat_reseau IN ('cup', 'jcb') THEN 1 ELSE 0 END) AS nb_cap_etranger_sur,
            SUM(CASE WHEN type_op <> 'CAP' AND montant = 0 THEN 1 ELSE 0 END) AS nb_retraits_montant_zero,
            SUM(CASE WHEN type_op <> 'CAP' AND (montant < 0 OR montant IS NULL) THEN 1 ELSE 0 END) AS nb_retraits_montant_invalide,
            SUM(CASE WHEN h IS NULL OR h > 23 THEN 1 ELSE 0 END) AS nb_heure_invalide,
            SUM(CASE WHEN type_op <> 'CAP' AND num_carte IS NULL THEN 1 ELSE 0 END) AS nb_retraits_sans_carte,
            SUM(CASE WHEN type_op <> 'CAP' AND inabouti = 0 THEN b_autre ELSE 0 END) AS nb_billets_valeur_inconnue
        FROM (
            -- niveau 2 : 3 fonctions de fenêtre (chacune = 1 tri des opérations)
            SELECT
                o.*,
                -- écart avec l'opération précédente du même GAB dans la journée
                o.sec - LAG(o.sec) OVER (PARTITION BY o.num_automate, o.date_jour ORDER BY o.sec) AS ecart_sec,
                -- même carte : écart avec son retrait abouti précédent sur ce GAB (minuit compris)
                o.t_abs - LAG(o.t_abs) OVER (PARTITION BY o.num_automate, o.num_carte, o.est_abouti ORDER BY o.t_abs)
                                                                                                   AS ecart_meme_carte_sec,
                -- encaisse : comparée au retrait abouti précédent du même GAB qui porte une encaisse (jours précédents compris)
                -- (à la même seconde, l'encaisse la plus haute est l'opération la plus ancienne : évite de faux chargements)
                o.encaisse - LAG(o.encaisse) OVER (PARTITION BY o.num_automate, o.est_abouti, o.encaisse_ok ORDER BY o.t_abs, o.encaisse DESC)
                                                                                                   AS variation_encaisse
            FROM (
                -- niveau 1 : lecture, typage et classification, une seule fois par opération
                SELECT
                    TRIM(CAST(num_automate AS STRING))                                         AS num_automate,
                    CASE WHEN TRIM(CAST(num_carte AS STRING)) = '' THEN NULL
                         ELSE TRIM(CAST(num_carte AS STRING)) END                               AS num_carte,
                    CASE WHEN UPPER(TRIM(type_porteur)) = 'PORTEUR' THEN 1
                         WHEN COALESCE(TRIM(type_porteur), '') = '' AND TRIM(lib_ope) = 'Retrait' THEN 1   -- COS : pas de type_porteur
                         ELSE 0 END                                                            AS porteur,
                    CASE WHEN CAST(date_operation AS STRING) LIKE '____-__-__%'
                         THEN TO_DATE(SUBSTR(CAST(date_operation AS STRING), 1, 10))
                         ELSE TO_DATE(FROM_UNIXTIME(UNIX_TIMESTAMP(LPAD(CAST(date_operation AS STRING), 8, '0'), 'ddMMyyyy')))
                    END                                                                        AS date_jour,
                    LPAD(CAST(heure_operation AS STRING), 6, '0')                              AS heure,
                    CAST(SUBSTR(LPAD(CAST(heure_operation AS STRING), 6, '0'), 1, 2) AS INT)   AS h,
                    CAST(SUBSTR(LPAD(CAST(heure_operation AS STRING), 6, '0'), 1, 2) AS INT) * 3600
                  + CAST(SUBSTR(LPAD(CAST(heure_operation AS STRING), 6, '0'), 3, 2) AS INT) * 60
                  + CAST(SUBSTR(LPAD(CAST(heure_operation AS STRING), 6, '0'), 5, 2) AS INT)   AS sec,
                    -- instant en secondes depuis le 01/01/2024 (pour comparer des opérations de part et d'autre de minuit)
                    CAST(DATEDIFF(CASE WHEN CAST(date_operation AS STRING) LIKE '____-__-__%'
                                       THEN TO_DATE(SUBSTR(CAST(date_operation AS STRING), 1, 10))
                                       ELSE TO_DATE(FROM_UNIXTIME(UNIX_TIMESTAMP(LPAD(CAST(date_operation AS STRING), 8, '0'), 'ddMMyyyy')))
                                  END, '2024-01-01') AS BIGINT) * 86400
                  + CAST(SUBSTR(LPAD(CAST(heure_operation AS STRING), 6, '0'), 1, 2) AS INT) * 3600
                  + CAST(SUBSTR(LPAD(CAST(heure_operation AS STRING), 6, '0'), 3, 2) AS INT) * 60
                  + CAST(SUBSTR(LPAD(CAST(heure_operation AS STRING), 6, '0'), 5, 2) AS INT)   AS t_abs,
                    CAST(montant_ope AS DOUBLE) / 100                                          AS montant,
                    CAST(REGEXP_REPLACE(CAST(encaisse_theorique AS STRING), '[^0-9.]', '') AS DOUBLE) AS encaisse,   -- texte en euros
                    CASE WHEN COALESCE(REGEXP_REPLACE(CAST(encaisse_theorique AS STRING), '[^0-9]', ''), '') = ''
                         THEN 0 ELSE 1 END                                                     AS encaisse_ok,
                    CASE TRIM(lib_ope) WHEN 'Retrait'              THEN 'RI'      -- retrait COS
                                       WHEN 'Autorisation-Retrait' THEN 'RE'      -- retrait hors COS
                                       ELSE 'CAP' END                                          AS type_op,
                    CASE WHEN CAST(top_annul AS INT) = 1 THEN 1 ELSE 0 END                     AS inabouti,
                    CASE WHEN TRIM(lib_ope) <> 'Capture de Carte' AND COALESCE(CAST(top_annul AS INT), 0) = 0
                         THEN 1 ELSE 0 END                                                     AS est_abouti,
                    COALESCE(CAST(nb_billetsk7_1 AS INT), 0) AS nb1,
                    CAST(val_coupurek7_1 AS INT)             AS val1,
                    COALESCE(CAST(nb_billetsk7_2 AS INT), 0) AS nb2,
                    CAST(val_coupurek7_2 AS INT)             AS val2,
                    COALESCE(CAST(nb_billetsk7_3 AS INT), 0) AS nb3,
                    CAST(val_coupurek7_3 AS INT)             AS val3,
                    COALESCE(CAST(nb_billetsk7_4 AS INT), 0) AS nb4,
                    CAST(val_coupurek7_4 AS INT)             AS val4,
                    (CASE WHEN CAST(val_coupurek7_1 AS INT) = 5 THEN COALESCE(CAST(nb_billetsk7_1 AS INT), 0) ELSE 0 END
                  + CASE WHEN CAST(val_coupurek7_2 AS INT) = 5 THEN COALESCE(CAST(nb_billetsk7_2 AS INT), 0) ELSE 0 END
                  + CASE WHEN CAST(val_coupurek7_3 AS INT) = 5 THEN COALESCE(CAST(nb_billetsk7_3 AS INT), 0) ELSE 0 END
                  + CASE WHEN CAST(val_coupurek7_4 AS INT) = 5 THEN COALESCE(CAST(nb_billetsk7_4 AS INT), 0) ELSE 0 END) AS b5,
                    (CASE WHEN CAST(val_coupurek7_1 AS INT) = 10 THEN COALESCE(CAST(nb_billetsk7_1 AS INT), 0) ELSE 0 END
                  + CASE WHEN CAST(val_coupurek7_2 AS INT) = 10 THEN COALESCE(CAST(nb_billetsk7_2 AS INT), 0) ELSE 0 END
                  + CASE WHEN CAST(val_coupurek7_3 AS INT) = 10 THEN COALESCE(CAST(nb_billetsk7_3 AS INT), 0) ELSE 0 END
                  + CASE WHEN CAST(val_coupurek7_4 AS INT) = 10 THEN COALESCE(CAST(nb_billetsk7_4 AS INT), 0) ELSE 0 END) AS b10,
                    (CASE WHEN CAST(val_coupurek7_1 AS INT) = 20 THEN COALESCE(CAST(nb_billetsk7_1 AS INT), 0) ELSE 0 END
                  + CASE WHEN CAST(val_coupurek7_2 AS INT) = 20 THEN COALESCE(CAST(nb_billetsk7_2 AS INT), 0) ELSE 0 END
                  + CASE WHEN CAST(val_coupurek7_3 AS INT) = 20 THEN COALESCE(CAST(nb_billetsk7_3 AS INT), 0) ELSE 0 END
                  + CASE WHEN CAST(val_coupurek7_4 AS INT) = 20 THEN COALESCE(CAST(nb_billetsk7_4 AS INT), 0) ELSE 0 END) AS b20,
                    (CASE WHEN CAST(val_coupurek7_1 AS INT) = 50 THEN COALESCE(CAST(nb_billetsk7_1 AS INT), 0) ELSE 0 END
                  + CASE WHEN CAST(val_coupurek7_2 AS INT) = 50 THEN COALESCE(CAST(nb_billetsk7_2 AS INT), 0) ELSE 0 END
                  + CASE WHEN CAST(val_coupurek7_3 AS INT) = 50 THEN COALESCE(CAST(nb_billetsk7_3 AS INT), 0) ELSE 0 END
                  + CASE WHEN CAST(val_coupurek7_4 AS INT) = 50 THEN COALESCE(CAST(nb_billetsk7_4 AS INT), 0) ELSE 0 END) AS b50,
                    (CASE WHEN CAST(val_coupurek7_1 AS INT) = 100 THEN COALESCE(CAST(nb_billetsk7_1 AS INT), 0) ELSE 0 END
                  + CASE WHEN CAST(val_coupurek7_2 AS INT) = 100 THEN COALESCE(CAST(nb_billetsk7_2 AS INT), 0) ELSE 0 END
                  + CASE WHEN CAST(val_coupurek7_3 AS INT) = 100 THEN COALESCE(CAST(nb_billetsk7_3 AS INT), 0) ELSE 0 END
                  + CASE WHEN CAST(val_coupurek7_4 AS INT) = 100 THEN COALESCE(CAST(nb_billetsk7_4 AS INT), 0) ELSE 0 END) AS b100,
                    (CASE WHEN CAST(val_coupurek7_1 AS INT) IN (5, 10, 20, 50, 100) OR COALESCE(CAST(nb_billetsk7_1 AS INT), 0) = 0 THEN 0 ELSE COALESCE(CAST(nb_billetsk7_1 AS INT), 0) END
                  + CASE WHEN CAST(val_coupurek7_2 AS INT) IN (5, 10, 20, 50, 100) OR COALESCE(CAST(nb_billetsk7_2 AS INT), 0) = 0 THEN 0 ELSE COALESCE(CAST(nb_billetsk7_2 AS INT), 0) END
                  + CASE WHEN CAST(val_coupurek7_3 AS INT) IN (5, 10, 20, 50, 100) OR COALESCE(CAST(nb_billetsk7_3 AS INT), 0) = 0 THEN 0 ELSE COALESCE(CAST(nb_billetsk7_3 AS INT), 0) END
                  + CASE WHEN CAST(val_coupurek7_4 AS INT) IN (5, 10, 20, 50, 100) OR COALESCE(CAST(nb_billetsk7_4 AS INT), 0) = 0 THEN 0 ELSE COALESCE(CAST(nb_billetsk7_4 AS INT), 0) END) AS b_autre,
                    (COALESCE(CAST(nb_billetsk7_1 AS DOUBLE), 0) * COALESCE(CAST(val_coupurek7_1 AS DOUBLE), 0)
                  + COALESCE(CAST(nb_billetsk7_2 AS DOUBLE), 0) * COALESCE(CAST(val_coupurek7_2 AS DOUBLE), 0)
                  + COALESCE(CAST(nb_billetsk7_3 AS DOUBLE), 0) * COALESCE(CAST(val_coupurek7_3 AS DOUBLE), 0)
                  + COALESCE(CAST(nb_billetsk7_4 AS DOUBLE), 0) * COALESCE(CAST(val_coupurek7_4 AS DOUBLE), 0)) AS montant_billets,
                    CASE
                        WHEN UPPER(TRIM(lib_motif_capture_carte)) LIKE 'OUBLI CARTE%'
                          OR UPPER(TRIM(lib_motif_capture_carte)) LIKE 'OUBLI DE CARTE%'
                          OR UPPER(TRIM(lib_motif_capture_carte)) LIKE 'INCIDENT LECT%'                THEN 'oubli_lecture'
                        WHEN UPPER(TRIM(lib_motif_capture_carte)) LIKE 'CAPTURE CARTE COS%'          THEN 'capture_cos'
                        WHEN UPPER(TRIM(lib_motif_capture_carte)) LIKE 'CARTE PERDU%'                 THEN 'carte_perdue'
                        WHEN UPPER(TRIM(lib_motif_capture_carte)) LIKE 'CONSERVER%'                    THEN 'conserver_carte'
                        WHEN UPPER(TRIM(lib_motif_capture_carte)) LIKE 'CARTE VOL%'
                          OR UPPER(TRIM(lib_motif_capture_carte)) LIKE 'VOL DE CARTE%'                 THEN 'carte_volee'
                        ELSE 'autre'                                                                   -- motif inconnu ou vide
                    END                                                                        AS motif,
                    -- réseau de carte, d'après le croisement type_reseau x code_carte_privative observé sur les données réelles
                    CASE
                        WHEN LPAD(TRIM(CAST(type_reseau AS STRING)), 2, '0') = '03'  THEN 'interne'   -- y compris produits CPE, C24'
                        WHEN LPAD(TRIM(CAST(type_reseau AS STRING)), 2, '0') = '00'  THEN 'cb'
                        WHEN LPAD(TRIM(CAST(type_reseau AS STRING)), 2, '0') = '01'  THEN 'visa'
                        WHEN LPAD(TRIM(CAST(type_reseau AS STRING)), 2, '0') = '02'  THEN 'mastercard'
                        WHEN LPAD(TRIM(CAST(type_reseau AS STRING)), 2, '0') = '11'  THEN 'cos'
                        WHEN LPAD(TRIM(CAST(type_reseau AS STRING)), 2, '0') = '07'  THEN 'amex'
                        WHEN LPAD(TRIM(CAST(type_reseau AS STRING)), 2, '0') = '12'  THEN 'jcb'
                        WHEN UPPER(TRIM(COALESCE(code_carte_privative, ''))) = 'CUP' THEN 'cup'      -- réseau 10 = Trionis, précisé par le code privatif
                        WHEN UPPER(TRIM(COALESCE(code_carte_privative, ''))) = 'DIN' THEN 'diners'
                        WHEN UPPER(TRIM(COALESCE(code_carte_privative, ''))) = 'AMX' THEN 'amex'
                        WHEN UPPER(TRIM(COALESCE(code_carte_privative, ''))) = 'JCB' THEN 'jcb'
                        WHEN UPPER(TRIM(COALESCE(code_carte_privative, ''))) = 'COS' THEN 'cos'
                        ELSE 'autre'
                    END                                                                        AS cat_reseau
                FROM `base`.`table_operations`
                WHERE TRIM(lib_ope) IN ('Retrait', 'Autorisation-Retrait', 'Capture de Carte')   -- TEST : AND date_operation LIKE '__102026'
            ) o
        ) ops
        GROUP BY num_automate, date_jour
    ) a
      ON  cal.num_automate              = a.cle_gab
     AND CAST(cal.date_jour AS STRING) = CAST(a.cle_jour AS STRING)
) t
