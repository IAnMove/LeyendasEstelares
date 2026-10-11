class_name SafeLayout
extends RefCounted

const DESIGN := Vector2(640, 360)

static func fit(viewport_rect: Rect2, safe_pixels: Rect2, screen_transform: Transform2D) -> Rect2:
	var available := viewport_rect
	if safe_pixels.has_area():
		available = available.intersection(screen_transform.affine_inverse() * safe_pixels)
	if not available.has_area():
		available = viewport_rect
	var factor := minf(available.size.x / DESIGN.x, available.size.y / DESIGN.y)
	var fitted := DESIGN * factor
	return Rect2(available.position + (available.size - fitted) * 0.5, fitted)
