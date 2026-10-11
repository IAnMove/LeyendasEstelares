class_name ShipScreen
extends Control
## Gestión de la tripulación y bodega; también se abre en superficie para usar suministros.

signal closed
var _body: HBoxContainer
var _status: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(UITheme.background())
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 10)
	panel.size = Vector2(616, 340)
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := UITheme.label(T.t("ui.ship.title"), UITheme.ACCENT, 18)
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(title)
	var back := UITheme.button(T.t("ui.ship.back"))
	back.autowrap_mode = TextServer.AUTOWRAP_OFF
	back.pressed.connect(func(): closed.emit())
	head.add_child(back)
	col.add_child(UITheme.label(T.t("ui.ship.surface" if GameState.on_surface else "ui.ship.brief"), UITheme.DIM, 11))
	_status = UITheme.label("", UITheme.GOOD, 11)
	col.add_child(_status)
	_status.visible = false
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	col.add_child(scroll)
	_body = HBoxContainer.new()
	_body.size_flags_horizontal = SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 12)
	scroll.add_child(_body)
	_refresh()
	UITheme.isolate_focus(self)
	back.grab_focus()


func _refresh() -> void:
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var crew_col := VBoxContainer.new()
	crew_col.custom_minimum_size.x = 238
	crew_col.add_child(UITheme.caption(T.t("ui.ship.crew_heading")))
	_body.add_child(crew_col)
	for member in GameState.crew:
		var id: String = member["id"]
		var row := HBoxContainer.new()
		crew_col.add_child(row)
		row.add_child(UITheme.illustration(member["portrait"], Vector2(76, 82)))
		var info := VBoxContainer.new()
		info.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_child(info)
		info.add_child(UITheme.label(T.t("avatar.%s.name" % id), UITheme.TEXT, 12))
		info.add_child(UITheme.label(T.t("avatar.%s.perk" % id), UITheme.DIM, 10))
		var leader: bool = GameState.avatar["id"] == id
		var pick := UITheme.button(T.t("ui.ship.leader" if leader else "ui.ship.assign"))
		pick.disabled = leader or GameState.on_surface
		pick.pressed.connect(func():
			GameState.select_leader(id)
			_refresh())
		info.add_child(pick)
		crew_col.add_child(HSeparator.new())
	crew_col.add_child(UITheme.label(T.t("ui.ship.team_perks"), UITheme.ACCENT, 11))
	var cargo := VBoxContainer.new()
	cargo.custom_minimum_size.x = 324
	cargo.add_child(UITheme.caption(T.t("ui.ship.cargo_heading")))
	cargo.size_flags_horizontal = SIZE_EXPAND_FILL
	_body.add_child(cargo)
	for item in Content.items:
		var id: String = item["id"]
		var row := HBoxContainer.new()
		cargo.add_child(row)
		row.add_theme_constant_override("separation", 7)
		row.add_child(ItemIcon.new(id))
		var text := UITheme.label("%s ×%d" % [T.t("item.%s.name" % id), GameState.item_count(id)], UITheme.TEXT, 12)
		text.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_child(text)
		var use := UITheme.button(T.t("ui.cargo.equipped" if item["kind"] == "equipment" else "ui.cargo.use"))
		use.autowrap_mode = TextServer.AUTOWRAP_OFF
		use.disabled = GameState.item_use_reason(id) != ""
		use.tooltip_text = T.t(GameState.item_use_reason(id)) if use.disabled else ""
		use.pressed.connect(func():
			var result := GameState.use_item(id)
			_status.text = " · ".join(result["lines"])
			_status.visible = true
			Sound.play("supply")
			_refresh())
		row.add_child(use)
		cargo.add_child(UITheme.label(T.t("item.%s.desc" % id), UITheme.DIM, 10))
		cargo.add_child(HSeparator.new())
