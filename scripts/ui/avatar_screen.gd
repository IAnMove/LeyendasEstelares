class_name AvatarScreen
extends Control

signal avatar_chosen(avatar_id: String)
var _layout: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_build()


func _build() -> void:
	if _layout != null:
		remove_child(_layout)
		_layout.queue_free()
	_layout = Control.new()
	_layout.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_layout)
	_layout.add_child(UITheme.background())
	var head := UITheme.label(T.t("ui.choose_traveler"), UITheme.TEXT, 24)
	head.position = Vector2(20, 12)
	head.size.x = 350
	_layout.add_child(head)
	var styles := UITheme.portrait_selector(_build)
	styles.position = Vector2(418, 17)
	_layout.add_child(styles)
	var hint := UITheme.label(T.t("ui.crew.selection_hint"), UITheme.DIM, 11)
	hint.position = Vector2(20, 44)
	hint.size.x = 596
	_layout.add_child(hint)
	var row := HBoxContainer.new()
	row.position = Vector2(20, 70)
	row.size = Vector2(600, 272)
	row.add_theme_constant_override("separation", 12)
	_layout.add_child(row)
	for a in Content.avatars:
		row.add_child(_card(a))
	row.get_child(0).find_children("*", "Button", true, false)[0].grab_focus()


func _card(a: Dictionary) -> Control:
	var id: String = a["id"]
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(294, 272)
	var paper := UITheme.box(UITheme.PAPER, UITheme.INK, 10, 2)
	paper.shadow_color = Color(0, 0, 0, 0.4)
	paper.shadow_offset = Vector2(3, 4)
	paper.shadow_size = 1
	panel.add_theme_stylebox_override("panel", paper)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 7)
	panel.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	v.add_child(top)
	top.add_child(UITheme.illustration(a["portrait"], Vector2(130, 158)))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 6)
	top.add_child(info)
	info.add_child(UITheme.caption("MER / 01" if id == "vance" else "MER / 02", Color("516667")))
	info.add_child(UITheme.label(T.t("avatar.%s.name" % id), UITheme.INK, 20))
	info.add_child(UITheme.label(T.t("avatar.%s.role" % id), Color("28636c"), 11))
	var crew_morale := 0
	for member in Content.avatars:
		crew_morale = maxi(crew_morale, int(member["max_morale"]))
	info.add_child(UITheme.label(T.t("ui.avatar_stats", {"oxygen": int(a["max_oxygen"]), "morale": crew_morale}), UITheme.INK, 11))
	info.add_child(UITheme.label(T.t("avatar.%s.perk" % id), Color("28636c"), 11))
	var desc := UITheme.label(T.t("avatar.%s.desc" % id), Color("3f5355"), 11)
	desc.custom_minimum_size.y = 38
	desc.size_flags_vertical = SIZE_EXPAND_FILL
	v.add_child(desc)
	var pick := UITheme.button(T.t("ui.choose"))
	pick.alignment = HORIZONTAL_ALIGNMENT_CENTER
	pick.custom_minimum_size.y = 28
	pick.pressed.connect(func(): avatar_chosen.emit(id))
	v.add_child(pick)
	return panel
