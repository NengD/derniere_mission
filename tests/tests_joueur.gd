extends SceneTree
## Tests du joueur (logique isolable, sans rendu). Code de sortie 1 si un test échoue.
## godot --headless --path . -s tests/tests_joueur.gd

var echecs := 0
var total := 0


func verifier(cond: bool, nom: String) -> void:
	total += 1
	if cond:
		print("  ok   ", nom)
	else:
		echecs += 1
		printerr("  ÉCHEC ", nom)


func _initialize() -> void:
	print("== Santé")
	var s := SanteJoueur.new()
	verifier(s.pv == 100.0 and s.trousses == 1, "départ : 100 PV, une trousse")
	verifier(not s.commencer_soin(), "pas de soin à pleine santé")
	s.recevoir(35.0)
	s.recevoir(35.0)
	verifier(not s.est_mort() and is_equal_approx(s.pv, 30.0), "deux balles de garde : 30 PV")
	verifier(s.commencer_soin() and s.trousses == 0, "soin commencé, trousse consommée")
	verifier(not s.commencer_soin(), "pas de deuxième soin simultané")
	for i in 20:
		s.avancer(0.1)
	verifier(s.pv > 30.0 and s.pv < 90.0 and s.en_soin(), "soin lent : en cours après 2 s")
	for i in 30:
		s.avancer(0.1)
	verifier(is_equal_approx(s.pv, 90.0) and not s.en_soin(), "soin terminé : +60 PV")
	s.recevoir(10.0)
	verifier(s.commencer_soin() == false, "plus de trousse")
	verifier(s.ramasser_trousse() and s.trousses == 1, "ramasser une trousse")
	verifier(s.commencer_soin(), "nouveau soin")
	s.recevoir(5.0)
	verifier(not s.en_soin(), "touché pendant le soin : soin interrompu")
	s.ramasser_trousse(); s.ramasser_trousse(); s.ramasser_trousse()
	verifier(s.trousses == SanteJoueur.TROUSSES_MAX and not s.ramasser_trousse(), "trousses plafonnées")
	# régénération
	var r := SanteJoueur.new()
	r.recevoir(80.0)
	for i in 100:
		r.avancer(0.1)
	verifier(is_equal_approx(r.pv, 20.0), "régénération coupée par défaut")
	r.regeneration = 2.0
	r.recevoir(1.0)
	for i in 70:
		r.avancer(0.1)
	verifier(is_equal_approx(r.pv, 19.0), "pas de régénération avant le délai")
	for i in 400:
		r.avancer(0.1)
	verifier(is_equal_approx(r.pv, SanteJoueur.REGEN_PLAFOND), "régénération plafonnée")
	r.recevoir(500.0)
	verifier(r.est_mort() and r.pv == 0.0, "mort à 0 PV")
	r.avancer(10.0)
	verifier(r.pv == 0.0, "pas de régénération une fois mort")
	var d := SanteJoueur.new()
	d.depuis_dict({"pv": 42.0, "trousses": 2})
	verifier(d.vers_dict() == {"pv": 42.0, "trousses": 2}, "santé : aller-retour dictionnaire")

	print("== Dispersion")
	var premiere := Dispersion.angle(0.0, 1.0, false, false, 0.0, 5.0)
	var suivante := Dispersion.angle(0.0, 1.0, false, false, 1.0, 0.2)
	verifier(premiere < 0.1, "première balle en visée quasi parfaite")
	verifier(suivante > premiere * 3.0, "tirs rapprochés : dispersion plus grande")
	verifier(Dispersion.angle(0.0, 0.0, false, false, 0.0, 5.0) > premiere, "hanche moins précise que la visée")
	verifier(Dispersion.angle(2.6, 0.0, false, false, 0.0, 5.0) > Dispersion.angle(0.0, 0.0, false, false, 0.0, 5.0), "en marchant : moins précis")
	verifier(Dispersion.angle(0.0, 0.0, false, true, 0.0, 5.0) > 4.0, "en l'air : très imprécis")
	verifier(Dispersion.angle(2.6, 0.0, true, false, 2.0, 0.1) < Dispersion.angle(2.6, 0.0, false, false, 2.0, 0.1), "accroupi : plus précis")
	verifier(Dispersion.angle(0.0, 0.0, false, false, 50.0, 0.1) <= Dispersion.angle(0.0, 0.0, false, false, Dispersion.CHALEUR_MAX, 0.1) + 0.001, "chaleur plafonnée")
	var dmax := 0.0
	for i in 200:
		var v := Dispersion.direction(Basis.IDENTITY, 2.0, randf(), randf())
		dmax = max(dmax, rad_to_deg(v.angle_to(Vector3.FORWARD)))
	verifier(dmax <= 2.0001 and dmax > 0.5, "directions dans le cône")
	verifier(Dispersion.direction(Basis.IDENTITY, 0.0, 0.7, 0.3).is_equal_approx(Vector3.FORWARD), "angle nul : tout droit")

	# la partie « scène » attend que l'arbre tourne (root dans l'arbre)
	process_frame.connect(_tests_scene, CONNECT_ONE_SHOT)


func _tests_scene() -> void:
	print("== Joueur (scène)")
	# sons coupés : sans pilote audio réel, Godot garderait les lectures en cours à la sortie
	if root.has_node("Audio"):
		root.get_node("Audio").name = "AudioCoupe"
	var j: Joueur = (load("res://scenes/joueur/joueur.tscn") as PackedScene).instantiate()
	j.pilote_auto = true
	j.creer_effet = false
	root.add_child(j)
	verifier(j.collision_layer == 2 and j.collision_mask == 5, "couches physiques : joueur 2, heurte monde + ennemis")
	verifier(j.has_method("recevoir_tir") and j.has_method("recevoir_degats"), "interface de dégâts présente")
	j.global_position = Vector3(1, 2, 3)
	j.tourner(30.0, -10.0)
	j.sante.recevoir(45.0)
	j.sante.trousses = 2
	j.arme.tirer()
	j.arme.tirer()
	var dico := j.vers_dict()
	var copie = JSON.parse_string(JSON.stringify(dico))   # comme une sauvegarde sur disque
	var j2: Joueur = (load("res://scenes/joueur/joueur.tscn") as PackedScene).instantiate()
	j2.pilote_auto = true
	j2.creer_effet = false
	root.add_child(j2)
	j2.depuis_dict(copie)
	verifier(j2.global_position.is_equal_approx(Vector3(1, 2, 3)), "point de contrôle : position")
	verifier(is_equal_approx(j2.lacet, j.lacet) and is_equal_approx(j2.tangage, j.tangage), "point de contrôle : regard")
	verifier(is_equal_approx(j2.sante.pv, 55.0) and j2.sante.trousses == 2, "point de contrôle : PV et trousses")
	verifier(j2.arme.cartouches_dans_arme() == j.arme.cartouches_dans_arme() and j2.arme.total() == j.arme.total(), "point de contrôle : munitions")
	var avant := j2.arme.total()
	j2.ramasser_chargeur(9)
	verifier(j2.arme.total() == avant + 9, "ramasser un chargeur entamé")
	var morts := [0]
	j2.mort.connect(func() -> void: morts[0] += 1)
	j2.recevoir_tir(35.0, "Head", Vector3.ZERO, Vector3.ZERO, Vector3.FORWARD, null)
	verifier(j2.est_mort and morts[0] == 1, "balle dans la tête (35 × 4) : signal mort")
	j2.recevoir_degats(10.0)
	verifier(morts[0] == 1, "pas de deuxième mort")
	verifier(Joueur.trouver_receveur(j2.forme) == j2, "receveur trouvé en remontant les parents")

	print("== Arme à la première personne")
	var j3: Joueur = (load("res://scenes/joueur/joueur.tscn") as PackedScene).instantiate()
	j3.pilote_auto = true
	j3.creer_effet = false
	root.add_child(j3)
	verifier(j3.glissiere != null and j3.chargeur_arme != null, "pistolet : glissière et chargeur séparés")
	var repos := j3.glissiere.position
	j3.arme.chambre = true
	j3.arme.chargeur = 0
	j3._appuyer_detente()
	for i in 6:
		j3._maj_glissiere(0.02)
	verifier(j3.glissiere_bloquee and j3.glissiere.position.z > repos.z + 0.03, "dernière balle : glissière bloquée en arrière")
	j3.arme.chambre = true
	j3.arme.chargeur = 5
	j3._liberer_glissiere()
	for i in 6:
		j3._maj_glissiere(0.02)
	verifier(not j3.glissiere_bloquee and j3.glissiere.position.is_equal_approx(repos), "glissière relâchée : revient en avant")
	j3._appuyer_detente()
	j3._maj_glissiere(0.012)
	var milieu := j3.glissiere.position.z
	for i in 6:
		j3._maj_glissiere(0.02)
	verifier(milieu > repos.z + 0.01 and j3.glissiere.position.is_equal_approx(repos) and not j3.glissiere_bloquee, "tir : la glissière recule puis revient")
	var t0 := j3._chargeur_dans_arme(0.0)
	var t1 := j3._chargeur_dans_arme(0.05)
	verifier((t1.origin - t0.origin).length() > 0.049 and (t1.origin - t0.origin).y < -0.04, "le chargeur sort vers le bas, le long de la poignée")
	j3.arme.chambre = false
	j3.arme.chargeur = 0
	j3._recharger()
	j3._rech_t = j3._rech_duree * 0.3
	verifier(not j3._chargeur_engage_visible(), "rechargement à vide : pas de chargeur dans la poignée à mi-course")
	j3._rech_t = j3._rech_duree * 0.9
	verifier(j3._chargeur_engage_visible(), "rechargement à vide : nouveau chargeur engagé à la fin")
	j3._rech_t = -1.0

	print("%d tests, %d échec(s)" % [total, echecs])
	# sons coupés et deux images d'attente : sortie sans flux audio encore en lecture
	for n in root.find_children("*", "", true, false):
		if n is AudioStreamPlayer:
			n.stop()
	j.free()
	j2.free()
	j3.free()
	await process_frame
	await process_frame
	quit(1 if echecs > 0 else 0)
