extends Node
## Bus audio : Musique / Effets / Voix / Ambiance (réglables), Radio (voix de Vincent, filtrée)
## et trois bus de réverbération selon la pièce (petite pièce, couloir, extérieur).
## Les zones de réverbération du niveau (Area3D) envoient le son des tirs vers le bon bus.

const REVERBS := {
	"Rev_Petite": {"taille": 0.25, "amorti": 0.6, "humide": 0.22, "predelai": 8.0},
	"Rev_Couloir": {"taille": 0.6, "amorti": 0.35, "humide": 0.34, "predelai": 25.0},
	"Rev_Hangar": {"taille": 0.95, "amorti": 0.2, "humide": 0.42, "predelai": 60.0},
	"Rev_Exterieur": {"taille": 0.85, "amorti": 0.75, "humide": 0.12, "predelai": 110.0},
}


func _enter_tree() -> void:
	_creer_bus("Musique", "Master")
	_creer_bus("Effets", "Master")
	_creer_bus("Voix", "Master")
	_creer_bus("Ambiance", "Master")
	_creer_bus("Radio", "Voix")
	var radio := AudioServer.get_bus_index("Radio")
	if AudioServer.get_bus_effect_count(radio) == 0:
		var bp := AudioEffectBandPassFilter.new()
		bp.cutoff_hz = 1800.0
		bp.resonance = 0.6
		AudioServer.add_bus_effect(radio, bp)
		var dist := AudioEffectDistortion.new()
		dist.mode = AudioEffectDistortion.MODE_OVERDRIVE
		dist.drive = 0.25
		dist.post_gain = -3.0
		AudioServer.add_bus_effect(radio, dist)
	for nom in REVERBS:
		_creer_bus(nom, "Effets")
		var i := AudioServer.get_bus_index(nom)
		if AudioServer.get_bus_effect_count(i) == 0:
			var r := AudioEffectReverb.new()
			var p: Dictionary = REVERBS[nom]
			r.room_size = p["taille"]
			r.damping = p["amorti"]
			# bus d'envoi : seulement la queue de réverbération (le son direct passe par « Effets »)
			r.wet = clamp(p["humide"] * 2.2, 0.0, 1.0)
			r.dry = 0.0
			r.predelay_msec = p["predelai"]
			r.predelay_feedback = 0.3
			AudioServer.add_bus_effect(i, r)
	# compresseur sur les effets : les tirs ne saturent pas
	var e := AudioServer.get_bus_index("Effets")
	if AudioServer.get_bus_effect_count(e) == 0:
		var c := AudioEffectCompressor.new()
		c.threshold = -10.0
		c.ratio = 6.0
		c.attack_us = 200.0
		AudioServer.add_bus_effect(e, c)
		var lim := AudioEffectHardLimiter.new()
		AudioServer.add_bus_effect(e, lim)


func _creer_bus(nom: String, vers: String) -> void:
	if AudioServer.get_bus_index(nom) >= 0:
		return
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, nom)
	AudioServer.set_bus_send(i, vers)


## Joue un son 3D ponctuel (le nœud se détruit à la fin).
func son_3d(flux: AudioStream, pos: Vector3, parent: Node, volume_db := 0.0, hauteur := 1.0, bus := "Effets", portee := 60.0) -> AudioStreamPlayer3D:
	if flux == null or parent == null or not parent.is_inside_tree():
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = flux
	p.volume_db = volume_db
	p.pitch_scale = hauteur
	p.bus = bus
	p.max_distance = portee
	p.unit_size = 6.0
	p.attenuation_filter_cutoff_hz = 6000.0
	parent.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()
	return p


## Son non spatialisé (corps du joueur : respiration, cœur, rechargement…).
func son_2d(flux: AudioStream, parent: Node, volume_db := 0.0, hauteur := 1.0, bus := "Effets") -> AudioStreamPlayer:
	if flux == null or parent == null:
		return null
	var p := AudioStreamPlayer.new()
	p.stream = flux
	p.volume_db = volume_db
	p.pitch_scale = hauteur
	p.bus = bus
	parent.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
	return p
