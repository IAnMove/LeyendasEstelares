class_name TitleScreen
extends Control

signal resume_pressed
signal start_pressed

var has_save := false
signal quit_pressed
signal language_changed

var _sound_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var bg := UITheme.illustration("generated/meridiana_title", Vector2.ZERO)
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/title_shade.gdshader")
	shade.material = material
	add_child(shade)
	var rule := ColorRect.new()
	rule.color = UITheme.WARN
	rule.position = Vector2(28, 12)
	rule.size = Vector2(584, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rule)
	var box := VBoxContainer.new()
	box.position = Vector2(28, 22)
	box.size = Vector2(278, 300)
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	box.add_child(UITheme.caption(T.t("ui.title.eyebrow"), UITheme.WARN))

	var title := UITheme.label(T.t("ui.title"), UITheme.TEXT, 36)
	title.add_theme_constant_override("line_spacing", -5)
	box.add_child(title)
	var sub := UITheme.label(T.t("ui.subtitle"), UITheme.ACCENT, 12)
	box.add_child(sub)
	box.add_child(UITheme.label(T.t("ui.title.intro"), UITheme.TEXT, 11))

	var start := UITheme.button(T.t("ui.new_expedition"))
	start.alignment = HORIZONTAL_ALIGNMENT_CENTER
	start.custom_minimum_size.y = 32
	UITheme.primary(start)
	start.pressed.connect(func(): start_pressed.emit())
	var actions := HBoxContainer.new()
	box.add_child(actions)
	start.size_flags_horizontal = SIZE_EXPAND_FILL
	actions.add_child(start)
	if has_save:
		var resume := UITheme.button(T.t("ui.save.resume"))
		resume.size_flags_horizontal = SIZE_EXPAND_FILL
		UITheme.primary(resume)
		resume.pressed.connect(func(): resume_pressed.emit())
		actions.add_child(resume)
	# Selector de idioma: un botón por idioma disponible.
	var langs := HBoxContainer.new()
	langs.alignment = BoxContainer.ALIGNMENT_CENTER
	langs.add_theme_constant_override("separation", 6)
	var language_label := UITheme.label(T.t("ui.language") + ":", UITheme.DIM, 11)
	language_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	langs.add_child(language_label)
	for code in T.LANGUAGES:
		var b := UITheme.button(T.LANGUAGES[code])
		b.autowrap_mode = TextServer.AUTOWRAP_OFF
		b.disabled = code == T.language()
		b.pressed.connect(func():
			T.set_language(code)
			language_changed.emit())
		langs.add_child(b)
	box.add_child(langs)
	var portraits := UITheme.portrait_selector(func(): language_changed.emit())
	portraits.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(portraits)
	var settings := HBoxContainer.new()
	box.add_child(settings)
	var sound := UITheme.button(T.t("ui.sound.off" if Sound.muted else "ui.sound.on"))
	_sound_button = sound
	sound.size_flags_horizontal = SIZE_EXPAND_FILL
	sound.alignment = HORIZONTAL_ALIGNMENT_CENTER
	sound.pressed.connect(func():
		Sound.set_muted(not Sound.muted))
	Sound.settings_changed.connect(_refresh_sound)
	settings.add_child(sound)
	if not OS.has_feature("web") and not OS.has_feature("mobile"):
		var quit := UITheme.button(T.t("ui.quit"))
		quit.autowrap_mode = TextServer.AUTOWRAP_OFF
		quit.alignment = HORIZONTAL_ALIGNMENT_CENTER
		quit.pressed.connect(func(): quit_pressed.emit())
		settings.add_child(quit)
	var footer := UITheme.label(T.t("ui.title.footer"), UITheme.DIM, 9)
	footer.position = Vector2(28, 337)
	footer.size.x = 570
	add_child(footer)
	start.grab_focus()


func _refresh_sound() -> void:
	_sound_button.text = T.t("ui.sound.off" if Sound.muted else "ui.sound.on")
