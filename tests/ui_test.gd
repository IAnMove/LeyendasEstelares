extends Node
## Prueba de interfaz con entradas reales: recorre título → avatar → mapa estelar → planeta / contacto / anomalía.
## godot --headless --path . res://tests/ui_test.tscn

var _failures := 0
var _main: Control


func _ready() -> void:
	T.set_language("en", false)
	_main = load("res://scenes/main.tscn").instantiate()
	_main.save_path = ""
	add_child(_main)
	await _frames()

	# Título e idioma
	_check(_main._current is TitleScreen, "arranca en el título")
	var lang_buttons := _buttons(_main._current, "Español")
	_check(not lang_buttons.is_empty(), "hay selector de idioma")
	lang_buttons[0].pressed.emit()
	await _frames()
	_check(T.language() == "es", "el botón cambia el idioma a español")
	_check(not _buttons(_main._current, "Nueva expedición").is_empty(), "el título se retraduce")
	_buttons(_main._current, "English")[0].pressed.emit()
	await _frames()
	_check(T.language() == "en", "vuelve a inglés")
	var muted_before := Sound.muted
	var mute_key := InputEventKey.new()
	mute_key.keycode = KEY_M
	mute_key.pressed = true
	get_viewport().push_input(mute_key)
	await _frames()
	_check(Sound.muted != muted_before, "M alterna el sonido")
	_check(not _buttons(_main._current, "Sound: off" if Sound.muted else "Sound: on").is_empty(), "el título refleja el silencio por teclado")
	Sound.set_muted(muted_before, false)
	_buttons(_main._current, "New expedition")[0].pressed.emit()
	await _frames()

	# Avatar → mapa estelar
	_check(_main._current is AvatarScreen, "pantalla de avatar")
	# Las versiones cambian los retratos renderizados, sin alterar los sprites ni la partida.
	_buttons(_main._current, "V1 original")[0].pressed.emit()
	await _frames()
	var original := Art.tex("generated/crew_vance")
	_check(original.resource_path == "res://art/generated/crew_vance.png", "V1 carga el retrato original")
	_check(_avatar_portrait_path().contains("generated/crew_vance.png"), "la ficha muestra V1 tras cambiar")
	_buttons(_main._current, "V2 comic")[0].pressed.emit()
	await _frames()
	_check(_avatar_portrait_path().contains("v2_retro/crew_vance.png"), "la ficha muestra V2 sin reiniciar")
	_check(Art.tex("generated/crew_vance") != original, "la caché separa ambas versiones")
	for portrait in Art.PORTRAITS:
		_check(Art.tex("generated/" + portrait).resource_path.contains("v2_retro/"), "versión coherente: " + portrait)
	_check(Art.tex("avatar_vance").resource_path == "res://art/avatar_vance.png", "el sprite táctico se conserva")
	Art.set_portrait_version("v1_original", false)
	Art.load_settings()
	_check(Art.portrait_version == "v2_retro", "se conserva la elección entre sesiones")
	_buttons(_main._current, "Choose")[0].pressed.emit()
	await _frames()
	_check(_main._current is SectorScreen, "mapa estelar tras elegir avatar")
	# Fixture estable: los recorridos posteriores prueban pantallas por separado.
	_main._campaign = Campaign.new(GameState, Content.campaign, 12)
	_main._show_sector()
	await _frames()
	var sector: SectorScreen = _main._current
	var camp: Campaign = _main._campaign
	var fuel0: int = GameState.fuel
	_buttons(sector, "Crew & cargo")[0].pressed.emit()
	await _frames()
	var ship: ShipScreen = sector.get_child(sector.get_child_count() - 1)
	_check(ship is ShipScreen, "se abre la tripulación y bodega")
	_check(sector._buttons.values()[0].focus_mode == Control.FOCUS_NONE, "el menú bloquea el foco del mapa de fondo")
	_buttons(ship, "Assign leader")[0].pressed.emit()
	await _frames()
	_check(GameState.avatar["id"] == "okafor", "el botón asigna a Okafor como líder")
	_buttons(ship, "Return")[0].pressed.emit()
	await _frames()
	_check(sector._buttons.values()[0].focus_mode == Control.FOCUS_ALL, "cerrar el menú restaura el foco del mapa")

	if UITheme.touch_mode():
		for node_button in sector._buttons.values():
			_check(node_button.size.x >= 48 and node_button.size.y >= 48, "objetivo táctil de al menos 48 unidades")

	# Seleccionar un nodo alcanzable, escanear y saltar con los botones reales
	var target: String = camp.sector.nodes[camp.current]["edges"][0]
	sector._buttons[target].pressed.emit()
	await _frames()
	var scan_btn := _buttons(sector, "Scan")
	_check(not scan_btn.is_empty() and not scan_btn[0].disabled, "botón de escanear disponible")
	scan_btn[0].pressed.emit()
	await _frames()
	_check(camp.node(target)["scanned"], "el escaneo revela el nodo")
	var jump_btn := _buttons(sector, "Jump")
	_check(not jump_btn.is_empty() and not jump_btn[0].disabled, "botón de saltar disponible")
	jump_btn[0].pressed.emit()
	await _frames()
	_check(camp.current == target and GameState.fuel < fuel0, "el salto mueve la nave y gasta combustible")
	_check(not (_main._current is SectorScreen), "se abre la pantalla del nodo (%s)" % camp.node(target)["type"])

	# Planeta: clic y teclado reales sobre el mapa hexagonal
	var planet_id := _find_node(camp, "planet", false)
	camp.current = planet_id
	_main._on_jumped(planet_id)
	await _frames()
	_check(_main._current is MapScreen, "pantalla de planeta")
	var screen: MapScreen = _main._current
	var view: PlanetMapView = screen._view
	_check(not view.enabled, "el mapa está bloqueado durante el briefing")
	_check(not _buttons(screen, "Do not descend").is_empty(), "en un planeta intermedio se puede no descender")
	_buttons(screen, "Descend")[0].pressed.emit()
	await _frames()
	_check(view.enabled, "el mapa se activa al descender")
	var ex := screen.expedition
	var adj := _adjacent(ex)
	var start := ex.player
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = view.get_global_transform_with_canvas() * HexGrid.center(adj)
	click.global_position = click.position
	get_viewport().push_input(click, true)
	await _frames()
	_check(ex.player == adj, "un clic sobre un hexágono adyacente mueve al jugador (%s → %s)" % [start, ex.player])
	var before := ex.player
	for key in [KEY_D, KEY_E, KEY_C, KEY_A, KEY_Q, KEY_Z]:
		if ex.player != before or not screen._view.enabled:
			break
		var ev := InputEventKey.new()
		ev.keycode = key
		ev.pressed = true
		get_viewport().push_input(ev)
		await _frames()
	_check(ex.player != before or not screen._view.enabled, "el teclado mueve al jugador (o abre un evento)")
	screen._overlay.close()
	GameState.oxygen = 10
	_buttons(screen, "Supplies & equipment")[0].pressed.emit()
	await _frames()
	var cargo: ShipScreen = screen.get_child(screen.get_child_count() - 1)
	_check(not view.enabled, "abrir suministros bloquea el mapa")
	_check(_buttons(cargo, "Assign leader")[0].disabled, "no se cambia de líder en superficie")
	_buttons(cargo, "Use")[0].pressed.emit()
	await _frames()
	_check(GameState.oxygen == 22 and GameState.item_count("oxygen_cell") == 0, "el botón consume oxígeno de la bodega")
	_buttons(cargo, "Return")[0].pressed.emit()
	await _frames()
	_check(view.enabled, "cerrar suministros reactiva el mapa")
	screen.finished.emit({"result": "abort", "reason": ""})
	await _frames()
	_check(_main._current is SectorScreen, "tras abortar se vuelve al mapa estelar")

	# Contacto: recorre la conversación pulsando botones
	for sp in Content.campaign["species"]:
		var cid := _find_node(camp, "contact", false, sp)
		camp.current = cid
		GameState.fuel = GameState.max_fuel
		_main._on_jumped(cid)
		await _frames()
		_check(_main._current is ContactScreen, "pantalla de contacto (%s)" % sp)
		var guard := 0
		while _main._current is ContactScreen and guard < 20:
			guard += 1
			var btns := _enabled_buttons(_main._current._options)
			_check(not btns.is_empty(), "siempre hay un botón pulsable en el contacto")
			if btns.is_empty():
				break
			var market_buttons := _buttons(_main._current, "Open trade channel")
			if not market_buttons.is_empty():
				GameState.data = 20
				market_buttons[0].pressed.emit()
				await _frames()
				var market: TradeScreen = _main._current.get_child(_main._current.get_child_count() - 1)
				_check(market is TradeScreen, "un acuerdo abre el mercado de la especie")
				var balance := GameState.data
				_buttons(market, "Buy")[0].pressed.emit()
				await _frames()
				_check(GameState.data < balance, "comprar desde la UI gasta datos")
				_buttons(market, "Sell")[0].pressed.emit()
				await _frames()
				_buttons(market, "Close market")[0].pressed.emit()
				await _frames()
				_buttons(_main._current, "Close the channel")[0].pressed.emit()
				await _frames()
				break
			btns[0].pressed.emit()
			await _frames()
		_check(_main._current is SectorScreen, "el contacto %s termina y vuelve al mapa" % sp)

	# Anomalía
	var aid := _find_node(camp, "anomaly", false)
	camp.current = aid
	_main._on_jumped(aid)
	await _frames()
	_check(_main._current is AnomalyScreen, "pantalla de anomalía")
	var guard2 := 0
	while _main._current is AnomalyScreen and guard2 < 5:
		guard2 += 1
		_enabled_buttons(_main._current)[0].pressed.emit()
		await _frames()
	_check(_main._current is SectorScreen, "la anomalía termina y vuelve al mapa")

	# Final: el planeta final aparece sin opción de saltarlo y da la victoria
	_main._on_jumped(camp.sector.final_id)
	await _frames()
	_check(_buttons(_main._current, "Do not descend").is_empty(), "el planeta final no se puede saltar")
	_main._current.finished.emit({"result": "success", "reason": ""})
	await _frames()
	_check(_main._current is EndScreen and _main._current.ending == "victory", "final de victoria")
	_buttons(_main._current, "Back to title")[0].pressed.emit()
	await _frames()
	_check(_main._current is TitleScreen, "vuelve al título")

	print("\n%s (%d fallos)" % ["UI OK" if _failures == 0 else "FALLOS", _failures])
	Sound.set_muted(true, false)
	_main.queue_free()
	await _frames()
	get_tree().quit(0 if _failures == 0 else 1)


func _frames(n := 3) -> void:
	for i in n:
		await get_tree().process_frame
	if _main != null and _main._current != null:
		for panel in _main._current.find_children("*", "PanelContainer", true, false):
			if panel.is_visible_in_tree():
				var rect: Rect2 = panel.get_global_rect()
				if rect.position.x < -1 or rect.position.y < -1 or rect.end.x > 641 or rect.end.y > 361:
					_check(false, "panel fuera de pantalla: %s %s" % [panel.get_path(), rect])


func _find_node(camp: Campaign, type: String, done: bool, ref := "") -> String:
	for id in camp.sector.nodes:
		var n: Dictionary = camp.sector.nodes[id]
		if n["type"] == type and n["done"] == done and not n["final"] and (ref == "" or n["ref"] == ref):
			return id
	return ""


func _buttons(root: Node, starts_with: String) -> Array[Button]:
	var out: Array[Button] = []
	for n in root.find_children("*", "Button", true, false):
		if (n as Button).text.begins_with(starts_with):
			out.append(n)
	return out


func _enabled_buttons(root: Node) -> Array[Button]:
	var out: Array[Button] = []
	for n in root.find_children("*", "Button", true, false):
		var b := n as Button
		if b.is_visible_in_tree() and not b.disabled and b.text != "":
			out.append(b)
	return out


func _adjacent(ex: Expedition) -> Vector2i:
	for n in HexGrid.neighbors(ex.player):
		if ex.can_move(n) and ex.map.poi_at(n).is_empty():
			return n
	return ex.player


func _check(cond: bool, msg: String) -> void:
	print(("  ok: " if cond else "  FALLO: ") + msg)
	if not cond:
		_failures += 1


func _avatar_portrait_path() -> String:
	for view in _main._current.find_children("*", "TextureRect", true, false):
		if view.texture != null and view.texture.resource_path.contains("crew_vance"):
			return view.texture.resource_path
	return ""
