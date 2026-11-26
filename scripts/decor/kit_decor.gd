class_name KitDecor
extends Node3D
## Kit de décor réutilisable : habille un couloir ou une pièce à partir de ses dimensions.
##
## Utilisation (dans un niveau, AVANT RenduNiveau.cuire_gi) :
##   var kit := KitDecor.new()
##   kit.graine = 12                       # même graine = même décor
##   kit.evite = [AABB(...), ...]          # zones de sol à laisser libres (objets, passages, ennemis)
##   add_child(kit)                        # le kit travaille dans son repère local : le placer/tourner
##   kit.couloir(AABB(Vector3(-1.6, 0, -17), Vector3(3.2, 3, 19)), {"gaine": 1, "cables": -1})
##   kit.porte(Vector3(-1.6, 0, -5), 90.0, 25.0)        # porte abîmée entrouverte
##   KitDecor.marquer(self)                # le décor statique reçoit les décalques (calque 11)
## Le couloir suit l'axe Z local (tourner le nœud de 90° pour un couloir selon X). Une pièce = un
## couloir court (mêmes fonctions). Chaque partie peut aussi être appelée seule : plafond_technique(),
## plinthes(), salete(), humidite(), flaques(), dechets(), affiches().
## Les murs, sols et plafonds eux-mêmes prennent KitDecor.materiau(...) (pas de répétition visible).

const D := "res://assets/decor/"
const G := "res://assets/decor/gen/"
const A := "res://assets/decor/acg/"
const CALQUE_DECOR := 1 << 10     ## calque 11 : décor statique, seul à recevoir les décalques du kit
const CALQUE_FLAQUE := 1 << 11    ## calque 12 : flaques, seules à recevoir la sonde de reflets
const SHADER := preload("res://scripts/decor/surface_variee.gdshader")
const SHADER_FLAQUE := preload("res://scripts/decor/flaque.gdshader")

@export var graine := 1
## Zones de sol (repère local) où ne rien poser (déchets, flaques).
var evite: Array[AABB] = []
## Zones de mur où ne rien coller (affiches, tags) : lampes, portes, panneaux.
var evite_murs: Array[AABB] = []

var rnd := RandomNumberGenerator.new()
var zone := AABB()
var nb_decalques := 0
var _maillages := {}
var _mat_cache := {}
static var _macro: Texture2D


func _init() -> void:
	name = "KitDecor"


func _ready() -> void:
	rnd.seed = graine


# ================================================================ matériaux

## Matériau de surface sans répétition visible (voir surface_variee.gdshader).
## options : tex2, echelle2, part_second, decalage (Vector2), variation, teinte_macro, salete (hauteur m),
## salete_couleur, salete_force, suie (hauteur m), plafond_y, humidite (0-1), rugosite, relief, sol_y
static func materiau(tex: String, echelle := 0.4, teinte := Color.WHITE, o := {}) -> Material:
	if "shader" in OS.get_environment("DECOR_SANS").split(","):
		return _materiau_simple(tex, echelle, teinte)
	var m := ShaderMaterial.new()
	m.shader = SHADER
	var base := D + "tex/%s/%s_" % [tex, tex]
	m.set_shader_parameter("tex_albedo", load(base + "diff_2k.jpg"))
	m.set_shader_parameter("tex_orm", load(base + "arm_2k.jpg"))
	m.set_shader_parameter("tex_normal", load(base + "nor_gl_2k.jpg"))
	if _macro == null:
		_macro = load(G + "macro_bruit.png")
	m.set_shader_parameter("macro", _macro)
	m.set_shader_parameter("echelle", echelle)
	m.set_shader_parameter("teinte", teinte)
	if o.has("tex2"):
		var b2 := D + "tex/%s/%s_" % [o["tex2"], o["tex2"]]
		m.set_shader_parameter("second_actif", true)
		m.set_shader_parameter("tex2_albedo", load(b2 + "diff_2k.jpg"))
		m.set_shader_parameter("tex2_orm", load(b2 + "arm_2k.jpg"))
		m.set_shader_parameter("tex2_normal", load(b2 + "nor_gl_2k.jpg"))
		m.set_shader_parameter("echelle2", o.get("echelle2", echelle))
		m.set_shader_parameter("part_second", o.get("part_second", 0.35))
	var cles := {"decalage": "decalage", "variation": "variation_teinte", "teinte_macro": "teinte_macro",
		"salete": "salete_hauteur", "salete_couleur": "salete_couleur", "salete_force": "salete_force",
		"suie": "suie_hauteur", "plafond_y": "plafond_y", "humidite": "humidite", "rugosite": "rugosite_mult",
		"relief": "relief", "sol_y": "sol_y", "melange": "melange_echelles"}
	for k in cles:
		if o.has(k):
			m.set_shader_parameter(cles[k], o[k])
	return m


static func _materiau_simple(tex: String, echelle: float, teinte: Color) -> ORMMaterial3D:
	var m := ORMMaterial3D.new()
	var base := D + "tex/%s/%s_" % [tex, tex]
	m.albedo_texture = load(base + "diff_2k.jpg")
	m.albedo_color = teinte
	m.orm_texture = load(base + "arm_2k.jpg")
	m.normal_enabled = true
	m.normal_texture = load(base + "nor_gl_2k.jpg")
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * echelle
	return m


## Copie d'un matériau de surface avec un autre décalage UV et une autre teinte (un par mur).
static func varier(m: Material, graine_v: int, ecart_teinte := 0.06) -> Material:
	if not m is ShaderMaterial:
		return m
	var r := RandomNumberGenerator.new()
	r.seed = graine_v
	var c := m.duplicate() as ShaderMaterial
	c.set_shader_parameter("decalage", Vector2(r.randf_range(0, 50), r.randf_range(0, 50)))
	var t: Color = m.get_shader_parameter("teinte")
	var k := r.randf_range(-ecart_teinte, ecart_teinte)
	c.set_shader_parameter("teinte", Color(t.r * (1 + k), t.g * (1 + k * 0.8), t.b * (1 + k * 0.6)))
	return c


func _mat_tex(tex: String, echelle := 1.0, teinte := Color.WHITE, metal := -1.0) -> ORMMaterial3D:
	var cle := "%s/%s/%s" % [tex, echelle, teinte]
	if _mat_cache.has(cle):
		return _mat_cache[cle]
	var m := ORMMaterial3D.new()
	var base := D + "tex/%s/%s_" % [tex, tex]
	m.albedo_texture = load(base + "diff_2k.jpg")
	m.albedo_color = teinte
	m.orm_texture = load(base + "arm_2k.jpg")
	m.normal_enabled = true
	m.normal_texture = load(base + "nor_gl_2k.jpg")
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * echelle
	if metal >= 0.0:
		m.metallic = metal
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mat_cache[cle] = m
	return m


func _mat_simple(couleur: Color, rugosite := 0.7, metal := 0.0) -> StandardMaterial3D:
	var cle := "s/%s/%s/%s" % [couleur, rugosite, metal]
	if _mat_cache.has(cle):
		return _mat_cache[cle]
	var m := StandardMaterial3D.new()
	m.albedo_color = couleur
	m.roughness = rugosite
	m.metallic = metal
	_mat_cache[cle] = m
	return m


## Met le décor statique d'une branche sur le calque des décalques (calque 11, en plus du calque 1).
## À appeler après la construction du décor, avant d'ajouter joueur et ennemis.
static func marquer(racine: Node) -> void:
	for n in racine.find_children("*", "GeometryInstance3D", true, false):
		if n is MeshInstance3D or n is MultiMeshInstance3D:
			var g := n as GeometryInstance3D
			if g.layers & CALQUE_FLAQUE == 0 and g.layers & 2 == 0:
				g.layers |= CALQUE_DECOR


# ================================================================ outils

func _maillage(modele: String, enfant: String) -> Mesh:
	var cle := modele + "/" + enfant
	if _maillages.has(cle):
		return _maillages[cle]
	var chemin := D + "models/%s/%s.gltf" % [modele, modele]
	if not ResourceLoader.exists(chemin):
		chemin = D + "models/%s/%s.glb" % [modele, modele]
	var sc: Node = (load(chemin) as PackedScene).instantiate()
	var mi := sc.find_child(enfant, true, false) as MeshInstance3D
	var m: Mesh = mi.mesh if mi else null
	sc.free()
	if m == null:
		push_warning("KitDecor : pièce introuvable %s" % cle)
	_maillages[cle] = m
	return m


## Transformation qui pose le point `ancre` (0-1 dans la boîte du maillage) en `cible`.
func _poser(m: Mesh, b: Basis, cible: Vector3, ancre := Vector3(0.5, 0.5, 0.5)) -> Transform3D:
	var bb := m.get_aabb()
	return Transform3D(b, cible - b * (bb.position + bb.size * ancre))


func _instance(m: Mesh, xf: Transform3D, ombre := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.transform = xf
	if not ombre:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _multi(m: Mesh, xfs: Array, ombre := true, gi := true, mat: Material = null) -> MultiMeshInstance3D:
	if m == null or xfs.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = m
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if mat:
		mmi.material_override = mat
	if not ombre:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not gi:
		mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mmi)
	return mmi


func _boite(taille: Vector3, pos: Vector3, m: Material, ombre := true) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = taille
	var mi := _instance(bm, Transform3D(Basis(), pos), ombre)
	mi.material_override = m
	return mi


## Tube le long d'une polyligne (câbles) ; couleur par sommet, plusieurs tubes dans le même SurfaceTool.
func _tube(st: SurfaceTool, pts: PackedVector3Array, r: float, couleur: Color, cotes := 6) -> void:
	var n := pts.size()
	var base := _sommets_st
	var haut := Vector3.UP
	for i in n:
		var t := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var x := t.cross(haut)
		if x.length() < 0.01:
			x = t.cross(Vector3.RIGHT)
		x = x.normalized()
		var y := x.cross(t).normalized()
		haut = y
		for k in cotes + 1:
			var a := TAU * k / cotes
			var d := x * cos(a) + y * sin(a)
			st.set_color(couleur)
			st.set_normal(d)
			st.set_uv(Vector2(float(k) / cotes, i * 0.25))
			st.add_vertex(pts[i] + d * r)
	for i in n - 1:
		for k in cotes:
			var a := base + i * (cotes + 1) + k
			var b := a + cotes + 1
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(b)
			st.add_index(a + 1)
			st.add_index(b + 1)
			st.add_index(b)
	_sommets_st += n * (cotes + 1)


var _sommets_st := 0


func _chainette(a: Vector3, b: Vector3, fleche: float, n := 12) -> PackedVector3Array:
	var p := PackedVector3Array()
	for i in n + 1:
		var t := float(i) / n
		p.append(a.lerp(b, t) + Vector3.DOWN * fleche * 4.0 * t * (1.0 - t))
	return p


func _libre(p: Vector3, marge := 0.0) -> bool:
	for b in evite:
		if b.grow(marge).has_point(Vector3(p.x, b.get_center().y, p.z)):
			return false
	return true


func _libre_mur(p: Vector3) -> bool:
	for b in evite_murs:
		if b.has_point(p):
			return false
	return true


# ================================================================ décalques

## Décalque collé sur une surface de normale `nrm` (vers l'intérieur de la pièce) : image droite
## sur les murs (haut de l'image vers le haut), `angle` = rotation autour de la normale (degrés).
func decal(tex: String, centre: Vector3, nrm: Vector3, largeur: float, hauteur: float, angle := 0.0,
		o := {}) -> Decal:
	if not ResourceLoader.exists(tex):
		push_warning("KitDecor : décalque introuvable " + tex)
		return null
	var d := Decal.new()
	d.texture_albedo = load(tex)
	var nor := tex.replace(".png", "_nor.png")
	if o.get("relief", true) and ResourceLoader.exists(nor):
		d.texture_normal = load(nor)
	var y := nrm.normalized()
	var z := Vector3.DOWN if absf(y.y) < 0.7 else Vector3.FORWARD
	var x := y.cross(z).normalized()
	z = x.cross(y).normalized()
	var b := Basis(x, y, z).rotated(y, deg_to_rad(angle))
	d.transform = Transform3D(b, centre)
	d.size = Vector3(largeur, o.get("profondeur", 0.25), hauteur)
	d.cull_mask = CALQUE_DECOR
	d.normal_fade = o.get("normal_fade", 0.3)
	d.upper_fade = 0.15
	d.lower_fade = 0.15
	d.albedo_mix = o.get("mix", 1.0)
	d.modulate = o.get("modulate", Color.WHITE)
	d.distance_fade_enabled = true
	d.distance_fade_begin = o.get("loin", 22.0)
	d.distance_fade_length = 4.0
	add_child(d)
	nb_decalques += 1
	return d


func _sol(tex: String, p: Vector3, l: float, h: float, o := {}) -> Decal:
	return decal(tex, Vector3(p.x, zone.position.y, p.z), Vector3.UP, l, h, rnd.randf_range(0, 360) if not o.has("angle") else o["angle"], o)


# ================================================================ couloir complet

## Habille un couloir (axe Z local) : zone = volume intérieur (sol à zone.position.y).
## options : sol_tex / sol_echelle (texture du sol, vue sous l'eau des flaques), gaine (1 = à droite +X, -1 = à gauche, 0 = aucune), cables (côté du chemin de câbles),
## tuyaux (côté des canalisations), flaques (nombre), fuite (Vector3 : flaque sous un raccord qui
## goutte), dechets (densité 0-2), affiches (nombre), tags (nombre), fin_gaine (z où la gaine s'arrête)
func couloir(z: AABB, o := {}) -> void:
	zone = z
	rnd.seed = graine
	# contrôle : DECOR_SANS=gaine,cables,tuyaux,plinthes,salete,humidite,flaques,dechets,affiches
	var sans := OS.get_environment("DECOR_SANS").split(",")
	for k in ["gaine", "cables", "tuyaux"]:
		if k in sans:
			o[k] = 0
	if not "plafond" in sans:
		plafond_technique(o)
	if not "plinthes" in sans:
		plinthes()
	if not "salete" in sans:
		salete(o)
	if not "humidite" in sans:
		humidite(o)
	if not "flaques" in sans:
		flaques(o)
	if not "dechets" in sans:
		dechets(o)
	if not "affiches" in sans:
		affiches(o)


# ================================================================ plafond technique

func plafond_technique(o := {}) -> void:
	var cote_gaine: int = o.get("gaine", 1)
	var cote_cables: int = o.get("cables", -1)
	var cote_tuyaux: int = o.get("tuyaux", -1)
	if cote_gaine != 0:
		_gaine(cote_gaine, o)
	if cote_cables != 0:
		_chemin_cables(cote_cables)
	if cote_tuyaux != 0:
		_tuyaux(cote_tuyaux, o)
	_grilles_plafond()


## Gaine de ventilation rectangulaire suspendue (Poly Haven modular_airduct_rectangular_01).
func _gaine(cote: int, o: Dictionary) -> void:
	var seg := _maillage("modular_airduct_rectangular_01", "modular_airduct_rectangular_01_tripple_01")
	var bride := _maillage("modular_airduct_rectangular_01", "modular_airduct_rectangular_01_connector_01")
	var grille := _maillage("modular_airduct_rectangular_01", "modular_airduct_rectangular_01_vent_01")
	var fil := _maillage("modular_airduct_rectangular_01", "modular_airduct_rectangular_01_brace_wire_01")
	var etrier := _maillage("modular_airduct_rectangular_01", "modular_airduct_rectangular_01_brace_01")
	if seg == null:
		return
	var bb := seg.get_aabb()
	var lg := bb.size.z
	var haut := zone.end.y
	var x := zone.get_center().x + cote * (zone.size.x / 2.0 - bb.size.x / 2.0 - 0.12)
	var y := haut - 0.12 - bb.size.y / 2.0
	var z0 := zone.end.z - 0.05
	var z1: float = o.get("fin_gaine", zone.position.z + 0.6)
	var n := int(floor((z0 - z1) / lg))
	var xfs_seg := []
	var xfs_bride := []
	var xfs_fil := []
	var xfs_etrier := []
	for i in n:
		var zc := z0 - (i + 0.5) * lg
		# léger affaissement entre deux suspentes, une section un peu tournée
		var b := Basis().rotated(Vector3.RIGHT, deg_to_rad(rnd.randf_range(-0.4, 0.4)))
		xfs_seg.append(_poser(seg, b, Vector3(x, y - rnd.randf_range(0, 0.012), zc)))
		if bride:
			xfs_bride.append(_poser(bride, Basis(), Vector3(x, y, zc - lg / 2.0)))
		if etrier and fil:
			var ze := zc + lg * 0.25
			xfs_etrier.append(_poser(etrier, Basis(), Vector3(x, y - bb.size.y / 2.0 - 0.02, ze)))
			var fb := fil.get_aabb()
			var hf := haut - (y - bb.size.y / 2.0 - 0.02)
			var bf := Basis().scaled(Vector3(1, hf / fb.size.y, 1))
			xfs_fil.append(_poser(fil, bf, Vector3(x, haut, ze), Vector3(0.5, 1.0, 0.5)))
	_multi(_sali(seg, 0.5), xfs_seg)
	_multi(_sali(bride, 0.5), xfs_bride)
	_multi(etrier, xfs_etrier, false)
	_multi(fil, xfs_fil, false, false)
	# grilles de soufflage sur le flanc côté couloir
	if grille:
		var xg := []
		for i in range(0, n, 2):
			var zc := z0 - (i + 0.5 + rnd.randf_range(-0.2, 0.2)) * lg
			var b := Basis().rotated(Vector3.UP, -cote * PI / 2.0)
			xg.append(_poser(grille, b, Vector3(x - cote * (bb.size.x / 2.0 + 0.01), y, zc)))
		_multi(grille, xg)
	# extrémité : coude qui rentre dans le mur
	var coude := _maillage("modular_airduct_rectangular_01", "modular_airduct_rectangular_01_corner_02")
	if coude:
		var zf := z0 - n * lg
		var b := Basis().rotated(Vector3.UP, PI if cote > 0 else -PI / 2.0)
		_instance(coude, _poser(coude, b, Vector3(x + cote * 0.1, y, zf - 0.38)))
	# poussière noire sous les grilles et le long de la gaine au plafond
	for i in range(0, n, 2):
		decal(G + "crasse_coin.png", Vector3(x, haut, z0 - (i + 0.5) * lg), Vector3.DOWN, 0.9, lg * 0.9, 0.0,
			{"mix": 0.6, "relief": false})


## Copie d'un maillage importé dont les matériaux sont assombris et rendus plus mats (tôle encrassée).
func _sali(m: Mesh, k: float) -> Mesh:
	if m == null:
		return null
	var cle := "sali/%s/%s" % [m.get_rid(), k]
	if _maillages.has(cle):
		return _maillages[cle]
	var c := m.duplicate() as Mesh
	for i in c.get_surface_count():
		var mat := c.surface_get_material(i)
		if mat is BaseMaterial3D:
			var d := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
			d.albedo_color = d.albedo_color * Color(k, k * 0.97, k * 0.92)
			d.roughness = minf(1.0, d.roughness * 1.3 + 0.1)
			c.surface_set_material(i, d)
	_maillages[cle] = c
	return c


## Chemin de câbles en fil d'acier, suspendu par des tiges filetées, chargé de câbles ; quelques
## câbles en sortent et pendent jusqu'aux boîtes de dérivation des murs.
func _chemin_cables(cote: int) -> void:
	var lg := zone.size.z - 0.1
	var cz := zone.get_center().z
	var haut := zone.end.y
	var x := zone.get_center().x + cote * (zone.size.x / 2.0 - 0.38)
	var y := haut - 0.32
	var grill := StandardMaterial3D.new()
	grill.albedo_texture = load(G + "grillage_cables.png")
	grill.albedo_color = Color(0.55, 0.56, 0.55)
	grill.metallic = 0.85
	grill.roughness = 0.45
	grill.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	grill.alpha_scissor_threshold = 0.5
	grill.cull_mode = BaseMaterial3D.CULL_DISABLED
	grill.uv1_triplanar = true
	grill.uv1_world_triplanar = true
	grill.uv1_scale = Vector3.ONE * 2.0
	_boite(Vector3(0.3, 0.004, lg), Vector3(x, y, cz), grill)
	for s in [-1, 1]:
		_boite(Vector3(0.004, 0.06, lg), Vector3(x + s * 0.15, y + 0.03, cz), grill)
	# tiges filetées et traverses tous les 1,5 m
	var tige := CylinderMesh.new()
	tige.top_radius = 0.005
	tige.bottom_radius = 0.005
	tige.height = haut - y + 0.02
	tige.radial_segments = 6
	tige.rings = 1
	var trav := BoxMesh.new()
	trav.size = Vector3(0.42, 0.025, 0.03)
	var xt := []
	var xtr := []
	var zz := zone.end.z - 0.6
	while zz > zone.position.z + 0.3:
		for s in [-1, 1]:
			xt.append(Transform3D(Basis(), Vector3(x + s * 0.19, y + tige.height / 2.0 - 0.02, zz)))
		xtr.append(Transform3D(Basis(), Vector3(x, y - 0.015, zz)))
		zz -= 1.5
	var acier := _mat_simple(Color(0.3, 0.3, 0.29), 0.5, 0.8)
	_multi(tige, xt, false, false, acier)
	_multi(trav, xtr, true, true, acier)
	# câbles couchés dans le chemin : légers serpentements, couleurs ternes
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_sommets_st = 0
	var couleurs := [Color(0.04, 0.04, 0.04), Color(0.06, 0.06, 0.065), Color(0.18, 0.18, 0.17),
		Color(0.05, 0.05, 0.05), Color(0.35, 0.16, 0.05), Color(0.03, 0.03, 0.03), Color(0.22, 0.22, 0.2)]
	for c in couleurs.size():
		var r := rnd.randf_range(0.008, 0.017)
		var pts := PackedVector3Array()
		var dx := rnd.randf_range(-0.1, 0.1)
		var z := zone.end.z - 0.05
		while z > zone.position.z + 0.05:
			dx = clampf(dx + rnd.randf_range(-0.025, 0.025), -0.12, 0.12)
			pts.append(Vector3(x + dx, y + r + 0.004 + (c % 3) * 0.012, z))
			z -= 0.45
		pts.append(Vector3(x + dx, y + r + 0.004, zone.position.z + 0.05))
		_tube(st, pts, r, couleurs[c])
	# câbles qui pendent entre deux traverses (attaches cassées) et qui descendent aux boîtes murales
	var mur_x := zone.get_center().x + cote * zone.size.x / 2.0
	for i in 4:
		var za := rnd.randf_range(zone.position.z + 1.5, zone.end.z - 2.0)
		var zb := za - rnd.randf_range(1.2, 2.4)
		var a := Vector3(x + rnd.randf_range(-0.1, 0.1), y + 0.01, za)
		var b := Vector3(x + rnd.randf_range(-0.1, 0.1), y + 0.01, zb)
		_tube(st, _chainette(a, b, rnd.randf_range(0.12, 0.35), 14), rnd.randf_range(0.006, 0.01), couleurs[i])
	for i in 3:
		var zc := zone.end.z - 2.0 - i * zone.size.z / 3.2 + rnd.randf_range(-0.5, 0.5)
		var a := Vector3(x - cote * 0.1, y + 0.01, zc)
		var b := Vector3(mur_x - cote * 0.03, y - 0.25, zc + rnd.randf_range(-0.3, 0.3))
		var pts := _chainette(a, b, 0.12, 8)
		pts.append(b + Vector3(0, -0.6 - rnd.randf_range(0, 0.6), 0))   # descend le long du mur
		_tube(st, pts, 0.007, couleurs[(i + 2) % couleurs.size()])
		if i == 0:
			# coffret électrique (Poly Haven power_box_01) au bout du premier câble
			var cof: Node3D = (load(D + "models/power_box_01/power_box_01.gltf") as PackedScene).instantiate()
			add_child(cof)
			cof.rotation_degrees.y = 90.0 if cote < 0 else -90.0
			cof.position = Vector3(mur_x - cote * 0.05, pts[pts.size() - 1].y - 0.3, pts[pts.size() - 1].z)
			continue
		var boite := _maillage("modular_electric_cables", "cable_box_3way")
		if boite:
			var bx := Basis().rotated(Vector3.UP, 0.0 if cote < 0 else PI)
			_instance(boite, _poser(boite, bx, pts[pts.size() - 1] + Vector3(cote * 0.0, -0.08, 0)))
	st.generate_tangents()
	var mc := StandardMaterial3D.new()
	mc.vertex_color_use_as_albedo = true
	mc.roughness = 0.55
	mc.cull_mode = BaseMaterial3D.CULL_DISABLED
	var cables := MeshInstance3D.new()
	cables.mesh = st.commit()
	cables.material_override = mc
	add_child(cables)


## Canalisations métalliques le long d'un mur (deux conduites sur colliers), une vanne, un raccord
## qui fuit (coulure de rouille, flaque en dessous si `fuite` est donné).
func _tuyaux(cote: int, o: Dictionary) -> void:
	var mur_x := zone.get_center().x + cote * zone.size.x / 2.0
	var haut := zone.end.y
	var metal := _mat_tex_modele("modular_pipes", "metal", Color(0.62, 0.6, 0.55))
	var lg := zone.size.z - 0.05
	var cz := zone.get_center().z
	var hauteurs := [haut - 0.42, haut - 0.6]
	var rayons := [0.05, 0.035]
	for i in 2:
		var cy := CylinderMesh.new()
		cy.top_radius = rayons[i]
		cy.bottom_radius = rayons[i]
		cy.height = lg
		cy.radial_segments = 14
		cy.rings = 1
		var mi := _instance(cy, Transform3D(Basis().rotated(Vector3.RIGHT, PI / 2.0), Vector3(mur_x - cote * (0.09 + i * 0.02), hauteurs[i], cz)))
		mi.material_override = metal
	# colliers muraux tous les 2 m (pièces du kit modular_pipes)
	var collier := _maillage("modular_pipes", "pipe_support_metal")
	if collier:
		var xs := []
		var z := zone.end.z - 0.8
		while z > zone.position.z + 0.3:
			for i in 2:
				var b := Basis().rotated(Vector3.UP, PI / 2.0 if cote < 0 else -PI / 2.0)
				xs.append(_poser(collier, b, Vector3(mur_x - cote * 0.07, hauteurs[i] - rayons[i], z), Vector3(0.5, 1.0, 0.5)))
			z -= 2.0
		_multi(collier, xs, true, true)
	# brides de raccord (anneaux plus larges) tous les 3 m
	var bride := CylinderMesh.new()
	bride.top_radius = 0.065
	bride.bottom_radius = 0.065
	bride.height = 0.04
	bride.radial_segments = 14
	bride.rings = 1
	var xb := []
	var z2 := zone.end.z - 1.4
	while z2 > zone.position.z + 0.5:
		xb.append(Transform3D(Basis().rotated(Vector3.RIGHT, PI / 2.0), Vector3(mur_x - cote * 0.09, hauteurs[0], z2)))
		z2 -= 3.0
	_multi(bride, xb, true, true, metal)
	# vanne sur la petite conduite
	var vanne := _maillage("modular_pipes", "pipe_thin_valve_1_metal")
	if vanne:
		var zv := zone.position.z + zone.size.z * 0.62
		var b := Basis().rotated(Vector3.RIGHT, PI / 2.0)
		_instance(vanne, _poser(vanne, b, Vector3(mur_x - cote * 0.11, hauteurs[1], zv)))
	# raccord qui fuit : coulure de rouille au mur, traînée d'eau, flaque au sol
	if o.has("fuite"):
		var f: Vector3 = o["fuite"]
		var nrm := Vector3(-cote, 0, 0)
		decal(G + "coulure_rouille.png", Vector3(mur_x, hauteurs[0] - 0.8, f.z), nrm, 0.35, 1.6, 0.0, {"relief": false})
		decal(A + "humidite_b.png", Vector3(mur_x, hauteurs[0] - 1.1, f.z + 0.1), nrm, 0.7, 2.2, 0.0, {"mix": 0.8})


func _mat_tex_modele(modele: String, partie: String, teinte := Color.WHITE) -> ORMMaterial3D:
	var cle := "mod/%s/%s" % [modele, partie]
	if _mat_cache.has(cle):
		return _mat_cache[cle]
	var base := D + "models/%s/textures/%s_%s_" % [modele, modele, partie]
	var m := ORMMaterial3D.new()
	m.albedo_texture = load(base + "diff_1k.jpg")
	m.albedo_color = teinte
	m.orm_texture = load(base + "arm_1k.jpg")
	m.normal_enabled = true
	m.normal_texture = load(base + "nor_gl_1k.jpg")
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * 1.5
	_mat_cache[cle] = m
	return m


## Grilles d'aération au plafond (cadre + lames), avec leur auréole de poussière noire.
func _grilles_plafond() -> void:
	var g := _maillage("modular_airduct_rectangular_01", "modular_airduct_rectangular_01_vent_02")
	if g == null:
		return
	var xs := []
	var z := zone.end.z - 3.0
	while z > zone.position.z + 1.0:
		var p := Vector3(zone.get_center().x + rnd.randf_range(-0.3, 0.1), zone.end.y - 0.02, z)
		if _libre_mur(p):
			var b := Basis().rotated(Vector3.RIGHT, -PI / 2.0)
			xs.append(_poser(g, b, p, Vector3(0.5, 0.5, 0.0)))
			decal(G + "crasse_coin.png", Vector3(p.x, zone.end.y, p.z), Vector3.DOWN, 0.9, 0.9, 90.0, {"mix": 0.7, "relief": false})
		z -= rnd.randf_range(5.5, 7.5)
	_multi(g, xs)


# ================================================================ murs

## Plinthes peintes, sales, ébréchées par endroits (bandes de 10 cm au pied des murs).
func plinthes() -> void:
	var m := KitDecor.materiau("painted_concrete", 1.2, Color(0.2, 0.22, 0.21),
		{"salete": 0.12, "salete_force": 0.8, "variation": 0.3, "decalage": Vector2(3, 7)})
	var lg := zone.size.z
	for s in [-1, 1]:
		var x: float = zone.get_center().x + s * (zone.size.x / 2.0 - 0.04)
		var mi := _boite(Vector3(0.02, 0.1, lg), Vector3(x, zone.position.y + 0.05, zone.get_center().z), m, false)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


# ================================================================ saleté

## Poussière et crasse au sol (le long des murs, dans les coins, traces de pas), fissures,
## chewing-gums ; crasse verticale dans les angles.
func salete(o := {}) -> void:
	var x0 := zone.position.x
	var x1 := zone.end.x
	var y0 := zone.position.y
	# bande sale au pied des deux murs, par tronçons de longueur variable
	for s in [-1, 1]:
		var z := zone.end.z
		while z > zone.position.z:
			var l := rnd.randf_range(1.8, 3.2)
			var x: float = (x0 if s < 0 else x1) - s * 0.25
			# haut de l'image contre le mur
			decal(G + "crasse_sol_mur.png", Vector3(x, y0, z - l / 2.0), Vector3.UP, l, 0.6,
				90.0 if s > 0 else -90.0, {"relief": false, "profondeur": 0.3, "mix": rnd.randf_range(0.7, 1.0)})
			z -= l * rnd.randf_range(0.85, 1.05)
	# plaques de poussière
	var n := int(zone.size.z / 2.2)
	for i in n:
		var p := Vector3(rnd.randf_range(x0 + 0.3, x1 - 0.3), y0, rnd.randf_range(zone.position.z + 0.5, zone.end.z - 0.5))
		_sol(G + "poussiere_%d.png" % (1 + i % 3), p, rnd.randf_range(1.2, 2.4), rnd.randf_range(1.0, 2.0), {"relief": false, "mix": rnd.randf_range(0.5, 0.9)})
	# traces de pas poussiéreuses au milieu
	_sol(G + "traces_pas.png", Vector3(zone.get_center().x + rnd.randf_range(-0.4, 0.4), y0, zone.get_center().z + rnd.randf_range(-3, 3)),
		0.55, 1.1, {"angle": rnd.randf_range(-12, 12), "relief": false, "mix": 0.7})
	# fissures, chewing-gums
	for i in 3:
		var p := Vector3(rnd.randf_range(x0 + 0.4, x1 - 0.4), y0, rnd.randf_range(zone.position.z + 1, zone.end.z - 1))
		_sol(A + "fissure_%d.png" % (1 + i % 4), p, rnd.randf_range(1.5, 2.6), rnd.randf_range(0.4, 0.6), {"mix": 0.85, "modulate": Color(0.32, 0.3, 0.27)})
	for i in 2:
		var p := Vector3(rnd.randf_range(x0 + 0.5, x1 - 0.5), y0, rnd.randf_range(zone.position.z + 1, zone.end.z - 1))
		_sol(A + "chewing_gum.png", p, 0.7, 0.7, {"mix": 0.9, "modulate": Color(0.28, 0.27, 0.26)})
	# murs : éraflures de chariots et de semelles en bas, mains et frottements à hauteur de hanche
	for s in [-1, 1]:
		var xm: float = x0 if s < 0 else x1
		var z := zone.end.z - rnd.randf_range(0.2, 1.5)
		while z > zone.position.z + 0.5:
			var l := rnd.randf_range(1.2, 2.6)
			var p := Vector3(xm, y0 + rnd.randf_range(0.18, 0.4), z - l / 2.0)
			if _libre_mur(p):
				decal(G + "eraflures.png", p, Vector3(-s, 0, 0), l, l * 0.25, rnd.randf_range(-2, 2), {"relief": false, "normal_fade": 0.4, "mix": rnd.randf_range(0.5, 0.9)})
			var q := Vector3(xm, y0 + rnd.randf_range(0.9, 1.5), z - rnd.randf_range(0, l))
			if _libre_mur(q) and rnd.randf() < 0.6:
				decal(G + "poussiere_%d.png" % (1 + rnd.randi() % 3), q, Vector3(-s, 0, 0), rnd.randf_range(0.6, 1.2), rnd.randf_range(0.5, 0.9),
					rnd.randf_range(0, 360), {"relief": false, "normal_fade": 0.4, "mix": 0.55, "modulate": Color(0.35, 0.31, 0.26)})
			z -= l + rnd.randf_range(0.3, 1.6)
	# crasse verticale dans les quatre angles
	for c in [Vector3(x0, 0, zone.position.z), Vector3(x1, 0, zone.position.z), Vector3(x0, 0, zone.end.z), Vector3(x1, 0, zone.end.z)]:
		var dz: float = 1.0 if c.z < zone.get_center().z else -1.0
		var dx: float = 1.0 if c.x < zone.get_center().x else -1.0
		decal(G + "crasse_coin.png", Vector3(c.x, y0 + zone.size.y / 2.0, c.z + dz * 0.15), Vector3(dx, 0, 0), 0.5, zone.size.y, 0.0, {"relief": false, "normal_fade": 0.1})
		decal(G + "crasse_coin.png", Vector3(c.x + dx * 0.15, y0 + zone.size.y / 2.0, c.z), Vector3(0, 0, dz), 0.5, zone.size.y, 0.0, {"relief": false, "normal_fade": 0.1})


## Coulures d'humidité depuis le plafond, auréoles brunes au plafond, traînées d'eau.
func humidite(o := {}) -> void:
	var haut := zone.end.y
	for i in int(zone.size.z / 4.0):
		var s: int = -1 if rnd.randf() < 0.5 else 1
		var x := zone.get_center().x + s * zone.size.x / 2.0
		var z := rnd.randf_range(zone.position.z + 0.6, zone.end.z - 0.6)
		var h := rnd.randf_range(1.2, 2.4)
		var p := Vector3(x, haut - h / 2.0, z)
		if not _libre_mur(p):
			continue
		var tex: String = [A + "humidite_a.png", A + "humidite_b.png", A + "traces_eau_1.png", A + "traces_eau_2.png"][i % 4]
		decal(tex, p, Vector3(-s, 0, 0), rnd.randf_range(1.0, 2.2), h, 0.0, {"mix": rnd.randf_range(0.6, 0.9)})
	for i in maxi(2, int(zone.size.z / 7.0)):
		var p := Vector3(rnd.randf_range(zone.position.x + 0.4, zone.end.x - 0.4), haut, rnd.randf_range(zone.position.z + 1, zone.end.z - 1))
		decal(G + "tache_humidite_%d.png" % (1 + i % 2), p, Vector3.DOWN, rnd.randf_range(1.2, 2.2), rnd.randf_range(1.2, 2.2), rnd.randf_range(0, 360), {"relief": false})


# ================================================================ flaques

## Flaques d'eau sale : maillage plat presque noir, rugosité très faible (reflets SSR et sonde de
## reflets bornée au couloir : les néons et le contre-jour s'y reflètent), halo de sol mouillé.
func flaques(o := {}) -> void:
	var pos: Array = (o.get("flaques_pos", []) as Array).duplicate()
	if o.has("fuite"):
		pos.append(o["fuite"])
	var n: int = o.get("flaques", 2)
	var essais := 0
	while pos.size() < n + (1 if o.has("fuite") else 0) and essais < 40:
		essais += 1
		var p := Vector3(rnd.randf_range(zone.position.x + 0.5, zone.end.x - 0.5), 0, rnd.randf_range(zone.position.z + 1, zone.end.z - 1.5))
		if _libre(p, 0.4):
			pos.append(p)
	var nor: Texture2D = load(G + "flaque_nor.png")
	var st: String = o.get("sol_tex", "hangar_concrete_floor")
	var sol_albedo: Texture2D = load(D + "tex/%s/%s_diff_2k.jpg" % [st, st])
	for i in pos.size():
		var p: Vector3 = pos[i]
		var l := rnd.randf_range(1.5, 2.3)
		var w := l * rnd.randf_range(0.6, 0.9)
		var ang := rnd.randf_range(0, TAU)
		var m := ShaderMaterial.new()
		m.shader = SHADER_FLAQUE
		m.set_shader_parameter("masque", load(G + "flaque_%d.png" % (1 + i % 3)))
		m.set_shader_parameter("sol_albedo", sol_albedo)
		m.set_shader_parameter("sol_echelle", o.get("sol_echelle", 0.35))
		m.set_shader_parameter("vaguelettes", nor)
		var pm := PlaneMesh.new()
		pm.size = Vector2(w, l)
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		mi.material_override = m
		mi.layers = 1 | CALQUE_FLAQUE
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mi.transform = Transform3D(Basis().rotated(Vector3.UP, ang), Vector3(p.x, zone.position.y + 0.004, p.z))
		add_child(mi)
		# halo humide plus large, plus sombre
		_sol(G + "mouille_%d.png" % (1 + i % 3), p, w * 1.7, l * 1.6, {"angle": rad_to_deg(ang), "relief": false, "mix": 0.9})
	if not pos.is_empty() and not "sonde" in OS.get_environment("DECOR_SANS").split(","):
		_sonde_reflets()


func _sonde_reflets() -> void:
	var s := ReflectionProbe.new()
	s.name = "SondeFlaques"
	s.update_mode = ReflectionProbe.UPDATE_ONCE
	s.size = zone.size + Vector3(0.2, 0.2, 0.2)
	s.position = zone.get_center()
	s.origin_offset = Vector3(0, -zone.size.y / 2.0 + 1.3, 0)
	s.box_projection = true
	s.interior = true
	s.enable_shadows = true
	s.cull_mask = 1 | CALQUE_DECOR
	s.reflection_mask = CALQUE_FLAQUE
	s.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	s.intensity = 1.0
	s.max_distance = zone.size.z
	add_child(s)


# ================================================================ déchets

## Déchets épars, surtout le long des murs : sacs-poubelle, canettes rouillées, bidon, sac de ciment,
## mégots (instances groupées), papiers et cendres (décalques).
func dechets(o := {}) -> void:
	var densite: float = o.get("dechets", 1.0)
	var x0 := zone.position.x
	var x1 := zone.end.x
	var y0 := zone.position.y
	var bords := func(marge: float) -> Vector3:
		var s: float = -1.0 if rnd.randf() < 0.5 else 1.0
		var x := (x0 if s < 0 else x1) - s * rnd.randf_range(0.12, marge)
		return Vector3(x, y0, rnd.randf_range(zone.position.z + 0.5, zone.end.z - 0.5))
	# objets 3D (sans collision : les balles et le joueur passent, comme de vrais déchets légers)
	var objets := [["trashbag", "trashbag", 0.3], ["can_rusted", "can_rusted", 0.4], ["can_rusted", "can_rusted", 0.4],
		["can_rusted", "can_rusted", 0.9], ["plastic_bottle_gallon", "plastic_bottle_gallon", 0.35], ["cement_bag", "cement_bag", 0.3]]
	var n := int(round(objets.size() * densite))
	for i in n:
		var e: Array = objets[i % objets.size()]
		var p: Vector3 = bords.call(e[2])
		if not _libre(p, 0.3):
			continue
		var m := _maillage(e[0], e[1])
		if m == null:
			continue
		var b := Basis().rotated(Vector3.UP, rnd.randf_range(0, TAU))
		if e[0] == "can_rusted" and rnd.randf() < 0.7:
			b = b * Basis().rotated(Vector3.RIGHT, PI / 2.0)        # canette couchée
		elif e[0] == "plastic_bottle_gallon":
			b = b * Basis().rotated(Vector3.FORWARD, PI / 2.0)
		var mi := _instance(m, _poser(m, b, p, Vector3(0.5, 0.0, 0.5)))
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		if e[0] == "can_rusted" and rnd.randf() < 0.5:
			mi.scale = Vector3.ONE * 0.85
	# mégots : petits groupes contre les murs et près des portes
	var cig := _maillage("cigarette_pack", "cigarette_pack_cigarette")
	if cig:
		var xs := []
		var bb := cig.get_aabb()
		for g in int(4 * densite):
			var c: Vector3 = bords.call(0.6)
			if not _libre(c, 0.2):
				continue
			decal(G + "megots.png", c, Vector3.UP, 0.5, 0.5, rnd.randf_range(0, 360), {"relief": false})
			for k in rnd.randi_range(3, 7):
				var p := c + Vector3(rnd.randf_range(-0.2, 0.2), 0, rnd.randf_range(-0.2, 0.2))
				# mégot = bout filtre de 3 cm, couché, écrasé
				var b := Basis().rotated(Vector3.UP, rnd.randf_range(0, TAU)) * Basis().rotated(Vector3.RIGHT, PI / 2.0)
				b = b.scaled_local(Vector3(1.0, rnd.randf_range(0.3, 0.45), rnd.randf_range(0.7, 1.0)))
				xs.append(_poser(cig, b, p + Vector3(0, 0.004, 0), Vector3(0.5, 0.0, 0.5)))
		_multi(cig, xs, false, false)
	# papiers au sol
	for i in int(6 * densite):
		var p: Vector3 = bords.call(0.9) if rnd.randf() < 0.7 else Vector3(rnd.randf_range(x0 + 0.4, x1 - 0.4), y0, rnd.randf_range(zone.position.z + 0.5, zone.end.z - 0.5))
		var t := rnd.randf_range(0.28, 0.5)
		_sol(G + "papier_%d.png" % (1 + i % 4), p, t, t, {"profondeur": 0.1, "modulate": Color(0.62, 0.6, 0.55)})


# ================================================================ affiches et tags

## Affiches (avis de recherche, publicité, consignes de l'aéroport, interdiction de fumer, lambeaux)
## et tags (dont ceux du cartel) sur les murs, à hauteur d'yeux, jamais sur les zones `evite_murs`.
func affiches(o := {}) -> void:
	var lst := [["affiche_recherche", 0.42, 0.59], ["affiche_pub", 0.5, 0.7], ["affiche_securite", 0.55, 0.75],
		["panneau_fumer", 0.35, 0.35], ["affiche_lambeaux", 0.5, 0.7], ["affiche_recherche", 0.42, 0.59]]
	var n: int = o.get("affiches", 5)
	var places := []
	var essais := 0
	while places.size() < n and essais < 60:
		essais += 1
		var s: int = -1 if rnd.randf() < 0.5 else 1
		var x := zone.get_center().x + s * zone.size.x / 2.0
		var p := Vector3(x, zone.position.y + rnd.randf_range(1.35, 1.75), rnd.randf_range(zone.position.z + 0.8, zone.end.z - 0.8))
		if not _libre_mur(p):
			continue
		var ok := true
		for q in places:
			if (q as Vector3).distance_to(p) < 1.6:
				ok = false
		if not ok:
			continue
		places.append(p)
		var e: Array = lst[places.size() - 1 if places.size() - 1 < lst.size() else rnd.randi() % lst.size()]
		var k := rnd.randf_range(0.95, 1.15)
		decal(G + e[0] + ".png", p, Vector3(-s, 0, 0), e[1] * k, e[2] * k, rnd.randf_range(-3, 3), {"profondeur": 0.12, "normal_fade": 0.5})
		# vieille affiche arrachée dessous, de travers
		if rnd.randf() < 0.4:
			decal(G + "affiche_lambeaux.png", p + Vector3(0, -0.1, rnd.randf_range(-0.2, 0.2)), Vector3(-s, 0, 0), 0.55, 0.75, rnd.randf_range(-8, 8), {"profondeur": 0.13, "normal_fade": 0.5})
	# tags
	var tags := [G + "tag_cartel_2.png", A + "graffiti_1.png", G + "tag_cartel_3.png", A + "graffiti_3.png", A + "graffiti_5.png", A + "graffiti_2.png"]
	var nt: int = o.get("tags", 4)
	essais = 0
	var poses := 0
	while poses < nt and essais < 60:
		essais += 1
		var s: int = -1 if rnd.randf() < 0.5 else 1
		var x := zone.get_center().x + s * zone.size.x / 2.0
		var p := Vector3(x, zone.position.y + rnd.randf_range(0.6, 1.9), rnd.randf_range(zone.position.z + 0.8, zone.end.z - 0.8))
		if not _libre_mur(p):
			continue
		var ok := true
		for q in places:
			if (q as Vector3).distance_to(p) < 1.0:
				ok = false
		if not ok:
			continue
		places.append(p)
		var t: String = tags[poses % tags.size()]
		var large := t.contains("tag_cartel")
		var l := rnd.randf_range(1.4, 2.0) if large else rnd.randf_range(0.7, 1.1)
		decal(t, p, Vector3(-s, 0, 0), l, l * (0.5 if large else 1.0), rnd.randf_range(-6, 6), {"relief": false, "mix": 0.92, "normal_fade": 0.4})
		poses += 1


# ================================================================ portes

## Porte de service métallique abîmée (tools/blender/build_porte.py) : `pos` = pied du gond (repère
## local), `rot_y` = orientation (0 : face avant vers +Z), `ouverture` en degrés (0 = fermée, vers
## l'arrière de la porte). Peinture verte écaillée sur rouille (Poly Haven green_metal_rust), béquille
## et paumelles en acier ; collision sur le vantail (méta matériau « metal »).
func porte(pos: Vector3, rot_y := 0.0, ouverture := 0.0, teinte := Color(0.6, 0.66, 0.62)) -> Node3D:
	var n: Node3D = (load(D + "models/porte_metal/porte_metal.glb") as PackedScene).instantiate()
	n.name = "Porte"
	n.position = pos
	n.rotation_degrees.y = rot_y
	add_child(n)
	# peinture verte écaillée, plaques de rouille, bas noirci (même anti-répétition que les murs)
	var peinture := KitDecor.materiau("green_metal_rust", 0.9, teinte, {"tex2": "rusty_painted_metal",
		"echelle2": 0.55, "part_second": 0.42, "salete": 0.45, "salete_force": 0.8, "sol_y": pos.y,
		"variation": 0.3, "decalage": Vector2(rnd.randf_range(0, 20), rnd.randf_range(0, 20)), "relief": 1.4})
	var acier := _mat_simple(Color(0.42, 0.41, 0.39), 0.42, 0.9)
	var grille := _mat_simple(Color(0.05, 0.05, 0.05), 0.6, 0.3)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		for s in m.get_surface_count():
			var nom := m.surface_get_material(s).resource_name if m.surface_get_material(s) else ""
			(mi as MeshInstance3D).set_surface_override_material(s, acier if nom.begins_with("acier") else grille if nom.begins_with("grille") else peinture)
	var battant := n.find_child("battant", true, false) as Node3D
	if battant:
		battant.rotation_degrees.y = -ouverture
		var sb := StaticBody3D.new()
		sb.set_meta("materiau", "metal")
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(0.92, 2.04, 0.05)
		cs.shape = sh
		cs.position = Vector3(0.46, 1.02, 0)
		sb.add_child(cs)
		battant.add_child(sb)
	# éraflures et crasse au bas, traces de mains près de la béquille
	var b := n.basis
	var avant := b * Vector3(0, 0, 1)
	# crasse sur le vantail : bas noirci, traces de mains autour de la béquille, coulures
	if battant:
		var av := battant.global_basis if battant.is_inside_tree() else n.basis * battant.basis
		var o0 := battant.global_position if battant.is_inside_tree() else pos
		var nf := av * Vector3(0, 0, 1)
		decal(G + "crasse_sol_mur.png", o0 + av * Vector3(0.46, 0.25, 0.0), nf, 0.95, 0.5, 180.0, {"relief": false, "profondeur": 0.1, "normal_fade": 0.5})
		decal(G + "poussiere_2.png", o0 + av * Vector3(0.78, 1.1, 0.0), nf, 0.35, 0.45, 20.0, {"relief": false, "profondeur": 0.1, "normal_fade": 0.5, "modulate": Color(0.25, 0.22, 0.18)})
		decal(A + "traces_eau_1.png", o0 + av * Vector3(0.4, 1.4, 0.0), nf, 0.9, 1.3, 0.0, {"relief": false, "profondeur": 0.1, "normal_fade": 0.5, "mix": 0.8})
		decal(G + "eraflures.png", o0 + av * Vector3(0.46, 0.55, 0.0), nf, 0.9, 0.25, 4.0, {"relief": false, "profondeur": 0.1, "normal_fade": 0.5})
	if ouverture < 5.0:
		decal(G + "crasse_coin.png", pos + b * Vector3(0.46, 0.3, 0.03), avant, 0.9, 0.6, 90.0, {"relief": false, "mix": 0.8, "profondeur": 0.08})
	return n
