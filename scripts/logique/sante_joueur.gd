class_name SanteJoueur
extends RefCounted
## Santé du joueur (logique pure, testable sans rendu) : points de vie, trousses de soin rares
## (soin lent, interrompu si on est touché), régénération réglable après un délai sans blessure.

const PV_MAX := 100.0
const TROUSSES_MAX := 3
const SOIN_TROUSSE := 60.0      # points rendus par une trousse
const DUREE_SOIN := 4.0         # secondes pour appliquer une trousse
const DELAI_REGEN := 8.0        # secondes sans blessure avant la régénération
const REGEN_PLAFOND := 60.0     # la régénération ne remonte jamais au-delà

var pv := PV_MAX
var trousses := 1
var regeneration := 0.0         # points par seconde (réglage du joueur, 0 = aucune)
var soin_restant := 0.0         # points encore à rendre par la trousse en cours
var depuis_blessure := 999.0


func est_mort() -> bool:
	return pv <= 0.0


func en_soin() -> bool:
	return soin_restant > 0.0


## Retire des points de vie. Renvoie les points de vie restants. Interrompt le soin en cours
## (la trousse est perdue : on ne se soigne pas sous le feu).
func recevoir(montant: float) -> float:
	if est_mort() or montant <= 0.0:
		return pv
	pv = max(0.0, pv - montant)
	depuis_blessure = 0.0
	soin_restant = 0.0
	return pv


## Commence à appliquer une trousse. Faux si aucune, déjà en soin, mort ou pleine santé.
func commencer_soin() -> bool:
	if trousses <= 0 or en_soin() or est_mort() or pv >= PV_MAX:
		return false
	trousses -= 1
	soin_restant = SOIN_TROUSSE
	return true


func ramasser_trousse() -> bool:
	if trousses >= TROUSSES_MAX:
		return false
	trousses += 1
	return true


func avancer(delta: float) -> void:
	if est_mort():
		return
	depuis_blessure += delta
	if en_soin():
		var d: float = min(soin_restant, SOIN_TROUSSE / DUREE_SOIN * delta)
		soin_restant -= d
		pv = min(PV_MAX, pv + d)
		if pv >= PV_MAX:
			soin_restant = 0.0
	elif regeneration > 0.0 and depuis_blessure >= DELAI_REGEN and pv < REGEN_PLAFOND:
		pv = min(REGEN_PLAFOND, pv + regeneration * delta)


## 0 = pleine forme, 1 = au bord de la mort (pour le son et l'image).
func gravite() -> float:
	return clamp(1.0 - pv / PV_MAX, 0.0, 1.0)


func vers_dict() -> Dictionary:
	return {"pv": pv, "trousses": trousses}


func depuis_dict(d: Dictionary) -> void:
	pv = float(d.get("pv", PV_MAX))
	trousses = int(d.get("trousses", 1))
	soin_restant = 0.0
	depuis_blessure = 999.0
