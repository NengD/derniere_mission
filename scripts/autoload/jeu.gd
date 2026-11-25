extends Node
## État de la partie : niveau en cours, statistiques, campagne, sauvegarde et points de contrôle.

signal stats_changees

const FICHIER := "user://sauvegarde.json"
const NIVEAUX := "res://data/niveaux.json"

var donnees: Dictionary = Sauvegarde.vide()
var niveaux: Array = []
var niveau_actuel := 1
var score := Score.new()
## état du joueur et du niveau au dernier point de contrôle (rechargé à la mort)
var point_controle: Dictionary = {}


func _ready() -> void:
	TranslationServer.set_locale("fr")
	var f := FileAccess.open(NIVEAUX, FileAccess.READ)
	if f:
		var d = JSON.parse_string(f.get_as_text())
		if d is Array:
			niveaux = d
	donnees = Sauvegarde.lire(FICHIER)


func info_niveau(n: int) -> Dictionary:
	for d in niveaux:
		if int(d.get("id", 0)) == n:
			return d
	return {}


func sauver() -> void:
	Sauvegarde.ecrire(FICHIER, donnees)


func a_une_partie() -> bool:
	return not donnees.get("partie", {}).is_empty()


## Nouvelle partie au niveau n (efface la partie en cours, garde les niveaux débloqués).
func commencer_niveau(n: int) -> void:
	niveau_actuel = n
	var info := info_niveau(n)
	score = Score.new()
	score.otages_total = int(info.get("otages", 0))
	score.documents_total = int(info.get("documents", 0))
	point_controle = {"id": "debut", "joueur": {}, "score": score.vers_dict(), "monde": {}}
	donnees["partie"] = {"niveau": n, "point": point_controle}
	sauver()


func continuer() -> int:
	var p: Dictionary = donnees.get("partie", {})
	niveau_actuel = int(p.get("niveau", 1))
	point_controle = p.get("point", {})
	score = Score.new()
	score.depuis_dict(point_controle.get("score", {}))
	return niveau_actuel


## Enregistre un point de contrôle : état du joueur et du monde (ennemis tués, otages, documents).
func enregistrer_point(id: String, joueur: Dictionary, monde: Dictionary) -> void:
	point_controle = {"id": id, "joueur": joueur, "score": score.vers_dict(), "monde": monde}
	donnees["partie"] = {"niveau": niveau_actuel, "point": point_controle}
	sauver()


func joueur_mort() -> void:
	# on revient au dernier point de contrôle, le compteur de morts est conservé
	var morts := score.morts_joueur + 1
	score.depuis_dict(point_controle.get("score", {}))
	score.morts_joueur = morts


func otage_libere(id: String) -> void:
	if not score.otages_liberes.has(id):
		score.otages_liberes.append(id)
	stats_changees.emit()


func document_trouve(id: String, cache := false) -> void:
	if not score.documents.has(id):
		score.documents.append(id)
	if cache:
		donnees["campagne"]["document_cache"] = true
	stats_changees.emit()


## Fin de niveau : cumule dans la campagne, débloque le suivant, efface la partie en cours.
func terminer_niveau() -> void:
	var c: Dictionary = donnees["campagne"]
	for o in score.otages_liberes:
		if not c["otages"].has(o):
			c["otages"].append(o)
	for d in score.documents:
		if not c["documents"].has(d):
			c["documents"].append(d)
	c["tues"] = int(c["tues"]) + score.tues
	c["tirs"] = int(c["tirs"]) + score.tirs
	c["touches"] = int(c["touches"]) + score.touches
	c["temps"] = float(c["temps"]) + score.temps
	var suivant := niveau_actuel + 1
	if not donnees["niveaux_debloques"].has(suivant) and not info_niveau(suivant).is_empty():
		donnees["niveaux_debloques"].append(suivant)
	donnees["partie"] = {}
	sauver()


func tr_f(cle: String, args: Array = []) -> String:
	var s := tr(cle)
	return s % args if not args.is_empty() else s
