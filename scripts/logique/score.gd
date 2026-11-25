class_name Score
extends RefCounted
## Statistiques et score de fin de niveau.

var tirs := 0
var touches := 0
var tues := 0
var temps := 0.0
var otages_liberes: Array[String] = []
var otages_total := 0
var documents: Array[String] = []
var documents_total := 0
var morts_joueur := 0


func precision() -> float:
	return 0.0 if tirs == 0 else float(touches) / float(tirs)


func points() -> int:
	var p := tues * 100 + otages_liberes.size() * 500 + documents.size() * 250
	p += int(precision() * 1000.0)
	p -= morts_joueur * 200
	p += max(0, 600 - int(temps)) * 2      # bonus de rapidité (10 min)
	return max(p, 0)


func note() -> String:
	var p := points()
	if p >= 3500:
		return "S"
	if p >= 2600:
		return "A"
	if p >= 1800:
		return "B"
	if p >= 1000:
		return "C"
	return "D"


func vers_dict() -> Dictionary:
	return {"tirs": tirs, "touches": touches, "tues": tues, "temps": temps,
		"otages_liberes": otages_liberes.duplicate(), "otages_total": otages_total,
		"documents": documents.duplicate(), "documents_total": documents_total, "morts_joueur": morts_joueur}


func depuis_dict(d: Dictionary) -> void:
	tirs = int(d.get("tirs", 0))
	touches = int(d.get("touches", 0))
	tues = int(d.get("tues", 0))
	temps = float(d.get("temps", 0.0))
	morts_joueur = int(d.get("morts_joueur", 0))
	otages_total = int(d.get("otages_total", 0))
	documents_total = int(d.get("documents_total", 0))
	otages_liberes.clear()
	for s in d.get("otages_liberes", []):
		otages_liberes.append(str(s))
	documents.clear()
	for s in d.get("documents", []):
		documents.append(str(s))
