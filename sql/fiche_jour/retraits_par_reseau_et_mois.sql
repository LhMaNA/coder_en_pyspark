-- =====================================================================================================
-- RETRAITS PAR MOIS, RÉSEAU x CODE CARTE PRIVATIVE (sur la table brute des opérations)
-- But : vérifier le classement des cartes avant de corriger la fiche, en croisant les DEUX colonnes
--       type_reseau et code_carte_privative (Trionis + CUP = UPI, interne + CPE, interne + C24, réseau 93...).
-- Retrait = lib_ope 'Retrait' ou 'Autorisation-Retrait' ; abouti = top_annul différent de 1 ; montant_ope en centimes.
-- Pour un seul mois : ajouter  AND date_operation LIKE '__102026'  dans le WHERE.
-- Remplacer la table par la table brute si besoin.
-- =====================================================================================================

-- -----------------------------------------------------------------------------------------------------
-- 1) Le détail brut : chaque couple (réseau, code privatif) qui existe, mois par mois. Rien n'est regroupé :
--    on voit tous les codes réellement présents (y compris ceux qu'on ne connaît pas).
-- -----------------------------------------------------------------------------------------------------
SELECT
    mois,
    reseau,
    code_privatif,
    categorie,
    SUM(CASE WHEN abouti = 1 THEN 1 ELSE 0 END)              AS nb_retraits_aboutis,
    SUM(CASE WHEN abouti = 0 THEN 1 ELSE 0 END)              AS nb_retraits_inaboutis,
    ROUND(SUM(CASE WHEN abouti = 1 THEN montant ELSE 0 END)) AS montant_retire_euros
FROM (
    SELECT
        SUBSTR(CAST(date_jour AS STRING), 1, 7)                                   AS mois,
        reseau,
        code_privatif,
        CASE
            WHEN reseau = '03' AND code_privatif IN ('', '-') THEN 'interne (sans code privatif)'
            WHEN reseau = '03' AND code_privatif = 'CPE'      THEN 'interne PostEpargne (CPE)'
            WHEN reseau = '03' AND code_privatif = 'C24'      THEN 'interne Carte 24/24 (C24)'
            WHEN reseau = '03'                                THEN 'interne, autre code privatif'
            WHEN reseau = '93'                                THEN 'réseau 93 (non identifié, interne ?)'
            WHEN reseau = '10' AND code_privatif = 'CUP'      THEN 'Trionis UnionPay (CUP)'
            WHEN reseau = '10' AND code_privatif = 'DIN'      THEN 'Trionis Diners (DIN)'
            WHEN reseau = '10' AND code_privatif = 'JCB'      THEN 'Trionis JCB'
            WHEN reseau = '10' AND code_privatif = 'AMX'      THEN 'Trionis Amex (AMX)'
            WHEN reseau = '10' AND code_privatif IN ('', '-') THEN 'Trionis sans code privatif'
            WHEN reseau = '10'                                THEN 'Trionis, autre code privatif'
            WHEN reseau = '00'                                THEN 'CB'
            WHEN reseau = '01'                                THEN 'Visa'
            WHEN reseau = '02'                                THEN 'Mastercard'
            WHEN reseau = '07'                                THEN 'Amex (réseau 07)'
            WHEN reseau = '11'                                THEN 'COS'
            WHEN reseau = '12'                                THEN 'JCB (réseau 12)'
            ELSE 'autre / inconnu'
        END                                                                       AS categorie,
        abouti,
        montant
    FROM (
        SELECT
            CASE WHEN CAST(date_operation AS STRING) LIKE '____-__-__%'
                 THEN TO_DATE(SUBSTR(CAST(date_operation AS STRING), 1, 10))
                 ELSE TO_DATE(FROM_UNIXTIME(UNIX_TIMESTAMP(LPAD(CAST(date_operation AS STRING), 8, '0'), 'ddMMyyyy')))
            END                                                                   AS date_jour,
            COALESCE(LPAD(TRIM(CAST(type_reseau AS STRING)), 2, '0'), '')         AS reseau,
            UPPER(TRIM(COALESCE(CAST(code_carte_privative AS STRING), '')))       AS code_privatif,
            CASE WHEN COALESCE(CAST(top_annul AS INT), 0) = 1 THEN 0 ELSE 1 END   AS abouti,
            CAST(montant_ope AS DOUBLE) / 100                                     AS montant
        FROM `base`.`table_operations_jointe`
        WHERE TRIM(lib_ope) IN ('Retrait', 'Autorisation-Retrait')
    ) o
) t
GROUP BY mois, reseau, code_privatif, categorie
ORDER BY mois, nb_retraits_aboutis DESC
;


-- -----------------------------------------------------------------------------------------------------
-- 2) Le tableau lisible : une ligne par mois, une colonne par catégorie (retraits aboutis).
--    Les colonnes « total ... » sont des sommes de sous-catégories : ne pas les additionner aux autres.
--    Contrôle : total_retraits = somme de toutes les colonnes de détail (sans les « total »).
-- -----------------------------------------------------------------------------------------------------
SELECT
    mois,
    COUNT(*)                                                                           AS total_retraits,
    -- interne (réseau 03)
    SUM(CASE WHEN reseau = '03' AND code_privatif IN ('', '-') THEN 1 ELSE 0 END)      AS interne_sans_code,
    SUM(CASE WHEN reseau = '03' AND code_privatif = 'CPE' THEN 1 ELSE 0 END)           AS interne_cpe,
    SUM(CASE WHEN reseau = '03' AND code_privatif = 'C24' THEN 1 ELSE 0 END)           AS interne_c24,
    SUM(CASE WHEN reseau = '03' AND code_privatif NOT IN ('', '-', 'CPE', 'C24') THEN 1 ELSE 0 END) AS interne_autre_code,
    SUM(CASE WHEN reseau = '03' THEN 1 ELSE 0 END)                                     AS total_interne_03,
    -- réseau 93 (non identifié)
    SUM(CASE WHEN reseau = '93' THEN 1 ELSE 0 END)                                     AS reseau_93,
    -- Trionis (réseau 10)
    SUM(CASE WHEN reseau = '10' AND code_privatif = 'CUP' THEN 1 ELSE 0 END)           AS trionis_upi_cup,
    SUM(CASE WHEN reseau = '10' AND code_privatif = 'DIN' THEN 1 ELSE 0 END)           AS trionis_diners,
    SUM(CASE WHEN reseau = '10' AND code_privatif = 'JCB' THEN 1 ELSE 0 END)           AS trionis_jcb,
    SUM(CASE WHEN reseau = '10' AND code_privatif = 'AMX' THEN 1 ELSE 0 END)           AS trionis_amex,
    SUM(CASE WHEN reseau = '10' AND code_privatif IN ('', '-') THEN 1 ELSE 0 END)      AS trionis_sans_code,
    SUM(CASE WHEN reseau = '10' AND code_privatif NOT IN ('', '-', 'CUP', 'DIN', 'JCB', 'AMX') THEN 1 ELSE 0 END) AS trionis_autre_code,
    SUM(CASE WHEN reseau = '10' THEN 1 ELSE 0 END)                                     AS total_trionis_10,
    -- autres réseaux
    SUM(CASE WHEN reseau = '00' THEN 1 ELSE 0 END)                                     AS cb_00,
    SUM(CASE WHEN reseau = '01' THEN 1 ELSE 0 END)                                     AS visa_01,
    SUM(CASE WHEN reseau = '02' THEN 1 ELSE 0 END)                                     AS mastercard_02,
    SUM(CASE WHEN reseau = '07' THEN 1 ELSE 0 END)                                     AS amex_07,
    SUM(CASE WHEN reseau = '11' THEN 1 ELSE 0 END)                                     AS cos_11,
    SUM(CASE WHEN reseau = '12' THEN 1 ELSE 0 END)                                     AS jcb_12,
    SUM(CASE WHEN reseau NOT IN ('00', '01', '02', '03', '07', '10', '11', '12', '93') THEN 1 ELSE 0 END) AS autre_ou_inconnu
FROM (
    SELECT
        SUBSTR(CAST(CASE WHEN CAST(date_operation AS STRING) LIKE '____-__-__%'
                         THEN TO_DATE(SUBSTR(CAST(date_operation AS STRING), 1, 10))
                         ELSE TO_DATE(FROM_UNIXTIME(UNIX_TIMESTAMP(LPAD(CAST(date_operation AS STRING), 8, '0'), 'ddMMyyyy')))
                    END AS STRING), 1, 7)                                          AS mois,
        COALESCE(LPAD(TRIM(CAST(type_reseau AS STRING)), 2, '0'), '')              AS reseau,
        UPPER(TRIM(COALESCE(CAST(code_carte_privative AS STRING), '')))            AS code_privatif
    FROM `base`.`table_operations_jointe`
    WHERE TRIM(lib_ope) IN ('Retrait', 'Autorisation-Retrait')
      AND COALESCE(CAST(top_annul AS INT), 0) <> 1                                 -- retraits aboutis
) o
GROUP BY mois
ORDER BY mois
;
