class_name EndScreen
extends Control
## Cierre de la campaña. `ending`: victory | abort | fuel | oxygen | morale.
## La victoria tiene variantes según lo que se hizo en la baliza final (ver victory_tier).

signal continue_pressed

## Bandera de la baliza -> variante de victoria; sin ninguna, el registro fue parcial.
const VICTORY_TIERS := {"baliza_respuesta": "answer", "baliza_dialogo": "dialogue", "baliza_mapa": "map", "baliza_apagada": "silence"}
const PARTIAL := "partial"

var ending := "victory"
var jumps := 0


static func victory_tier(state) -> String:
	for flag in VICTORY_TIERS:
		if state.has_flag(flag):
			return VICTORY_TIERS[flag]
	return PARTIAL


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(UITheme.background())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(540, 328)
	center.add_child(panel)
	var outer := VBoxContainer.new()
	panel.add_child(outer)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = 8
	outer.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	scroll.add_child(v)

	var key := ending
	var color := UITheme.WARN if ending == "abort" else UITheme.BAD
	if ending == "victory":
		key = "victory." + victory_tier(GameState)
		color = UITheme.WARN if victory_tier(GameState) == PARTIAL else UITheme.GOOD
	v.add_child(UITheme.label(T.t("ending.%s.title" % key), color, 18))
	v.add_child(UITheme.label(T.t("ending.%s.body" % key), UITheme.TEXT, 12))
	var closing := GameState.voice("end." + victory_tier(GameState)) if ending == "victory" else {}
	if not closing.is_empty():
		v.add_child(UITheme.label(T.show(closing), UITheme.ACCENT, 12))
	for p in Content.planets:
		for flag in p.get("epilogues", []):
			if GameState.has_flag(flag):
				v.add_child(UITheme.label("· " + T.t("planet.%s.epilogue.%s" % [p["id"], flag]), UITheme.DIM, 11))
	# Cómo acabó cada contacto (las facciones sin reputación propia solo se ven aquí).
	for sp in Content.campaign.get("species", []):
		if GameState.relations.has(sp):
			v.add_child(UITheme.label("· " + T.t("ending.contact.%s.%s" % [sp, GameState.relations[sp]]), UITheme.DIM, 11))
	_add_thread(v)
	if not GameState.journal.is_empty():
		v.add_child(UITheme.label(T.t("ui.story.journal"), UITheme.WARN, 14))
		for entry in GameState.journal:
			v.add_child(UITheme.label(T.ev(entry["event"], "c%d.%s" % [entry["choice"], entry["suffix"]]), UITheme.DIM, 11))
	if not GameState.story_queue.is_empty():
		v.add_child(UITheme.label(T.t("ui.story.pending_end", {"n": GameState.story_queue.size()}), UITheme.DIM, 11))
	v.add_child(HSeparator.new())
	v.add_child(UITheme.label(T.t("ending.stats", {"data": GameState.data, "jumps": jumps, "morale": GameState.morale, "max": GameState.max_morale}), UITheme.ACCENT, 12))
	v.add_child(UITheme.label(T.t("ui.tones.list", {"n": GameState.tones(), "total": Content.TONES.size(), "list": GameState.tone_names()}), UITheme.ACCENT, 11))
	for faction in GameState.rep:
		var n: int = GameState.rep[faction]
		v.add_child(UITheme.label(T.t("ending.rep", {"faction": T.t("faction." + faction), "value": ("+" if n > 0 else "") + str(n)}), UITheme.DIM, 11))
	var btn := UITheme.button(T.t("ui.back_title"))
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.pressed.connect(func(): continue_pressed.emit())
	outer.add_child(btn)
	btn.grab_focus()


## Hilo de la campaña: las pistas encontradas y, con suficientes, lo que pasó.
func _add_thread(v: VBoxContainer) -> void:
	var thread: Dictionary = Content.campaign.get("thread", {})
	var found := GameState.thread_clues()
	if found.is_empty():
		return
	var id: String = thread["id"]
	v.add_child(UITheme.label(T.t("ui.thread.progress", {"title": T.t("thread.%s.title" % id), "n": found.size(), "total": thread["clues"].size()}), UITheme.WARN, 14))
	for clue in found:
		v.add_child(UITheme.label("· " + T.t("thread.%s.%s" % [id, clue]), UITheme.DIM, 11))
	if found.size() >= int(thread["reveal"]):
		v.add_child(UITheme.label(T.t("thread.%s.reveal" % id), UITheme.TEXT, 12))
	else:
		v.add_child(UITheme.label(T.t("thread.%s.open" % id), UITheme.DIM, 11))
