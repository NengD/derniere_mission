extends Node3D
## Aperçu des gardes MPFB (issue #1) : les gardes du cartel côte à côte dans un local sombre de
## l'aéroport de fret, vus à travers l'effet caméra-piéton (direction A).
##
## Arguments (après « -- ») : <mode> [fichier de sortie] [option]
##   ensemble <png>          : les gardes côte à côte (pistolet baissé)
##   visages <png>           : gros plan de deux visages couverts
##   controle <png> <anim>   : contrôle sans effet, éclairage plat, tous les gardes dans la même animation
##                             (option : nom d'animation, « @t » pour l'instant, ex. Death01@1.5)
##   video                   : à lancer avec --write-movie x.avi --fixed-fps 30 ; attente, marche prudente,
##                             visée (animations CMU retravaillées), puis quitte
##   (controle : suffixes « #g1 »…« #g4 » gros plan du visage du garde N, « #c1 »… en pied, « #d » de côté)

const PH := "res://assets/decor/"
const GARDES := ["garde_1", "garde_3", "garde_2", "garde_4"]
const VIDEO_LEN := 9.5
## vitesses de marche des animations CMU (m/s, mesurées par tools/blender/retarget_cmu.py)
const VITESSE := {"Cmu_Marche": 1.23, "Cmu_Marche_Lente": 0.95, "Cmu_Marche_Prudente": 0.95, "Visee_Marche": 0.95, "Cmu_Course": 3.04}

var mode := "ensemble"
var out_path := ""
var option := ""
var t := 0.0
var frames := 0
var cam: Camera3D
var post: ShaderMaterial
var guards: Array[Node3D] = []
var anims: Array[AnimationPlayer] = []
var grips: Array = []
var pistols: Array[Node3D] = []
var phase := ""
var flicker: Array = []


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0: mode = a[0]
	if a.size() > 1: out_path = a[1]
	if a.size() > 2: option = a[2]
	_build_environment()
	_build_room()
	_build_lights()
	_build_guards()
	_build_camera()
	_build_post()


# ---------------------------------------------------------------- matériaux et décor

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


func _box(size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	add_child(mi)
	return mi


func _prop(name: String, pos: Vector3, rot_y := 0.0, child := "") -> Node3D:
	var n: Node3D = (load(PH + "models/%s/%s.gltf" % [name, name]) as PackedScene).instantiate()
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
	return n


func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color.BLACK
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.55, 0.6)
	e.ambient_light_energy = 0.035 if mode != "controle" else 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_white = 6.0
	e.ssao_enabled = true
	e.ssao_radius = 1.2
	e.ssao_intensity = 2.0
	e.ssil_enabled = true
	e.glow_enabled = true
	e.glow_intensity = 0.6
	e.glow_bloom = 0.04
	e.glow_hdr_threshold = 1.2
	e.volumetric_fog_enabled = mode != "controle"
	e.volumetric_fog_density = 0.03
	e.volumetric_fog_anisotropy = 0.6
	e.volumetric_fog_length = 30.0
	we.environment = e
	add_child(we)


const W := 6.0
const H := 3.2
const Z0 := 3.0
const Z1 := -12.0


func _build_room() -> void:
	var len := Z0 - Z1
	var cz := (Z0 + Z1) / 2.0
	_box(Vector3(W, 0.2, len), Vector3(0, -0.1, cz), _mat("hangar_concrete_floor", 0.35))
	_box(Vector3(W, 0.2, len), Vector3(0, H + 0.1, cz), _mat("concrete_panels", 0.4, Color(0.6, 0.6, 0.6)))
	var wall := _mat("concrete_wall_008", 0.4, Color(0.8, 0.8, 0.78))
	var dado := _mat("painted_concrete", 0.5, Color(0.42, 0.5, 0.46))
	for s in [-1.0, 1.0]:
		_box(Vector3(0.2, H, len), Vector3(s * (W / 2 + 0.1), H / 2, cz), wall)
		_box(Vector3(0.03, 1.15, len), Vector3(s * (W / 2 - 0.015), 0.575, cz), dado)
	_box(Vector3(W, H, 0.2), Vector3(0, H / 2, Z1 - 0.1), wall)
	_box(Vector3(W, H, 0.2), Vector3(0, H / 2, Z0 + 0.1), wall)
	var door := _prop("rollershutter_door", Vector3(0, 0, Z1 + 0.05), 0, "rollershutter_door_graffiti")
	door.scale = Vector3(2.6 / 1.08, 2.8 / 2.4, 1.0)
	_prop("wooden_military_crate", Vector3(-W / 2 + 0.5, 0, -7.5), 80)
	_prop("wooden_military_crate", Vector3(-W / 2 + 0.5, 0, -8.4), 95)
	_prop("cardboard_box_01", Vector3(W / 2 - 0.5, 0, -6.5), 20)
	_prop("plastic_crate_01", Vector3(W / 2 - 0.6, 0, -9.0), 30)
	var tag := Decal.new()
	tag.texture_albedo = load("res://assets/fx/tag_cercle.png")
	tag.size = Vector3(1.4, 0.3, 1.4)
	tag.position = Vector3(-1.6, 1.9, Z1 + 0.05)
	tag.rotation_degrees = Vector3(90, 0, 0)
	tag.albedo_mix = 0.9
	add_child(tag)


func _build_lights() -> void:
	if mode == "controle":
		for p in [Vector3(1.5, 2.8, -1.5), Vector3(-2.0, 2.2, -2.0), Vector3(0.0, 2.6, -6.5)]:
			var o := OmniLight3D.new()
			o.position = p
			o.omni_range = 9.0
			o.light_energy = 2.2
			o.shadow_enabled = true
			add_child(o)
		return
	# rampes fluorescentes (néon froid) au plafond
	for z in [-0.5, -3.1, -8.5]:
		_prop("mounted_fluorescent_lights", Vector3(0, H - 0.02, z), 90, "mounted_fluorescent_lights_a")
		var s := SpotLight3D.new()
		s.position = Vector3(0, H - 0.12, z)
		s.rotation_degrees = Vector3(-90, 0, 0)
		s.spot_angle = 75
		s.spot_attenuation = 0.8
		s.spot_range = 7.0
		s.light_energy = 2.4
		s.light_color = Color(0.86, 0.95, 1.0)
		s.shadow_enabled = true
		s.shadow_blur = 1.5
		s.light_volumetric_fog_energy = 0.5
		add_child(s)
		if z < -8.0:
			flicker.append(s)
	# baladeuse au sodium posée sur une caisse, à gauche : éclaire les visages de trois quarts
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(-2.2, 1.5, -2.4)
	lamp.omni_range = 5.5
	lamp.light_energy = 1.3
	lamp.light_color = Color(1.0, 0.7, 0.4)
	lamp.shadow_enabled = true
	add_child(lamp)
	# projecteur au sodium par la porte du fond et lampe de garde orange sur le côté
	var ext := SpotLight3D.new()
	ext.position = Vector3(0.6, 0.4, Z1 + 0.3)
	ext.rotation_degrees = Vector3(-6, 0, 0)
	ext.spot_angle = 55
	ext.spot_range = 14
	ext.light_energy = 2.5
	ext.light_color = Color(1.0, 0.72, 0.42)
	ext.light_volumetric_fog_energy = 1.8
	ext.shadow_enabled = true
	add_child(ext)
	var sodium := OmniLight3D.new()
	sodium.position = Vector3(W / 2 - 0.4, 2.4, -3.2)
	sodium.omni_range = 5.0
	sodium.light_energy = 1.1
	sodium.light_color = Color(1.0, 0.66, 0.32)
	sodium.shadow_enabled = true
	add_child(sodium)
	# rebond froid côté caméra (sinon les visages sont noirs)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-1.0, 2.2, 0.8)
	fill.omni_range = 6.0
	fill.light_energy = 0.35
	fill.light_color = Color(0.7, 0.8, 1.0)
	add_child(fill)


# ---------------------------------------------------------------- gardes

func _build_guards() -> void:
	var xs := [-1.65, -0.55, 0.55, 1.65]
	var z := -3.4
	if mode == "visages":
		xs = [-1.9, -0.27, 0.27, 1.9]
		z = -4.0
	elif mode == "video":
		z = -6.6      # assez loin pour marcher ~3 m vers la caméra
	for i in GARDES.size():
		var path := "res://assets/characters/gardes/%s.glb" % GARDES[i]
		if not ResourceLoader.exists(path):
			continue
		var g: Node3D = (load(path) as PackedScene).instantiate()
		g.position = Vector3(xs[i], 0, z)
		g.rotation_degrees.y = [6.0, -4.0, 3.0, -7.0][i]
		add_child(g)
		guards.append(g)
		var ap: AnimationPlayer = g.find_children("*", "AnimationPlayer", true, false)[0]
		for n in ap.get_animation_list():   # boucles (« _Loop » retiré par l'import) + visée
			if n.begins_with("Cmu_") or n.ends_with("_Vivante") or n in ["Idle", "Pistol_Idle", "Pistol_Aim_Neutral", "Walk", "Visee_Marche"]:
				ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR
		anims.append(ap)
		pistols.append(_attach_pistol(g))
		ap.play("Pistol_Aim_Neutral")   # pose de visée d'abord, pour caler l'arme dans la main


func _attach_pistol(model: Node3D) -> Node3D:
	var skel: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var fc := FingerCurl.new()
	fc.axis = Vector3(0, 0, 1)
	skel.add_child(fc)
	var ba := BoneAttachment3D.new()
	ba.bone_name = "hand_r"
	skel.add_child(ba)
	var g: Node3D = (load("res://assets/weapons/pistolet.glb") as PackedScene).instantiate()
	ba.add_child(g)
	g.visible = false
	grips.append([model, skel, g])
	return g


## Cale l'arme dans la main une fois la pose de visée appliquée (même calcul que apercu.gd).
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
		basis = basis.rotated(right, deg_to_rad(-4))
		var pos := hand.origin.lerp(mid.origin, 0.55) + Vector3.DOWN * 0.035
		g.global_transform = Transform3D(basis, pos)
		g.visible = mode != "controle" or not (option.begins_with("Idle") or option.begins_with("Death") or option.begins_with("Hit"))


func _play_all(n: String, blend := 0.25, stagger := 0.0) -> void:
	for i in anims.size():
		var ap := anims[i]
		if ap.has_animation(n):
			ap.play(n, blend)
			if stagger > 0.0:
				ap.seek(stagger * i, true)


# ---------------------------------------------------------------- caméra et effet

func _build_camera() -> void:
	cam = Camera3D.new()
	cam.fov = 62
	cam.near = 0.03
	cam.far = 60
	add_child(cam)
	cam.make_current()
	_place_camera()


func _place_camera() -> void:
	match mode:
		"visages":
			cam.fov = 24
			cam.position = Vector3(0.05, 1.66, -2.2)
			cam.look_at(Vector3(0.0, 1.6, -4.0))
		"controle":
			cam.fov = 50
			cam.position = Vector3(0.0, 1.3, -0.9)
			cam.look_at(Vector3(0.0, 0.95, -4.0))
			var gi := option.find("#g")
			if gi >= 0 or option.find("#c") >= 0:
				# gros plan d'un garde (#g1..#g4 : visage, #c1..#c4 : en pied), numéro = garde_N
				var plein := gi < 0
				var num := int(option.substr((gi if gi >= 0 else option.find("#c")) + 2, 1))
				var g: Node3D = guards[GARDES.find("garde_%d" % num)]
				var fwd := g.global_basis.z.normalized()
				var side := fwd.cross(Vector3.UP).normalized()
				var cible := g.global_position + Vector3(0, 0.95 if plein else 1.58, 0)
				cam.fov = 34 if plein else 16
				var ang := 0.35 if option.find("#d") < 0 else 1.2
				var dir := (fwd * cos(ang) + side * sin(ang)).normalized()
				cam.position = cible + dir * (3.2 if plein else 1.6) + Vector3(0, 0.05, 0)
				cam.look_at(cible)
			elif option.ends_with("#tete"):     # gros plan des têtes (gardes 3 et 4 de la liste)
				cam.fov = 30
				cam.position = Vector3(-0.6, 1.62, -2.6)
				cam.look_at(Vector3(-0.6, 1.6, -4.0))
			elif option.ends_with("#cote"):   # vue de trois quarts arrière (épaules, coudes)
				cam.position = Vector3(2.8, 1.5, -2.6)
				cam.look_at(Vector3(1.2, 1.1, -4.0))
		_:
			cam.position = Vector3(0.1, 1.62, 0.2)
			cam.look_at(Vector3(0, 1.15, -4.0))


## Gros plan : caméra placée face au milieu des deux têtes (gardes 2 et 3 de la liste).
func _frame_faces() -> void:
	var heads: Array[Vector3] = []
	for i in [1, 2]:
		var sk: Skeleton3D = guards[i].find_children("*", "Skeleton3D", true, false)[0]
		heads.append((sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head"))).origin)
	var c: Vector3 = (heads[0] + heads[1]) / 2.0 + Vector3(0, 0.09, 0)
	cam.fov = 22
	# les deux têtes occupent environ le tiers central de l'image (l'objectif grand-angle de l'effet écarte les bords)
	var d := heads[0].distance_to(heads[1])
	var half_w := tan(deg_to_rad(cam.fov / 2.0)) * 16.0 / 9.0
	var dist := d / (0.3 * 2.0 * half_w)
	cam.position = c + Vector3(0.06 * dist, 0.02, dist)
	cam.look_at(c)


func _build_post() -> void:
	if mode == "controle":
		return
	var cl := CanvasLayer.new()
	add_child(cl)
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post = ShaderMaterial.new()
	post.shader = load("res://shaders/camera_pieton.gdshader")
	r.material = post
	cl.add_child(r)
	# réglages de la direction A (voir apercu.gd, _build_post)
	post.set_shader_parameter("contrast", 1.06)
	post.set_shader_parameter("saturation", 0.72)
	post.set_shader_parameter("chroma", 0.003)
	post.set_shader_parameter("grain", 0.06)
	post.set_shader_parameter("vignette", 0.85)
	post.set_shader_parameter("split_tone", 0.2)
	post.set_shader_parameter("black_lift", 0.014)
	var lab := Label.new()
	lab.name = "rec"
	lab.position = Vector2(64, 46)
	lab.add_theme_font_size_override("font_size", 26)
	lab.add_theme_color_override("font_color", Color(0.92, 0.92, 0.9, 0.85))
	lab.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	cl.add_child(lab)
	var dot := ColorRect.new()
	dot.name = "dot"
	dot.color = Color(0.95, 0.08, 0.05)
	dot.size = Vector2(16, 16)
	dot.position = Vector2(40, 56)
	cl.add_child(dot)
	_update_rec()


func _update_rec() -> void:
	var lab: Label = find_child("rec", true, false)
	if lab == null:
		return
	var dot: ColorRect = find_child("dot", true, false)
	var s := 3 * 3600 + 9 * 60 + 41 + int(t)
	lab.text = "REC   14/03/2027   %02d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
	dot.visible = fmod(t, 1.0) < 0.6


# ---------------------------------------------------------------- déroulement

func _process(delta: float) -> void:
	t += delta
	frames += 1
	if frames == 3:
		_calibrate_grips()
		_start()
	if frames == 5 and mode == "visages":
		_frame_faces()
	_update_rec()
	for l in flicker:
		var f := 1.0 if fmod(t * 7.3, 3.1) > 0.3 else (0.05 if fmod(t * 41.0, 1.0) > 0.5 else 0.6)
		(l as Light3D).light_energy = 2.4 * f
	if mode == "video":
		_video(delta)
		if t >= VIDEO_LEN:
			get_tree().quit()
	elif frames > 10 and t > 1.4 and out_path != "":
		_save_and_quit()


func _start() -> void:
	if option.find("#lod0") >= 0:
		get_viewport().mesh_lod_threshold = 0.0
	var ci := option.find("#cache=")      # contrôle : cache les maillages dont le nom contient le texte
	if ci >= 0:
		var motif := option.substr(ci + 7).split("#")[0]
		for g in guards:
			for m in g.find_children("*" + motif + "*", "MeshInstance3D", true, false):
				(m as Node3D).visible = false
	match mode:
		"controle":
			var parts := option.split("#")[0].split("@")
			var n := parts[0] if option != "" else "Pistol_Aim_Neutral"
			for ap in anims:
				ap.play(n, 0.0)
				if parts.size() > 1:
					ap.seek(float(parts[1]), true)
				if parts.size() > 1:
					ap.pause()
		"video":
			for i in anims.size():   # deux gardes attendent, deux scrutent la pièce
				anims[i].play(["Cmu_Attente", "Cmu_Regard", "Cmu_Attente", "Cmu_Regard"][i], 0.0)
				anims[i].seek(0.7 * i + 0.3, true)
			phase = "idle"
		"visages":
			_play_all("Cmu_Attente", 0.0, 0.6)
		_:
			_play_all("Pistolet_Attente_Vivante", 0.0, 0.9)


func _video(_delta: float) -> void:
	# 0-3 s : attente (captures CMU) ; 3-6,2 s : marche prudente vers la caméra, arme basse ;
	# 6,2-9,5 s : arrêt et visée « vivante » (respiration, poids du corps)
	if t > 3.0 and phase == "idle":
		phase = "walk"
		for i in anims.size():
			anims[i].play(["Cmu_Marche_Prudente", "Cmu_Marche_Lente", "Cmu_Marche_Prudente", "Cmu_Marche"][i], 0.45)
			anims[i].seek(0.27 * i, true)
	if phase == "walk":
		for i in guards.size():
			var n: StringName = anims[i].current_animation
			guards[i].position.z += VITESSE.get(String(n), 0.9) * 0.96 * _delta
	if t > 5.9 and phase == "walk":
		phase = "aim"
		_play_all("Visee_Vivante", 0.4, 0.8)
	# léger mouvement de la caméra portée
	cam.position = Vector3(0.1 + 0.01 * sin(t * 1.3), 1.62 + 0.006 * sin(t * 2.1), 0.2)
	cam.look_at(Vector3(0.02 * sin(t * 0.7), 1.15, -4.0))


func _save_and_quit() -> void:
	set_process(false)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_path)
	print("CAPTURE ", out_path)
	get_tree().quit()
