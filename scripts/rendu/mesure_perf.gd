class_name MesurePerf
extends Node
## Mesure des images par seconde en temps réel (vsync coupée) : moyenne et « 1 % bas »
## (moyenne des 1 % d'images les plus lentes), écrites dans `fichier` à la sortie de l'arbre.

var fichier := "res://logs/perf.txt"
var etiquette := ""
var echauffement := 1.5
var _t := 0.0
var _durees: PackedFloat32Array = []
var _lents: PackedStringArray = []


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	process_priority = 1000


func _process(delta: float) -> void:
	_t += delta
	if _t > echauffement:
		_durees.append(delta)
		if delta > 0.03:
			_lents.append("%.2fs:%.0fms" % [_t, delta * 1000.0])


func resultat() -> String:
	if _durees.is_empty():
		return "aucune mesure"
	var tri := _durees.duplicate()
	tri.sort()
	var somme := 0.0
	for d in tri:
		somme += d
	var n1 := maxi(1, tri.size() / 100)
	var lent := 0.0
	for i in n1:
		lent += tri[tri.size() - 1 - i]
	var moy := tri.size() / somme
	var bas := n1 / lent
	return "%s  %dx%d  qualite=%s  images=%d  moyenne=%.1f i/s  1%%bas=%.1f i/s  pire=%.1f ms  GPU=%s" % [
		etiquette, get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y,
		str(get_node("/root/Reglages").call("get_v", "qualite")) if has_node("/root/Reglages") else "?",
		tri.size(), moy, bas, tri[tri.size() - 1] * 1000.0, RenderingServer.get_video_adapter_name()]


func ecrire() -> void:
	var r := resultat()
	print("PERF ", r)
	print("PERF images lentes (> 30 ms) : ", ", ".join(_lents))
	var f := FileAccess.open(fichier, FileAccess.READ_WRITE if FileAccess.file_exists(fichier) else FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line(Time.get_datetime_string_from_system() + "  " + r)
