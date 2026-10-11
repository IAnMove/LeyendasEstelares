class_name SectorData
extends RefCounted
## Mapa estelar tipo FTL: columnas de nodos conectadas de izquierda a derecha.
## Lógica pura (sin nodos de escena) para poder probarla y simularla en headless.

var nodes := {}  # id -> Dictionary {id, col, y, type, ref, edges, scanned, done, final, planet}
var columns: Array = []  # columns[c] = Array de ids ordenados de arriba abajo
var start_id := ""
var final_id := ""


func generate(cfg: Dictionary, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	nodes.clear()
	columns.clear()
	var col_sizes: Array = cfg["columns"]
	for c in col_sizes.size():
		var ids: Array[String] = []
		var n: int = col_sizes[c]
		for i in n:
			var id := "n%d_%d" % [c, i]
			var y := 0.5 if n == 1 else clampf((i + 0.5) / n + rng.randf_range(-0.07, 0.07), 0.08, 0.92)
			nodes[id] = {
				"id": id, "col": c, "y": y, "type": "anomaly", "ref": "", "edges": [], "costs": {},
				"scanned": false, "done": false, "final": false, "planet": {},
			}
			ids.append(id)
		columns.append(ids)
	start_id = columns[0][0]
	final_id = columns[columns.size() - 1][0]
	nodes[start_id].merge({"type": "start", "scanned": true, "done": true}, true)

	_connect(rng)
	_assign_types(cfg, rng)
	_make_planet(nodes[final_id], cfg["final_planet"], rng)
	nodes[final_id]["final"] = true
	nodes[final_id]["planet"]["final"] = true
	nodes[final_id]["scanned"] = true


func _connect(rng: RandomNumberGenerator) -> void:
	for c in range(columns.size() - 1):
		var cur: Array = columns[c]
		var nxt: Array = columns[c + 1]
		var n := cur.size()
		var m := nxt.size()
		var incoming := {}
		for i in n:
			var j := mini(int(floor(float(i) * m / n)), m - 1)
			_link(cur[i], nxt[j], 1)
			incoming[j] = true
			# Rutas secundarias: más largas (cuestan 2 de combustible).
			if j + 1 < m and rng.randf() < 0.5:
				_link(cur[i], nxt[j + 1], 2)
				incoming[j + 1] = true
		for j in m:
			if not incoming.has(j):
				_link(cur[mini(int(round(float(j) * n / m)), n - 1)], nxt[j], 1)


func _link(a: String, b: String, cost: int) -> void:
	if not nodes[a]["edges"].has(b):
		nodes[a]["edges"].append(b)
		nodes[a]["costs"][b] = cost


func _assign_types(cfg: Dictionary, rng: RandomNumberGenerator) -> void:
	var mid: Array[String] = []
	for c in range(1, columns.size() - 1):
		mid.append_array(columns[c])
	_shuffle(mid, rng)
	var used_cols := {}
	# Planetas intermedios en columnas distintas mientras sea posible.
	for planet_id in cfg["intermediate_planets"]:
		var pick := -1
		for i in mid.size():
			if not used_cols.has(nodes[mid[i]]["col"]):
				pick = i
				break
		if pick < 0:
			pick = 0
		var node: Dictionary = nodes[mid[pick]]
		used_cols[node["col"]] = true
		mid.remove_at(pick)
		_make_planet(node, planet_id, rng)
	for sp in cfg["species"]:
		var node: Dictionary = nodes[mid.pop_front()]
		node["type"] = "contact"
		node["ref"] = sp
	var pool: Array = cfg["anomaly_pool"].duplicate()
	_shuffle(pool, rng)
	for id in mid:
		nodes[id]["type"] = "anomaly"
		nodes[id]["ref"] = pool.pop_front()


func _make_planet(node: Dictionary, planet_id: String, rng: RandomNumberGenerator) -> void:
	var planet: Dictionary = Content.planet_by_id(planet_id).duplicate(true)
	var pool: Array = planet["event_pool"].duplicate()
	_shuffle(pool, rng)
	planet["event_pool"] = pool.slice(0, mini(int(planet.get("poi_count", 6)), pool.size()))
	planet["seed"] = rng.randi()
	node["type"] = "planet"
	node["ref"] = planet_id
	node["planet"] = planet


func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t


## Etiquetas que revela un escaneo: tipos de puntos de interés presentes y si hay combustible.
func scan_tags(id: String) -> Array[String]:
	var tags: Array[String] = []
	var node: Dictionary = nodes[id]
	if node["type"] != "planet":
		return tags
	var fuel := false
	for event_id in node["planet"]["event_pool"]:
		var t: String = Content.events[event_id]["type"]
		if not tags.has(t):
			tags.append(t)
		fuel = fuel or Content.event_gives(event_id, "fuel")
	var beacon_id: String = node["planet"]["beacon_event"]
	fuel = fuel or Content.event_gives(beacon_id, "fuel")
	tags.sort()
	if fuel:
		tags.append("fuel")
	return tags


func snapshot() -> Dictionary:
	var out := {}
	for key in ["nodes", "columns", "start_id", "final_id"]:
		out[key] = get(key)
	return out.duplicate(true)


func restore(saved: Dictionary) -> void:
	for key in snapshot():
		if saved.has(key):
			set(key, saved[key])
