extends Node
## Observador de solo lectura para el APK QA. El controlador usa eventos táctiles ADB.
## Este archivo y su escena se excluyen de los APK/AAB de distribución.

var main
var elapsed := 0.0
var samples: Array[float] = []
var pauses := 0
var resumes := 0

func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	T.set_language("en", false)
	main._show_title()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		pauses += 1
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		resumes += 1

func _process(delta: float) -> void:
	elapsed += delta
	samples.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	if samples.size() > 300:
		samples.pop_front()
	if elapsed < 0.5 or not is_instance_valid(main._current):
		return
	elapsed = 0
	var current: Control = main._current
	var active: Node = main._pause_menu if is_instance_valid(main._pause_menu) else _interactive(current)
	var report := {
		"tick": Time.get_ticks_msec(), "stage": current.get_script().get_global_name(),
		"active": active.get_script().get_global_name() if active.get_script() != null else active.get_class(),
		"paused": is_instance_valid(main._pause_menu), "audio_suspended": Sound.suspended,
		"pauses": pauses, "resumes": resumes, "state": GameState.snapshot(), "buttons": [],
		"scrolls": [], "fps": Engine.get_frames_per_second(),
		"process_ms_average": _mean(samples), "memory_static_bytes": Performance.get_monitor(Performance.MEMORY_STATIC),
		"screen": DisplayServer.screen_get_size(), "safe_area": DisplayServer.get_display_safe_area(),
		"game_rect": _physical_rect(main._safe_content.get_global_rect()),
	}
	for node in active.find_children("*", "Button", true, false):
		var button: Button = node
		if not button.is_visible_in_tree():
			continue
		var rect := button.get_global_rect()
		var clip := _clip(button)
		var context := ""
		for sibling in button.get_parent().get_children():
			if sibling is Label:
				context += sibling.text + " "
		report["buttons"].append({"text": button.text, "path": str(button.get_path()), "disabled": button.disabled,
			"rect": _physical_rect(rect), "visible": clip.grow(0.2).encloses(rect), "context": context})
	for node in active.find_children("*", "ScrollContainer", true, false):
		if node.is_visible_in_tree():
			report["scrolls"].append(_physical_rect(node.get_global_rect()))
	if main._campaign != null:
		report["campaign"] = main._campaign.snapshot()
	if current is SectorScreen:
		report["selected"] = current._selected
		report["nodes"] = []
		for id in current.campaign.node(current.campaign.current)["edges"]:
			if current.campaign.can_jump(id):
				var node: Dictionary = current.campaign.node(id)
				report["nodes"].append({"id": id, "type": node["type"], "cost": current.campaign.edge_cost(current.campaign.current, id),
					"rect": _physical_rect(current._buttons[id].get_global_rect())})
	if current is MapScreen:
		report["phase"] = current._phase
		report["player"] = [current.expedition.player.x, current.expedition.player.y]
		if current._phase == "explore":
			var ex: Expedition = current.expedition
			var target: Vector2i = ex.map.ship_cell if ex.objective_done else ex.map.beacon_cell
			var route: Array[Vector2i] = ex.map.find_path(ex.player, target)
			if not route.is_empty():
				var local := HexGrid.center(route[0])
				var point: Vector2 = get_viewport().get_screen_transform() * current._view.to_global(local)
				report["suggested_hex"] = [point.x, point.y]
	elif current is ContactScreen and current._phase == "prompt":
		var best := -1
		var best_score := -999
		for i in current.runner.exchange()["options"].size():
			if current.runner.lock_reason(i) != "":
				continue
			var forecast: Dictionary = current.runner.preview(i)
			var score: int = forecast["trust"] - forecast["tension"]
			if score > best_score:
				best_score = score
				best = i
		if best >= 0:
			report["suggested_button"] = str(current._options.get_child(best).get_path())
	elif current is EndScreen:
		report["ending"] = current.ending
	if FileAccess.file_exists(main.save_path):
		report["save_hash"] = FileAccess.get_sha256(main.save_path)
	var file := FileAccess.open("user://qa-observation.tmp", FileAccess.WRITE)
	file.store_string(JSON.stringify(report))
	file.close()
	DirAccess.rename_absolute("user://qa-observation.tmp", "user://qa-observation.json")

func _interactive(node: Node) -> Node:
	var children := node.get_children()
	children.reverse()
	for child in children:
		if child is Control and child.is_visible_in_tree() and not child.is_queued_for_deletion():
			if child is Overlay or child is ShipScreen or child is TradeScreen:
				return _interactive(child)
	return node

func _physical_rect(rect: Rect2) -> Array:
	var physical := get_viewport().get_screen_transform() * rect
	return [physical.position.x, physical.position.y, physical.size.x, physical.size.y]

func _clip(control: Control) -> Rect2:
	var rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var node: Node = control.get_parent()
	while node != null:
		if node is Control and node.clip_contents:
			rect = rect.intersection(node.get_global_rect())
		node = node.get_parent()
	return rect

func _mean(values: Array[float]) -> float:
	var total := 0.0
	for value in values:
		total += value
	return total / max(1, values.size())
