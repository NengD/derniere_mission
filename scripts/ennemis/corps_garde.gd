class_name CorpsGarde
extends CharacterBody3D
## Corps d'un garde du cartel (sans IA) : modèle MPFB, pistolet en main, hitboxes par os, dégâts
## localisés, réactions (sursaut, bras touché, chute à la jambe) et mort en ragdoll physique qui
## garde l'élan du mouvement et l'impulsion de la balle : aucune mort ne ressemble à une autre.
##
## Interface :
##   recevoir_tir(degats, os_ou_zone, point, normale, direction, tireur)   (degats AVANT multiplicateur)
##   signaux : mort(garde), touche(garde, zone, degats, reaction)
##   marcher(vitesse_monde) / arreter() : déplacement simple (l'IA le pilotera plus tard)
##   jouer(animation) ; vivant, a_terre, pv, bras_blesse
## Couches : capsule de déplacement 3 (ennemis), hitboxes 4 (Area3D), ragdoll → monde seulement.

signal mort(garde: CorpsGarde)
signal touche(garde: CorpsGarde, zone: int, degats: float, reaction: int)

const COUCHE_MONDE := 1
const COUCHE_ENNEMIS := 4
const DOSSIER := "res://assets/characters/gardes/"
const SONS := "res://assets/sons/"
## impulsion (N·s) par point de dégât brut de la balle
const IMPULSION_PAR_DEGAT := 0.16
const IMPULSION_MAX := 16.0

## corps morts présents (du plus ancien au plus récent), pour la limite « limite_corps »
static var corps_morts: Array = []

@export var variante := "garde_1"
@export var animation := "Pistol_Idle"
@export var arme := true
@export var graine := 0

var pv := Degats.PV_MAX
var vivant := true
var a_terre := false
var bras_blesse := {"l": false, "r": false}
var vitesse_marche := Vector3.ZERO

var modele: Node3D
var squelette: Skeleton3D
var anim: AnimationPlayer
var ragdoll: PhysicalBoneSimulator3D
var blessure: BlessureGarde
var pistolet: Node3D
var segments := {}
var _hitboxes: Array = []
var _rng := RandomNumberGenerator.new()
var _prec := {}             # os → position globale de la hitbox à l'image précédente (élan)
var _vitesses := {}         # os → vitesse estimée (m/s)
var _t_mort := 0.0
var _chute_jouee := false
var _vy_prec := 0.0
var _endormi := false
var _impulsions: Array = []  # appliquées à l'image physique suivant le début de la simulation
var _anim_courante := ""
var _capsule: CollisionShape3D


func _ready() -> void:
	if graine != 0:
		_rng.seed = graine
	else:
		_rng.randomize()
	add_to_group("gardes")
	collision_layer = COUCHE_ENNEMIS
	collision_mask = COUCHE_MONDE
	_capsule = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = 1.75
	_capsule.shape = cap
	_capsule.position.y = 0.875
	add_child(_capsule)
	var chemin := DOSSIER + variante + ".glb"
	if not ResourceLoader.exists(chemin):
		push_error("Garde introuvable : " + chemin)
		return
	var scene := load(chemin) as PackedScene
	if scene == null:
		push_error("Garde illisible : " + chemin)
		return
	modele = scene.instantiate()
	modele.name = "Modele"
	add_child(modele)
	squelette = modele.find_children("*", "Skeleton3D", true, false)[0]
	anim = modele.find_children("*", "AnimationPlayer", true, false)[0]
	anim.playback_default_blend_time = 0.2
	for n in ["Pistol_Idle", "Pistol_Aim_Neutral", "Walk", "Idle", "Jog_Fwd", "Crouch_Idle"]:
		if anim.has_animation(n):
			anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	# ragdoll et hitboxes construits en pose de repos (limites des articulations comptées depuis le repos)
	squelette.reset_bone_poses()
	segments = RagdollGarde.mesurer(squelette, squelette.find_children("*", "MeshInstance3D", true, false))
	var fc := FingerCurl.new()
	fc.axis = Vector3(0, 0, 1)
	fc.sides = PackedStringArray(["r"] if arme else ["r", "l"])
	squelette.add_child(fc)
	blessure = BlessureGarde.new()
	squelette.add_child(blessure)
	ragdoll = RagdollGarde.construire(squelette, segments)
	_hitboxes = RagdollGarde.hitboxes(self, segments, ragdoll)
	cap.height = clamp(squelette.get_bone_global_rest(squelette.find_bone("Head")).origin.y + 0.2, 1.5, 1.95)
	_capsule.position.y = cap.height * 0.5
	if arme:
		_armer()
	jouer(animation)
	_placer_hitboxes(0.0)


## Prend le pistolet en main : pose de visée appliquée tout de suite, arme calée entre la paume et le
## majeur (même calcul que l'aperçu des gardes), puis l'animation demandée.
func _armer() -> void:
	anim.play("Pistol_Aim_Neutral")
	anim.seek(0.0, true)
	var ba := BoneAttachment3D.new()
	ba.name = "MainDroite"
	ba.bone_name = "hand_r"
	squelette.add_child(ba)
	pistolet = (load("res://assets/weapons/pistolet.glb") as PackedScene).instantiate()
	pistolet.name = "Pistolet"
	ba.add_child(pistolet)
	var sk_t := squelette.global_transform
	var main := sk_t * squelette.get_bone_global_pose(squelette.find_bone("hand_r"))
	var milieu := sk_t * squelette.get_bone_global_pose(squelette.find_bone("middle_01_r"))
	var avant: Vector3 = global_basis.z.normalized()
	var droite := Vector3.UP.cross(-avant).normalized()
	var b := Basis(droite, Vector3.UP, -avant).orthonormalized().rotated(droite, deg_to_rad(-4))
	var cible := Transform3D(b, main.origin.lerp(milieu.origin, 0.55) + Vector3.DOWN * 0.035)
	# l'attache n'est pas encore à jour : position relative à la main calculée à la main
	pistolet.transform = main.affine_inverse() * cible


func jouer(nom: String, fondu := 0.25) -> void:
	if anim == null or not anim.has_animation(nom):
		return
	_anim_courante = nom
	anim.play(nom, fondu)
	if anim.get_animation(nom).loop_mode != Animation.LOOP_NONE:
		anim.seek(_rng.randf() * anim.get_animation(nom).length, false)


func marcher(vitesse: Vector3) -> void:
	if not vivant or a_terre:
		return
	vitesse_marche = Vector3(vitesse.x, 0.0, vitesse.z)
	if vitesse_marche.length() > 0.05:
		look_at(global_position - vitesse_marche, Vector3.UP)   # le modèle regarde +Z
		jouer("Jog_Fwd" if vitesse_marche.length() > 2.5 else "Walk", 0.3)


func arreter() -> void:
	vitesse_marche = Vector3.ZERO
	if vivant and not a_terre:
		jouer(animation, 0.3)


# ---------------------------------------------------------------- dégâts

## Dégâts finaux d'une balle selon l'os touché (logique pure, testée).
static func degats_pour(degats: float, os_ou_zone) -> float:
	return degats * Degats.MULTIPLICATEUR[zone_de(os_ou_zone)]


static func zone_de(os_ou_zone) -> int:
	if os_ou_zone is int:
		return os_ou_zone
	var s := str(os_ou_zone)
	match s.to_lower():
		"tete":
			return Degats.Zone.TETE
		"bras":
			return Degats.Zone.BRAS
		"jambe":
			return Degats.Zone.JAMBE
	return Degats.zone_depuis_os(s)


## Nombre de corps à retirer pour respecter la limite (logique pure, testée).
static func corps_en_trop(nb: int, limite: int) -> int:
	return max(0, nb - max(limite, 1))


## Impulsion d'une balle (N·s) : proportionnelle aux dégâts bruts, ±25 % au hasard.
static func impulsion(degats: float, alea: float) -> float:
	return min(degats * IMPULSION_PAR_DEGAT, IMPULSION_MAX) * (0.75 + 0.5 * alea)


func recevoir_tir(degats: float, os_ou_zone, point: Vector3, normale: Vector3, direction: Vector3, tireur: Node) -> void:
	if modele == null:
		return
	var dir := direction.normalized() if direction.length() > 0.01 else -global_basis.z
	var os := _os_depuis(os_ou_zone, point)
	var zone := zone_de(os_ou_zone if os == "" else os)
	FxSang.impact(get_parent(), point, normale, dir, 1.4 if zone == Degats.Zone.TETE else 1.0)
	_son("impact_chair_%d" % _rng.randi_range(1, 3), point, -2.0)
	if not vivant:
		# corps déjà à terre : la balle le bouscule encore
		_endormi = false
		_impulsions.append([os, point, dir * impulsion(degats, _rng.randf()) * 0.6])
		return
	var finaux := degats_pour(degats, zone)
	pv -= finaux
	var r := Degats.reaction(zone, pv, a_terre)
	touche.emit(self, zone, finaux, r)
	match r:
		Degats.Reaction.MORT:
			_mourir(os, point, dir, degats, tireur)
		Degats.Reaction.CHUTE:
			_chuter(os, dir)
		Degats.Reaction.BRAS_TOUCHE:
			var cote := "l" if os.ends_with("_l") else "r"
			bras_blesse[cote] = true
			blessure.secouer(os, dir, 26.0)
			blessure.laisser_tomber_bras(cote)
			_douleur()
		_:
			_sursaut(os, dir)


## Os touché : celui de la hitbox, sinon le segment le plus proche du point d'impact.
func _os_depuis(os_ou_zone, point: Vector3) -> String:
	var s := str(os_ou_zone)
	if segments.has(s):
		return s
	if squelette != null and squelette.find_bone(s) >= 0:
		# os non simulé (main, doigt, clavicule…) : son segment parent
		var i := squelette.find_bone(s)
		while i >= 0 and not segments.has(squelette.get_bone_name(i)):
			i = squelette.get_bone_parent(i)
		if i >= 0:
			return squelette.get_bone_name(i)
	var meilleur := ""
	var dmin := INF
	for h in _hitboxes:
		var d := (h["zone"] as Node3D).global_position.distance_to(point)
		if d < dmin:
			dmin = d
			meilleur = h["os"]
	return meilleur


func _sursaut(os: String, dir: Vector3) -> void:
	blessure.secouer(os, dir, _rng.randf_range(18.0, 28.0))
	if not a_terre:
		vitesse_marche = Vector3.ZERO
		var n := "Hit_Head" if Degats.zone_depuis_os(os) == Degats.Zone.TETE else "Hit_Chest"
		if anim.has_animation(n):
			anim.play(n, 0.06)
			anim.queue(animation)
			_anim_courante = animation
	_douleur()


## Balle dans la jambe : le garde s'effondre et reste au sol, assis, vivant.
func _chuter(os: String, dir: Vector3) -> void:
	a_terre = true
	vitesse_marche = Vector3.ZERO
	blessure.secouer(os, dir, 20.0)
	anim.play("Death01", 0.08, 1.15)
	var arret := 0.85 + _rng.randf_range(-0.04, 0.04)
	get_tree().create_timer(arret / 1.15, false).timeout.connect(func() -> void:
		if vivant and is_instance_valid(anim):
			anim.pause())
	(_capsule.shape as CapsuleShape3D).height = 1.0
	_capsule.position.y = 0.5
	_son("cri", global_position + Vector3.UP, -6.0, _rng.randf_range(0.9, 1.05))
	get_tree().create_timer(0.75, false).timeout.connect(func() -> void:
		if is_instance_valid(self):
			_son("chute_corps", global_position + Vector3.UP * 0.3, -8.0))


func _douleur() -> void:
	_son("douleur_%d" % _rng.randi_range(1, 4), global_position + Vector3.UP * 1.6, -4.0, _rng.randf_range(0.92, 1.08))


# ---------------------------------------------------------------- mort et ragdoll

func _mourir(os: String, point: Vector3, dir: Vector3, degats: float, tireur: Node) -> void:
	vivant = false
	_t_mort = 0.0
	_capsule.set_deferred("disabled", true)
	blessure.active = false
	# élan : vitesse de chaque segment à l'instant de la mort (marche, sursaut, chute…)
	var elan := {}
	for h in _hitboxes:
		var v: Vector3 = _vitesses.get(h["os"], Vector3.ZERO) + velocity
		elan[h["os"]] = v.limit_length(4.0)
	# la tête part vers l'arrière, le reste du corps se plie : quelques variations au hasard
	ragdoll.physical_bones_start_simulation()
	# bref mélange animation → physique : la pose tient encore un instant (pas de pantin dès la 1re image)
	ragdoll.influence = 0.45
	create_tween().tween_property(ragdoll, "influence", 1.0, 0.18).set_ease(Tween.EASE_IN)
	var imp := dir * impulsion(degats, _rng.randf())
	_impulsions.append([os, point, imp])
	# une petite part va au bassin (le corps entier recule) et une torsion au hasard sur le tronc
	_impulsions.append(["pelvis", Vector3.INF, imp * _rng.randf_range(0.15, 0.35)])
	var tors := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * 0.8
	for h in _hitboxes:
		var pb: PhysicalBone3D = h["pb"]
		pb.linear_velocity = elan[h["os"]]
		if (h["os"] as String).begins_with("spine"):
			pb.angular_velocity = tors
	anim.pause()
	velocity = Vector3.ZERO
	vitesse_marche = Vector3.ZERO
	if arme:
		_lacher_arme(dir)
	if Degats.zone_depuis_os(os) != Degats.Zone.TETE and _rng.randf() < 0.6:
		_son("douleur_%d" % _rng.randi_range(1, 4), global_position + Vector3.UP * 1.4, -7.0, _rng.randf_range(0.85, 0.95))
	if tireur != null and tireur.is_in_group("joueur") and has_node("/root/Jeu"):
		get_node("/root/Jeu").score.tues += 1
	_enregistrer_corps()
	mort.emit(self)


func _enregistrer_corps() -> void:
	corps_morts = corps_morts.filter(func(c) -> bool: return is_instance_valid(c))
	corps_morts.append(self)
	var limite := 24
	if has_node("/root/Reglages"):
		limite = int(get_node("/root/Reglages").get_v("limite_corps"))
	for i in corps_en_trop(corps_morts.size(), limite):
		var vieux = corps_morts.pop_front()
		if is_instance_valid(vieux) and vieux != self:
			vieux.queue_free()


## Le pistolet quitte la main : il devient un corps rigide ; un chargeur ramassable tombe près du corps.
func _lacher_arme(dir: Vector3) -> void:
	if pistolet == null or not is_instance_valid(pistolet):
		return
	var t := pistolet.global_transform
	var rb := RigidBody3D.new()
	rb.name = "ArmeTombee"
	rb.collision_layer = 0
	rb.collision_mask = COUCHE_MONDE
	rb.mass = 0.9
	rb.continuous_cd = true
	var pm := PhysicsMaterial.new()
	pm.friction = 0.8
	pm.bounce = 0.1
	rb.physics_material_override = pm
	for f in [[Vector3(0.03, 0.05, 0.2), Vector3(0, 0.045, -0.15)], [Vector3(0.03, 0.13, 0.05), Vector3(0, -0.05, -0.03)]]:
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = f[0]
		cs.shape = b
		cs.position = f[1]
		rb.add_child(cs)
	get_parent().add_child(rb, true)
	rb.global_transform = t
	pistolet.get_parent().remove_child(pistolet)
	rb.add_child(pistolet)
	pistolet.transform = Transform3D.IDENTITY
	rb.linear_velocity = _vitesses.get("lowerarm_r", Vector3.ZERO).limit_length(3.0) + dir * 0.6 + Vector3.UP * 0.5
	rb.angular_velocity = Vector3(_rng.randf_range(-6, 6), _rng.randf_range(-4, 4), _rng.randf_range(-6, 6))
	# chargeur : le maillage du pistolet, un peu plus loin, quelques cartouches dedans
	var mesh: Mesh = null
	var mat: Material = null
	var src := pistolet.find_child("chargeur", true, false) as MeshInstance3D
	if src != null:
		mesh = src.mesh
		mat = src.get_active_material(0)
	var c := ChargeurGarde.creer(mesh, mat, _rng.randi_range(6, 15))
	get_parent().add_child(c, true)
	var hanche := squelette.global_transform * squelette.get_bone_global_pose(squelette.find_bone("pelvis"))
	c.global_position = hanche.origin + Vector3(_rng.randf_range(-0.25, 0.25), 0.05, _rng.randf_range(-0.25, 0.25))
	c.rotation = Vector3(_rng.randf_range(0, TAU), _rng.randf_range(0, TAU), 0)
	c.linear_velocity = dir * 0.4


func _physics_process(delta: float) -> void:
	if modele == null:
		return
	if vivant:
		if not is_on_floor():
			velocity.y -= 9.8 * delta
		else:
			velocity.y = -0.1
		velocity.x = vitesse_marche.x
		velocity.z = vitesse_marche.z
		move_and_slide()
	else:
		_t_mort += delta
		_appliquer_impulsions()
		_surveiller_chute()
		if not _endormi and _t_mort > 4.0 and _immobile():
			_endormi = true
			_placer_hitboxes(delta)
	if not _endormi:
		_placer_hitboxes(delta)


func _appliquer_impulsions() -> void:
	if _impulsions.is_empty() or _t_mort <= 0.0:
		return
	for e in _impulsions:
		var pb := ragdoll.get_node_or_null("pb_" + str(e[0])) as PhysicalBone3D
		if pb == null:
			continue
		var point: Vector3 = e[1]
		if point == Vector3.INF:
			pb.apply_central_impulse(e[2])
		else:
			pb.apply_impulse(e[2], point - pb.global_position)
	_impulsions.clear()


## Bruit du corps qui touche le sol : le tronc tombait vite et s'arrête net.
func _surveiller_chute() -> void:
	if _chute_jouee:
		return
	var pb := ragdoll.get_node_or_null("pb_spine_03") as PhysicalBone3D
	if pb == null:
		return
	var vy := pb.linear_velocity.y
	if _vy_prec < -1.2 and vy > _vy_prec * 0.3 and _t_mort > 0.15:
		_chute_jouee = true
		_son("chute_corps", pb.global_position, -2.0, _rng.randf_range(0.9, 1.08))
	_vy_prec = vy


func _immobile() -> bool:
	for h in _hitboxes:
		var pb: PhysicalBone3D = h["pb"]
		if pb.linear_velocity.length() > 0.06:
			return false
	return true


func _placer_hitboxes(delta: float) -> void:
	var sk_t := squelette.global_transform
	for h in _hitboxes:
		var a: Area3D = h["zone"]
		var t: Transform3D
		if vivant:
			t = sk_t * squelette.get_bone_global_pose(h["idx"]) * (h["offset"] as Transform3D)
		else:
			t = (h["pb"] as PhysicalBone3D).global_transform
		a.global_transform = t
		var os: String = h["os"]
		if delta > 0.0 and _prec.has(os):
			_vitesses[os] = (t.origin - (_prec[os] as Vector3)) / delta
		_prec[os] = t.origin


func _son(nom: String, pos: Vector3, volume := 0.0, hauteur := 1.0) -> void:
	var flux := load(SONS + nom + ".wav") as AudioStream
	if flux != null and has_node("/root/Audio"):
		get_node("/root/Audio").son_3d(flux, pos, get_parent(), volume, hauteur, "Effets", 40.0)


## Os physique d'un segment (pour les tests et les effets).
func os_physique(nom: String) -> PhysicalBone3D:
	return ragdoll.get_node_or_null("pb_" + nom) as PhysicalBone3D


func _exit_tree() -> void:
	corps_morts.erase(self)
