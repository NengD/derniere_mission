extends SceneTree
## Tests du corps des gardes : dégâts localisés, réactions, ragdoll (stabilité, articulations), limite de corps.
## godot --headless --path . -s tests/tests_garde.gd     (code de sortie 1 si un test échoue)

var echecs := 0
var total := 0


func verifier(cond: bool, nom: String) -> void:
	total += 1
	if cond:
		print("  ok   ", nom)
	else:
		echecs += 1
		printerr("  ÉCHEC ", nom)


func _garde(variante: String, pos := Vector3.ZERO, arme := true) -> CorpsGarde:
	var g := CorpsGarde.new()
	g.variante = variante
	g.arme = arme
	g.graine = 1234
	g.position = pos
	root.add_child(g)
	return g


## Flexion (degrés) de b par rapport à a autour de l'axe `axe_local` (repère de a).
func _flexion(a: PhysicalBone3D, b: PhysicalBone3D, axe_local: Vector3) -> float:
	var ad := a.global_basis.y.normalized()
	var bd := b.global_basis.y.normalized()
	var ax := (a.global_basis * axe_local).normalized()
	return rad_to_deg(atan2(ad.cross(bd).dot(ax), ad.dot(bd)))


func _sol() -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(40, 0.2, 40)
	cs.shape = b
	cs.position.y = -0.1
	sb.add_child(cs)
	root.add_child(sb)
	return sb


func _initialize() -> void:
	print("== Zones et dégâts par os")
	verifier(CorpsGarde.zone_de("Head") == Degats.Zone.TETE and CorpsGarde.zone_de("neck_01") == Degats.Zone.TETE, "tête et cou : zone tête")
	verifier(CorpsGarde.zone_de("spine_03") == Degats.Zone.TORSE and CorpsGarde.zone_de("pelvis") == Degats.Zone.TORSE, "tronc et bassin : zone torse")
	verifier(CorpsGarde.zone_de("upperarm_l") == Degats.Zone.BRAS and CorpsGarde.zone_de("lowerarm_r") == Degats.Zone.BRAS and CorpsGarde.zone_de("hand_r") == Degats.Zone.BRAS, "bras, avant-bras, main : zone bras")
	verifier(CorpsGarde.zone_de("thigh_r") == Degats.Zone.JAMBE and CorpsGarde.zone_de("calf_l") == Degats.Zone.JAMBE and CorpsGarde.zone_de("foot_l") == Degats.Zone.JAMBE, "cuisse, mollet, pied : zone jambe")
	verifier(CorpsGarde.zone_de("tete") == Degats.Zone.TETE and CorpsGarde.zone_de(Degats.Zone.BRAS) == Degats.Zone.BRAS, "zone donnée par nom ou par numéro")
	verifier(is_equal_approx(CorpsGarde.degats_pour(55.0, "Head"), 220.0) and is_equal_approx(CorpsGarde.degats_pour(55.0, "spine_01"), 55.0), "multiplicateurs : tête ×4, torse ×1")
	verifier(is_equal_approx(CorpsGarde.degats_pour(55.0, "lowerarm_l"), 27.5) and is_equal_approx(CorpsGarde.degats_pour(55.0, "calf_r"), 33.0), "multiplicateurs : bras ×0,5, jambe ×0,6")
	var i0 := CorpsGarde.impulsion(55.0, 0.0)
	var i1 := CorpsGarde.impulsion(55.0, 1.0)
	verifier(i0 > 3.0 and i1 > i0 and i1 <= CorpsGarde.IMPULSION_MAX * 1.25, "impulsion de balle bornée et variable")
	verifier(CorpsGarde.impulsion(200.0, 0.5) > CorpsGarde.impulsion(55.0, 0.5), "impulsion proportionnelle aux dégâts")

	print("== Limite de corps")
	verifier(CorpsGarde.corps_en_trop(10, 24) == 0, "sous la limite : rien à retirer")
	verifier(CorpsGarde.corps_en_trop(26, 24) == 2, "au-delà : les plus anciens partent")
	verifier(CorpsGarde.corps_en_trop(3, 0) == 2, "limite nulle ramenée à un corps")

	print("== Construction (garde_1 mince, garde_3 en surpoids)")
	var sol := _sol()
	var g1 := _garde("garde_1", Vector3(0, 0, 0))
	var g3 := _garde("garde_3", Vector3(3, 0, 0))
	await physics_frame
	await physics_frame
	verifier(g1.ragdoll != null and g1.ragdoll.get_child_count() == RagdollGarde.SEGMENTS.size(), "ragdoll : 14 os physiques")
	var hb := g1.find_children("hb_*", "Area3D", false, false)
	verifier(hb.size() == RagdollGarde.SEGMENTS.size(), "14 hitboxes")
	var couches_ok := true
	for a in hb:
		couches_ok = couches_ok and (a as Area3D).collision_layer == 8 and (a as Area3D).has_meta("os")
	verifier(couches_ok, "hitboxes sur la couche 4 avec la méta « os »")
	verifier(g1.collision_layer == 4, "capsule de déplacement sur la couche 3")
	var masse := 0.0
	for pb in g1.ragdoll.get_children():
		masse += (pb as PhysicalBone3D).mass
	verifier(masse > 45.0 and masse < 110.0, "masse totale plausible (%.0f kg)" % masse)
	var tronc1: Vector3 = (g1.segments["spine_03"] as RagdollGarde.Segment).taille
	var tronc3: Vector3 = (g3.segments["spine_03"] as RagdollGarde.Segment).taille
	var ventre1: Vector3 = (g1.segments["spine_01"] as RagdollGarde.Segment).taille
	var ventre3: Vector3 = (g3.segments["spine_01"] as RagdollGarde.Segment).taille
	verifier(ventre3.z > ventre1.z and tronc3.x * tronc3.z > tronc1.x * tronc1.z, "corpulence : le ventre et le torse du gros sont plus épais")
	var tete: RagdollGarde.Segment = g1.segments["Head"]
	verifier(tete.taille.x > 0.08 and tete.taille.x < 0.14, "tête : rayon plausible (%.3f m)" % tete.taille.x)
	verifier(g1.pistolet != null and g1.pistolet.get_parent() is BoneAttachment3D, "pistolet tenu dans la main droite")

	print("== Tir sur les hitboxes")
	var ds := root.get_world_3d().direct_space_state
	var tete_pos := (g1.find_child("hb_Head", false, false) as Node3D).global_position
	var q := PhysicsRayQueryParameters3D.create(tete_pos + Vector3(0, 0, 5), tete_pos + Vector3(0, 0, -5), 1 | 8)
	q.collide_with_areas = true
	var r := ds.intersect_ray(q)
	verifier(not r.is_empty() and (r["collider"] as Node).get_meta("os", "") == "Head", "un rayon vers la tête touche la hitbox « Head »")
	verifier(not r.is_empty() and Joueur.trouver_receveur(r["collider"]) == g1, "le receveur du tir est le garde")

	print("== Réactions")
	var morts := [0]
	var reactions: Array = []
	g1.mort.connect(func(_g) -> void: morts[0] += 1)
	g1.touche.connect(func(_g, _z, _d, rea) -> void: reactions.append(rea))
	g1.recevoir_tir(55.0, "upperarm_l", tete_pos, Vector3.ZERO, Vector3.FORWARD, null)
	verifier(g1.vivant and g1.bras_blesse["l"] and reactions[-1] == Degats.Reaction.BRAS_TOUCHE, "bras touché : vivant, bras gauche blessé")
	g1.recevoir_tir(55.0, "thigh_r", tete_pos, Vector3.ZERO, Vector3.FORWARD, null)
	verifier(g1.vivant and g1.a_terre and reactions[-1] == Degats.Reaction.CHUTE, "jambe touchée : au sol, vivant")
	verifier(is_equal_approx(g1.pv, 100.0 - 27.5 - 33.0), "PV après bras et jambe : %.1f" % g1.pv)
	g1.recevoir_tir(20.0, "calf_l", tete_pos, Vector3.ZERO, Vector3.FORWARD, null)
	verifier(g1.vivant and reactions[-1] == Degats.Reaction.SURSAUT, "déjà au sol : la jambe ne fait plus tomber")
	var g2 := _garde("garde_2", Vector3(-3, 0, 0))
	await physics_frame
	var m2 := [0]
	g2.mort.connect(func(_g) -> void: m2[0] += 1)
	g2.recevoir_tir(55.0, "spine_03", g2.global_position + Vector3(0, 1.3, 0), Vector3.ZERO, Vector3.FORWARD, null)
	verifier(g2.vivant and m2[0] == 0, "une balle au torse : vivant")
	g2.recevoir_tir(55.0, "spine_01", g2.global_position + Vector3(0, 1.1, 0), Vector3.ZERO, Vector3.FORWARD, null)
	verifier(not g2.vivant and m2[0] == 1 and g2.ragdoll.is_simulating_physics(), "deux balles au torse : mort, ragdoll")
	g2.recevoir_tir(55.0, "spine_01", g2.global_position + Vector3(0, 1.1, 0), Vector3.ZERO, Vector3.FORWARD, null)
	verifier(m2[0] == 1, "un corps touché ne meurt pas deux fois")
	var g4 := _garde("garde_4", Vector3(6, 0, 0))
	await physics_frame
	var m4 := [0]
	g4.mort.connect(func(_g) -> void: m4[0] += 1)
	var tues_avant := 0
	if root.has_node("Jeu"):
		tues_avant = root.get_node("Jeu").score.tues
	var faux_joueur := Node.new()
	faux_joueur.add_to_group("joueur")
	root.add_child(faux_joueur)
	g4.recevoir_tir(55.0 * Degats.FACTEUR_MIN, "Head", g4.global_position + Vector3(0, 1.6, 0), Vector3.ZERO, Vector3.FORWARD, faux_joueur)
	verifier(not g4.vivant and m4[0] == 1, "une balle dans la tête, même de loin : mort")
	verifier(not root.has_node("Jeu") or root.get_node("Jeu").score.tues == tues_avant + 1, "le score compte le garde tué par le joueur")
	await physics_frame
	verifier(root.find_children("ArmeTombee*", "RigidBody3D", false, false).size() >= 2, "l'arme tombe (corps rigide)")
	var chargeurs := root.find_children("Chargeur*", "", false, false)
	verifier(chargeurs.size() >= 2 and chargeurs[0].has_method("interagir") and (chargeurs[0] as CollisionObject3D).collision_layer == 16, "un chargeur ramassable (couche 5) reste près du corps")
	verifier(chargeurs.size() > 0 and str(chargeurs[0].texte_aide()).length() > 3, "texte d'aide du chargeur")

	print("== Ragdoll : stabilité sur 5 s")
	g1.recevoir_tir(55.0, "Head", g1.global_position + Vector3(0, 1.6, 0), Vector3.ZERO, Vector3(0.3, 0, -1).normalized(), null)
	var tous := [g1, g2, g4]
	var min_y := 99.0
	var ecart_max := 0.0
	var vmax := 0.0
	for i in 300:
		await physics_frame
		for g in tous:
			var pel := (g as CorpsGarde).os_physique("pelvis").global_position
			for pb in (g as CorpsGarde).ragdoll.get_children():
				var p := (pb as PhysicalBone3D).global_position
				min_y = min(min_y, p.y)
				ecart_max = max(ecart_max, p.distance_to(pel))
				vmax = max(vmax, (pb as PhysicalBone3D).linear_velocity.length())
	verifier(min_y > -0.05, "aucun os ne traverse le sol (y min des centres %.3f)" % min_y)
	verifier(ecart_max < 1.15, "pas d'explosion : os à moins de 1,15 m du bassin (%.2f)" % ecart_max)
	verifier(vmax < 12.0, "vitesses bornées (%.1f m/s)" % vmax)
	var au_repos := true
	for g in tous:
		for pb in (g as CorpsGarde).ragdoll.get_children():
			au_repos = au_repos and (pb as PhysicalBone3D).linear_velocity.length() < 0.15
	verifier(au_repos, "les corps se posent et s'immobilisent")
	var genoux_ok := true
	var coudes_ok := true
	for g in tous:
		for c in ["l", "r"]:
			var f := _flexion((g as CorpsGarde).os_physique("thigh_" + c), (g as CorpsGarde).os_physique("calf_" + c), Vector3.RIGHT)
			genoux_ok = genoux_ok and f > -15.0 and f < 150.0
	verifier(genoux_ok, "genoux : jamais pliés vers l'avant")

	print("== Articulations : le genou ne plie que vers l'arrière")
	var gk := _garde("garde_1", Vector3(0, 0, 8), false)
	await physics_frame
	await physics_frame
	for pb in gk.ragdoll.get_children():
		(pb as PhysicalBone3D).gravity_scale = 0.0
	gk.ragdoll.physical_bones_start_simulation()
	await physics_frame
	var cuisse := gk.os_physique("thigh_l")
	var mollet := gk.os_physique("calf_l")
	var bras := gk.os_physique("upperarm_l")
	var avb := gk.os_physique("lowerarm_l")
	var n_coude := (bras.global_basis.inverse() * bras.global_basis.y.cross(avb.global_basis.y)).normalized()
	mollet.apply_impulse(Vector3(0, 0, 3.0), Vector3(0, -0.2, 0))   # pied poussé vers l'avant : hyperextension
	avb.apply_impulse(Vector3(0, 0, -2.0), Vector3(0, -0.1, 0))
	var fmin := 999.0
	var cmin := 999.0
	for i in 60:
		await physics_frame
		fmin = min(fmin, _flexion(cuisse, mollet, Vector3.RIGHT))
		cmin = min(cmin, _flexion(bras, avb, n_coude))
	verifier(fmin > -25.0, "genou poussé vers l'avant : bloqué (%.0f°)" % fmin)
	verifier(cmin > -25.0, "coude poussé à l'envers : bloqué (%.0f°)" % cmin)
	mollet.apply_impulse(Vector3(0, 0, -3.0), Vector3(0, -0.2, 0))
	var fmax := -999.0
	for i in 60:
		await physics_frame
		fmax = max(fmax, _flexion(cuisse, mollet, Vector3.RIGHT))
	verifier(fmax > 60.0, "genou poussé vers l'arrière : il plie (%.0f°)" % fmax)
	var cou := _flexion(gk.os_physique("spine_03"), gk.os_physique("Head"), Vector3.RIGHT)
	verifier(abs(cou) < 75.0, "cou limité (%.0f°)" % cou)

	print("== Limite de corps en jeu")
	var reg = root.get_node_or_null("Reglages")
	var ancienne = 24
	if reg:
		ancienne = reg.get_v("limite_corps")
		reg.valeurs["limite_corps"] = 2
	var vieux := CorpsGarde.corps_morts.duplicate()
	var g5 := _garde("garde_2", Vector3(-6, 0, 0), false)
	await physics_frame
	g5.recevoir_tir(300.0, "spine_03", g5.global_position + Vector3(0, 1.3, 0), Vector3.ZERO, Vector3.FORWARD, null)
	await process_frame
	var vivants_corps := CorpsGarde.corps_morts.filter(func(c) -> bool: return is_instance_valid(c) and not c.is_queued_for_deletion())
	verifier(reg == null or vivants_corps.size() <= 2, "limite de 2 corps : les plus anciens sont retirés (%d restants)" % vivants_corps.size())
	if reg:
		reg.valeurs["limite_corps"] = ancienne

	print("%d tests, %d échec(s)" % [total, echecs])
	for n in root.find_children("*", "", true, false):
		if n is AudioStreamPlayer3D or n is AudioStreamPlayer:
			n.stop()
	for n in root.get_children():
		if n is CorpsGarde or n is RigidBody3D or n == sol or n == faux_joueur or n is GPUParticles3D:
			n.queue_free()
	CorpsGarde.corps_morts.clear()
	FxSang.liberer()
	await process_frame
	await process_frame
	quit(1 if echecs > 0 else 0)
