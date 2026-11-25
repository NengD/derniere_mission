class_name BT
extends RefCounted
## Petit moteur d'arbre de comportement : séquence, sélecteur, condition, action, décorateurs.
## Chaque nœud renvoie SUCCES, ECHEC ou EN_COURS à chaque « tick ».
## Les feuilles appellent des Callable du personnage : cond(bb) -> bool ; action(bb, delta) -> Etat.

enum Etat { SUCCES, ECHEC, EN_COURS }


class Noeud:
	extends RefCounted
	var nom := ""

	func tick(_bb: Dictionary, _delta: float) -> int:
		return Etat.ECHEC

	func reinitialiser() -> void:
		pass


## Essaie ses enfants dans l'ordre ; s'arrête au premier qui ne échoue pas. Réévalué à chaque tick
## (réactif : un enfant prioritaire peut interrompre une action en cours).
class Selecteur:
	extends Noeud
	var enfants: Array = []
	var _actif := -1

	func _init(n: String, e: Array) -> void:
		nom = n
		enfants = e

	func tick(bb: Dictionary, delta: float) -> int:
		for i in enfants.size():
			var r: int = enfants[i].tick(bb, delta)
			if r != Etat.ECHEC:
				if _actif != -1 and _actif != i:
					enfants[_actif].reinitialiser()
				_actif = i if r == Etat.EN_COURS else -1
				if r == Etat.EN_COURS or r == Etat.SUCCES:
					bb["_chemin_" + nom] = enfants[i].nom
				return r
		_actif = -1
		return Etat.ECHEC

	func reinitialiser() -> void:
		for e in enfants:
			e.reinitialiser()
		_actif = -1


## Exécute ses enfants dans l'ordre ; échoue au premier échec. Mémorise l'enfant en cours.
class Sequence:
	extends Noeud
	var enfants: Array = []
	var _i := 0

	func _init(n: String, e: Array) -> void:
		nom = n
		enfants = e

	func tick(bb: Dictionary, delta: float) -> int:
		while _i < enfants.size():
			var r: int = enfants[_i].tick(bb, delta)
			if r == Etat.EN_COURS:
				return r
			if r == Etat.ECHEC:
				_i = 0
				return r
			_i += 1
		_i = 0
		return Etat.SUCCES

	func reinitialiser() -> void:
		for e in enfants:
			e.reinitialiser()
		_i = 0


class Condition:
	extends Noeud
	var f: Callable

	func _init(n: String, fn: Callable) -> void:
		nom = n
		f = fn

	func tick(bb: Dictionary, _delta: float) -> int:
		return Etat.SUCCES if f.call(bb) else Etat.ECHEC


class Action:
	extends Noeud
	var f: Callable
	var fin: Callable

	func _init(n: String, fn: Callable, quand_interrompue := Callable()) -> void:
		nom = n
		f = fn
		fin = quand_interrompue

	func tick(bb: Dictionary, delta: float) -> int:
		return f.call(bb, delta)

	func reinitialiser() -> void:
		if fin.is_valid():
			fin.call()


## Inverse SUCCES et ECHEC.
class Inverse:
	extends Noeud
	var enfant: Noeud

	func _init(e: Noeud) -> void:
		enfant = e
		nom = "non_" + e.nom

	func tick(bb: Dictionary, delta: float) -> int:
		var r := enfant.tick(bb, delta)
		if r == Etat.SUCCES:
			return Etat.ECHEC
		if r == Etat.ECHEC:
			return Etat.SUCCES
		return r


## Laisse passer l'enfant au plus une fois toutes les `periode` secondes (sinon ECHEC).
class Delai:
	extends Noeud
	var enfant: Noeud
	var periode := 1.0
	var _attente := 0.0

	func _init(n: String, e: Noeud, p: float) -> void:
		nom = n
		enfant = e
		periode = p

	func tick(bb: Dictionary, delta: float) -> int:
		_attente -= delta
		if _attente > 0.0:
			return Etat.ECHEC
		var r := enfant.tick(bb, delta)
		if r != Etat.EN_COURS:
			_attente = periode
		return r


static func sel(n: String, e: Array) -> Selecteur:
	return Selecteur.new(n, e)


static func seq(n: String, e: Array) -> Sequence:
	return Sequence.new(n, e)


static func si(n: String, f: Callable) -> Condition:
	return Condition.new(n, f)


static func fais(n: String, f: Callable, fin := Callable()) -> Action:
	return Action.new(n, f, fin)
