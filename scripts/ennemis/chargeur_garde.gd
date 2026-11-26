class_name ChargeurGarde
extends RigidBody3D
## Chargeur lâché par un garde mort : tombe, roule un peu, puis se ramasse (couche 5 : interactifs).

var cartouches := 15


func _init() -> void:
	collision_layer = 16
	collision_mask = 1
	mass = 0.25
	continuous_cd = true
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.15
	physics_material_override = pm


## Construit le chargeur : maillage pris sur le pistolet du garde si possible, sinon un pavé.
static func creer(maillage: Mesh, materiau: Material, nb: int) -> ChargeurGarde:
	var c := ChargeurGarde.new()
	c.name = "Chargeur"
	c.cartouches = nb
	var mi := MeshInstance3D.new()
	var taille := Vector3(0.028, 0.125, 0.034)
	if maillage != null:
		mi.mesh = maillage
		var bb := maillage.get_aabb()
		taille = bb.size.max(Vector3.ONE * 0.02)
		mi.position = -bb.get_center()
		if materiau != null:
			mi.material_override = materiau
	else:
		var bm := BoxMesh.new()
		bm.size = taille
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.04, 0.04, 0.045)
		m.roughness = 0.5
		bm.material = m
		mi.mesh = bm
	c.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = taille
	cs.shape = sh
	c.add_child(cs)
	return c


func texte_aide() -> String:
	return tr("AIDE_CHARGEUR_GARDE") % cartouches


func interagir(joueur: Node) -> void:
	if joueur.has_method("ramasser_chargeur"):
		joueur.ramasser_chargeur(cartouches)
		queue_free()
