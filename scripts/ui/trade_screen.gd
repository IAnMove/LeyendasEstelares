class_name TradeScreen
extends Control

signal closed
var species_id := "hallen"
var market: TradeRunner
var _list: VBoxContainer
var _balance: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	market = TradeRunner.new(GameState, species_id)
	add_child(UITheme.background())
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 12)
	panel.size = Vector2(608, 336)
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	head.add_child(UITheme.illustration(Content.species_by_id(species_id)["portrait"], Vector2(46, 46)))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(info)
	info.add_child(UITheme.label(T.t("ui.trade.title", {"species": T.t("species.%s.name" % species_id)}), UITheme.ACCENT, 16))
	_balance = UITheme.label("", UITheme.WARN, 12)
	info.add_child(_balance)
	var back := UITheme.button(T.t("ui.trade.back"))
	back.autowrap_mode = TextServer.AUTOWRAP_OFF
	back.pressed.connect(func(): closed.emit())
	head.add_child(back)
	col.add_child(UITheme.label(T.t("ui.trade.hint"), UITheme.DIM, 11))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(_list)
	_refresh()
	UITheme.isolate_focus(self)
	back.grab_focus()


func _refresh() -> void:
	_balance.text = T.t("ui.trade.balance", {"n": GameState.data})
	if GameState.relations.get(species_id, "") == "alliance":
		_balance.text += " · " + T.t("ui.trade.discount")
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	if not market.is_open():
		_list.add_child(UITheme.label(T.t("ui.trade.closed"), UITheme.BAD))
		return
	for id in market.offers():
		var row := HBoxContainer.new()
		_list.add_child(row)
		row.add_theme_constant_override("separation", 8)
		row.add_child(ItemIcon.new(id))
		var info := VBoxContainer.new()
		info.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_child(info)
		info.add_child(UITheme.label(T.t("item.%s.name" % id), UITheme.TEXT, 13))
		info.add_child(UITheme.label(T.t("ui.trade.stock", {"stock": market.stock(id), "owned": GameState.item_count(id)}), UITheme.DIM, 10))
		for selling in [false, true]:
			var b := UITheme.button(T.t("ui.trade.sell" if selling else "ui.trade.buy", {"n": market.price(id, selling)}))
			b.custom_minimum_size.x = 104
			b.add_theme_font_size_override("font_size", 10)
			b.alignment = HORIZONTAL_ALIGNMENT_CENTER
			if not selling:
				UITheme.primary(b)
			b.disabled = market.reason(id, selling) != ""
			b.tooltip_text = T.t(market.reason(id, selling)) if b.disabled else ""
			b.pressed.connect(func():
				if market.transact(id, selling):
					Sound.play("trade")
				_refresh())
			row.add_child(b)
		_list.add_child(UITheme.label(T.t("item.%s.desc" % id), UITheme.DIM, 11))
		_list.add_child(HSeparator.new())
