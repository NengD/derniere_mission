extends StaticBody3D
## Objet ramassable de la salle de test (couche 5 : interactifs) : chargeur ou trousse de soin.
## Montre l'interface d'interaction : interagir(joueur) et texte_aide().

@export var type := "chargeur"   # "chargeur" ou "trousse"


func _ready() -> void:
	collision_layer = 16
	collision_mask = 0


func texte_aide() -> String:
	return tr("AIDE_TROUSSE") if type == "trousse" else tr("AIDE_CHARGEUR")


func interagir(joueur: Node) -> void:
	if type == "trousse":
		if joueur.has_method("ramasser_trousse") and joueur.ramasser_trousse():
			queue_free()
	elif joueur.has_method("ramasser_chargeur"):
		joueur.ramasser_chargeur(15)
		queue_free()
