extends Node3D
## Aperçu de la phase 0 : un couloir du niveau 1 (aéroport de fret, de nuit) et un garde du cartel,
## vus à travers l'effet caméra-piéton. Deux directions artistiques : A (photoréaliste sombre)
## et B (réaliste stylisé, contrasté).
##
## Arguments (après « -- ») : <A|B> <photo|video|blesse> [fichier de sortie]
##   photo  : une image PNG puis quitte
##   video  : à lancer avec --write-movie x.avi --fixed-fps 30 ; joue la scène puis quitte
##   blesse : image avec sang sur l'objectif et vision trouble

const PH := "res://assets/decor/"
const VIDEO_LEN := 6.0

var style := "A"
var mode := "photo"
var out_path := ""
var t := 0.0
var cam: Camera3D
var rig: Node3D
var post: ShaderMaterial
var guard: Node3D
var guard_anim: AnimationPlayer
var marc_anim: AnimationPlayer
var muzzle_light: OmniLight3D
var muzzle_sprite: Sprite3D
var flicker: Array = []
var grips: Array = []
var frames := 0
var curl_axis := Vector3(0, 0, 1)
var shots := [2.55, 2.95]
var shot_done := {}
var guard_state := "idle"
var recoil := 0.0
var shake := 0.0
var last_cam_basis: Basis
var blood_ps: GPUParticles3D
var wall_blood: Decal
var floor_blood: Decal
var pool_scale := 0.0


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0: style = a[0]
	if a.size() > 1: mode = a[1]
	if a.size() > 2: out_path = a[2]
	if a.size() > 3: curl_axis = str_to_var(a[3])
	_build_environment()
	_build_corridor()
	_build_props()
	_build_lights()
	_build_guard()
	_build_player()
	_build_post()
	_build_blood()
	last_cam_basis = cam.global_transform.basis


# ---------------------------------------------------------------- matériaux

func _mat(tex: String, scale := 0.5, tint := Color.WHITE) -> ORMMaterial3D:
	var m := ORMMaterial3D.new()
	var base := PH + "tex/%s/%s_" % [tex, tex]
	m.albedo_texture = load(base + "diff_2k.jpg")
	m.albedo_color = tint
	m.orm_texture = load(base + "arm_2k.jpg")
	m.normal_enabled = true
	m.normal_texture = load(base + "nor_gl_2k.jpg")
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _box(size: Vector3, pos: Vector3, m: Material, parent: Node = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	sb.add_child(cs)
	mi.add_child(sb)
	return mi


# ---------------------------------------------------------------- environnement

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color.BLACK
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.55, 0.6) if style == "A" else Color(0.35, 0.45, 0.55)
	e.ambient_light_energy = 0.035
	e.tonemap_mode = Environment.TONE_MAPPER_AGX if style == "A" else Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.0 if style == "A" else 1.15
	e.tonemap_white = 6.0
	e.ssao_enabled = true
	e.ssao_radius = 1.2
	e.ssao_intensity = 2.5
	e.ssil_enabled = true
	e.ssil_intensity = 1.2
	e.ssr_enabled = true
	e.ssr_max_steps = 64
	e.glow_enabled = true
	e.glow_intensity = 0.6 if style == "A" else 1.0
	e.glow_bloom = 0.04 if style == "A" else 0.1
	e.glow_hdr_threshold = 1.2 if style == "A" else 0.9
	e.volumetric_fog_enabled = true
	e.volumetric_fog_density = 0.035 if style == "A" else 0.05
	e.volumetric_fog_albedo = Color(0.85, 0.85, 0.85)
	e.volumetric_fog_anisotropy = 0.6
	e.volumetric_fog_length = 40.0
	e.volumetric_fog_gi_inject = 0.5
	if style == "B":
		e.adjustment_enabled = true
		e.adjustment_contrast = 1.12
		e.adjustment_saturation = 1.1
	we.environment = e
	add_child(we)


# ---------------------------------------------------------------- couloir

const W := 2.7      # largeur
const H := 3.0      # hauteur
const L0 := 2.0     # début (derrière le joueur)
const L1 := -24.0   # fond
const DOOR_Z := -12.4   # ouverture latérale à droite


func _build_corridor() -> void:
	var floor_m := _mat("hangar_concrete_floor", 0.35)
	var wall_m := _mat("concrete_wall_008", 0.4, Color(0.8, 0.8, 0.78))
	var dado_m := _mat("painted_concrete", 0.5, Color(0.42, 0.5, 0.46) if style == "A" else Color(0.3, 0.42, 0.42))
	var ceil_m := _mat("concrete_panels", 0.4, Color(0.6, 0.6, 0.6))
	var len := L0 - L1
	var cz := (L0 + L1) / 2.0
	_box(Vector3(W + 0.4, 0.2, len), Vector3(0, -0.1, cz), floor_m)
	_box(Vector3(W + 0.4, 0.2, len), Vector3(0, H + 0.1, cz), ceil_m)
	# mur gauche (plein)
	_box(Vector3(0.2, H, len), Vector3(-W / 2 - 0.1, H / 2, cz), wall_m)
	_box(Vector3(0.03, 1.15, len), Vector3(-W / 2 + 0.015, 0.575, cz), dado_m)
	# mur droit, coupé par une porte ouverte
	var dz0 := DOOR_Z + 0.6
	var dz1 := DOOR_Z - 0.6
	_box(Vector3(0.2, H, L0 - dz0), Vector3(W / 2 + 0.1, H / 2, (L0 + dz0) / 2), wall_m)
	_box(Vector3(0.2, H, dz1 - L1), Vector3(W / 2 + 0.1, H / 2, (dz1 + L1) / 2), wall_m)
	_box(Vector3(0.2, H - 2.15, 1.2), Vector3(W / 2 + 0.1, 2.15 + (H - 2.15) / 2, DOOR_Z), wall_m)
	_box(Vector3(0.03, 1.15, L0 - dz0), Vector3(W / 2 - 0.015, 0.575, (L0 + dz0) / 2), dado_m)
	_box(Vector3(0.03, 1.15, dz1 - L1), Vector3(W / 2 - 0.015, 0.575, (dz1 + L1) / 2), dado_m)
	# petite pièce derrière la porte (bureau sombre)
	_box(Vector3(3.0, H, 0.2), Vector3(W / 2 + 1.6, H / 2, DOOR_Z + 1.6), wall_m)
	_box(Vector3(3.0, H, 0.2), Vector3(W / 2 + 1.6, H / 2, DOOR_Z - 1.6), wall_m)
	_box(Vector3(0.2, H, 3.4), Vector3(W / 2 + 3.1, H / 2, DOOR_Z), wall_m)
	# fond et arrière
	_box(Vector3(W, H, 0.2), Vector3(0, H / 2, L1 - 0.1), wall_m)
	_box(Vector3(W, H, 0.2), Vector3(0, H / 2, L0 + 0.1), wall_m)
	# plinthes métal
	var metal := _mat("rusty_painted_metal", 1.0, Color(0.25, 0.25, 0.25))
	_box(Vector3(0.04, 0.12, len), Vector3(-W / 2 + 0.03, 0.06, cz), metal)
	# tag du cartel sur le mur gauche, près du garde
	var tag := Decal.new()
	tag.texture_albedo = load("res://assets/fx/tag_cercle.png")
	tag.size = Vector3(1.3, 0.3, 1.3)
	tag.position = Vector3(-W / 2 + 0.05, 1.75, -10.2)
	tag.rotation_degrees = Vector3(0, 0, -90)
	tag.albedo_mix = 0.92
	tag.modulate = Color(1, 1, 1, 0.9)
	add_child(tag)


# ---------------------------------------------------------------- objets Poly Haven (CC0)

func _prop(name: String, pos: Vector3, rot_y := 0.0, child := "", scale := 1.0) -> Node3D:
	var ps: PackedScene = load(PH + "models/%s/%s.gltf" % [name, name])
	var n: Node3D = ps.instantiate()
	add_child(n)
	if child != "":
		for c in n.get_children():
			if c is Node3D:
				if c.name == child:
					(c as Node3D).position = Vector3.ZERO
				else:
					c.queue_free()
	n.position = pos
	n.rotation_degrees.y = rot_y
	n.scale = Vector3.ONE * scale
	return n


func _build_props() -> void:
	var shelf := _prop("steel_frame_shelves_01", Vector3(-W / 2 + 0.3, 0, -4.2), 90)
	shelf.scale = Vector3.ONE * (2.0 / 21.405)   # le modèle source est 10x trop grand
	_prop("cardboard_box_01", Vector3(-W / 2 + 0.35, 0.0, -2.6), 12)
	_prop("cardboard_box_01", Vector3(-W / 2 + 0.4, 0.42, -2.55), -20, "", 0.85)
	_prop("wooden_military_crate", Vector3(W / 2 - 0.45, 0, -6.6), 80)
	_prop("wooden_military_crate", Vector3(W / 2 - 0.45, 0, -7.45), 95)
	_prop("plastic_crate_01", Vector3(W / 2 - 0.4, 0.62, -7.0), 30)
	_prop("korean_fire_extinguisher_01", Vector3(W / 2 - 0.15, 0, -2.0), -90)
	_prop("metal_trash_can", Vector3(-W / 2 + 0.3, 0, -11.2), 0)
	_prop("hand_truck", Vector3(-W / 2 + 0.35, 0, -15.5), 70)
	_prop("cardboard_box_01", Vector3(W / 2 - 0.4, 0, -17.0), 40)
	_prop("cardboard_box_01", Vector3(W / 2 - 0.35, 0, -17.6), 5)
	_prop("fire_alarm", Vector3(W / 2 - 0.02, 1.5, -5.4), -90)
	_prop("security_camera_01", Vector3(-W / 2 + 0.1, H - 0.15, -1.0), 150)
	var door := _prop("rollershutter_door", Vector3(0, 0, L1 + 0.05), 0, "rollershutter_door_graffiti")
	door.scale = Vector3((W - 0.1) / 1.08, H / 2.4, 1.0)
	var pipes := _prop("modular_industrial_pipes_01", Vector3(-W / 2 + 0.25, H - 0.3, -10), 0, "modular_industrial_pipes_01_pipe01")
	pipes.rotation_degrees = Vector3(90, 0, 0)
	pipes.scale = Vector3(1, 26.0 / 1.95, 1)


func _aabb(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _fit_width(n: Node3D, w: float) -> void:
	var b := _aabb(n)
	if b.size.x > 0.01:
		n.scale *= w / b.size.x


func _fit_length(n: Node3D, l: float) -> void:
	var b := _aabb(n)
	var cur: float = max(b.size.x, b.size.z)
	if cur > 0.01:
		n.scale.x *= l / cur


# ---------------------------------------------------------------- éclairage

func _build_lights() -> void:
	var zs := [-1.5, -5.5, -9.5, -13.5, -17.5, -21.5]
	for i in zs.size():
		var z: float = zs[i]
		var on := i != 3          # une rampe grillée : zone d'ombre
		var col := Color(0.86, 0.95, 1.0) if style == "A" else Color(0.82, 1.0, 0.95)
		if style == "B" and i == 2:
			col = Color(1.0, 0.8, 0.6)
		_prop("mounted_fluorescent_lights", Vector3(0, H - 0.02, z), 90, "mounted_fluorescent_lights_a")
		if not on:
			continue
		var s := SpotLight3D.new()
		s.position = Vector3(0, H - 0.12, z)
		s.rotation_degrees = Vector3(-90, 0, 0)
		s.spot_angle = 78
		s.spot_attenuation = 0.8
		s.spot_range = 7.5
		s.light_energy = 2.2 if style == "A" else 2.8
		s.light_color = col
		s.shadow_enabled = true
		s.shadow_blur = 1.5
		s.light_volumetric_fog_energy = 0.6
		add_child(s)
		var glow := OmniLight3D.new()     # rebond sur le plafond
		glow.position = Vector3(0, H - 0.3, z)
		glow.omni_range = 3.0
		glow.light_energy = 0.25
		glow.light_color = col
		add_child(glow)
		if i == 4:
			flicker.append(s)
			flicker.append(glow)
	# lumière extérieure qui passe sous le rideau métallique du fond (projecteur au sodium)
	var ext := SpotLight3D.new()
	ext.position = Vector3(0, 0.3, L1 + 0.3)
	ext.rotation_degrees = Vector3(-8, 0, 0)
	ext.spot_angle = 60
	ext.spot_range = 9
	ext.light_energy = 3.0
	ext.light_color = Color(1.0, 0.62, 0.3) if style == "B" else Color(1.0, 0.78, 0.55)
	ext.light_volumetric_fog_energy = 2.0
	add_child(ext)
	# bureau sur le côté : écran allumé (lumière froide et faible)
	var office := OmniLight3D.new()
	office.position = Vector3(W / 2 + 1.8, 1.0, DOOR_Z - 0.6)
	office.omni_range = 3.5
	office.light_energy = 0.6
	office.light_color = Color(0.5, 0.7, 1.0) if style == "A" else Color(0.3, 0.55, 1.0)
	office.shadow_enabled = true
	add_child(office)
	if style == "B":
		# panneau de sortie rouge au-dessus de la porte du fond
		var sign := _box(Vector3(0.45, 0.16, 0.05), Vector3(0, H - 0.35, L1 + 0.05), _emissive(Color(1, 0.05, 0.04), 6.0))
		var red := OmniLight3D.new()
		red.position = Vector3(0, H - 0.45, L1 + 0.5)
		red.light_color = Color(1, 0.1, 0.08)
		red.light_energy = 1.2
		red.omni_range = 4.0
		add_child(red)
		sign.name = "sortie"


func _emissive(c: Color, e: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	return m


# ---------------------------------------------------------------- personnages

func _find_anim(n: Node) -> AnimationPlayer:
	return n.find_children("*", "AnimationPlayer", true, false)[0]


func _attach_pistol(model: Node, offset: Transform3D) -> Node3D:
	var skel: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var fc := FingerCurl.new()
	fc.axis = curl_axis
	skel.add_child(fc)
	var ba := BoneAttachment3D.new()
	ba.bone_name = "hand_r"
	skel.add_child(ba)
	var g: Node3D = (load("res://assets/weapons/pistolet.glb") as PackedScene).instantiate()
	g.transform = offset
	ba.add_child(g)
	g.visible = false
	grips.append([model, skel, g])
	return g


## Cale l'arme dans la main une fois la pose de visée appliquée : canon vers l'avant du personnage,
## poignée entre le poignet et la base des doigts. Le décalage obtenu reste ensuite fixe dans la main.
func _calibrate_grips() -> void:
	for e in grips:
		var model: Node3D = e[0]
		var skel: Skeleton3D = e[1]
		var g: Node3D = e[2]
		var hand := skel.global_transform * skel.get_bone_global_pose(skel.find_bone("hand_r"))
		var mid := skel.global_transform * skel.get_bone_global_pose(skel.find_bone("middle_01_r"))
		var fwd: Vector3 = model.global_basis.z.normalized()
		var up := Vector3.UP
		var right := up.cross(-fwd).normalized()
		var basis := Basis(right, up, -fwd).orthonormalized()
		# la poignée est inclinée de 18° : on remonte le canon d'autant
		basis = basis.rotated(right, deg_to_rad(-4))
		var pos := hand.origin.lerp(mid.origin, 0.55) + Vector3.DOWN * 0.035
		g.global_transform = Transform3D(basis, pos)
		g.visible = true


# position de l'arme dans la main droite (repère de l'os hand_r)
var GRIP_ROT := Vector3(0, 90, -90)
var GRIP_POS := Vector3(0.0, 0.085, 0.03)
var GRIP: Transform3D:
	get: return Transform3D(Basis.from_euler(GRIP_ROT * PI / 180.0), GRIP_POS)


func _build_guard() -> void:
	guard = (load("res://assets/characters/garde.glb") as PackedScene).instantiate()
	guard.position = Vector3(0.35, 0, -8.6)
	guard.rotation_degrees.y = 8
	add_child(guard)
	guard_anim = _find_anim(guard)
	_attach_pistol(guard, GRIP)
	var anim := "Pistol_Aim_Neutral"   # pose de visée d'abord, pour caler l'arme dans la main
	_loop(guard_anim, "Pistol_Idle")
	_loop(guard_anim, "Pistol_Aim_Neutral")
	guard_anim.play(anim)
	guard_state = "aim" if mode != "video" else "idle"


func _loop(ap: AnimationPlayer, n: String) -> void:
	if ap.has_animation(n):
		ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR


func _build_player() -> void:
	rig = Node3D.new()
	rig.position = Vector3(-0.15, 0, 0.6)
	add_child(rig)
	var marc: Node3D = (load("res://assets/characters/marc.glb") as PackedScene).instantiate()
	marc.rotation_degrees.y = 180
	rig.add_child(marc)
	marc_anim = _find_anim(marc)
	_loop(marc_anim, "Pistol_Aim_Neutral")
	marc_anim.play("Pistol_Aim_Neutral")
	var g := _attach_pistol(marc, GRIP)
	# main gauche ramenée sur la poignée (l'animation libre la laisse écartée)
	var sk: Skeleton3D = marc.find_children("*", "Skeleton3D", true, false)[0]
	var tgt := Marker3D.new()
	tgt.name = "cible_main_g"
	tgt.position = Vector3(-0.05, -0.03, 0.02)
	g.add_child(tgt)
	var pole := Marker3D.new()
	pole.name = "coude_g"
	rig.add_child(pole)
	pole.position = Vector3(-0.6, 0.6, -0.1)
	var ik := TwoBoneIK3D.new()
	sk.add_child(ik)
	ik.setting_count = 1
	ik.set_root_bone_name(0, "upperarm_l")
	ik.set_middle_bone_name(0, "lowerarm_l")
	ik.set_end_bone_name(0, "hand_l")
	ik.set_target_node(0, ik.get_path_to(tgt))
	ik.set_pole_node(0, ik.get_path_to(pole))
	# flash de bouche
	muzzle_light = OmniLight3D.new()
	muzzle_light.light_color = Color(1.0, 0.75, 0.45)
	muzzle_light.omni_range = 6.0
	muzzle_light.light_energy = 0.0
	muzzle_light.shadow_enabled = true
	muzzle_light.position = Vector3(0, 0.08, 0.2)
	g.add_child(muzzle_light)
	muzzle_sprite = Sprite3D.new()
	muzzle_sprite.texture = load("res://assets/fx/flash_canon.png")
	muzzle_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	muzzle_sprite.pixel_size = 0.0012
	muzzle_sprite.shaded = false
	muzzle_sprite.modulate = Color(1, 0.9, 0.7, 1)
	muzzle_sprite.position = Vector3(0, 0.075, 0.2)
	muzzle_sprite.visible = false
	g.add_child(muzzle_sprite)
	cam = Camera3D.new()
	cam.position = Vector3(0, 1.63, 0.0)
	cam.fov = 78
	cam.near = 0.03
	cam.far = 80
	rig.add_child(cam)
	cam.make_current()


# ---------------------------------------------------------------- effet caméra-piéton

func _build_post() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post = ShaderMaterial.new()
	post.shader = load("res://shaders/camera_pieton.gdshader")
	r.material = post
	cl.add_child(r)
	if style == "A":
		post.set_shader_parameter("contrast", 1.06)
		post.set_shader_parameter("saturation", 0.72)
		post.set_shader_parameter("chroma", 0.003)
		post.set_shader_parameter("grain", 0.06)
		post.set_shader_parameter("vignette", 0.85)
		post.set_shader_parameter("split_tone", 0.2)
		post.set_shader_parameter("black_lift", 0.014)
	else:
		post.set_shader_parameter("contrast", 1.32)
		post.set_shader_parameter("saturation", 1.0)
		post.set_shader_parameter("chroma", 0.006)
		post.set_shader_parameter("grain", 0.085)
		post.set_shader_parameter("vignette", 1.2)
		post.set_shader_parameter("split_tone", 0.22)
		post.set_shader_parameter("tint_shadows", Color(0.4, 0.5, 0.56))
		post.set_shader_parameter("tint_highlights", Color(0.56, 0.51, 0.46))
		post.set_shader_parameter("black_lift", 0.004)
		post.set_shader_parameter("compression", 0.5)
	if mode == "blesse":
		post.set_shader_parameter("blood", 0.75)
		post.set_shader_parameter("hurt", 0.45)
	# incrustation « REC » et horodatage
	var lab := Label.new()
	lab.name = "rec"
	lab.position = Vector2(64, 46)
	lab.add_theme_font_size_override("font_size", 26)
	lab.add_theme_color_override("font_color", Color(0.92, 0.92, 0.9, 0.85))
	lab.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	lab.add_theme_constant_override("shadow_offset_x", 2)
	lab.add_theme_constant_override("shadow_offset_y", 2)
	cl.add_child(lab)
	var dot := ColorRect.new()
	dot.name = "dot"
	dot.color = Color(0.95, 0.08, 0.05)
	dot.size = Vector2(16, 16)
	dot.position = Vector2(40, 56)
	cl.add_child(dot)
	var id := Label.new()
	id.text = "CAM 07  ·  M. D."
	id.position = Vector2(64, 80)
	id.add_theme_font_size_override("font_size", 18)
	id.add_theme_color_override("font_color", Color(0.85, 0.85, 0.82, 0.6))
	cl.add_child(id)
	_update_rec()


func _update_rec() -> void:
	var lab: Label = find_child("rec", true, false)
	var dot: ColorRect = find_child("dot", true, false)
	var s := 3 * 3600 + 14 * 60 + 27 + int(t)
	lab.text = "REC   14/03/2027   %02d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
	dot.visible = fmod(t, 1.0) < 0.6


# ---------------------------------------------------------------- sang

func _build_blood() -> void:
	blood_ps = GPUParticles3D.new()
	blood_ps.one_shot = true
	blood_ps.emitting = false
	blood_ps.amount = 160
	blood_ps.lifetime = 1.4
	blood_ps.explosiveness = 0.95
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0.25, -1)
	pm.spread = 22
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 6.5
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.4
	pm.scale_max = 1.6
	pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	blood_ps.process_material = pm
	var sm := SphereMesh.new()
	sm.radius = 0.012
	sm.height = 0.024
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.32, 0.0, 0.01)
	bm.roughness = 0.2
	sm.material = bm
	blood_ps.draw_pass_1 = sm
	add_child(blood_ps)
	var col := GPUParticlesCollisionBox3D.new()
	col.size = Vector3(W, 0.2, 30)
	col.position = Vector3(0, -0.1, -10)
	add_child(col)
	wall_blood = Decal.new()
	wall_blood.texture_albedo = load("res://assets/fx/sang_eclaboussure.png")
	wall_blood.size = Vector3(1.6, 0.4, 1.6)
	wall_blood.position = Vector3(-W / 2 + 0.05, 1.3, -9.9)
	wall_blood.rotation_degrees = Vector3(0, 0, -90)
	wall_blood.visible = mode != "video"
	add_child(wall_blood)
	floor_blood = Decal.new()
	floor_blood.texture_albedo = load("res://assets/fx/sang_flaque.png")
	floor_blood.size = Vector3(0.01, 0.3, 0.01)
	floor_blood.position = Vector3(0.1, 0.05, -9.6)
	floor_blood.visible = false
	add_child(floor_blood)


# ---------------------------------------------------------------- scénario

func _process(delta: float) -> void:
	t += delta
	frames += 1
	if frames == 3:
		_calibrate_grips()
		if mode == "video":
			guard_anim.play("Pistol_Idle")
	_update_rec()
	for i in flicker.size():
		var l: Light3D = flicker[i]
		var base := 2.2 if l is SpotLight3D else 0.25
		var f := 1.0 if fmod(t * 7.3, 3.1) > 0.35 else (0.05 if fmod(t * 41.0, 1.0) > 0.5 else 0.6)
		l.light_energy = base * f
	if mode == "video":
		if frames == 1:
			rig.position = Vector3(-0.2, 0, -3.2)
		_video(delta)
	else:
		_pose_photo()
	_update_post(delta)
	if mode != "video" and frames > 8 and t > 1.2 and out_path != "":
		_save_and_quit()
	if mode == "video" and t >= VIDEO_LEN:
		get_tree().quit()


func _pose_photo() -> void:
	rig.position = Vector3(-0.2, 0, -4.3)
	cam.rotation_degrees = Vector3(-2.0, 2.5, 0.6)
	if mode == "plan":   # contrôle : vue de trois quarts du garde
		cam.global_position = guard.global_position + Vector3(1.0, 1.6, 2.2)
		cam.look_at(guard.global_position + Vector3(0, 1.2, 0))
		post.set_shader_parameter("intensity", 0.0)
	if mode == "mains":  # contrôle : vue de côté du corps de Marc
		cam.global_position = rig.global_position + Vector3(1.6, 1.5, -0.3)
		cam.look_at(rig.global_position + Vector3(0, 1.3, -0.3))
		post.set_shader_parameter("intensity", 0.0)


func _video(delta: float) -> void:
	# marche prudente, s'arrête pour tirer, puis avance vers le corps
	var walk := 0.0
	if t < 2.3:
		walk = 1.0
	elif t > 3.8:
		walk = 0.6
	rig.position.z -= walk * 1.15 * delta
	var bob := walk * sin(t * 9.0)
	cam.position = Vector3(0.012 * sin(t * 4.5) * walk, 1.63 + 0.018 * bob, 0.0)
	if t > 1.3 and guard_state == "idle":
		guard_state = "aim"
		guard_anim.play("Pistol_Aim_Neutral", 0.35)
	for s in shots:
		if t >= s and not shot_done.has(s):
			shot_done[s] = true
			_fire()
	if t > 2.65 and guard_state == "aim":
		guard_state = "hit"
		guard_anim.play("Hit_Chest", 0.05)
		blood_ps.global_position = guard.global_position + Vector3(0, 1.3, -0.1)
		blood_ps.restart()
		wall_blood.visible = true
	if t > 3.05 and guard_state == "hit":
		guard_state = "dead"
		guard_anim.play("Death01", 0.08)
		blood_ps.global_position = guard.global_position + Vector3(0, 1.2, -0.1)
		blood_ps.restart()
	if guard_state == "dead" and t > 4.0:
		floor_blood.visible = true
		pool_scale = min(1.4, pool_scale + delta * 0.5)
		floor_blood.size = Vector3(0.3 + pool_scale, 0.3, 0.3 + pool_scale)
	recoil = move_toward(recoil, 0.0, delta * 14.0)
	shake = move_toward(shake, 0.0, delta * 3.0)
	var sx := (randf() - 0.5) * shake
	var sy := (randf() - 0.5) * shake
	cam.rotation_degrees = Vector3(-1.5 + recoil * 4.0 + sx * 3.0 + 0.6 * bob, 1.0 + sy * 3.0 + 0.4 * sin(t * 4.5) * walk, 0.8 * sin(t * 4.5) * walk)
	var on := muzzle_light.light_energy > 0.0
	muzzle_light.light_energy = max(0.0, muzzle_light.light_energy - delta * 90.0)
	muzzle_sprite.visible = muzzle_light.light_energy > 1.5
	if on:
		muzzle_sprite.rotation_degrees.z = randf() * 360.0


func _fire() -> void:
	muzzle_light.light_energy = 9.0
	muzzle_sprite.visible = true
	recoil = 1.0
	shake = 1.0
	post.set_shader_parameter("flash", 0.12)


func _update_post(delta: float) -> void:
	var b := cam.global_transform.basis
	var dq := last_cam_basis.inverse() * b
	var e := dq.get_euler()
	last_cam_basis = b
	var mv: Vector2 = Vector2(-e.y, e.x) / max(delta, 0.001) * 0.05
	post.set_shader_parameter("motion", mv)
	var f: float = post.get_shader_parameter("flash") if post.get_shader_parameter("flash") != null else 0.0
	post.set_shader_parameter("flash", max(0.0, f - delta * 1.2))


func _save_and_quit() -> void:
	set_process(false)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_path)
	print("CAPTURE ", out_path)
	get_tree().quit()
