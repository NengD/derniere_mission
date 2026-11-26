class_name Joueur
extends CharacterBody3D
## Marc Delmas à la première personne, vue caméra-piéton.
## Construit tous ses nœuds en code (scène `scenes/joueur/joueur.tscn` = ce script seul) :
##   Joueur (lacet) ─ Tete (hauteur, penché, tangage, roulis) ─ Recul (recul, saccades, balancement)
##     ─ Camera3D ─ PorteArme (pose procédurale) ─ pistolet.glb + repères (bouche, éjection)
##   Corps : marc.glb visible (jambes animées, buste et bras pilotés par BrasIK), tête cachée.
##   CameraPieton : effet d'image, REC, sous-titres, HUD optionnel.
##
## Couches physiques : 1 monde, 2 joueur, 3 corps des ennemis, 4 hitboxes, 5 interactifs.
## Interface de dégâts (voir rapport) : ce que le tir touche reçoit, s'il a la méthode,
##   recevoir_tir(degats, os_ou_zone, point, normale, direction, tireur)
## Le joueur lui-même expose recevoir_tir(...) et recevoir_degats(montant, zone, direction).
##
## Entrées : actions de l'autoload Commandes. En mode « pilote automatique » (captures, tests),
## aucune entrée réelle n'est lue : le scénario remplit `auto_axes`, `auto_tenu`, `auto_appui`
## et appelle `tourner()`.

signal mort
signal blesse(montant: float, zone: int)
signal tir_bruit(position: Vector3, portee: float)   # pour l'ouïe des gardes
signal aide_changee(texte: String)
signal munitions_changees(dans_arme: int, reserve: int)

const COUCHE_MONDE := 1
const COUCHE_JOUEUR := 2
const COUCHE_ENNEMIS := 4
const COUCHE_HITBOX := 8
const COUCHE_INTERACTIF := 16
const CALQUE_VUE_JOUEUR := 2       # calque de rendu du corps et de l'arme (pas de décalques dessus)

const MARCHE := 2.6
const COURSE := 5.0
const ACCROUPI := 1.4
const RECUL_FACTEUR := 0.8         # vitesse en marche arrière
const VISEE_FACTEUR := 0.7
const ACCEL_SOL := 11.0
const FREIN_SOL := 14.0
const ACCEL_AIR := 2.0
const GRAVITE := 11.0
const SAUT := 3.1
const HAUTEUR_DEBOUT := 1.8
const HAUTEUR_ACCROUPI := 1.15
const OEIL_DEBOUT := 1.64
const OEIL_ACCROUPI := 1.08
## Caméra-piéton fixée sur la poitrine (sternum), sous les yeux et en avant des épaules : la tête (pivot
## du regard, logique, dégâts) reste aux yeux, seule l'image part de la poitrine. Bras vus par en dessous
## et en enfilade : seuls avant-bras et mains entrent dans le champ.
const CAMERA_SOUS_YEUX := 0.15
const CAMERA_AVANT := 0.14
const PENCHE := 0.35
const PENCHE_ROULIS := 11.0        # degrés
const RAYON := 0.3
const DEGATS_PISTOLET := 55.0
const PORTEE_TIR := 150.0
const PORTEE_INTERACTION := 2.0
const PORTEE_BRUIT_TIR := 45.0

# --- options
@export var creer_effet := true        # couche caméra-piéton
@export var corps_visible := true
@export var pilote_auto := false
@export var bus_reverb := "Rev_Couloir"  # changé par les zones de réverbération du niveau

# --- état
var sante := SanteJoueur.new()
var arme := EtatArme.new(15, 2)
var lacet := 0.0
var tangage := 0.0
var est_mort := false
var visee_t := 0.0
var accroupi_t := 0.0
var penche := 0.0
var course_t := 0.0
var essoufflement := 0.0

# --- entrées automatiques
var auto_axes := Vector2.ZERO          # x : droite(+)/gauche(-), y : avancer(+)/reculer(-)
var auto_tenu := {}                    # action -> true
var auto_appui := {}                   # action -> true (un seul pas physique)

# --- nœuds
var tete: Node3D
var recul_n: Node3D
var camera: Camera3D
var porte_arme: Node3D
var pistolet: Node3D
var bouche: Marker3D
var ejection: Marker3D
var corps: Node3D
var corps_anim: AnimationPlayer
var bras: BrasIK
var effet: CameraPieton
var forme: CollisionShape3D
var capsule: CapsuleShape3D
var lumiere_tir: OmniLight3D
var sprite_tir: Sprite3D               # flamme vue de face (atlas 2 × 2 de flash_canon.png)
var flamme_tir: MeshInstance3D         # flamme vue de côté : deux plans croisés le long du canon (atlas flamme_bouche.png)
var _mat_flamme: StandardMaterial3D
var _detente := 0.0                   # index droit : 0 le long de la carcasse, 1 sur la détente
var _prechauffage := false
var _flash_images := 0                 # images restantes du coup de feu (flamme + lumière : 2 images)
var chargeur_visuel: MeshInstance3D
var glissiere: Node3D                  # pièce mobile du glb (recule au tir, bloquée en arrière à vide)
var chargeur_arme: Node3D              # chargeur engagé (pièce du glb)
var glissiere_bloquee := false
var _glissiere_repos := Transform3D.IDENTITY
var _chargeur_repos := Transform3D.IDENTITY
var _glissiere_t := 9.0                # temps depuis le dernier départ du coup
var _fumees: Array[GPUParticles3D] = []
var _fumee_i := 0

# --- interne
var _sons := {}
var _rng := RandomNumberGenerator.new()
var _recul := Vector2.ZERO
var _recul_cible := Vector2.ZERO
var _coup_arme := 0.0
var _recul_lateral := 0.0              # sens du recul de ce coup (-1..1)
var _secousse := 0.0
var _coup_tete := Vector2.ZERO
var _balance := Vector2.ZERO
var _balance_cible := Vector2.ZERO
var _phase_pas := 0.0
var _dist_pas := 0.0
var _chaleur := 0.0
var _depuis_tir := 99.0
var _mur_t := 0.0
var _sang := 0.0
var _trouble_coup := 0.0
var _coeur_t := 0.0
var _resp: AudioStreamPlayer
var _rech_t := -1.0
var _rech_duree := 0.0
var _rech_action := ""
var _rech_evts: Array = []
var _soin_t := -1.0
var _cible_interaction: Node = null
var _texte_aide := ""
var _base_cam_prec: Basis
var _anim_corps := ""
var _douilles: Array[Node] = []
var _decalques: Array[Node] = []
var _t := 0.0


func _ready() -> void:
	_rng.randomize()
	add_to_group("joueur")
	collision_layer = COUCHE_JOUEUR
	collision_mask = COUCHE_MONDE | COUCHE_ENNEMIS
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(50)
	_construire()
	sante.regeneration = float(_reglage("regeneration", 0.0))
	_base_cam_prec = camera.global_basis
	_emettre_munitions()
	_prechauffer.call_deferred()


func _exit_tree() -> void:
	# ressources partagées gardées en variables statiques : libérées pour une sortie propre
	_mat_fumee = null
	_pm_fumee = null
	_mesh_douille = null
	_forme_douille = null
	_tex_impact = null
	FxImpact.liberer()


# ================================================================ construction

func _construire() -> void:
	forme = CollisionShape3D.new()
	capsule = CapsuleShape3D.new()
	capsule.radius = RAYON
	capsule.height = HAUTEUR_DEBOUT
	forme.shape = capsule
	forme.position.y = HAUTEUR_DEBOUT / 2.0
	add_child(forme)

	tete = Node3D.new()
	tete.name = "Tete"
	tete.position = Vector3(0, OEIL_DEBOUT - 0.1, 0)
	add_child(tete)
	recul_n = Node3D.new()
	recul_n.name = "Recul"
	recul_n.position = Vector3(0, 0.1 - CAMERA_SOUS_YEUX, -CAMERA_AVANT)
	tete.add_child(recul_n)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.near = 0.02
	camera.far = 120.0
	camera.fov = float(_reglage("fov", 78.0))
	recul_n.add_child(camera)

	porte_arme = Node3D.new()
	porte_arme.name = "PorteArme"
	camera.add_child(porte_arme)
	pistolet = (load("res://assets/weapons/pistolet.glb") as PackedScene).instantiate()
	porte_arme.add_child(pistolet)
	pistolet.scale = Vector3.ONE * ECHELLE_ARME
	glissiere = pistolet.find_child("glissiere", true, false)
	chargeur_arme = pistolet.find_child("chargeur", true, false)
	if glissiere:
		_glissiere_repos = glissiere.transform
	if chargeur_arme:
		_chargeur_repos = chargeur_arme.transform
	bouche = Marker3D.new()
	bouche.position = Vector3(0, 0.072, -0.152)
	pistolet.add_child(bouche)
	ejection = Marker3D.new()
	ejection.position = Vector3(0.009, 0.082, -0.056)
	pistolet.add_child(ejection)
	_construire_effets_arme()
	if OS.has_environment("DEBUG_LUMIERE_MAINS"):
		var l := OmniLight3D.new()
		l.light_energy = float(OS.get_environment("DEBUG_LUMIERE_MAINS"))
		l.omni_range = 2.0
		l.position = Vector3(-0.25, 0.25, -0.2)
		camera.add_child(l)

	if corps_visible:
		_construire_corps()
	_calque_vue(pistolet)

	if creer_effet:
		effet = CameraPieton.new()
		effet.name = "CameraPieton"
		add_child(effet)

	_resp = AudioStreamPlayer.new()
	_resp.stream = _boucle("respiration_peur")
	_resp.bus = "Voix"
	_resp.volume_db = -60.0
	add_child(_resp)


func _calque_vue(n: Node) -> void:
	for mi in n.find_children("*", "VisualInstance3D", true, false):
		(mi as VisualInstance3D).layers = CALQUE_VUE_JOUEUR
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = CALQUE_VUE_JOUEUR


func _construire_corps() -> void:
	corps = (load("res://assets/characters/marc.glb") as PackedScene).instantiate()
	corps.name = "Corps"
	corps.rotation_degrees.y = 180.0
	corps.position = Vector3(0, 0, 0.13)
	add_child(corps)
	_calque_vue(corps)
	corps_anim = corps.find_children("*", "AnimationPlayer", true, false)[0]
	for n in ["Idle", "Walk", "Jog_Fwd", "Sprint", "Crouch_Idle", "Crouch_Fwd", "Pistol_Idle"]:
		if corps_anim.has_animation(n):
			corps_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	_jouer_corps("Pistol_Idle", 1.0)
	_regler_tissus(corps)
	_ombre_tete()
	var sk: Skeleton3D = corps.find_children("*", "Skeleton3D", true, false)[0]
	bras = BrasIK.new()
	bras.name = "BrasIK"
	sk.add_child(bras)


## Préchauffage (évite l'à-coup au premier tir / premier impact) : sons et textures chargés d'avance,
## flamme, fumée, douille, poussière et étincelles affichées une fois, invisibles (noires en additif,
## minuscules), pendant les premières images ; les shaders sont alors compilés pendant le chargement.
func _prechauffer() -> void:
	if not is_inside_tree():
		return
	for n in ["tir_pistolet_1", "tir_pistolet_2", "tir_pistolet_3", "douille_1", "douille_2", "douille_3",
			"impact_beton_1", "impact_beton_2", "impact_beton_3", "impact_metal_1", "impact_metal_2",
			"impact_chair_1", "impact_chair_2", "impact_chair_3", "clic_vide", "chargeur_sortie",
			"chargeur_entree", "culasse"]:
		_son(n)
	if _tex_impact == null:
		_tex_impact = load("res://assets/fx/impact_balle.png")
	var devant := camera.global_transform * Vector3(0, 0, -1.0)
	FxImpact.prechauffer(_monde(), devant)
	# flamme et lumière : visibles mais éteintes
	_prechauffage = true
	sprite_tir.modulate.a = 0.0
	_mat_flamme.albedo_color = Color(0, 0, 0)
	sprite_tir.visible = true
	flamme_tir.visible = true
	lumiere_tir.light_energy = 0.0
	lumiere_tir.visible = true
	# fumée : un émetteur minuscule
	var f := _particules_fumee()
	f.amount = 1
	f.lifetime = 0.3
	f.local_coords = true
	add_child(f)
	f.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.001), devant)
	f.emitting = true
	# douille (matériau métal) : minuscule, un instant
	var d := MeshInstance3D.new()
	_douille_preparer()
	d.mesh = _mesh_douille
	d.scale = Vector3.ONE * 0.001
	_monde().add_child(d)
	d.global_position = devant
	for i in 4:
		await get_tree().process_frame
	if not is_instance_valid(self):
		return
	f.queue_free()
	d.queue_free()
	_prechauffage = false
	if _flash_images <= 0:
		sprite_tir.visible = false
		flamme_tir.visible = false
		lumiere_tir.visible = false


## Ombre du joueur : le corps de Marc (bras compris) projette sa vraie ombre ; la tête et le cou, retirés
## du modèle (la caméra est là), sont remplacés pour l'ombre seule par une tête et un cou simples, invisibles
## à l'écran. Sans eux l'ombre au sol est une tache sans tête, informe.
func _ombre_tete() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.1, 0.09, 0.08)
	var t := MeshInstance3D.new()
	t.name = "OmbreTete"
	var sp := SphereMesh.new()
	sp.radius = 0.1
	sp.height = 0.24
	sp.radial_segments = 16
	sp.rings = 8
	t.mesh = sp
	t.position = Vector3(0, 0.1, 0.06)
	var c := MeshInstance3D.new()
	c.name = "OmbreCou"
	var cap := CapsuleMesh.new()
	cap.radius = 0.055
	cap.height = 0.2
	c.mesh = cap
	c.position = Vector3(0, -0.04, 0.07)
	for mi in [t, c]:
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		mi.layers = CALQUE_VUE_JOUEUR
		tete.add_child(mi)


## Tissus : reflet spéculaire réduit (un tissu mat ne brille pas en lumière rasante), cuir un peu plus vif.
func _regler_tissus(n: Node) -> void:
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).get_active_material(0) as BaseMaterial3D
		if m == null:
			continue
		m = m.duplicate()
		match String(mi.name):
			"Veste":
				m.metallic_specular = 0.12
				m.roughness = 1.0
			"Gants":
				# cuir noir : albédo cuit trop clair pour l'exposition auto d'un couloir sombre (gris clair
				# sous la lampe) → assombri ; reflet de cuir étroit et faible (rugosité ≈ 0,45 de la texture)
				m.albedo_color = Color(0.42, 0.41, 0.4)
				m.metallic_specular = 0.28
				m.cull_mode = BaseMaterial3D.CULL_BACK
			_:
				m.metallic_specular = 0.3
		(mi as MeshInstance3D).material_override = m


func _construire_effets_arme() -> void:
	# lumière du coup : ponctuelle, chaude, avec ombres, deux images seulement
	lumiere_tir = OmniLight3D.new()
	lumiere_tir.light_color = Color(1.0, 0.66, 0.36)
	lumiere_tir.omni_range = 6.0
	lumiere_tir.omni_attenuation = 1.6
	lumiere_tir.light_energy = 0.0
	lumiere_tir.light_volumetric_fog_energy = 0.4
	lumiere_tir.shadow_enabled = true
	lumiere_tir.position = Vector3(0, 0, -0.05)
	lumiere_tir.visible = false
	bouche.add_child(lumiere_tir)
	# flamme de bouche : petite fleur de gaz chauds (pas d'étoile), additive, variante tirée au hasard
	sprite_tir = Sprite3D.new()
	sprite_tir.texture = load("res://assets/fx/flash_canon.png")
	sprite_tir.region_enabled = true
	sprite_tir.region_rect = Rect2(0, 0, 256, 256)
	sprite_tir.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite_tir.pixel_size = 0.00022
	sprite_tir.shaded = false
	sprite_tir.double_sided = true
	sprite_tir.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	sprite_tir.modulate = Color(1, 0.9, 0.75, 0.9)
	sprite_tir.position = Vector3(0, 0, -0.012)
	sprite_tir.visible = false
	bouche.add_child(sprite_tir)
	_mat_flamme = StandardMaterial3D.new()
	_mat_flamme.albedo_texture = load("res://assets/fx/flamme_bouche.png")
	_mat_flamme.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_flamme.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat_flamme.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_flamme.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_flamme.uv1_scale = Vector3(1, 0.25, 1)
	_mat_flamme.albedo_color = Color(1.6, 1.4, 1.2)
	var am := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# deux plans croisés le long de -Z (u = 0 à la bouche), 9 cm de long, 2,4 cm de large
	for k in 2:
		var lat := Vector3(0.012, 0, 0) if k == 0 else Vector3(0, 0.012, 0)
		var av := Vector3(0, 0, -0.09)
		var c := [-lat, -lat + av, lat + av, lat]
		var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_uv(uv[i])
			st.add_vertex(c[i])
	st.commit(am)
	flamme_tir = MeshInstance3D.new()
	flamme_tir.mesh = am
	flamme_tir.material_override = _mat_flamme
	flamme_tir.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flamme_tir.visible = false
	bouche.add_child(flamme_tir)
	# fumée : trois émetteurs utilisés à tour de rôle
	for i in 3:
		var p := _particules_fumee()
		add_child(p)
		_fumees.append(p)
	# chargeur hors de l'arme pendant le rechargement (copie de la pièce du glb)
	chargeur_visuel = MeshInstance3D.new()
	if chargeur_arme is MeshInstance3D:
		chargeur_visuel.mesh = (chargeur_arme as MeshInstance3D).mesh
	else:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.022, 0.115, 0.032)
		chargeur_visuel.mesh = bm
	chargeur_visuel.visible = false
	add_child(chargeur_visuel)
	chargeur_visuel.top_level = true


static var _mat_fumee: StandardMaterial3D
static var _pm_fumee: ParticleProcessMaterial


func _particules_fumee() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 7
	p.lifetime = 1.6
	p.explosiveness = 0.85
	p.local_coords = false
	if _pm_fumee == null:
		_pm_fumee = ParticleProcessMaterial.new()
		_pm_fumee.direction = Vector3(0, 0.3, -1)
		_pm_fumee.spread = 25.0
		_pm_fumee.initial_velocity_min = 0.2
		_pm_fumee.initial_velocity_max = 0.7
		_pm_fumee.gravity = Vector3(0, 0.12, 0)
		_pm_fumee.damping_min = 0.8
		_pm_fumee.damping_max = 1.4
		_pm_fumee.scale_min = 0.5
		_pm_fumee.scale_max = 1.0
		var sc := CurveTexture.new()
		var c := Curve.new()
		c.add_point(Vector2(0, 0.4))
		c.add_point(Vector2(1, 2.2))
		sc.curve = c
		_pm_fumee.scale_curve = sc
		var g := Gradient.new()
		g.set_color(0, Color(0.7, 0.7, 0.68, 0.32))
		g.set_color(1, Color(0.6, 0.6, 0.6, 0.0))
		var gt := GradientTexture1D.new()
		gt.gradient = g
		_pm_fumee.color_ramp = gt
		_pm_fumee.angle_min = 0.0
		_pm_fumee.angle_max = 360.0
	p.process_material = _pm_fumee
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.09)
	if _mat_fumee == null:
		_mat_fumee = StandardMaterial3D.new()
		_mat_fumee.albedo_texture = load("res://assets/fx/fumee.png")
		_mat_fumee.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat_fumee.vertex_color_use_as_albedo = true
		_mat_fumee.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_mat_fumee.billboard_keep_scale = true
		_mat_fumee.roughness = 1.0
	q.material = _mat_fumee
	p.draw_pass_1 = q
	p.layers = CALQUE_VUE_JOUEUR
	return p


# ================================================================ réglages, sons

func _reglage(cle: String, defaut):
	if has_node("/root/Reglages"):
		var v = get_node("/root/Reglages").call("get_v", cle)
		return defaut if v == null else v
	return defaut


func _son(nom: String) -> AudioStream:
	if not _sons.has(nom):
		_sons[nom] = load("res://assets/sons/%s.wav" % nom)
	return _sons[nom]


func _son_hasard(prefixe: String, n: int) -> AudioStream:
	return _son("%s_%d" % [prefixe, _rng.randi_range(1, n)])


func _boucle(nom: String) -> AudioStream:
	var s: AudioStreamWAV = (_son(nom) as AudioStreamWAV).duplicate()
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = int(s.get_length() * s.mix_rate)
	return s


func _jouer(flux: AudioStream, volume := 0.0, hauteur := 1.0, bus := "Effets") -> void:
	if has_node("/root/Audio"):
		get_node("/root/Audio").son_2d(flux, self, volume, hauteur, bus)


func _jouer_3d(flux: AudioStream, pos: Vector3, volume := 0.0) -> void:
	if has_node("/root/Audio"):
		get_node("/root/Audio").son_3d(flux, pos, _monde(), volume, _rng.randf_range(0.94, 1.06))


func _monde() -> Node:
	var s := get_tree().current_scene
	return s if s != null else get_parent()


# ================================================================ entrées

func _tenu(a: String) -> bool:
	if pilote_auto:
		return auto_tenu.get(a, false)
	return InputMap.has_action(a) and Input.is_action_pressed(a)


func _appui(a: String) -> bool:
	if pilote_auto:
		return auto_appui.has(a)
	return InputMap.has_action(a) and Input.is_action_just_pressed(a)


func _axes() -> Vector2:
	if pilote_auto:
		return auto_axes.limit_length(1.0)
	var v := Vector2.ZERO
	if InputMap.has_action("avancer"):
		v.x = Input.get_action_strength("droite") - Input.get_action_strength("gauche")
		v.y = Input.get_action_strength("avancer") - Input.get_action_strength("reculer")
	return v.limit_length(1.0)


## Capture la souris : à appeler par le niveau en jeu réel uniquement (jamais en capture / test).
func capturer_souris(oui := true) -> void:
	if pilote_auto:
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if oui else Input.MOUSE_MODE_VISIBLE


func _unhandled_input(ev: InputEvent) -> void:
	if pilote_auto or est_mort:
		return
	if ev is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s: float = float(_reglage("sensibilite", 0.12)) * lerp(1.0, 0.8, visee_t)
		var r := (ev as InputEventMouseMotion).relative   # delta brut, jamais multiplié par delta
		tourner(r.x * s, r.y * s)


## Tourne le regard (degrés) : dx vers la droite, dy vers le bas.
func tourner(dx: float, dy: float) -> void:
	lacet -= deg_to_rad(dx)
	tangage = clamp(tangage - deg_to_rad(dy), deg_to_rad(-78), deg_to_rad(80))
	rotation.y = lacet
	_balance_cible += Vector2(dx, dy) * 0.25


# ================================================================ physique

func _physics_process(delta: float) -> void:
	_t += delta
	if est_mort:
		velocity.x = move_toward(velocity.x, 0, FREIN_SOL * delta)
		velocity.z = move_toward(velocity.z, 0, FREIN_SOL * delta)
		velocity.y -= GRAVITE * delta
		move_and_slide()
		auto_appui.clear()
		return
	arme.avancer(delta)
	sante.regeneration = float(_reglage("regeneration", 0.0))
	sante.avancer(delta)
	_depuis_tir += delta
	_chaleur = max(0.0, _chaleur - delta * 2.2)
	_deplacer(delta)
	_actions(delta)
	_interaction()
	_pas(delta)
	auto_appui.clear()


func _deplacer(delta: float) -> void:
	var e := _axes()
	var veut_accroupi := _tenu("accroupi")
	if not veut_accroupi and accroupi_t > 0.5 and _plafond_bas():
		veut_accroupi = true
	accroupi_t = move_toward(accroupi_t, 1.0 if veut_accroupi else 0.0, delta / 0.28)
	var h: float = lerp(HAUTEUR_DEBOUT, HAUTEUR_ACCROUPI, accroupi_t)
	capsule.height = h
	forme.position.y = h / 2.0

	var occupe := _rech_t >= 0.0 or _soin_t >= 0.0
	var vise := _tenu("viser") and course_t < 0.5 and _soin_t < 0.0
	var court := _tenu("courir") and e.y > 0.4 and accroupi_t < 0.3 and not vise and is_on_floor()
	course_t = move_toward(course_t, 1.0 if court else 0.0, delta / 0.2)
	visee_t = move_toward(visee_t, 1.0 if vise else 0.0, delta / 0.2)

	var vmax := MARCHE
	if court:
		vmax = COURSE
	elif accroupi_t > 0.5:
		vmax = ACCROUPI
	if e.y < -0.1:
		vmax *= RECUL_FACTEUR
	vmax *= lerp(1.0, VISEE_FACTEUR, visee_t)
	if occupe and not court:
		vmax *= 0.9
	var dir := global_basis * Vector3(e.x, 0, -e.y)
	var cible := dir * vmax
	var horiz := Vector3(velocity.x, 0, velocity.z)
	var acc := ACCEL_AIR
	if is_on_floor():
		acc = ACCEL_SOL if cible.length() > horiz.length() else FREIN_SOL
	horiz = horiz.move_toward(cible, acc * delta)
	velocity.x = horiz.x
	velocity.z = horiz.z
	if is_on_floor():
		if _appui("sauter") and accroupi_t < 0.2:
			velocity.y = SAUT
	else:
		velocity.y -= GRAVITE * delta
	move_and_slide()

	# essoufflement : monte en courant, redescend lentement
	if court and horiz.length() > 3.5:
		essoufflement = min(1.0, essoufflement + delta * 0.11)
	else:
		essoufflement = max(0.0, essoufflement - delta * 0.05)

	# se pencher, bloqué par les murs
	var p := 0.0
	if course_t < 0.5:
		if _tenu("pencher_droite"):
			p += PENCHE
		if _tenu("pencher_gauche"):
			p -= PENCHE
	penche = move_toward(penche, _penche_libre(p), delta * 1.5)
	# un mur se rapproche : on se redresse aussitôt
	penche = _penche_libre(penche)

	# arme trop près d'un mur : on la ramènera contre soi
	var q := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position - camera.global_basis.z * 0.75, COUCHE_MONDE, [get_rid()])
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	var mur := 0.0
	if not r.is_empty():
		mur = clamp(1.0 - (camera.global_position.distance_to(r["position"]) - 0.3) / 0.4, 0.0, 1.0)
	_mur_t = move_toward(_mur_t, mur, delta * 4.0)


func _plafond_bas() -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var s := SphereShape3D.new()
	s.radius = RAYON * 0.9
	q.shape = s
	q.transform = Transform3D(Basis(), global_position + Vector3(0, HAUTEUR_DEBOUT - RAYON, 0))
	q.collision_mask = COUCHE_MONDE
	q.exclude = [get_rid()]
	return not get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


## Distance de penché réellement possible (test de collision d'une sphère depuis la tête).
func _penche_libre(voulu: float) -> float:
	if voulu == 0.0 or not is_inside_tree():
		return voulu
	var q := PhysicsShapeQueryParameters3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.16
	q.shape = s
	var h: float = lerp(OEIL_DEBOUT, OEIL_ACCROUPI, accroupi_t)
	q.transform = Transform3D(Basis(), global_position + Vector3(0, h, 0))
	q.motion = global_basis.x * voulu
	q.collision_mask = COUCHE_MONDE
	q.exclude = [get_rid()]
	var r := get_world_3d().direct_space_state.cast_motion(q)
	if r.is_empty():
		return voulu
	return voulu * float(r[0])


# ================================================================ arme

func _actions(delta: float) -> void:
	if _appui("tirer") and _soin_t < 0.0:
		course_t = 0.0   # tirer interrompt la course
		_appuyer_detente()
	if _appui("recharger") and _soin_t < 0.0:
		_recharger()
	if _appui("soigner") and _rech_t < 0.0:
		if sante.commencer_soin():
			_soin_t = 0.0
			_jouer(_son("souffle_coupe"), -10.0, 1.0, "Voix")
	if _soin_t >= 0.0:
		_soin_t += delta
		if not sante.en_soin():
			_soin_t = -1.0
	if _rech_t >= 0.0:
		_rech_t += delta
		while not _rech_evts.is_empty() and _rech_t >= float(_rech_evts[0][0]):
			var ev: Array = _rech_evts.pop_front()
			(ev[1] as Callable).call()
		if _rech_t >= _rech_duree:
			_rech_t = -1.0
			chargeur_visuel.visible = false
			_emettre_munitions()


func _appuyer_detente() -> void:
	match arme.tirer():
		EtatArme.Tir.OK:
			_tir()
		EtatArme.Tir.VIDE, EtatArme.Tir.ENRAYEE:
			_jouer(_son("clic_vide"), -6.0, _rng.randf_range(0.95, 1.05))
			_coup_arme = max(_coup_arme, 0.12)
		_:
			pass
	_emettre_munitions()


func angle_dispersion() -> float:
	var v := Vector2(velocity.x, velocity.z).length()
	return Dispersion.angle(v, visee_t, accroupi_t > 0.5, not is_on_floor(), _chaleur, _depuis_tir)


func _tir() -> void:
	var ang := angle_dispersion()
	_depuis_tir = 0.0
	_detente = 1.0
	_chaleur += 1.0
	var base := camera.global_basis
	var dir := Dispersion.direction(base, ang, _rng.randf(), _rng.randf())
	var depart := camera.global_position
	var q := PhysicsRayQueryParameters3D.create(depart, depart + dir * PORTEE_TIR, COUCHE_MONDE | COUCHE_HITBOX, [get_rid()])
	q.collide_with_areas = true
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if has_node("/root/Jeu"):
		get_node("/root/Jeu").score.tirs += 1
	if not r.is_empty():
		var col: Object = r["collider"]
		var point: Vector3 = r["position"]
		var normale: Vector3 = r["normal"]
		var degats := DEGATS_PISTOLET * Degats.attenuation(depart.distance_to(point))
		var receveur := trouver_receveur(col)
		if receveur != null:
			var os_ou_zone = col.get_meta("os", col.get_meta("zone", (col as Node).name if col is Node else ""))
			receveur.call("recevoir_tir", degats, os_ou_zone, point, normale, dir, self)
			if has_node("/root/Jeu"):
				get_node("/root/Jeu").score.touches += 1
		else:
			_impact(point, normale, col)
	# effets
	_jouer(_son_hasard("tir_pistolet", 3), -1.0, _rng.randf_range(0.97, 1.03))
	_jouer(_son_hasard("tir_pistolet", 3), -4.0, _rng.randf_range(0.95, 1.0), bus_reverb)
	tir_bruit.emit(global_position, PORTEE_BRUIT_TIR)
	var k: float = lerp(2.4, 1.7, visee_t) * (0.8 if accroupi_t > 0.5 else 1.0)
	_recul_cible += Vector2(k, _rng.randf_range(-0.7, 0.7))
	_coup_arme = 1.0
	_recul_lateral = _rng.randf_range(-1.0, 1.0)
	_secousse = max(_secousse, 0.35)
	_allumer_flamme()
	if effet:
		effet.eblouir(0.012)   # à peine : la lumière ponctuelle éclaire déjà la pièce, l'image ne doit pas blanchir
	var f := _fumees[_fumee_i]
	_fumee_i = (_fumee_i + 1) % _fumees.size()
	f.global_transform = bouche.global_transform
	f.restart()
	_glissiere_t = 0.0
	# chambre vide après le coup : la glissière reste ouverte (arrêtoir) ; enrayage : à moitié ouverte
	glissiere_bloquee = not arme.chambre
	get_tree().create_timer(0.012, false).timeout.connect(func() -> void:
		if is_instance_valid(self):
			_douille(false))


## Remonte les parents (4 niveaux) pour trouver qui reçoit le tir.
static func trouver_receveur(o: Object) -> Object:
	var n: Node = o as Node
	for i in 5:
		if n == null:
			return null
		if n.has_method("recevoir_tir"):
			return n
		n = n.get_parent()
	return null


func _impact(point: Vector3, normale: Vector3, col: Object) -> void:
	var mat := "beton"
	if col is Node:
		mat = str((col as Node).get_meta("materiau", "beton"))
	if mat == "metal":
		_jouer_3d(_son_hasard("impact_metal", 2), point, -4.0)
	else:
		_jouer_3d(_son_hasard("impact_beton", 3), point, -3.0)
	FxImpact.poussiere(_monde(), point, normale, mat)
	if mat != "metal" or _rng.randf() < 0.7:
		_decalque(point, normale)


func _decalque(point: Vector3, normale: Vector3) -> void:
	var d := Decal.new()
	if _tex_impact == null:
		_tex_impact = load("res://assets/fx/impact_balle.png")   # gardée : sinon relue sur le disque à chaque balle
	d.texture_albedo = _tex_impact
	var t := _rng.randf_range(0.05, 0.075)
	d.size = Vector3(t, 0.06, t)
	d.cull_mask = 1
	d.upper_fade = 0.2
	d.lower_fade = 0.2
	_monde().add_child(d)
	var y := normale.normalized()
	var x := y.cross(Vector3.UP if abs(y.y) < 0.9 else Vector3.RIGHT).normalized()
	var b := Basis(x, y, x.cross(y)).rotated(y, _rng.randf() * TAU)
	d.global_transform = Transform3D(b, point + y * 0.005)
	_decalques.append(d)
	while _decalques.size() > 120:
		var v: Node = _decalques.pop_front()
		if is_instance_valid(v):
			v.queue_free()


static var _tex_impact: Texture2D
static var _mesh_douille: CylinderMesh
static var _forme_douille: CylinderShape3D


func _douille_preparer() -> void:
	if _mesh_douille == null:
		_mesh_douille = CylinderMesh.new()
		_mesh_douille.top_radius = 0.0046
		_mesh_douille.bottom_radius = 0.0046
		_mesh_douille.height = 0.019
		_mesh_douille.radial_segments = 8
		_mesh_douille.rings = 1
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.78, 0.56, 0.26)
		m.metallic = 1.0
		m.roughness = 0.32
		_mesh_douille.material = m
		_forme_douille = CylinderShape3D.new()
		_forme_douille.radius = 0.005
		_forme_douille.height = 0.02


## Douille éjectée (ou cartouche entière lors d'un désenrayage).
func _douille(cartouche: bool) -> void:
	var rb := RigidBody3D.new()
	rb.collision_layer = 0
	rb.collision_mask = COUCHE_MONDE
	rb.mass = 0.012
	rb.continuous_cd = true
	rb.contact_monitor = true
	rb.max_contacts_reported = 1
	_douille_preparer()
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh_douille
	if cartouche:
		mi.scale = Vector3(1, 1.45, 1)
	rb.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = _forme_douille
	rb.add_child(cs)
	_monde().add_child(rb)
	var b := ejection.global_basis.orthonormalized()
	rb.global_transform = Transform3D(b * Basis(Vector3.RIGHT, PI / 2), ejection.global_position)
	rb.linear_velocity = velocity + b.x * _rng.randf_range(2.2, 3.2) + b.y * _rng.randf_range(1.4, 2.2) + b.z * _rng.randf_range(0.3, 0.8)
	rb.angular_velocity = Vector3(_rng.randf_range(-25, 25), _rng.randf_range(-25, 25), _rng.randf_range(-25, 25))
	var deja := [false]
	rb.body_entered.connect(func(_b: Node) -> void:
		if not deja[0] and is_instance_valid(rb):
			deja[0] = true
			_jouer_3d(_son_hasard("douille", 3), rb.global_position, -12.0))
	_douilles.append(rb)
	while _douilles.size() > 40:
		var v: Node = _douilles.pop_front()
		if is_instance_valid(v):
			v.queue_free()


func _recharger() -> void:
	if _rech_t >= 0.0:
		return
	var duree := arme.recharger()
	if duree <= 0.0:
		return
	_rech_action = arme.action_en_cours()
	_rech_duree = duree
	_rech_t = 0.0
	_rech_evts.clear()
	var D := duree
	match _rech_action:
		"desenrayer":
			_rech_evts = [
				[D * 0.15, func() -> void: _jouer(_son("chargeur_entree"), -6.0, 1.1)],
				[D * 0.45, func() -> void:
					_jouer(_son("culasse"), -3.0)
					_liberer_glissiere()
					_douille(true)],
			]
		"recharger_vide":
			_rech_evts = [
				[D * 0.1, func() -> void:
					_jouer(_son("chargeur_sortie"), -4.0)
					_chargeur_tombe()],
				[D * 0.58, func() -> void: _jouer(_son("chargeur_entree"), -3.0)],
				[D * 0.8, func() -> void:
					_jouer(_son("culasse"), -2.0)
					_liberer_glissiere()],
			]
		_:
			_rech_evts = [
				[D * 0.14, func() -> void: _jouer(_son("chargeur_sortie"), -4.0)],
				[D * 0.68, func() -> void: _jouer(_son("chargeur_entree"), -3.0)],
			]


func _chargeur_tombe() -> void:
	var rb := RigidBody3D.new()
	rb.collision_layer = 0
	rb.collision_mask = COUCHE_MONDE
	rb.mass = 0.1
	var mi := MeshInstance3D.new()
	mi.mesh = chargeur_visuel.mesh
	rb.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.024, 0.118, 0.034)
	cs.shape = bs
	cs.position = Vector3(0, -0.055, 0)
	rb.add_child(cs)
	_monde().add_child(rb)
	rb.global_transform = pistolet.global_transform * _chargeur_dans_arme(0.06)
	rb.linear_velocity = velocity + Vector3.DOWN * 1.2
	rb.angular_velocity = Vector3(_rng.randf_range(-3, 3), 0, _rng.randf_range(-3, 3))
	_douilles.append(rb)


## Position du chargeur dans le repère de l'arme ; `sortie` = de combien il dépasse vers le bas
## (le long de la poignée : axe -Y du chargeur).
func _chargeur_dans_arme(sortie: float) -> Transform3D:
	return _chargeur_repos * Transform3D(Basis.IDENTITY, Vector3(0, -sortie, 0))


func ramasser_chargeur(nb: int) -> void:
	arme.ramasser_chargeur(nb)
	_jouer(_son("chargeur_entree"), -14.0, 0.9)
	_emettre_munitions()


func ramasser_trousse() -> bool:
	return sante.ramasser_trousse()


func _emettre_munitions() -> void:
	var reserve := arme.total() - arme.cartouches_dans_arme()
	munitions_changees.emit(arme.cartouches_dans_arme(), reserve)
	if effet:
		effet.munitions(arme.cartouches_dans_arme(), reserve)


# ================================================================ interaction

func _interaction() -> void:
	var depart := camera.global_position
	var fin := depart - camera.global_basis.z * PORTEE_INTERACTION
	var q := PhysicsRayQueryParameters3D.create(depart, fin, COUCHE_MONDE | COUCHE_INTERACTIF, [get_rid()])
	q.collide_with_areas = true
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	var cible: Node = null
	if not r.is_empty():
		var n: Node = r["collider"]
		for i in 4:
			if n == null:
				break
			if n.has_method("interagir"):
				cible = n
				break
			n = n.get_parent()
	_cible_interaction = cible
	var texte := ""
	if cible != null:
		var t: String = cible.call("texte_aide") if cible.has_method("texte_aide") else tr("AIDE_INTERAGIR")
		texte = tr("AIDE_TOUCHE") % [_nom_touche("interagir"), t]
	if texte != _texte_aide:
		_texte_aide = texte
		aide_changee.emit(texte)
		if effet:
			effet.aide(texte)
	if cible != null and _appui("interagir"):
		cible.call("interagir", self)


func _nom_touche(action: String) -> String:
	if not InputMap.has_action(action):
		return "?"
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			var k := (e as InputEventKey).physical_keycode
			return OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(k))
	return "?"


func cible_interaction() -> Node:
	return _cible_interaction


# ================================================================ pas, souffle, cœur

func _pas(delta: float) -> void:
	var v := Vector2(velocity.x, velocity.z).length()
	if not is_on_floor() or v < 0.3:
		_dist_pas = min(_dist_pas, 0.5)
		return
	var foulee := 0.78
	if accroupi_t > 0.5:
		foulee = 0.55
	elif v > 3.5:
		foulee = 1.15
	_dist_pas += v * delta
	_phase_pas += v * delta / foulee * PI
	if _dist_pas >= foulee:
		_dist_pas -= foulee
		if accroupi_t > 0.5:
			_jouer(_son_hasard("pas_doux", 4), -20.0, _rng.randf_range(0.92, 1.05))
		else:
			_jouer(_son_hasard("pas_dur", 4), -15.0 + (5.0 if v > 3.5 else 0.0), _rng.randf_range(0.92, 1.06))


func _sons_corps(delta: float) -> void:
	var g := sante.gravite()
	var peur: float = max(essoufflement, clamp((g - 0.3) / 0.6, 0.0, 1.0))
	var cible_db: float = -60.0 if peur < 0.05 else lerp(-26.0, -6.0, peur)
	_resp.volume_db = move_toward(_resp.volume_db, cible_db, delta * 30.0)
	# la boucle de respiration ne tourne que si on l'entend
	if _resp.volume_db > -59.0 and not _resp.playing:
		_resp.play()
	elif _resp.volume_db <= -59.9 and _resp.playing:
		_resp.stop()
	if g > 0.35 and not est_mort:
		_coeur_t -= delta
		if _coeur_t <= 0.0:
			_coeur_t = lerp(1.15, 0.55, g)
			_jouer(_son("coeur"), lerp(-16.0, -3.0, g), 1.0, "Voix")


# ================================================================ santé

## Dégâts directs (déjà multipliés par la zone). zone : Degats.Zone ; direction : sens de la balle.
func recevoir_degats(montant: float, zone: int = Degats.Zone.TORSE, direction := Vector3.ZERO) -> void:
	if est_mort:
		return
	sante.recevoir(montant)
	_soin_t = -1.0
	var force: float = clamp(montant / 40.0, 0.3, 1.5)
	_secousse = max(_secousse, 0.9 * force)
	_trouble_coup = min(1.0, _trouble_coup + 0.5 * force)
	_sang = min(1.0, _sang + (0.55 if zone == Degats.Zone.TETE else 0.3) * force)
	if direction != Vector3.ZERO:
		var loc := global_basis.inverse() * direction.normalized()
		_coup_tete += Vector2(-loc.z * 4.0 + 2.0, loc.x * 5.0) * force
	else:
		_coup_tete += Vector2(3.0, _rng.randf_range(-3, 3)) * force
	if effet:
		effet.eblouir(0.18)
	_jouer(_son_hasard("impact_chair", 3), -4.0)
	if sante.est_mort():
		_jouer(_son("souffle_coupe"), -2.0, 0.9, "Voix")
		_mourir()
	else:
		_jouer(_son_hasard("douleur", 4), -3.0, _rng.randf_range(0.95, 1.03), "Voix")
		if _rng.randf() < 0.5:
			_jouer(_son("souffle_coupe"), -8.0, 1.0, "Voix")
	blesse.emit(montant, zone)


## Même interface que les ennemis : la zone est déduite de la hauteur du point d'impact.
func recevoir_tir(degats: float, os_ou_zone, point: Vector3, _normale: Vector3, direction: Vector3, _tireur: Node) -> void:
	var zone: int
	if os_ou_zone is int:
		zone = os_ou_zone
	elif os_ou_zone is String and os_ou_zone != "" and os_ou_zone != forme.name:
		zone = Degats.zone_depuis_os(os_ou_zone)
	else:
		var h := point.y - global_position.y
		var oeil: float = lerp(OEIL_DEBOUT, OEIL_ACCROUPI, accroupi_t)
		if h > oeil - 0.2:
			zone = Degats.Zone.TETE
		elif h < oeil * 0.5:
			zone = Degats.Zone.JAMBE
		else:
			zone = Degats.Zone.TORSE
	recevoir_degats(degats * Degats.MULTIPLICATEUR[zone], zone, direction)


func _mourir() -> void:
	est_mort = true
	_rech_t = -1.0
	chargeur_visuel.visible = false
	porte_arme.visible = false
	if corps:
		corps.visible = false
	# la caméra tombe au sol et continue de filmer
	var tw := create_tween().set_parallel(true)
	tw.tween_property(tete, "position", Vector3(0.25, 0.22, -0.3), 0.9).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_property(tete, "rotation", Vector3(deg_to_rad(-8), 0, deg_to_rad(78)), 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	mort.emit()


# ================================================================ points de contrôle

func vers_dict() -> Dictionary:
	return {
		"pos": [global_position.x, global_position.y, global_position.z],
		"lacet": rad_to_deg(lacet),
		"tangage": rad_to_deg(tangage),
		"pv": sante.pv,
		"trousses": sante.trousses,
		"arme": arme.vers_dict(),
	}


func depuis_dict(d: Dictionary) -> void:
	var p: Array = d.get("pos", [])
	if p.size() == 3:
		global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	lacet = deg_to_rad(float(d.get("lacet", 0.0)))
	tangage = deg_to_rad(float(d.get("tangage", 0.0)))
	rotation.y = lacet
	sante.depuis_dict({"pv": d.get("pv", SanteJoueur.PV_MAX), "trousses": d.get("trousses", 1)})
	if d.has("arme"):
		arme.depuis_dict(d["arme"])
	est_mort = false
	velocity = Vector3.ZERO
	_rech_t = -1.0
	_soin_t = -1.0
	_sang = 0.0
	if porte_arme:
		porte_arme.visible = true
	if corps:
		corps.visible = true
	_emettre_munitions()


# ================================================================ image (chaque image)

func _process(delta: float) -> void:
	_sons_corps(delta)
	if est_mort:
		_maj_effet(delta)
		return
	var mal: bool = _reglage("mal_des_transports", false)
	camera.fov = lerp(float(_reglage("fov", 78.0)), float(_reglage("fov", 78.0)) * 0.86, visee_t)

	# tête : hauteur, penché, balancement
	var oeil: float = lerp(OEIL_DEBOUT, OEIL_ACCROUPI, accroupi_t)
	var v := Vector2(velocity.x, velocity.z).length()
	var amp: float = 0.0 if mal else clamp(v / COURSE, 0.0, 1.0)
	var bob := Vector3(sin(_phase_pas) * 0.012, -abs(cos(_phase_pas)) * 0.02 + 0.01, 0) * amp
	tete.position = Vector3(penche, oeil - 0.1 - abs(penche) * 0.12, 0) + bob
	tete.rotation = Vector3(tangage, 0, -penche / PENCHE * deg_to_rad(PENCHE_ROULIS))

	# recul (décalage séparé de l'angle de visée, revient à zéro), coups reçus, saccades
	_recul = _recul.lerp(_recul_cible, 1.0 - exp(-38.0 * delta))
	_recul_cible = _recul_cible.lerp(Vector2.ZERO, 1.0 - exp(-7.5 * delta))
	_coup_tete = _coup_tete.lerp(Vector2.ZERO, 1.0 - exp(-5.0 * delta))
	_secousse = max(0.0, _secousse - delta * 1.6)
	var sac := _secousse + (0.12 * course_t if v > 3.0 else 0.0)
	if mal:
		sac = 0.0
	var sx := (_rng.randf() - 0.5) * sac * 2.2
	var sy := (_rng.randf() - 0.5) * sac * 2.2
	var r_bob := Vector2(sin(_phase_pas * 2.0) * 0.35, sin(_phase_pas) * 0.3) * amp
	recul_n.rotation_degrees = Vector3(_recul.x + _coup_tete.x + sx + r_bob.x, _recul.y + _coup_tete.y + sy + r_bob.y, sx * 0.6 + sin(_phase_pas) * 0.5 * amp)
	_placer_camera()

	_pose_arme(delta, v)
	_maj_glissiere(delta)
	_maj_corps(delta, v)
	if chargeur_arme:
		chargeur_arme.visible = _chargeur_engage_visible()
	_maj_effet(delta)

	_maj_flamme()


## Caméra sur la poitrine : son décalage sous les yeux suit le lacet et le penché mais PAS le tangage
## (elle est fixée au buste, pas à la tête) ; en regardant vers le bas elle avance avec la poitrine qui se
## penche, pour ne jamais entrer dans la veste.
func _placer_camera() -> void:
	var bas: float = max(0.0, -sin(tangage))
	var dec := Vector3(0, 0.1 - CAMERA_SOUS_YEUX + bas * 0.05, -CAMERA_AVANT - bas * 0.1)
	var sans_tangage := Basis(Vector3.BACK, tete.rotation.z)
	recul_n.position = tete.basis.inverse() * (sans_tangage * dec)


## Coup de feu : flamme (variante au hasard) et lumière visibles deux images rendues, la seconde plus faible
## (allumées par _maj_flamme dans _process, juste avant le rendu).
func _allumer_flamme() -> void:
	_flash_images = 2
	var v := _rng.randi() % 4
	sprite_tir.region_rect = Rect2((v % 2) * 256, (v / 2) * 256, 256, 256)
	sprite_tir.rotation.z = _rng.randf() * TAU
	sprite_tir.scale = Vector3.ONE * _rng.randf_range(0.75, 1.2)
	_mat_flamme.uv1_offset = Vector3(0, (_rng.randi() % 4) * 0.25, 0)
	flamme_tir.rotation.z = _rng.randf_range(-0.6, 0.6)
	flamme_tir.scale = Vector3(_rng.randf_range(0.8, 1.15), _rng.randf_range(0.8, 1.15), _rng.randf_range(0.7, 1.2))


func _maj_flamme() -> void:
	if _prechauffage and _flash_images <= 0:
		return
	var on := _flash_images > 0
	lumiere_tir.visible = on
	sprite_tir.visible = on
	flamme_tir.visible = on
	if on:
		var fort := _flash_images == 2
		lumiere_tir.light_energy = 1.8 if fort else 0.6
		sprite_tir.modulate.a = 0.9 if fort else 0.35
		_mat_flamme.albedo_color = Color(1.6, 1.4, 1.2) if fort else Color(0.5, 0.42, 0.35)
		_flash_images -= 1


## Arme tenue bras tendus devant la poitrine (caméra-piéton) : visée = organes de visée sur l'axe.
## Prise à deux mains devant la poitrine : l'arme à ≈ 40 cm de la caméra de poitrine, sous l'axe (on voit
## le dessus de la glissière et les mains), coudes ouverts hors champ, avant-bras qui entrent par les coins bas.
const VISEE := Vector3(0.0, -0.14, -0.38)
const HANCHE := Vector3(0.04, -0.22, -0.34)
## Échelle du pistolet (modèle à 18,8 cm → ≈ 19,7 cm, proche d'un Glock 17 réel de 18,6 à 20,2 cm)
const ECHELLE_ARME := 1.05


## Pose procédurale de l'arme dans le repère de la caméra.
func _pose_arme(delta: float, v: float) -> void:
	var hanche := Transform3D(Basis.from_euler(Vector3(deg_to_rad(2.0), deg_to_rad(1.5), deg_to_rad(-2.0))), HANCHE)
	var visee := Transform3D(Basis.IDENTITY, VISEE)
	var basse := Transform3D(Basis.from_euler(Vector3(deg_to_rad(-38), deg_to_rad(18), deg_to_rad(12))), Vector3(0.09, -0.30, -0.30))
	var t := hanche.interpolate_with(visee, _lisse(visee_t))
	var bas: float = max(course_t, _mur_t, 1.0 if _soin_t >= 0.0 else 0.0)
	t = t.interpolate_with(basse, _lisse(bas))

	# rechargement : arme inclinée et rapprochée
	if _rech_t >= 0.0:
		var u: float = clamp(_rech_t / _rech_duree, 0.0, 1.0)
		var w: float = _lisse(clamp(u / 0.15, 0.0, 1.0)) * _lisse(clamp((1.0 - u) / 0.15, 0.0, 1.0))
		var rech := Transform3D(Basis.from_euler(Vector3(deg_to_rad(18), deg_to_rad(-8), deg_to_rad(28))), Vector3(0.03, -0.075, -0.33))
		if _rech_action == "desenrayer":
			rech = Transform3D(Basis.from_euler(Vector3(deg_to_rad(12), deg_to_rad(-6), deg_to_rad(50))), Vector3(0.03, -0.085, -0.34))
		var secoue := 0.0
		for e in _rech_reperes():
			secoue += exp(-pow((u - e) * 30.0, 2.0))
		t = t.interpolate_with(rech, w)
		t.origin.y += secoue * 0.008
		t.basis = t.basis * Basis(Vector3.RIGHT, deg_to_rad(secoue * 2.0))

	# balancement (inertie de la souris), marche, respiration
	_balance_cible = _balance_cible.limit_length(6.0).lerp(Vector2.ZERO, 1.0 - exp(-9.0 * delta))
	_balance = _balance.lerp(_balance_cible, 1.0 - exp(-14.0 * delta))
	# marche : huit couché synchronisé sur les pas (l'arme suit les épaules), plus ample en courant
	var amp: float = clamp(v / COURSE, 0.0, 1.0) * lerp(1.0, 0.45, visee_t) * (1.0 + course_t * 0.8)
	var ph := _phase_pas
	t.origin += Vector3(sin(ph) * 0.016, -abs(cos(ph)) * 0.016 + 0.006, sin(ph * 2.0) * 0.004) * amp
	t.basis = Basis.from_euler(Vector3(deg_to_rad(-abs(cos(ph)) * 1.6 * amp), deg_to_rad(sin(ph) * 1.4 * amp), deg_to_rad(sin(ph) * 2.2 * amp))) * t.basis
	# respiration : montée-descente lente et léger tangage, plus forts essoufflé ; micro-tremblement des bras tendus
	var resp_a: float = (0.0018 + essoufflement * 0.005) * lerp(1.0, 0.6, visee_t)
	var respire: float = sin(_t * 1.6) * resp_a
	var tremble := Vector2(sin(_t * 7.3) + sin(_t * 11.9) * 0.5, sin(_t * 6.1 + 1.0) + sin(_t * 13.7) * 0.4) * (0.08 + essoufflement * 0.25)
	t.origin += Vector3(0, respire, 0)
	t.basis = Basis.from_euler(Vector3(deg_to_rad(_balance.y * 0.6 + respire * 120.0 + tremble.y), deg_to_rad(_balance.x * 0.6 + tremble.x), deg_to_rad(_balance.x * 0.8))) * t.basis

	# coup de recul : l'arme part en arrière et se relève d'un coup (relèvement), puis revient en
	# douceur avec un léger dépassement (les bras ramènent l'arme sur la cible)
	_coup_arme = max(0.0, _coup_arme - delta * 6.0)
	var c := _coup_arme * _coup_arme
	var retour := sin((1.0 - _coup_arme) * PI) * _coup_arme * 0.6   # petit rebond sous la ligne de visée
	var force: float = lerp(1.0, 0.75, visee_t)
	t.origin += Vector3(_recul_lateral * c * 0.01, 0.018 * c - 0.004 * retour, 0.06 * c) * force
	t.basis = t.basis * Basis.from_euler(Vector3(deg_to_rad((16.0 * c - 2.5 * retour) * force), deg_to_rad(_recul_lateral * 2.0 * c), deg_to_rad(-_recul_lateral * 3.0 * c)))
	porte_arme.transform = t


const COURSE_GLISSIERE := 0.034


## La glissière revient en avant (relâchée par la main gauche ou par l'arrêtoir).
func _liberer_glissiere() -> void:
	glissiere_bloquee = false
	_glissiere_t = 0.03


## Glissière : cycle de tir (recule en 18 ms, revient en 45 ms), bloquée ouverte à vide,
## entrouverte si enrayée, tirée par la main gauche pendant le rechargement.
func _maj_glissiere(delta: float) -> void:
	if glissiere == null:
		return
	_glissiere_t += delta
	var t := _glissiere_t
	var k := 0.0
	if t < 0.018:
		k = t / 0.018
	elif t < 0.03:
		k = 1.0
	elif t < 0.075:
		k = 1.0 - _lisse((t - 0.03) / 0.045)
	if glissiere_bloquee and t >= 0.018:
		k = 0.4 if arme.enrayee else 1.0
	if _rech_t >= 0.0:
		var u: float = clamp(_rech_t / _rech_duree, 0.0, 1.0)
		match _rech_action:
			"recharger_vide":
				if u >= 0.7 and u < 0.8:
					k = 1.0 + 0.06 * sin((u - 0.7) / 0.1 * PI)
			"desenrayer":
				if u >= 0.32 and u < 0.45:
					k = max(k, _lisse((u - 0.32) / 0.1))
	glissiere.transform = _glissiere_repos * Transform3D(Basis.IDENTITY, Vector3(0, 0, COURSE_GLISSIERE * k))


## Chargeur engagé visible dans la poignée ? (caché pendant qu'il est dans la main ou absent)
func _chargeur_engage_visible() -> bool:
	if _rech_t < 0.0:
		return true
	var u: float = clamp(_rech_t / _rech_duree, 0.0, 1.0)
	match _rech_action:
		"recharger_vide":
			return u < 0.1 or u >= 0.6
		"recharger":
			return u >= 0.7
	return true


func _rech_reperes() -> Array:
	match _rech_action:
		"desenrayer":
			return [0.15, 0.45]
		"recharger_vide":
			return [0.1, 0.58, 0.8]
	return [0.14, 0.68]


static func _lisse(x: float) -> float:
	x = clamp(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


# --- mains (repère de l'arme : -Z avant, +Y haut, +X droite ; origine = poignée)
## main droite : X = dos de la main, Y = vers les doigts, Z = pouce
static func main_droite() -> Transform3D:
	var y := Vector3(-0.04, -0.25, -1.0).normalized()
	var x := Vector3(0.98, 0.15, 0.0)
	x = (x - y * x.dot(y)).normalized()
	return Transform3D(Basis(x, y, x.cross(y)), Vector3(0.024, 0.035, 0.088))


## main gauche (soutien) : X = paume, Y = vers les doigts, Z = pouce.
## Paume plaquée sur le flanc gauche de la poignée par-dessus les doigts droits, doigts qui descendent
## en enveloppant l'avant de la poignée sous le pontet, pouce le long de la carcasse pointé vers l'avant.
static func main_gauche() -> Transform3D:
	var p := Vector3(-0.05, 0.03, 0.055)
	var y := Vector3(0.45, -0.6, -0.65).normalized()
	var z := Vector3(0.05, 0.3, -1.0)
	z = (z - y * z.dot(y)).normalized()
	return Transform3D(Basis(y.cross(z), y, z), p)


## Chargeur tenu dans la main gauche (repère de la main : X paume, Y doigts, Z pouce) :
## culot dans la paume, lèvres vers le pouce.
const CHARGEUR_EN_MAIN := Transform3D(Basis(Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)), Vector3(0.03, 0.075, 0.035))


## Cible de la main gauche pendant le rechargement (repère global).
func _main_gauche_rechargement(normale: Transform3D) -> Transform3D:
	var u: float = clamp(_rech_t / _rech_duree, 0.0, 1.0)
	var arme_g := pistolet.global_transform
	# sous la poignée, tenant le chargeur
	# main qui présente le chargeur sous la poignée (déduite de la prise du chargeur dans la main)
	var puits := arme_g * _chargeur_dans_arme(0.05) * CHARGEUR_EN_MAIN.affine_inverse()
	# poche à chargeurs à la ceinture, côté gauche, repère du CORPS (ne suit pas le regard) : la main y
	# descend par l'avant, paume vers le ventre, doigts vers le bas, sans traverser la veste ni la poche
	var corps_t := Transform3D(global_basis, global_position)
	var poche := corps_t * Transform3D(Basis(Vector3(0, 0, 1), Vector3(0, -1, 0), Vector3(1, 0, 0)), Vector3(-0.15, 1.06, -0.2))
	var y_d := Vector3(0.15, -0.75, -0.65).normalized()
	var z_d := Vector3(1, 0, 0)
	z_d = (z_d - y_d * z_d.dot(y_d)).normalized()
	var devant := corps_t * Transform3D(Basis(y_d.cross(z_d), y_d, z_d), Vector3(-0.15, 1.18, -0.36))
	# sur la culasse (dessus de l'arme)
	var y_s := Vector3(0.55, -0.1, -0.83).normalized()
	var x_s := Vector3(0.3, -0.95, 0.0)
	x_s = (x_s - y_s * x_s.dot(y_s)).normalized()
	var culasse := arme_g * Transform3D(Basis(x_s, y_s, x_s.cross(y_s)), Vector3(-0.07, 0.07, 0.07))
	var culasse_tiree := arme_g * Transform3D(Basis(x_s, y_s, x_s.cross(y_s)), Vector3(-0.07, 0.07, 0.12))
	var cles: Array
	match _rech_action:
		"desenrayer":
			cles = [[0.0, normale], [0.1, puits], [0.2, puits], [0.32, culasse], [0.45, culasse_tiree], [0.55, culasse], [0.8, normale]]
		"recharger_vide":
			cles = [[0.0, normale], [0.12, normale], [0.2, devant], [0.3, poche], [0.38, poche], [0.46, devant], [0.54, puits], [0.6, puits], [0.7, culasse], [0.8, culasse_tiree], [0.86, culasse], [1.0, normale]]
		_:
			cles = [[0.0, normale], [0.12, puits], [0.2, devant], [0.3, poche], [0.4, poche], [0.5, devant], [0.6, puits], [0.7, puits], [0.86, normale]]
	return _interp_cles(cles, u)


static func _interp_cles(cles: Array, u: float) -> Transform3D:
	if u <= float(cles[0][0]):
		return cles[0][1]
	for i in range(1, cles.size()):
		if u <= float(cles[i][0]):
			var a: float = cles[i - 1][0]
			var b: float = cles[i][0]
			var k := _lisse((u - a) / max(b - a, 0.0001))
			return (cles[i - 1][1] as Transform3D).interpolate_with(cles[i][1], k)
	return cles[cles.size() - 1][1]


func _maj_corps(delta: float, v: float) -> void:
	if corps == null:
		return
	var arme_g := pistolet.global_transform
	var cible_d := arme_g * main_droite()
	var cible_g := arme_g * main_gauche()
	chargeur_visuel.visible = false
	if _rech_t >= 0.0:
		cible_g = _main_gauche_rechargement(cible_g)
		_chargeur_visuel(arme_g, cible_g)
	elif _soin_t >= 0.0:
		var y_c := Vector3(0.3, -0.5, -0.8).normalized()
		var x_c := Vector3(1, 0, 0)
		x_c = (x_c - y_c * x_c.dot(y_c)).normalized()
		var poitrine := camera.global_transform * Transform3D(Basis(x_c, y_c, x_c.cross(y_c)), Vector3(-0.05, -0.42, -0.12))
		cible_g = cible_g.interpolate_with(poitrine, _lisse(_soin_t / 0.4))
	# index sur la détente seulement pour tirer (doigt tenu, ou juste après un coup), sinon le long de la carcasse
	var veut := 1.0 if (_tenu("tirer") or _depuis_tir < 0.35) and _rech_t < 0.0 and _soin_t < 0.0 else 0.0
	_detente = move_toward(_detente, veut, delta * (14.0 if veut > _detente else 5.0))
	bras.detente = _lisse(_detente)
	bras.cible_d = cible_d
	bras.cible_g = cible_g
	bras.actif_d = true
	bras.actif_g = true
	var pole := Vector3(1.0, -0.7, 0.2)   # coudes ouverts sur les côtés : avant-bras qui convergent, mains visibles
	bras.pole_d = camera.global_transform * pole
	var pole_g := Vector3(-pole.x, pole.y - 0.05, pole.z - 0.05)
	if _rech_t >= 0.0:
		# rechargement : coude gauche bas, l'avant-bras passe sous la caméra au lieu de la masquer
		var ur: float = clamp(_rech_t / _rech_duree, 0.0, 1.0)
		pole_g = pole_g.lerp(Vector3(-0.5, -1.4, -0.1), _lisse(ur / 0.12) * _lisse((1.0 - ur) / 0.12))
	bras.pole_g = camera.global_transform * pole_g
	bras.tangage = tangage
	bras.roulis = asin(clamp(penche / 0.7, -0.9, 0.9))
	# corps recalé à l'horizontale pour que le milieu des épaules soit juste sous et derrière les yeux
	# (quelle que soit l'animation des jambes, le penché ou le buste plié)
	if bras.epaules_valides:
		var voulu := tete.global_position + global_basis * Vector3(0, -0.11, 0.04)   # épaules ≈ 21 cm sous les yeux, 4 cm derrière (caméra 18 cm devant elles)
		var ecart := global_basis.inverse() * (voulu - bras.epaules)
		var pos := corps.position + ecart * (1.0 - exp(-20.0 * delta))
		pos.x = clamp(pos.x, -0.5, 0.5)
		pos.z = clamp(pos.z, -0.5, 0.6)
		pos.y = clamp(pos.y, -0.35, 0.15)  # épaules trop hautes (accroupi) : on descend le corps ; trop basses : on le remonte
		corps.position = pos
	# jambes
	var nom := "Pistol_Idle"
	var vitesse_anim := 1.0
	var avance := (global_basis.inverse() * velocity).z < 0.05
	if accroupi_t > 0.5:
		nom = "Crouch_Fwd" if v > 0.2 else "Crouch_Idle"
		vitesse_anim = max(0.6, v / 1.2) if v > 0.2 else 1.0
	elif v > 3.6:
		nom = "Jog_Fwd"
		vitesse_anim = v / 4.2
	elif v > 0.25:
		nom = "Walk"
		vitesse_anim = max(0.5, v / 1.6)
	if not avance and v > 0.25:
		vitesse_anim = -vitesse_anim
	_jouer_corps(nom, vitesse_anim)


func _jouer_corps(nom: String, vitesse: float) -> void:
	if corps_anim == null or not corps_anim.has_animation(nom):
		return
	if nom != _anim_corps:
		_anim_corps = nom
		corps_anim.play(nom, 0.25)
	corps_anim.speed_scale = vitesse


## Chargeur visible pendant le rechargement : sort de la poignée, suit la main gauche, rentre.
func _chargeur_visuel(arme_g: Transform3D, main_g: Transform3D) -> void:
	var u: float = clamp(_rech_t / _rech_duree, 0.0, 1.0)
	var dans_main := main_g * CHARGEUR_EN_MAIN
	var t: Transform3D
	match _rech_action:
		"desenrayer":
			return
		"recharger_vide":
			if u < 0.1:
				return
			if u < 0.32:
				if u < 0.24:
					return  # l'ancien est tombé, la main va chercher le neuf
				t = dans_main
			elif u < 0.54:
				t = dans_main
			else:
				var k := _lisse((u - 0.54) / 0.06)
				t = dans_main.interpolate_with(arme_g * _chargeur_dans_arme(0.0), k)
				if u > 0.6:
					t = arme_g * _chargeur_dans_arme(0.0)
				if u > 0.66:
					return
		_:
			if u < 0.12:
				t = arme_g * _chargeur_dans_arme(_lisse(u / 0.12) * 0.07)
			elif u < 0.6:
				t = dans_main
			elif u < 0.7:
				t = dans_main.interpolate_with(arme_g * _chargeur_dans_arme(0.0), _lisse((u - 0.6) / 0.08))
			else:
				return
	chargeur_visuel.global_transform = t
	chargeur_visuel.visible = true


func _maj_effet(delta: float) -> void:
	# sang : décroît lentement mais reste selon la gravité ; trouble : pulsation au coup reçu
	var g := sante.gravite()
	_sang = max(_sang - delta * 0.02, g * 0.45 if g > 0.3 else 0.0)
	_trouble_coup = max(0.0, _trouble_coup - delta * 0.6)
	if effet == null:
		return
	var trouble: float = clamp(max(0.0, g - 0.35) * 0.9 + _trouble_coup * 0.5, 0.0, 1.0)
	effet.regler_blessure(_sang, trouble)
	var b := camera.global_basis
	var dq := _base_cam_prec.inverse() * b
	var e := dq.get_euler()
	_base_cam_prec = b
	effet.regler_mouvement(Vector2(-e.y, e.x) / max(delta, 0.001) * 0.05)
