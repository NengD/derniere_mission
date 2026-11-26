class_name BrasIK
extends SkeletonModifier3D
## Corps du joueur à la première personne, appliqué par-dessus l'animation des jambes :
## - cache la tête (la caméra est dans les yeux),
## - plie le buste selon le regard (tangage) et l'inclinaison (se pencher),
## - place les deux mains par IK à deux os sur des cibles (poignée de l'arme, chargeur…),
##   coude en charnière sur l'axe X local du bras (convention UE / UAL), torsion répartie sur l'avant-bras,
## - referme les doigts (index sur la détente).
## Squelette façon UE : upperarm_r, lowerarm_r, hand_r, index_01_r…, Head, spine_01..03.

## cibles en coordonnées globales (origine = poignet, axes : X dos de la main droite /
## paume de la main gauche, Y vers les doigts, Z vers le pouce)
var cible_d := Transform3D.IDENTITY
var cible_g := Transform3D.IDENTITY
var pole_d := Vector3.ZERO           # point global vers lequel pointe le coude droit
var pole_g := Vector3.ZERO
var actif_d := false
var actif_g := false
var tangage := 0.0                   # radians, positif = regard vers le haut
var part_tangage := 0.45             # part du tangage reprise par le buste
var roulis := 0.0                    # radians, positif = penché à droite
var equerre := 1.0                   # part de la torsion des épaules corrigée
## milieu des épaules après modification (global), lu par le joueur pour recaler le corps
var epaules := Vector3.ZERO
var epaules_valides := false
var cacher_tete := true
## mains MakeHuman un peu grandes (≈ 20 cm du poignet au bout du majeur) → ≈ 19 cm, taille d'une main d'homme
var echelle_mains := 0.95
var axe_doigts := Vector3(0, 0, 1)   # axe de flexion des phalanges (repère local de l'os)
## Doigts posés à partir de la pose de repos (l'animation tient le pistolet main ouverte, doigts écartés :
## « griffes ») : doigts rapprochés (écart de repos annulé), puis fléchis.
## flexion de chaque doigt (0 = tendu, 1 = serré autour de la poignée), main droite puis gauche
var doigts_d := {"index": 0.0, "middle": 1.0, "ring": 1.05, "pinky": 1.1, "thumb": 1.0}
var doigts_g := {"index": 0.9, "middle": 0.95, "ring": 1.0, "pinky": 1.05, "thumb": 1.0}
## index droit : 0 = tendu le long de la carcasse au-dessus du pontet, 1 = sur la détente
var detente := 0.0

## angles de flexion des phalanges 01, 02, 03 pour une flexion de 1 (degrés)
const ANGLES := {"01": 62.0, "02": 78.0, "03": 42.0}
## index droit le long de la carcasse / sur la détente
const INDEX_LONG := {"01": 8.0, "02": 6.0, "03": 4.0}
const INDEX_DETENTE := {"01": 38.0, "02": 52.0, "03": 22.0}
## pouces (flexion des trois phalanges, degrés ; « ouv » = écartement de la première autour de son axe X)
## droit : allongé sur le flanc gauche de la carcasse, pointé vers l'avant (prise pouces en avant) ;
## gauche : à plat sur le flanc, sous la glissière, pointé vers l'avant
## première phalange : rotations x, y, z (degrés, repère local de l'os, appliquées sur la pose de repos)
var pouce_d := {"x": 0.0, "y": 0.0, "z": 40.0, "02": 4.0, "03": 2.0}
var pouce_g := {"x": 0.0, "y": 0.0, "z": 0.0, "02": -4.0, "03": 0.0}

var _ecart := {}

var _os := {}


func _os_i(nom: String) -> int:
	if not _os.has(nom):
		_os[nom] = get_skeleton().find_bone(nom)
	return _os[nom]


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if cacher_tete:
		for n in ["Head", "neck_01"]:
			var h := _os_i(n)
			if h >= 0:
				sk.set_bone_pose_scale(h, Vector3.ONE * 0.001)
	_buste(sk)
	var el := _os_i("upperarm_l")
	var er := _os_i("upperarm_r")
	if el >= 0 and er >= 0:
		epaules = sk.global_transform * ((sk.get_bone_global_pose(el).origin + sk.get_bone_global_pose(er).origin) * 0.5)
		epaules_valides = true
	var inv := sk.global_transform.affine_inverse()
	if actif_d:
		_epaule(sk, "r", inv * cible_d)
		_bras(sk, "r", inv * cible_d, inv * pole_d)
	if actif_g:
		_epaule(sk, "l", inv * cible_g)
		_bras(sk, "l", inv * cible_g, inv * pole_g)
	_doigts(sk, "r", doigts_d)
	_doigts(sk, "l", doigts_g)


## Le modèle regarde vers +Z dans le repère du squelette : regarder en bas = rotation autour de +X,
## se pencher à droite (vers -X) = rotation autour de +Z.
func _buste(sk: Skeleton3D) -> void:
	var noms := ["spine_01", "spine_02", "spine_03"]
	# vers le bas, le buste plie peu (sinon la poitrine passe sous la caméra)
	var part := part_tangage if tangage > 0.0 else part_tangage * 0.35
	var r := Basis(Vector3.RIGHT, -tangage * part / 3.0) * Basis(Vector3.BACK, roulis / 3.0)
	for n in noms:
		var i := _os_i(n)
		if i < 0:
			continue
		var gp := sk.get_bone_global_pose(i)
		sk.set_bone_global_pose(i, Transform3D(r * gp.basis, gp.origin))
	# épaules d'équerre face à l'arme (les animations libres tiennent le buste de biais)
	var i3 := _os_i("spine_03")
	var el := _os_i("upperarm_l")
	var er := _os_i("upperarm_r")
	if i3 >= 0 and el >= 0 and er >= 0:
		var v := sk.get_bone_global_pose(el).origin - sk.get_bone_global_pose(er).origin
		var ang := atan2(v.z, v.x)
		var gp := sk.get_bone_global_pose(i3)
		sk.set_bone_global_pose(i3, Transform3D(Basis(Vector3.UP, ang * equerre) * gp.basis, gp.origin))


## Épaule avancée (protraction de la clavicule) quand la main est loin : bras tendus vers l'arme,
## l'épaule suit au lieu de laisser le poignet décroché de sa cible.
func _epaule(sk: Skeleton3D, cote: String, cible: Transform3D) -> void:
	var ic := _os_i("clavicle_" + cote)
	var iu := _os_i("upperarm_" + cote)
	var il := _os_i("lowerarm_" + cote)
	var ih := _os_i("hand_" + cote)
	if ic < 0 or iu < 0 or il < 0 or ih < 0:
		return
	var gc := sk.get_bone_global_pose(ic)
	var s := sk.get_bone_global_pose(iu).origin
	var portee := s.distance_to(sk.get_bone_global_pose(il).origin) + sk.get_bone_global_pose(il).origin.distance_to(sk.get_bone_global_pose(ih).origin)
	var exces := s.distance_to(cible.origin) - portee * 0.985
	if exces <= 0.0:
		return
	var v := s - gc.origin
	var w := cible.origin - gc.origin
	var axe := v.cross(w)
	if axe.length() < 1e-5:
		return
	# angle qui rapproche l'épaule de la cible d'environ l'excès (plafonné à 28°)
	var ang: float = min(exces / max(v.length(), 0.05), deg_to_rad(28.0))
	ang = min(ang, v.angle_to(w))
	sk.set_bone_global_pose(ic, Transform3D(Basis(axe.normalized(), ang) * gc.basis, gc.origin))


func _bras(sk: Skeleton3D, cote: String, cible: Transform3D, pole: Vector3) -> void:
	var iu := _os_i("upperarm_" + cote)
	var il := _os_i("lowerarm_" + cote)
	var ih := _os_i("hand_" + cote)
	if iu < 0 or il < 0 or ih < 0:
		return
	var gu := sk.get_bone_global_pose(iu)
	var gl := sk.get_bone_global_pose(il)
	var gh := sk.get_bone_global_pose(ih)
	var s := gu.origin
	var a := gu.origin.distance_to(gl.origin)
	var b := gl.origin.distance_to(gh.origin)
	var vers := cible.origin - s
	var d: float = clamp(vers.length(), 0.05, (a + b) * 0.999)
	var dir := vers.normalized()
	var cos_a: float = clamp((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var sin_a := sqrt(1.0 - cos_a * cos_a)
	var p := pole - s
	var pn := (p - dir * p.dot(dir))
	if pn.length() < 0.0001:
		pn = Vector3.DOWN - dir * Vector3.DOWN.dot(dir)
	pn = pn.normalized()
	var coude := s + dir * (a * cos_a) + pn * (a * sin_a)
	var main := s + dir * d
	# bras : Y vers le coude, charnière = X local, l'avant-bras plie vers +Z local
	var y_u := (coude - s).normalized()
	var f := (main - coude).normalized()
	var z_u := f - y_u * f.dot(y_u)
	if z_u.length() < 0.001:
		z_u = -pn
	z_u = z_u.normalized()
	var x_u := y_u.cross(z_u).normalized()
	var bu := Basis(x_u, y_u, z_u)
	sk.set_bone_global_pose(iu, Transform3D(bu.scaled_local(gu.basis.get_scale()), s))
	# avant-bras : même charnière, torsion vers la main répartie à moitié
	var z_l := x_u.cross(f).normalized()
	var bl := Basis(x_u, f, z_l)
	var xh := cible.basis.x.normalized()
	var xh_p := (xh - f * xh.dot(f))
	if xh_p.length() > 0.001:
		var tw := x_u.signed_angle_to(xh_p.normalized(), f)
		bl = Basis(f, tw * 0.5) * bl
	sk.set_bone_global_pose(il, Transform3D(bl.scaled_local(gl.basis.get_scale()), coude))
	var o := sk.get_bone_global_pose(ih).origin
	sk.set_bone_global_pose(ih, Transform3D(cible.basis.orthonormalized().scaled_local(gh.basis.get_scale() * echelle_mains), o))


## Écart de repos de chaque doigt par rapport au majeur, autour de l'axe X local de la phalange 01.
func _ecart_repos(sk: Skeleton3D, f: String, cote: String) -> float:
	var cle := f + cote
	if _ecart.has(cle):
		return _ecart[cle]
	var a := 0.0
	var i := _os_i("%s_01_%s" % [f, cote])
	var m := _os_i("middle_01_" + cote)
	if i >= 0 and m >= 0 and f != "middle":
		var bf := sk.get_bone_global_rest(i).basis.orthonormalized()
		var dm := sk.get_bone_global_rest(m).basis.y.normalized()
		var l := bf.inverse() * dm
		a = atan2(l.z, l.y)
	_ecart[cle] = a
	return a


func _doigts(sk: Skeleton3D, cote: String, flex: Dictionary) -> void:
	for f in ["index", "middle", "ring", "pinky"]:
		var c: float = flex.get(f, 1.0)
		var ecart := _ecart_repos(sk, f, cote) * 0.85
		for k in ANGLES:
			var i := _os_i("%s_%s_%s" % [f, k, cote])
			if i < 0:
				continue
			var ang: float = ANGLES[k] * c
			if f == "index" and cote == "r":
				ang = lerp(float(INDEX_LONG[k]), float(INDEX_DETENTE[k]), detente)
			var q := sk.get_bone_rest(i).basis.get_rotation_quaternion()
			if k == "01":
				q = q * Quaternion(Vector3.RIGHT, ecart)
			sk.set_bone_pose_rotation(i, q * Quaternion(axe_doigts, deg_to_rad(ang)))
	var pc: Dictionary = pouce_d if cote == "r" else pouce_g
	var cp: float = flex.get("thumb", 1.0)
	for k in ["01", "02", "03"]:
		var i := _os_i("thumb_%s_%s" % [k, cote])
		if i < 0:
			continue
		var q := sk.get_bone_rest(i).basis.get_rotation_quaternion()
		if k == "01":
			q = q * Quaternion.from_euler(Vector3(deg_to_rad(float(pc["x"])), deg_to_rad(float(pc["y"])), deg_to_rad(float(pc["z"]) * cp)))
		else:
			q = q * Quaternion(axe_doigts, deg_to_rad(float(pc[k]) * cp))
		sk.set_bone_pose_rotation(i, q)
