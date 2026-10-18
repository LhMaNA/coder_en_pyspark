"""Anomalies avancées (règles 18 à 26) : matériel, zone géographique, fraude coordonnée, réseaux, comportements.

18  cassette vide ou défaillante : une coupure disparaît des billets délivrés
19  incident de zone : plusieurs terminaux d'une même zone muets à la même heure (une seule cause commune)
20  attaque coordonnée : activité suspecte sur plusieurs terminaux d'une même zone dans la même heure
21  motif de capture inhabituel : pic de cartes volées, de codes faux ou d'incidents de lecture
22  inaboutis concentrés sur un réseau : un réseau échoue alors que les autres passent
23  rythme trop régulier : retraits espacés de façon quasi constante (script, test)
24  activité à une heure habituellement morte pour ce terminal
25  même carte sur plusieurs terminaux en peu de temps (nécessite un identifiant de carte anonymisé)
26  écart à l'année précédente (nécessite plus d'un an de données)
"""
from pyspark.sql import SparkSession, Window
from pyspark.sql import functions as F

from .anomalies import regle
from .outils import CLE_TERMINAL, fenetre_meme_jour_semaine


def zones(donnees):
    """Zone de chaque terminal (num_automate, zone) selon l'option « zone » : departement, code_postal ou ville."""
    referentiel, choix = donnees.referentiel, donnees.conf["options"]["zone"]
    if referentiel is None:
        return None
    if choix == "departement" and "code_postal" in referentiel.columns:
        code = F.lpad(F.regexp_replace(F.col("code_postal").cast("string"), "[^0-9AB]", ""), 5, "0")
        zone = F.when(code.startswith("97") | code.startswith("98"), code.substr(1, 3)).otherwise(code.substr(1, 2))
    elif choix in referentiel.columns:
        zone = F.col(choix).cast("string")
    else:
        return None
    return referentiel.select(CLE_TERMINAL, zone.alias("zone")).filter(F.col("zone").isNotNull())


# ------------------------------------------------------------------ 18 : cassettes
@regle("18", "Cassette vide ou défaillante")
def regle_cassette(donnees, seuils):
    """Une coupure habituellement délivrée disparaît (ou presque) des billets délivrés dans la journée."""
    if not donnees.coupures_presentes:
        return None
    retraits = donnees.ops.filter(F.col("est_retrait") == 1)
    colonnes = ["nb{}".format(i) for i in range(1, 5)]
    par_jour = retraits.groupBy(CLE_TERMINAL, "date").agg(
        F.count("*").alias("retraits"), *[F.sum(F.col("billets_" + c)).alias(c) for c in colonnes])
    total = sum(F.col(c) for c in colonnes)
    habitude = par_jour.groupBy(CLE_TERMINAL).agg(*[(F.sum(c) / F.sum(total)).alias("part_" + c) for c in colonnes])
    jour = par_jour.join(habitude, CLE_TERMINAL).filter(F.col("retraits") >= seuils["cassette_retraits_min"])
    alertes = None
    for c in colonnes:
        disparue = ((F.col("part_" + c) >= seuils["cassette_part_habituelle_min"]) &
                    (F.col(c) / F.greatest(total, F.lit(1))
                     <= seuils["cassette_part_restante_max"] * F.col("part_" + c)))
        alertes = disparue if alertes is None else alertes | disparue
    return jour.filter(alertes).select(CLE_TERMINAL, "date", F.col("retraits").alias("valeur"))


# ------------------------------------------------------------------ 19 et 20 : zone géographique
@regle("19", "Incident de zone")
def regle_incident_zone(donnees, seuils):
    """Plusieurs terminaux d'une même zone dans un silence improbable à la même heure (cause commune).

    Un terminal compte comme muet à une heure s'il est dans un silence de probabilité < `zone_silence_proba`
    (règle 01 : rythme horaire du terminal recalé sur l'activité du jour, donc insensible à la saison).
    """
    groupes = zones(donnees)
    if groupes is None:
        return None
    spark = SparkSession.builder.getOrCreate()
    heures = spark.range(0, 24).select(F.col("id").cast("int").alias("heure"))
    muets = (donnees.silences().filter(F.col("proba_hasard") < seuils["zone_silence_proba"])
             .crossJoin(heures)
             .filter((F.col("heure") >= F.col("debut_silence")) &
                     (F.col("heure") < F.col("debut_silence") + F.col("silence_h")))
             .select(CLE_TERMINAL, "date", "heure").join(groupes, CLE_TERMINAL))
    simultanes = (muets.groupBy("zone", "date", "heure").agg(F.countDistinct(CLE_TERMINAL).alias("terminal_muets"))
                  .filter(F.col("terminal_muets") >= seuils["zone_terminal_min"]))
    return (muets.join(simultanes, ["zone", "date", "heure"])
            .groupBy(CLE_TERMINAL, "date").agg(F.max("terminal_muets").alias("valeur")))


def activite_suspecte_horaire(donnees, seuils):
    """terminal x jour x heure présentant une rafale, un montant répété ou un pic de cartes étrangères rares."""
    def calcul():
        meme_montant = (Window.partitionBy(CLE_TERMINAL, "montant").orderBy("t")
                        .rangeBetween(0, seuils["meme_montant_fenetre_s"]))
        return (donnees.retraits.withColumn("meme_montant", F.count("*").over(meme_montant))
                .groupBy(CLE_TERMINAL, "date", "heure")
                .agg(F.max("nb_ope_5min").alias("rafale"), F.max("meme_montant").alias("meme_montant"),
                     F.sum("est_etranger").alias("etrangers"))
                .filter((F.col("rafale") >= seuils["coordonnee_rafale_min"]) |
                        (F.col("meme_montant") >= seuils["coordonnee_meme_montant_min"]) |
                        (F.col("etrangers") >= seuils["coordonnee_etrangers_min"])))
    return donnees.memoriser("activite_suspecte_horaire", calcul)


@regle("20", "Attaque coordonnée")
def regle_attaque_coordonnee(donnees, seuils):
    """Activité suspecte (rafale, montant répété, cartes étrangères) sur plusieurs terminaux d'une zone dans l'heure."""
    groupes = zones(donnees)
    if groupes is None:
        return None
    suspects = activite_suspecte_horaire(donnees, seuils).join(groupes, CLE_TERMINAL)
    simultanes = (suspects.groupBy("zone", "date", "heure").agg(F.countDistinct(CLE_TERMINAL).alias("terminal_suspects"))
                  .filter(F.col("terminal_suspects") >= seuils["coordonnee_terminal_min"]))
    return (suspects.join(simultanes, ["zone", "date", "heure"])
            .groupBy(CLE_TERMINAL, "date").agg(F.max("terminal_suspects").alias("valeur")))


# ------------------------------------------------------------------ 21 et 22 : captures et réseaux
@regle("21", "Motif de capture inhabituel")
def regle_motif_capture(donnees, seuils):
    """Captures d'un même motif dans la journée, improbables vu l'habitude du terminal pour ce motif (Poisson)."""
    captures = donnees.ops.filter((F.col("est_capture") == 1) &
                                  F.col("motif_capture").isin(seuils["motifs_surveilles"]))
    par_jour = captures.groupBy(CLE_TERMINAL, "date", "motif_capture").agg(F.count("*").alias("n"))
    nb_jours = donnees.journees.groupBy(CLE_TERMINAL).agg(F.count("*").alias("jours"))
    habitude = (par_jour.groupBy(CLE_TERMINAL, "motif_capture").agg(F.sum("n").alias("total"))
                .join(nb_jours, CLE_TERMINAL).withColumn("par_jour", F.col("total") / F.col("jours")))
    # probabilité d'observer au moins n captures de ce motif par hasard (Poisson, premier terme de la queue)
    lam = F.greatest(F.col("par_jour"), F.lit(1e-3))
    proba = F.pow(lam, F.col("n")) * F.exp(-lam) / F.factorial(F.col("n").cast("int"))
    return (par_jour.join(habitude, [CLE_TERMINAL, "motif_capture"])
            .filter((F.col("n") >= seuils["motif_min"]) & (proba < seuils["motif_proba"]))
            .groupBy(CLE_TERMINAL, "date").agg(F.max("n").alias("valeur")))


@regle("22", "Inaboutis concentrés sur un réseau")
def regle_inaboutis_reseau(donnees, seuils):
    """Les retraits d'un réseau échouent massivement alors que ceux des autres réseaux passent."""
    retraits = donnees.ops.filter(F.col("est_retrait") == 1)
    par_reseau = retraits.groupBy(CLE_TERMINAL, "date", "groupe_reseau").agg(
        F.count("*").alias("n"), F.avg("inabouti").alias("taux"))
    habitude = retraits.groupBy(CLE_TERMINAL, "groupe_reseau").agg(F.avg("inabouti").alias("taux_habituel"))
    autres = (par_reseau.alias("a").join(par_reseau.alias("b"), [CLE_TERMINAL, "date"])
              .filter(F.col("a.groupe_reseau") != F.col("b.groupe_reseau"))
              .groupBy(CLE_TERMINAL, "date", F.col("a.groupe_reseau").alias("groupe_reseau"))
              .agg((F.sum(F.col("b.taux") * F.col("b.n")) / F.sum("b.n")).alias("taux_autres")))
    return (par_reseau.join(habitude, [CLE_TERMINAL, "groupe_reseau"]).join(autres, [CLE_TERMINAL, "date", "groupe_reseau"])
            .filter((F.col("n") >= seuils["reseau_retraits_min"]) &
                    (F.col("taux") >= seuils["reseau_taux_min"]) &
                    (F.col("taux") >= seuils["reseau_facteur"] * F.greatest(F.col("taux_habituel"), F.lit(0.01))) &
                    (F.col("taux_autres") <= seuils["reseau_taux_autres_max"]))
            .groupBy(CLE_TERMINAL, "date").agg(F.max("taux").alias("valeur")))


# ------------------------------------------------------------------ 23 et 24 : comportements
@regle("23", "Rythme trop régulier")
def regle_rythme_regulier(donnees, seuils):
    """Le même délai entre deux retraits (à la seconde près) revient bien plus souvent que le hasard ne le permet.

    Un humain ne retire pas à intervalle constant ; un script ou un test, si. Dans une fenêtre glissante, on
    compare le nombre de délais identiques au nombre attendu si les arrivées étaient aléatoires (loi
    exponentielle des délais au rythme local), puis on calcule la probabilité de hasard (Poisson). Les terminaux
    très chargés, où les délais courts se répètent naturellement, ne sont donc pas signalés.
    """
    fenetre = seuils["regulier_fenetre_s"]
    autour = Window.partitionBy(CLE_TERMINAL).orderBy("t").rangeBetween(-fenetre, fenetre)
    meme_delai = Window.partitionBy(CLE_TERMINAL, "delai").orderBy("t").rangeBetween(-fenetre, fenetre)
    rythme = F.col("retraits_autour") / F.lit(2.0 * fenetre)
    attendu = F.greatest(F.col("retraits_autour") * rythme * F.exp(-rythme * F.col("delai")), F.lit(1e-3))
    k = F.col("repetitions")
    # factorielle plafonnée à 20! (limite Spark) : la probabilité est alors surestimée, donc prudente
    proba = F.exp(k * F.log(attendu) - attendu - F.log(F.factorial(F.least(k, F.lit(20)).cast("int"))))
    return (donnees.retraits
            .withColumn("delai", F.col("delai_precedente_s").cast("int"))
            .withColumn("retraits_autour", F.count("*").over(autour))
            .filter(F.col("delai").between(seuils["regulier_delai_min_s"], seuils["regulier_delai_max_s"]))
            .withColumn("repetitions", F.count("*").over(meme_delai))
            .filter((k >= seuils["regulier_nb_retraits"]) & (proba < seuils["regulier_proba"]))
            .groupBy(CLE_TERMINAL, "date").agg(F.max("repetitions").alias("valeur")))


@regle("24", "Activité à une heure morte")
def regle_heure_morte(donnees, seuils):
    """Plusieurs retraits à une heure où le terminal n'opère presque jamais (ex. agence fermée)."""
    retraits = donnees.ops.filter(F.col("est_retrait") == 1)
    par_heure = retraits.groupBy(CLE_TERMINAL, "date", "heure").agg(F.count("*").alias("n"))
    nb_jours = donnees.journees.groupBy(CLE_TERMINAL).agg(F.count("*").alias("jours"))
    habitude = (par_heure.groupBy(CLE_TERMINAL, "heure").agg(F.count("*").alias("jours_actifs_heure"))
                .join(nb_jours, CLE_TERMINAL).withColumn("part_jours", F.col("jours_actifs_heure") / F.col("jours")))
    resultat = (par_heure.join(habitude, [CLE_TERMINAL, "heure"])
                .filter((F.col("n") >= seuils["heure_morte_retraits_min"]) &
                        (F.col("part_jours") <= seuils["heure_morte_part_max"]) & (F.col("jours") >= 60)))
    sites = donnees.conf["options"]["sites_interieurs"]
    if sites and donnees.referentiel is not None and "libelle_site" in donnees.referentiel.columns:
        resultat = resultat.join(donnees.referentiel.filter(F.col("libelle_site").isin(sites)).select(CLE_TERMINAL),
                                 CLE_TERMINAL)
    return resultat.groupBy(CLE_TERMINAL, "date").agg(F.max("n").alias("valeur"))


# ------------------------------------------------------------------ 25 et 26 : données supplémentaires
@regle("25", "Même carte sur plusieurs terminaux")
def regle_meme_carte(donnees, seuils):
    """Une carte utilisée sur plusieurs terminaux en peu de temps, ou à une vitesse de déplacement impossible."""
    if not donnees.colonne_presente("id_carte") or donnees.referentiel is None or \
            "latitude" not in donnees.referentiel.columns:
        return None
    position = donnees.referentiel.select(CLE_TERMINAL, "longitude", "latitude")
    par_carte = Window.partitionBy("id_carte").orderBy("t")
    retraits = (donnees.retraits.filter(F.col("id_carte").isNotNull()).join(position, CLE_TERMINAL)
                .withColumn("terminal_suivant", F.lead(CLE_TERMINAL).over(par_carte))
                .withColumn("t_suivant", F.lead("t").over(par_carte))
                .withColumn("lat2", F.lead("latitude").over(par_carte))
                .withColumn("lon2", F.lead("longitude").over(par_carte)))
    distance_km = 111.0 * F.sqrt(F.pow(F.col("lat2") - F.col("latitude"), 2) +
                                 F.pow((F.col("lon2") - F.col("longitude")) * F.cos(F.radians("latitude")), 2))
    vitesse = distance_km / F.greatest((F.col("t_suivant") - F.col("t")) / 3600.0, F.lit(1.0 / 60))
    return (retraits.filter((F.col("terminal_suivant") != F.col(CLE_TERMINAL)) &
                            (vitesse >= seuils["carte_vitesse_max_kmh"]))
            .groupBy(CLE_TERMINAL, "date").agg(F.max(vitesse).alias("valeur")))


@regle("26", "Écart à l'année précédente")
def regle_annee_precedente(donnees, seuils):
    """Retraits du jour très différents de ceux des mêmes jours de semaine, un an plus tôt (52 semaines)."""
    journees = donnees.journees
    bornes = journees.agg(F.min("date"), F.max("date")).collect()[0]
    if (bornes[1] - bornes[0]).days < 400:
        return None
    il_y_a_un_an = journees.select(CLE_TERMINAL, F.date_add("date", 364).alias("date"), F.col("retraits").alias("n1"))
    meme_jour = fenetre_meme_jour_semaine(4)
    return (journees.join(il_y_a_un_an, [CLE_TERMINAL, "date"])
            .withColumn("n1_moyen", F.avg("n1").over(meme_jour))
            .filter(F.col("n1_moyen") >= seuils["annee_habitude_min"])
            .withColumn("valeur", F.col("retraits") / F.col("n1_moyen"))
            .filter((F.col("valeur") >= seuils["annee_ratio"]) | (F.col("valeur") <= 1.0 / seuils["annee_ratio"]))
            .select(CLE_TERMINAL, "date", "valeur"))
