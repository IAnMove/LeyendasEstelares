class_name Expedition
extends RefCounted
## Una salida a la superficie: mapa + jugador + reglas de movimiento y eventos.

const VISION := 2

var state
var planet: Dictionary
var events: Dictionary
var map := PlanetData.new()
var player := Vector2i.ZERO
var objective_done := false


func _init(state_, planet_: Dictionary, events_: Dictionary, seed_value: int) -> void:
	state = state_
	planet = planet_
	events = events_
	map.generate(planet, events, seed_value)
	player = map.ship_cell
	map.reveal(player, VISION)


func can_move(c: Vector2i) -> bool:
	return HexGrid.distance(player, c) == 1 and map.is_passable(c)


## Mueve al jugador (gasta oxígeno). Devuelve {poi, failure, home}.
func move(c: Vector2i) -> Dictionary:
	state.spend_oxygen(map.move_cost(c))
	player = c
	map.reveal(player, VISION)
	var home := c == map.ship_cell and objective_done
	var poi := map.poi_at(c)
	if not poi.is_empty() and poi["resolved"]:
		poi = {}
	return {
		"poi": poi,
		"failure": "" if home else state.failure_reason(),
		"home": home,
	}


func event_of(poi: Dictionary) -> Dictionary:
	return events[poi["event_id"]]


func resolve_choice(poi: Dictionary, index: int, rng: RandomNumberGenerator) -> Dictionary:
	var choice: Dictionary = event_of(poi)["choices"][index]
	var result := EventRunner.resolve(poi["event_id"], index, choice, state, rng)
	poi["resolved"] = true
	if poi["objective"]:
		objective_done = true
	return result


func snapshot() -> Dictionary:
	return {"map": map.snapshot(), "player": player, "objective_done": objective_done}


func restore(saved: Dictionary) -> void:
	map.restore(saved["map"])
	player = saved["player"]
	objective_done = saved["objective_done"]


## Solo terreno ya descubierto; los eventos pueden alterar el consumo posterior.
func return_cost() -> int:
	return int(map.path_costs(player, true).get(map.ship_cell, -1))


func return_path() -> Array[Vector2i]:
	return map.find_path(player, map.ship_cell, true)
