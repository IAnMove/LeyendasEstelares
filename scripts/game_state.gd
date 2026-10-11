extends Node
## Estado de la expedición en curso. Persiste entre planetas (autoload "GameState").

signal changed

var avatar: Dictionary = {}
var oxygen := 0
var max_oxygen := 0
var morale := 0
var max_morale := 0
var data := 0
var fuel := 0
var max_fuel := 0
var scans := 0
var max_scans := 0
var rep := {}  # facción -> int
var flags := {}  # String -> true
var faction_ids: Array = []
var crew: Array = []
var inventory: Dictionary = {}
var relations: Dictionary = {}
var market_stock: Dictionary = {}
var on_surface := false
var story_turn := 0
var story_queue: Array = []
var story_seen: Dictionary = {}
var story_active: Dictionary = {}
var journal: Array = []


func start_run(avatar_dict: Dictionary, factions: Dictionary = {}, campaign_cfg: Dictionary = {}) -> void:
	avatar = avatar_dict
	crew = Content.avatars.duplicate(true)
	inventory = campaign_cfg.get("starting_items", {}).duplicate(true)
	relations = {}
	market_stock = {}
	story_turn = 0
	story_queue = []
	story_seen = {}
	story_active = {}
	journal = []
	on_surface = false
	max_oxygen = int(avatar.get("max_oxygen", 40))
	max_morale = int(avatar.get("max_morale", 10))
	for member in crew:
		max_morale = maxi(max_morale, int(member.get("max_morale", 10)))
	max_fuel = int(campaign_cfg.get("max_fuel", 10))
	max_scans = int(campaign_cfg.get("max_scans", 6))
	oxygen = max_oxygen
	morale = max_morale
	fuel = int(campaign_cfg.get("start_fuel", 8))
	scans = int(campaign_cfg.get("start_scans", 4))
	data = 0
	rep = {}
	flags = {}
	faction_ids = factions.keys()
	changed.emit()


## Reabastece oxígeno al descender; moral, datos, combustible y reputación se conservan.
func begin_planet() -> void:
	on_surface = true
	oxygen = max_oxygen
	changed.emit()


func has_trait(t: String) -> bool:
	return t in avatar.get("traits", [])


func has_crew_trait(t: String) -> bool:
	for member in crew:
		if t in member.get("traits", []):
			return true
	return false


func select_leader(id: String) -> bool:
	if on_surface:
		return false
	for member in crew:
		if member["id"] == id:
			avatar = member
			max_oxygen = int(member["max_oxygen"])
			oxygen = mini(oxygen, max_oxygen)
			changed.emit()
			return true
	return false


func item_count(id: String) -> int:
	return int(inventory.get(id, 0))


func item_bonus(stat: String) -> float:
	var bonus := 0.0
	for id in inventory:
		if item_count(id) > 0:
			bonus += float(Content.item_by_id(id).get("bonus", {}).get(stat, 0.0))
	return bonus


func item_use_reason(id: String) -> String:
	var item := Content.item_by_id(id)
	if item.is_empty() or item_count(id) <= 0:
		return "ui.cargo.empty"
	if item.get("kind", "") == "equipment":
		return "ui.cargo.passive"
	if item.get("context", "any") == "surface" and not on_surface:
		return "ui.cargo.surface_only"
	if item.get("context", "any") == "sector" and on_surface:
		return "ui.cargo.sector_only"
	for stat in item.get("effects", {}):
		if int(get(stat)) < int(get("max_" + stat)):
			return ""
	return "ui.cargo.full"


func use_item(id: String) -> Dictionary:
	var reason := item_use_reason(id)
	if reason != "":
		return {"ok": false, "reason": reason, "lines": []}
	inventory[id] = item_count(id) - 1
	var lines := apply_effects(Content.item_by_id(id)["effects"])
	return {"ok": true, "reason": "", "lines": lines}


func has_flag(f: String) -> bool:
	return flags.has(f)


## Tonos del pulso reunidos (abren las salidas de la baliza final).
func tones() -> int:
	var n := 0
	for tone in Content.TONES:
		if flags.has(tone):
			n += 1
	return n


## "Tono grave, tono agudo" o "—" si aún no hay ninguno.
func tone_names() -> String:
	var names: Array[String] = []
	for tone in Content.TONES:
		if flags.has(tone):
			names.append(T.t("flag." + tone))
	return ", ".join(names) if not names.is_empty() else "—"


## Oficial que se queda al mando de la Meridiana mientras el líder baja ("" si no hay otro).
func aboard() -> String:
	for member in crew:
		if member["id"] != avatar.get("id", ""):
			return member["id"]
	return ""


## Comentario del oficial a bordo (`voice.<oficial>.<key>`) como `T.later`, o {} si no hay nadie a bordo.
func voice(key: String) -> Dictionary:
	var officer := aboard()
	if officer == "":
		return {}
	return T.later("ui.voice", {"name": T.later("avatar.%s.name" % officer), "line": T.later("voice.%s.%s" % [officer, key])})


## Pistas del hilo de la campaña ya encontradas, en el orden de campaign.json.
func thread_clues() -> Array:
	var found := []
	for clue in Content.campaign.get("thread", {}).get("clues", []):
		if flags.has(clue):
			found.append(clue)
	return found


func spend_oxygen(n: int) -> void:
	oxygen = maxi(oxygen - n, 0)
	changed.emit()


func spend_fuel(n: int) -> void:
	fuel = maxi(fuel - n, 0)
	changed.emit()


func spend_scan() -> void:
	scans = maxi(scans - 1, 0)
	changed.emit()


## "oxygen", "morale" o "" si la expedición sigue viva (oxígeno solo cuenta en superficie).
func failure_reason() -> String:
	if oxygen <= 0:
		return "oxygen"
	if morale <= 0:
		return "morale"
	return ""


## Aplica efectos y devuelve líneas (`T.later`, se traducen al mostrarlas) de lo que cambió realmente.
func apply_effects(effects: Dictionary) -> Array:
	var lines: Array = []
	_apply_stat(effects, "oxygen", "max_oxygen", lines)
	_apply_stat(effects, "morale", "max_morale", lines)
	_apply_stat(effects, "fuel", "max_fuel", lines)
	_apply_stat(effects, "scans", "max_scans", lines)
	if effects.has("data"):
		var before := data
		data = maxi(data + int(effects["data"]), 0)
		if data != before:
			lines.append(T.later("fx.data", {"delta": _signed(data - before)}))
	for faction in effects.get("rep", {}):
		var delta := int(effects["rep"][faction])
		rep[faction] = int(rep.get(faction, 0)) + delta
		lines.append(T.later("fx.rep", {"faction": T.later("faction." + faction), "delta": _signed(delta)}))
	for f in effects.get("set_flags", []):
		var new_tone: bool = f in Content.TONES and not flags.has(f)
		flags[f] = true
		if new_tone:
			lines.append(T.later("fx.tone", {"name": T.later("flag." + f), "n": tones(), "total": Content.TONES.size()}))
	for id in effects.get("items", {}):
		var item := Content.item_by_id(id)
		if item.is_empty():
			continue
		var before := item_count(id)
		inventory[id] = clampi(before + int(effects["items"][id]), 0, int(item["capacity"]))
		if item_count(id) != before:
			lines.append(T.later("fx.item", {"name": T.later("item.%s.name" % id), "delta": _signed(item_count(id) - before)}))
	changed.emit()
	return lines


func _apply_stat(effects: Dictionary, stat: String, max_stat: String, lines: Array) -> void:
	if not effects.has(stat):
		return
	var before: int = get(stat)
	var after := clampi(before + int(effects[stat]), 0, int(get(max_stat)))
	set(stat, after)
	if after != before:
		lines.append(T.later("fx." + stat, {"delta": _signed(after - before)}))


func _signed(n: int) -> String:
	return ("+%d" % n) if n > 0 else ("−%d" % absi(n))


func snapshot() -> Dictionary:
	var out := {}
	for key in ["avatar", "oxygen", "max_oxygen", "morale", "max_morale", "data", "fuel", "max_fuel", "scans", "max_scans", "rep", "flags", "faction_ids", "crew", "inventory", "relations", "market_stock", "on_surface", "story_turn", "story_queue", "story_seen", "story_active", "journal"]:
		out[key] = get(key)
	return out.duplicate(true)


## Parte de un estado vacío: un guardado anterior a un campo nuevo no hereda valores de la partida previa.
func restore(saved: Dictionary) -> void:
	for key in snapshot():
		var value = get(key)
		set(key, saved[key] if saved.has(key) else _empty_like(value))


static func _empty_like(value):
	match typeof(value):
		TYPE_DICTIONARY: return {}
		TYPE_ARRAY: return []
		TYPE_BOOL: return false
		TYPE_INT: return 0
	return null


func queue_story(follow_up: Dictionary) -> void:
	var id: String = follow_up["event"]
	if story_seen.has(id):
		return
	story_seen[id] = true
	story_queue.append({"event": id, "due": story_turn + maxi(1, int(follow_up.get("delay", 1)))})
	changed.emit()


func next_story() -> Dictionary:
	if not story_active.is_empty():
		return story_active
	for i in story_queue.size():
		if story_queue[i]["due"] <= story_turn:
			story_active = story_queue[i]
			story_queue.remove_at(i)
			return story_active
	return {}


func complete_story() -> void:
	story_active = {}
	changed.emit()
