class_name PlanetMapView
extends Node2D
## Dibuja el mapa hexagonal de una Expedition y emite los clics sobre casillas.

signal cell_clicked(cell: Vector2i)

var expedition: Expedition
var enabled := true
var return_route: Array[Vector2i] = []
var return_at_risk := false
var _hover := Vector2i(-1, -1)
var _time := 0.0

const KEY_DIRS: Array[int] = [KEY_D, KEY_E, KEY_Q, KEY_A, KEY_Z, KEY_C]
const _HEX_OFFSET := Vector2(HexGrid.W / 2.0, HexGrid.H / 2.0)


func size_px() -> Vector2:
	return Vector2(PlanetData.COLS * HexGrid.W + HexGrid.W / 2.0, (PlanetData.ROWS - 1) * HexGrid.ROW_H + HexGrid.H)


func cell_at(local: Vector2) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 19.0
	for c in expedition.map.terrain:
		var d := local.distance_to(HexGrid.center(c))
		if d < best_d:
			best_d = d
			best = c
	return best


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


func _process(delta: float) -> void:
	_time += delta
	var c := cell_at(get_local_mouse_position()) if enabled and expedition != null else Vector2i(-1, -1)
	if c != _hover:
		_hover = c
	queue_redraw()  # animaciones suaves (respiración del astronauta, pulso de los puntos de interés)


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or expedition == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local := make_input_local(event) as InputEventMouseButton
		var c := cell_at(local.position)
		if c != Vector2i(-1, -1):
			cell_clicked.emit(c)
	elif event is InputEventKey and event.pressed and not event.echo:
		# Teclas alrededor de la S: D=E, E=NE, Q=NO, A=O, Z=SO, C=SE (mismo orden que HexGrid.neighbors).
		var idx: int = KEY_DIRS.find(event.keycode)
		if idx >= 0:
			cell_clicked.emit(HexGrid.neighbors(expedition.player)[idx])
			get_viewport().set_input_as_handled()


func _draw() -> void:
	if expedition == null:
		return
	var map := expedition.map
	var biome: String = expedition.planet.get("biome", "frost")
	for c in map.terrain:
		var tile: String = "tile_fog" if not map.revealed.has(c) else "tile_%s_%s" % [biome, map.terrain[c]]
		draw_texture_rect(Cartography.tex(tile), Rect2(HexGrid.center(c) - _HEX_OFFSET, Vector2(HexGrid.W, HexGrid.H)), false)

	var previous := HexGrid.center(expedition.player)
	for cell in return_route:
		var next := HexGrid.center(cell)
		draw_line(previous, next, Color(0.07, 0.17, 0.2, 0.7), 3.0, true)
		draw_dashed_line(previous, next, UITheme.BAD if return_at_risk else UITheme.PAPER, 1.2, 3.0, true)
		previous = next

	for p in map.pois:
		if map.revealed.has(p["cell"]):
			var pulse := 0.85 + 0.15 * sin(_time * 3.0 + p["cell"].x)
			var tint := Color(1, 1, 1, 0.35) if p["resolved"] else Color(pulse, pulse, pulse, 1)
			var bob := 0.0 if p["resolved"] else roundf(sin(_time * 2.0 + p["cell"].y) * 1.0)
			draw_texture_rect(Cartography.tex("poi_" + p["type"]), Rect2(HexGrid.center(p["cell"]) - Vector2(8, 12 - bob), Vector2(16, 24)), false, tint)
	draw_texture_rect(Cartography.tex("ship"), Rect2(HexGrid.center(map.ship_cell) - Vector2(8, 12), Vector2(16, 24)), false)

	var font := UITheme.MONO_FONT
	var reach_alpha := 0.65 + 0.35 * sin(_time * 4.0)
	for n in HexGrid.neighbors(expedition.player):
		if expedition.can_move(n):
			var pos := HexGrid.center(n)
			draw_texture_rect(Cartography.tex("hl_reach"), Rect2(pos - _HEX_OFFSET, Vector2(HexGrid.W, HexGrid.H)), false, Color(1, 1, 1, reach_alpha))
			if not map.poi_at(n).is_empty() and map.revealed.has(n):
				continue
			var badge := pos + Vector2(8, 9)
			draw_circle(badge, 6.5, UITheme.INK)
			draw_string(font, badge + Vector2(-3, 3.5), str(map.move_cost(n)), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UITheme.WARN)
	if enabled and _hover != Vector2i(-1, -1):
		draw_texture_rect(Cartography.tex("hl_hover"), Rect2(HexGrid.center(_hover) - _HEX_OFFSET, Vector2(HexGrid.W, HexGrid.H)), false)

	var breathe := roundf(sin(_time * 2.4) * 0.6)
	var avatar_tex := Cartography.tex(GameState.avatar.get("sprite", "avatar_vance"))
	draw_texture_rect(avatar_tex, Rect2(HexGrid.center(expedition.player) - Vector2(8, 13 - breathe), Vector2(16, 24)), false)
