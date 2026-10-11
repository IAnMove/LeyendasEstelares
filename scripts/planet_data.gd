class_name PlanetData
extends RefCounted
## Mapa hexagonal de un planeta: terreno, puntos de interés, niebla y rutas.
## Es lógica pura (sin nodos) para poder probarla en headless.

const COLS := 11
const ROWS := 9

const TERRAINS := {
	"llanura": {"cost": 1, "passable": true},
	"roca": {"cost": 2, "passable": true},
	"hielo": {"cost": 2, "passable": true},
	"crater": {"cost": 3, "passable": true},
	"grieta": {"cost": 0, "passable": false},
}

var terrain := {}  # Vector2i -> String
var revealed := {}  # Vector2i -> true
var ship_cell := Vector2i.ZERO
var beacon_cell := Vector2i.ZERO
var pois: Array[Dictionary] = []  # {cell, type, event_id, resolved, objective}


func generate(planet: Dictionary, events: Dictionary, seed_value: int) -> void:
	for attempt in 80:
		if _try_generate(planet, events, seed_value + attempt * 7919):
			return
	# Último recurso: llanura sin obstáculos, siempre con baliza alcanzable (nunca una partida sin objetivo).
	if not _try_generate(planet, events, seed_value, true):
		push_error("PlanetData: no se pudo generar un mapa válido para %s" % planet.get("id", "?"))


func is_passable(c: Vector2i) -> bool:
	return terrain.has(c) and TERRAINS[terrain[c]]["passable"]


func move_cost(c: Vector2i) -> int:
	return int(TERRAINS[terrain[c]]["cost"])


func reveal(center_cell: Vector2i, radius: int) -> void:
	for c in terrain:
		if HexGrid.distance(c, center_cell) <= radius:
			revealed[c] = true


func poi_at(c: Vector2i) -> Dictionary:
	for p in pois:
		if p["cell"] == c:
			return p
	return {}


## Coste mínimo de oxígeno desde `from` a cada casilla alcanzable.
func path_costs(from: Vector2i, known_only := false) -> Dictionary:
	return _dijkstra(from, known_only)["dist"]


## Ruta (sin incluir `from`) de menor coste; vacía si no hay.
func find_path(from: Vector2i, to: Vector2i, known_only := false) -> Array[Vector2i]:
	var res := _dijkstra(from, known_only)
	var prev: Dictionary = res["prev"]
	var path: Array[Vector2i] = []
	if not res["dist"].has(to):
		return path
	var cur := to
	while cur != from:
		path.push_front(cur)
		cur = prev[cur]
	return path


func _dijkstra(from: Vector2i, known_only := false) -> Dictionary:
	var dist := {from: 0}
	var prev := {}
	var open: Array[Vector2i] = [from]
	while not open.is_empty():
		var best := 0
		for i in open.size():
			if dist[open[i]] < dist[open[best]]:
				best = i
		var cur: Vector2i = open[best]
		open.remove_at(best)
		for n in HexGrid.neighbors(cur):
			if not is_passable(n) or (known_only and not revealed.has(n)):
				continue
			var nd: int = dist[cur] + move_cost(n)
			if not dist.has(n) or nd < dist[n]:
				dist[n] = nd
				prev[n] = cur
				if not open.has(n):
					open.append(n)
	return {"dist": dist, "prev": prev}


func _terrain_for(v: float) -> String:
	if v < -0.42:
		return "grieta"
	if v < -0.18:
		return "hielo"
	if v < 0.2:
		return "llanura"
	if v < 0.4:
		return "roca"
	return "crater"


func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t


func _too_close(c: Vector2i) -> bool:
	for p in pois:
		if HexGrid.distance(c, p["cell"]) < 2:
			return true
	return false


func _try_generate(planet: Dictionary, events: Dictionary, s: int, flat := false) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	var noise := FastNoiseLite.new()
	noise.seed = s
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.22
	terrain.clear()
	pois.clear()
	revealed.clear()
	for y in ROWS:
		for x in COLS:
			terrain[Vector2i(x, y)] = "llanura" if flat else _terrain_for(noise.get_noise_2d(x, y))

	ship_cell = Vector2i(1, rng.randi_range(2, ROWS - 3))
	beacon_cell = Vector2i(COLS - 2, rng.randi_range(2, ROWS - 3))
	for anchor in [ship_cell, beacon_cell]:
		terrain[anchor] = "llanura"
		for n in HexGrid.neighbors(anchor):
			if terrain.has(n):
				terrain[n] = "llanura"

	var pool: Array = planet.get("event_pool", []).duplicate()
	_shuffle(pool, rng)
	var chosen: Array = pool.slice(0, mini(int(planet.get("poi_count", 6)), pool.size()))

	var cells: Array[Vector2i] = []
	for c in terrain:
		if is_passable(c) and HexGrid.distance(c, ship_cell) >= 3 and HexGrid.distance(c, beacon_cell) >= 2:
			cells.append(c)
	cells.sort()  # orden estable antes de barajar: el mapa depende solo de la semilla
	_shuffle(cells, rng)

	for event_id in chosen:
		var placed := false
		for c in cells:
			if _too_close(c):
				continue
			pois.append({
				"cell": c, "type": events[event_id]["type"], "event_id": event_id,
				"resolved": false, "objective": false,
			})
			placed = true
			break
		if not placed:
			return false

	var beacon_id: String = planet["beacon_event"]
	pois.append({
		"cell": beacon_cell, "type": events[beacon_id]["type"], "event_id": beacon_id,
		"resolved": false, "objective": true,
	})

	var dist := path_costs(ship_cell)
	for p in pois:
		if not dist.has(p["cell"]):
			return false
	return dist[beacon_cell] <= int(planet.get("max_beacon_cost", 22))


func snapshot() -> Dictionary:
	var out := {}
	for key in ["terrain", "revealed", "ship_cell", "beacon_cell", "pois"]:
		out[key] = get(key)
	return out.duplicate(true)


func restore(saved: Dictionary) -> void:
	for key in snapshot():
		if saved.has(key):
			set(key, saved[key])
