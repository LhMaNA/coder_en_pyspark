-- =====================================================================================================
-- RECETTE 1 : VOISINS DE CHAQUE GAB (table quasi fixe, à relancer quand le référentiel change)
-- Entrée  : référentiel GAB final (coordonnées corrigées)
-- Sortie  : voisins_gab, une ligne par GAB et par voisin : les 5 GAB les plus proches à moins de 3 km
-- Méthode : distance à vol d'oiseau (formule de haversine). Pour éviter de comparer chaque GAB aux 6 000 autres,
-- Réglages : RAYON (3 km) et NB_VOISINS (5) en bas de la requête.
-- =====================================================================================================
SELECT
    num_automate,
    voisin,
    distance_km,
    rang_voisin
FROM (
    SELECT
        d.num_automate,
        d.voisin,
        d.distance_km,
        ROW_NUMBER() OVER (PARTITION BY d.num_automate ORDER BY d.distance_km, d.voisin) AS rang_voisin
    FROM (
        SELECT
            a.num_automate,
            b.num_automate AS voisin,
            ROUND(2 * 6371.0 * ASIN(SQRT(
                  POW(SIN(RADIANS(b.lat - a.lat) / 2), 2)
                + COS(RADIANS(a.lat)) * COS(RADIANS(b.lat)) * POW(SIN(RADIANS(b.lon - a.lon) / 2), 2))), 2) AS distance_km
        FROM (
            SELECT
                TRIM(CAST(num_automate AS STRING))     AS num_automate,
                CAST(latitude_finale AS DOUBLE)        AS lat,
                CAST(longitude_finale AS DOUBLE)       AS lon,
                FLOOR(CAST(latitude_finale AS DOUBLE) / 0.05)  AS case_lat,
                FLOOR(CAST(longitude_finale AS DOUBLE) / 0.05) AS case_lon
            FROM `base`.`referentiel_gab`
            WHERE latitude_finale IS NOT NULL AND longitude_finale IS NOT NULL
        ) a
        -- les 9 cases autour de celle du GAB (la sienne comprise)
        LATERAL VIEW EXPLODE(ARRAY(-1, 0, 1)) dl AS d_lat
        LATERAL VIEW EXPLODE(ARRAY(-1, 0, 1)) dn AS d_lon
        JOIN (
            SELECT
                TRIM(CAST(num_automate AS STRING))     AS num_automate,
                CAST(latitude_finale AS DOUBLE)        AS lat,
                CAST(longitude_finale AS DOUBLE)       AS lon,
                FLOOR(CAST(latitude_finale AS DOUBLE) / 0.05)  AS case_lat,
                FLOOR(CAST(longitude_finale AS DOUBLE) / 0.05) AS case_lon
            FROM `base`.`referentiel_gab`
            WHERE latitude_finale IS NOT NULL AND longitude_finale IS NOT NULL
        ) b
          ON  b.case_lat = a.case_lat + d_lat
         AND b.case_lon = a.case_lon + d_lon
        WHERE b.num_automate <> a.num_automate
    ) d
    WHERE d.distance_km <= 3.0                                   -- RAYON
) t
WHERE rang_voisin <= 5                                           -- NB_VOISINS
