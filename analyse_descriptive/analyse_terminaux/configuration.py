"""Configuration par défaut : noms de colonnes, codes métier, options et seuils.

Rien n'est codé en dur ailleurs dans la librairie : tout passe par le dictionnaire renvoyé par
`configuration()`, que le notebook peut surcharger partiellement, par exemple :

    conf = configuration(colonnes={"num_automate": "id_terminal"}, seuils={"rafale_min_10min": 15})
"""
import copy

# Valeurs FICTIVES (format de la table de test) : à remplacer par les noms de la vraie table, de préférence
# dans la cellule « Configuration » du notebook. Clé = nom utilisé dans le code ; valeur = nom dans la table.
COLONNES = {
    "num_automate": "id_terminal",
    "date_operation": "date_ope",
    "heure_operation": "heure_ope",
    "montant_ope": "montant_centimes",
    "lib_ope": "libelle_ope",
    "type_reseau": "code_reseau",
    "code_carte_privative": "code_carte_speciale",
    "top_annule": "flag_annulation",
    "lib_motif_capture_carte": "motif_capture",
    "date_validite_carte": "fin_validite_carte",
    "code_site": "code_site",
    "libelle_site": "type_site",
    "code_postal": "cp",
    "ville": "commune",
    "longitude": "lon",
    "latitude": "lat",
    "nb1": "nb_billets_1", "nb2": "nb_billets_2", "nb3": "nb_billets_3", "nb4": "nb_billets_4",
    "coupure1": "valeur_billet_1", "coupure2": "valeur_billet_2", "coupure3": "valeur_billet_3",
    "coupure4": "valeur_billet_4",
    "id_carte": "id_carte",          # facultatif : identifiant de carte anonymisé (règle 25)
}

MOTS_CLES = {
    "num_automate": [["automate"], ["terminal"]],
    "date_operation": [["date", "op"]],
    "heure_operation": [["heure"]],
    "montant_ope": [["montant"]],
    "lib_ope": [["lib", "ope"]],
    "type_reseau": [["type", "reseau"], ["reseau"]],
    "code_carte_privative": [["privative"]],
    "top_annule": [["annul"]],
    "lib_motif_capture_carte": [["motif"]],
    "date_validite_carte": [["validit"]],
    "code_site": [["code", "site"]],
    "libelle_site": [["lib", "site"]],
    "code_postal": [["postal"]],
    "ville": [["ville"]],
    "longitude": [["longitude"], ["lon"]],
    "latitude": [["latitude"], ["lat"]],
    "id_carte": [["id_carte"], ["hash"]],
}
MOTS_CLES.update({"nb{}".format(i): [["nb{}".format(i)]] for i in range(1, 5)})
MOTS_CLES.update({"coupure{}".format(i): [["coupure", str(i)]] for i in range(1, 5)})

COLONNES_OBLIGATOIRES = ["num_automate", "date_operation", "montant_ope", "lib_ope"]

# Codes et libellés FICTIFS : à remplacer par les règles de gestion réelles.
CODES_RESEAU = {        # code réseau (sur 2 caractères) -> nom du réseau
    "10": "Reseau national", "20": "Reseau international 1", "30": "Reseau international 2",
    "40": "Reseau interne", "50": "Reseau etranger A", "60": "Reseau etranger B",
}
CODES_PRIVATIVE = {     # code de carte spéciale -> nom (utilisé quand le code réseau n'est pas dans la liste)
    "SPA": "Reseau etranger C", "SPB": "Reseau etranger D", "SPC": "Carte privative X",
}
GROUPES_RESEAU = {      # nom du réseau -> groupe affiché dans les graphiques
    "Reseau national": "National", "Carte interbancaire": "Interbancaire",
    "Reseau international 1": "International 1", "Reseau international 2": "International 2",
    "Reseau etranger A": "Etrangeres rares", "Reseau etranger B": "Etrangeres rares",
    "Reseau etranger C": "Etrangeres rares", "Reseau etranger D": "Etrangeres rares",
    "Reseau interne": "interne",
}

METIER = {
    "codes_reseau": CODES_RESEAU,
    "codes_privative": CODES_PRIVATIVE,
    "groupes_reseau": GROUPES_RESEAU,
    "groupe_par_defaut": "Privatives / autres",
    "reseau_interne": "Reseau interne",          # captures internes / « hors réseau interne »
    "reseaux_etrangers": ["Reseau etranger A", "Reseau etranger B", "Reseau etranger C", "Reseau etranger D"],
    # Type d'opération selon le libellé (sans majuscules ; le premier motif trouvé l'emporte)
    "types_operation": [("%AUTRE BANQUE%", "RETRAIT_EXTERNE"), ("%CAPTURE%", "CAPTURE"),
                        ("%RETRAIT%", "RETRAIT_INTERNE")],
    # Motif normalisé -> libellés de la table (en majuscules)
    "motifs_capture": {
        "OUBLI_OU_INCIDENT_LECTURE": ["MOTIF INCIDENT LECTURE"],
        "CODE_CONFIDENTIEL_DEPASSE": ["MOTIF CODE FAUX"],
        "CARTE_PERDUE": ["MOTIF CARTE PERDUE"],
        "CONSERVER_LA_CARTE": ["MOTIF CONSERVATION"],
        "CARTE_VOLEE": ["MOTIF CARTE VOLEE"],
    },
    "billets_par_defaut": {"nb1": 5, "nb2": 10, "nb3": 20, "nb4": 50},
}

OPTIONS = {
    "format_date": "ddMMyyyy",       # format de date_operation quand c'est du texte
    "diviseur_montant": 100,         # montant_ope en centimes -> euros (1 si déjà en euros)
    "heure_debut_jour": 7,           # plage horaire étudiée pour les silences et les trous horaires
    "heure_fin_jour": 22,
    "date_debut": None,              # None = toute la table
    "date_fin": None,
    "persister": True,               # garde les tables préparées en mémoire / disque du cluster
    "groupe_pairs": "libelle_site",  # terminal comparables entre eux (type de site, ville, code_postal...)
    "zone": "departement",           # zone géographique des règles 19-20 : departement, code_postal ou ville
    "sites_interieurs": None,        # règle 24 limitée à ces sites (ex. ["Agence"]) ; None = tous les terminaux
    "jours_particuliers": [],        # dates à atténuer dans le score (vacances, événements) ; fériés automatiques
    "metropole": {"longitude": (-5.5, 10.0), "latitude": (41.0, 51.5)},
}

SEUILS = {
    # --- anomalies directes (01 à 11)
    "silence_proba": 1e-5,           # 01 : probabilité maximale que le silence arrive par hasard
    "muet_quantile_parc": 0.90,      # 02 : terminal « très fréquenté » = 10 % du parc le plus actif
    "muet_retraits_habituels": 7,    # 02 : retraits habituels minimum ce jour de la semaine
    "rafale_min_10min": 10,          # 03 : opérations en 10 minutes
    "rafale_facteur": 2,             # 03 : x niveau élevé habituel du terminal (99e centile)
    "meme_montant_min": 6,           # 04 : retraits du même montant...
    "meme_montant_fenetre_s": 300,   # 04 : ... en 5 minutes
    "inaboutis_serie_min": 3,        # 05 : inaboutis consécutifs
    "captures_heure_min": 3,         # 06 : captures hors réseau interne en une heure
    "etrangers_heure_min": 20,       # 07 : retraits de cartes étrangères rares en une heure
    "etrangers_facteur": 5,          # 07 : x niveau horaire habituel du terminal (90e centile)
    "nuit_min": 3,                   # 08 : retraits entre 0 h et 5 h...
    "nuit_part_max": 0.01,           # 08 : ... sur un terminal dont moins de 1 % des retraits sont la nuit
    "volume_ratio": 3,               # 10 : retraits x3
    "volume_ecart": 4,               # 10 : et à plus de 4 écarts
    "volume_habitude_min": 10,       # 10 : sur un terminal qui fait au moins 10 retraits ce jour-là
    "montant_ratio": 3,              # 11 : montant moyen x3
    "montant_retraits_min": 5,       # 11 : avec au moins 5 retraits dans la journée
    # --- anomalies cachées (12 à 17)
    "profil_volume_min": 20,         # 12 : retraits minimum dans la journée pour juger sa forme horaire
    "profil_ecarts_robustes": 6,     # 12 : divergence > médiane + 6 écarts robustes du terminal...
    "profil_divergence_min": 0.20,   # 12 : ... et > 0,20 (divergence de Jensen-Shannon, entre 0 et 1)
    "reseaux_volume_min": 50,        # 13 : idem pour le mélange des réseaux de cartes
    "reseaux_ecarts_robustes": 6,
    "reseaux_divergence_min": 0.12,
    "pairs_ratio_bas": 0.4,          # 14 : le terminal tombe sous 40 % de son habitude...
    "pairs_ratio_normal": 0.8,       # 14 : ... alors que ses pairs restent au-dessus de 80 %
    "pairs_ratio_haut": 2.5,         # 14 : ou dépasse 250 % quand ses pairs restent sous 130 %
    "pairs_ratio_haut_pairs": 1.3,
    "pairs_nb_min": 5,               # 14 : au moins 5 terminaux pairs ce jour-là
    "pairs_habitude_min": 20,        # 14 : terminal qui fait habituellement au moins 20 retraits ce jour-là
    "derive_ratio": 0.6,             # 15 : les 4 dernières semaines < 60 % des 8 précédentes...
    "derive_semaine_min": 0.25,      # 15 : ... sans semaine quasi nulle (ce serait une panne)
    "derive_pairs_min": 0.85,        # 15 : ... alors que les pairs restent au-dessus de 85 %
    "derive_reference_min": 50,      # 15 : référence d'au moins 50 retraits par semaine
    "trou_part_jours_vides": 0.5,    # 16 : heure vide plus d'un jour sur deux dans le mois...
    "trou_taux_horaire_min": 3,      # 16 : ... alors que le terminal devrait y faire au moins 3 retraits ce mois-là
    "trou_jours_min": 20,            # 16 : sur au moins 20 jours d'activité dans le mois
    "multivarie_part": 0.001,        # 17 : 0,1 % des journées terminal, parmi celles qu'aucune autre règle n'a vues
    "multivarie_echantillon": 300000,
    # --- anomalies avancées (18 à 26)
    "cassette_retraits_min": 30,         # 18 : journée d'au moins 30 retraits...
    "cassette_part_habituelle_min": 0.15,  # 18 : ... coupure qui pèse habituellement au moins 15 % des billets...
    "cassette_part_restante_max": 0.10,  # 18 : ... tombée sous 10 % de sa part habituelle
    "zone_silence_proba": 1e-3,          # 19 : terminal muet = dans un silence de probabilité < 1/1 000 (règle 01)...
    "zone_terminal_min": 5,                   # 19 : ... au moins 5 terminaux d'une même zone muets à la même heure
    "coordonnee_rafale_min": 15,         # 20 : heure suspecte = rafale d'au moins 15 opérations en 10 min...
    "coordonnee_meme_montant_min": 6,    # 20 : ... ou 6 retraits du même montant en 5 min...
    "coordonnee_etrangers_min": 10,      # 20 : ... ou 10 retraits de cartes étrangères rares
    "coordonnee_terminal_min": 3,             # 20 : sur au moins 3 terminaux d'une même zone dans la même heure
    "motifs_surveilles": ["CARTE_VOLEE", "CARTE_PERDUE", "CODE_CONFIDENTIEL_DEPASSE", "OUBLI_OU_INCIDENT_LECTURE"],
    "motif_min": 3,                      # 21 : au moins 3 captures d'un même motif dans la journée...
    "motif_proba": 1e-4,                 # 21 : ... avec une probabilité de hasard < 1/10 000 (Poisson)
    "reseau_retraits_min": 5,            # 22 : au moins 5 retraits du réseau dans la journée...
    "reseau_taux_min": 0.3,              # 22 : ... dont au moins 30 % d'inaboutis...
    "reseau_facteur": 5,                 # 22 : ... soit 5 fois le taux habituel du réseau sur ce terminal...
    "reseau_taux_autres_max": 0.1,       # 22 : ... alors que les autres réseaux restent sous 10 %
    "regulier_nb_retraits": 8,           # 23 : le même délai entre deux retraits (à la seconde) revient 8 fois...
    "regulier_delai_min_s": 10,          # 23 : ... délai compris entre 10 s...
    "regulier_delai_max_s": 180,         # 23 : ... et 3 minutes...
    "regulier_fenetre_s": 900,           # 23 : ... dans une fenêtre de +/- 15 minutes...
    "regulier_proba": 1e-6,              # 23 : ... avec une probabilité de hasard < 1/1 000 000 (Poisson)
    "heure_morte_retraits_min": 3,       # 24 : au moins 3 retraits dans l'heure...
    "heure_morte_part_max": 0.01,        # 24 : ... à une heure active moins de 1 % des jours
    "carte_vitesse_max_kmh": 300,        # 25 : déplacement impossible au-delà de 300 km/h
    "annee_ratio": 3,                    # 26 : retraits x3 ou /3 par rapport à l'année précédente...
    "annee_habitude_min": 10,            # 26 : ... pour un terminal qui faisait au moins 10 retraits
}


def configuration(**surcharges):
    """Configuration complète, avec les valeurs par défaut surchargées par `surcharges`.

    Les clés sont : colonnes, mots_cles, colonnes_obligatoires, metier, options, seuils.
    Une surcharge de dictionnaire ne remplace que les clés indiquées.
    """
    conf = copy.deepcopy({
        "colonnes": COLONNES, "mots_cles": MOTS_CLES, "colonnes_obligatoires": COLONNES_OBLIGATOIRES,
        "metier": METIER, "options": OPTIONS, "seuils": SEUILS,
    })
    for cle, valeur in surcharges.items():
        if cle not in conf:
            raise KeyError("Clé de configuration inconnue : {} (attendu : {})".format(cle, sorted(conf)))
        if isinstance(conf[cle], dict) and isinstance(valeur, dict):
            conf[cle].update(valeur)
        else:
            conf[cle] = valeur
    return conf
