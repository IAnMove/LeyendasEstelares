extends Node
## Prueba integral del guardado, con ruta aislada y recreación real de pantallas.

const SLOT := "user://test-expedition.save"
var failures := 0
var main

func _ready() -> void:
	SaveStore.clear(SLOT)
	main = load("res://scenes/main.tscn").instantiate()
	main.save_path = SLOT
	add_child(main)
	GameState.start_run(Content.avatar_by_id("vance"), Content.factions, Content.campaign)
	main._campaign = Campaign.new(GameState, Content.campaign, 12)
	main._show_sector()
	await frames()
	check(not SaveStore.read(SLOT).is_empty(), "se guarda el sector")
	var campaign: Dictionary = main._campaign.snapshot()
	GameState.data = 7
	main._save_checkpoint()
	main._show_title()
	main._resume()
	await frames()
	check(main._campaign.snapshot() == campaign and GameState.data == 7, "sector y recursos conservados")

	# Atrás, subpantallas y ciclo de vida Android sin salir ni cambiar el silencio elegido.
	main._go_back()
	check(is_instance_valid(main._pause_menu), "Atrás abre pausa")
	check(Sound.suspended and main._current.process_mode == Node.PROCESS_MODE_DISABLED, "pausa audio e interacción")
	main._go_back()
	await frames()
	check(not Sound.suspended, "Atrás reanuda")
	var muted := Sound.muted
	main._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check(Sound.suspended, "segundo plano suspende audio")
	main._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check(Sound.suspended and Sound.muted == muted, "volver conserva pausa y preferencia de audio")
	main._close_pause()
	await frames()
	main._current._open_ship()
	await frames()
	main._go_back()
	await frames()
	check(not is_instance_valid(main._pause_menu), "Atrás cierra bodega antes de pausar")

	# Partida en superficie, con posición, niebla, POI y resultado pendiente.
	var planet_id := ""
	var contact_id := ""
	var anomaly_id := ""
	for id in main._campaign.sector.nodes:
		match main._campaign.node(id)["type"]:
			"planet": planet_id = id
			"contact": contact_id = id
			"anomaly": anomaly_id = id
	main._campaign.current = planet_id
	main._on_jumped(planet_id)
	await frames()
	var surface: MapScreen = main._current
	var poi: Dictionary = surface.expedition.map.pois[0]
	surface.expedition.player = poi["cell"]
	surface.expedition.map.reveal(poi["cell"], 2)
	surface._rng.seed = 1337
	var outcome := surface.expedition.resolve_choice(poi, 2, surface._rng)
	surface._phase = "result"
	surface._pending = {"index": 2, "result": outcome}
	main._save_checkpoint()
	var before := GameState.snapshot()
	var expected := surface.save_state()
	main._show_title()
	main._resume()
	await frames()
	check(main._current.save_state() == expected, "superficie completa y RNG restaurados")
	check(GameState.snapshot() == before, "reanudar evento no repite sus efectos")

	# Contacto ya resuelto: recompensas, relación y existencias no se duplican.
	main._campaign.current = contact_id
	main._on_jumped(contact_id)
	await frames()
	var contact: ContactScreen = main._current
	while not contact.runner.finished():
		contact.runner.choose(0 if contact.runner.lock_reason(0) == "" else 1)
	contact._show_outcome()
	GameState.market_stock = {"test": {"fuel_cell": 1}}
	main._save_checkpoint()
	before = GameState.snapshot()
	expected = contact.save_state()
	main._show_title()
	main._resume()
	await frames()
	check(main._current.save_state() == expected, "contacto y desenlace restaurados")
	check(GameState.snapshot() == before, "sin recompensas ni existencias duplicadas")

	main._campaign.current = anomaly_id
	main._on_jumped(anomaly_id)
	await frames()
	var anomaly: AnomalyScreen = main._current
	anomaly._choice = 2
	anomaly._result = EventRunner.resolve(anomaly.event_id, 2, Content.events[anomaly.event_id]["choices"][2], GameState, anomaly._rng)
	main._save_checkpoint()
	before = GameState.snapshot()
	expected = anomaly.save_state()
	main._show_title()
	main._resume()
	await frames()
	check(main._current.save_state() == expected and GameState.snapshot() == before, "anomalía pendiente idempotente")

	# Continuación narrativa en tránsito; recuperar resultado no repite la recompensa.
	GameState.queue_story({"event": "convoy_rescatado", "delay": 1})
	GameState.story_turn += 1
	main._campaign.current = planet_id
	main._on_jumped(planet_id)
	await frames()
	check(main._current is AnomalyScreen and main._current.is_story, "la consecuencia llega antes del destino")
	var story: AnomalyScreen = main._current
	story._choice = 1
	story._result = EventRunner.resolve(story.event_id, 1, Content.events[story.event_id]["choices"][1], GameState, story._rng)
	main._save_checkpoint()
	before = GameState.snapshot()
	main._show_title()
	main._resume()
	await frames()
	check(main._current.is_story and GameState.snapshot() == before, "reanudar conserva la transmisión y su continuación")
	main._current.finished.emit()
	await frames()
	check(main._current is MapScreen and GameState.story_active.is_empty(), "después de la transmisión se llega al planeta")

	# Guardado truncado: se recupera el último archivo verificado.
	main._save_checkpoint()
	var backup := SaveStore.read(SLOT)
	var file := FileAccess.open(SLOT, FileAccess.WRITE)
	file.store_string("truncado")
	file.close()
	check(SaveStore.read(SLOT) == backup, "recupera copia de respaldo tras truncado")
	check(SaveStore.write(backup, SLOT) == OK, "reemplaza el archivo dañado")
	check(SaveStore.write({"state": {}}, SLOT) == ERR_INVALID_DATA, "rechaza esquema incompleto")
	main._end("victory")
	await frames()
	check(SaveStore.read(SLOT).is_empty(), "borra guardado y respaldo al terminar")
	SaveStore.clear(SLOT)
	main.queue_free()
	Sound.set_muted(true, false)
	await frames()
	print("GUARDADO: %d fallos" % failures)
	get_tree().quit(0 if failures == 0 else 1)

func frames() -> void:
	for i in 4:
		await get_tree().process_frame

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		print("FALLO: ", message)
