class_name FxSang
extends RefCounted
## Sang minimal à l'impact d'une balle dans un corps : brume rouge sombre à l'entrée, gouttelettes
## projetées dans le sens du tir (sortie). Respecte le réglage « violence » (0 = sans sang,
## 1 = réduite, 2 = maximum). Le gros du sang (flaques, giclées, décalques) viendra plus tard.

static var _pm_brume: ParticleProcessMaterial
static var _pm_gouttes: ParticleProcessMaterial
static var _quad_brume: QuadMesh
static var _mesh_goutte: BoxMesh


static func niveau_violence() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root.has_node("Reglages"):
		return int(tree.root.get_node("Reglages").get_v("violence"))
	return 2


## `point` : impact ; `normale` : surface touchée ; `direction` : sens de la balle.
static func impact(parent: Node, point: Vector3, normale: Vector3, direction: Vector3, force := 1.0) -> void:
	var v := niveau_violence()
	if v <= 0 or parent == null or not parent.is_inside_tree():
		return
	_preparer()
	var k := 1.0 if v >= 2 else 0.45
	var n := normale if normale.length() > 0.1 else -direction
	# brume d'entrée (vers le tireur) et de sortie (dans le sens du tir)
	_emettre(parent, _pm_brume, _quad_brume, int(10 * k * force) + 2, 0.45, point, n)
	_emettre(parent, _pm_brume, _quad_brume, int(8 * k * force) + 1, 0.55, point, direction)
	_emettre(parent, _pm_gouttes, _mesh_goutte, int(22 * k * force) + 2, 0.9, point, direction)


static func _emettre(parent: Node, pm: ParticleProcessMaterial, m: Mesh, nb: int, duree: float, point: Vector3, dir: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.97
	p.local_coords = false
	p.amount = max(nb, 1)
	p.lifetime = duree
	p.process_material = pm
	p.draw_pass_1 = m
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	var z := -dir.normalized()   # l'émetteur projette selon son -Z
	var x := z.cross(Vector3.UP if abs(z.y) < 0.9 else Vector3.RIGHT).normalized()
	p.global_transform = Transform3D(Basis(x, z.cross(x), z), point)
	p.emitting = true
	p.get_tree().create_timer(duree + 0.4, false).timeout.connect(p.queue_free)


## À appeler au chargement du niveau : compile les shaders des particules hors combat.
static func prechauffer(parent: Node, point: Vector3) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	_preparer()
	for e in [[_pm_brume, _quad_brume], [_pm_gouttes, _mesh_goutte]]:
		var p := GPUParticles3D.new()
		p.one_shot = true
		p.amount = 1
		p.lifetime = 0.2
		p.process_material = e[0]
		p.draw_pass_1 = e[1]
		parent.add_child(p)
		p.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.001), point)
		p.emitting = true
		p.get_tree().create_timer(0.5, false).timeout.connect(p.queue_free)


static func liberer() -> void:
	_pm_brume = null
	_pm_gouttes = null
	_quad_brume = null
	_mesh_goutte = null


static func _preparer() -> void:
	if _pm_brume != null:
		return
	_pm_brume = ParticleProcessMaterial.new()
	_pm_brume.direction = Vector3(0, 0, -1)
	_pm_brume.spread = 28.0
	_pm_brume.initial_velocity_min = 0.6
	_pm_brume.initial_velocity_max = 2.4
	_pm_brume.gravity = Vector3(0, -1.2, 0)
	_pm_brume.damping_min = 3.0
	_pm_brume.damping_max = 6.0
	_pm_brume.scale_min = 0.5
	_pm_brume.scale_max = 1.3
	_pm_brume.angle_max = 360.0
	var sc := CurveTexture.new()
	var c := Curve.new()
	c.add_point(Vector2(0, 0.4))
	c.add_point(Vector2(1, 1.8))
	sc.curve = c
	_pm_brume.scale_curve = sc
	var g := Gradient.new()
	g.set_color(0, Color(0.32, 0.02, 0.02, 0.85))
	g.set_color(1, Color(0.22, 0.01, 0.01, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	_pm_brume.color_ramp = gt
	_quad_brume = QuadMesh.new()
	_quad_brume.size = Vector2(0.09, 0.09)
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/fx/fumee.png")
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.roughness = 0.6
	_quad_brume.material = m

	_pm_gouttes = ParticleProcessMaterial.new()
	_pm_gouttes.direction = Vector3(0, 0, -1)
	_pm_gouttes.spread = 22.0
	_pm_gouttes.initial_velocity_min = 1.5
	_pm_gouttes.initial_velocity_max = 4.5
	_pm_gouttes.gravity = Vector3(0, -9.8, 0)
	_pm_gouttes.scale_min = 0.5
	_pm_gouttes.scale_max = 1.4
	_pm_gouttes.particle_flag_align_y = true
	_mesh_goutte = BoxMesh.new()
	_mesh_goutte.size = Vector3(0.005, 0.018, 0.005)
	var mg := StandardMaterial3D.new()
	mg.albedo_color = Color(0.24, 0.01, 0.01)
	mg.roughness = 0.25
	mg.metallic_specular = 0.7
	_mesh_goutte.material = mg
