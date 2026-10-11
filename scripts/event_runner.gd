class_name EventRunner
extends RefCounted
## Reglas de las decisiones de un evento. `state` es GameState (o algo con su misma interfaz).

const TAG_BONUS := 0.2


## "" si la opción se puede elegir; si no, `hint` (o "locked" si no se pasó texto).
static func lock_reason(choice: Dictionary, state, hint := "") -> String:
	var req: Dictionary = choice.get("requires", {})
	var locked := false
	if req.has("trait") and not state.has_trait(req["trait"]):
		locked = true
	if req.has("flag") and not state.has_flag(req["flag"]):
		locked = true
	if req.has("any_flag"):
		var ok := false
		for f in req["any_flag"]:
			ok = ok or state.has_flag(f)
		locked = locked or not ok
	if req.has("not_flag") and state.has_flag(req["not_flag"]):
		locked = true
	if req.has("min_data") and state.data < int(req["min_data"]):
		locked = true
	if not locked:
		return ""
	return hint if hint != "" else "locked"


static func success_chance(choice: Dictionary, state) -> float:
	if not choice.has("risk"):
		return 1.0
	var chance: float = choice["risk"]["chance"]
	if choice.has("tag") and state.has_trait(choice["tag"]):
		chance += TAG_BONUS
	chance += state.item_bonus("risk")
	return clampf(chance, 0.05, 0.95)


## Resuelve la opción `index` del evento: aplica efectos y devuelve {text, lines, success}.
static func resolve(event_id: String, index: int, choice: Dictionary, state, rng: RandomNumberGenerator) -> Dictionary:
	var branch: Dictionary
	var success := true
	var suffix := "res"
	if choice.has("risk"):
		success = rng.randf() < success_chance(choice, state)
		branch = choice["risk"]["success"] if success else choice["risk"]["fail"]
		suffix = "ok" if success else "fail"
	else:
		branch = choice["result"]
	var lines: Array[String] = state.apply_effects(branch.get("effects", {}))
	if success and choice.get("tag", "") == "ciencia" and state.has_trait("ciencia"):
		state.apply_effects({"data": 1})
		lines.append(T.t("ui.crew.discovery"))
	if branch.has("follow_up"):
		state.queue_story(branch["follow_up"])
		lines.append(T.t("ui.story.queued"))
	if branch.has("follow_up") or not state.story_active.is_empty():
		state.journal.append({"event": event_id, "choice": index, "suffix": suffix})
	return {"text": T.ev(event_id, "c%d.%s" % [index, suffix]), "lines": lines, "success": success}


static func preview(choice: Dictionary, state) -> String:
	var bonus := 1 if choice.get("tag", "") == "ciencia" and state.has_trait("ciencia") else 0
	if choice.has("risk"):
		return T.t("ui.choice.preview_risk", {
			"success": describe_branch(choice["risk"]["success"], state, bonus),
			"fail": describe_branch(choice["risk"]["fail"], state)})
	return describe_branch(choice["result"], state, bonus)


static func describe_branch(branch: Dictionary, state, science_bonus := 0) -> String:
	var effects: Dictionary = branch.get("effects", {}).duplicate(true)
	if science_bonus > 0:
		effects["data"] = int(effects.get("data", 0)) + science_bonus
	var parts: Array[String] = []
	for stat in ["oxygen", "morale", "data", "fuel", "scans"]:
		var delta := int(effects.get(stat, 0))
		if delta == 0:
			continue
		var current: int = state.get(stat)
		var limit: int = current + maxi(delta, 0) if stat == "data" else state.get("max_" + stat)
		delta = clampi(current + delta, 0, limit) - current
		if delta != 0:
			parts.append("%s %+d" % [T.t("ui.resource." + stat), delta])
	for faction in effects.get("rep", {}):
		parts.append("%s %+d" % [T.t("faction." + faction), effects["rep"][faction]])
	for id in effects.get("items", {}):
		var count: int = state.item_count(id)
		var delta := clampi(count + int(effects["items"][id]), 0, int(Content.item_by_id(id)["capacity"])) - count
		if delta != 0:
			parts.append("%s %+d" % [T.t("item.%s.name" % id), delta])
	for flag in effects.get("set_flags", []):
		if not state.has_flag(flag):
			parts.append(T.t("flag." + flag))
	if branch.has("follow_up") and not state.story_seen.has(branch["follow_up"]["event"]):
		parts.append(T.t("ui.story.later"))
	return " · ".join(parts) if not parts.is_empty() else T.t("ui.choice.no_change")
