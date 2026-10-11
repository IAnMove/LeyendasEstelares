class_name Cartography
extends RefCounted
## Símbolos y terrenos vectoriales, compatibles con el lenguaje de tinta y papel de la UI.
static var _cache := {}

static func tex(id: String) -> Texture2D:
	if not _cache.has(id):
		_cache[id] = load("res://art/cartography/%s.svg" % id)
	return _cache[id]
