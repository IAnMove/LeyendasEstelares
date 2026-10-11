class_name T
extends RefCounted
## Traducción de todos los textos del juego (sistema estándar de Godot).
##
## Los textos viven en res://translations/strings.csv (columnas: keys, en, es, ...). Para añadir un idioma
## basta añadir una columna con su código y su entrada en LANGUAGES. En los textos, los parámetros se escriben
## como {nombre} y se rellenan con T.t("clave", {"nombre": valor}).

const LANGUAGES := {"en": "English", "es": "Español"}
const CSV_PATH := "res://translations/strings.csv"
const SETTINGS_PATH := "user://settings.cfg"

static var _loaded := false


static func t(key: String, args: Dictionary = {}) -> String:
	ensure_loaded()
	var s := String(TranslationServer.translate(key))
	return s.format(args) if not args.is_empty() else s


## Texto de un evento por convención: event.<id>.<sufijo>
static func ev(event_id: String, suffix: String, args: Dictionary = {}) -> String:
	return t("event.%s.%s" % [event_id, suffix], args)


## Texto que se traduce al mostrarlo, no al crearlo: lo que se guarda es la clave y sus parámetros,
## así una partida reanudada en otro idioma no mezcla idiomas. Un parámetro puede ser otro `later`.
static func later(key: String, args: Dictionary = {}) -> Dictionary:
	return {"key": key, "args": args}


## Traduce un `later`; los textos ya traducidos (guardados antiguos) se devuelven tal cual.
static func show(text) -> String:
	if not text is Dictionary:
		return str(text)
	var args := {}
	for name in text.get("args", {}):
		var value = text["args"][name]
		args[name] = show(value) if value is Dictionary else value
	return t(str(text.get("key", "")), args)


static func join(texts: Array, separator := "  ·  ") -> String:
	var out: Array[String] = []
	for text in texts:
		out.append(show(text))
	return separator.join(out)


## Registra las traducciones desde el CSV si el editor aún no las ha importado (ejecución directa sin importar).
static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if TranslationServer.get_translation_object("en") != null and TranslationServer.get_translation_object("es") != null:
		return
	var f := FileAccess.open(CSV_PATH, FileAccess.READ)
	if f == null:
		push_error("No se encuentra %s" % CSV_PATH)
		return
	var header := f.get_csv_line()
	var by_col := {}
	for i in range(1, header.size()):
		var tl := Translation.new()
		tl.locale = header[i]
		by_col[i] = tl
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < 2 or row[0] == "":
			continue
		for i in range(1, mini(row.size(), header.size())):
			if row[i] != "":
				by_col[i].add_message(row[0], row[i].c_unescape())
	for tl in by_col.values():
		TranslationServer.add_translation(tl)


static func language() -> String:
	return TranslationServer.get_locale().substr(0, 2)


static func set_language(lang: String, save := true) -> void:
	ensure_loaded()
	if not LANGUAGES.has(lang):
		lang = "en"
	TranslationServer.set_locale(lang)
	if save:
		var cfg := ConfigFile.new()
		cfg.load(SETTINGS_PATH)
		cfg.set_value("game", "language", lang)
		cfg.save(SETTINGS_PATH)


## Idioma guardado, o el del sistema (español si el sistema está en español, inglés en otro caso).
static func load_language() -> void:
	var cfg := ConfigFile.new()
	var lang := ""
	if cfg.load(SETTINGS_PATH) == OK:
		lang = str(cfg.get_value("game", "language", ""))
	if not LANGUAGES.has(lang):
		lang = "es" if OS.get_locale_language() == "es" else "en"
	set_language(lang, false)
