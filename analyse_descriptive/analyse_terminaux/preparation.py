"""Lecture de la table brute, correspondance des colonnes, typage et enrichissement au grain transaction."""
from pyspark.sql import SparkSession, Window
from pyspark.sql import functions as F

from .outils import CLE_TERMINAL, en_nombre, fmt_nombre, persister, selon_correspondance


def lire_table(dataset=None, table_hive=None):
    """Lit la table brute : par le dataset Dataiku (recommandé) ou par son nom Hive."""
    spark = SparkSession.builder.getOrCreate()
    if dataset:
        import dataiku
        import dataiku.spark as dkuspark
        from pyspark.sql import SQLContext
        return dkuspark.get_dataframe(SQLContext(spark.sparkContext), dataiku.Dataset(dataset))
    if table_hive:
        return spark.table(table_hive)
    raise ValueError("Indiquer le dataset Dataiku ou la table Hive à lire.")


def associer_colonnes(colonnes_table, colonnes, mots_cles):
    """Pour chaque colonne attendue : nom exact, sinon sans tenir compte des majuscules, sinon mots-clés.

    Renvoie {colonne attendue: colonne trouvée dans la table, ou None}.
    """
    minuscules = {c.lower(): c for c in colonnes_table}
    deja_prises, correspondance = set(), {}
    for cle, nom in colonnes.items():
        trouve = nom if nom in colonnes_table else minuscules.get((nom or "").lower())
        for mots in mots_cles.get(cle, []) if trouve is None else []:
            candidates = [c for c in colonnes_table
                          if c not in deja_prises and all(m in c.lower() for m in mots)]
            if candidates:
                trouve = candidates[0]
                break
        correspondance[cle] = trouve
        if trouve:
            deja_prises.add(trouve)
    return correspondance


def standardiser(source, conf):
    """Renomme les colonnes de la table selon la configuration ; les colonnes absentes sont créées vides.

    Renvoie (table standardisée, correspondance).
    """
    correspondance = associer_colonnes(source.columns, conf["colonnes"], conf["mots_cles"])
    manquantes = [cle for cle in conf["colonnes_obligatoires"] if not correspondance[cle]]
    if manquantes:
        raise ValueError("Colonnes indispensables introuvables : {} (configuration « colonnes »)".format(
            manquantes))
    brut = source.select([F.col(nom).alias(cle) if nom else F.lit(None).cast("string").alias(cle)
                          for cle, nom in correspondance.items()])
    return brut, correspondance


def coupures_presentes(correspondance):
    """Vrai si les 4 colonnes coupure existent dans la table."""
    return all(correspondance.get("coupure{}".format(i)) for i in range(1, 5))


def geographie_presente(correspondance):
    """Vrai si longitude et latitude existent dans la table."""
    return bool(correspondance.get("longitude") and correspondance.get("latitude"))


def expression_date(type_colonne, format_date):
    """Date d'opération, que la colonne soit une date ou du texte."""
    if type_colonne in ("date", "timestamp"):
        return F.to_date(F.col("date_operation"))
    texte = F.trim(F.col("date_operation").cast("string"))
    if format_date in ("ddMMyyyy", "yyyyMMdd"):
        texte = F.lpad(texte, 8, "0")
    return F.to_date(texte, format_date)


def expression_heure():
    """Heure au format HHMMSS sur 6 chiffres (séparateurs retirés, zéros initiaux rétablis)."""
    chiffres = F.regexp_replace(F.trim(F.col("heure_operation").cast("string")), "[^0-9]", "")
    return F.lpad(chiffres, 6, "0")


def expression_reseau(metier):
    """Catégorie de réseau : code type_reseau, puis code de carte privative, sinon le code brut."""
    code_reseau = F.lpad(F.trim(F.col("type_reseau").cast("string")), 2, "0")
    code_privative = F.trim(F.col("code_carte_privative").cast("string"))
    categorie = selon_correspondance(code_reseau, metier["codes_reseau"])
    categorie = categorie.when(code_privative == "", "Carte interbancaire")
    for code, nom in metier["codes_privative"].items():
        categorie = categorie.when(code_privative == code, nom)
    return (categorie.when(code_privative.isNotNull() & (code_privative != ""), code_privative)
            .otherwise(F.coalesce(code_reseau, F.lit("inconnu"))))


def expression_groupe(metier):
    """Groupe de réseau affiché dans les graphiques."""
    if not metier["groupes_reseau"]:
        return F.col("cat_reseau")
    correspondance = F.create_map([F.lit(x) for paire in metier["groupes_reseau"].items() for x in paire])
    return F.coalesce(correspondance[F.col("cat_reseau")], F.lit(metier["groupe_par_defaut"]))


def expression_motif(metier):
    """Motif de capture normalisé ; tout autre libellé renseigné devient AUTRE_MOTIF."""
    texte = F.upper(F.trim(F.col("lib_motif_capture_carte")))
    motif = F.when(F.lit(False), F.lit(""))
    for nom, libelles in metier["motifs_capture"].items():
        motif = motif.when(texte.isin(libelles), nom)
    return motif.when(F.col("lib_motif_capture_carte").isNotNull(), "AUTRE_MOTIF")


def expression_type_operation(metier):
    """Type d'opération à partir du libellé (sans tenir compte des majuscules ni des espaces)."""
    libelle = F.upper(F.trim(F.col("lib_ope").cast("string")))
    type_op = F.when(F.lit(False), F.lit(""))
    for motif, nom in metier["types_operation"]:
        type_op = type_op.when(libelle.like(motif), nom)
    return type_op


def expression_montant_delivre(brut, correspondance, metier):
    """Montant délivré = somme des (nombre de billets x coupure) ; coupures en euros ou en centimes."""
    if not coupures_presentes(correspondance):
        print("Coupures absentes : valeurs par défaut", metier["billets_par_defaut"])
        termes = [F.coalesce(en_nombre(c), F.lit(0.0)) * v for c, v in metier["billets_par_defaut"].items()]
    else:
        plus_grande = brut.select(F.max(F.greatest(*[en_nombre("coupure{}".format(i)) for i in range(1, 5)]))
                                  .alias("m")).collect()[0]["m"] or 0
        diviseur = 100.0 if plus_grande > 500 else 1.0
        print("Coupures : valeur maximale {} -> divisées par {:.0f}".format(plus_grande, diviseur))
        termes = [F.coalesce(en_nombre("nb{}".format(i)), F.lit(0.0)) *
                  F.coalesce(en_nombre("coupure{}".format(i)), F.lit(0.0)) / diviseur for i in range(1, 5)]
    total = termes[0]
    for terme in termes[1:]:
        total = total + terme
    return total


def construire_operations(brut, correspondance, conf):
    """Une ligne par opération (retrait ou capture), typée et enrichie de ses indicateurs propres."""
    metier, options = conf["metier"], conf["options"]
    date_op = expression_date(dict(brut.dtypes)["date_operation"], options["format_date"])
    heure_txt = expression_heure()
    type_op = expression_type_operation(metier)
    est_retrait = F.col("est_retrait") == 1
    ops = (brut
           .filter(type_op.isNotNull())
           .select(F.col(CLE_TERMINAL),
                   date_op.alias("date"),
                   heure_txt.substr(1, 2).cast("int").alias("heure"),
                   heure_txt.substr(3, 2).cast("int").alias("minute"),
                   F.to_timestamp(F.concat(F.date_format(date_op, "yyyyMMdd"), heure_txt), "yyyyMMddHHmmss")
                   .alias("ts"),
                   (en_nombre("montant_ope") / options["diviseur_montant"]).alias("montant"),
                   F.trim(F.col("date_validite_carte").cast("string")).alias("validite_txt"),
                   type_op.alias("type_op"),
                   expression_reseau(metier).alias("cat_reseau"),
                   expression_motif(metier).alias("motif_capture"),
                   F.coalesce(F.col("top_annule").cast("int"), F.lit(0)).alias("top_annule"),
                   expression_montant_delivre(brut, correspondance, metier).alias("montant_billets"),
                   *[F.coalesce(en_nombre("nb{}".format(i)), F.lit(0.0)).alias("billets_nb{}".format(i))
                     for i in range(1, 5)],
                   F.col("id_carte").cast("string").alias("id_carte"))
           .withColumn("est_retrait", F.col("type_op").isin("RETRAIT_INTERNE", "RETRAIT_EXTERNE").cast("int"))
           .withColumn("est_capture", (F.col("type_op") == "CAPTURE").cast("int"))
           .filter((F.col("est_capture") == 1) | (F.col("montant") > 0))
           .withColumn("groupe_reseau", expression_groupe(metier))
           .withColumn("est_etranger", F.col("cat_reseau").isin(metier["reseaux_etrangers"]).cast("int"))
           .withColumn("est_reseau_interne", (F.col("cat_reseau") == metier["reseau_interne"]).cast("int"))
           .withColumn("est_capture_interne", F.col("est_capture") * F.col("est_reseau_interne"))
           .withColumn("est_capture_externe", F.col("est_capture") * (1 - F.col("est_reseau_interne")))
           .withColumn("ecart_billets", F.col("montant") - F.col("montant_billets"))
           .withColumn("inabouti_annule", (est_retrait & (F.col("top_annule") == 1)).cast("int"))
           .withColumn("inabouti_billets", (est_retrait & (F.abs(F.col("ecart_billets")) > 0.001)).cast("int"))
           .withColumn("inabouti", F.greatest("inabouti_annule", "inabouti_billets"))
           .withColumn("est_nuit", ((F.col("heure") >= 22) | (F.col("heure") < 6)).cast("int"))
           .withColumn("jour_semaine", F.dayofweek("date"))
           .withColumn("mois", F.trunc("date", "month")))
    if options["date_debut"]:
        ops = ops.filter(F.col("date") >= F.lit(options["date_debut"]).cast("date"))
    if options["date_fin"]:
        ops = ops.filter(F.col("date") <= F.lit(options["date_fin"]).cast("date"))
    return persister(ops, options["persister"])


def enrichir_transactions(ops, actif_persistance=True):
    """Ajoute à chaque opération des indicateurs calculés à partir de ses voisines sur le même terminal.

    delai_precedente_s / delai_suivante_s, rang_dans_journee, nb_ope_5min (opérations à +/- 5 min),
    meme_montant_precedent, inabouti_precedent, capture_dans_l_heure (captures dans l'heure qui précède).
    """
    dans_le_temps = Window.partitionBy(CLE_TERMINAL).orderBy("t")
    journee_dans_le_temps = Window.partitionBy(CLE_TERMINAL, "date").orderBy("t")
    est_retrait = F.col("est_retrait") == 1
    transactions = (ops.filter(F.col("ts").isNotNull())
                    .withColumn("t", F.unix_timestamp("ts"))
                    .withColumn("delai_precedente_s", F.col("t") - F.lag("t").over(dans_le_temps))
                    .withColumn("delai_suivante_s", F.lead("t").over(dans_le_temps) - F.col("t"))
                    .withColumn("rang_dans_journee", F.row_number().over(journee_dans_le_temps))
                    .withColumn("nb_ope_5min", F.count("*").over(dans_le_temps.rangeBetween(-300, 300)))
                    .withColumn("meme_montant_precedent",
                                (est_retrait & (F.col("montant") == F.lag("montant").over(dans_le_temps)))
                                .cast("int"))
                    .withColumn("inabouti_precedent", F.coalesce(F.lag("inabouti").over(dans_le_temps), F.lit(0)))
                    .withColumn("capture_dans_l_heure",
                                F.sum("est_capture").over(dans_le_temps.rangeBetween(-3600, -1))))
    return persister(transactions, actif_persistance)


def vue_terminal_jour(ops, actif_persistance=True):
    """Comptages par terminal et par jour (vue pour les graphiques et les règles journalières)."""
    est_retrait = F.col("est_retrait") == 1
    vue = (ops.groupBy(CLE_TERMINAL, "date")
           .agg(F.sum("est_retrait").alias("retraits"),
                F.sum("est_capture").alias("captures"),
                F.sum("est_capture_interne").alias("captures_interne"),
                F.sum("est_capture_externe").alias("captures_externe"),
                F.sum("inabouti").alias("inaboutis"),
                F.sum(F.when(est_retrait, F.col("est_etranger")).otherwise(0)).alias("etrangers"),
                F.sum(F.when(est_retrait, F.col("montant")).otherwise(0)).alias("montant"),
                F.sum(F.when(est_retrait, F.col("est_nuit")).otherwise(0)).alias("retraits_nuit")))
    return persister(vue, actif_persistance)


def referentiel_terminal(brut, correspondance):
    """Une ligne par terminal : coordonnées, nombre de coordonnées différentes, lieu et site d'implantation."""
    colonnes = [c for c in ("code_postal", "ville", "code_site", "libelle_site") if correspondance.get(c)]
    mesures = [F.first(c, True).alias(c) for c in colonnes]
    if geographie_presente(correspondance):
        mesures += [F.first(en_nombre("longitude"), True).alias("longitude"),
                    F.first(en_nombre("latitude"), True).alias("latitude"),
                    F.countDistinct(F.concat_ws("/", F.col("longitude").cast("string"),
                                                F.col("latitude").cast("string"))).alias("nb_coordonnees")]
    if not mesures:
        return brut.select(CLE_TERMINAL).distinct()
    return brut.groupBy(CLE_TERMINAL).agg(*mesures)


def lire_validite(retraits):
    """Date de fin de validité des cartes (format MMAA, AAMM, AAAAMM ou AAAAMMJJ détecté automatiquement).

    Renvoie une table (num_automate, date, mois_restants) ou None si le format n'est pas reconnu.
    """
    validite = retraits.select(CLE_TERMINAL, "date", F.regexp_replace("validite_txt", "[^0-9]", "").alias("v"))
    longueurs = (validite.filter(F.length("v") > 0).groupBy(F.length("v").alias("longueur")).count()
                 .orderBy(F.desc("count")).limit(1).collect())
    longueur = longueurs[0]["longueur"] if longueurs else 0
    if longueur == 4:
        sens = validite.filter(F.length("v") == 4).agg(
            F.avg((F.substring("v", 1, 2).cast("int") <= 12).cast("int")).alias("mois_devant"),
            F.avg((F.substring("v", 3, 2).cast("int") <= 12).cast("int")).alias("mois_derriere")).collect()[0]
        mois_devant = sens["mois_devant"] >= sens["mois_derriere"]
        print("Date de validité : format", "MMAA" if mois_devant else "AAMM")
        mois_v = F.substring("v", 1, 2) if mois_devant else F.substring("v", 3, 2)
        annee_v = F.substring("v", 3, 2) if mois_devant else F.substring("v", 1, 2)
        fin = F.last_day(F.to_date(F.concat(F.lit("20"), annee_v, F.lit("-"), mois_v, F.lit("-01"))))
    elif longueur in (6, 8):
        fin = F.last_day(F.to_date("v", "yyyyMM" if longueur == 6 else "yyyyMMdd"))
    else:
        print("Format de date de validité non reconnu.")
        return None
    return validite.withColumn("mois_restants", F.months_between(fin, F.col("date"))).drop("v")


def resumer(ops):
    """Chiffres clés de la table préparée."""
    resume = ops.agg(F.count("*").alias("operations"), F.sum("est_retrait").alias("retraits"),
                     F.sum("est_capture").alias("captures"), F.countDistinct(CLE_TERMINAL).alias("terminal"),
                     F.min("date").alias("debut"), F.max("date").alias("fin"),
                     F.countDistinct("date").alias("jours")).collect()[0].asDict()
    for cle, valeur in resume.items():
        print("{:<12}: {}".format(cle, fmt_nombre(valeur) if isinstance(valeur, (int, float)) else valeur))
    return resume
