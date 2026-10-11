class_name MapScreen
extends Control
## Exploración de un planeta: mapa a la izquierda, HUD a la derecha, eventos como panel superpuesto.
## Termina con finished({result: "success"|"abort"|"fail"|"skip", reason}).

signal finished(outcome: Dictionary)

var planet: Dictionary = {}
var expedition: Expedition
var restored: Dictionary = {}
var _phase := "briefing"
var _pending: Dictionary = {}
var _step_buttons: Array[Button] = []

var _view: PlanetMapView
var _log: RichTextLabel
var _o2_label: Label
var _o2_bar: ProgressBar
var _morale_label: Label
var _morale_bar: ProgressBar
var _data_label: Label
var _rep_label: Label
var _goal_label: Label
var _overlay: Overlay
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # si no, este Control se come los clics del mapa
	_rng.randomize()
	expedition = Expedition.new(GameState, planet, Content.events, int(planet.get("seed", 1)))
	if not restored.is_empty():
		expedition.restore(restored["expedition"])
		_rng.state = restored["rng"]
		_phase = restored["phase"]
		_pending = restored["pending"]

	add_child(UITheme.background())
	_view = PlanetMapView.new()
	_view.position = Vector2(8, 8)
	_view.expedition = expedition
	_view.cell_clicked.connect(_on_cell_clicked)
	add_child(_view)
	_build_hud()
	_overlay = Overlay.new()
	_overlay.opened.connect(func(): _view.enabled = false)
	_overlay.closed.connect(func(): _view.enabled = true)
	add_child(_overlay)
	GameState.changed.connect(_refresh_hud)
	_refresh_hud()
	_view.enabled = true
	match _phase:
		"briefing": _show_briefing()
		"event": _open_event(expedition.map.poi_at(expedition.player))
		"result":
			var poi := expedition.map.poi_at(expedition.player)
			_overlay.show_result(poi["event_id"], _pending["index"], _pending["result"], func(): _after_event(poi))
		"fail": _fail(_pending["reason"])
		"conclusion": _conclude(_pending["result"])
	_log.text = restored.get("log", "")


func _build_hud() -> void:
	_log = RichTextLabel.new()
	_log.position = Vector2(8, 258)
	_log.size = Vector2(354, 94)
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.add_theme_font_size_override("normal_font_size", 11)
	_log.add_theme_stylebox_override("normal", UITheme.box(Color(0.04, 0.05, 0.09, 0.85), UITheme.PANEL_BORDER, 5))
	add_child(_log)
	if UITheme.touch_mode():
		_log.hide()
		var steps := HBoxContainer.new()
		steps.position = Vector2(8, 282)
		steps.add_theme_constant_override("separation", 5)
		add_child(steps)
		var caption := UITheme.label(T.t("ui.touch.move"), UITheme.DIM, 11)
		caption.position = Vector2(8, 260)
		caption.size.x = 354
		add_child(caption)
		for i in 6:
			var direction := i
			var b := UITheme.button(["→", "↗", "↖", "←", "↙", "↘"][i])
			b.custom_minimum_size = Vector2(54, 56)
			b.alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.pressed.connect(func():
				if _view.enabled:
					_on_cell_clicked(HexGrid.neighbors(expedition.player)[direction]))
			steps.add_child(b)
			_step_buttons.append(b)

	var panel := PanelContainer.new()
	panel.position = Vector2(370, 8)
	panel.size = Vector2(262, 344)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	var scroll := UITheme.scrolling(panel)
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := UITheme.label(T.t("planet.%s.name" % planet["id"]), UITheme.ACCENT, 16)
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(UITheme.pause_button())
	v.add_child(UITheme.label(T.t("avatar.%s.name" % GameState.avatar["id"]), UITheme.TEXT, 12))
	v.add_child(HSeparator.new())
	_o2_label = UITheme.label("", UITheme.TEXT, 11)
	v.add_child(_o2_label)
	_o2_bar = UITheme.bar(Color("4fc3e8"))
	v.add_child(_o2_bar)
	_morale_label = UITheme.label("", UITheme.TEXT, 11)
	v.add_child(_morale_label)
	_morale_bar = UITheme.bar(Color("e8b45c"))
	v.add_child(_morale_bar)
	_data_label = UITheme.label("", UITheme.ACCENT, 11)
	v.add_child(_data_label)
	_rep_label = UITheme.label("", UITheme.DIM, 10)
	v.add_child(_rep_label)
	v.add_child(HSeparator.new())
	_goal_label = UITheme.label("", UITheme.WARN, 11)
	v.add_child(_goal_label)
	v.add_child(UITheme.label(T.t("ui.touch.map_hint" if UITheme.touch_mode() else "ui.map.hint"), UITheme.DIM, 10))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	var abort := UITheme.button(T.t("ui.map.abort"))
	var cargo := UITheme.button(T.t("ui.cargo.open"))
	cargo.alignment = HORIZONTAL_ALIGNMENT_CENTER
	cargo.pressed.connect(_open_cargo)
	v.add_child(cargo)
	abort.alignment = HORIZONTAL_ALIGNMENT_CENTER
	abort.pressed.connect(_confirm_abort)
	v.add_child(abort)


func _open_cargo() -> void:
	if _overlay.is_open() or not _view.enabled:
		return
	_view.enabled = false
	var screen := ShipScreen.new()
	screen.closed.connect(func():
		screen.queue_free()
		_view.enabled = true
		_refresh_hud())
	add_child(screen)


func _refresh_hud() -> void:
	_o2_label.text = T.t("ui.hud.oxygen", {"cur": GameState.oxygen, "max": GameState.max_oxygen})
	_o2_bar.max_value = GameState.max_oxygen
	_o2_bar.value = GameState.oxygen
	_morale_label.text = T.t("ui.hud.morale", {"cur": GameState.morale, "max": GameState.max_morale})
	_morale_bar.max_value = GameState.max_morale
	_morale_bar.value = GameState.morale
	_data_label.text = T.t("ui.hud.data", {"n": GameState.data})
	var parts: Array[String] = []
	for f in GameState.rep:
		parts.append("%s %+d" % [T.t("faction." + f), GameState.rep[f]])
	_rep_label.text = T.t("ui.hud.rep", {"list": ", ".join(parts) if not parts.is_empty() else "—"})
	_goal_label.text = T.t("ui.map.goal_done" if expedition.objective_done else "ui.map.goal_pending")
	for i in _step_buttons.size():
		var cell: Vector2i = HexGrid.neighbors(expedition.player)[i]
		_step_buttons[i].disabled = not expedition.can_move(cell)
		_step_buttons[i].text = ["→", "↗", "↖", "←", "↙", "↘"][i]
		if expedition.can_move(cell):
			_step_buttons[i].text += "\n−%d O₂" % expedition.map.move_cost(cell)


func _say(text: String, color := UITheme.TEXT) -> void:
	_log.append_text("[color=#%s]%s[/color]\n" % [color.to_html(false), text])


# ---------------------------------------------------------------- movimiento
func _on_cell_clicked(cell: Vector2i) -> void:
	if not expedition.can_move(cell):
		return
	var cost := expedition.map.move_cost(cell)
	var res := expedition.move(cell)
	_refresh_hud()
	Sound.play("step")
	_say(T.t("ui.log.move", {"cost": cost}), UITheme.DIM)
	if res["failure"] != "":
		_fail(res["failure"])
	elif not res["poi"].is_empty():
		_open_event(res["poi"])
	elif res["home"]:
		_conclude("success")


# ------------------------------------------------------------------- diálogos
func _show_briefing() -> void:
	var pid: String = planet["id"]
	_overlay.open()
	_overlay.title(T.t("ui.briefing.title", {"planet": T.t("planet.%s.name" % pid)}))
	_overlay.art("generated/planet_" + pid)
	_overlay.body(T.t("planet.%s.intro" % pid))
	_overlay.button(T.t("ui.descend"), func():
		_phase = "explore"
		_overlay.close()
		Sound.play("signal")
		_say(T.t("ui.log.descend"), UITheme.ACCENT)
	).grab_focus()
	if not planet.get("final", false):
		_overlay.button(T.t("ui.skip_planet"), func(): finished.emit({"result": "skip", "reason": ""}))


func _open_event(poi: Dictionary) -> void:
	_phase = "event"
	_overlay.present_event(
		poi["event_id"],
		func(i: int):
			var result := expedition.resolve_choice(poi, i, _rng)
			_phase = "result"
			_pending = {"index": i, "result": result}
			return result,
		func(): _after_event(poi))


func _after_event(poi: Dictionary) -> void:
	_phase = "explore"
	_pending = {}
	_refresh_hud()
	_say("%s" % T.ev(poi["event_id"], "title"), UITheme.TEXT)
	if poi["objective"]:
		_say(T.t("ui.map.goal_done"), UITheme.GOOD)
	var reason := GameState.failure_reason()
	if reason != "":
		_fail(reason)
		return
	_overlay.close()


func _fail(reason: String) -> void:
	_phase = "fail"
	_pending = {"reason": reason}
	_overlay.open()
	_overlay.title(T.t("ui.fail.title"), UITheme.BAD)
	_overlay.body(T.t("ui.fail.oxygen" if reason == "oxygen" else "ui.fail.morale"))
	_overlay.button(T.t("ui.continue"), func(): finished.emit({"result": "fail", "reason": reason})).grab_focus()


func _confirm_abort() -> void:
	if _overlay.is_open():
		return
	_overlay.open()
	_overlay.title(T.t("ui.abort.title"), UITheme.WARN)
	_overlay.body(T.t("ui.abort.body"))
	_overlay.button(T.t("ui.abort.yes"), func(): _conclude("abort")).grab_focus()
	_overlay.button(T.t("ui.abort.no"), _overlay.close)


## Cierra la salida con un pequeño epílogo del planeta.
func _conclude(result: String) -> void:
	_phase = "conclusion"
	_pending = {"result": result}
	var pid: String = planet["id"]
	_overlay.open()
	if result == "success":
		_overlay.title(T.t("ui.planet.done"), UITheme.GOOD)
		_overlay.body(T.t("planet.%s.outro_success" % pid))
	else:
		_overlay.title(T.t("ui.planet.aborted"), UITheme.WARN)
		_overlay.body(T.t("planet.%s.outro_abort" % pid))
	_overlay.button(T.t("ui.continue"), func(): finished.emit({"result": result, "reason": ""})).grab_focus()


func save_state() -> Dictionary:
	return {"kind": "planet", "expedition": expedition.snapshot(), "rng": _rng.state,
		"phase": _phase, "pending": _pending, "log": _log.text}
