extends Control
## Raíz del juego: título → avatar → mapa estelar → (planeta | contacto | anomalía) → … → final.

var _current: Control
var _campaign: Campaign
var _vignette: ColorRect
var save_path := SaveStore.PATH
var _save_queued := false
var _last_save_error := OK


func _ready() -> void:
	add_to_group("checkpoint_owner")
	GameState.changed.connect(queue_checkpoint)
	T.load_language()
	Art.load_settings()
	theme = UITheme.build()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette = ColorRect.new()
	_vignette.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/vignette.gdshader")
	_vignette.material = mat
	add_child(_vignette)
	_show_title()


func _swap(screen: Control) -> void:
	if _current != null:
		_current.queue_free()
	_current = screen
	add_child(screen)
	move_child(_vignette, -1)  # la viñeta siempre por encima
	screen.modulate.a = 0.0
	create_tween().tween_property(screen, "modulate:a", 1.0, 0.25)
	queue_checkpoint()


func _show_title() -> void:
	var s := TitleScreen.new()
	s.has_save = not save_path.is_empty() and not SaveStore.read(save_path).is_empty()
	s.resume_pressed.connect(_resume)
	s.start_pressed.connect(_request_new_run)
	s.quit_pressed.connect(func(): get_tree().quit())
	s.language_changed.connect(_show_title)
	_swap(s)


func _show_avatars() -> void:
	var s := AvatarScreen.new()
	s.avatar_chosen.connect(func(id: String):
		GameState.start_run(Content.avatar_by_id(id), Content.factions, Content.campaign)
		_campaign = Campaign.new(GameState, Content.campaign, randi())
		_show_sector())
	_swap(s)


func _show_sector() -> void:
	GameState.on_surface = false
	var s := SectorScreen.new()
	s.campaign = _campaign
	s.jumped.connect(_on_jumped)
	_swap(s)


func _on_jumped(id: String, restored: Dictionary = {}) -> void:
	var node := _campaign.node(id)
	match node["type"]:
		"planet":
			if restored.is_empty():
				GameState.begin_planet()
			var s := MapScreen.new()
			s.restored = restored
			s.planet = node["planet"]
			s.finished.connect(func(outcome: Dictionary): _after_planet(id, outcome))
			_swap(s)
		"contact":
			var s := ContactScreen.new()
			s.restored = restored
			s.species_id = node["ref"]
			s.finished.connect(func(_outcome: Dictionary): _after_node(id))
			_swap(s)
		_:
			var s := AnomalyScreen.new()
			s.restored = restored
			s.event_id = node["ref"]
			s.finished.connect(func(): _after_node(id))
			_swap(s)


func _after_planet(id: String, outcome: Dictionary) -> void:
	if outcome["result"] == "fail":
		_end(outcome["reason"])
		return
	if _campaign.is_final(id):
		_end("victory" if outcome["result"] == "success" else "abort")
		return
	_after_node(id)


func _after_node(id: String) -> void:
	_campaign.finish_node(id)
	var reason := _campaign.end_reason()
	if reason != "":
		_end(reason)
	else:
		_show_sector()


func _end(ending: String) -> void:
	if not save_path.is_empty():
		SaveStore.clear(save_path)
	GameState.on_surface = false
	Sound.play("signal" if ending == "victory" else "warning")
	var s := EndScreen.new()
	s.ending = ending
	s.jumps = _campaign.jumps
	s.continue_pressed.connect(_show_title)
	_swap(s)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11:
			var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
		elif event.keycode == KEY_M:
			Sound.set_muted(not Sound.muted)


func _request_new_run() -> void:
	if save_path.is_empty() or SaveStore.read(save_path).is_empty():
		_show_avatars()
		return
	var modal := Overlay.new()
	_current.add_child(modal)
	modal.open()
	modal.title(T.t("ui.save.replace_title"))
	modal.body(T.t("ui.save.replace_body"))
	modal.button(T.t("ui.new_expedition"), _show_avatars)
	modal.button(T.t("ui.save.cancel"), modal.queue_free).grab_focus()


func queue_checkpoint() -> void:
	if _save_queued:
		return
	_save_queued = true
	_save_checkpoint.call_deferred()


func _save_checkpoint() -> void:
	_save_queued = false
	if save_path.is_empty() or _campaign == null or not is_instance_valid(_current):
		return
	var screen := {}
	if _current is SectorScreen:
		screen = {"kind": "sector"}
	elif _current.has_method("save_state"):
		screen = _current.save_state()
	if screen.is_empty():
		return
	var error := SaveStore.write({"state": GameState.snapshot(), "campaign": _campaign.snapshot(), "screen": screen}, save_path)
	if error != OK and _last_save_error == OK:
		var modal := Overlay.new()
		_current.add_child(modal)
		modal.open()
		modal.title(T.t("ui.save.error_title"), UITheme.BAD)
		modal.body(T.t("ui.save.error_body"))
		modal.button(T.t("ui.continue"), modal.queue_free)
	_last_save_error = error


func _resume() -> void:
	var saved := SaveStore.read(save_path)
	if saved.is_empty():
		_show_title()
		return
	GameState.restore(saved["state"])
	_campaign = Campaign.new(GameState, Content.campaign, 0)
	_campaign.restore(saved["campaign"])
	if saved["screen"]["kind"] == "sector":
		_show_sector()
	else:
		_on_jumped(_campaign.current, saved["screen"])
