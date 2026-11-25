class_name Fins
extends RefCounted
## Choix de la fin selon la façon de jouer (réglages dans data/fins.json).

const FICHIER := "res://data/fins.json"


static func charger_config() -> Dictionary:
	var f := FileAccess.open(FICHIER, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


## stats : otages_liberes, otages_total, documents_trouves, documents_total, document_cache (bool)
static func choisir(stats: Dictionary, config: Dictionary) -> String:
	if config.get("rebondissement_si_document_cache", true) and stats.get("document_cache", false):
		return "rebondissement"
	var ot: float = max(1.0, float(stats.get("otages_total", 1)))
	var dt: float = max(1.0, float(stats.get("documents_total", 1)))
	var r_ot := float(stats.get("otages_liberes", 0)) / ot
	var r_doc := float(stats.get("documents_trouves", 0)) / dt
	if r_ot >= float(config.get("heureuse_seuil_otages", 1.0)) - 0.0001 \
			and r_doc >= float(config.get("heureuse_seuil_documents", 1.0)) - 0.0001:
		return "heureuse"
	return "tragique"
