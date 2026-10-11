class_name Art
extends RefCounted
## Texturas cacheadas: ilustraciones en generated/ y sprites tácticos en art/.

static var _cache := {}
const PORTRAITS := ["crew_vance", "crew_okafor", "portrait_vael", "portrait_hallen", "portrait_draeth"]
const VERSIONS := ["v1_original", "v2_retro"]
static var portrait_version := "v2_retro"


static func load_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(T.SETTINGS_PATH)
	set_portrait_version(str(cfg.get_value("art", "portraits", "v2_retro")), false)


static func set_portrait_version(version: String, save := true) -> void:
	portrait_version = version if version in VERSIONS else "v2_retro"
	if save:
		var cfg := ConfigFile.new()
		cfg.load(T.SETTINGS_PATH)
		cfg.set_value("art", "portraits", portrait_version)
		cfg.save(T.SETTINGS_PATH)


static func texture_path(tex_name: String) -> String:
	if portrait_version == "v2_retro" and tex_name.begins_with("generated/") and tex_name.get_file() in PORTRAITS:
		return "res://art/generated/v2_retro/%s.png" % tex_name.get_file()
	return "res://art/%s.png" % tex_name


static func tex(tex_name: String) -> Texture2D:
	var path := texture_path(tex_name)
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]
