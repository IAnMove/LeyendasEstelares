class_name ContactScreen
extends Control
## Comunicación de primer contacto: retrato de la especie, barras de confianza/tensión y respuestas por postura.
## Termina con finished({result: "alliance"|"deal"|"wary"|"hostile"}).

signal finished(outcome: Dictionary)

var species_id := ""
var runner: ContactRunner
var restored: Dictionary = {}
var _phase := "intro"
var _reply: Dictionary = {}

var _species: Dictionary
var _color := Color.WHITE
var _trust_bar: ProgressBar
var _tension_bar: ProgressBar
var _trust_label: Label
var _tension_label: Label
var _speech: Label
var _extra: Label
var _options: VBoxContainer
var _outcome: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_species = Content.species_by_id(species_id)
	_color = Color(_species["color"])
	runner = ContactRunner.new(GameState, _species, Content.encounter_for(species_id))
	if not restored.is_empty():
		runner.restore(restored["runner"])
		_phase = restored["phase"]
		_reply = restored["reply"]
	add_child(UITheme.background())
	_build_left()
	_build_right()
	_refresh_bars()
	match _phase:
		"intro": _show_intro()
		"prompt": _show_prompt()
		"reply": _show_reply()
		"outcome": _show_outcome()


func _build_left() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.size = Vector2(196, 328)
	panel.add_theme_stylebox_override("panel", UITheme.box(UITheme.PANEL, _color.darkened(0.3), 8, 1))
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	var portrait := TextureRect.new()
	portrait.texture = Art.tex(_species["portrait"])
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	portrait.custom_minimum_size = Vector2(178, 145)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/comm.gdshader")
	mat.set_shader_parameter("tint", _color)
	portrait.material = mat
	v.add_child(portrait)
	v.add_child(UITheme.label(T.t("species.%s.name" % species_id), _color, 16))
	var desc := UITheme.label(T.t("species.%s.desc" % species_id), UITheme.DIM, 10)
	v.add_child(desc)
	_trust_label = UITheme.label("", UITheme.TEXT, 10)
	v.add_child(_trust_label)
	_trust_bar = UITheme.bar(UITheme.GOOD)
	_trust_bar.max_value = ContactRunner.MAX_METER
	v.add_child(_trust_bar)
	_tension_label = UITheme.label("", UITheme.TEXT, 10)
	v.add_child(_tension_label)
	_tension_bar = UITheme.bar(UITheme.BAD)
	_tension_bar.max_value = ContactRunner.MAX_METER
	v.add_child(_tension_bar)
	var hint := _hint_text()
	if hint != "":
		v.add_child(UITheme.label(hint, UITheme.WARN, 10))


func _hint_text() -> String:
	var value := T.t("ui.value." + runner.best_stance())
	if GameState.has_trait("ciencia"):
		return T.t("ui.contact.analysis", {"value": value})
	if GameState.has_flag("met_" + species_id):
		return T.t("ui.contact.experience", {"value": value})
	return ""


func _build_right() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(222, 16)
	panel.size = Vector2(402, 328)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var caption := UITheme.caption(T.t("ui.contact.channel"), UITheme.WARN)
	caption.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(caption)
	head.add_child(UITheme.pause_button())
	var scroll := UITheme.scrolling(v)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	scroll.add_child(body)
	v = body
	v.add_child(HSeparator.new())
	_speech = UITheme.label("", _color, 14)
	_speech.custom_minimum_size = Vector2(360, 58)
	v.add_child(_speech)
	_extra = UITheme.label("", UITheme.DIM, 11)
	_extra.custom_minimum_size = Vector2(360, 30)
	v.add_child(_extra)
	v.add_child(HSeparator.new())
	_options = VBoxContainer.new()
	_options.add_theme_constant_override("separation", 6)
	v.add_child(_options)


func _refresh_bars() -> void:
	_trust_bar.value = runner.trust
	_tension_bar.value = runner.tension
	_trust_label.text = "%s  %d/%d" % [T.t("ui.contact.trust"), runner.trust, ContactRunner.MAX_METER]
	_tension_label.text = "%s  %d/%d" % [T.t("ui.contact.tension"), runner.tension, ContactRunner.MAX_METER]


func _clear_options() -> void:
	for c in _options.get_children():
		_options.remove_child(c)
		c.queue_free()


func _add_option(text: String, cb: Callable, disabled := false) -> Button:
	var b := UITheme.button(text)
	b.custom_minimum_size = Vector2(360, 0)
	b.add_theme_font_size_override("font_size", 11)
	b.disabled = disabled
	b.pressed.connect(cb)
	_options.add_child(b)
	return b


func _show_intro() -> void:
	_clear_options()
	_speech.text = T.t("contact.%s.intro" % runner.encounter["id"])
	_speech.add_theme_color_override("font_color", UITheme.TEXT)
	_extra.text = ""
	_add_option(T.t("ui.continue"), _show_prompt).grab_focus()


func _show_prompt() -> void:
	_phase = "prompt"
	_clear_options()
	var eid: String = runner.encounter["id"]
	var x := runner.index
	_speech.add_theme_color_override("font_color", _color)
	_speech.text = T.t("contact.%s.x%d.prompt" % [eid, x])
	_extra.text = T.t("contact.%s.x%d.context" % [eid, x]) + "\n" + T.t("ui.contact.repetition")
	var first: Button = null
	var opts: Array = runner.exchange()["options"]
	for i in opts.size():
		var hint := T.t("contact.%s.x%d.o%d.hint" % [eid, x, i]) if opts[i].has("requires") else ""
		var lock := runner.lock_reason(i, hint)
		var label := "[%s]  %s" % [T.t("ui.stance." + opts[i]["stance"]), T.t("contact.%s.x%d.o%d" % [eid, x, i])]
		var forecast := runner.preview(i)
		label += "\n" + T.t("ui.contact.forecast", {"trust": "%+d" % forecast["trust"], "tension": "%+d" % forecast["tension"]})
		if forecast["cost"] > 0:
			label += " · " + T.t("ui.contact.data_cost", {"n": forecast["cost"]})
		if forecast["repeats"] > 0:
			label += " · " + T.t("ui.contact.repeated")
		if lock != "":
			label += "   [%s]" % lock
		var b := _add_option(label, _on_choose.bind(i), lock != "")
		if first == null and lock == "":
			first = b
	if first != null:
		first.grab_focus()


func _on_choose(i: int) -> void:
	var eid: String = runner.encounter["id"]
	var x := runner.index
	var mine := T.t("contact.%s.x%d.o%d" % [eid, x, i])
	_reply = {"mine": mine, "result": runner.choose(i)}
	_show_reply()


func _show_reply() -> void:
	_phase = "reply"
	var mine: String = _reply["mine"]
	var res: Dictionary = _reply["result"]
	_refresh_bars()
	_clear_options()
	_speech.add_theme_color_override("font_color", _color)
	_speech.text = T.t(res["key"])
	_extra.text = "%s: %s\n%s" % [T.t("ui.contact.you"), mine, "  ·  ".join(res["lines"])]
	_add_option(T.t("ui.continue"), _after_reply).grab_focus()


func _after_reply() -> void:
	if runner.finished():
		_show_outcome()
	else:
		_show_prompt()


func _show_outcome() -> void:
	_phase = "outcome"
	_clear_options()
	var out := runner.apply_outcome()
	_outcome = out
	var colors := {"alliance": UITheme.GOOD, "deal": UITheme.ACCENT, "wary": UITheme.DIM, "hostile": UITheme.BAD}
	_speech.add_theme_color_override("font_color", colors[out["id"]])
	_speech.text = "%s\n\n%s" % [T.t("ui.contact.result." + out["id"]), T.t(out["key"])]
	_extra.text = "  ·  ".join(out["lines"])
	_add_option(T.t("ui.contact.close"), func(): finished.emit({"result": out["id"]})).grab_focus()
	if out["id"] in ["alliance", "deal"]:
		_add_option(T.t("ui.trade.open"), _open_trade)
	else:
		_extra.text += "\n" + T.t("ui.trade.closed")


func _open_trade() -> void:
	var screen := TradeScreen.new()
	screen.species_id = species_id
	screen.closed.connect(func():
		screen.queue_free()
		_show_outcome())
	add_child(screen)


func save_state() -> Dictionary:
	return {"kind": "contact", "runner": runner.snapshot(), "phase": _phase, "reply": _reply}
