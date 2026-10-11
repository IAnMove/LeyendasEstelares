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
	return {"text": T.ev(event_id, "c%d.%s" % [index, suffix]), "lines": lines, "success": success}
