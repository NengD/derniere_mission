class_name RagdollGarde
extends RefCounted
## Construction du ragdoll d'un garde (squelette UE / Quaternius) : un PhysicalBone3D par grand segment
## du corps, formes mesurées sur les maillages (la corpulence de chaque garde est respectée), masses
## tirées du volume, articulations à limites anatomiques. Fournit aussi les hitboxes (Area3D, couche 4)
## de mêmes formes, qui suivent l'animation tant que le garde est vivant.
##
## Godot coupe les couches des PhysicalBone3D hors simulation : les tirs touchent donc les Area3D,
## jamais les corps physiques ; le garde transmet ensuite l'impulsion au PhysicalBone3D du même os.

const COUCHE_MONDE := 1
const COUCHE_HITBOX := 8
const DENSITE := 950.0   # kg/m³ (corps humain ≈ 985, vêtements compris)

## Segments du ragdoll : [os, forme, articulation, paramètres]
##   forme : "boite" (tronc) ou "capsule" ; articulation : "aucune", "cone" [balancement, torsion],
##   "hanche" [balancement, torsion, inclinaison vers l'avant], "charniere" [flexion min, flexion max]
##   (degrés, comptés depuis la position de repos du modèle, flexion positive = sens anatomique).
const SEGMENTS := [
	["pelvis", "boite", "aucune", []],
	["spine_01", "boite", "cone", [18.0, 14.0]],
	["spine_03", "boite", "cone", [22.0, 18.0]],
	["Head", "capsule", "cone", [32.0, 40.0]],
	["upperarm_l", "capsule", "cone", [70.0, 35.0]],
	["upperarm_r", "capsule", "cone", [70.0, 35.0]],
	["lowerarm_l", "capsule", "charniere", [-40.0, 95.0]],
	["lowerarm_r", "capsule", "charniere", [-40.0, 95.0]],
	["thigh_l", "capsule", "hanche", [62.0, 12.0, 28.0]],
	["thigh_r", "capsule", "hanche", [62.0, 12.0, 28.0]],
	["calf_l", "capsule", "charniere", [-4.0, 135.0]],
	["calf_r", "capsule", "charniere", [-4.0, 135.0]],
	["foot_l", "capsule", "cone", [22.0, 6.0]],
	["foot_r", "capsule", "cone", [22.0, 6.0]],
]

## Fin de chaque segment (os dont la tête termine le segment)
const FINS := {
	"pelvis": "spine_01", "spine_01": "spine_03", "spine_03": "neck_01",
	"upperarm_l": "lowerarm_l", "upperarm_r": "lowerarm_r",
	"lowerarm_l": "hand_l", "lowerarm_r": "hand_r",
	"thigh_l": "calf_l", "thigh_r": "calf_r", "calf_l": "foot_l", "calf_r": "foot_r",
	"foot_l": "ball_l", "foot_r": "ball_r",
}

## Part de la masse totale par segment (tables anthropométriques, main comptée avec l'avant-bras)
const FRACTIONS := {
	"pelvis": 0.14, "spine_01": 0.14, "spine_03": 0.21, "Head": 0.08, "upperarm": 0.028,
	"lowerarm": 0.022, "thigh": 0.10, "calf": 0.0465, "foot": 0.0145,
}

## Os rattachés à un segment autre que leur ancêtre le plus proche (le cou appartient à la tête)
const RATTACHES := {"neck_01": "Head"}

## Sens de la flexion des charnières : avec Jolt, l'angle de la charnière se compte dans l'autre sens que
## notre axe (vérifié par tests/tests_garde.gd : un genou ne plie que vers l'arrière, un coude vers l'avant)
static var sens_charniere := -1.0


## Résultat de la mesure d'un segment, en espace squelette au repos.
class Segment:
	var os := ""
	var idx := -1
	var forme := "capsule"
	var repere := Transform3D()      # centre et axes de la forme (Y = le long du segment)
	var taille := Vector3.ONE        # boîte : dimensions ; capsule : (rayon, hauteur, 0)
	var debut := Vector3.ZERO        # articulation (tête de l'os)
	var direction := Vector3.UP
	var longueur := 0.0
	var masse := 1.0

	func forme_physique() -> Shape3D:
		if forme == "boite":
			var b := BoxShape3D.new()
			b.size = taille
			return b
		var c := CapsuleShape3D.new()
		c.radius = taille.x
		c.height = taille.y
		return c


## Mesure tous les segments sur les maillages habillés du modèle (pose de repos).
static func mesurer(sk: Skeleton3D, maillages: Array) -> Dictionary:
	var rest := {}   # idx → Transform3D global de repos (espace squelette)
	for i in sk.get_bone_count():
		rest[i] = sk.get_bone_global_rest(i)
	# os → segment propriétaire
	var noms := {}
	for s in SEGMENTS:
		noms[s[0]] = true
	var proprio := {}
	for i in sk.get_bone_count():
		var n := sk.get_bone_name(i)
		if RATTACHES.has(n):
			proprio[i] = RATTACHES[n]
			continue
		var j := i
		while j >= 0 and not noms.has(sk.get_bone_name(j)):
			j = sk.get_bone_parent(j)
		proprio[i] = sk.get_bone_name(j) if j >= 0 else ""
	# sommets regroupés par segment (poids dominant)
	var points := {}
	for s in SEGMENTS:
		points[s[0]] = PackedVector3Array()
	for mi in maillages:
		var m := mi as MeshInstance3D
		if m == null or m.mesh == null or m.skin == null:
			continue
		var skin := m.skin
		var bind_os := PackedInt32Array()
		for b in skin.get_bind_count():
			var nom := skin.get_bind_name(b)
			bind_os.append(sk.find_bone(nom) if nom != "" else skin.get_bind_bone(b))
		for surf in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(surf)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bs = arr[Mesh.ARRAY_BONES]
			var ws = arr[Mesh.ARRAY_WEIGHTS]
			if bs == null or ws == null or vs.is_empty():
				continue
			var par := int(bs.size() / vs.size())
			# un sommet sur deux suffit à la mesure
			for v in range(0, vs.size(), 2):
				var meilleur := 0
				var wmax := -1.0
				for k in par:
					if ws[v * par + k] > wmax:
						wmax = ws[v * par + k]
						meilleur = int(bs[v * par + k])
				if meilleur >= bind_os.size():
					continue
				var o := bind_os[meilleur]
				if o < 0:
					continue
				var seg: String = proprio.get(o, "")
				if seg == "":
					continue
				var p: Vector3 = rest[o] * (skin.get_bind_pose(meilleur) * vs[v])
				points[seg].append(p)
	var res := {}
	var volume := 0.0
	for s in SEGMENTS:
		res[s[0]] = _segment(sk, rest, s[0], s[1], points[s[0]])
		volume += _volume(res[s[0]])
	# masse totale tirée du volume (les formes débordent du corps : ×0,62), répartie selon les tables
	# anthropométriques : la corpulence change le poids, pas les proportions
	var total: float = clamp(volume * DENSITE * 0.62, 55.0, 120.0)
	for k in res:
		(res[k] as Segment).masse = total * FRACTIONS[k.trim_suffix("_l").trim_suffix("_r")]
	return res


static func _segment(sk: Skeleton3D, rest: Dictionary, nom: String, forme: String, pts: PackedVector3Array) -> Segment:
	var g := Segment.new()
	g.os = nom
	g.idx = sk.find_bone(nom)
	g.forme = forme
	var t: Transform3D = rest[g.idx]
	var debut := t.origin
	var fin: Vector3
	if nom == "Head":
		fin = debut + t.basis.y.normalized() * 0.2
		debut = debut - t.basis.y.normalized() * 0.07   # couvre le cou
	else:
		fin = (rest[sk.find_bone(FINS[nom])] as Transform3D).origin
		if nom.begins_with("lowerarm"):
			fin += (fin - debut).normalized() * 0.1     # jusqu'au bout de la main
		elif nom.begins_with("foot"):
			fin += (fin - debut).normalized() * 0.05
	g.debut = t.origin
	var d := fin - debut
	g.longueur = d.length()
	g.direction = d / max(g.longueur, 0.001)
	# repère : Y le long du segment, X vers la droite du personnage (X du monde au repos), Z vers l'avant
	var x := Vector3.RIGHT - g.direction * g.direction.dot(Vector3.RIGHT)
	if x.length() < 0.2:
		x = Vector3.FORWARD.cross(g.direction)
	x = x.normalized()
	var z := x.cross(g.direction).normalized()
	var b := Basis(x, g.direction, z)
	if forme == "boite":
		var xs: Array[float] = []
		var ys: Array[float] = []
		var zs: Array[float] = []
		for p in pts:
			var l: Vector3 = b.transposed() * (p - debut)
			xs.append(l.x)
			ys.append(l.y)
			zs.append(l.z)
		var mn := Vector3(_centile(xs, 0.04), _centile(ys, 0.03), _centile(zs, 0.05))
		var mx := Vector3(_centile(xs, 0.96), _centile(ys, 0.97), _centile(zs, 0.95))
		if pts.size() < 20:
			mn = Vector3(-0.15, 0.0, -0.1)
			mx = Vector3(0.15, g.longueur, 0.1)
		# le tronc ne descend pas sous la hanche ni ne monte au-dessus de son os de fin
		mn.y = max(mn.y, -0.14)
		mx.y = min(max(mx.y, g.longueur), g.longueur + 0.05)
		g.taille = (mx - mn).clamp(Vector3(0.12, 0.06, 0.1), Vector3(0.6, 0.6, 0.45))
		g.repere = Transform3D(b, debut + b * ((mn + mx) * 0.5))
	else:
		var ds: Array[float] = []
		for p in pts:
			var v := p - debut
			var u := v.dot(g.direction)
			if u < -0.02 or u > g.longueur + 0.02:
				continue
			ds.append((v - g.direction * u).length())
		var r := _centile(ds, 0.72) if ds.size() >= 12 else 0.06
		var rmax := 0.13 if nom == "Head" else 0.2
		r = clamp(r, 0.035, rmax)
		if nom == "Head":
			r = clamp(r, 0.085, 0.13)
		g.taille = Vector3(r, max(g.longueur + r, 2.0 * r + 0.01), 0.0)
		g.repere = Transform3D(b, debut + g.direction * (g.longueur * 0.5))
	return g


static func _volume(g: Segment) -> float:
	if g.forme == "boite":
		return g.taille.x * g.taille.y * g.taille.z
	var r := g.taille.x
	var h: float = max(g.taille.y - 2.0 * r, 0.0)
	return PI * r * r * h + 4.0 / 3.0 * PI * r * r * r


static func _centile(v: Array[float], q: float) -> float:
	if v.is_empty():
		return 0.0
	var c := v.duplicate()
	c.sort()
	return c[clamp(int(q * (c.size() - 1)), 0, c.size() - 1)]


## Crée le simulateur et les PhysicalBone3D. Le squelette doit être en pose de repos (les repères des
## articulations sont pris maintenant : les limites se comptent depuis le repos, pas depuis la pose de la mort).
static func construire(sk: Skeleton3D, segments: Dictionary) -> PhysicalBoneSimulator3D:
	var sim := PhysicalBoneSimulator3D.new()
	sim.name = "Ragdoll"
	sk.add_child(sim)
	var corps := {}
	for s in SEGMENTS:
		var g: Segment = segments[s[0]]
		var pb := PhysicalBone3D.new()
		pb.name = "pb_" + g.os
		pb.set("bone_name", g.os)
		var rest := sk.get_bone_global_rest(g.idx)
		pb.body_offset = rest.affine_inverse() * g.repere
		pb.mass = g.masse
		pb.friction = 0.85
		pb.bounce = 0.0
		pb.linear_damp = 0.15
		pb.angular_damp = 2.2 if g.os.begins_with("spine") or g.os == "pelvis" else 1.4
		pb.collision_layer = 0          # ni le joueur ni les tirs : seulement le monde
		pb.collision_mask = COUCHE_MONDE
		var cs := CollisionShape3D.new()
		cs.shape = g.forme_physique()
		pb.add_child(cs)
		sim.add_child(pb)
		pb.global_transform = sk.global_transform * g.repere
		corps[g.os] = pb
	# articulations (après que tous les corps sont placés au repos)
	for s in SEGMENTS:
		if s[2] == "aucune":
			continue
		var g: Segment = segments[s[0]]
		var pb: PhysicalBone3D = corps[g.os]
		var p: Array = s[3]
		var j: Basis
		if s[2] == "charniere":
			var axe := _axe_charniere(sk, g)
			j = Basis(g.direction, axe.cross(g.direction).normalized(), axe)
		else:
			# torsion autour de X : X le long du segment
			var lat: Vector3 = g.repere.basis.x
			j = Basis(g.direction, lat.cross(g.direction).normalized(), lat)
		var jt := Transform3D(j.orthonormalized(), g.debut)
		pb.joint_offset = g.repere.affine_inverse() * jt
		var garde := Transform3D()
		if s[2] == "hanche":
			# le cône de la hanche est penché vers l'avant : on crée l'articulation cuisse levée
			garde = pb.global_transform
			var avant := Vector3.BACK - g.direction * g.direction.dot(Vector3.BACK)
			var axe_h := g.direction.cross(avant.normalized()).normalized()
			var piv := sk.global_transform * g.debut
			var rot := Basis((sk.global_basis * axe_h).normalized(), deg_to_rad(p[2]))
			pb.global_transform = Transform3D(rot * pb.global_basis, piv + rot * (pb.global_position - piv))
		match s[2]:
			"cone", "hanche":
				pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
				pb.set("joint_constraints/swing_span", p[0])
				pb.set("joint_constraints/twist_span", p[1])
				pb.set("joint_constraints/bias", 0.3)
				pb.set("joint_constraints/softness", 0.8)
				pb.set("joint_constraints/relaxation", 1.0)
			"charniere":
				pb.joint_type = PhysicalBone3D.JOINT_TYPE_HINGE
				var lo: float = p[0] * sens_charniere
				var hi: float = p[1] * sens_charniere
				pb.set("joint_constraints/angular_limit_enabled", true)
				pb.set("joint_constraints/angular_limit_lower", min(lo, hi))
				pb.set("joint_constraints/angular_limit_upper", max(lo, hi))
				pb.set("joint_constraints/angular_limit_bias", 0.3)
				pb.set("joint_constraints/angular_limit_softness", 0.9)
				pb.set("joint_constraints/angular_limit_relaxation", 1.0)
		if s[2] == "hanche":
			pb.global_transform = garde
	return sim


## Axe de flexion d'une charnière : rotation positive = flexion anatomique (genou vers l'arrière,
## coude vers l'avant / l'intérieur), à partir de la pose de repos.
static func _axe_charniere(sk: Skeleton3D, g: Segment) -> Vector3:
	var parent := sk.get_bone_parent(g.idx)
	var dp: Vector3 = (sk.get_bone_global_rest(g.idx).origin - sk.get_bone_global_rest(parent).origin).normalized()
	var plie: Vector3
	if g.os.begins_with("calf"):
		plie = Vector3.FORWARD      # le pied part vers l'arrière (le personnage regarde +Z)
	else:
		plie = Vector3.BACK         # l'avant-bras vient vers l'avant
		var a := dp.cross(g.direction)
		if a.length() > 0.3:        # avant-bras déjà plié au repos : le plan de flexion est connu
			return a.normalized()
	var p := plie - dp * dp.dot(plie)
	return dp.cross(p.normalized()).normalized()


## Hitboxes (Area3D, couche 4) : mêmes formes, méta « os ». Enfants directs du garde (le tir les remonte
## jusqu'à recevoir_tir), en coordonnées globales : le garde les replace à chaque image physique.
static func hitboxes(garde: Node3D, segments: Dictionary, sim: PhysicalBoneSimulator3D) -> Array:
	var res := []
	for s in SEGMENTS:
		var g: Segment = segments[s[0]]
		var a := Area3D.new()
		a.name = "hb_" + g.os
		a.collision_layer = COUCHE_HITBOX
		a.collision_mask = 0
		a.monitoring = false
		a.monitorable = false
		a.top_level = true
		a.set_meta("os", g.os)
		var cs := CollisionShape3D.new()
		var pb := sim.get_node("pb_" + g.os) as PhysicalBone3D
		cs.shape = (pb.get_child(0) as CollisionShape3D).shape
		a.add_child(cs)
		garde.add_child(a)
		res.append({"zone": a, "idx": g.idx, "offset": pb.body_offset, "pb": pb, "os": g.os})
	return res
