"""Graphiques : chaque fonction reçoit des tableaux déjà calculés et ne fait que dessiner."""
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from pyspark.sql import functions as F

from .indicateurs import ORDRE_JOURS
from .outils import CLE_TERMINAL, en_pandas

COULEURS_ANOMALIES = {"01": "black", "02": "dimgray", "03": "tab:red", "04": "tab:pink", "05": "tab:orange",
                      "06": "tab:purple", "07": "tab:green", "08": "navy", "09": "tab:brown", "10": "tab:blue",
                      "11": "tab:olive", "12": "tab:cyan", "13": "gold", "14": "crimson", "15": "teal",
                      "16": "sienna", "17": "magenta", "18": "darkgoldenrod", "19": "darkred", "20": "indigo",
                      "21": "darkviolet", "22": "chocolate", "23": "deepskyblue", "24": "darkslategray",
                      "25": "olivedrab", "26": "slateblue"}
ASPECT_FRANCE = 1 / np.cos(np.radians(46.5))


# ------------------------------------------------------------------ briques
def couleur_anomalie(nom):
    """Couleur fixe d'une anomalie à partir de son numéro (« 03 Rafale » -> rouge)."""
    return COULEURS_ANOMALIES.get(str(nom)[:2], "grey")


def afficher_matrice(ax, matrice, titre, cmap="viridis", annoter=False, etiquettes_x=None, **options):
    """Carte de chaleur d'un DataFrame pandas, avec ses étiquettes (et ses valeurs si `annoter`)."""
    image = ax.imshow(np.ma.masked_invalid(matrice.values.astype(float)), aspect="auto", cmap=cmap,
                      interpolation="nearest", **options)
    ax.set_yticks(range(matrice.shape[0]))
    ax.set_yticklabels([str(i)[:32] for i in matrice.index])
    ax.set_xticks(range(matrice.shape[1]))
    ax.set_xticklabels(etiquettes_x if etiquettes_x is not None else matrice.columns)
    if annoter:
        for i in range(matrice.shape[0]):
            for j in range(matrice.shape[1]):
                ax.text(j, i, "{:.0f}".format(matrice.values[i, j]), ha="center", va="center", fontsize=8)
    ax.set_title(titre)
    plt.colorbar(image, ax=ax)
    return image


def tracer_matrice(matrice, titre, cmap="viridis", taille=(14, 4), xlabel=None, **options):
    """Figure contenant une seule carte de chaleur."""
    fig, ax = plt.subplots(figsize=taille)
    afficher_matrice(ax, matrice, titre, cmap=cmap, **options)
    if xlabel:
        ax.set_xlabel(xlabel)
    plt.show()


def carte_france(ax, points, valeurs=None, titre="", fond=None, cmap="viridis", taille=6):
    """Nuage de terminaux sur leurs coordonnées (sans fond de carte), avec un fond gris optionnel."""
    if fond is not None:
        ax.scatter(fond["longitude"], fond["latitude"], s=1, color="#d5d9e0")
    if valeurs is None:
        ax.scatter(points["longitude"], points["latitude"], s=taille)
    else:
        ordre = valeurs.sort_values().index
        nuage = ax.scatter(points.loc[ordre, "longitude"], points.loc[ordre, "latitude"], c=valeurs[ordre],
                           s=taille, cmap=cmap, alpha=0.85)
        plt.colorbar(nuage, ax=ax, shrink=0.7)
    ax.set_aspect(ASPECT_FRANCE)
    ax.set_title(titre, fontsize=10)


def nuage_par_categorie(ax, table, x, y, categorie, titre, echelle_x_log=True, nb_categories=8):
    """Nuage de points coloré par catégorie (les plus fréquentes ; les autres en gris), avec légende."""
    categories = table[categorie].fillna("inconnu")
    palette = plt.get_cmap("tab10")
    legende = {c: palette(i) for i, c in enumerate(categories.value_counts().head(nb_categories).index)}
    ax.scatter(table[x], table[y], s=10, alpha=0.6, c=[legende.get(c, (0.7, 0.7, 0.7, 1.0)) for c in categories])
    for nom, couleur in legende.items():
        ax.scatter([], [], color=couleur, label=str(nom)[:20])
    if echelle_x_log:
        ax.set_xscale("log")
    ax.set_xlabel(x)
    ax.set_title(titre)
    ax.legend(fontsize=7, loc="upper right")


def grille_axes(nb, colonnes=4, hauteur=3.4, largeur=18):
    """Grille de sous-graphiques pour `nb` panneaux ; les panneaux en trop sont masqués."""
    lignes = int(np.ceil(nb / colonnes))
    fig, axes = plt.subplots(lignes, colonnes, figsize=(largeur, hauteur * lignes), squeeze=False)
    for ax in axes.ravel()[nb:]:
        ax.axis("off")
    return fig, axes.ravel()[:nb]


# ------------------------------------------------------------------ volumes et rythmes
def tracer_volumes(jour):
    """Retraits par jour (avec moyennes glissantes) et nombre de terminaux actifs."""
    fig, axes = plt.subplots(2, 1, figsize=(14, 8), sharex=True)
    axes[0].plot(jour.index, jour["retraits"], lw=0.6, alpha=0.5, label="par jour")
    for fenetre in (7, 28):
        axes[0].plot(jour.index, jour["retraits"].rolling(fenetre, center=True).mean(), lw=1.6,
                     label="moyenne {} jours".format(fenetre))
    axes[0].set_title("Retraits par jour, parc complet")
    axes[0].legend()
    axes[1].plot(jour.index, jour["terminal_actifs"], lw=0.8, color="tab:green")
    axes[1].set_title("terminal ayant au moins une opération dans la journée")
    plt.tight_layout()
    plt.show()


def tracer_calendrier(serie, titre, cmap="YlGnBu"):
    """Calendrier (jours de semaine x semaines) d'une série journalière indexée par date."""
    semaine = ((serie.index - serie.index[0]).days + serie.index[0].dayofweek) // 7
    calendrier = np.full((7, semaine.max() + 1), np.nan)
    calendrier[serie.index.dayofweek, semaine] = serie.values
    debuts = [i for i, d in enumerate(serie.index) if d.day == 1]
    fig, ax = plt.subplots(figsize=(16, 3.5))
    image = ax.imshow(calendrier, aspect="auto", cmap=cmap, interpolation="nearest")
    ax.set_yticks(range(7))
    ax.set_yticklabels(ORDRE_JOURS)
    ax.set_xticks([semaine[i] for i in debuts])
    ax.set_xticklabels([serie.index[i].strftime("%b") for i in debuts])
    ax.set_title(titre)
    plt.colorbar(image, ax=ax)
    plt.show()


def tracer_profils(profil_horaire, profil_hebdo):
    """Profils normalisés de tous les terminaux (une ligne par terminal) et leurs distributions."""
    fig, axes = plt.subplots(1, 2, figsize=(16, 10), gridspec_kw={"width_ratios": [3, 1.3]})
    afficher_matrice(axes[0], profil_horaire, "Profil horaire de chaque terminal (part de ses retraits par heure)",
                     cmap="magma", vmax=np.percentile(profil_horaire.values, 99))
    axes[0].set_yticks([])
    axes[0].set_ylabel("{} terminal, triés par heure de pointe".format(len(profil_horaire)))
    afficher_matrice(axes[1], profil_hebdo, "Profil hebdomadaire (trié par part du week-end)")
    axes[1].set_yticks([])
    plt.tight_layout()
    plt.show()
    fig, axes = plt.subplots(1, 3, figsize=(17, 4))
    axes[0].bar(range(24), np.bincount(profil_horaire.values.argmax(axis=1), minlength=24))
    axes[0].set_title("Heure de pointe des terminaux")
    axes[1].hist((profil_horaire[[0, 1, 2, 3, 4, 5, 22, 23]].sum(axis=1) * 100).clip(upper=40), bins=60)
    axes[1].set_yscale("log")
    axes[1].set_title("% des retraits entre 22 h et 6 h, par terminal")
    axes[2].hist((profil_hebdo["sam"] + profil_hebdo["dim"]) * 100, bins=60)
    axes[2].axvline(200 / 7, color="grey", lw=1)
    axes[2].set_title("% des retraits le week-end, par terminal (trait : répartition uniforme)")
    plt.tight_layout()
    plt.show()


def tracer_carte_parc(ecarts):
    """Carte terminal x jour des écarts à l'habitude (log2) : bleu = en dessous, rouge = au-dessus."""
    fig, ax = plt.subplots(figsize=(16, 10))
    image = ax.imshow(np.ma.masked_invalid(ecarts.values), aspect="auto", cmap="RdBu_r", vmin=-3, vmax=3,
                      interpolation="nearest")
    debuts = [i for i, d in enumerate(ecarts.columns) if d.day == 1]
    ax.set_xticks(debuts)
    ax.set_xticklabels([ecarts.columns[i].strftime("%b") for i in debuts])
    ax.set_ylabel("{} terminal, du plus actif (haut) au moins actif (bas)".format(len(ecarts)))
    ax.set_title("Retraits du jour / habitude du terminal pour ce jour de semaine (log2)")
    plt.colorbar(image, ax=ax, label="log2(retraits / habitude)")
    plt.show()


# ------------------------------------------------------------------ parc, géographie, relations
def tracer_parc(par_terminal):
    """Volume par terminal, concentration de l'activité, taux de présence."""
    fig, axes = plt.subplots(1, 3, figsize=(16, 4))
    axes[0].hist(np.log10(par_terminal["retraits_par_jour_actif"].clip(lower=0.1)), bins=60)
    axes[0].set_title("Retraits par jour actif (log10)")
    tries = np.sort(par_terminal["retraits"].values)[::-1]
    axes[1].plot(np.arange(1, len(tries) + 1) / len(tries) * 100, np.cumsum(tries) / tries.sum() * 100)
    axes[1].set_title("% des retraits réalisés par les x % de terminaux les plus actifs")
    axes[1].set_xlabel("% des terminaux")
    axes[2].hist(par_terminal["taux_presence"], bins=50)
    axes[2].set_title("Taux de présence (jours actifs / durée de vie)")
    plt.tight_layout()
    plt.show()


def tracer_cartes_geographiques(en_metropole):
    """Quatre cartes de France : volume, cartes étrangères rares, inaboutis, captures."""
    vues = [("retraits_par_jour_actif", "Retraits par jour actif (log10)", "viridis", True),
            ("part_etrangers_pct", "% de cartes étrangères rares", "magma_r", False),
            ("taux_inaboutis_pct", "% de retraits inaboutis", "Reds", False),
            ("captures_pour_1000", "Captures pour 1 000 retraits", "Purples", False)]
    fig, axes = plt.subplots(2, 2, figsize=(16, 15))
    for ax, (colonne, titre, cmap, echelle_log) in zip(axes.ravel(), vues):
        valeurs = en_metropole[colonne].clip(upper=en_metropole[colonne].quantile(0.99))
        valeurs = np.log10(valeurs.clip(lower=0.1)) if echelle_log else valeurs
        carte_france(ax, en_metropole, valeurs, titre, cmap=cmap)
    plt.tight_layout()
    plt.show()


def tracer_volume_par_site(par_terminal, nb_sites=12):
    """Retraits par jour actif selon le type de site d'implantation (boîtes à moustaches)."""
    sites = par_terminal["libelle_site"].value_counts().head(nb_sites).index
    fig, ax = plt.subplots(figsize=(14, 5))
    ax.boxplot([par_terminal.loc[par_terminal["libelle_site"] == s, "retraits_par_jour_actif"].dropna() for s in sites],
               showfliers=False)
    ax.set_xticklabels([str(s)[:22] for s in sites], rotation=30, ha="right")
    ax.set_yscale("log")
    ax.set_title("Retraits par jour actif selon le type de site d'implantation")
    plt.show()


def tracer_relations(terminal_actifs, categorie):
    """Nuages : volume du terminal face à ses taux (inaboutis, captures, étrangers, montant, nuit)."""
    vues = [("taux_inaboutis_pct", "Taux d'inaboutis (%) selon le volume"),
            ("captures_pour_1000", "Captures pour 1 000 retraits selon le volume"),
            ("part_etrangers_pct", "% de cartes étrangères rares selon le volume"),
            ("montant_moyen", "Montant moyen selon le volume"),
            ("part_nuit_pct", "% de retraits de nuit selon le volume")]
    fig, axes = grille_axes(len(vues), colonnes=3, hauteur=5.2, largeur=19)
    for ax, (colonne, titre) in zip(axes, vues):
        nuage_par_categorie(ax, terminal_actifs, "retraits_par_jour_actif", colonne, categorie, titre)
    plt.tight_layout()
    plt.show()


# ------------------------------------------------------------------ montants, inaboutis, captures
def tracer_montants(tranches, quantiles_heure, montant_jour_heure):
    """Distribution des montants, montant selon l'heure (médiane et dispersion), montant jour x heure."""
    fig, axes = plt.subplots(1, 3, figsize=(20, 4.5))
    axes[0].bar(tranches["tranche"], tranches["count"], width=9)
    axes[0].set_yscale("log")
    axes[0].set_title("Montants retirés (tranches de 10 €, log)")
    axes[1].fill_between(quantiles_heure.index, quantiles_heure["p10"], quantiles_heure["p90"], alpha=0.15,
                         label="10 % - 90 %")
    axes[1].fill_between(quantiles_heure.index, quantiles_heure["p25"], quantiles_heure["p75"], alpha=0.3,
                         label="25 % - 75 %")
    axes[1].plot(quantiles_heure.index, quantiles_heure["p50"], marker="o", label="médiane")
    axes[1].set_title("Montant retiré selon l'heure")
    axes[1].legend()
    afficher_matrice(axes[2], montant_jour_heure, "Montant moyen (€) : jour x heure", cmap="cividis")
    plt.tight_layout()
    plt.show()


def tracer_taux(taux_heure, taux_reseau, titre):
    """Taux (en %) selon l'heure et selon le réseau."""
    fig, axes = plt.subplots(1, 2, figsize=(15, 4))
    axes[0].plot(taux_heure.iloc[:, 0], taux_heure["taux"], marker="o")
    axes[0].set_title("{} selon l'heure (%)".format(titre))
    axes[1].barh(taux_reseau.iloc[:, 0].astype(str), taux_reseau["taux"])
    axes[1].set_title("{} selon le réseau (%)".format(titre))
    plt.tight_layout()
    plt.show()


def tracer_histogramme(valeurs, titre, bins=60, log=True):
    """Histogramme simple."""
    plt.hist(valeurs, bins=bins)
    if log:
        plt.yscale("log")
    plt.title(titre)
    plt.show()


def tracer_reseaux(parts_mois, profils_heure):
    """Part mensuelle des réseaux (hors réseau principal) et profil horaire de chaque réseau."""
    fig, axes = plt.subplots(1, 2, figsize=(17, 4.5))
    parts_mois.drop(columns=[parts_mois.sum().idxmax()]).plot(
        ax=axes[0], title="Part mensuelle des réseaux (hors principal), %")
    profils_heure.plot(ax=axes[1], title="Profil horaire de chaque réseau (part de ses retraits)")
    plt.tight_layout()
    plt.show()


# ------------------------------------------------------------------ dynamique dans la journée
def tracer_silences_et_delais(debut_duree, delais_log):
    """Silences improbables (durée x heure de début) et délais entre retraits (échelle log)."""
    fig, axes = plt.subplots(1, 2, figsize=(17, 5))
    if len(debut_duree):
        afficher_matrice(axes[0], debut_duree, "Silences improbables : durée (h) x heure de début", cmap="Greys")
        axes[0].set_xlabel("heure de début")
    axes[1].bar(delais_log["log10_delai"], delais_log["count"], width=0.09)
    axes[1].set_xticks([0, 1, np.log10(60), np.log10(600), np.log10(3600), np.log10(86400)])
    axes[1].set_xticklabels(["1 s", "10 s", "1 min", "10 min", "1 h", "1 j"])
    axes[1].set_yscale("log")
    axes[1].set_title("Délai entre deux retraits successifs (échelle log)")
    plt.tight_layout()
    plt.show()


def tracer_ecart_parc_heure(ecarts):
    """Parc jour x heure : log2(retraits / habitude) ; une case bleue isolée = incident commun."""
    fig, ax = plt.subplots(figsize=(10, 14))
    image = ax.imshow(ecarts.values, aspect="auto", cmap="RdBu_r", vmin=-2, vmax=2, interpolation="nearest")
    reperes = [i for i, d in enumerate(ecarts.index) if d.day == 1]
    ax.set_yticks(reperes)
    ax.set_yticklabels([ecarts.index[i].strftime("%m/%y") for i in reperes], fontsize=7)
    ax.set_xticks(range(24))
    ax.set_xlabel("heure")
    ax.set_title("Parc complet : retraits par heure / habitude (log2, bleu = déficit)")
    plt.colorbar(image, label="log2(retraits / habitude)")
    plt.show()


def regarder_journee(ops, num_automate, date_txt):
    """Retraits d'un terminal par quart d'heure ce jour-là, comparés à la médiane des 8 mêmes jours précédents."""
    jour_cible = pd.Timestamp(date_txt)
    dates = [(jour_cible - pd.Timedelta(weeks=k)).strftime("%Y-%m-%d") for k in range(0, 9)]
    detail = en_pandas(
        ops.filter((F.col(CLE_TERMINAL) == num_automate) & F.col("date").cast("string").isin(dates))
        .groupBy("date", "type_op", ((F.col("heure") * 60 + F.col("minute")) / 15).cast("int").alias("quart"))
        .agg(F.count("*").alias("n")))
    if detail.empty:
        print("Aucune opération trouvée.")
        return
    detail["date"] = pd.to_datetime(detail["date"])
    retraits = (detail[detail["type_op"] != "CAPTURE"].groupby(["date", "quart"])["n"].sum()
                .unstack(fill_value=0).reindex(columns=range(96), fill_value=0))
    du_jour = retraits.loc[jour_cible] if jour_cible in retraits.index else pd.Series(0, index=range(96))
    reference = retraits.drop(index=jour_cible, errors="ignore").median()
    heures = np.arange(96) / 4
    plt.figure(figsize=(14, 4))
    plt.step(heures, reference.values, where="post", color="grey", label="médiane des 8 mêmes jours précédents")
    plt.step(heures, du_jour.values, where="post", color="tab:red", label=str(date_txt))
    captures = detail[(detail["type_op"] == "CAPTURE") & (detail["date"] == jour_cible)]
    if len(captures):
        plt.scatter(captures["quart"] / 4, [0] * len(captures), marker="x", s=80, color="black", label="captures")
    plt.title("terminal {} : retraits par quart d'heure".format(num_automate))
    plt.xlabel("heure")
    plt.legend()
    plt.show()
    print("Ce jour : {} retraits ; référence : {:.0f}".format(int(du_jour.sum()), reference.sum()))


def carte_heures_terminal(ops, num_automate, debut=None, fin=None):
    """Retraits d'un terminal par heure, un jour par ligne ; croix = inaboutis, ronds = captures."""
    selection = ops.filter(F.col(CLE_TERMINAL) == num_automate)
    if debut:
        selection = selection.filter(F.col("date") >= F.lit(debut).cast("date"))
    if fin:
        selection = selection.filter(F.col("date") <= F.lit(fin).cast("date"))
    detail = en_pandas(selection.groupBy("date", "heure").agg(F.sum("est_retrait").alias("retraits"),
                                                              F.sum("inabouti").alias("inaboutis"),
                                                              F.sum("est_capture").alias("captures")))
    if detail.empty:
        print("Aucune opération.")
        return
    detail["date"] = pd.to_datetime(detail["date"])
    jours = pd.date_range(detail["date"].min(), detail["date"].max())
    grille = (detail.pivot(index="date", columns="heure", values="retraits")
              .reindex(index=jours, columns=range(24)).fillna(0))
    fig, ax = plt.subplots(figsize=(11, max(4, len(jours) * 0.04)))
    image = ax.imshow(np.log1p(grille.values), aspect="auto", cmap="magma", interpolation="nearest")
    for colonne, marque, couleur in [("inaboutis", "x", "cyan"), ("captures", "o", "lime")]:
        lignes = detail[detail[colonne] > 0]
        ax.scatter(lignes["heure"], [jours.get_loc(d) for d in lignes["date"]], marker=marque, s=12,
                   color=couleur, label=colonne)
    reperes = [i for i, d in enumerate(jours) if d.day == 1 or i == 0]
    ax.set_yticks(reperes)
    ax.set_yticklabels([jours[i].strftime("%d/%m/%y") for i in reperes], fontsize=7)
    ax.set_xticks(range(24))
    ax.set_xlabel("heure")
    ax.set_title("terminal {} : retraits par heure (log), un jour par ligne".format(num_automate))
    ax.legend(loc="upper right", fontsize=8)
    plt.colorbar(image, label="log(1 + retraits)")
    plt.show()


# ------------------------------------------------------------------ catalogue des anomalies
def tracer_frequences(recap):
    """Journées terminal concernées, % de terminaux touchés, % de terminaux qui récidivent, par anomalie."""
    fig, axes = plt.subplots(1, 3, figsize=(18, 0.45 * len(recap) + 2), sharey=True)
    for ax, (colonne, titre, couleur) in zip(axes, [
            ("journees_terminal", "Journées terminal concernées", "tab:blue"),
            ("pct_terminal_touches", "% des terminaux touchés au moins une fois", "tab:orange"),
            ("pct_terminal_recurrents", "% des terminaux touchés qui récidivent (>= 4 semaines)", "tab:red")]):
        ax.barh(np.arange(len(recap)), recap[colonne], color=[couleur_anomalie(t) for t in recap.index])
        ax.set_title(titre)
    axes[0].set_yticks(np.arange(len(recap)))
    axes[0].set_yticklabels(recap.index)
    axes[0].invert_yaxis()
    plt.tight_layout()
    plt.show()


def tracer_recurrence(par_type_terminal):
    """Répartition des terminaux touchés selon le nombre de semaines où l'anomalie revient."""
    classes = pd.cut(par_type_terminal["semaines"], [0, 1, 3, 9, 1000], labels=["1 semaine", "2-3", "4-9", "10 et plus"])
    (pd.crosstab(par_type_terminal["type"], classes, normalize="index") * 100).plot(
        kind="barh", stacked=True, figsize=(14, 0.4 * par_type_terminal["type"].nunique() + 2), colormap="RdYlGn_r",
        title="Récurrence : terminal touchés selon le nombre de semaines avec l'anomalie (%)")
    plt.gca().invert_yaxis()
    plt.legend(loc="lower right")
    plt.show()


def tracer_intensites(valeurs_types):
    """Distribution de la valeur qui a déclenché chaque anomalie."""
    types = sorted(valeurs_types["type"].unique())
    fig, axes = grille_axes(len(types))
    for ax, nom in zip(axes, types):
        valeurs = valeurs_types.loc[valeurs_types["type"] == nom, "valeur"].abs()
        ax.hist(valeurs.clip(upper=valeurs.quantile(0.99)), bins=30, color=couleur_anomalie(nom))
        ax.set_title("{} (n = {})".format(nom, len(valeurs)), fontsize=9)
    plt.tight_layout()
    plt.show()


def tracer_evolution(par_jour_type):
    """Nombre d'événements sur 7 jours glissants, par anomalie."""
    fig, ax = plt.subplots(figsize=(16, 5))
    for nom, groupe in par_jour_type.groupby("type"):
        serie = groupe.set_index("date")["count"].sort_index()
        ax.plot(serie.index, serie.rolling(7, min_periods=1).sum(), label=nom, color=couleur_anomalie(nom))
    ax.set_title("Événements sur 7 jours glissants, par anomalie")
    ax.legend(fontsize=8, ncol=3)
    plt.show()


def tracer_cartes_anomalies(occurrences, positions):
    """Une petite carte de France par anomalie : terminal touchés, couleur selon le nombre d'occurrences."""
    fig, axes = grille_axes(occurrences.shape[1], hauteur=4.6)
    for ax, nom in zip(axes, occurrences.columns):
        compte = occurrences[nom].reindex(positions.index).fillna(0)
        touches = compte[compte > 0]
        carte_france(ax, positions.loc[touches.index], np.log1p(touches), "{} ({} terminal)".format(nom, len(touches)),
                     fond=positions, cmap="autumn_r", taille=10)
        ax.set_xticks([])
        ax.set_yticks([])
    plt.tight_layout()
    plt.show()


def tracer_galerie(journees, evenements, terminal_choisis, synthese):
    """Retraits par jour des terminaux choisis ; chaque anomalie est marquée à sa date avec sa couleur."""
    fig, axes = grille_axes(len(terminal_choisis), colonnes=3, hauteur=3.5, largeur=19)
    for ax, terminal in zip(axes, terminal_choisis):
        serie = journees[journees[CLE_TERMINAL] == terminal].set_index("date")["retraits"].sort_index()
        ax.plot(serie.index, serie.values, lw=0.7, color="grey")
        for nom, groupe in evenements[evenements[CLE_TERMINAL] == terminal].groupby("type"):
            ax.scatter(groupe["date"], serie.reindex(groupe["date"]).fillna(0), s=30, label=nom[:2],
                       color=couleur_anomalie(nom), zorder=3)
        ax.set_title("terminal {} ({:.0f} anomalies)".format(terminal, synthese.loc[terminal, "evenements"]), fontsize=9)
        ax.legend(fontsize=7, ncol=5)
    plt.tight_layout()
    plt.show()


def tracer_chronologie(evenements, terminal_choisis):
    """Un point par anomalie : terminal (lignes) x date ; un alignement vertical = épisode commun."""
    position = {terminal: i for i, terminal in enumerate(terminal_choisis)}
    fig, ax = plt.subplots(figsize=(16, 0.27 * len(terminal_choisis) + 2))
    for nom, groupe in evenements[evenements[CLE_TERMINAL].isin(terminal_choisis)].groupby("type"):
        ax.scatter(groupe["date"], groupe[CLE_TERMINAL].map(position), s=22, label=nom, color=couleur_anomalie(nom))
    ax.set_yticks(range(len(terminal_choisis)))
    ax.set_yticklabels(terminal_choisis, fontsize=7)
    ax.invert_yaxis()
    ax.set_title("Chronologie des anomalies des terminaux les plus touchés")
    ax.legend(fontsize=8, loc="center left", bbox_to_anchor=(1.0, 0.5))
    plt.tight_layout()
    plt.show()


def tracer_explications(scores, part=0.001):
    """Indicateurs le plus souvent en cause dans les journées les plus atypiques (règle 17)."""
    plus_atypiques = scores.nlargest(max(1, int(len(scores) * part)), "score")
    colonnes = [c for c in scores.columns if c.startswith("z_")]
    poids = plus_atypiques[colonnes].abs().mean().sort_values()
    fig, axes = plt.subplots(1, 2, figsize=(17, 4.5))
    axes[0].hist(scores["score"], bins=80)
    axes[0].axvline(plus_atypiques["score"].min(), color="red", lw=1)
    axes[0].set_yscale("log")
    axes[0].set_title("Score d'atypicité des journées terminal (trait : seuil retenu)")
    axes[1].barh([c[2:] for c in poids.index], poids.values, color="tab:purple")
    axes[1].set_title("Écart moyen (en écarts habituels) dans les journées retenues")
    plt.tight_layout()
    plt.show()


def tracer_charge_quotidienne(charge, budget):
    """Nombre de terminaux alertés chaque jour, par niveau, avec la capacité de traitement du métier."""
    table = charge.groupby(["jour", "niveau"]).size().unstack(fill_value=0)
    table = table.reindex(columns=[n for n in ("Critique", "Élevé", "Modéré") if n in table.columns])
    couleurs = {"Critique": "tab:red", "Élevé": "tab:orange", "Modéré": "gold"}
    ax = table.plot(kind="bar", stacked=True, figsize=(16, 4.5), color=[couleurs[c] for c in table.columns],
                    width=0.85)
    ax.axhline(budget, color="black", lw=1.2, ls="--", label="capacité quotidienne du métier")
    ax.set_xticks(range(0, len(table), 7))
    ax.set_xticklabels([pd.Timestamp(j).strftime("%d/%m") for j in table.index[::7]], rotation=0)
    ax.set_title("terminal alertés par jour et par niveau (60 derniers jours)")
    ax.legend()
    plt.show()
