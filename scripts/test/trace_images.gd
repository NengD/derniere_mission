extends Node
## Outil de diagnostic (salle de test, variable d'environnement TRACE_IMAGES) : pour chaque image lente
## (> 35 ms), affiche les compilations de pipelines (shaders) faites pendant les images voisines.

var _t := 0.0
var _hist: Array = []


func _compil() -> Array:
	return [
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION),
	]


func _process(delta: float) -> void:
	_t += delta
	_hist.append([snapped(_t, 0.001), int(delta * 1000.0), _compil()])
	if _hist.size() > 6:
		_hist.pop_front()
	if delta > 0.035:
		print("TRACE ", _hist)
