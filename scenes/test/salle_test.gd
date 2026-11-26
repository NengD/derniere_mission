extends Node3D
## Salle de test du joueur : couloir sombre, caisses, trois mannequins, un chargeur et une trousse.
##
## Sans argument : jeu réel (clic = capturer la souris, Échap = la libérer).
## Arguments (après « -- ») :
##   photo <fichier.png> [jeu|visee|tir|lampe|pieds|penche|recharge|blesse|plan|mains]
##   video   (avec --write-movie x.avi --fixed-fps 30) : scénario scripté puis quitte
##   video court : les 10,5 premières secondes seulement
##   perf [0|1|2]  même scénario en temps réel, vsync coupée : i/s moyenne et 1 % bas dans logs/perf.txt
##   video_decor (avec --write-movie) : 9,5 s de marche lente pour montrer le décor (flaque, plafond, porte)
##   video_bras (avec --write-movie) : 9,6 s de bras et d'arme (marche, 4 tirs, culasse ouverte, rechargement à vide)
##   video_ragdoll [ext] (avec --write-movie) : 10,8 s, quatre gardes tués de quatre façons (tête, torse en
##     marche, jambe puis achèvement au sol, bras puis torse) : ragdolls tous différents
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
		if OS.has_environment("TRACE_IMAGES"):
			add_child(preload("res://scripts/test/trace_images.gd").new())
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
	FxSang.prechauffer(self, joueur.global_position + Vector3(0, 1.4, -0.6))
	if mode == "video_ragdoll":
		if _cam_ext:
			joueur.effet.post.set_shader_parameter("intensity", 0.0)
			_cam_ext.make_current.call_deferred()
		for g in gardes:
			g.touche.connect(func(gg: CorpsGarde, zone: int, deg: float, rea: int) -> void:
				print("TOUCHE %s zone %d dégâts %.0f réaction %d à %.2f s" % [gg.name, zone, deg, rea, t]))
	if mode == "photo" and (vue == "plan" or vue == "mains" or (vue == "recharge" and sortie.contains("plan"))):
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


## Porte de service entrouverte dans le mur gauche (centre en z) et réduit sombre derrière.
const PORTE_Z := -4.6
const REDUIT := 1.9


func _couloir() -> void:
	# matériaux du kit de décor (scripts/decor/) : deux échelles, plaques d'un second matériau,
	# teinte et décalage propres à chaque mur, saleté au pied, suie sous le plafond
	var sol := KitDecor.materiau("hangar_concrete_floor", 0.35, Color.WHITE,
		{"tex2": "concrete_floor_worn_001", "echelle2": 0.3, "part_second": 0.45, "variation": 0.25})
	var mur := KitDecor.materiau("concrete_wall_008", 0.4, Color(0.8, 0.8, 0.78),
		{"suie": 0.6, "plafond_y": H, "variation": 0.18})
	var soubassement := KitDecor.materiau("painted_concrete", 0.5, Color(0.42, 0.5, 0.46),
		{"tex2": "peeling_painted_wall", "echelle2": 0.5, "part_second": 0.3, "salete": 0.45, "humidite": 0.7, "variation": 0.2})
	var plafond := KitDecor.materiau("concrete_panels", 0.4, Color(0.6, 0.6, 0.6), {"variation": 0.3, "suie": 0.0})
	var lg := Z0 - Z1
	var cz := (Z0 + Z1) / 2.0
	_boite(Vector3(W + 0.4, 0.2, lg), Vector3(0, -0.1, cz), sol)
	_boite(Vector3(W + 0.4, 0.2, lg), Vector3(0, H + 0.1, cz), plafond)
	# mur gauche coupé par la porte (deux pans + linteau), mur droit d'un seul tenant
	var pz0 := PORTE_Z - 0.5
	var pz1 := PORTE_Z + 0.5
	var mg := KitDecor.varier(mur, 11)
	_boite(Vector3(0.2, H, Z0 - pz1), Vector3(-W / 2 - 0.1, H / 2, (Z0 + pz1) / 2), mg)
	_boite(Vector3(0.2, H, pz0 - Z1), Vector3(-W / 2 - 0.1, H / 2, (pz0 + Z1) / 2), mg)
	_boite(Vector3(0.2, H - 2.09, 1.0), Vector3(-W / 2 - 0.1, (H + 2.09) / 2, PORTE_Z), mg)
	_boite(Vector3(0.2, H, lg), Vector3(W / 2 + 0.1, H / 2, cz), KitDecor.varier(mur, 12))
	var sg := KitDecor.varier(soubassement, 13)
	_boite(Vector3(0.03, 1.15, Z0 - pz1), Vector3(-W / 2 + 0.015, 0.575, (Z0 + pz1) / 2), sg)
	_boite(Vector3(0.03, 1.15, pz0 - Z1), Vector3(-W / 2 + 0.015, 0.575, (pz0 + Z1) / 2), sg)
	_boite(Vector3(0.03, 1.15, lg), Vector3(W / 2 - 0.015, 0.575, cz), KitDecor.varier(soubassement, 14))
	_boite(Vector3(W, H, 0.2), Vector3(0, H / 2, Z1 - 0.1), KitDecor.varier(mur, 15))
	_boite(Vector3(W, H, 0.2), Vector3(0, H / 2, Z0 + 0.1), KitDecor.varier(mur, 16))
	# réduit derrière la porte : noir, juste assez profond pour qu'on devine des étagères
	var xr := -W / 2 - 0.2
	var rz := PORTE_Z
	var mr := KitDecor.varier(mur, 17)
	_boite(Vector3(REDUIT, 0.2, 2.4), Vector3(xr - REDUIT / 2, -0.1, rz), KitDecor.varier(sol, 18))
	_boite(Vector3(REDUIT, 0.2, 2.4), Vector3(xr - REDUIT / 2, 2.7, rz), plafond)
	_boite(Vector3(0.2, 2.6, 2.4), Vector3(xr - REDUIT - 0.1, 1.3, rz), mr)
	_boite(Vector3(REDUIT, 2.6, 0.2), Vector3(xr - REDUIT / 2, 1.3, rz - 1.3), mr)
	_boite(Vector3(REDUIT, 2.6, 0.2), Vector3(xr - REDUIT / 2, 1.3, rz + 1.3), mr)
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
	_decor()
	# objets ramassables (couche 5)
	_ramassable("chargeur", Vector3(W / 2 - 0.5, 1.2, -6.0))
	_ramassable("trousse", Vector3(-W / 2 + 0.4, 0.84, -2.95))


## Habillage du couloir par le kit de décor (scripts/decor/kit_decor.gd) : plafond technique (gaine,
## chemin de câbles, canalisations qui fuient), saleté, humidité, flaques, déchets, affiches et tags,
## deux portes abîmées (une entrouverte sur le réduit, une fermée). Zones laissées libres : objets,
## gardes, cibles, départ du joueur, lampes.
var decor: KitDecor


func _decor() -> void:
	decor = KitDecor.new()
	decor.graine = 7
	var libre := func(x: float, z: float, r := 0.45) -> AABB:
		return AABB(Vector3(x - r, -0.1, z - r), Vector3(2 * r, 3.2, 2 * r))
	decor.evite = [
		AABB(Vector3(W / 2 - 0.9, -0.1, -6.8), Vector3(0.9, 2, 1.9)),       # caisses
		AABB(Vector3(-W / 2, -0.1, -3.5), Vector3(0.7, 2, 1.0)),            # cartons
		AABB(Vector3(-W / 2, -0.1, -11.0), Vector3(0.7, 2, 0.8)),           # poubelle
		AABB(Vector3(W / 2 - 0.9, -0.1, -12.6), Vector3(0.9, 2, 1.2)),      # diable
		AABB(Vector3(W / 2 - 0.4, -0.1, -1.9), Vector3(0.4, 2, 0.8)),       # extincteur
		AABB(Vector3(-W / 2, -0.1, -8.3), Vector3(0.45, 2, 0.6)),           # poteau
		AABB(Vector3(-W / 2, -0.1, PORTE_Z - 0.7), Vector3(0.8, 2, 1.4)),   # battant de la porte
		AABB(Vector3(-W / 2, -0.1, Z1), Vector3(W, 2, 1.6)),                # contre-jour sous le rideau
		libre.call(-0.3, 0.8, 0.7),                                          # départ du joueur
	]
	for p in [Vector3(-0.95, 0, -7.6), Vector3(-0.25, 0, -14.3), Vector3(1.05, 0, -11.2), Vector3(0.95, 0, -16.2),
			Vector3(-0.9, 0, -5.2), Vector3(0.9, 0, -13.6), Vector3(0.55, 0, -9.5), Vector3(-0.8, 0, -12.8), Vector3(0.7, 0, -15.6)]:
		decor.evite.append(libre.call(p.x, p.z))
	var murs := func(c: Vector3, t: Vector3) -> AABB:
		return AABB(c - t / 2, t)
	decor.evite_murs = [
		murs.call(Vector3(-W / 2, 2.2, -9.6), Vector3(0.6, 1.2, 1.0)),       # lampe rouge
		murs.call(Vector3(-W / 2, 1.6, -7.2), Vector3(0.6, 1.4, 2.2)),       # tag du cercle, poteau
		murs.call(Vector3(-W / 2, 1.2, PORTE_Z), Vector3(0.6, 2.6, 1.4)),    # porte gauche
		murs.call(Vector3(W / 2, 1.2, -14.0), Vector3(0.6, 2.6, 1.4)),       # porte droite
		murs.call(Vector3(W / 2, 1.0, -1.5), Vector3(0.6, 1.5, 0.8)),        # extincteur
		murs.call(Vector3(W / 2, 1.0, -5.85), Vector3(0.6, 1.0, 1.8)),       # caisses
	]
	for z in [0.0, -4.0, -16.0, -12.0]:
		decor.evite_murs.append(murs.call(Vector3(0, H, z), Vector3(W, 0.6, 1.8)))   # néons, ampoule
	add_child(decor)
	decor.couloir(AABB(Vector3(-W / 2, 0, Z1), Vector3(W, H, Z0 - Z1)), {
		"gaine": 1, "cables": -1, "tuyaux": -1, "fin_gaine": -15.0,
		"fuite": Vector3(-1.2, 0, -6.6), "flaques": 0,
		"flaques_pos": [Vector3(0.3, 0, -1.5), Vector3(0.15, 0, -15.2)],
		"dechets": 1.8, "affiches": 5, "tags": 4})
	# portes abîmées : service entrouverte sur le réduit (gauche), fermée (droite)
	decor.porte(Vector3(-W / 2 - 0.1, 0, PORTE_Z + 0.46), 90.0, 55.0)
	decor.porte(Vector3(W / 2, 0, -14.0 - 0.46), -90.0, 0.0, Color(0.6, 0.62, 0.66))
	# un peu de bazar dans le réduit
	_modele("cardboard_box_01", Vector3(-W / 2 - 1.6, 0, PORTE_Z - 0.6), 25, "", true, "carton")
	_modele("cardboard_box_01", Vector3(-W / 2 - 1.5, 0, PORTE_Z + 0.5), -10, "", true, "carton")
	KitDecor.marquer(self)
	print("Décor : %d décalques" % decor.nb_decalques)


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
	# contre-jours (issue #4) : le fond du couloir est la zone la plus claire du champ, pour que
	# quiconque s'y tient se détache en silhouette. Sodium de la rue qui filtre sous le rideau
	# métallique et rase le sol vers le joueur (longues ombres des jambes, brume éclairée)…
	var sodium := Color(1.0, 0.55, 0.18)
	var fuite := SpotLight3D.new()
	fuite.position = Vector3(0, 0.1, Z1 + 0.15)
	fuite.rotation_degrees = Vector3(-3, 180, 0)
	fuite.spot_angle = 55
	fuite.spot_angle_attenuation = 0.8
	fuite.spot_range = 11
	fuite.spot_attenuation = 1.1
	fuite.light_energy = 3.6
	fuite.light_color = sodium
	fuite.light_volumetric_fog_energy = 4.0
	fuite.shadow_enabled = true
	fuite.shadow_blur = 1.5
	add_child(fuite)
	# … et le rideau lui-même, éclairé par la fente du bas (fond clair derrière les silhouettes)
	var rideau := SpotLight3D.new()
	rideau.position = Vector3(0, 0.15, Z1 + 0.9)
	rideau.rotation_degrees = Vector3(28, 0, 0)
	rideau.spot_angle = 60
	rideau.spot_range = 3.5
	rideau.light_energy = 1.6
	rideau.light_color = sodium
	rideau.light_volumetric_fog_energy = 0.0
	rideau.light_specular = 0.3
	add_child(rideau)
	# poussière plus dense devant le rideau : la lumière rasante s'y diffuse
	rendu.brume(AABB(Vector3(-W / 2, 0, Z1), Vector3(W, 2.0, 3.6)), 0.07, Color(0.75, 0.72, 0.66))
	# rebond du sol éclairé, très faible : modelé des épaules et des visages sans éclairer les murs
	rendu.rebond(Vector3(0, 0.25, Z1 + 2.5), sodium.lerp(Color.WHITE, 0.3), 0.12, 3.0)
	rendu.rebond(Vector3(-0.2, 0.3, -7.8), Color(0.8, 0.95, 0.85), 0.06, 2.6)


func _lampe(type: String, pos: Vector3, panne := "aucune") -> Lampe:
	var l := Lampe.new()
	l.type = type
	l.panne = panne
	l.position = pos
	l.graine = int(pos.z * 100.0) + 7
	add_child(l)
	return l


func _cibles() -> void:
	if mode == "video_ragdoll":
		_gardes_ragdoll()
		return
	if mode == "perf":
		# deux gardes de plus, tués au début de la mesure : 4 debout + 2 corps au sol
		_garde("garde_1", Vector3(-0.9, 0, -5.2), 30.0, "Pistol_Idle")
		_garde("garde_4", Vector3(0.9, 0, -13.6), -20.0, "Pistol_Idle")
	var pos := [Vector3(0.55, 0, -9.5), Vector3(-0.8, 0, -12.8), Vector3(0.7, 0, -15.6)]
	for i in pos.size():
		var c := CibleTest.new()
		c.name = "Cible%d" % (i + 1)
		c.position = pos[i]
		c.rotation_degrees.y = [-8.0, 12.0, 0.0][i]
		add_child(c)
		cibles.append(c)
	# gardes du cartel équipés de corps_garde.gd (hitboxes, dégâts localisés, ragdoll), sans IA :
	# l'un dans la zone sombre près du poteau, l'autre en contre-jour devant le rideau métallique,
	# plus deux autres au fond (en mode perf, ces deux-là sont tués d'entrée : corps au sol)
	_garde("garde_2", Vector3(-0.95, 0, -7.6), 18.0, "Pistol_Idle")
	_garde("garde_3", Vector3(-0.25, 0, -14.3), -4.0, "Pistol_Aim_Neutral")
	_garde("garde_1", Vector3(1.05, 0, -11.2), -15.0, "Pistol_Idle")
	_garde("garde_4", Vector3(0.95, 0, -16.2), 5.0, "Pistol_Idle")


var gardes: Array[CorpsGarde] = []


func _garde(nom: String, pos: Vector3, rot_y: float, anim: String) -> CorpsGarde:
	var g := CorpsGarde.new()
	g.name = nom
	g.variante = nom
	g.animation = anim
	g.position = pos
	g.rotation_degrees.y = rot_y
	add_child(g)
	gardes.append(g)
	return g


## Gardes de la vidéo des morts : un qui attend, un qui traverse le couloir, le gros, un qui vise.
func _gardes_ragdoll() -> void:
	_garde("garde_1", Vector3(0.3, 0, -5.5), 8.0, "Pistol_Idle")
	_garde("garde_2", Vector3(-1.3, 0, -7.0), 90.0, "Pistol_Idle")
	_garde("garde_3", Vector3(-0.45, 0, -8.3), 6.0, "Pistol_Aim_Neutral")
	_garde("garde_4", Vector3(0.55, 0, -9.5), -12.0, "Pistol_Aim_Neutral")
	if sortie == "ext":
		# vue de contrôle depuis le côté, sans effet caméra-piéton, un peu de lumière sur la scène
		_cam_ext = Camera3D.new()
		_cam_ext.fov = 62
		add_child(_cam_ext)
		_cam_ext.position = Vector3(0.95, 2.25, -3.3)
		_cam_ext.look_at_from_position(_cam_ext.position, Vector3(-0.25, 0.4, -7.7))
		_cam_ext.make_current()
		var l := OmniLight3D.new()
		l.position = Vector3(0.4, 2.6, -6.8)
		l.omni_range = 6.0
		l.light_energy = 0.9
		l.shadow_enabled = true
		add_child(l)


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
	if mode == "video_ragdoll":
		_video_ragdoll()
		if t >= DUREE_RAGDOLL and _une_fois("fin"):
			_quitter()
		return
	if mode == "perf" and t >= 0.2 and gardes.size() >= 6 and _une_fois("corps"):
		# les deux gardes en plus tombent : corps au sol pendant toute la mesure
		for g in [gardes[0], gardes[1]]:
			g.recevoir_tir(55.0, "Head", g.global_position + Vector3(0, 1.6, 0), Vector3.ZERO, Vector3(0.2, 0, -1).normalized(), null)
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
	elif mode == "video_decor":
		_video_decor()
		if t >= 9.5 and _une_fois("fin"):
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


## Vidéo des morts (10,8 s) : [début de la visée, heure du tir, garde, os visé]. Le joueur vise
## réellement l'os (hitbox) et tire avec son arme dès que le viseur est dessus : balle dans la tête
## d'un garde qui attend, deux balles dans le torse d'un garde qui marche, jambe du gros (il tombe
## assis) puis achèvement, bras d'un garde qui vise (le bras retombe) puis deux balles.
const PLAN_RAGDOLL := [
	[0.5, 1.5, 0, "Head"],
	[2.1, 2.95, 1, "spine_03"],
	[3.0, 3.3, 1, "spine_01"],
	[3.8, 4.6, 2, "thigh_l"],
	[5.5, 6.4, 2, "spine_03"],
	[6.5, 6.85, 2, "spine_03"],
	[7.4, 8.1, 3, "upperarm_r"],
	[8.6, 9.1, 3, "spine_03"],
	[9.2, 9.45, 3, "spine_01"],
]
const DUREE_RAGDOLL := 10.8


func _video_ragdoll() -> void:
	var j := joueur
	j.auto_axes = Vector2.ZERO
	j.auto_tenu.clear()
	if t < 0.05:
		j.global_position = Vector3(0.05, 0.05, -2.6)
		j.arme.chambre = true
		j.arme.chargeur = 15
	# le garde 2 traverse le couloir de gauche à droite
	if t >= 1.5 and _une_fois("marche"):
		gardes[1].marcher(Vector3(1.25, 0, 0))
	if t >= 4.6 and gardes[1].vivant and _une_fois("arret"):
		gardes[1].arreter()
	var actif: Array = []
	for e in PLAN_RAGDOLL:
		if t >= e[0] and not _faits.has("tir_%s_%s" % [e[1], e[3]]):
			actif = e
			break
	if actif.is_empty():
		_regarder(rad_to_deg(j.lacet), -6.0, 0.4)
		return
	j.auto_tenu["viser"] = true
	var g: CorpsGarde = gardes[actif[2]]
	var hb := g.get_node_or_null("hb_" + str(actif[3])) as Node3D
	if hb == null:
		return
	var cible := _point_degage(hb)
	_viser_vers(cible, 2.2)
	var vers := (cible - j.camera.global_position).normalized()
	var ecart := rad_to_deg(vers.angle_to(-j.camera.global_basis.z))
	if t >= actif[1] and (ecart < 0.5 or t > actif[1] + 0.6):
		_faits["tir_%s_%s" % [actif[1], actif[3]]] = true
		j.auto_appui["tirer"] = true
		var q := PhysicsRayQueryParameters3D.create(j.camera.global_position, j.camera.global_position - j.camera.global_basis.z * 30.0, 1 | 8, [j.get_rid()])
		q.collide_with_areas = true
		var r := get_world_3d().direct_space_state.intersect_ray(q)
		print("TIR %s %s écart %.2f° → %s" % [g.name, actif[3], ecart, ("%s %s" % [(r["collider"] as Node).name, r["position"]]) if not r.is_empty() else "rien"])


## Point de la hitbox que le joueur voit sans obstacle (bras devant le torse, autre garde…) : centre,
## puis quelques décalages ; à défaut le centre.
func _point_degage(hb: Node3D) -> Vector3:
	var depart := joueur.camera.global_position
	var ds := get_world_3d().direct_space_state
	var b := hb.global_basis.orthonormalized()
	for d in [Vector3.ZERO, b.y * 0.08, -b.y * 0.08, b.x * 0.06, -b.x * 0.06, b.y * 0.14, -b.y * 0.14]:
		var p: Vector3 = hb.global_position + d
		var q := PhysicsRayQueryParameters3D.create(depart, p + (p - depart).normalized() * 0.3, 1 | 8, [joueur.get_rid()])
		q.collide_with_areas = true
		var r := ds.intersect_ray(q)
		if not r.is_empty() and r["collider"] == hb:
			return p
	return hb.global_position


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


## Vidéo du décor (9,5 s) : marche lente, regard sur la flaque (reflet du néon), au plafond (gaine,
## câbles, tuyaux), sur la porte entrouverte, sur les affiches, puis vers le fond en contre-jour.
func _video_decor() -> void:
	var j := joueur
	j.auto_axes = Vector2.ZERO
	j.auto_tenu.clear()
	if t < 0.05:
		j.global_position = Vector3(0.35, 0.05, 1.0)
	if t < 8.6:
		j.auto_axes = Vector2(0, 0.4)
	if t < 2.0:
		_regarder(2.0, -48.0, 2.0)
	elif t < 3.0:
		_regarder(-14.0, 34.0, 1.6)
	elif t < 4.3:
		_regarder(38.0, -8.0, 1.6)
	elif t < 5.4:
		_regarder(16.0, 32.0, 1.4)
	elif t < 6.9:
		_regarder(-50.0, 0.0, 1.8)
	else:
		_regarder(0.0, -9.0, 1.6)


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
		"sombre", "contre":
			# lisibilité : garde dans la zone sombre près du poteau / garde au fond devant le rideau
			if t < 0.05:
				j.global_position = Vector3(0.6, 0.05, -2.6) if vue == "sombre" else Vector3(-0.7, 0.05, -8.4)
			if gardes.size() >= 2:
				_viser_vers(gardes[0 if vue == "sombre" else 1].global_position + Vector3(0, 1.3, 0), 4.0)
			fin = 3.0   # laisse l'exposition automatique se poser
		"porte":
			if t < 0.05:
				j.global_position = Vector3(0.5, 0.05, -2.9)
			_viser_vers(Vector3(-W / 2, 1.0, PORTE_Z - 0.2), 4.0)
			fin = 2.5
		"plafond", "sol", "couloir", "flaque":
			# décor : plafond technique, sol (poussière, déchets, flaque), couloir en enfilade
			if t < 0.05:
				j.global_position = {"plafond": Vector3(0.3, 0.05, -2.0), "sol": Vector3(0.2, 0.05, -1.2), "couloir": Vector3(0.9, 0.05, 1.4), "flaque": Vector3(0.35, 0.05, -0.25)}[vue]
			_regarder({"plafond": 4.0, "sol": 6.0, "couloir": 6.0, "flaque": 2.0}[vue], {"plafond": 38.0, "sol": -42.0, "couloir": -3.0, "flaque": -50.0}[vue], 6.0)
			fin = 2.5
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
			if _cam_ext:
				# contrôle du trajet de la main gauche (ceinture → puits → culasse), vu de trois quarts avant gauche
				_cam_ext.global_position = j.global_position + j.global_basis * Vector3(-1.1, 1.3, -1.1)
				_cam_ext.look_at(j.global_position + Vector3(0, 1.15, 0))
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
