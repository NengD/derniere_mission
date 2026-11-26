extends Node3D
## Salle de test du joueur : couloir sombre, caisses, trois mannequins, un chargeur et une trousse.
##
## Sans argument : jeu réel (clic = capturer la souris, Échap = la libérer).
## Arguments (après « -- ») :
##   photo <fichier.png> [jeu|visee|tir|lampe|pieds|penche|recharge|blesse|plan|mains]
##   video   (avec --write-movie x.avi --fixed-fps 30) : scénario scripté puis quitte
##   video court : les 10,5 premières secondes seulement
##   perf [0|1|2]  même scénario en temps réel, vsync coupée : i/s moyenne et 1 % bas dans logs/perf.txt
##   video_bras (avec --write-movie) : 9,6 s de bras et d'arme (marche, 4 tirs, culasse ouverte, rechargement à vide)
## En photo et vidéo, aucune entrée réelle n'est lue et la souris n'est jamais capturée.

const PH := "res://assets/decor/"
const W := 3.2
const H := 3.0
const Z0 := 2.0
const Z1 := -17.0
const DUREE_VIDEO := 16.5

var mode := "jeu"
var vue := "jeu"
var sortie := ""
var joueur: Joueur
var cibles: Array[Node3D] = []
var t := 0.0
var _faits := {}
var _cam_ext: Camera3D
var rendu: RenduNiveau
var _perf: MesurePerf


func _ready() -> void:
	process_physics_priority = -10   # le scénario remplit les entrées avant le joueur
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		mode = a[0]
	if a.size() > 1:
		sortie = a[1]
	if a.size() > 2:
		vue = a[2]
	if mode == "perf":
		# mesure en temps réel : même parcours que la vidéo, qualité imposée sans l'enregistrer
		if sortie != "" and has_node("/root/Reglages"):
			get_node("/root/Reglages").valeurs["qualite"] = int(sortie)
		_perf = MesurePerf.new()
		_perf.etiquette = "salle_test parcours video"
		add_child(_perf)
	_environnement()
	_couloir()
	_objets()
	_lumieres()
	rendu.cuire_gi(self)
	_cibles()
	joueur = (load("res://scenes/joueur/joueur.tscn") as PackedScene).instantiate()
	joueur.pilote_auto = mode != "jeu"
	add_child(joueur)
	joueur.global_position = Vector3(-0.3, 0.05, 0.8)
	joueur.bus_reverb = "Rev_Couloir"
	joueur.mort.connect(func() -> void: print("JOUEUR MORT"))
	# pas de saccades d'image en photo (la capture attend une image dessinée)
	joueur.effet.saccades = mode != "photo" and mode != "perf"
	if mode == "jeu":
		joueur.effet.sous_titre(tr("TEST_AIDE"), 6.0)
	if mode == "photo" and (vue == "plan" or vue == "mains"):
		_cam_ext = Camera3D.new()
		_cam_ext.fov = 50 if vue == "plan" else 35
		_cam_ext.near = 0.02
		add_child(_cam_ext)
		_cam_ext.make_current()
		joueur.effet.post.set_shader_parameter("intensity", 0.0)


# ---------------------------------------------------------------- décor

func _mat(tex: String, echelle := 0.5, teinte := Color.WHITE) -> ORMMaterial3D:
	var m := ORMMaterial3D.new()
	var base := PH + "tex/%s/%s_" % [tex, tex]
	m.albedo_texture = load(base + "diff_2k.jpg")
	m.albedo_color = teinte
	m.orm_texture = load(base + "arm_2k.jpg")
	m.normal_enabled = true
	m.normal_texture = load(base + "nor_gl_2k.jpg")
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * echelle
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _boite(taille: Vector3, pos: Vector3, m: Material, materiau := "beton") -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	sb.set_meta("materiau", materiau)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = taille
	mi.mesh = bm
	mi.material_override = m
	sb.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = taille
	cs.shape = sh
	sb.add_child(cs)
	sb.position = pos
	add_child(sb)
	return sb


func _environnement() -> void:
	# environnement, exposition automatique, poussière et qualité : réutilisables (scripts/rendu/)
	rendu = RenduNiveau.new()
	rendu.name = "Rendu"
	rendu.zone = AABB(Vector3(-W / 2, 0, Z1), Vector3(W, H, Z0 - Z1))
	add_child(rendu)


func _couloir() -> void:
	var sol := _mat("hangar_concrete_floor", 0.35)
	var mur := _mat("concrete_wall_008", 0.4, Color(0.8, 0.8, 0.78))
	var soubassement := _mat("painted_concrete", 0.5, Color(0.42, 0.5, 0.46))
	var plafond := _mat("concrete_panels", 0.4, Color(0.6, 0.6, 0.6))
	var lg := Z0 - Z1
	var cz := (Z0 + Z1) / 2.0
	_boite(Vector3(W + 0.4, 0.2, lg), Vector3(0, -0.1, cz), sol)
	_boite(Vector3(W + 0.4, 0.2, lg), Vector3(0, H + 0.1, cz), plafond)
	_boite(Vector3(0.2, H, lg), Vector3(-W / 2 - 0.1, H / 2, cz), mur)
	_boite(Vector3(0.2, H, lg), Vector3(W / 2 + 0.1, H / 2, cz), mur)
	_boite(Vector3(0.03, 1.15, lg), Vector3(-W / 2 + 0.015, 0.575, cz), soubassement)
	_boite(Vector3(0.03, 1.15, lg), Vector3(W / 2 - 0.015, 0.575, cz), soubassement)
	_boite(Vector3(W, H, 0.2), Vector3(0, H / 2, Z1 - 0.1), mur)
	_boite(Vector3(W, H, 0.2), Vector3(0, H / 2, Z0 + 0.1), mur)
	# poteau métallique et plaque d'acier (impacts métalliques)
	var acier := _mat("rusty_painted_metal", 1.0, Color(0.45, 0.45, 0.45))
	_boite(Vector3(0.25, H, 0.25), Vector3(-W / 2 + 0.125, H / 2, -8.0), acier, "metal")
	_boite(Vector3(1.2, 1.0, 0.04), Vector3(0.4, 0.5, -16.9), acier, "metal")


func _modele(nom: String, pos: Vector3, rot_y := 0.0, enfant := "", collision := true, materiau := "bois") -> Node3D:
	var n: Node3D = (load(PH + "models/%s/%s.gltf" % [nom, nom]) as PackedScene).instantiate()
	add_child(n)
	if enfant != "":
		for c in n.get_children():
			if c is Node3D:
				if c.name == enfant:
					(c as Node3D).position = Vector3.ZERO
				else:
					c.free()
	n.position = pos
	n.rotation_degrees.y = rot_y
	if collision:
		var boite := AABB()
		var premier := true
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			var b: AABB = n.global_transform.affine_inverse() * (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
			boite = b if premier else boite.merge(b)
			premier = false
		var sb := StaticBody3D.new()
		sb.set_meta("materiau", materiau)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = boite.size
		cs.shape = sh
		cs.position = boite.get_center()
		sb.add_child(cs)
		n.add_child(sb)
	return n


func _objets() -> void:
	_modele("wooden_military_crate", Vector3(W / 2 - 0.5, 0, -5.4), 85)
	_modele("wooden_military_crate", Vector3(W / 2 - 0.5, 0, -6.3), 95)
	_modele("plastic_crate_01", Vector3(W / 2 - 0.45, 0.62, -5.8), 30, "", true, "plastique")
	_modele("cardboard_box_01", Vector3(-W / 2 + 0.4, 0, -3.0), 12, "", true, "carton")
	_modele("cardboard_box_01", Vector3(-W / 2 + 0.45, 0.42, -2.95), -20, "", true, "carton")
	_modele("metal_trash_can", Vector3(-W / 2 + 0.35, 0, -10.6), 0, "", true, "metal")
	_modele("korean_fire_extinguisher_01", Vector3(W / 2 - 0.15, 0, -1.5), -90, "", false)
	_modele("hand_truck", Vector3(W / 2 - 0.4, 0, -12.0), 70, "", true, "metal")
	var porte := _modele("rollershutter_door", Vector3(0, 0, Z1 + 0.05), 0, "rollershutter_door_graffiti", false)
	porte.scale = Vector3((W - 0.1) / 1.08, H / 2.4, 1.0)
	var tag := Decal.new()
	tag.texture_albedo = load("res://assets/fx/tag_cercle.png")
	tag.size = Vector3(1.3, 0.3, 1.3)
	tag.position = Vector3(-W / 2 + 0.05, 1.75, -7.0)
	tag.rotation_degrees = Vector3(0, 0, -90)
	tag.cull_mask = 1
	add_child(tag)
	# objets ramassables (couche 5)
	_ramassable("chargeur", Vector3(W / 2 - 0.5, 1.2, -6.0))
	_ramassable("trousse", Vector3(-W / 2 + 0.4, 0.84, -2.95))


func _ramassable(type: String, pos: Vector3) -> void:
	var o := StaticBody3D.new()
	o.set_script(load("res://scripts/test/objet_test.gd"))
	o.set("type", type)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var m := StandardMaterial3D.new()
	if type == "trousse":
		bm.size = Vector3(0.22, 0.08, 0.15)
		m.albedo_color = Color(0.5, 0.08, 0.06)
	else:
		bm.size = Vector3(0.03, 0.12, 0.035)
		m.albedo_color = Color(0.04, 0.04, 0.045)
	mi.mesh = bm
	mi.material_override = m
	o.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = bm.size + Vector3.ONE * 0.06
	cs.shape = sh
	o.add_child(cs)
	o.position = pos + Vector3(0, bm.size.y / 2.0, 0)
	add_child(o)


func _lumieres() -> void:
	# néons au plafond : un normal près du départ, un qui grésille, un mort qui tente de s'amorcer ;
	# entre eux, des zones presque noires (poteau, caisses)
	_lampe("neon", Vector3(0, H - 0.02, 0.0), "aucune")
	_lampe("neon", Vector3(0, H - 0.02, -4.0), "gresille")
	_lampe("neon", Vector3(0, H - 0.02, -16.0), "morte")
	# ampoule nue pendue au-dessus du deuxième mannequin
	_lampe("ampoule", Vector3(-0.3, H, -12.0))
	# lampes de sécurité : rouge sur le mur gauche, verte au-dessus du rideau métallique
	var r := _lampe("securite_rouge", Vector3(-W / 2 + 0.02, 2.3, -9.6))
	r.rotation_degrees.y = -90
	var v := _lampe("securite_verte", Vector3(W / 2 - 0.6, H - 0.35, Z1 + 0.02))
	v.rotation_degrees.y = 180
	# sodium de la rue qui filtre sous le rideau métallique
	var ext := SpotLight3D.new()
	ext.position = Vector3(0, 0.25, Z1 + 0.25)
	ext.rotation_degrees = Vector3(-6, 0, 0)
	ext.spot_angle = 65
	ext.spot_range = 10
	ext.light_energy = 2.5
	ext.light_color = Color(1.0, 0.55, 0.18)
	ext.light_volumetric_fog_energy = 3.0
	ext.shadow_enabled = true
	add_child(ext)


func _lampe(type: String, pos: Vector3, panne := "aucune") -> Lampe:
	var l := Lampe.new()
	l.type = type
	l.panne = panne
	l.position = pos
	l.graine = int(pos.z * 100.0) + 7
	add_child(l)
	return l


func _cibles() -> void:
	var pos := [Vector3(0.55, 0, -9.5), Vector3(-0.8, 0, -12.8), Vector3(0.7, 0, -15.6)]
	for i in pos.size():
		var c := CibleTest.new()
		c.name = "Cible%d" % (i + 1)
		c.position = pos[i]
		c.rotation_degrees.y = [-8.0, 12.0, 0.0][i]
		add_child(c)
		cibles.append(c)


# ---------------------------------------------------------------- jeu réel : souris

func _unhandled_input(ev: InputEvent) -> void:
	if mode != "jeu":
		return
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		joueur.capturer_souris(true)
	elif ev.is_action_pressed("pause"):
		joueur.capturer_souris(false)


# ---------------------------------------------------------------- scénarios

func _physics_process(delta: float) -> void:
	t += delta
	if mode == "video" or mode == "perf":
		_video()
		if t >= (10.5 if sortie == "court" else DUREE_VIDEO) and _une_fois("fin"):
			if _perf:
				_perf.ecrire()
			_quitter()
	elif mode == "photo":
		_photo()
	elif mode == "video_bras":
		_video_bras()
		if t >= 9.6 and _une_fois("fin"):
			_quitter()


func _une_fois(cle: String) -> bool:
	if _faits.has(cle):
		return false
	_faits[cle] = true
	return true


func _entre(a: float, b: float) -> bool:
	return t >= a and t < b


## Oriente le regard vers un point, à vitesse limitée (degrés par pas physique).
func _viser_vers(p: Vector3, vitesse := 3.0) -> void:
	var d := p - joueur.camera.global_position
	var lacet_v := atan2(-d.x, -d.z)
	var tangage_v := atan2(d.y, Vector2(d.x, d.z).length())
	var dx := rad_to_deg(wrapf(joueur.lacet - lacet_v, -PI, PI))
	var dy := rad_to_deg(joueur.tangage - tangage_v)
	joueur.tourner(clamp(dx, -vitesse, vitesse), clamp(dy, -vitesse, vitesse))


func _regarder(lacet_deg: float, tangage_deg: float, vitesse := 2.0) -> void:
	var dx := rad_to_deg(wrapf(joueur.lacet - deg_to_rad(lacet_deg), -PI, PI))
	var dy := rad_to_deg(joueur.tangage) - tangage_deg
	joueur.tourner(clamp(dx, -vitesse, vitesse), clamp(dy, -vitesse, vitesse))


func _torse(i: int) -> Vector3:
	return cibles[i].global_position + Vector3(0, 1.2, 0)


func _video() -> void:
	var j := joueur
	j.auto_axes = Vector2.ZERO
	j.auto_tenu.clear()
	# marche prudente, petit regard à gauche puis devant
	if _entre(0.4, 2.7):
		j.auto_axes = Vector2(0, 1)
		_regarder(8.0 if t < 1.6 else -3.0, -4.0, 0.6)
	# se penche à droite derrière les caisses, vise le premier mannequin, trois tirs
	if _entre(2.7, 4.9):
		j.auto_tenu["pencher_droite"] = true
		if t > 3.0:
			j.auto_tenu["viser"] = true
			_viser_vers(_torse(0), 1.5)
		for s in [3.55, 3.95, 4.35]:
			if t >= s and _une_fois("tir%s" % s):
				j.auto_appui["tirer"] = true
	# rechargement tactique en se redressant
	if t >= 5.1 and _une_fois("r1"):
		j.auto_appui["recharger"] = true
	if _entre(5.1, 6.9):
		_regarder(-2.0, -12.0, 0.5)
	# coup d'œil aux pieds (corps visible)
	if _entre(6.9, 7.8):
		_regarder(-2.0, -62.0, 3.0)
	if _entre(7.8, 8.4):
		_regarder(-2.0, -5.0, 3.0)
	# avance accroupi
	if _entre(8.4, 10.0):
		j.auto_tenu["accroupi"] = true
		j.auto_axes = Vector2(0.15, 1)
	# debout, vise le deuxième mannequin : deux balles puis clic à vide
	if t >= 10.0 and _une_fois("vide"):
		j.arme.chambre = true
		j.arme.chargeur = 1
	if _entre(10.2, 12.0):
		j.auto_tenu["viser"] = true
		_viser_vers(_torse(1), 1.5)
		for s in [10.8, 11.25, 11.7]:
			if t >= s and _une_fois("tir%s" % s):
				j.auto_appui["tirer"] = true
	# rechargement à vide (culasse)
	if t >= 12.0 and _une_fois("r2"):
		j.auto_appui["recharger"] = true
	if _entre(12.0, 14.4):
		_regarder(rad_to_deg(j.lacet), -10.0, 0.5)
	# une balle reçue de face, puis une deuxième
	if t >= 14.5 and _une_fois("b1"):
		j.recevoir_tir(35.0, "", j.global_position + Vector3(0, 1.3, 0), Vector3.ZERO, j.global_basis * Vector3(0.2, 0, 1), null)
	if t >= 15.3 and _une_fois("b2"):
		j.recevoir_tir(35.0, "", j.global_position + Vector3(0, 1.2, 0), Vector3.ZERO, j.global_basis * Vector3(-0.3, 0, 1), null)


## Vidéo courte des bras et de l'arme (9,6 s) : marche, visée, quatre tirs jusqu'à la culasse ouverte,
## rechargement à vide, reprise de la visée en avançant.
func _video_bras() -> void:
	var j := joueur
	j.auto_axes = Vector2.ZERO
	j.auto_tenu.clear()
	if t < 0.05:
		j.global_position = Vector3(-0.2, 0.05, 0.6)
	if _entre(0.3, 2.6):
		j.auto_axes = Vector2(0, 1)
		_regarder(6.0 if t < 1.5 else -4.0, -5.0, 0.5)
	if t >= 2.4 and _une_fois("munitions"):
		j.arme.chambre = true
		j.arme.chargeur = 3
	if _entre(2.6, 5.0):
		j.auto_tenu["viser"] = true
		_viser_vers(_torse(0), 1.6)
		for s in [3.3, 3.75, 4.2, 4.65]:
			if t >= s and _une_fois("tir%s" % s):
				j.auto_appui["tirer"] = true
	if t >= 5.1 and _une_fois("recharge"):
		j.auto_appui["recharger"] = true
	if _entre(5.1, 7.6):
		_regarder(rad_to_deg(j.lacet), -9.0, 0.4)
	if _entre(7.6, 9.6):
		j.auto_tenu["viser"] = true
		j.auto_axes = Vector2(0, 0.5)
		_viser_vers(_torse(1), 1.2)


var _gizmos: Array = []


## Repères de contrôle (X rouge, Y vert, Z bleu) : cibles des mains et os réels.
func _gizmo() -> Node3D:
	var n := Node3D.new()
	for i in 3:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var d := Vector3.ONE * 0.003
		d[i] = 0.06
		bm.size = d
		mi.mesh = bm
		mi.position[i] = 0.03
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = [Color.RED, Color.GREEN, Color.BLUE][i]
		m.no_depth_test = true
		mi.material_override = m
		n.add_child(mi)
	add_child(n)
	return n


func _maj_gizmos() -> void:
	if _gizmos.is_empty():
		for i in 4:
			_gizmos.append(_gizmo())
	var sk: Skeleton3D = joueur.bras.get_skeleton()
	_gizmos[0].global_transform = joueur.bras.cible_d
	_gizmos[1].global_transform = joueur.bras.cible_g
	_gizmos[2].global_transform = (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("hand_r"))).orthonormalized()
	_gizmos[3].global_transform = (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("hand_l"))).orthonormalized()
	_gizmos[2].scale = Vector3.ONE * 0.6
	_gizmos[3].scale = Vector3.ONE * 0.6


func _photo() -> void:
	var j := joueur
	if OS.has_environment("DEBUG_MAINS") and joueur.bras != null:
		_maj_gizmos()
	j.auto_tenu.clear()
	j.auto_axes = Vector2.ZERO
	if t < 0.05:
		j.global_position = Vector3(-0.2, 0.05, -4.0)
	var fin := 1.6
	match vue:
		"visee":
			j.auto_tenu["viser"] = true
			_viser_vers(_torse(0), 4.0)
		"tir":
			j.auto_tenu["viser"] = true
			_viser_vers(_torse(0), 4.0)
			if t >= 1.4 and _une_fois("tir"):
				j.auto_appui["tirer"] = true
			fin = 1.4
		"pieds":
			_regarder(10.0, -65.0, 6.0)
		"lampe":
			# sous le néon qui grésille, regard vers l'ampoule nue et la lampe rouge (surexposition)
			if t < 0.05:
				j.global_position = Vector3(0.4, 0.05, -7.0)
			_viser_vers(Vector3(-0.6, H - 0.7, -12.0), 4.0)
		"penche":
			j.auto_tenu["pencher_droite"] = true
			_viser_vers(_torse(0), 4.0)
		"recharge":
			_regarder(0.0, -10.0, 4.0)
			if t >= 0.5 and _une_fois("r"):
				j.arme.chambre = false
				j.arme.chargeur = 0
				j.auto_appui["recharger"] = true
			fin = 0.5 + 2.4 * (float(OS.get_environment("RECH_U")) if OS.has_environment("RECH_U") else 0.45)
		"blesse":
			_viser_vers(_torse(0), 4.0)
			if t >= 0.6 and _une_fois("b1"):
				j.recevoir_tir(35.0, "", j.global_position + Vector3(0, 1.3, 0), Vector3.ZERO, j.global_basis * Vector3(0, 0, 1), null)
			if t >= 0.9 and _une_fois("b2"):
				j.recevoir_tir(35.0, "", j.global_position + Vector3(0, 1.2, 0), Vector3.ZERO, j.global_basis * Vector3(0, 0, 1), null)
		"plan", "mains":
			j.auto_tenu["viser"] = sortie.contains("visee")
			_viser_vers(_torse(0), 4.0)
			var c := j.camera.global_transform
			if vue == "plan":
				_cam_ext.global_position = j.global_position + j.global_basis * Vector3(1.25, 1.55, -1.3)
				_cam_ext.look_at(j.global_position + Vector3(0, 1.25, 0) - j.global_basis.z * 0.25)
			elif sortie.contains("droite"):
				_cam_ext.global_position = c * Vector3(0.45, -0.1, -0.4)
				_cam_ext.look_at(j.pistolet.global_position)
			else:
				_cam_ext.global_position = c * Vector3(-0.3, -0.05, -0.75)
				_cam_ext.look_at(j.pistolet.global_position)
		_:
			_viser_vers(_torse(0) + Vector3(0.3, 0.2, 0), 4.0)
	if t >= fin and _une_fois("capture"):
		_capturer()


func _capturer() -> void:
	if OS.has_environment("DEBUG_MAINS"):
		var sk: Skeleton3D = joueur.corps.find_children("*", "Skeleton3D", true, false)[0]
		for c in ["r", "l"]:
			var u := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("upperarm_" + c))
			var h := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("hand_" + c))
			var cible: Transform3D = joueur.bras.cible_d if c == "r" else joueur.bras.cible_g
			print("MAIN ", c, " epaule->cible ", u.origin.distance_to(cible.origin), " main->cible ", h.origin.distance_to(cible.origin), " epaule(cam) ", joueur.camera.global_transform.affine_inverse() * u.origin)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(sortie)
	print("CAPTURE ", sortie)
	_quitter()


## Coupe les sons en cours avant de quitter (sinon Godot signale des flux encore en lecture).
func _quitter() -> void:
	set_physics_process(false)
	joueur.set_process(false)
	joueur.set_physics_process(false)
	for n in get_tree().root.find_children("*", "", true, false):
		if n is AudioStreamPlayer or n is AudioStreamPlayer3D:
			n.stop()
			n.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit()
