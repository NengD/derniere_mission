class_name BlessureGarde
extends SkeletonModifier3D
## Réactions procédurales d'un garde vivant, par-dessus l'animation :
## - secousse de l'os touché (et, atténuée, de ses parents) dans la direction du tir ;
## - bras blessé qui retombe le long du corps.

const DUREE_SECOUSSE := 0.45

## secousses en cours : {idx, axe (espace squelette), angle (rad), t}
var _secousses: Array = []
## poids du bras ballant visé / courant, par côté
var bras_cible := {"l": 0.0, "r": 0.0}
var _bras := {"l": 0.0, "r": 0.0}
var _repos := {}   # idx → rotation de repos


func _ready() -> void:
	process_priority = -1


func _process(delta: float) -> void:
	for s in _secousses:
		s["t"] += delta
	_secousses = _secousses.filter(func(s: Dictionary) -> bool: return s["t"] < DUREE_SECOUSSE)
	for c in _bras:
		_bras[c] = move_toward(_bras[c], bras_cible[c], delta * 2.8)


## Secoue l'os touché : `direction` = direction du tir (monde), `force` en degrés.
func secouer(os: String, direction: Vector3, force: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	var i := sk.find_bone(os)
	var attenue := 1.0
	var n := 0
	while i >= 0 and n < 4:
		var g := sk.get_bone_global_pose(i)
		var dir_sk := (sk.global_basis.inverse() * direction).normalized()
		var axe := g.basis.y.normalized().cross(dir_sk)
		if axe.length() > 0.05:
			_secousses.append({"idx": i, "axe": axe.normalized(), "angle": deg_to_rad(force * attenue), "t": 0.0})
		i = sk.get_bone_parent(i)
		attenue *= 0.45
		n += 1


func laisser_tomber_bras(cote: String) -> void:
	bras_cible[cote] = 0.85


func _enveloppe(t: float) -> float:
	# montée en 50 ms, retour amorti
	if t < 0.05:
		return t / 0.05
	return exp(-(t - 0.05) * 8.0) * cos((t - 0.05) * 9.0)


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	# bras ballants : retour vers la pose de repos (bras pendants) des os du bras
	for c in _bras:
		var w: float = _bras[c]
		if w <= 0.001:
			continue
		for nom in ["upperarm_", "lowerarm_", "hand_"]:
			var i := sk.find_bone(nom + c)
			if i < 0:
				continue
			if not _repos.has(i):
				_repos[i] = sk.get_bone_rest(i).basis.get_rotation_quaternion()
			var q := sk.get_bone_pose_rotation(i)
			sk.set_bone_pose_rotation(i, q.slerp(_repos[i], w * (1.0 if nom == "upperarm_" else 0.7)))
	# secousses : rotation (espace squelette) appliquée à l'os dans l'espace de son parent
	for s in _secousses:
		var i: int = s["idx"]
		var ang: float = s["angle"] * _enveloppe(s["t"])
		var parent := sk.get_bone_parent(i)
		var axe: Vector3 = s["axe"]
		if parent >= 0:
			axe = (sk.get_bone_global_pose(parent).basis.orthonormalized().inverse() * axe).normalized()
		var q := sk.get_bone_pose_rotation(i)
		sk.set_bone_pose_rotation(i, Quaternion(axe, ang) * q)
