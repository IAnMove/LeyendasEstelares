extends Node
## Captura pantallas del juego real (requiere display, p. ej. xvfb-run).
## xvfb-run -a godot --path . res://tests/screenshot.tscn -- <directorio_salida> [en|es]

var _out := "/tmp"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	var lang := args[1] if args.size() > 1 else "en"
	var main: Control = load("res://scenes/main.tscn").instantiate()
	main.save_path = ""
	add_child(main)
	T.set_language(lang, false)
	Art.set_portrait_version(args[2] if args.size() > 2 else "v2_retro", false)
	main._show_title()
	await _shot("1_title")
	main._show_avatars()
	await _shot("2_avatars")
	GameState.start_run(Content.avatar_by_id("vance"), Content.factions, Content.campaign)
	main._campaign = Campaign.new(GameState, Content.campaign, 12)
	main._show_sector()
	await _shot("3_sector")
	var camp: Campaign = main._campaign
	# Escanea el primer nodo y selecciónalo.
	var first: String = camp.sector.nodes[camp.current]["edges"][0]
	camp.scan(first)
	main._current._select(first)
	await _shot("4_sector_scanned")
	var ship := ShipScreen.new()
	main._swap(ship)
	await _shot("4_ship")
	GameState.relations["hallen"] = "alliance"
	GameState.data = 12
	var market := TradeScreen.new()
	market.species_id = "hallen"
	main._swap(market)
	await _shot("4_trade")

	for sp in ["vael", "hallen", "draeth"]:
		var cs := ContactScreen.new()
		cs.species_id = sp
		main._swap(cs)
		await _shot("5_contact_%s_intro" % sp)
		cs._show_prompt()
		await _shot("5_contact_%s_prompt" % sp)
		cs._on_choose(0)
		await _shot("5_contact_%s_reply" % sp)

	for pid in ["kaelora", "nerea", "tessarine"]:
		var planet: Dictionary = camp.sector.nodes[camp.sector.final_id]["planet"] if pid == "tessarine" else _planet_of(camp, pid)
		var ms := MapScreen.new()
		GameState.begin_planet()
		ms.planet = planet
		main._swap(ms)
		await _shot("6_%s_briefing" % pid)
		ms._overlay.close()
		var ex := ms.expedition
		var target: Dictionary = ex.map.pois[0]
		for c in ex.map.find_path(ex.player, target["cell"]):
			var res := ex.move(c)
			ms._refresh_hud()
			if not res["poi"].is_empty():
				break
		await _shot("6_%s_map" % pid)
		if pid == "nerea":
			ms._open_event(ex.map.poi_at(ex.player))
			await _shot("7_event")

	var an := AnomalyScreen.new()
	an.event_id = "campo_de_asteroides"
	main._swap(an)
	await _shot("8_anomaly")
	main._end("victory")
	await _shot("9_end")
	Sound.set_muted(true, false)
	main.queue_free()
	await get_tree().process_frame
	# Deja al mezclador liberar las reproducciones antes de cerrar el driver Dummy.
	await get_tree().create_timer(0.2).timeout
	get_tree().quit()


func _planet_of(camp: Campaign, pid: String) -> Dictionary:
	for id in camp.sector.nodes:
		if camp.sector.nodes[id]["ref"] == pid and camp.sector.nodes[id]["type"] == "planet":
			return camp.sector.nodes[id]["planet"]
	return {}


func _shot(shot_name: String) -> void:
	await get_tree().create_timer(0.45).timeout
	get_tree().call_group("typewriter", "finish_typing")
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, shot_name])
