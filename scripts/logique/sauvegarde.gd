class_name Sauvegarde
extends RefCounted
## Lecture / écriture de la sauvegarde (user://sauvegarde.json), écriture atomique.

const VERSION := 1


static func vide() -> Dictionary:
	return {
		"version": VERSION,
		"niveaux_debloques": [1],
		"campagne": {"otages": [], "documents": [], "document_cache": false, "tues": 0, "tirs": 0, "touches": 0, "temps": 0.0},
		"partie": {},
	}


static func ecrire(chemin: String, donnees: Dictionary) -> bool:
	var tmp := chemin + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(donnees, "\t"))
	f.close()
	var dir := DirAccess.open(chemin.get_base_dir())
	if dir == null:
		return false
	if FileAccess.file_exists(chemin):
		dir.remove(chemin.get_file())
	return dir.rename(tmp.get_file(), chemin.get_file()) == OK


static func lire(chemin: String) -> Dictionary:
	if not FileAccess.file_exists(chemin):
		return vide()
	var f := FileAccess.open(chemin, FileAccess.READ)
	if f == null:
		return vide()
	var d = JSON.parse_string(f.get_as_text())
	if not d is Dictionary:
		return vide()
	return migrer(d)


## Complète une sauvegarde ancienne ou incomplète avec les valeurs par défaut.
static func migrer(d: Dictionary) -> Dictionary:
	var base := vide()
	for k in base:
		if not d.has(k):
			d[k] = base[k]
	for k in base["campagne"]:
		if not d["campagne"].has(k):
			d["campagne"][k] = base["campagne"][k]
	# le JSON relit les nombres en flottants : on remet les numéros de niveau en entiers
	var niv: Array = []
	for n in d["niveaux_debloques"]:
		niv.append(int(n))
	d["niveaux_debloques"] = niv
	d["version"] = VERSION
	return d
