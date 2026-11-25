extends Node
## Options du joueur, enregistrées dans user://reglages.cfg.

signal change

const FICHIER := "user://reglages.cfg"

var valeurs := {
	"sensibilite": 0.12,          # degrés par pixel de souris
	"fov": 78.0,
	"effet_camera": 1.0,          # intensité de l'effet caméra-piéton (0 à 1)
	"mal_des_transports": false,  # coupe la déformation et les saccades
	"violence": 2,                # 2 = Maximum, 1 = Réduite, 0 = Sans sang
	"afficher_munitions": false,
	"afficher_point": false,
	"regeneration": 0.0,          # points de vie par seconde (0 = aucune)
	"limite_corps": 24,           # corps et morceaux gardés dans le niveau
	"limite_decals": 160,         # taches de sang gardées
	"qualite": 2,                 # 0 Bas, 1 Moyen, 2 Élevé
	"volume_musique": 0.8,
	"volume_effets": 1.0,
	"volume_voix": 1.0,
	"volume_ambiance": 0.8,
}


func _ready() -> void:
	charger()
	appliquer_volumes()


func get_v(cle: String):
	return valeurs.get(cle)


func set_v(cle: String, v) -> void:
	valeurs[cle] = v
	sauver()
	if cle.begins_with("volume_"):
		appliquer_volumes()
	change.emit()


func charger() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(FICHIER) != OK:
		return
	for k in valeurs:
		valeurs[k] = cfg.get_value("reglages", k, valeurs[k])


func sauver() -> void:
	var cfg := ConfigFile.new()
	for k in valeurs:
		cfg.set_value("reglages", k, valeurs[k])
	cfg.save(FICHIER)


func appliquer_volumes() -> void:
	for bus in ["Musique", "Effets", "Voix", "Ambiance"]:
		var i := AudioServer.get_bus_index(bus)
		if i >= 0:
			var v: float = valeurs["volume_" + bus.to_lower()]
			AudioServer.set_bus_volume_db(i, linear_to_db(max(v, 0.0001)))
