class_name Lampe
extends Node3D
## Source de lumière visible et réutilisable pour les niveaux (direction A, photoréaliste sombre).
## Types :
##   "neon"            rampe fluorescente au plafond (bourdonne ; peut grésiller ou être en panne)
##   "ampoule"         ampoule nue pendue à un fil (chaude, se balance un peu)
##   "securite_verte"  applique grillagée verte (sortie de secours)
##   "securite_rouge"  applique grillagée rouge (alarme)
##   "sodium"          projecteur extérieur au sodium (orange)
## Placement : nœud positionné au point d'accroche (plafond pour neon/ampoule, mur pour
## securite_*, mur ou poteau pour sodium) ; l'axe -Z local pointe hors du mur pour les appliques.
## Panne : "aucune", "gresille" (sauts de temps en temps), "morte" (presque toujours éteinte, amorçages ratés).

const MODELES := "res://assets/decor/models/%s/%s.gltf"

@export var type := "neon"
@export var panne := "aucune"
@export var energie := 1.0            ## multiplicateur d'intensité
@export var portee := 0.0             ## 0 = valeur par défaut du type
@export var ombres := true
@export var son := true
@export var longueur_fil := 0.6       ## ampoule : longueur du fil sous le plafond
@export var graine := 0

var lumiere: Light3D                  ## lumière principale (ombres)
var appoint: OmniLight3D              ## lumière d'appoint autour de la source (sans ombre)
var _emissif: Array[StandardMaterial3D] = []
var _energie_emissive := 1.0
var _base_lumiere := 1.0
var _base_appoint := 0.0
var _bourdon: AudioStreamPlayer3D
var _gresil: Array[AudioStream] = []
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _etat := 1.0                      ## 0 éteinte … 1 allumée
var _prochain_saut := 2.0
var _saut_fin := -1.0
var _pendule: Node3D
var _phase := 0.0
var _volume_bourdon := -26.0


func _ready() -> void:
	_rng.seed = graine if graine != 0 else hash(str(global_position))
	_prochain_saut = _rng.randf_range(0.5, 4.0)
	_phase = _rng.randf() * TAU
	match type:
		"neon": _neon()
		"ampoule": _ampoule()
		"securite_verte": _securite(Color(0.15, 1.0, 0.35))
		"securite_rouge": _securite(Color(1.0, 0.08, 0.04))
		"sodium": _sodium()
		_: push_warning("Lampe : type inconnu " + type)
	if lumiere:
		_base_lumiere = lumiere.light_energy
	if appoint:
		_base_appoint = appoint.light_energy
	if panne == "morte":
		_etat = 0.0
	_appliquer(_etat)


# ---------------------------------------------------------------- construction

func _modele(nom: String, enfant := "") -> Node3D:
	var n: Node3D = (load(MODELES % [nom, nom]) as PackedScene).instantiate()
	if enfant != "":
		for c in n.get_children():
			if c is Node3D and c.name != enfant:
				c.free()
			elif c is Node3D:
				(c as Node3D).position = Vector3.ZERO
	add_child(n)
	return n


## Remplace les surfaces dont le matériau contient `motif` (ex. "glass") par un matériau émissif.
func _rendre_emissif(racine: Node, motif: String, couleur: Color, energie_em: float, transparent := false) -> void:
	for mi in racine.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if motif == "*" else m.cast_shadow
		for s in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(s)
			if motif != "*" and (mat == null or not String(mat.resource_name).contains(motif)):
				continue
			var e := StandardMaterial3D.new()
			e.albedo_color = couleur.lerp(Color.WHITE, 0.25)
			e.emission_enabled = true
			e.emission = couleur
			e.emission_energy_multiplier = energie_em
			e.roughness = 0.3
			if transparent:
				e.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				e.albedo_color.a = 0.85
			m.set_surface_override_material(s, e)
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_emissif.append(e)
	_energie_emissive = energie_em


func _spot(couleur: Color, energie_l: float, angle: float, port: float, fog := 1.0) -> SpotLight3D:
	var s := SpotLight3D.new()
	s.light_color = couleur
	s.light_energy = energie_l * energie
	s.spot_angle = angle
	s.spot_angle_attenuation = 1.4
	s.spot_range = portee if portee > 0.0 else port
	s.spot_attenuation = 1.2
	s.shadow_enabled = ombres
	s.shadow_blur = 1.2
	s.shadow_normal_bias = 0.6
	s.shadow_bias = 0.02
	s.light_volumetric_fog_energy = fog
	s.light_size = 0.15
	add_child(s)
	return s


func _omni(couleur: Color, energie_l: float, port: float, ombre := false, fog := 0.5) -> OmniLight3D:
	var o := OmniLight3D.new()
	o.light_color = couleur
	o.light_energy = energie_l * energie
	o.omni_range = port
	o.omni_attenuation = 1.6
	o.shadow_enabled = ombre and ombres
	o.shadow_blur = 1.0
	o.shadow_normal_bias = 0.8
	o.light_volumetric_fog_energy = fog
	o.light_size = 0.05
	add_child(o)
	return o


func _neon() -> void:
	var c := Color(0.82, 1.0, 0.86)      # tube « blanc froid » usé : légèrement vert
	var m := _modele("mounted_fluorescent_lights", "mounted_fluorescent_lights_a")
	m.rotation_degrees.y = 90
	_rendre_emissif(m, "glass", c, 9.0)
	lumiere = _spot(c, 3.2, 80.0, 8.0, 0.8)
	lumiere.position = Vector3(0, -0.06, 0)
	lumiere.rotation_degrees = Vector3(-90, 0, 0)
	appoint = _omni(c, 0.35, 3.2, false, 0.3)
	appoint.position = Vector3(0, -0.25, 0)
	if son:
		_volume_bourdon = -24.0
		_bourdon_demarrer("neon_bourdon", 1.0)


func _ampoule() -> void:
	var c := Color(1.0, 0.62, 0.32)      # tungstène ~2700 K
	_pendule = Node3D.new()
	add_child(_pendule)
	# fil
	var fil := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = 0.004
	cy.bottom_radius = 0.004
	cy.height = longueur_fil
	cy.radial_segments = 6
	fil.mesh = cy
	var mf := StandardMaterial3D.new()
	mf.albedo_color = Color(0.03, 0.03, 0.03)
	mf.roughness = 0.6
	fil.material_override = mf
	fil.position.y = -longueur_fil / 2.0
	_pendule.add_child(fil)
	var douille: Node3D = (load(MODELES % ["pull_chain_light_socket", "pull_chain_light_socket"]) as PackedScene).instantiate()
	douille.position.y = -longueur_fil
	_pendule.add_child(douille)
	var amp: Node3D = (load(MODELES % ["lightbulb_01", "lightbulb_01"]) as PackedScene).instantiate()
	amp.rotation_degrees.x = 180
	amp.position.y = -longueur_fil - 0.045
	_pendule.add_child(amp)
	_rendre_emissif(amp, "glass", c, 60.0)
	var o := OmniLight3D.new()
	o.light_color = c
	o.light_energy = 1.6 * energie
	o.omni_range = portee if portee > 0.0 else 6.5
	o.omni_attenuation = 1.8
	o.shadow_enabled = ombres
	o.shadow_blur = 0.8
	o.shadow_normal_bias = 0.8
	o.light_volumetric_fog_energy = 1.2
	o.light_size = 0.03
	o.position.y = -longueur_fil - 0.09
	_pendule.add_child(o)
	lumiere = o
	if son:
		_volume_bourdon = -38.0
		_bourdon_demarrer("neon_bourdon", 2.0)


func _securite(c: Color) -> void:
	var m := _modele("industrial_caged_sconce", "industrial_caged_sconce_a")
	# l'applique est modélisée le long de +Z (base contre le mur)
	m.rotation_degrees.y = 180
	_rendre_emissif(m, "glass", c, 4.0)
	# ampoule colorée au centre de la cage
	var b := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.035
	sm.height = 0.09
	b.mesh = sm
	b.position = Vector3(0, 0.0, -0.13)
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var e := StandardMaterial3D.new()
	e.albedo_color = c
	e.emission_enabled = true
	e.emission = c
	e.emission_energy_multiplier = 6.0
	b.material_override = e
	_emissif.append(e)
	_energie_emissive = 6.0
	add_child(b)
	lumiere = _omni(c, 0.6 if c.r > c.g else 0.35, portee if portee > 0.0 else 3.5, true, 0.5)
	lumiere.position = Vector3(0, 0.0, -0.2)


func _sodium() -> void:
	var c := Color(1.0, 0.55, 0.18)      # sodium haute pression
	var m := _modele("security_light")
	m.rotation_degrees.x = 0
	_rendre_emissif(m, "bulb", c, 30.0)
	_rendre_emissif(m, "glass", c, 6.0, true)
	lumiere = _spot(c, 6.0, 55.0, 14.0, 2.5)
	lumiere.position = Vector3(0, -0.3, -0.12)
	lumiere.rotation_degrees = Vector3(-60, 0, 0)
	appoint = _omni(c, 0.4, 2.0, false, 0.6)
	appoint.position = Vector3(0, -0.3, -0.2)
	if son:
		_volume_bourdon = -34.0
		_bourdon_demarrer("neon_bourdon", 0.5)


func _bourdon_demarrer(nom: String, hauteur: float) -> void:
	var s0 := load("res://assets/sons/%s.wav" % nom) as AudioStreamWAV
	if s0 == null:
		return
	var s: AudioStreamWAV = s0.duplicate()
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = int(s.get_length() * s.mix_rate)
	_bourdon = AudioStreamPlayer3D.new()
	_bourdon.stream = s
	_bourdon.pitch_scale = hauteur
	_bourdon.volume_db = _volume_bourdon
	_bourdon.unit_size = 1.5
	_bourdon.max_distance = 9.0
	_bourdon.bus = "Ambiance" if AudioServer.get_bus_index("Ambiance") >= 0 else "Master"
	_bourdon.autoplay = true
	add_child(_bourdon)
	for k in 3:
		var g := load("res://assets/sons/neon_gresil_%d.wav" % (k + 1))
		if g:
			_gresil.append(g)


# ---------------------------------------------------------------- animation

func _process(delta: float) -> void:
	_t += delta
	if lumiere == null:
		return
	var e := 1.0
	match panne:
		"gresille":
			if _t >= _prochain_saut:
				_saut_fin = _t + _rng.randf_range(0.15, 0.7)
				_prochain_saut = _t + _rng.randf_range(1.5, 6.0)
				_gresiller()
			if _t < _saut_fin:
				# scintillement rapide : le tube décroche et se rallume (≈ 50-120 Hz visible en battements)
				var f := sin(_t * 61.0) * sin(_t * 23.0 + 1.3)
				e = 0.08 if f > 0.1 else (0.5 if f > -0.4 else 1.0)
		"morte":
			e = 0.0
			if _t >= _prochain_saut:
				_saut_fin = _t + _rng.randf_range(0.05, 0.3)
				_prochain_saut = _t + _rng.randf_range(0.8, 4.0)
				_gresiller()
			if _t < _saut_fin:
				e = 0.9 if fmod(_t * 37.0, 1.0) > 0.45 else 0.15
		_:
			# léger battement du tube (à peine perceptible)
			e = 1.0 - 0.025 * (0.5 + 0.5 * sin(_t * 7.0 + _phase))
	_appliquer(e)
	if _pendule:
		var a := 2.2 * sin(_t * 1.9 + _phase) + 0.8 * sin(_t * 3.3)
		_pendule.rotation_degrees = Vector3(a, 0, a * 0.6)


func _appliquer(e: float) -> void:
	_etat = e
	if lumiere:
		lumiere.light_energy = _base_lumiere * e
		lumiere.visible = e > 0.01
	if appoint:
		appoint.light_energy = _base_appoint * e
		appoint.visible = e > 0.01
	for m in _emissif:
		m.emission_energy_multiplier = _energie_emissive * max(e, 0.004)
	if _bourdon:
		_bourdon.volume_db = _volume_bourdon + (0.0 if e > 0.3 else -12.0)


func _gresiller() -> void:
	if _gresil.is_empty() or not is_inside_tree():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = _gresil[_rng.randi() % _gresil.size()]
	p.volume_db = -14.0
	p.unit_size = 2.0
	p.max_distance = 14.0
	p.pitch_scale = _rng.randf_range(0.9, 1.1)
	p.bus = _bourdon.bus if _bourdon else "Master"
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
