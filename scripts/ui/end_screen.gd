class_name EndScreen
extends Control
## Cierre de la campaña. `ending`: victory | abort | fuel | oxygen | morale.

signal continue_pressed

var ending := "victory"
var jumps := 0


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

	var color := UITheme.GOOD if ending == "victory" else (UITheme.WARN if ending == "abort" else UITheme.BAD)
	v.add_child(UITheme.label(T.t("ending.%s.title" % ending), color, 18))
	v.add_child(UITheme.label(T.t("ending.%s.body" % ending), UITheme.TEXT, 12))
	for p in Content.planets:
		for flag in p.get("epilogues", []):
			if GameState.has_flag(flag):
				v.add_child(UITheme.label("· " + T.t("planet.%s.epilogue.%s" % [p["id"], flag]), UITheme.DIM, 11))
	if not GameState.journal.is_empty():
		v.add_child(UITheme.label(T.t("ui.story.journal"), UITheme.WARN, 14))
		for entry in GameState.journal:
			v.add_child(UITheme.label(T.ev(entry["event"], "c%d.%s" % [entry["choice"], entry["suffix"]]), UITheme.DIM, 11))
	if not GameState.story_queue.is_empty():
		v.add_child(UITheme.label(T.t("ui.story.pending_end", {"n": GameState.story_queue.size()}), UITheme.DIM, 11))
	v.add_child(HSeparator.new())
	v.add_child(UITheme.label(T.t("ending.stats", {"data": GameState.data, "jumps": jumps, "morale": GameState.morale, "max": GameState.max_morale}), UITheme.ACCENT, 12))
	for faction in GameState.rep:
		var n: int = GameState.rep[faction]
		v.add_child(UITheme.label(T.t("ending.rep", {"faction": T.t("faction." + faction), "value": ("+" if n > 0 else "") + str(n)}), UITheme.DIM, 11))
	var btn := UITheme.button(T.t("ui.back_title"))
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.pressed.connect(func(): continue_pressed.emit())
	outer.add_child(btn)
	btn.grab_focus()
