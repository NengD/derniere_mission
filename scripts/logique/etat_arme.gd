class_name EtatArme
extends RefCounted
## Munitions d'une arme à chargeurs : le chargeur partiellement vidé est conservé à part,
## rechargement plus lent si l'arme est vide (culasse à relâcher), enrayement rare.

enum Tir { OK, VIDE, ENRAYEE, OCCUPEE }

var capacite := 15
var chambre := true            # une cartouche dans la chambre
var chargeur := 15             # cartouches dans le chargeur engagé
var poches: Array[int] = []    # chargeurs de rechange (nombre de cartouches dans chacun)
var enrayee := false
var proba_enrayage := 0.004
var duree_recharge_tactique := 1.7
var duree_recharge_vide := 2.4
var duree_desenrayage := 1.3
var occupe := 0.0              # temps restant de l'action en cours
var _action := ""
var _rng := RandomNumberGenerator.new()


func _init(cap := 15, nb_chargeurs := 2, graine := -1) -> void:
	capacite = cap
	chargeur = cap
	chambre = true
	poches.clear()
	for i in nb_chargeurs:
		poches.append(cap)
	if graine >= 0:
		_rng.seed = graine
	else:
		_rng.randomize()


func cartouches_dans_arme() -> int:
	return chargeur + (1 if chambre else 0)


func total() -> int:
	var t := cartouches_dans_arme()
	for c in poches:
		t += c
	return t


func peut_tirer() -> bool:
	return occupe <= 0.0 and chambre and not enrayee


func tirer() -> Tir:
	if occupe > 0.0:
		return Tir.OCCUPEE
	if enrayee:
		return Tir.ENRAYEE
	if not chambre:
		return Tir.VIDE
	chambre = false
	# la culasse réarme depuis le chargeur… sauf enrayage
	if chargeur > 0:
		if _rng.randf() < proba_enrayage:
			enrayee = true
		else:
			chargeur -= 1
			chambre = true
	return Tir.OK


## Lance un rechargement (ou un désenrayage si l'arme est enrayée). Renvoie la durée, 0 si impossible.
func recharger() -> float:
	if occupe > 0.0:
		return 0.0
	if enrayee:
		_action = "desenrayer"
		occupe = duree_desenrayage
		return occupe
	if poches.is_empty() or chargeur >= capacite:
		return 0.0
	_action = "recharger_vide" if not chambre else "recharger"
	occupe = duree_recharge_vide if not chambre else duree_recharge_tactique
	return occupe


func avancer(delta: float) -> void:
	if occupe <= 0.0:
		return
	occupe -= delta
	if occupe <= 0.0:
		occupe = 0.0
		_terminer()


func _terminer() -> void:
	match _action:
		"desenrayer":
			enrayee = false
			if chargeur > 0:
				chargeur -= 1
				chambre = true
		"recharger", "recharger_vide":
			# on range le chargeur engagé (même entamé) et on prend le plus plein
			var meilleur := 0
			for i in poches.size():
				if poches[i] > poches[meilleur]:
					meilleur = i
			var nouveau: int = poches[meilleur]
			poches.remove_at(meilleur)
			if chargeur > 0:
				poches.append(chargeur)
			chargeur = nouveau
			if not chambre and chargeur > 0:
				chargeur -= 1
				chambre = true
	_action = ""


func action_en_cours() -> String:
	return _action


## Ramasser des munitions sur un ennemi : un chargeur (éventuellement entamé).
func ramasser_chargeur(nb: int) -> void:
	if nb > 0:
		poches.append(min(nb, capacite))


func vers_dict() -> Dictionary:
	return {"chambre": chambre, "chargeur": chargeur, "poches": poches.duplicate(), "enrayee": enrayee}


func depuis_dict(d: Dictionary) -> void:
	chambre = d.get("chambre", true)
	chargeur = int(d.get("chargeur", capacite))
	poches.clear()
	for c in d.get("poches", []):
		poches.append(int(c))
	enrayee = d.get("enrayee", false)
	occupe = 0.0
	_action = ""
