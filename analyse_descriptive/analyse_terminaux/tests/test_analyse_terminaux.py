"""Tests de la librairie analyse_terminaux sur de petites tables construites à la main.

Lancer depuis le dossier qui contient `analyse_terminaux` :  python -m unittest discover -s analyse_terminaux/tests -v
"""
import datetime as dt
import unittest

from pyspark.sql import SparkSession
from pyspark.sql import functions as F

import pandas as pd

from analyse_terminaux import anomalies, anomalies_avancees, anomalies_cachees, preparation, priorisation
from analyse_terminaux.configuration import configuration

JOUR = dt.date(2026, 3, 2)


class TestAvecSpark(unittest.TestCase):
    """Partage une session Spark locale entre les tests."""

    @classmethod
    def setUpClass(cls):
        cls.spark = (SparkSession.builder.master("local[2]").config("spark.sql.shuffle.partitions", "2")
                     .config("spark.ui.enabled", "false").getOrCreate())
        cls.conf = configuration()

    def transactions(self, lignes):
        """Transactions minimales : (num_automate, date, t, montant, est_retrait, est_capture_externe, inabouti)."""
        table = self.spark.createDataFrame(lignes, ["num_automate", "date", "t", "montant", "est_retrait",
                                                    "est_capture_externe", "inabouti"])
        return preparation.enrichir_transactions(
            table.withColumn("ts", F.from_unixtime("t").cast("timestamp"))
                 .withColumn("est_capture", F.col("est_capture_externe")), actif_persistance=False)

    def donnees(self, transactions):
        return anomalies.DonneesAnalyse(None, transactions, None, self.conf)


class TestConfiguration(unittest.TestCase):

    def test_surcharge_partielle(self):
        conf = configuration(seuils={"rafale_min_10min": 99}, colonnes={"num_automate": "code_terminal"})
        self.assertEqual(conf["seuils"]["rafale_min_10min"], 99)
        self.assertEqual(conf["seuils"]["nuit_min"], 3)
        self.assertEqual(conf["colonnes"]["num_automate"], "code_terminal")
        self.assertEqual(conf["colonnes"]["montant_ope"], "montant_centimes")

    def test_cle_inconnue_refusee(self):
        with self.assertRaises(KeyError):
            configuration(seuil={"x": 1})

    def test_valeurs_par_defaut_non_modifiees(self):
        configuration(seuils={"nuit_min": 42})
        self.assertEqual(configuration()["seuils"]["nuit_min"], 3)


class TestCorrespondanceColonnes(unittest.TestCase):

    def test_nom_exact_majuscules_et_mots_cles(self):
        conf = configuration()
        trouve = preparation.associer_colonnes(
            ["ID_TERMINAL", "dt_operation_retrait", "mt_montant", "libelle_ope"], conf["colonnes"],
            conf["mots_cles"])
        self.assertEqual(trouve["num_automate"], "ID_TERMINAL")
        self.assertEqual(trouve["montant_ope"], "mt_montant")
        self.assertEqual(trouve["lib_ope"], "libelle_ope")
        self.assertIsNone(trouve["latitude"])


class TestExpressions(TestAvecSpark):

    def test_type_operation_et_reseau(self):
        table = self.spark.createDataFrame(
            [("Retrait interne", "40", ""), ("RETRAIT AUTRE BANQUE", "20", ""), ("Capture carte", "70", "SPA"),
             ("Consultation", "10", "")], ["lib_ope", "type_reseau", "code_carte_privative"])
        metier = self.conf["metier"]
        resultat = table.select(preparation.expression_type_operation(metier).alias("type"),
                                preparation.expression_reseau(metier).alias("reseau")).collect()
        self.assertEqual([r["type"] for r in resultat], ["RETRAIT_INTERNE", "RETRAIT_EXTERNE", "CAPTURE", None])
        attendus = ["Reseau interne", "Reseau international 1", "Reseau etranger C", "Reseau national"]
        self.assertEqual([r["reseau"] for r in resultat], attendus)


class TestRegles(TestAvecSpark):

    def test_meme_montant_repete(self):
        repetes = [("G1", JOUR, 1000 + 40 * i, 300.0, 1, 0, 0) for i in range(7)]
        normaux = [("G1", JOUR, 5000 + 600 * i, 20.0 * (i % 5 + 1), 1, 0, 0) for i in range(7)]
        resultat = anomalies.regle_meme_montant(self.donnees(self.transactions(repetes + normaux)),
                                                self.conf["seuils"]).collect()
        self.assertEqual(len(resultat), 1)
        self.assertEqual(resultat[0]["valeur"], 7)

    def test_captures_hors_cos_en_serie(self):
        captures = [("G1", JOUR, 1000 + 600 * i, 0.0, 0, 1, 0) for i in range(3)]
        isolees = [("G2", JOUR, 1000 + 7200 * i, 0.0, 0, 1, 0) for i in range(3)]
        resultat = anomalies.regle_captures_serie(self.donnees(self.transactions(captures + isolees)),
                                                  self.conf["seuils"]).collect()
        self.assertEqual([r["num_automate"] for r in resultat], ["G1"])

    def test_inaboutis_en_serie(self):
        lignes = [("G1", JOUR, 1000 + 60 * i, 50.0, 1, 0, 1 if 2 <= i <= 5 else 0) for i in range(10)]
        resultat = anomalies.regle_inaboutis_serie(self.donnees(self.transactions(lignes)),
                                                   self.conf["seuils"]).collect()
        self.assertEqual(len(resultat), 1)
        self.assertEqual(resultat[0]["valeur"], 4)

    def test_registre_complet_et_ordonne(self):
        codes = sorted(r.code for r in anomalies.REGLES)
        self.assertEqual(codes, ["{:02d}".format(i) for i in range(1, 27)])
        self.assertTrue(anomalies_cachees.regle_profil_horaire in [r.fonction for r in anomalies.REGLES])


class TestDivergence(TestAvecSpark):

    def test_jensen_shannon_bornes(self):
        observe = self.spark.createDataFrame([("G1", JOUR, 9, 10), ("G1", JOUR, 10, 10),
                                              ("G2", JOUR, 9, 10)], ["num_automate", "date", "heure", "n"])
        habituel = self.spark.createDataFrame([("G1", 9, 0.5), ("G1", 10, 0.5), ("G2", 20, 1.0)],
                                              ["num_automate", "heure", "q"])
        resultat = {r["num_automate"]: r["divergence"] for r in anomalies_cachees.divergence_jensen_shannon(
            observe, habituel, ["num_automate", "date"], ["num_automate"], "heure").collect()}
        self.assertAlmostEqual(resultat["G1"], 0.0, places=6)    # distribution identique
        self.assertAlmostEqual(resultat["G2"], 1.0, places=6)    # distributions disjointes


class TestReglesAvancees(TestAvecSpark):

    def test_rythme_trop_regulier(self):
        reguliers = [("G1", JOUR, 1000 + 45 * i, 20.0 * (i % 5 + 1), 1, 0, 0) for i in range(12)]
        irreguliers = [("G2", JOUR, 1000 + int(45 * i * (1 + 0.5 * (i % 3))), 20.0, 1, 0, 0) for i in range(12)]
        resultat = anomalies_avancees.regle_rythme_regulier(self.donnees(self.transactions(reguliers + irreguliers)),
                                                            self.conf["seuils"]).collect()
        self.assertEqual([r["num_automate"] for r in resultat], ["G1"])
        self.assertEqual(resultat[0]["valeur"], 11)    # 12 retraits espacés de 45 s = 11 délais identiques


class TestPriorisation(unittest.TestCase):

    def evenements(self):
        return pd.DataFrame({
            "num_automate": ["G1", "G1", "G2", "G3", "G3", "G4", "G4"],
            "date": ["2026-03-02", "2026-02-20", "2026-03-02", "2026-03-02", "2026-03-02", "2026-03-02",
                     "2026-03-02"],
            "type": ["03 Rafale", "03 Rafale", "09 Carte expirée", "19 Incident de zone", "01 Silence anormal",
                     "18 Cassette vide ou défaillante", "05 Inaboutis en série"],
            "valeur": [25, 18, 1, 6, 4, 40, 4]})

    def test_score_niveau_et_raisons(self):
        alertes = priorisation.score_de_risque(self.evenements(), "2026-03-02").set_index("num_automate")
        self.assertEqual(alertes.loc["G4", "niveau"], "Élevé")         # gravités 3 + 2
        self.assertEqual(alertes.loc["G2", "niveau"], "Modéré")        # gravité 1
        self.assertIn("rafale de 25 opérations", alertes.loc["G1", "raisons"])
        self.assertGreater(alertes.loc["G1", "score"], 3)              # récidive sur 28 jours
        self.assertNotIn("Silence", alertes.loc["G3", "anomalies"])    # absorbé par l'incident de zone

    def test_selection_quotidienne_respecte_le_budget(self):
        alertes = priorisation.score_de_risque(self.evenements(), "2026-03-02")
        transmises = priorisation.selection_quotidienne(alertes, budget=1)
        self.assertEqual(len(transmises), 1)
        self.assertTrue(transmises["niveau"].isin(["Critique", "Élevé"]).all())

    def test_precision_par_regle(self):
        retours = pd.DataFrame({"num_automate": ["G1", "G2"], "date": ["2026-03-02", "2026-03-02"],
                                "avis_metier": ["vraie anomalie", "fausse alerte"]})
        precision = priorisation.precision_par_regle(self.evenements(), retours)
        self.assertEqual(precision.loc["03 Rafale", "precision"], 1.0)
        self.assertEqual(precision.loc["09 Carte expirée", "precision"], 0.0)


if __name__ == "__main__":
    unittest.main()
