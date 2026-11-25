class_name CameraPieton
extends CanvasLayer
## Couche d'image « caméra-piéton » réutilisable : shader plein écran (direction A), incrustation
## REC + horodatage + identifiant de la caméra, sous-titres, texte d'aide d'interaction et HUD
## optionnel (munitions, point de visée), invisible par défaut.
## Le joueur pilote : motion (flou d'après la rotation), flash, sang, blessure.

## heure affichée au départ (secondes depuis minuit) et date de l'horodatage
var heure_depart := 3 * 3600 + 14 * 60 + 27
var date := "14/03/2027"

var post: ShaderMaterial
var _ecran: ColorRect
var _rec: Label
var _point_rec: ColorRect
var _id: Label
var _sous_titre: Label
var _aide: Label
var _munitions: Label
var _viseur: ColorRect
var _t := 0.0
var _sous_titre_reste := 0.0
var _flash := 0.0
var _sang := 0.0
var _blessure := 0.0
var _motion := Vector2.ZERO


func _ready() -> void:
	layer = 10
	_ecran = ColorRect.new()
	_ecran.name = "effet"
	_ecran.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ecran.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post = ShaderMaterial.new()
	post.shader = load("res://shaders/camera_pieton.gdshader")
	_ecran.material = post
	add_child(_ecran)
	# étalonnage de la direction A (photoréaliste sombre)
	post.set_shader_parameter("contrast", 1.06)
	post.set_shader_parameter("saturation", 0.72)
	post.set_shader_parameter("chroma", 0.003)
	post.set_shader_parameter("grain", 0.06)
	post.set_shader_parameter("vignette", 0.85)
	post.set_shader_parameter("split_tone", 0.2)
	post.set_shader_parameter("black_lift", 0.014)

	_point_rec = ColorRect.new()
	_point_rec.color = Color(0.95, 0.08, 0.05)
	_point_rec.size = Vector2(16, 16)
	_point_rec.position = Vector2(40, 56)
	_point_rec.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_point_rec)
	_rec = _label(Vector2(64, 46), 26, Color(0.92, 0.92, 0.9, 0.85))
	_id = _label(Vector2(64, 80), 18, Color(0.85, 0.85, 0.82, 0.6))
	_id.text = tr("CAM_ID")

	_sous_titre = _label(Vector2.ZERO, 30, Color(0.95, 0.95, 0.92))
	_sous_titre.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_sous_titre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sous_titre.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sous_titre.offset_left = -700
	_sous_titre.offset_right = 700
	_sous_titre.offset_top = -170
	_sous_titre.offset_bottom = -90
	_sous_titre.visible = false

	_aide = _label(Vector2.ZERO, 22, Color(0.9, 0.9, 0.86, 0.8))
	_aide.set_anchors_preset(Control.PRESET_CENTER)
	_aide.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_aide.offset_left = -400
	_aide.offset_right = 400
	_aide.offset_top = 70
	_aide.offset_bottom = 110
	_aide.visible = false

	_munitions = _label(Vector2.ZERO, 24, Color(0.9, 0.9, 0.86, 0.75))
	_munitions.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_munitions.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_munitions.offset_left = -300
	_munitions.offset_right = -60
	_munitions.offset_top = -90
	_munitions.offset_bottom = -50

	_viseur = ColorRect.new()
	_viseur.color = Color(0.95, 0.95, 0.9, 0.7)
	_viseur.size = Vector2(4, 4)
	_viseur.set_anchors_preset(Control.PRESET_CENTER)
	_viseur.offset_left = -2
	_viseur.offset_top = -2
	_viseur.offset_right = 2
	_viseur.offset_bottom = 2
	_viseur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_viseur)

	if has_node("/root/Reglages"):
		get_node("/root/Reglages").connect("change", appliquer_reglages)
	appliquer_reglages()
	_maj_rec()


func _label(pos: Vector2, taille: int, couleur: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", taille)
	l.add_theme_color_override("font_color", couleur)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	add_child(l)
	return l


func _reglage(cle: String, defaut):
	if has_node("/root/Reglages"):
		var v = get_node("/root/Reglages").call("get_v", cle)
		return defaut if v == null else v
	return defaut


func appliquer_reglages() -> void:
	post.set_shader_parameter("intensity", float(_reglage("effet_camera", 1.0)))
	var mal: bool = _reglage("mal_des_transports", false)
	post.set_shader_parameter("distortion", 0.0 if mal else 0.24)
	post.set_shader_parameter("zoom_fit", 1.0 if mal else 0.76)
	post.set_shader_parameter("motion_blur", 0.25 if mal else 0.6)
	_munitions.visible = bool(_reglage("afficher_munitions", false))
	_viseur.visible = bool(_reglage("afficher_point", false))


func _process(delta: float) -> void:
	_t += delta
	_maj_rec()
	_flash = max(0.0, _flash - delta * 2.5)
	post.set_shader_parameter("flash", _flash)
	post.set_shader_parameter("motion", _motion)
	post.set_shader_parameter("blood", _sang)
	post.set_shader_parameter("hurt", _blessure)
	if _sous_titre_reste > 0.0:
		_sous_titre_reste -= delta
		if _sous_titre_reste <= 0.0:
			_sous_titre.visible = false


func _maj_rec() -> void:
	var s := heure_depart + int(_t)
	_rec.text = "%s   %s   %02d:%02d:%02d" % [tr("CAM_REC"), date, (s / 3600) % 24, (s / 60) % 60, s % 60]
	_point_rec.visible = fmod(_t, 1.0) < 0.6


# ---------------------------------------------------------------- API

## Déplacement apparent de l'image (UV/s), d'après la rotation de la caméra.
func regler_mouvement(v: Vector2) -> void:
	_motion = v


func eblouir(v: float) -> void:
	_flash = max(_flash, v)


## Sang sur l'objectif (0 à 1) et vision trouble (0 à 1).
func regler_blessure(sang: float, trouble: float) -> void:
	_sang = clamp(sang, 0.0, 1.0)
	_blessure = clamp(trouble, 0.0, 1.0)


## Sous-titre (texte déjà traduit) affiché `duree` secondes ; texte vide = efface.
func sous_titre(texte: String, duree := 4.0) -> void:
	_sous_titre.text = texte
	_sous_titre.visible = texte != ""
	_sous_titre_reste = duree


## Texte d'aide d'interaction (déjà traduit) ; vide = masqué.
func aide(texte: String) -> void:
	_aide.text = texte
	_aide.visible = texte != ""


func munitions(dans_arme: int, reserve: int) -> void:
	_munitions.text = tr("HUD_MUNITIONS") % [dans_arme, reserve]
