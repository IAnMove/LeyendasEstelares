class_name ItemIcon
extends Control
## Pictogramas vectoriales propios: se dibujan a cualquier escala, sin texturas externas.

var item_id := ""


func _init(id: String = "") -> void:
	item_id = id
	custom_minimum_size = Vector2(28, 28)
	mouse_filter = MOUSE_FILTER_IGNORE
	size_flags_vertical = SIZE_SHRINK_CENTER


func _draw() -> void:
	var ink := UITheme.ACCENT
	draw_rect(Rect2(0, 0, 28, 28), UITheme.BG)
	match item_id:
		"oxygen_cell":
			draw_rect(Rect2(9, 7, 10, 16), ink, false, 1.5)
			draw_rect(Rect2(11, 4, 6, 3), ink)
			draw_line(Vector2(11, 14), Vector2(17, 14), ink, 1.5)
			draw_line(Vector2(14, 11), Vector2(14, 17), ink, 1.5)
		"rations":
			draw_rect(Rect2(6, 7, 16, 15), ink, false, 1.5)
			draw_line(Vector2(6, 11), Vector2(22, 11), ink, 1.5)
			draw_line(Vector2(10, 15), Vector2(18, 15), ink, 1.5)
			draw_line(Vector2(10, 18), Vector2(16, 18), ink, 1.5)
		"fuel_cell":
			draw_rect(Rect2(7, 8, 14, 15), UITheme.WARN, false, 1.5)
			draw_rect(Rect2(10, 4, 8, 4), UITheme.WARN, false, 1.5)
			draw_polyline(PackedVector2Array([Vector2(16, 11), Vector2(12, 16), Vector2(16, 16), Vector2(12, 21)]), UITheme.WARN, 1.5, true)
		"scan_probe":
			draw_circle(Vector2(14, 14), 2, ink)
			for radius in [6.0, 10.0]:
				draw_arc(Vector2(14, 14), radius, -2.3, 0.6, 18, ink, 1.5, true)
			draw_line(Vector2(14, 14), Vector2(8, 22), ink, 1.5)
		"survey_kit":
			draw_rect(Rect2(5, 10, 18, 13), ink, false, 1.5)
			draw_rect(Rect2(10, 5, 8, 5), ink, false, 1.5)
			draw_line(Vector2(5, 15), Vector2(23, 15), ink, 1.5)
			draw_rect(Rect2(12, 13, 4, 5), ink)
		"translator":
			draw_rect(Rect2(5, 5, 18, 15), ink, false, 1.5)
			draw_polyline(PackedVector2Array([Vector2(9, 20), Vector2(9, 24), Vector2(14, 20)]), ink, 1.5, true)
			for x in [10, 14, 18]:
				draw_circle(Vector2(x, 12), 1, ink)
