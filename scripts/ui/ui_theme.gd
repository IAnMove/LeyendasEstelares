class_name UITheme
extends RefCounted
## Dirección de arte: tinta azul petróleo, papel cálido y controles de navegación ámbar.

const BG := Color("091c24")
const PANEL := Color("112c35")
const PANEL_BORDER := Color("41616a")
const TEXT := Color("f1e6cb")
const DIM := Color("a8b9b6")
const ACCENT := Color("71c7c5")
const WARN := Color("efb65f")
const BAD := Color("ee8371")
const GOOD := Color("a9c995")
const PAPER := Color("e9ddbd")
const INK := Color("122b34")
const BODY_FONT = preload("res://art/fonts/LiberationSans-Regular.ttf")
const BOLD_FONT = preload("res://art/fonts/LiberationSans-Bold.ttf")
const DISPLAY_FONT = preload("res://art/fonts/LiberationSans-BoldItalic.ttf")
const MONO_FONT = preload("res://art/fonts/LiberationMono-Regular.ttf")


static func box(bg: Color, border: Color, pad := 6, border_w := 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_content_margin_all(pad)
	return sb


static func build() -> Theme:
	var t := Theme.new()
	t.default_font = BODY_FONT
	t.default_font_size = 12
	t.set_color("font_color", "Label", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font_size("normal_font_size", "RichTextLabel", 12)
	var panel := box(PANEL, PANEL_BORDER, 8)
	panel.border_width_top = 2
	panel.shadow_color = Color(0, 0, 0, 0.25)
	panel.shadow_offset = Vector2(2, 3)
	panel.shadow_size = 1
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_font("font", "Button", BOLD_FONT)
	t.set_stylebox("normal", "Button", box(Color("203f47"), PANEL_BORDER, 6))
	t.set_stylebox("hover", "Button", box(Color("315761"), ACCENT, 6))
	t.set_stylebox("pressed", "Button", box(ACCENT, ACCENT, 6))
	t.set_stylebox("disabled", "Button", box(Color("10272f"), Color("2f474f"), 6))
	var focus := box(Color.TRANSPARENT, WARN, 6, 2)
	focus.expand_margin_left = 2
	focus.expand_margin_right = 2
	focus.expand_margin_top = 2
	focus.expand_margin_bottom = 2
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", Color("81958f"))
	t.set_stylebox("background", "ProgressBar", box(BG, PANEL_BORDER, 0))
	var separator := box(PANEL_BORDER, PANEL_BORDER, 0, 0)
	separator.content_margin_top = 1
	t.set_stylebox("separator", "HSeparator", separator)
	t.set_constant("separation", "HSeparator", 6)
	t.set_stylebox("scroll", "VScrollBar", box(BG, BG, 2, 0))
	t.set_stylebox("grabber", "VScrollBar", box(PANEL_BORDER, PANEL_BORDER, 2, 0))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(ACCENT, ACCENT, 2, 0))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(WARN, WARN, 2, 0))
	return t


static func label(text: String, color := TEXT, size := 12) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	if size >= 14:
		l.add_theme_font_override("font", DISPLAY_FONT if size >= 18 else BOLD_FONT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func caption(text: String, color := ACCENT) -> Label:
	var l := label(text, color, 9)
	l.add_theme_font_override("font", MONO_FONT)
	return l


static func bar(color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(0, 8)
	b.add_theme_stylebox_override("fill", box(color, color, 0, 0))
	return b


static func touch_mode() -> bool:
	return OS.has_feature("mobile") or DisplayServer.is_touchscreen_available() or "--touch-ui" in OS.get_cmdline_user_args()


static func scrolling(parent: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	return scroll


static func help_button() -> Button:
	var b := button("?")
	b.custom_minimum_size.x = 48
	b.tooltip_text = T.t("ui.help.title")
	b.accessibility_name = T.t("ui.help.title")
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.pressed.connect(func(): b.get_tree().call_group("checkpoint_owner", "_open_help"))
	return b


static func pause_button() -> Button:
	var b := button("Ⅱ")
	b.tooltip_text = T.t("ui.pause.title")
	b.accessibility_name = T.t("ui.pause.title")
	b.custom_minimum_size.x = 48
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.pressed.connect(func(): b.get_tree().call_group("checkpoint_owner", "_open_pause"))
	return b


static func button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	if touch_mode():
		b.ready.connect(func(): b.custom_minimum_size = b.custom_minimum_size.max(Vector2(48, 48)))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(func():
		Sound.play("click")
		b.get_tree().call_group("checkpoint_owner", "queue_checkpoint"))
	return b


static func primary(b: Button) -> void:
	b.add_theme_stylebox_override("normal", box(WARN, WARN, 6))
	b.add_theme_stylebox_override("hover", box(PAPER, PAPER, 6))
	b.add_theme_stylebox_override("pressed", box(ACCENT, ACCENT, 6))
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_focus_color", INK)


static func illustration(tex_name: String, minimum: Vector2) -> TextureRect:
	var view := TextureRect.new()
	view.texture = Art.tex(tex_name)
	view.custom_minimum_size = minimum
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return view


class ChartBackdrop extends Control:
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), BG)
		for x in range(0, int(size.x), 24):
			for y in range(0, int(size.y), 24):
				draw_circle(Vector2(x, y), 0.6, Color("29414a"))
		var center := Vector2(size.x * 0.79, size.y * 0.45)
		for radius in [62.0, 104.0, 150.0, 210.0]:
			draw_arc(center, radius, 0, TAU, 96, Color("1b3741"), 1, true)
		draw_line(Vector2(0, 56), Vector2(size.x, 56), PANEL_BORDER.darkened(0.4), 1)
		draw_line(Vector2(16, size.y - 10), Vector2(size.x - 16, size.y - 10), PANEL_BORDER.darkened(0.5), 1)


static func background() -> Control:
	var bg := ChartBackdrop.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bg


static func portrait_selector(on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	for version in Art.VERSIONS:
		var b := button(T.t("ui.art.original" if version == "v1_original" else "ui.art.retro"))
		b.autowrap_mode = TextServer.AUTOWRAP_OFF
		b.add_theme_font_size_override("font_size", 10)
		b.disabled = Art.portrait_version == version
		if b.disabled:
			b.add_theme_stylebox_override("disabled", box(PAPER, PAPER, 5))
			b.add_theme_color_override("font_disabled_color", INK)
		b.pressed.connect(func():
			Art.set_portrait_version(version)
			on_change.call())
		row.add_child(b)
	return row


static func isolate_focus(screen: Control) -> void:
	var previous: Array = []
	for control in screen.get_tree().root.find_children("*", "Control", true, false):
		if control != screen and not screen.is_ancestor_of(control) and control.focus_mode != Control.FOCUS_NONE:
			previous.append([weakref(control), control.focus_mode])
			control.focus_mode = Control.FOCUS_NONE
	screen.tree_exiting.connect(func():
		for entry in previous:
			var control = entry[0].get_ref()
			if control != null:
				control.focus_mode = entry[1])
