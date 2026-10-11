class_name SaveStore
extends RefCounted
## Guardado local versionado. Variants sin objetos preservan hexágonos y RNG de 64 bits.
## Escribe primero un temporal verificado; conserva el último guardado íntegro como respaldo.

const PATH := "user://expedition.save"
const VERSION := 1
const MAX_BYTES := 8 * 1024 * 1024


static func write(snapshot: Dictionary, path := PATH) -> Error:
	if not valid(snapshot):
		return ERR_INVALID_DATA
	var payload := var_to_bytes(snapshot)
	var envelope := var_to_bytes({"version": VERSION, "sha256": payload.hex_encode().sha256_text(), "payload": payload})
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(envelope)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or _read(path + ".tmp").is_empty():
		return ERR_FILE_CANT_WRITE
	if not _read(path).is_empty():
		if FileAccess.file_exists(path + ".bak"):
			DirAccess.remove_absolute(path + ".bak")
		error = DirAccess.rename_absolute(path, path + ".bak")
		if error != OK:
			return error
	return DirAccess.rename_absolute(path + ".tmp", path)


static func read(path := PATH) -> Dictionary:
	var saved := _read(path)
	if saved.is_empty():
		saved = _read(path + ".bak")
	return saved


static func clear(path := PATH) -> void:
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)


static func _read(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES or file.get_length() < 16:
		return {}
	var envelope = bytes_to_var(file.get_buffer(file.get_length()))
	if not envelope is Dictionary or envelope.get("version") != VERSION:
		return {}
	var payload = envelope.get("payload")
	if not payload is PackedByteArray or payload.hex_encode().sha256_text() != envelope.get("sha256"):
		return {}
	var saved = bytes_to_var(payload)
	return saved if saved is Dictionary and valid(saved) else {}


static func valid(saved: Dictionary) -> bool:
	if not saved.get("state") is Dictionary or not saved.get("campaign") is Dictionary or not saved.get("screen") is Dictionary:
		return false
	var state: Dictionary = saved["state"]
	var camp: Dictionary = saved["campaign"]
	var screen: Dictionary = saved["screen"]
	if not state.get("avatar") is Dictionary or Content.avatar_by_id(state["avatar"].get("id", "")).is_empty():
		return false
	for key in ["oxygen", "max_oxygen", "morale", "max_morale", "data", "fuel", "max_fuel", "scans", "max_scans"]:
		if not state.get(key) is int or state[key] < 0:
			return false
	for key in ["rep", "flags", "inventory", "relations", "market_stock"]:
		if not state.get(key) is Dictionary:
			return false
	if not camp.get("sector") is Dictionary or not camp.get("jumps") is int:
		return false
	var sector: Dictionary = camp["sector"]
	if not sector.get("nodes") is Dictionary or not sector.get("columns") is Array or not sector["nodes"].has(camp.get("current")):
		return false
	if not screen.get("kind") in ["sector", "planet", "contact", "anomaly"]:
		return false
	var current: Dictionary = sector["nodes"][camp["current"]]
	if screen["kind"] != "sector" and current.get("type") != screen["kind"]:
		return false
	if screen["kind"] == "planet":
		var ex = screen.get("expedition")
		if not ex is Dictionary or not ex.get("map") is Dictionary or not ex.get("player") is Vector2i:
			return false
		var map: Dictionary = ex["map"]
		if not map.get("terrain") is Dictionary or not map.get("revealed") is Dictionary or not map.get("pois") is Array:
			return false
		if not map["terrain"].has(ex["player"]):
			return false
	if screen["kind"] == "contact" and not screen.get("runner") is Dictionary:
		return false
	return true
