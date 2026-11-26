class_name RenduNiveau
extends Node3D
## Rendu d'un niveau intérieur (direction A) : environnement, exposition automatique qui « pompe »
## comme une caméra-piéton, éclairage global VoxelGI (cuit au chargement), poussière en suspension,
## et préréglages de qualité liés à Reglages « qualite » (0 Bas, 1 Moyen, 2 Élevé).
##
## Utilisation : construire la géométrie statique sous un nœud `geometrie`, puis
##   var r := RenduNiveau.new(); r.zone = AABB(...); add_child(r); r.cuire_gi(geometrie)
## La zone (AABB monde) délimite le VoxelGI et la poussière.
##
## Pourquoi VoxelGI et pas LightmapGI : Godot 4.7 n'expose aucune méthode pour précalculer les
## lightmaps hors de l'éditeur (pas de LightmapGI.bake() en script), et piloter l'interface de
## l'éditeur prendrait le focus. VoxelGI se cuit à l'exécution (VoxelGI.bake()), suit les lumières
## dynamiques (néons qui clignotent, lampe torche, éclairs de tir) et convient aux couloirs.

@export var zone := AABB(Vector3(-2, 0, -18), Vector3(4, 3.2, 20))
@export var ambiance := Color(0.55, 0.6, 0.62)   ## lumière ambiante résiduelle (très faible)
@export var ambiance_energie := 0.02
@export var brouillard := 0.025                  ## densité du brouillard volumétrique
@export var brouillard_couleur := Color(0.62, 0.64, 0.62)
@export var poussiere_quantite := 1400
## Lisibilité dans le noir (issue #4) : comme le gain d'une caméra-piéton qui monte dans l'ombre,
## sans relever les noirs (l'ambiance reste presque nulle) ; les silhouettes se lisent sur les
## fonds éclairés (contre-jours) et dans la brume autour des sources.
@export var gain_max := 1600.0                    ## sensibilité maximale de l'exposition auto
@export var gi_energie := 1.35                    ## rebond VoxelGI (remplit sans déboucher les noirs)

var environnement: Environment
var monde: WorldEnvironment
var attributs: CameraAttributesPractical
var gi: VoxelGI
var poussiere: GPUParticles3D
var _t := 0.0
var _echelle_expo := 0.28


func _ready() -> void:
	monde = WorldEnvironment.new()
	environnement = Environment.new()
	var e := environnement
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color.BLACK
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = ambiance
	e.ambient_light_energy = ambiance_energie
	e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	# AgX : hautes lumières qui « brûlent » vers le blanc comme un petit capteur
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_white = 4.0
	e.tonemap_exposure = 1.0
	# occlusion ambiante serrée (ombres de contact au pied des murs et des objets)
	e.ssao_enabled = true
	e.ssao_radius = 0.6
	e.ssao_intensity = 3.0
	e.ssao_power = 1.6
	e.ssao_detail = 1.2
	e.ssao_light_affect = 0.35
	e.ssao_ao_channel_affect = 0.5
	e.ssil_enabled = true
	e.ssil_radius = 4.0
	e.ssil_intensity = 1.4
	e.ssil_normal_rejection = 1.0
	# halos autour des sources (le shader caméra ajoute les reflets d'objectif)
	e.glow_enabled = true
	e.glow_normalized = false
	e.glow_intensity = 0.6
	e.glow_strength = 1.0
	e.glow_bloom = 0.02
	e.glow_hdr_threshold = 1.3
	e.glow_hdr_scale = 2.0
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	for i in 7:
		e.set_glow_level(i, [0.0, 0.3, 1.0, 0.7, 0.6, 0.3, 0.0][i])
	e.volumetric_fog_enabled = true
	e.volumetric_fog_density = brouillard
	e.volumetric_fog_albedo = brouillard_couleur
	e.volumetric_fog_anisotropy = 0.55
	e.volumetric_fog_length = 32.0
	e.volumetric_fog_detail_spread = 1.6
	e.volumetric_fog_gi_inject = 0.6
	e.volumetric_fog_ambient_inject = 0.0
	e.volumetric_fog_temporal_reprojection_enabled = true
	e.volumetric_fog_temporal_reprojection_amount = 0.85
	e.adjustment_enabled = false
	monde.environment = e
	# exposition automatique lente : s'assombrit près des lampes, remonte dans le noir
	attributs = CameraAttributesPractical.new()
	attributs.auto_exposure_enabled = true
	attributs.auto_exposure_scale = _echelle_expo
	attributs.auto_exposure_speed = 1.1
	attributs.auto_exposure_min_sensitivity = 40.0
	attributs.auto_exposure_max_sensitivity = gain_max
	attributs.dof_blur_far_enabled = false
	attributs.dof_blur_near_enabled = false
	monde.camera_attributes = attributs
	add_child(monde)
	_poussiere()
	if has_node("/root/Reglages"):
		get_node("/root/Reglages").connect("change", appliquer_qualite)
	appliquer_qualite()


func _reglage(cle: String, defaut):
	if has_node("/root/Reglages"):
		var v = get_node("/root/Reglages").call("get_v", cle)
		return defaut if v == null else v
	return defaut


## Cuit l'éclairage global sur la géométrie statique de `racine` (meshes en GI statique).
## À appeler après la construction du décor et des lampes, AVANT d'ajouter joueur et ennemis.
func cuire_gi(racine: Node) -> void:
	if int(_reglage("qualite", 2)) == 0:
		return
	gi = VoxelGI.new()
	gi.name = "VoxelGI"
	gi.size = zone.size + Vector3(0.4, 0.4, 0.4)
	gi.subdiv = VoxelGI.SUBDIV_128
	racine.add_child(gi)
	gi.global_position = zone.get_center()
	var d := VoxelGIData.new()
	d.energy = gi_energie
	d.propagation = 0.75
	d.bias = 1.5
	d.normal_bias = 0.0
	d.dynamic_range = 4.0
	d.interior = true
	d.use_two_bounces = true
	gi.data = d
	var t0 := Time.get_ticks_msec()
	gi.bake(racine)
	gi.data.energy = d.energy
	gi.data.interior = true
	gi.data.use_two_bounces = true
	gi.data.propagation = d.propagation
	print("VoxelGI cuit en %d ms" % (Time.get_ticks_msec() - t0))


## Brume plus dense dans une zone (fond de couloir, porte, sous un projecteur) : la lumière s'y
## diffuse et découpe les silhouettes qui passent devant, comme la fumée et la poussière réelles.
func brume(boite: AABB, densite := 0.06, couleur := Color(0.7, 0.7, 0.68)) -> FogVolume:
	var f := FogVolume.new()
	f.size = boite.size
	f.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	var m := FogMaterial.new()
	m.density = densite
	m.albedo = couleur
	m.edge_fade = 0.6
	var bruit := FastNoiseLite.new()
	bruit.frequency = 0.25
	var tex := NoiseTexture3D.new()
	tex.noise = bruit
	tex.width = 32
	tex.height = 32
	tex.depth = 32
	m.density_texture = tex
	f.material = m
	add_child(f)
	f.global_position = boite.get_center()
	return f


## Lumière de rebond sans ombre (sol ou mur éclairé qui renvoie un peu de lumière) : à placer
## dans les zones de passage trop noires, très faible, pour que les visages et les épaules
## gardent un modelé sans éclairer les murs voisins.
func rebond(pos: Vector3, couleur: Color, energie := 0.12, portee := 3.0) -> OmniLight3D:
	var o := OmniLight3D.new()
	o.light_color = couleur
	o.light_energy = energie
	o.omni_range = portee
	o.omni_attenuation = 2.0
	o.shadow_enabled = false
	o.light_specular = 0.2
	o.light_volumetric_fog_energy = 0.0
	add_child(o)
	o.global_position = pos
	return o


func _poussiere() -> void:
	# fines particules en suspension : invisibles dans le noir, scintillent dans les faisceaux
	poussiere = GPUParticles3D.new()
	poussiere.name = "Poussiere"
	poussiere.amount = poussiere_quantite
	poussiere.lifetime = 14.0
	poussiere.preprocess = 14.0
	poussiere.explosiveness = 0.0
	poussiere.visibility_aabb = AABB(-zone.size / 2.0, zone.size)
	poussiere.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	poussiere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = zone.size / 2.0
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.03
	pm.gravity = Vector3(0, -0.004, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.4
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_noise_speed = Vector3(0.02, 0.01, 0.02)
	pm.turbulence_influence_min = 0.02
	pm.turbulence_influence_max = 0.06
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	poussiere.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.0025, 0.0025)
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.8, 0.78, 0.72, 0.45)
	m.roughness = 1.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.disable_receive_shadows = false
	m.proximity_fade_enabled = true
	m.proximity_fade_distance = 0.3
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = 6.0
	m.distance_fade_max_distance = 0.4
	q.material = m
	poussiere.draw_pass_1 = q
	add_child(poussiere)
	poussiere.global_position = zone.get_center()


## Préréglages : 0 Bas (sans GI, sans SSIL, brouillard grossier), 1 Moyen, 2 Élevé.
func appliquer_qualite() -> void:
	var q := int(_reglage("qualite", 2))
	var e := environnement
	e.ssil_enabled = q >= 2
	e.ssao_enabled = q >= 1
	e.volumetric_fog_enabled = true
	e.sdfgi_enabled = false
	RenderingServer.environment_set_ssao_quality(
		[RenderingServer.ENV_SSAO_QUALITY_VERY_LOW, RenderingServer.ENV_SSAO_QUALITY_LOW, RenderingServer.ENV_SSAO_QUALITY_MEDIUM][q],
		true, 0.5, 2, 50.0, 300.0)
	RenderingServer.environment_set_ssil_quality(
		[RenderingServer.ENV_SSIL_QUALITY_VERY_LOW, RenderingServer.ENV_SSIL_QUALITY_LOW, RenderingServer.ENV_SSIL_QUALITY_LOW][q],
		true, 0.5, 4, 50.0, 300.0)
	RenderingServer.environment_set_volumetric_fog_volume_size([64, 96, 128][q], [48, 64, 96][q])
	RenderingServer.environment_set_volumetric_fog_filter_active(q >= 1)
	RenderingServer.voxel_gi_set_quality(RenderingServer.VOXEL_GI_QUALITY_LOW)
	if gi:
		gi.visible = q >= 1
	if poussiere:
		poussiere.amount = [poussiere_quantite / 3, poussiere_quantite / 2, poussiere_quantite][q]
	var vp := get_viewport()
	if vp:
		vp.positional_shadow_atlas_size = [2048, 4096, 4096][q]
		vp.positional_shadow_atlas_16_bits = true
	RenderingServer.positional_soft_shadow_filter_set_quality(
		[RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM][q])


func _process(delta: float) -> void:
	_t += delta
	# la cellule d'exposition d'une caméra bon marché « cherche » en permanence (petite dérive lente)
	if attributs:
		attributs.auto_exposure_scale = _echelle_expo * (1.0 + 0.06 * sin(_t * 0.7) + 0.04 * sin(_t * 1.9 + 1.0))
