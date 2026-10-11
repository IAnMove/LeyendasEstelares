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


func start_run(avatar_dict: Dictionary, factions: Dictionary = {}, campaign_cfg: Dictionary = {}) -> void:
	avatar = avatar_dict
	crew = Content.avatars.duplicate(true)
	inventory = campaign_cfg.get("starting_items", {}).duplicate(true)
	relations = {}
	market_stock = {}
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


## Aplica efectos y devuelve líneas legibles (ya traducidas) de lo que cambió realmente.
func apply_effects(effects: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	_apply_stat(effects, "oxygen", "max_oxygen", lines)
	_apply_stat(effects, "morale", "max_morale", lines)
	_apply_stat(effects, "fuel", "max_fuel", lines)
	_apply_stat(effects, "scans", "max_scans", lines)
	if effects.has("data"):
		var before := data
		data = maxi(data + int(effects["data"]), 0)
		if data != before:
			lines.append(T.t("fx.data", {"delta": _signed(data - before)}))
	for faction in effects.get("rep", {}):
		var delta := int(effects["rep"][faction])
		rep[faction] = int(rep.get(faction, 0)) + delta
		lines.append(T.t("fx.rep", {"faction": T.t("faction." + faction), "delta": _signed(delta)}))
	for f in effects.get("set_flags", []):
		flags[f] = true
	for id in effects.get("items", {}):
		var item := Content.item_by_id(id)
		if item.is_empty():
			continue
		var before := item_count(id)
		inventory[id] = clampi(before + int(effects["items"][id]), 0, int(item["capacity"]))
		if item_count(id) != before:
			lines.append(T.t("fx.item", {"name": T.t("item.%s.name" % id), "delta": _signed(item_count(id) - before)}))
	changed.emit()
	return lines


func _apply_stat(effects: Dictionary, stat: String, max_stat: String, lines: Array[String]) -> void:
	if not effects.has(stat):
		return
	var before: int = get(stat)
	var after := clampi(before + int(effects[stat]), 0, int(get(max_stat)))
	set(stat, after)
	if after != before:
		lines.append(T.t("fx." + stat, {"delta": _signed(after - before)}))


func _signed(n: int) -> String:
	return ("+%d" % n) if n > 0 else ("−%d" % absi(n))
