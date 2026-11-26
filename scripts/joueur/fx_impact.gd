class_name FxImpact
extends RefCounted
## Petits effets d'impact de balle sur le décor : poussière (béton, bois) ou étincelles (métal).
## Réutilisable par les gardes. Les nœuds créés se détruisent seuls.

static var _pm_poussiere: ParticleProcessMaterial
static var _pm_etincelles: ParticleProcessMaterial
static var _quad_poussiere: QuadMesh
static var _mesh_etincelle: BoxMesh


static func poussiere(parent: Node, point: Vector3, normale: Vector3, materiau := "beton") -> void:
	if parent == null or not parent.is_inside_tree():
		return
	_preparer()
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.local_coords = false
	if materiau == "metal":
		p.amount = 14
		p.lifetime = 0.35
		p.process_material = _pm_etincelles
		p.draw_pass_1 = _mesh_etincelle
	else:
		p.amount = 12
		p.lifetime = 1.1
		p.process_material = _pm_poussiere
		p.draw_pass_1 = _quad_poussiere
	parent.add_child(p)
	var y := normale.normalized()
	var x := y.cross(Vector3.UP if abs(y.y) < 0.9 else Vector3.RIGHT).normalized()
	# l'émetteur projette selon son -Z : on aligne -Z sur la normale
	var z := -y
	p.global_transform = Transform3D(Basis(x, z.cross(x), z), point + y * 0.02)
	p.emitting = true
	if materiau == "metal":
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.7, 0.35)
		l.light_energy = 1.5
		l.omni_range = 1.5
		parent.add_child(l)
		l.global_position = point + y * 0.08
		l.create_tween().tween_property(l, "light_energy", 0.0, 0.08)
		l.get_tree().create_timer(0.2).timeout.connect(l.queue_free)
	p.get_tree().create_timer(p.lifetime + 0.5).timeout.connect(p.queue_free)


## Préchauffage au chargement : un émetteur de chaque sorte, minuscule, devant la caméra pendant quelques
## images, pour que les shaders des particules soient compilés avant le premier tir (sinon la première
## balle qui touche le décor ou un mannequin fige l'image ≈ 50 à 150 ms).
static func prechauffer(parent: Node, point: Vector3) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	_preparer()
	for pm in [[_pm_poussiere, _quad_poussiere], [_pm_etincelles, _mesh_etincelle]]:
		var p := GPUParticles3D.new()
		p.one_shot = true
		p.amount = 2
		p.lifetime = 0.3
		p.local_coords = true
		p.process_material = pm[0]
		p.draw_pass_1 = pm[1]
		parent.add_child(p)
		p.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.001), point)
		p.emitting = true
		p.get_tree().create_timer(0.6).timeout.connect(p.queue_free)


static func liberer() -> void:
	_pm_poussiere = null
	_pm_etincelles = null
	_quad_poussiere = null
	_mesh_etincelle = null


static func _preparer() -> void:
	if _pm_poussiere != null:
		return
	_pm_poussiere = ParticleProcessMaterial.new()
	_pm_poussiere.direction = Vector3(0, 0, -1)
	_pm_poussiere.spread = 35.0
	_pm_poussiere.initial_velocity_min = 0.6
	_pm_poussiere.initial_velocity_max = 2.2
	_pm_poussiere.gravity = Vector3(0, -2.5, 0)
	_pm_poussiere.damping_min = 2.0
	_pm_poussiere.damping_max = 4.0
	_pm_poussiere.scale_min = 0.4
	_pm_poussiere.scale_max = 1.2
	_pm_poussiere.angle_max = 360.0
	var sc := CurveTexture.new()
	var c := Curve.new()
	c.add_point(Vector2(0, 0.5))
	c.add_point(Vector2(1, 2.0))
	sc.curve = c
	_pm_poussiere.scale_curve = sc
	var g := Gradient.new()
	g.set_color(0, Color(0.62, 0.6, 0.56, 0.55))
	g.set_color(1, Color(0.55, 0.53, 0.5, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	_pm_poussiere.color_ramp = gt
	_quad_poussiere = QuadMesh.new()
	_quad_poussiere.size = Vector2(0.07, 0.07)
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/fx/fumee.png")
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.roughness = 1.0
	_quad_poussiere.material = m

	_pm_etincelles = ParticleProcessMaterial.new()
	_pm_etincelles.direction = Vector3(0, 0, -1)
	_pm_etincelles.spread = 50.0
	_pm_etincelles.initial_velocity_min = 2.5
	_pm_etincelles.initial_velocity_max = 6.0
	_pm_etincelles.gravity = Vector3(0, -9.8, 0)
	_pm_etincelles.scale_min = 0.5
	_pm_etincelles.scale_max = 1.0
	_pm_etincelles.particle_flag_align_y = true
	_mesh_etincelle = BoxMesh.new()
	_mesh_etincelle.size = Vector3(0.003, 0.03, 0.003)
	var me := StandardMaterial3D.new()
	me.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	me.albedo_color = Color(1.0, 0.75, 0.4)
	me.emission_enabled = true
	me.emission = Color(1.0, 0.6, 0.25)
	me.emission_energy_multiplier = 6.0
	_mesh_etincelle.material = me
