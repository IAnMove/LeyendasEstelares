extends Node
## Carga los datos del juego (res://data/*.json) y los valida (autoload "Content").
## Los JSON solo contienen mecánica; todo el texto sale de las traducciones por clave convencional
## (ver text_keys()).

const VALID_EFFECTS := ["oxygen", "morale", "data", "fuel", "scans", "rep", "set_flags", "items"]
const VALID_CONTACT_EFFECTS := ["trust", "tension", "oxygen", "morale", "data", "fuel", "scans", "rep", "set_flags", "items"]
const VALID_REQUIRES := ["trait", "flag", "any_flag", "not_flag", "min_data", "min_tones"]
const VALID_TYPES := ["signal", "ruins", "wreck", "life", "beacon", "anomaly"]
const VALID_BIOMES := ["frost", "dust", "verdant"]
const STANCES := ["open", "careful", "firm", "deceive"]
const OUTCOMES := ["alliance", "deal", "hostile", "wary"]
## Los tres tonos del pulso: relés planetarios, especies con acuerdo y la propia señal.
const TONES := ["tono_grave", "tono_medio", "tono_agudo"]

var avatars: Array = []
var planets: Array = []
var events := {}  # id -> evento
var factions := {}
var species: Array = []
var encounters: Array = []
var campaign := {}
var items: Array = []
var markets: Dictionary = {}


func _init() -> void:
	avatars = _read("res://data/avatars.json")
	planets = _read("res://data/planets.json")
	factions = _read("res://data/factions.json")
	species = _read("res://data/species.json")
	encounters = _read("res://data/encounters.json")
	campaign = _read("res://data/campaign.json")
	items = _read("res://data/items.json")
	markets = _read("res://data/markets.json")
	for e in _read("res://data/events.json"):
		events[e["id"]] = e


func item_by_id(id: String) -> Dictionary:
	for item in items:
		if item["id"] == id:
			return item
	return {}


func avatar_by_id(id: String) -> Dictionary:
	for a in avatars:
		if a["id"] == id:
			return a
	return {}


func planet_by_id(id: String) -> Dictionary:
	for p in planets:
		if p["id"] == id:
			return p
	return {}


func species_by_id(id: String) -> Dictionary:
	for s in species:
		if s["id"] == id:
			return s
	return {}


func encounter_for(species_id: String) -> Dictionary:
	for e in encounters:
		if e["species"] == species_id:
			return e
	return {}


## ¿Alguna rama del evento aporta esta clave de efecto en positivo? (p. ej. "fuel" para el escáner)
func event_gives(event_id: String, key: String) -> bool:
	for c in events[event_id].get("choices", []):
		var branches: Array = []
		if c.has("risk"):
			branches = [c["risk"]["success"], c["risk"]["fail"]]
		elif c.has("result"):
			branches = [c["result"]]
		for b in branches:
			if int(b.get("effects", {}).get(key, 0)) > 0:
				return true
	return false


func _read(path: String) -> Variant:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed == null:
		push_error("JSON inválido o ausente: %s" % path)
	return parsed


func _branches(c: Dictionary) -> Array:
	if c.has("risk"):
		return [["ok", c["risk"].get("success", {})], ["fail", c["risk"].get("fail", {})]]
	return [["res", c.get("result", {})]]


## Todas las claves de traducción que exigen los datos (por convención de nombres).
func text_keys() -> Array[String]:
	var keys: Array[String] = []
	for item in items:
		keys.append("item.%s.name" % item["id"])
		keys.append("item.%s.desc" % item["id"])
	for id in factions:
		keys.append("faction." + id)
	for a in avatars:
		for s in ["name", "role", "desc", "perk"]:
			keys.append("avatar.%s.%s" % [a["id"], s])
	for p in planets:
		for s in ["name", "intro", "outro_success", "outro_abort"]:
			keys.append("planet.%s.%s" % [p["id"], s])
		for f in p.get("epilogues", []):
			keys.append("planet.%s.epilogue.%s" % [p["id"], f])
	for sp in species:
		for s in ["name", "desc"]:
			keys.append("species.%s.%s" % [sp["id"], s])
	for id in events:
		var e: Dictionary = events[id]
		keys.append("event.%s.title" % id)
		keys.append("event.%s.text" % id)
		for i in e["choices"].size():
			var c: Dictionary = e["choices"][i]
			keys.append("event.%s.c%d.text" % [id, i])
			if c.has("requires"):
				keys.append("event.%s.c%d.hint" % [id, i])
			for b in _branches(c):
				keys.append("event.%s.c%d.%s" % [id, i, b[0]])
	for enc in encounters:
		var id: String = enc["id"]
		keys.append("contact.%s.intro" % id)
		for o in OUTCOMES:
			keys.append("contact.%s.out.%s" % [id, o])
		for x in enc["exchanges"].size():
			keys.append("contact.%s.x%d.prompt" % [id, x])
			keys.append("contact.%s.x%d.context" % [id, x])
			for i in enc["exchanges"][x]["options"].size():
				var opt: Dictionary = enc["exchanges"][x]["options"][i]
				keys.append("contact.%s.x%d.o%d" % [id, x, i])
				keys.append("contact.%s.x%d.o%d.reply" % [id, x, i])
				if opt.has("requires"):
					keys.append("contact.%s.x%d.o%d.hint" % [id, x, i])
	for flag in _known_flags():
		keys.append("flag." + flag)
	return keys


func _known_flags() -> Array:
	var flags := {}
	for event in events.values():
		for choice in event["choices"]:
			for branch in _branches(choice):
				for flag in branch[1].get("effects", {}).get("set_flags", []):
					flags[flag] = true
	for encounter in encounters:
		for outcome in encounter["outcomes"].values():
			for flag in outcome.get("effects", {}).get("set_flags", []):
				flags[flag] = true
	return flags.keys()


## Lista de problemas de coherencia en los datos (vacía si todo está bien).
func validate() -> Array[String]:
	var errors: Array[String] = []
	var item_ids := {}
	for item in items:
		var id: String = item.get("id", "")
		if id == "" or item_ids.has(id):
			errors.append("objeto: id vacío o duplicado")
		item_ids[id] = true
		if int(item.get("price", 0)) < 2 or int(item.get("capacity", 0)) < 1:
			errors.append("objeto %s: precio o capacidad inválidos" % id)
		if item.get("kind", "") not in ["consumable", "equipment"] or item.get("context", "") not in ["any", "surface", "sector"]:
			errors.append("objeto %s: tipo o contexto inválidos" % id)
		for stat in item.get("effects", {}):
			if stat not in ["oxygen", "morale", "fuel", "scans"] or int(item["effects"][stat]) <= 0:
				errors.append("objeto %s: efecto inválido" % id)
	for species_id in markets:
		if species_by_id(species_id).is_empty():
			errors.append("mercado: especie inexistente %s" % species_id)
		for id in markets[species_id]:
			if not item_ids.has(id) or int(markets[species_id][id]) < 1:
				errors.append("mercado %s: objeto o existencias inválidos %s" % [species_id, id])
	for id in campaign.get("starting_items", {}):
		if not item_ids.has(id) or int(campaign["starting_items"][id]) < 0 or int(campaign["starting_items"][id]) > int(item_by_id(id).get("capacity", 0)):
			errors.append("inventario inicial inválido: %s" % id)
	var set_flags := {}
	for id in events:
		var e: Dictionary = events[id]
		if not (e.get("type", "") in VALID_TYPES):
			errors.append("%s: tipo inválido" % id)
		if e.get("choices", []).size() < 2:
			errors.append("%s: necesita al menos 2 opciones" % id)
		for i in e.get("choices", []).size():
			_validate_choice(e["choices"][i], "%s[%d]" % [id, i], VALID_EFFECTS, errors, set_flags, true)
	for enc in encounters:
		if species_by_id(enc.get("species", "")).is_empty():
			errors.append("encuentro %s: especie inexistente" % enc.get("id", "?"))
		for o in OUTCOMES:
			if not enc.get("outcomes", {}).has(o):
				errors.append("encuentro %s: falta el desenlace %s" % [enc.get("id", "?"), o])
		for o in enc.get("outcomes", {}):
			for k in enc["outcomes"][o].get("effects", {}):
				if not (k in VALID_EFFECTS):
					errors.append("encuentro %s/%s: efecto desconocido '%s'" % [enc["id"], o, k])
			for f in enc["outcomes"][o].get("effects", {}).get("set_flags", []):
				set_flags[f] = true
		for x in enc.get("exchanges", []).size():
			for stance in enc["exchanges"][x].get("context_effects", {}):
				if not stance in STANCES:
					errors.append("contexto diplomático: postura desconocida")
				for stat in enc["exchanges"][x]["context_effects"][stance]:
					if not stat in ["trust", "tension"]:
						errors.append("contexto diplomático: efecto desconocido")
			for i in enc["exchanges"][x]["options"].size():
				var opt: Dictionary = enc["exchanges"][x]["options"][i]
				var where := "%s.x%d.o%d" % [enc["id"], x, i]
				if not (opt.get("stance", "") in STANCES):
					errors.append("%s: postura inválida" % where)
				for k in opt.get("effects", {}):
					if not (k in VALID_CONTACT_EFFECTS):
						errors.append("%s: efecto desconocido '%s'" % [where, k])
				for k in opt.get("requires", {}):
					if not (k in VALID_REQUIRES):
						errors.append("%s: requisito desconocido '%s'" % [where, k])
	for sp in species:
		for s in STANCES:
			if not sp.get("stance_effects", {}).has(s):
				errors.append("especie %s: falta postura %s" % [sp["id"], s])
		if encounter_for(sp["id"]).is_empty():
			errors.append("especie %s: sin encuentro" % sp["id"])
	# Los flags exigidos deben poder activarse en algún sitio.
	var required: Array = []
	for id in events:
		for c in events[id].get("choices", []):
			required.append(c.get("requires", {}))
	for enc in encounters:
		for ex in enc.get("exchanges", []):
			for opt in ex["options"]:
				required.append(opt.get("requires", {}))
	for tone in TONES:
		if not set_flags.has(tone):
			errors.append("el tono '%s' nunca se consigue" % tone)
	for req in required:
		if int(req.get("min_tones", 0)) > TONES.size():
			errors.append("min_tones mayor que el número de tonos")
		var needed: Array = req.get("any_flag", []).duplicate()
		if req.has("flag"):
			needed.append(req["flag"])
		for f in needed:
			if not set_flags.has(f):
				errors.append("el flag '%s' nunca se activa" % f)
	for p in planets:
		var pid: String = p.get("id", "?")
		if not (p.get("biome", "") in VALID_BIOMES):
			errors.append("planeta %s: bioma inválido" % pid)
		for id in p.get("event_pool", []) + [p.get("beacon_event", "")]:
			if not events.has(id):
				errors.append("planeta %s: evento inexistente '%s'" % [pid, id])
		if p.get("event_pool", []).size() < int(p.get("poi_count", 6)):
			errors.append("planeta %s: el pool tiene menos eventos que poi_count" % pid)
	# Campaña
	var mid := 0
	var cols: Array = campaign.get("columns", [])
	for c in range(1, cols.size() - 1):
		mid += int(cols[c])
	var n_planets: int = campaign.get("intermediate_planets", []).size()
	if mid != n_planets + campaign.get("species", []).size() + int(campaign.get("anomalies", 0)):
		errors.append("campaña: los nodos intermedios no cuadran con planetas + contactos + anomalías")
	if campaign.get("anomaly_pool", []).size() < int(campaign.get("anomalies", 0)):
		errors.append("campaña: pocas anomalías en el pool")
	for id in campaign.get("anomaly_pool", []):
		if not events.has(id) or events[id]["type"] != "anomaly":
			errors.append("campaña: '%s' no es una anomalía" % id)
	if planet_by_id(campaign.get("final_planet", "")).is_empty():
		errors.append("campaña: planeta final inexistente")
	for id in campaign.get("intermediate_planets", []):
		if planet_by_id(id).is_empty():
			errors.append("campaña: planeta intermedio inexistente '%s'" % id)
	return errors


func _validate_choice(c: Dictionary, where: String, valid_effects: Array, errors: Array[String], set_flags: Dictionary, _is_event: bool) -> void:
	if c.has("risk") == c.has("result"):
		errors.append("%s: debe tener exactamente uno de risk/result" % where)
	if c.has("risk"):
		var chance: float = c["risk"].get("chance", -1.0)
		if chance < 0.0 or chance > 1.0:
			errors.append("%s: chance fuera de rango" % where)
	for b in _branches(c):
		if b[1].has("follow_up"):
			var follow: Dictionary = b[1]["follow_up"]
			if not events.has(follow.get("event", "")) or int(follow.get("delay", 0)) < 1:
				errors.append("%s: continuación inexistente o sin demora" % where)
		for id in b[1].get("effects", {}).get("items", {}):
			if item_by_id(id).is_empty():
				errors.append("%s: objeto desconocido '%s'" % [where, id])
		for k in b[1].get("effects", {}):
			if not (k in valid_effects):
				errors.append("%s: efecto desconocido '%s'" % [where, k])
		for f in b[1].get("effects", {}).get("set_flags", []):
			set_flags[f] = true
		for fac in b[1].get("effects", {}).get("rep", {}):
			if not factions.has(fac):
				errors.append("%s: facción desconocida '%s'" % [where, fac])
	for k in c.get("requires", {}):
		if not (k in VALID_REQUIRES):
			errors.append("%s: requisito desconocido '%s'" % [where, k])
	if c.has("tag") and not _any_avatar_has_trait(c["tag"]):
		errors.append("%s: ningún avatar tiene el rasgo '%s'" % [where, c["tag"]])


func _any_avatar_has_trait(t: String) -> bool:
	for a in avatars:
		if t in a.get("traits", []):
			return true
	return false
