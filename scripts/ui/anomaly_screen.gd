class_name AnomalyScreen
extends Control
## Anomalía espacial: un evento breve resuelto desde la nave, sin mapa de superficie.

signal finished

var event_id := ""
var restored: Dictionary = {}
var _result: Dictionary = {}
var _choice := -1

var _overlay: Overlay
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()
	add_child(UITheme.background())
	_overlay = Overlay.new()
	add_child(_overlay)
	if not restored.is_empty():
		_rng.state = restored["rng"]
		_result = restored["result"]
		_choice = restored["choice"]
	if not _result.is_empty():
		_overlay.show_result(event_id, _choice, _result, func(): finished.emit())
		return
	_overlay.present_event(
		event_id,
		func(i: int):
			_choice = i
			_result = EventRunner.resolve(event_id, i, Content.events[event_id]["choices"][i], GameState, _rng)
			return _result,
		func(): finished.emit())


func save_state() -> Dictionary:
	return {"kind": "anomaly", "rng": _rng.state, "result": _result, "choice": _choice}
