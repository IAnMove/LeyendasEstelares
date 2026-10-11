extends Node
## Pruebas headless: godot --headless --path . res://tests/run_tests.tscn
## Sale con código 0 si todo pasa. Incluye simulaciones de campañas completas con un bot.

var _failures := 0


func _ready() -> void:
	T.set_language("en", false)
	_test_safe_layout()
	_test_hex()
	_test_content()
	_test_translations()
	_test_generation()
	_test_event_rules()
	_test_sector()
	_test_contacts()
	_test_contact_context()
	_test_stories()
	_test_return_guidance()
	_test_campaign_rules()
	_test_crew_and_items()
	_test_leader_specialties()
	_test_pulse_tones()
	_test_trade()
	for avatar in ["vance", "okafor"]:
		_test_bot_campaigns(avatar)
	print("\n%s (%d fallos)" % ["TODO OK" if _failures == 0 else "FALLOS", _failures])
	Sound.set_muted(true, false)
	await get_tree().process_frame
	get_tree().quit(0 if _failures == 0 else 1)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		print("  FALLO: ", msg)


func _new_state(avatar_id: String):
	var gs = load("res://scripts/game_state.gd").new()
	gs.start_run(Content.avatar_by_id(avatar_id), Content.factions, Content.campaign)
	return gs


# ------------------------------------------------------------------- básicos
func _test_hex() -> void:
	print("hex")
	for y in 6:
		for x in 6:
			var c := Vector2i(x, y)
			for n in HexGrid.neighbors(c):
				_check(HexGrid.distance(c, n) == 1, "vecino a distancia 1 %s→%s" % [c, n])
				_check(HexGrid.neighbors(n).has(c), "vecindad simétrica %s↔%s" % [c, n])
	_check(HexGrid.distance(Vector2i(0, 0), Vector2i(3, 0)) == 3, "distancia en línea")


func _test_content() -> void:
	print("contenido")
	for e in Content.validate():
		_check(false, e)
	_check(Content.avatars.size() >= 2, "al menos 2 avatares")
	_check(Content.species.size() == 3, "3 especies")
	_check(Content.encounters.size() == 3, "3 encuentros")


# --------------------------------------------------------------- traducciones
func _code_keys() -> Array[String]:
	var keys: Array[String] = []
	var re := RegEx.new()
	re.compile("\"((?:ui|ending|fx|trait)\\.[a-z0-9_.]*[a-z0-9_])\"")
	var dirs := ["res://scripts", "res://scripts/ui"]
	for d in dirs:
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".gd") and f != "t.gd":
				var src := FileAccess.get_file_as_string("%s/%s" % [d, f])
				for m in re.search_all(src):
					keys.append(m.get_string(1))
	return keys


func _dynamic_keys() -> Array[String]:
	# Familias de claves que el código compone en tiempo de ejecución.
	var keys: Array[String] = []
	for id in Content.factions:
		keys.append("faction." + id)
	for s in Content.STANCES:
		keys.append("ui.stance." + s)
		keys.append("ui.value." + s)
	for o in Content.OUTCOMES:
		keys.append("ui.contact.result." + o)
	for stat in ["oxygen", "morale", "data", "fuel", "scans"]:
		keys.append("ui.resource." + stat)
	for fx in ["oxygen", "morale", "fuel", "scans", "data", "rep", "trust", "tension"]:
		keys.append("fx." + fx)
	for e in ["abort", "fuel", "oxygen", "morale"]:
		keys.append("ending.%s.title" % e)
		keys.append("ending.%s.body" % e)
	for tier in EndScreen.VICTORY_TIERS.values() + [EndScreen.PARTIAL]:
		keys.append("ending.victory.%s.title" % tier)
		keys.append("ending.victory.%s.body" % tier)
	for t in ["signal", "ruins", "wreck", "life", "fuel"]:
		keys.append("ui.scan.tag." + t)
	for t in ["planet", "contact", "anomaly", "start", "final"]:
		keys.append("ui.sector.type." + t)
	for tr_ in ["ciencia", "diplomacia"]:
		keys.append("trait." + tr_)
	return keys


func _placeholders(s: String) -> Array:
	var re := RegEx.new()
	re.compile("\\{([a-z_]+)\\}")
	var out: Array = []
	for m in re.search_all(s):
		if not out.has(m.get_string(1)):
			out.append(m.get_string(1))
	out.sort()
	return out


func _test_translations() -> void:
	print("traducciones")
	var used := {}
	for k in Content.text_keys():
		used[k] = true
	for k in _code_keys():
		used[k] = true
	for k in _dynamic_keys():
		used[k] = true
	for lang in T.LANGUAGES:
		TranslationServer.set_locale(lang)
		for k in used:
			var s := T.t(k)
			_check(s != k and s != "", "[%s] falta la traducción de '%s'" % [lang, k])
	# Mismos parámetros {x} en todos los idiomas.
	for k in used:
		TranslationServer.set_locale("en")
		var en := _placeholders(T.t(k))
		TranslationServer.set_locale("es")
		var es := _placeholders(T.t(k))
		_check(en == es, "parámetros distintos entre idiomas en '%s': %s vs %s" % [k, en, es])
	# Claves del CSV que nadie usa (código muerto de traducciones).
	var f := FileAccess.open(T.CSV_PATH, FileAccess.READ)
	f.get_csv_line()
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() >= 3 and row[0] != "":
			_check(used.has(row[0]), "clave sin uso en el CSV: '%s'" % row[0])
	T.set_language("en", false)


# ------------------------------------------------------- mapas de superficie
func _test_generation() -> void:
	print("generación de mapas de planeta")
	for planet in Content.planets:
		var counts := {}
		for s in 200:
			var m := PlanetData.new()
			m.generate(planet, Content.events, s)
			var costs := m.path_costs(m.ship_cell)
			_check(m.pois.size() == int(planet["poi_count"]) + 1, "%s: nº de POIs semilla %d" % [planet["id"], s])
			for p in m.pois:
				_check(costs.has(p["cell"]), "%s: POI alcanzable semilla %d" % [planet["id"], s])
			_check(costs[m.beacon_cell] >= 8, "%s: objetivo no demasiado cerca semilla %d" % [planet["id"], s])
			for t in m.terrain.values():
				counts[t] = int(counts.get(t, 0)) + 1
			var again := PlanetData.new()
			again.generate(planet, Content.events, s)
			_check(again.terrain == m.terrain and again.ship_cell == m.ship_cell, "%s: determinista semilla %d" % [planet["id"], s])
		print("  %s: %s" % [planet["id"], counts])
		var fallback := PlanetData.new()
		_check(fallback._try_generate(planet, Content.events, 0, true), "%s: el mapa de reserva siempre es válido" % planet["id"])
		_check(fallback.pois.filter(func(p): return p["objective"]).size() == 1, "%s: el mapa de reserva conserva el objetivo" % planet["id"])


func _test_event_rules() -> void:
	print("reglas de eventos")
	var gs = _new_state("vance")
	var sci := {"tag": "ciencia", "risk": {"chance": 0.5, "success": {"effects": {"data": 2}}, "fail": {"effects": {"oxygen": -3}}}}
	_check(is_equal_approx(EventRunner.success_chance(sci, gs), 0.7), "bonus de rasgo +20%")
	gs.start_run(Content.avatar_by_id("okafor"), Content.factions, Content.campaign)
	_check(is_equal_approx(EventRunner.success_chance(sci, gs), 0.5), "sin rasgo, sin bonus")
	var locked := {"requires": {"flag": "x"}, "result": {"effects": {}}}
	_check(EventRunner.lock_reason(locked, gs, "falta x") == "falta x", "opción bloqueada por flag")
	gs.apply_effects({"set_flags": ["x"]})
	_check(EventRunner.lock_reason(locked, gs, "falta x") == "", "opción desbloqueada tras flag")
	var data_gate := {"requires": {"min_data": 2}, "result": {"effects": {}}}
	_check(EventRunner.lock_reason(data_gate, gs) != "", "bloqueada por datos insuficientes")
	gs.apply_effects({"data": 3})
	_check(EventRunner.lock_reason(data_gate, gs) == "", "desbloqueada con datos")
	var before: int = gs.oxygen
	gs.apply_effects({"oxygen": -5, "morale": -1, "rep": {"vael": 2}, "fuel": -2, "scans": -1})
	_check(gs.oxygen == before - 5 and gs.rep["vael"] == 2, "efectos aplicados")
	_check(gs.fuel == int(Content.campaign["start_fuel"]) - 2 and gs.scans == int(Content.campaign["start_scans"]) - 1, "combustible y escaneos")
	gs.apply_effects({"oxygen": 999, "fuel": 999})
	_check(gs.oxygen == gs.max_oxygen and gs.fuel == gs.max_fuel, "recursos acotados al máximo")
	gs.apply_effects({"oxygen": -999})
	_check(gs.failure_reason() == "oxygen", "fallo por oxígeno")
	# Las líneas guardan clave y parámetros: se traducen al mostrarlas, no al resolverse.
	var lines: Array = gs.apply_effects({"oxygen": 5, "rep": {"vael": 1}})
	var english := T.join(lines)
	T.set_language("es", false)
	_check(T.join(lines) != english and not "{" in T.join(lines), "las líneas se traducen en el idioma activo")
	T.set_language("en", false)
	_check(T.show("texto de un guardado antiguo") == "texto de un guardado antiguo", "los textos ya traducidos se muestran tal cual")
	# Restaurar parte de un estado vacío: un guardado sin un campo no hereda el de la partida anterior.
	var saved: Dictionary = gs.snapshot()
	saved.erase("journal")
	saved.erase("story_queue")
	gs.journal.append({"event": "anterior", "choice": 0, "suffix": "res"})
	gs.story_queue.append({"event": "anterior", "due": 1})
	gs.restore(saved)
	_check(gs.journal.is_empty() and gs.story_queue.is_empty(), "restaurar no hereda la bitácora de otra partida")
	_check(gs.flags.has("x") and gs.rep["vael"] == 3, "restaurar conserva los campos guardados")
	gs.free()


# ------------------------------------------------------------------ campaña
func _test_sector() -> void:
	print("mapa estelar")
	for s in 300:
		var sec := SectorData.new()
		sec.generate(Content.campaign, s)
		var counts := {"planet": 0, "contact": 0, "anomaly": 0}
		var species_seen := {}
		var anomalies := {}
		var planet_cols := {}
		for id in sec.nodes:
			var n: Dictionary = sec.nodes[id]
			if n["type"] in counts:
				counts[n["type"]] += 1
			if n["type"] == "contact":
				species_seen[n["ref"]] = true
			if n["type"] == "anomaly":
				anomalies[n["ref"]] = true
			if n["type"] == "planet" and not n["final"]:
				planet_cols[n["col"]] = true
		_check(counts["planet"] == 3 and counts["contact"] == 3 and counts["anomaly"] == 5, "composición del sector semilla %d: %s" % [s, counts])
		_check(species_seen.size() == 3, "las 3 especies aparecen (semilla %d)" % s)
		_check(anomalies.size() == 5, "anomalías sin repetir (semilla %d)" % s)
		# alcanzabilidad y longitud mínima del camino
		var dist := {sec.start_id: 0}
		var queue: Array[String] = [sec.start_id]
		while not queue.is_empty():
			var cur: String = queue.pop_front()
			for to in sec.nodes[cur]["edges"]:
				if not dist.has(to):
					dist[to] = dist[cur] + 1
					queue.append(to)
		_check(dist.size() == sec.nodes.size(), "todos los nodos alcanzables (semilla %d)" % s)
		_check(dist[sec.final_id] == Content.campaign["columns"].size() - 1, "camino mínimo = columnas-1 (semilla %d)" % s)
		var cost := {sec.start_id: 0}
		for c in sec.columns.size():
			for id in sec.columns[c]:
				if cost.has(id):
					for to in sec.nodes[id]["edges"]:
						var nc: int = cost[id] + int(sec.nodes[id]["costs"][to])
						if not cost.has(to) or nc < cost[to]:
							cost[to] = nc
		_check(cost[sec.final_id] == Content.campaign["columns"].size() - 1, "existe una ruta de coste mínimo 5 (semilla %d)" % s)
		for id in sec.nodes:
			if sec.nodes[id]["type"] == "planet":
				_check(not sec.scan_tags(id).is_empty(), "un planeta escaneado revela etiquetas (semilla %d)" % s)
			_check(id == sec.final_id or not sec.nodes[id]["edges"].is_empty(), "sin callejones sin salida (semilla %d)" % s)


func _test_contacts() -> void:
	print("contactos")
	for sp in Content.species:
		var enc := Content.encounter_for(sp["id"])
		for label in ["best", "worst"]:
			var gs = _new_state("okafor")
			gs.apply_effects({"data": 5, "set_flags": ["vael_contacto"]})
			var r := ContactRunner.new(gs, sp, enc)
			while not r.finished():
				var pick := 0
				var best_score := -999 if label == "best" else 999
				for i in r.exchange()["options"].size():
					if r.lock_reason(i) != "":
						continue
					var forecast := r.preview(i)
					var score: int = forecast["trust"] - forecast["tension"]
					if (label == "best" and score > best_score) or (label == "worst" and score < best_score):
						best_score = score
						pick = i
				r.choose(pick)
			var out := r.outcome()
			print("  %s %s → %s (trust %d, tension %d)" % [sp["id"], label, out, r.trust, r.tension])
			_check(r.trust >= 0 and r.trust <= 10 and r.tension >= 0 and r.tension <= 10, "barras acotadas")
			if label == "best":
				_check(out == "alliance" or out == "deal", "%s: la mejor estrategia da alianza o acuerdo" % sp["id"])
			else:
				_check(out == "hostile" or out == "wary", "%s: la peor estrategia no da alianza" % sp["id"])
			gs.free()
	# La postura preferida coincide con lo que dicen los datos.
	var tmp = _new_state("vance")
	for pair in [["vael", "open"], ["hallen", "careful"], ["draeth", "firm"]]:
		var got := ContactRunner.new(tmp, Content.species_by_id(pair[0]), Content.encounter_for(pair[0])).best_stance()
		_check(got == pair[1], "%s valora la postura %s (datos: %s)" % [pair[0], pair[1], got])
	tmp.free()
	# El rasgo diplomático templa la tensión.
	var dip = _new_state("okafor")
	var sci = _new_state("vance")
	var dr := ContactRunner.new(dip, Content.species_by_id("draeth"), Content.encounter_for("draeth"))
	var sr := ContactRunner.new(sci, Content.species_by_id("draeth"), Content.encounter_for("draeth"))
	dr.choose(0)  # open: tensión +1 base
	sr.choose(0)
	_check(dr.tension == sr.tension - 1, "la diplomacia reduce la tensión ganada")
	dip.free()
	sci.free()


func _test_campaign_rules() -> void:
	print("reglas de campaña")
	var gs = _new_state("vance")
	var c := Campaign.new(gs, Content.campaign, 5)
	var first: String = c.sector.nodes[c.current]["edges"][0]
	_check(c.can_jump(first), "se puede saltar a un nodo conectado")
	var far: String = c.sector.columns[3][0]
	_check(not c.can_jump(far), "no se salta a un nodo no conectado")
	_check(c.can_scan(first), "se puede escanear el siguiente nodo")
	var scans: int = gs.scans
	c.scan(first)
	_check(gs.scans == scans - 1 and c.node(first)["scanned"], "el escaneo gasta una carga y revela")
	_check(not c.can_scan(first), "no se escanea dos veces")
	var fuel: int = gs.fuel
	var cost := c.edge_cost(c.current, first)
	c.jump(first)
	_check(gs.fuel == fuel - cost and c.current == first, "el salto gasta el combustible de la ruta")
	gs.fuel = 0
	c.finish_node(first)
	_check(c.end_reason() == "fuel", "sin combustible lejos del destino se pierde")
	gs.fuel = 1
	var cheap := ""
	var pricey := ""
	for to in c.sector.nodes[c.current]["edges"]:
		if c.edge_cost(c.current, to) == 1 and cheap == "":
			cheap = to
		if c.edge_cost(c.current, to) == 2 and pricey == "":
			pricey = to
	_check(cheap == "" or c.can_jump(cheap), "con 1 de combustible se puede una ruta corta")
	_check(pricey == "" or not c.can_jump(pricey), "con 1 de combustible no se puede una ruta larga")
	gs.morale = 0
	_check(c.end_reason() == "morale", "sin moral la tripulación se niega")
	gs.free()


func _test_crew_and_items() -> void:
	print("tripulación e inventario")
	var gs = _new_state("vance")
	_check(gs.crew.size() == 2 and gs.has_crew_trait("diplomacia"), "ambos oficiales viajan en equipo")
	_check(gs.select_leader("okafor") and gs.has_trait("diplomacia"), "se puede cambiar de líder a bordo")
	_check(not gs.select_leader("unknown"), "no se asigna un tripulante inexistente")
	_check(not gs.use_item("oxygen_cell")["ok"], "el oxígeno solo se usa en superficie")
	gs.begin_planet()
	_check(not gs.select_leader("vance"), "el líder no cambia durante el descenso")
	_check(not gs.use_item("oxygen_cell")["ok"] and gs.item_count("oxygen_cell") == 1, "un recurso lleno no consume objetos")
	gs.spend_oxygen(8)
	_check(gs.use_item("oxygen_cell")["ok"] and gs.oxygen == gs.max_oxygen, "el cartucho repone sin superar el máximo")
	_check(gs.item_count("oxygen_cell") == 0 and not gs.use_item("oxygen_cell")["ok"], "el objeto se consume una sola vez")
	gs.apply_effects({"items": {"survey_kit": 8, "fuel_cell": 1}})
	_check(gs.item_count("survey_kit") == 1, "equipo único, sin acumulación")
	var choice := {"risk": {"chance": 0.5}}
	_check(is_equal_approx(EventRunner.success_chance(choice, gs), 0.6), "el equipo mejora las acciones arriesgadas")
	_check(not gs.use_item("survey_kit")["ok"], "el equipo pasivo no se consume")
	_check(not gs.use_item("fuel_cell")["ok"], "no se reposta en superficie")
	gs.on_surface = false
	var camp := Campaign.new(gs, Content.campaign, 5)
	gs.fuel = 0
	_check(camp.end_reason() == "", "la reserva permite rescatar la nave sin combustible")
	_check(gs.use_item("fuel_cell")["ok"] and gs.fuel == 2, "se puede repostar la reserva")
	gs.fuel = 0
	_check(camp.end_reason() == "fuel", "sin reserva se pierde por combustible")
	gs.start_run(Content.avatar_by_id("vance"), Content.factions, Content.campaign)
	_check(gs.item_count("survey_kit") == 0 and gs.item_count("oxygen_cell") == 1 and not gs.on_surface, "una nueva campaña reinicia la bodega y el contexto")
	gs.free()


func _test_trade() -> void:
	print("comercio y relaciones")
	var gs = _new_state("vance")
	var market := TradeRunner.new(gs, "hallen")
	gs.data = 30
	_check(not market.transact("fuel_cell"), "sin acuerdo no hay comercio")
	gs.relations["hallen"] = "hostile"
	_check(not market.transact("fuel_cell"), "la hostilidad cierra el comercio")
	gs.relations["hallen"] = "deal"
	var initial_stock := market.stock("fuel_cell")
	var initial_data: int = gs.data
	_check(market.transact("fuel_cell"), "compra permitida con acuerdo")
	_check(gs.data == initial_data - 4 and gs.item_count("fuel_cell") == 1 and market.stock("fuel_cell") == initial_stock - 1, "compra atómica: datos, objeto y existencias")
	var reopened := TradeRunner.new(gs, "hallen")
	_check(reopened.stock("fuel_cell") == initial_stock - 1, "reabrir no regenera existencias")
	_check(market.transact("fuel_cell", true) and gs.item_count("fuel_cell") == 0, "vender devuelve datos y retira el objeto")
	_check(gs.data < initial_data and not market.transact("fuel_cell", true), "no se duplican datos ni se venden objetos ausentes")
	gs.relations["hallen"] = "alliance"
	_check(market.price("fuel_cell") == 3, "la alianza descuenta un dato")
	for id in market.offers():
		_check(market.price(id, true) <= market.price(id), "no existe arbitraje entre compra y venta")
	gs.data = 0
	var before := market.stock("fuel_cell")
	_check(not market.transact("fuel_cell") and market.stock("fuel_cell") == before, "compra fallida no altera existencias")
	gs.data = 100
	_check(not market.transact("unknown"), "rechaza objetos desconocidos")
	for i in initial_stock:
		market.transact("fuel_cell")
	_check(not market.transact("fuel_cell") and market.stock("fuel_cell") == 0, "las existencias son finitas")
	_check(market.transact("translator") and not market.transact("translator"), "equipo único")
	var runner := ContactRunner.new(gs, Content.species_by_id("vael"), Content.encounter_for("vael"))
	_check(runner.trust == 4, "el traductor mejora la confianza inicial")
	_check(runner.apply_outcome().is_empty(), "no se cobran recompensas antes de terminar el contacto")
	while not runner.finished():
		runner.choose(0)
	runner.apply_outcome()
	var data_after: int = gs.data
	var fuel_after: int = gs.fuel
	runner.apply_outcome()
	_check(gs.data == data_after and gs.fuel == fuel_after, "reabrir el resultado no duplica recompensas")
	_check(gs.relations.has("vael"), "el contacto persiste su relación comercial")
	gs.start_run(Content.avatar_by_id("vance"), Content.factions, Content.campaign)
	_check(gs.market_stock.is_empty() and gs.relations.is_empty(), "la siguiente campaña reinicia mercados y relaciones")
	gs.free()


# ---------------------------------------------------------------- simulación
func _test_bot_campaigns(avatar_id: String) -> void:
	print("bot de campaña (%s)" % avatar_id)
	var results := {"victory": 0, "fuel": 0, "oxygen": 0, "morale": 0, "abort": 0}
	var runs := 300
	var gs = _new_state(avatar_id)
	for s in runs:
		var rng := RandomNumberGenerator.new()
		rng.seed = s * 131 + 17
		gs.start_run(Content.avatar_by_id(avatar_id), Content.factions, Content.campaign)
		var camp := Campaign.new(gs, Content.campaign, s)
		results[_bot_campaign(camp, gs, rng)] += 1
	print("  ", results)
	var win_rate := float(results["victory"]) / runs
	_check(win_rate > 0.05 and win_rate < 0.95, "tasa de victoria razonable (%.2f)" % win_rate)
	gs.free()


func _bot_campaign(camp: Campaign, gs, rng: RandomNumberGenerator) -> String:
	for _step in 20:
		gs.on_surface = false
		if gs.fuel <= 3:
			gs.use_item("fuel_cell")
		if gs.scans == 0:
			gs.use_item("scan_probe")
		if gs.morale <= gs.max_morale - 3:
			gs.use_item("rations")
		var here: Dictionary = camp.node(camp.current)
		# Escanea al azar mientras queden cargas.
		for id in camp.sector.nodes:
			if camp.can_scan(id) and rng.randf() < 0.5:
				camp.scan(id)
		var options: Array[String] = []
		for to in here["edges"]:
			if camp.can_jump(to):
				options.append(to)
		if options.is_empty():
			return "fuel"
		var best := options[0]
		var best_score := -1.0
		for to in options:
			var n: Dictionary = camp.node(to)
			var score := rng.randf()
			if n["scanned"] and n["type"] == "planet":
				score += 0.6 if camp.sector.scan_tags(to).has("fuel") and gs.fuel <= 4 else 0.2
			if n["scanned"] and n["type"] == "contact":
				score += 0.3
			if score > best_score:
				best_score = score
				best = to
		camp.jump(best)
		var node: Dictionary = camp.node(best)
		var outcome := _bot_node(camp, gs, rng, node)
		gs.on_surface = false
		if outcome != "":
			return outcome
		camp.finish_node(best)
		var reason := camp.end_reason()
		if reason != "":
			return reason
	return "fuel"


## Devuelve "" si el nodo se resolvió sin acabar la partida; si no, el desenlace.
func _bot_node(camp: Campaign, gs, rng: RandomNumberGenerator, node: Dictionary) -> String:
	while not gs.next_story().is_empty():
		var event_id: String = gs.story_active["event"]
		var legal: Array[int] = []
		var event: Dictionary = Content.events[event_id]
		for i in event["choices"].size():
			if EventRunner.lock_reason(event["choices"][i], gs) == "":
				legal.append(i)
		var pick := legal[rng.randi() % legal.size()]
		EventRunner.resolve(event_id, pick, event["choices"][pick], gs, rng)
		gs.complete_story()
		if gs.morale <= 0:
			return "morale"
	match node["type"]:
		"planet":
			gs.begin_planet()
			var ex := Expedition.new(gs, node["planet"], Content.events, int(node["planet"]["seed"]))
			var res := _bot_planet(ex, gs, rng)
			if res == "fail":
				return gs.failure_reason() if gs.failure_reason() != "" else "oxygen"
			if node["final"]:
				return "victory" if res == "success" else "abort"
			return ""
		"contact":
			var r := ContactRunner.new(gs, Content.species_by_id(node["ref"]), Content.encounter_for(node["ref"]))
			while not r.finished():
				var opts: Array = []
				for i in r.exchange()["options"].size():
					if r.lock_reason(i) == "":
						opts.append(i)
				r.choose(opts[rng.randi() % opts.size()])
			r.apply_outcome()
			var market := TradeRunner.new(gs, node["ref"])
			for item in ["fuel_cell", "oxygen_cell", "rations", "survey_kit"]:
				if gs.item_count(item) == 0:
					market.transact(item)
		_:
			var ev: Dictionary = Content.events[node["ref"]]
			var opts: Array = []
			for i in ev["choices"].size():
				if EventRunner.lock_reason(ev["choices"][i], gs) == "":
					opts.append(i)
			var i: int = opts[rng.randi() % opts.size()]
			EventRunner.resolve(node["ref"], i, ev["choices"][i], gs, rng)
	return ""


func _bot_planet(ex: Expedition, gs, rng: RandomNumberGenerator) -> String:
	var visits := rng.randi_range(1, 4)
	var targets: Array[Dictionary] = []
	for p in ex.map.pois:
		if not p["objective"]:
			targets.append(p)
	targets.sort_custom(func(a, b): return HexGrid.distance(a["cell"], ex.map.ship_cell) < HexGrid.distance(b["cell"], ex.map.ship_cell))
	var beacon: Dictionary = ex.map.poi_at(ex.map.beacon_cell)
	var plan: Array[Dictionary] = targets.slice(0, visits)
	plan.append(beacon)
	for target in plan:
		var costs := ex.map.path_costs(ex.player)
		var home_costs := ex.map.path_costs(ex.map.ship_cell)
		var need: int = costs[target["cell"]] + home_costs[target["cell"]] + 2
		if not target["objective"] and need > gs.oxygen:
			continue
		if _bot_walk(ex, gs, rng, ex.map.find_path(ex.player, target["cell"])) != "":
			return "fail"
	if not ex.objective_done:
		return "abort"
	var last := _bot_walk(ex, gs, rng, ex.map.find_path(ex.player, ex.map.ship_cell))
	return "success" if last == "home" else "fail"


func _bot_walk(ex: Expedition, gs, rng: RandomNumberGenerator, path: Array[Vector2i]) -> String:
	for c in path:
		if gs.oxygen <= 12:
			gs.use_item("oxygen_cell")
		if gs.morale <= gs.max_morale - 3:
			gs.use_item("rations")
		var res := ex.move(c)
		if res["home"]:
			return "home"
		if res["failure"] != "":
			return "fail"
		if not res["poi"].is_empty():
			var ev := ex.event_of(res["poi"])
			var opts: Array = []
			for i in ev["choices"].size():
				if EventRunner.lock_reason(ev["choices"][i], gs) == "":
					opts.append(i)
			ex.resolve_choice(res["poi"], opts[rng.randi() % opts.size()], rng)
			if gs.failure_reason() != "":
				return "fail"
	return ""


func _test_safe_layout() -> void:
	print("área segura: teléfono, muesca y tableta")
	var viewport := Rect2(0, 0, 640, 360)
	for physical in [Vector2(1920, 1080), Vector2(2400, 1080), Vector2(2560, 1600)]:
		var scale_factor := minf(physical.x / 640, physical.y / 360)
		var transform := Transform2D(Vector2(scale_factor, 0), Vector2(0, scale_factor), (physical - Vector2(640, 360) * scale_factor) / 2)
		var safe := Rect2(Vector2(88, 0), physical - Vector2(88, 32))
		var fitted := SafeLayout.fit(viewport, safe, transform)
		_check(viewport.encloses(fitted), "área lógica contenida")
		_check(safe.grow(0.01).encloses(transform * fitted), "respeta muesca y barra: %s" % physical)
		_check(is_equal_approx(fitted.size.x / fitted.size.y, 640.0 / 360), "sin distorsión")


func _test_contact_context() -> void:
	print("contexto, repetición y costes diplomáticos")
	var gs = _new_state("vance")
	gs.data = 5
	var r := ContactRunner.new(gs, Content.species_by_id("vael"), Content.encounter_for("vael"))
	_check(r.preview(0)["trust"] > r.preview(1)["trust"], "franqueza al presentarse")
	r.choose(0)
	_check(r.preview(1)["trust"] > r.preview(0)["trust"], "prudencia ante recuerdos privados")
	var forecast := r.preview(0)
	_check(forecast["repeats"] == 1, "se recuerda la postura anterior")
	var trust_before := r.trust
	r.choose(0)
	_check(r.trust - trust_before == forecast["trust"], "pronóstico coincide con resultado")
	var restored := ContactRunner.new(gs, r.species, r.encounter)
	restored.restore(r.snapshot())
	_check(restored.preview(0) == r.preview(0), "historial persiste al reanudar")
	gs.data = 0
	var before := r.snapshot()
	_check(not r.choose(0)["ok"] and r.snapshot() == before, "no se puede pagar con datos inexistentes")
	r.choose(1)
	before = r.snapshot()
	_check(not r.choose(1)["ok"] and r.snapshot() == before, "contacto terminado no acepta más decisiones")
	gs.free()


func _test_stories() -> void:
	print("cadenas narrativas y promesas")
	var gs = _new_state("vance")
	gs.queue_story({"event": "convoy_rescatado", "delay": 2})
	gs.queue_story({"event": "convoy_rescatado", "delay": 2})
	_check(gs.story_queue.size() == 1, "misma cadena no se programa dos veces")
	_check(gs.next_story().is_empty(), "no llega en el mismo salto")
	gs.story_turn = 1
	_check(gs.next_story().is_empty(), "respeta la demora")
	gs.story_turn = 2
	_check(gs.next_story()["event"] == "convoy_rescatado", "llega en el salto previsto")
	var rng := RandomNumberGenerator.new()
	gs.data = 2
	EventRunner.resolve("convoy_rescatado", 0, Content.events["convoy_rescatado"]["choices"][0], gs, rng)
	_check(gs.data == 0 and gs.has_flag("convoy_guiado"), "compartir cartas tiene coste y deja una promesa")
	gs.complete_story()
	_check(gs.next_story().is_empty(), "el segundo episodio tampoco llega inmediatamente")
	gs.story_turn += 1
	_check(gs.next_story()["event"] == "destino_del_convoy", "cadena continúa tras otro salto")
	var promise: Dictionary = Content.events["destino_del_convoy"]["choices"][0]
	_check(EventRunner.lock_reason(promise, gs) == "", "decisión anterior abre la ruta prometida")
	gs.flags.erase("convoy_guiado")
	_check(EventRunner.lock_reason(promise, gs) != "", "sin aquella decisión no se abre la ruta")
	_check(gs.journal.size() == 1, "consecuencia registrada en bitácora")
	gs.free()


func _test_leader_specialties() -> void:
	print("capacidades activas del líder")
	var science = _new_state("vance")
	var diplomacy = _new_state("okafor")
	_check(science.max_oxygen == diplomacy.max_oxygen, "misma autonomía de exploración")
	var sp := Content.species_by_id("draeth")
	var a := ContactRunner.new(science, sp, Content.encounter_for("draeth"))
	var b := ContactRunner.new(diplomacy, sp, Content.encounter_for("draeth"))
	_check(b.trust == a.trust + 1, "Okafor aporta confianza inicial")
	_check(b.preview(0)["tension"] == a.preview(0)["tension"] - 1, "solo el líder diplomático amortigua tensión")
	var rng := RandomNumberGenerator.new()
	var choice := {"tag": "ciencia", "result": {"effects": {"data": 2}}}
	EventRunner.resolve("senal_periodica", 2, choice, science, rng)
	EventRunner.resolve("senal_periodica", 2, choice, diplomacy, rng)
	_check(science.data == 3 and diplomacy.data == 2, "solo Vance aporta el dato adicional")
	var failure := {"tag": "ciencia", "risk": {"chance": -1, "success": {"effects": {}}, "fail": {"effects": {}}}}
	# Fixture sin azar: 95% mínimo de fallo, busca una tirada fallida y verifica su recompensa.
	var before: int = science.data
	for seed_value in 20:
		rng.seed = seed_value
		if rng.randf() >= EventRunner.success_chance(failure, science):
			rng.seed = seed_value
			var result := EventRunner.resolve("senal_periodica", 0, failure, science, rng)
			_check(not result["success"] and science.data == before, "un fallo científico no concede datos")
			break
	science.free()
	diplomacy.free()


func _test_pulse_tones() -> void:
	print("tonos del pulso y finales de la baliza")
	var gs = _new_state("vance")
	var beacon: Array = Content.events["baliza_central"]["choices"]
	var answer: Dictionary = beacon.filter(func(c): return c.get("requires", {}).get("min_tones", 0) == Content.TONES.size())[0]
	gs.apply_effects({"set_flags": ["vael_contacto", "mapa_vael"]})
	_check(EventRunner.lock_reason(beacon[0], gs) != "" and EventRunner.lock_reason(beacon[1], gs) != "", "sin tonos, la baliza no abre diálogo ni mapa")
	_check(EventRunner.lock_reason(beacon[2], gs) == "" and EventRunner.lock_reason(beacon[3], gs) == "", "registro parcial y silencio siempre disponibles")
	var lines: Array = gs.apply_effects({"set_flags": ["tono_grave"]})
	_check(gs.tones() == 1 and T.join(lines).contains("1/3"), "un tono nuevo se anuncia con el recuento")
	_check(gs.apply_effects({"set_flags": ["tono_grave"]}).is_empty(), "repetir un tono no lo cuenta dos veces")
	gs.apply_effects({"set_flags": ["tono_medio"]})
	_check(EventRunner.lock_reason(beacon[0], gs) == "" and EventRunner.lock_reason(answer, gs) != "", "dos tonos abren el diálogo, no la respuesta")
	gs.apply_effects({"set_flags": ["tono_agudo"]})
	_check(EventRunner.lock_reason(answer, gs) == "" and gs.tone_names().count(",") == 2, "los tres tonos permiten responder al pulso")
	# Fuentes: cada acuerdo o alianza da el tono medio; los relés de Kaelora y Nerea, el grave, pase lo que pase.
	for enc in Content.encounters:
		for o in ["deal", "alliance"]:
			_check("tono_medio" in enc["outcomes"][o]["effects"].get("set_flags", []), "%s/%s concede el tono medio" % [enc["id"], o])
	for id in Content.campaign["intermediate_planets"]:
		var relay: Dictionary = Content.events[Content.planet_by_id(id)["beacon_event"]]
		for c in relay["choices"]:
			for b in Content._branches(c):
				_check("tono_grave" in b[1].get("effects", {}).get("set_flags", []), "%s concede el tono grave" % id)
	# El final depende de la salida de la baliza.
	var tiers := {}
	for flag in EndScreen.VICTORY_TIERS:
		var probe = _new_state("vance")
		probe.apply_effects({"set_flags": [flag]})
		tiers[EndScreen.victory_tier(probe)] = true
		probe.free()
	_check(tiers.size() == EndScreen.VICTORY_TIERS.size() and EndScreen.victory_tier(gs) == EndScreen.PARTIAL, "cada salida de la baliza tiene su final; sin ella, registro parcial")
	gs.free()


func _test_return_guidance() -> void:
	print("ruta de vuelta sin revelar niebla y vista previa sin efectos")
	var gs = _new_state("vance")
	var ex := Expedition.new(gs, Content.planets[0], Content.events, 32)
	ex.map.terrain = {Vector2i(0, 0): "llanura", Vector2i(1, 0): "roca", Vector2i(2, 0): "hielo"}
	ex.map.ship_cell = Vector2i.ZERO
	ex.player = Vector2i(2, 0)
	ex.map.revealed = {Vector2i(0, 0): true, Vector2i(2, 0): true}
	_check(ex.return_cost() == -1, "no inventa una ruta a través de terreno oculto")
	ex.map.revealed[Vector2i(1, 0)] = true
	_check(ex.return_cost() == 3, "vuelta paga destino, no casilla de salida")
	_check(ex.map.path_costs(Vector2i.ZERO)[Vector2i(2, 0)] == 4, "ida y vuelta pueden costar distinto")
	ex.player = Vector2i.ZERO
	_check(ex.return_cost() == 0 and ex.return_path().is_empty(), "en la nave la vuelta cuesta cero")
	var before: Dictionary = gs.snapshot()
	var preview := EventRunner.preview(Content.events["senal_periodica"]["choices"][0], gs)
	_check(preview.contains("Data +3") and gs.snapshot() == before, "anticipa el bonus científico sin mutar el estado")
	gs.free()
