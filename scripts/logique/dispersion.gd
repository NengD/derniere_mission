class_name Dispersion
extends RefCounted
## Dispersion des tirs du joueur (en degrés, demi-angle du cône). Logique pure, testable.
## Première balle précise quand on est posé ; le mouvement, le saut et les tirs rapprochés l'ouvrent.

const BASE_HANCHE := 1.6
const BASE_VISEE := 0.25
const PAR_MS := 0.9           # degrés en plus par m/s de vitesse
const EN_L_AIR := 4.0
const ACCROUPI := 0.75        # multiplicateur
const PAR_TIR := 0.55         # degrés en plus par tir récent (chaleur)
const CHALEUR_MAX := 4.0
const DELAI_PREMIERE := 0.45  # s sans tirer pour que la balle suivante soit « première »


## vitesse : m/s horizontale ; visee : 0 (hanche) à 1 (visée) ; chaleur : nombre de tirs récents
## (décroît avec le temps) ; depuis_tir : secondes depuis le tir précédent.
static func angle(vitesse: float, visee: float, accroupi: bool, en_l_air: bool, chaleur: float, depuis_tir: float) -> float:
	var a: float = lerp(BASE_HANCHE, BASE_VISEE, clamp(visee, 0.0, 1.0))
	a += max(0.0, vitesse - 0.3) * PAR_MS * lerp(1.0, 0.6, visee)
	if en_l_air:
		a += EN_L_AIR
	if depuis_tir >= DELAI_PREMIERE and vitesse < 0.5 and not en_l_air:
		# première balle : quasi parfaite en visée, resserrée à la hanche
		a *= 0.1 if visee > 0.8 else 0.6
	else:
		a += min(chaleur, CHALEUR_MAX) * PAR_TIR * lerp(1.0, 0.5, visee)
	if accroupi:
		a *= ACCROUPI
	return a


## Tire une direction dans le cône (axe = -Z du repère `base`). `r1`, `r2` dans [0, 1[.
static func direction(base: Basis, angle_deg: float, r1: float, r2: float) -> Vector3:
	# répartition plus dense au centre (racine non appliquée volontairement)
	var rayon := tan(deg_to_rad(angle_deg)) * r1
	var phi := r2 * TAU
	var d := Vector3(cos(phi) * rayon, sin(phi) * rayon, -1.0).normalized()
	return (base * d).normalized()
