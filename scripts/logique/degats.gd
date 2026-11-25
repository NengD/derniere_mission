class_name Degats
extends RefCounted
## Modèle de dégâts commun au joueur et aux ennemis : 2 ou 3 balles suffisent.

enum Zone { TETE, TORSE, BRAS, JAMBE }
enum Reaction { AUCUNE, SURSAUT, BRAS_TOUCHE, CHUTE, MORT }

const PV_MAX := 100.0
const MULTIPLICATEUR := {Zone.TETE: 4.0, Zone.TORSE: 1.0, Zone.BRAS: 0.5, Zone.JAMBE: 0.6}
const PORTEE_PLEINE := 20.0     # m : dégâts complets jusqu'ici
const PORTEE_MIN := 60.0        # m : dégâts minimaux au-delà
const FACTEUR_MIN := 0.6


static func zone_depuis_os(os: String) -> Zone:
	var o := os.to_lower()
	if o.begins_with("head") or o.begins_with("neck"):
		return Zone.TETE
	if o.contains("arm") or o.begins_with("hand") or o.begins_with("clavicle"):
		return Zone.BRAS
	if o.begins_with("thigh") or o.begins_with("calf") or o.begins_with("foot"):
		return Zone.JAMBE
	return Zone.TORSE


static func attenuation(distance: float) -> float:
	if distance <= PORTEE_PLEINE:
		return 1.0
	var t: float = clamp((distance - PORTEE_PLEINE) / (PORTEE_MIN - PORTEE_PLEINE), 0.0, 1.0)
	return lerp(1.0, FACTEUR_MIN, t)


static func calculer(base: float, zone: Zone, distance: float) -> float:
	return base * MULTIPLICATEUR[zone] * attenuation(distance)


## Réaction d'un personnage après un impact (pv = points de vie APRÈS l'impact).
static func reaction(zone: Zone, pv: float, deja_a_terre: bool) -> Reaction:
	if pv <= 0.0:
		return Reaction.MORT
	if zone == Zone.JAMBE and not deja_a_terre:
		return Reaction.CHUTE
	if zone == Zone.BRAS:
		return Reaction.BRAS_TOUCHE
	return Reaction.SURSAUT
