extends SceneTree
## Tests de la logique pure (sans rendu). Code de sortie 1 si un test échoue.
## godot --headless --path . -s tests/tests_logique.gd

var echecs := 0
var total := 0


func verifier(cond: bool, nom: String) -> void:
	total += 1
	if cond:
		print("  ok   ", nom)
	else:
		echecs += 1
		printerr("  ÉCHEC ", nom)


func _init() -> void:
	print("== Dégâts")
	verifier(Degats.zone_depuis_os("Head") == Degats.Zone.TETE, "tête reconnue")
	verifier(Degats.zone_depuis_os("lowerarm_l") == Degats.Zone.BRAS, "avant-bras = bras")
	verifier(Degats.zone_depuis_os("calf_r") == Degats.Zone.JAMBE, "mollet = jambe")
	verifier(Degats.zone_depuis_os("spine_02") == Degats.Zone.TORSE, "colonne = torse")
	var d_pistolet := 55.0
	var pv := Degats.PV_MAX
	pv -= Degats.calculer(d_pistolet, Degats.Zone.TORSE, 8.0)
	verifier(pv > 0.0, "une balle au torse ne tue pas")
	pv -= Degats.calculer(d_pistolet, Degats.Zone.TORSE, 8.0)
	verifier(pv <= 0.0, "deux balles au torse tuent")
	verifier(Degats.calculer(d_pistolet, Degats.Zone.TETE, 10.0) >= Degats.PV_MAX, "une balle dans la tête tue")
	verifier(Degats.calculer(d_pistolet, Degats.Zone.TORSE, 80.0) < d_pistolet, "atténuation à longue distance")
	verifier(Degats.reaction(Degats.Zone.JAMBE, 60.0, false) == Degats.Reaction.CHUTE, "jambe touchée : chute")
	verifier(Degats.reaction(Degats.Zone.JAMBE, 60.0, true) == Degats.Reaction.SURSAUT, "déjà à terre : pas de deuxième chute")
	verifier(Degats.reaction(Degats.Zone.TORSE, 0.0, false) == Degats.Reaction.MORT, "plus de vie : mort")
	# le garde (35 par balle au torse) tue le joueur en 3 balles
	var pj := Degats.PV_MAX
	for i in 2:
		pj -= Degats.calculer(35.0, Degats.Zone.TORSE, 10.0)
	verifier(pj > 0.0, "joueur : deux balles ne tuent pas")
	pj -= Degats.calculer(35.0, Degats.Zone.TORSE, 10.0)
	verifier(pj <= 0.0, "joueur : trois balles tuent")

	print("== Munitions")
	var a := EtatArme.new(15, 2, 42)
	a.proba_enrayage = 0.0
	verifier(a.total() == 46, "15 + 1 dans la chambre + 2 chargeurs")
	for i in 5:
		a.tirer()
	verifier(a.cartouches_dans_arme() == 11, "5 tirs : 11 restantes")
	verifier(a.recharger() == a.duree_recharge_tactique, "rechargement tactique (plus rapide)")
	verifier(a.tirer() == EtatArme.Tir.OCCUPEE, "pas de tir pendant le rechargement")
	a.avancer(5.0)
	verifier(a.chargeur == 15 and a.chambre, "chargeur plein engagé, cartouche gardée dans la chambre")
	verifier(a.poches.has(10), "le chargeur entamé (10) est conservé à part")
	var b := EtatArme.new(15, 1, 1)
	b.proba_enrayage = 0.0
	for i in 16:
		b.tirer()
	verifier(b.cartouches_dans_arme() == 0 and b.tirer() == EtatArme.Tir.VIDE, "arme vide : clic")
	verifier(b.recharger() == b.duree_recharge_vide, "rechargement à vide plus lent")
	b.avancer(5.0)
	verifier(b.chambre and b.chargeur == 14, "culasse relâchée : une cartouche chambrée")
	verifier(b.poches.is_empty(), "le chargeur vide n'est pas gardé")
	var c := EtatArme.new(15, 1, 7)
	c.proba_enrayage = 1.0
	c.tirer()
	verifier(c.enrayee and c.tirer() == EtatArme.Tir.ENRAYEE, "enrayage bloque le tir")
	c.recharger()
	c.avancer(5.0)
	verifier(not c.enrayee and c.chambre, "désenrayage avec R")
	var e := EtatArme.new(15, 0, 3)
	e.ramasser_chargeur(9)
	verifier(e.poches == [9], "munitions ramassées sur un ennemi")
	var s := EtatArme.new(15, 2, 3)
	s.tirer()
	var s2 := EtatArme.new(15, 0, 3)
	s2.depuis_dict(s.vers_dict())
	verifier(s2.total() == s.total(), "sauvegarde des munitions")

	print("== Fins")
	var cfg := Fins.charger_config()
	verifier(cfg.get("heureuse_seuil_otages", 0.0) == 1.0, "fichier data/fins.json lu (seuil 100 %)")
	var tout := {"otages_liberes": 10, "otages_total": 10, "documents_trouves": 17, "documents_total": 17, "document_cache": false}
	verifier(Fins.choisir(tout, cfg) == "heureuse", "tout trouvé : fin heureuse")
	var presque := tout.duplicate()
	presque["documents_trouves"] = 16
	verifier(Fins.choisir(presque, cfg) == "tragique", "un document manquant : fin tragique (seuil strict)")
	var fonce := {"otages_liberes": 0, "otages_total": 10, "documents_trouves": 1, "documents_total": 17, "document_cache": false}
	verifier(Fins.choisir(fonce, cfg) == "tragique", "joueur qui fonce : fin tragique")
	var cache := fonce.duplicate()
	cache["document_cache"] = true
	verifier(Fins.choisir(cache, cfg) == "rebondissement", "document caché : rebondissement prioritaire")
	var souple := cfg.duplicate()
	souple["heureuse_seuil_documents"] = 0.8
	verifier(Fins.choisir(presque, souple) == "heureuse", "seuil réglable")

	print("== Score")
	var sc := Score.new()
	sc.tirs = 10
	sc.touches = 7
	sc.tues = 8
	sc.temps = 300.0
	sc.otages_liberes.append("manutentionnaire")
	verifier(is_equal_approx(sc.precision(), 0.7), "précision 70 %")
	verifier(sc.points() > 0 and sc.note() != "", "points et note")
	var sc2 := Score.new()
	sc2.depuis_dict(sc.vers_dict())
	verifier(sc2.points() == sc.points(), "score sauvegardé à l'identique")

	print("== Sauvegarde")
	var chemin := "user://test_sauvegarde.json"
	var donnees := Sauvegarde.vide()
	donnees["niveaux_debloques"] = [1, 2]
	donnees["partie"] = {"niveau": 1, "point": {"id": "douane"}}
	verifier(Sauvegarde.ecrire(chemin, donnees), "écriture")
	var relu := Sauvegarde.lire(chemin)
	verifier(relu["niveaux_debloques"] == [1, 2] and relu["partie"]["point"]["id"] == "douane", "relecture identique")
	var ancienne := {"niveaux_debloques": [1]}
	var migree := Sauvegarde.migrer(ancienne)
	verifier(migree.has("campagne") and migree["campagne"].has("document_cache"), "migration d'une sauvegarde incomplète")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(chemin))
	verifier(Sauvegarde.lire("user://inexistant.json")["niveaux_debloques"] == [1], "sans fichier : partie neuve")

	print("== Arbre de comportement")
	var bb := {"menace": false, "pv": 100.0, "journal": []}
	var arbre := BT.sel("racine", [
		BT.seq("fuir", [BT.si("blesse", func(b): return b["pv"] < 30.0), BT.fais("reculer", func(b, _d): b["journal"].append("reculer"); return BT.Etat.EN_COURS)]),
		BT.seq("combat", [BT.si("menace", func(b): return b["menace"]), BT.fais("tirer", func(b, _d): b["journal"].append("tirer"); return BT.Etat.EN_COURS)]),
		BT.fais("patrouiller", func(b, _d): b["journal"].append("patrouiller"); return BT.Etat.EN_COURS),
	])
	arbre.tick(bb, 0.1)
	verifier(bb["journal"].back() == "patrouiller", "calme : patrouille")
	bb["menace"] = true
	arbre.tick(bb, 0.1)
	verifier(bb["journal"].back() == "tirer", "menace : combat")
	bb["pv"] = 20.0
	arbre.tick(bb, 0.1)
	verifier(bb["journal"].back() == "reculer", "gravement blessé : recule (priorité)")

	print("\n%d tests, %d échec(s)" % [total, echecs])
	quit(1 if echecs > 0 else 0)
