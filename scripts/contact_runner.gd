class_name ContactRunner
extends RefCounted
## Conversación de primer contacto: barras de confianza y tensión (0-10) según la postura elegida
## y los valores de la especie. Lógica pura, testable.

const MAX_METER := 10

var state
var species: Dictionary
var encounter: Dictionary
var trust := 0
var tension := 0
var index := 0  # intercambio actual
var broke := false  # tensión al máximo: la conversación se rompe
var _applied_outcome: Dictionary = {}
var history: Array = []


func _init(state_, species_: Dictionary, encounter_: Dictionary) -> void:
	state = state_
	species = species_
	encounter = encounter_
	trust = int(species["start"]["trust"])
	trust = mini(trust + int(state.item_bonus("trust")) + (1 if state.has_trait("diplomacia") else 0), MAX_METER)
	tension = int(species["start"]["tension"])


func finished() -> bool:
	return broke or index >= encounter["exchanges"].size()


func exchange() -> Dictionary:
	return encounter["exchanges"][index]


func option(i: int) -> Dictionary:
	return exchange()["options"][i]


func lock_reason(i: int, hint := "") -> String:
	if finished() or i < 0 or i >= exchange()["options"].size():
		return T.t("ui.contact.finished")
	var cost := -int(option(i).get("effects", {}).get("data", 0))
	if cost > state.data:
		return T.t("ui.contact.data_required", {"n": cost})
	return EventRunner.lock_reason(option(i), state, hint)


## Postura que la especie valora más (para la pista del analista / experiencia previa).
func best_stance() -> String:
	var best := ""
	var best_score := -999
	for s in Content.STANCES:
		var e: Dictionary = species["stance_effects"][s]
		var score: int = int(e["trust"]) - int(e["tension"])
		if score > best_score:
			best_score = score
			best = s
	return best


## Elige la opción: aplica postura + efectos propios y devuelve {lines, key} (key = clave del texto de respuesta).
func preview(i: int) -> Dictionary:
	var opt := option(i)
	var stance: String = opt["stance"]
	var base: Dictionary = species["stance_effects"][stance]
	var extra: Dictionary = opt.get("effects", {})
	var context: Dictionary = exchange().get("context_effects", {}).get(stance, {})
	var repeats := mini(history.count(stance), 2)
	var d_trust := int(base["trust"]) + int(extra.get("trust", 0)) + int(context.get("trust", 0)) - repeats
	var d_tension := int(base["tension"]) + int(extra.get("tension", 0)) + int(context.get("tension", 0)) + (1 if repeats > 0 else 0)
	if state.has_trait("diplomacia") and d_tension > 0:
		d_tension -= 1
	return {"trust": clampi(trust + d_trust, 0, MAX_METER) - trust,
		"tension": clampi(tension + d_tension, 0, MAX_METER) - tension,
		"cost": maxi(0, -int(extra.get("data", 0))), "repeats": repeats}


func choose(i: int) -> Dictionary:
	if lock_reason(i) != "":
		return {"ok": false, "lines": [], "key": ""}
	var opt := option(i)
	var extra: Dictionary = opt.get("effects", {})
	var forecast := preview(i)
	var d_trust: int = forecast["trust"]
	var d_tension: int = forecast["tension"]
	history.append(opt["stance"])
	var lines: Array = []
	var t0 := trust
	var n0 := tension
	trust = clampi(trust + d_trust, 0, MAX_METER)
	tension = clampi(tension + d_tension, 0, MAX_METER)
	if trust != t0:
		lines.append(T.later("fx.trust", {"delta": _signed(trust - t0)}))
	if tension != n0:
		lines.append(T.later("fx.tension", {"delta": _signed(tension - n0)}))
	var generic := {}
	for k in extra:
		if k != "trust" and k != "tension":
			generic[k] = extra[k]
	lines.append_array(state.apply_effects(generic))
	var key := "contact.%s.x%d.o%d.reply" % [encounter["id"], index, i]
	index += 1
	if tension >= MAX_METER:
		broke = true
	return {"ok": true, "lines": lines, "key": key}


## Desenlace según las barras: alliance, hostile, deal o wary.
func outcome() -> String:
	var o: Dictionary = encounter["outcomes"]
	if broke:
		return "hostile"
	for name in ["alliance", "hostile", "deal"]:
		var c: Dictionary = o[name]
		if trust >= int(c.get("min_trust", 0)) and tension >= int(c.get("min_tension", 0)) and tension <= int(c.get("max_tension", MAX_METER)):
			return name
	return "wary"


## Aplica los efectos del desenlace y devuelve {id, key, lines}.
func apply_outcome() -> Dictionary:
	if not _applied_outcome.is_empty():
		return _applied_outcome
	if not finished():
		return {}
	var id := outcome()
	state.relations[species["id"]] = id
	var lines: Array = state.apply_effects(encounter["outcomes"][id].get("effects", {}))
	if not state.has_flag("met_" + species["id"]):
		state.flags["met_" + species["id"]] = true
	_applied_outcome = {"id": id, "key": "contact.%s.out.%s" % [encounter["id"], id], "lines": lines}
	return _applied_outcome


func _signed(n: int) -> String:
	return ("+%d" % n) if n > 0 else ("−%d" % absi(n))


func snapshot() -> Dictionary:
	var out := {}
	for key in ["trust", "tension", "index", "broke", "_applied_outcome", "history"]:
		out[key] = get(key)
	return out.duplicate(true)


func restore(saved: Dictionary) -> void:
	for key in snapshot():
		if saved.has(key):
			set(key, saved[key])
