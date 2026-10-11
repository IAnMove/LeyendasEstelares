extends Control
## Raíz del juego: título → avatar → mapa estelar → (planeta | contacto | anomalía) → … → final.

var _current: Control
var _campaign: Campaign
var _vignette: ColorRect


func _ready() -> void:
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


func _show_title() -> void:
	var s := TitleScreen.new()
	s.start_pressed.connect(_show_avatars)
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


func _on_jumped(id: String) -> void:
	var node := _campaign.node(id)
	match node["type"]:
		"planet":
			GameState.begin_planet()
			var s := MapScreen.new()
			s.planet = node["planet"]
			s.finished.connect(func(outcome: Dictionary): _after_planet(id, outcome))
			_swap(s)
		"contact":
			var s := ContactScreen.new()
			s.species_id = node["ref"]
			s.finished.connect(func(_outcome: Dictionary): _after_node(id))
			_swap(s)
		_:
			var s := AnomalyScreen.new()
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
