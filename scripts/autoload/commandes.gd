extends Node
## Actions du clavier et de la souris (clavier-souris uniquement, pas de manette).
## Touches définies par leur POSITION physique : ZQSD sur un clavier AZERTY = WASD sur QWERTY.
## Les touches réassignées par le joueur sont lues et écrites dans user://commandes.cfg.

const FICHIER := "user://commandes.cfg"

# action -> [type, code]  (type : "touche" = position physique, "souris" = bouton)
const DEFAUTS := {
	"avancer": ["touche", KEY_W],
	"reculer": ["touche", KEY_S],
	"gauche": ["touche", KEY_A],
	"droite": ["touche", KEY_D],
	"courir": ["touche", KEY_SHIFT],
	"accroupi": ["touche", KEY_CTRL],
	"pencher_gauche": ["touche", KEY_Q],
	"pencher_droite": ["touche", KEY_E],
	"sauter": ["touche", KEY_SPACE],
	"tirer": ["souris", MOUSE_BUTTON_LEFT],
	"viser": ["souris", MOUSE_BUTTON_RIGHT],
	"recharger": ["touche", KEY_R],
	"interagir": ["touche", KEY_F],
	"soigner": ["touche", KEY_H],
	"documents": ["touche", KEY_TAB],
	"pause": ["touche", KEY_ESCAPE],
}


func _ready() -> void:
	appliquer_defauts()
	charger()


func appliquer_defauts() -> void:
	for action in DEFAUTS:
		_lier(action, DEFAUTS[action][0], DEFAUTS[action][1])


func _lier(action: String, type: String, code: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	InputMap.action_erase_events(action)
	if type == "touche":
		var ev := InputEventKey.new()
		ev.physical_keycode = code as Key
		InputMap.action_add_event(action, ev)
	else:
		var mb := InputEventMouseButton.new()
		mb.button_index = code as MouseButton
		InputMap.action_add_event(action, mb)


func reassigner(action: String, type: String, code: int) -> void:
	_lier(action, type, code)
	sauver()


func sauver() -> void:
	var cfg := ConfigFile.new()
	for action in DEFAUTS:
		var evs := InputMap.action_get_events(action)
		if evs.is_empty():
			continue
		var e: InputEvent = evs[0]
		if e is InputEventKey:
			cfg.set_value("commandes", action, ["touche", (e as InputEventKey).physical_keycode])
		elif e is InputEventMouseButton:
			cfg.set_value("commandes", action, ["souris", (e as InputEventMouseButton).button_index])
	cfg.save(FICHIER)


func charger() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(FICHIER) != OK:
		return
	for action in DEFAUTS:
		var v = cfg.get_value("commandes", action, null)
		if v is Array and v.size() == 2:
			_lier(action, v[0], int(v[1]))
