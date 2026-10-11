extends Node
## Revisa el layout de todas las pantallas, eventos y conversaciones en ambos idiomas: detecta texto
## partido letra a letra (columna estrecha y alta) y controles que se salen de la pantalla.
## godot --headless --path . res://tests/layout_test.tscn            (escritorio)
## godot --headless --path . res://tests/layout_test.tscn -- --touch-ui  (botones táctiles)
## Adaptada de la prueba de la rama archive/pixel-art-ui.

const FLAGS := ["met_vael", "met_hallen", "met_draeth", "vael_contacto", "mapa_vael", "gremio_amigo", "draeth_respeto", "tono_grave", "tono_medio", "tono_agudo",
	# Antecedentes que activan todos los recuerdos de los contactos y las opciones de las cadenas (textos más largos).
	"jardin_cosechado", "torre_reparada", "archivo_preservado", "deuda_gremio", "convoy_guiado", "convoy_autonomo", "gremio_reparacion", "pista_refugio"]

var _failures := 0
var _checked := 0
var _size := Vector2i(SafeLayout.DESIGN)


func _ready() -> void:
	for lang in T.LANGUAGES:
		T.set_language(lang, false)
		await _audit_all("[%s%s]" % [lang, " táctil" if UITheme.touch_mode() else ""])
	T.load_language()
	print("\n%s (%d controles revisados, %d fallos)" % ["LAYOUT OK" if _failures == 0 else "FALLOS", _checked, _failures])
	Sound.set_muted(true, false)
	await get_tree().process_frame
	get_tree().quit(0 if _failures == 0 else 1)


## Monta un nodo dentro de un SubViewport del tamaño de diseño y devuelve el viewport.
func _stage(screen: Node) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = _size
	vp.disable_3d = true
	add_child(vp)
	var root := Control.new()
	root.theme = UITheme.build()
	root.size = Vector2(_size)
	vp.add_child(root)
	root.add_child(screen)
	return vp


func _settle() -> void:
	for i in 3:
		await get_tree().process_frame


func _show(screen: Control, label: String, setup := Callable()) -> void:
	var vp := _stage(screen)
	await _settle()
	if setup.is_valid():
		setup.call()
		await _settle()
	_audit(screen, label)
	vp.queue_free()
	await get_tree().process_frame


func _new_run(avatar: String) -> void:
	GameState.start_run(Content.avatar_by_id(avatar), Content.factions, Content.campaign)
	GameState.apply_effects({"set_flags": FLAGS, "data": 6, "rep": {"vael": 2, "concordato": 2}})


func _audit_all(tag: String) -> void:
	_new_run("vance")
	var title := TitleScreen.new()
	title.has_save = true
	await _show(title, tag + " título")
	await _show(AvatarScreen.new(), tag + " avatares")
	var camp := Campaign.new(GameState, Content.campaign, 12)
	for id in camp.sector.nodes:
		camp.sector.nodes[id]["scanned"] = true
	var sec := SectorScreen.new()
	sec.campaign = camp
	await _show(sec, tag + " mapa estelar", func(): sec._select(camp.sector.nodes[camp.current]["edges"][0]))
	sec = SectorScreen.new()
	sec.campaign = camp
	await _show(sec, tag + " bodega", sec._open_ship)

	for sp in Content.campaign["species"]:
		for avatar in ["vance", "okafor"]:
			_new_run(avatar)
			var cs := ContactScreen.new()
			cs.species_id = sp
			var vp := _stage(cs)
			await _settle()
			cs.finish_typing()
			_audit(cs, "%s contacto %s/%s intro" % [tag, sp, avatar])
			var guard := 0
			while not cs.runner.finished() and guard < 10:
				guard += 1
				cs._show_prompt()
				cs.finish_typing()
				await _settle()
				_audit(cs, "%s contacto %s/%s intercambio %d" % [tag, sp, avatar, cs.runner.index])
				var pick := 0
				for i in cs.runner.exchange()["options"].size():
					if cs.runner.lock_reason(i) == "":
						pick = i
				cs._on_choose(pick)
				cs.finish_typing()
				await _settle()
				_audit(cs, "%s contacto %s/%s respuesta %d" % [tag, sp, avatar, cs.runner.index])
			cs._show_outcome()
			cs.finish_typing()
			await _settle()
			_audit(cs, "%s contacto %s/%s desenlace" % [tag, sp, avatar])
			cs._open_trade()
			await _settle()
			_audit(cs, "%s comercio %s/%s" % [tag, sp, avatar])
			vp.queue_free()
			await get_tree().process_frame

	_new_run("vance")
	for planet in Content.planets:
		var ms := MapScreen.new()
		ms.planet = planet
		await _show(ms, "%s planeta %s briefing" % [tag, planet["id"]])
		ms = MapScreen.new()
		ms.planet = planet
		await _show(ms, "%s planeta %s superficie" % [tag, planet["id"]], func(): ms._overlay.close())

	# Todos los eventos: presentación con y sin opciones bloqueadas, y resultado con varias líneas.
	var holder := MapScreen.new()
	holder.planet = Content.planets[0]
	var stage := _stage(holder)
	await _settle()
	for id in Content.events:
		for flagged in [false, true]:
			GameState.flags = {}
			if flagged:
				for f in FLAGS:
					GameState.flags[f] = true
			GameState.data = 6
			holder._overlay.present_event(id, func(_i): return {}, func(): pass)
			await _settle()
			_audit(holder, "%s evento %s (flags=%s)" % [tag, id, flagged])
		var suffix := "ok" if Content.events[id]["choices"][0].has("risk") else "res"
		var lines := [T.later("fx.oxygen", {"delta": "−3"}), T.later("fx.rep", {"faction": T.later("faction.concordato"), "delta": "+1"}), T.later("fx.data", {"delta": "+2"})]
		holder._overlay.show_result(id, 0, {"text": T.later("event.%s.c0.%s" % [id, suffix]), "lines": lines, "success": true, "voice": GameState.voice("torre_reparada")}, func(): pass)
		await _settle()
		_audit(holder, "%s resultado de %s" % [tag, id])
	stage.queue_free()
	await get_tree().process_frame

	# Finales, y cada variante de victoria según la salida de la baliza ("" = registro parcial).
	for ending in ["victory", "abort", "fuel", "oxygen", "morale"]:
		for beacon in (EndScreen.VICTORY_TIERS.keys() + [""] if ending == "victory" else [""]):
			_new_run("vance")
			GameState.apply_effects({"rep": {"concordato": 2, "vael": -1}, "set_flags": Content.campaign["thread"]["clues"]})
			GameState.relations = {"vael": "alliance", "hallen": "hostile", "draeth": "deal"}
			if beacon != "":
				GameState.flags[beacon] = true
			var end := EndScreen.new()
			end.ending = ending
			end.jumps = 7
			await _show(end, "%s final %s %s" % [tag, ending, beacon])

	# Guía (F1 / botón ?), dentro de la raíz real del juego.
	var main: Control = load("res://scenes/main.tscn").instantiate()
	main.save_path = ""
	var vp := _stage(main)
	await _settle()
	main._open_help()
	await _settle()
	_audit(main._pause_menu, tag + " guía")
	main._close_pause()
	main._show_prologue()
	await _settle()
	_audit(main, tag + " orden de misión")
	vp.queue_free()
	await get_tree().process_frame


func _audit(root: Node, label: String) -> void:
	var bounds := Rect2(Vector2.ZERO, Vector2(_size))
	for n in root.find_children("*", "Control", true, false):
		var c := n as Control
		if not c.is_visible_in_tree():
			continue
		_checked += 1
		if c is Label:
			var l := c as Label
			if l.autowrap_mode != TextServer.AUTOWRAP_OFF and l.text.length() > 8 and l.get_line_count() > maxi(2, l.text.length() / 7):
				_fail("%s: texto en vertical (%d líneas, ancho %d): '%s'" % [label, l.get_line_count(), int(l.size.x), l.text.left(40)])
		if (c is Label or c is Button or c is PanelContainer) and not _inside_scroll(c):
			var r := c.get_global_rect()
			if r.end.x > bounds.end.x + 1.0 or r.end.y > bounds.end.y + 1.0 or r.position.x < -1.0 or r.position.y < -1.0:
				var text: String = str(c.get("text")).left(30) if (c is Label or c is Button) else ""
				_fail("%s: %s se sale de la pantalla %s '%s'" % [label, c.get_class(), r, text])


func _inside_scroll(c: Node) -> bool:
	var p := c.get_parent()
	while p != null:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false


func _fail(msg: String) -> void:
	_failures += 1
	if _failures <= 60:
		print("  FALLO: ", msg)
