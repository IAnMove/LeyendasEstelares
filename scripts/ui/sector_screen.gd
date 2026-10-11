class_name SectorScreen
extends Control
## Mapa estelar tipo FTL: elige a dónde saltar, escanea para reducir la incertidumbre y gestiona el combustible.

signal jumped(node_id: String)

const MAP_X0 := 44.0
const MAP_X1 := 596.0
const MAP_Y0 := 74.0
const MAP_H := 178.0
const NODE_SIZE := Vector2(34, 34)

var campaign: Campaign

var _buttons := {}  # id -> Button
var _selected := ""
var _lines: _Lines
var _ship: TextureRect
var _hud: Label
var _info_title: Label
var _info_body: Label
var _jump_btn: Button
var _scan_btn: Button
var _time := 0.0


class _Lines extends Control:
	var screen: SectorScreen

	func _draw() -> void:
		var c := screen.campaign
		for id in c.sector.nodes:
			var a: Dictionary = c.sector.nodes[id]
			for to in a["edges"]:
				var reachable: bool = id == c.current and c.can_jump(to)
				var col := UITheme.WARN if reachable else Color(0.35, 0.55, 0.58, 0.45)
				var a_pos := screen.node_pos(id)
				var b_pos := screen.node_pos(to)
				if reachable:
					draw_line(a_pos, b_pos, col, 2.0, true)
				else:
					draw_dashed_line(a_pos, b_pos, col, 1.0, 5.0, true)
				var cost: int = a["costs"][to]
				if cost > 1:
					var mid := (a_pos + b_pos) * 0.5
					draw_circle(mid, 7.0, Color(0.06, 0.08, 0.14, 0.95))
					draw_string(ThemeDB.fallback_font, mid + Vector2(-4, 4), str(cost), HORIZONTAL_ALIGNMENT_CENTER, 8, 11, col)


class _Stars extends Control:
	var _pts: Array = []

	func _init() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 77
		for i in 90:
			_pts.append([rng.randf() * 640.0, rng.randf() * 360.0, rng.randi_range(1, 3), rng.randf() * 6.28])

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var t := Time.get_ticks_msec() / 1000.0
		for p in _pts:
			var layer: int = p[2]
			var x := fposmod(p[0] - t * 2.5 * layer, 640.0)
			var a := 0.35 + 0.25 * layer / 3.0 + 0.15 * sin(t * 1.5 + p[3])
			draw_rect(Rect2(floorf(x), floorf(p[1]), 1 if layer < 3 else 2, 1 if layer < 3 else 2), Color(0.8, 0.88, 1.0, a))


func node_pos(id: String) -> Vector2:
	var n: Dictionary = campaign.sector.nodes[id]
	var cols: int = campaign.sector.columns.size()
	if UITheme.touch_mode():
		var column: Array = campaign.sector.columns[n["col"]]
		var y := 174.0 if column.size() == 1 else lerpf(104, 244, float(column.find(id)) / (column.size() - 1))
		return Vector2(lerpf(MAP_X0, MAP_X1, float(n["col"]) / (cols - 1)), y)
	return Vector2(lerpf(MAP_X0, MAP_X1, float(n["col"]) / (cols - 1)), MAP_Y0 + float(n["y"]) * MAP_H)


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(UITheme.background())
	var stars := _Stars.new()
	stars.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stars)
	_lines = _Lines.new()
	_lines.screen = self
	_lines.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lines)

	for id in campaign.sector.nodes:
		var b := Button.new()
		var target_size := Vector2(48, 48) if UITheme.touch_mode() else NODE_SIZE
		b.custom_minimum_size = target_size
		b.size = target_size
		b.position = node_pos(id) - target_size / 2.0
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.expand_icon = false
		b.focus_mode = Control.FOCUS_ALL
		b.pressed.connect(_select.bind(id))
		b.focus_entered.connect(_select.bind(id))
		add_child(b)
		_buttons[id] = b

	_ship = TextureRect.new()
	_ship.texture = Art.tex("sector_ship")
	_ship.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ship.size = Vector2(16, 16)
	add_child(_ship)

	_build_hud()
	_build_info()
	GameState.changed.connect(_refresh)
	_select(campaign.current)
	_refresh()
	# Foco inicial en un nodo alcanzable para poder jugar solo con teclado.
	for to in campaign.sector.nodes[campaign.current]["edges"]:
		if campaign.can_jump(to):
			_buttons[to].grab_focus()
			break


func _process(delta: float) -> void:
	_time += delta
	var base := node_pos(campaign.current) + Vector2(-8, -34)
	_ship.position = base + Vector2(0, roundf(sin(_time * 2.2) * 1.5))


func _build_hud() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(8, 6)
	panel.size = Vector2(624, 42)
	add_child(panel)
	var row := HBoxContainer.new()
	panel.add_child(row)
	_hud = UITheme.label("", UITheme.TEXT, 11)
	_hud.autowrap_mode = TextServer.AUTOWRAP_OFF
	_hud.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(_hud)
	var ship := UITheme.button(T.t("ui.ship.open"))
	ship.autowrap_mode = TextServer.AUTOWRAP_OFF
	ship.add_theme_font_size_override("font_size", 11)
	ship.pressed.connect(_open_ship)
	row.add_child(ship)
	row.add_child(UITheme.pause_button())


func _open_ship() -> void:
	var screen := ShipScreen.new()
	screen.closed.connect(func():
		screen.queue_free()
		_refresh())
	add_child(screen)


func _build_info() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(8, 274)
	panel.size = Vector2(624, 78)
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)
	_info_title = UITheme.label("", UITheme.ACCENT, 13)
	col.add_child(_info_title)
	_info_body = UITheme.label("", UITheme.DIM, 11)
	col.add_child(_info_body)
	var btns: BoxContainer = HBoxContainer.new() if UITheme.touch_mode() else VBoxContainer.new()
	btns.add_theme_constant_override("separation", 3)
	row.add_child(btns)
	_jump_btn = UITheme.button("")
	UITheme.primary(_jump_btn)
	_jump_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_jump_btn.custom_minimum_size = Vector2(112 if UITheme.touch_mode() else 170, 0)
	_jump_btn.pressed.connect(_on_jump)
	btns.add_child(_jump_btn)
	_scan_btn = UITheme.button("")
	_scan_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scan_btn.custom_minimum_size = Vector2(112 if UITheme.touch_mode() else 170, 0)
	_scan_btn.pressed.connect(_on_scan)
	btns.add_child(_scan_btn)


func _refresh() -> void:
	_hud.text = "%s     %s     %s     %s" % [
		T.t("ui.hud.fuel", {"cur": GameState.fuel, "max": GameState.max_fuel}),
		T.t("ui.hud.scans", {"n": GameState.scans}),
		T.t("ui.hud.data", {"n": GameState.data}),
		T.t("ui.hud.morale", {"cur": GameState.morale, "max": GameState.max_morale}),
	]
	for id in _buttons:
		_style_node(id)
	_lines.queue_redraw()
	_update_info()


func _icon_for(id: String) -> String:
	var n: Dictionary = campaign.node(id)
	if n["type"] == "start":
		return "node_start"
	if n["final"]:
		return "node_final"
	if not n["scanned"]:
		return "node_unknown"
	return "node_" + n["type"]


func _style_node(id: String) -> void:
	var b: Button = _buttons[id]
	var n: Dictionary = campaign.node(id)
	b.icon = Art.tex(_icon_for(id))
	var border := UITheme.PANEL_BORDER
	if id == campaign.current:
		border = UITheme.ACCENT
	elif campaign.node(campaign.current)["edges"].has(id) and not n["done"]:
		border = UITheme.WARN
	elif n["done"]:
		border = UITheme.PANEL_BORDER
	if id == _selected:
		border = Color.WHITE
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := UITheme.box(UITheme.PANEL if state != "hover" else Color("315761"), border, 4, 2 if id == _selected else 1)
		sb.set_corner_radius_all(17)
		b.add_theme_stylebox_override(state, sb)
	b.self_modulate = Color(1, 1, 1, 0.45 if n["done"] and id != campaign.current else 1.0)


func _select(id: String) -> void:
	_selected = id
	for other in _buttons:
		_style_node(other)
	_update_info()


func _update_info() -> void:
	if _selected == "":
		_info_title.text = T.t("ui.sector.select")
		return
	var n: Dictionary = campaign.node(_selected)
	var here := _selected == campaign.current
	_info_title.text = _title_for(n)
	var body := ""
	if here:
		body = T.t("ui.sector.here")
	elif n["done"]:
		body = T.t("ui.sector.visited")
	elif not campaign.node(campaign.current)["edges"].has(_selected):
		body = T.t("ui.sector.unreachable")
	elif GameState.fuel < campaign.edge_cost(campaign.current, _selected):
		body = T.t("ui.sector.no_fuel")
	if not n["scanned"]:
		body = (body + "  " if body != "" else "") + T.t("ui.sector.unknown_body")
	elif n["type"] == "planet":
		var tags: Array[String] = []
		for tag in campaign.sector.scan_tags(_selected):
			tags.append(T.t("ui.scan.tag." + tag))
		if not tags.is_empty():
			body = (body + "  " if body != "" else "") + T.t("ui.sector.tags", {"list": ", ".join(tags)})
	_info_body.text = body
	var cost := campaign.edge_cost(campaign.current, _selected) if campaign.node(campaign.current)["edges"].has(_selected) else 1
	_jump_btn.text = T.t("ui.sector.jump", {"n": cost})
	_jump_btn.disabled = not campaign.can_jump(_selected)
	_scan_btn.text = T.t("ui.sector.scan", {"n": GameState.scans})
	_scan_btn.disabled = not campaign.can_scan(_selected)


func _title_for(n: Dictionary) -> String:
	if n["type"] == "start":
		return T.t("ui.sector.type.start")
	if not n["scanned"]:
		return T.t("ui.sector.unknown_title")
	match n["type"]:
		"planet":
			var name := T.t("planet.%s.name" % n["ref"])
			return T.t("ui.sector.type.final" if n["final"] else "ui.sector.type.planet", {"name": name})
		"contact":
			return T.t("ui.sector.type.contact", {"species": T.t("species.%s.name" % n["ref"])})
	return T.t("ui.sector.type.anomaly")


func _on_jump() -> void:
	if campaign.can_jump(_selected):
		var id := _selected
		campaign.jump(id)
		Sound.play("jump")
		jumped.emit(id)


func _on_scan() -> void:
	if campaign.can_scan(_selected):
		campaign.scan(_selected)
		Sound.play("scan")
		_refresh()
