class_name Overlay
extends Control
## Panel modal reutilizable (briefings, eventos, resultados). Contiene la lógica de presentar un evento.

signal opened
signal closed

var _dim: ColorRect
var _panel: PanelContainer
var _box: VBoxContainer
var _scroll: ScrollContainer


func _init() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.55)
	_dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)
	_panel = PanelContainer.new()
	_panel.position = Vector2(64, 28)
	_panel.size = Vector2(512, 304)
	add_child(_panel)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_panel.add_child(_scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 8)
	_scroll.add_child(_box)


func is_open() -> bool:
	return visible


func open() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	_panel.size = Vector2(512, 304)
	_scroll.scroll_vertical = 0
	visible = true
	opened.emit()


func close() -> void:
	visible = false
	closed.emit()


func title(text: String, color := UITheme.ACCENT) -> void:
	_box.add_child(UITheme.label(text, color, 16))


func body(text: String) -> void:
	var l := UITheme.label(text, UITheme.TEXT, 12)
	l.custom_minimum_size = Vector2(478, 0)
	_box.add_child(l)


func art(tex_name: String) -> void:
	_box.add_child(UITheme.illustration(tex_name, Vector2(478, 82)))


func note(text: String, color := UITheme.WARN) -> void:
	_box.add_child(UITheme.label(text, color, 12))


func separator() -> void:
	_box.add_child(HSeparator.new())


func button(text: String, cb: Callable, disabled := false) -> Button:
	var b := UITheme.button(text)
	b.custom_minimum_size = Vector2(478, 0)
	b.disabled = disabled
	b.pressed.connect(cb)
	_box.add_child(b)
	return b


## Presenta un evento y resuelve la elección con `resolve(index) -> {text, lines, success}`;
## al pulsar Continuar llama a `on_done`.
func present_event(event_id: String, resolve: Callable, on_done: Callable) -> void:
	var ev: Dictionary = Content.events[event_id]
	open()
	title(T.ev(event_id, "title"))
	body(T.ev(event_id, "text"))
	separator()
	var first: Button = null
	for i in ev["choices"].size():
		var choice: Dictionary = ev["choices"][i]
		var hint := T.ev(event_id, "c%d.hint" % i) if choice.has("requires") else ""
		var lock := EventRunner.lock_reason(choice, GameState, hint)
		var label := T.ev(event_id, "c%d.text" % i)
		if lock != "":
			label += "   [%s]" % lock
		elif choice.has("risk"):
			label += "   (%s)" % _chance_text(choice)
		var b := button(label, _on_pick.bind(event_id, i, resolve, on_done), lock != "")
		if first == null and lock == "":
			first = b
	if first != null:
		first.grab_focus()


func _chance_text(choice: Dictionary) -> String:
	var pct := roundi(EventRunner.success_chance(choice, GameState) * 100.0)
	if choice.has("tag") and GameState.has_trait(choice["tag"]):
		return T.t("ui.choice.chance_bonus", {"pct": pct, "trait": T.t("trait." + choice["tag"])})
	return T.t("ui.choice.chance", {"pct": pct})


func _on_pick(event_id: String, index: int, resolve: Callable, on_done: Callable) -> void:
	var choice: Dictionary = Content.events[event_id]["choices"][index]
	var result: Dictionary = resolve.call(index)
	open()
	var headline := T.ev(event_id, "title")
	if choice.has("risk"):
		headline += " — " + T.t("ui.event.success" if result["success"] else "ui.event.setback")
	title(headline, UITheme.GOOD if result["success"] else UITheme.BAD)
	body(result["text"])
	if not result["lines"].is_empty():
		note("  ·  ".join(result["lines"]))
	button(T.t("ui.continue"), on_done).grab_focus()
