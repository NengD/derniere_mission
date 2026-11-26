class_name CibleTest
extends Node3D
## Mannequin d'entraînement pour la salle de test : parties du corps séparées sur la couche 4
## (hitboxes) avec la métadonnée « os » (noms façon UE), et la méthode commune recevoir_tir().
## Tombe à 0 PV et se relève après quelques secondes.

signal touche(zone: int, degats: float, pv: float)

var pv := Degats.PV_MAX
var _balancement := Vector2.ZERO
var _vitesse := Vector2.ZERO
var _pivot: Node3D
var _a_terre := false


func _ready() -> void:
	_pivot = Node3D.new()
	add_child(_pivot)
	var bois := StandardMaterial3D.new()
	bois.albedo_color = Color(0.36, 0.3, 0.22)
	bois.roughness = 0.85
	var tissu := StandardMaterial3D.new()
	tissu.albedo_color = Color(0.16, 0.17, 0.15)
	tissu.roughness = 0.95
	# socle et poteau
	_piece("socle", BoxShape3D, Vector3(0.5, 0.06, 0.5), Vector3(0, 0.03, 0), bois, "", false)
	_piece("poteau", BoxShape3D, Vector3(0.05, 0.75, 0.05), Vector3(0, 0.4, 0), bois, "", false)
	# corps
	_piece("tete", SphereShape3D, Vector3(0.11, 0, 0), Vector3(0, 1.62, 0), tissu, "Head")
	_piece("cou", CapsuleShape3D, Vector3(0.06, 0.14, 0), Vector3(0, 1.48, 0), tissu, "neck_01")
	_piece("torse", CapsuleShape3D, Vector3(0.18, 0.62, 0), Vector3(0, 1.15, 0), tissu, "spine_02")
	_piece("bras_g", CapsuleShape3D, Vector3(0.055, 0.6, 0), Vector3(0.24, 1.1, 0), tissu, "upperarm_l")
	_piece("bras_d", CapsuleShape3D, Vector3(0.055, 0.6, 0), Vector3(-0.24, 1.1, 0), tissu, "upperarm_r")
	_piece("jambe_g", CapsuleShape3D, Vector3(0.075, 0.82, 0), Vector3(0.1, 0.42 + 0.06, 0), tissu, "thigh_l")
	_piece("jambe_d", CapsuleShape3D, Vector3(0.075, 0.82, 0), Vector3(-0.1, 0.42 + 0.06, 0), tissu, "thigh_r")


func _piece(nom: String, type, dims: Vector3, pos: Vector3, m: Material, os: String, hitbox := true) -> void:
	var sb := StaticBody3D.new()
	sb.name = nom
	sb.collision_layer = 8 if hitbox else 1   # couche 4 : hitboxes ; sinon décor
	sb.collision_mask = 0
	if os != "":
		sb.set_meta("os", os)
	var cs := CollisionShape3D.new()
	var mi := MeshInstance3D.new()
	if type == SphereShape3D:
		var s := SphereShape3D.new()
		s.radius = dims.x
		cs.shape = s
		var sm := SphereMesh.new()
		sm.radius = dims.x
		sm.height = dims.x * 2.0
		mi.mesh = sm
	elif type == CapsuleShape3D:
		var c := CapsuleShape3D.new()
		c.radius = dims.x
		c.height = dims.y
		cs.shape = c
		var cm := CapsuleMesh.new()
		cm.radius = dims.x
		cm.height = dims.y
		mi.mesh = cm
	else:
		var b := BoxShape3D.new()
		b.size = dims
		cs.shape = b
		var bm := BoxMesh.new()
		bm.size = dims
		mi.mesh = bm
	mi.material_override = m
	sb.add_child(cs)
	sb.add_child(mi)
	sb.position = pos
	_pivot.add_child(sb)


## Interface commune des dégâts (voir scripts/joueur/joueur.gd).
func recevoir_tir(degats: float, os_ou_zone, point: Vector3, _normale: Vector3, direction: Vector3, _tireur: Node) -> void:
	var zone: int = os_ou_zone if os_ou_zone is int else Degats.zone_depuis_os(str(os_ou_zone))
	var d: float = degats * Degats.MULTIPLICATEUR[zone]
	pv -= d
	if has_node("/root/Audio"):
		get_node("/root/Audio").son_3d(load("res://assets/sons/impact_chair_%d.wav" % randi_range(1, 3)), point, get_parent(), -2.0)
	FxImpact.poussiere(get_parent(), point, -direction, "tissu")
	var loc := global_basis.inverse() * direction
	_vitesse += Vector2(-loc.z, loc.x) * 2.5
	# pas de print() ici : sous Windows, écrire dans la console bloque l'image ≈ 33 ms (à-coup à chaque balle)
	print_verbose("CIBLE ", name, " touchée : ", os_ou_zone, " zone ", zone, " dégâts ", snapped(d, 0.1), " PV ", snapped(pv, 0.1))
	touche.emit(zone, d, pv)
	if pv <= 0.0 and not _a_terre:
		_a_terre = true
		var tw := create_tween()
		tw.tween_property(_pivot, "rotation:x", -PI / 2.0 * 0.95, 0.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.tween_interval(3.0)
		tw.tween_property(_pivot, "rotation:x", 0.0, 0.6)
		tw.tween_callback(func() -> void:
			pv = Degats.PV_MAX
			_a_terre = false)


func _process(delta: float) -> void:
	if _a_terre:
		return
	# balancier amorti
	_vitesse += -_balancement * 60.0 * delta
	_vitesse *= exp(-4.0 * delta)
	_balancement += _vitesse * delta
	_pivot.rotation = Vector3(_balancement.x * 0.25, 0, _balancement.y * 0.25)
