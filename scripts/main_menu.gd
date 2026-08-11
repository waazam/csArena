extends Control
## Main menu: PLAY (PvE waves), MULTIPLAYER (host / join PvP deathmatch), QUIT.
## Neon-noir styling: animated grid backdrop, pulsing title, styled buttons.

const ACCENT := Color(0.45, 0.95, 1.0)
const ACCENT2 := Color(1.0, 0.35, 0.62)

var status_label: Label
var main_box: VBoxContainer
var mp_box: VBoxContainer
var ip_edit: LineEdit
var title_label: Label
var t := 0.0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not Net.join_failed.is_connected(_on_join_failed):
		Net.join_failed.connect(_on_join_failed)

	var bg := MenuBG.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(v)

	title_label = Label.new()
	title_label.text = "CS STICK ARENA"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 64)
	title_label.add_theme_color_override("font_color", ACCENT2)
	title_label.add_theme_color_override("font_outline_color", Color(ACCENT2.r, ACCENT2.g, ACCENT2.b, 0.35))
	title_label.add_theme_constant_override("outline_size", 12)
	# Offset cyan shadow for a cheap chromatic-aberration feel.
	title_label.add_theme_color_override("font_shadow_color", Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.5))
	title_label.add_theme_constant_override("shadow_offset_x", 3)
	title_label.add_theme_constant_override("shadow_offset_y", 2)
	v.add_child(title_label)

	var sub := Label.new()
	sub.text = "top-down stick shooter"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", Color(0.62, 0.66, 0.80))
	v.add_child(sub)

	v.add_child(_spacer(18))

	main_box = VBoxContainer.new()
	main_box.add_theme_constant_override("separation", 10)
	v.add_child(main_box)
	main_box.add_child(_button("PLAY  ·  PVE ARENA", _on_play))
	main_box.add_child(_button("MULTIPLAYER  ·  PVP", _on_multiplayer))
	main_box.add_child(_button("QUIT", _on_quit))

	mp_box = VBoxContainer.new()
	mp_box.add_theme_constant_override("separation", 10)
	mp_box.visible = false
	v.add_child(mp_box)
	var mp_title := Label.new()
	mp_title.text = "PVP DEATHMATCH — LAN / DIRECT IP"
	mp_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mp_title.add_theme_font_size_override("font_size", 20)
	mp_title.add_theme_color_override("font_color", ACCENT)
	mp_box.add_child(mp_title)
	mp_box.add_child(_button("HOST GAME", _on_host))
	ip_edit = LineEdit.new()
	ip_edit.text = "127.0.0.1"
	ip_edit.placeholder_text = "host IP address"
	ip_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	ip_edit.custom_minimum_size = Vector2(360, 44)
	var esb := StyleBoxFlat.new()
	esb.bg_color = Color(0.05, 0.06, 0.11, 0.9)
	esb.border_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.35)
	esb.set_border_width_all(1)
	esb.set_corner_radius_all(8)
	ip_edit.add_theme_stylebox_override("normal", esb)
	var esb_f := esb.duplicate()
	esb_f.border_color = ACCENT
	ip_edit.add_theme_stylebox_override("focus", esb_f)
	mp_box.add_child(ip_edit)
	mp_box.add_child(_button("JOIN GAME", _on_join))
	mp_box.add_child(_button("BACK", _on_back))
	var lan := Label.new()
	lan.text = "your LAN IP: %s   ·   port %d" % [_lan_ip(), Net.PORT]
	lan.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lan.add_theme_font_size_override("font_size", 13)
	lan.add_theme_color_override("font_color", Color(0.55, 0.58, 0.70))
	mp_box.add_child(lan)

	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 16)
	status_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	v.add_child(status_label)

	v.add_child(_spacer(24))
	var help := Label.new()
	help.text = "WASD move · mouse aim · LMB shoot · R reload · walk over guns to pick up · ESC quits to menu"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_theme_font_size_override("font_size", 13)
	help.add_theme_color_override("font_color", Color(0.55, 0.58, 0.70))
	v.add_child(help)

func _process(delta: float) -> void:
	t += delta
	if title_label:
		var pulse := 0.5 + 0.5 * sin(t * 2.2)
		title_label.add_theme_color_override("font_outline_color",
				Color(ACCENT2.r, ACCENT2.g, ACCENT2.b, 0.18 + 0.30 * pulse))
		title_label.modulate = Color(1, 1, 1, 0.90 + 0.10 * pulse)

func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(360, 52)
	b.add_theme_font_size_override("font_size", 22)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.06, 0.07, 0.14, 0.92)
	normal.border_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.40)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(10)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.10, 0.13, 0.22, 0.95)
	hover.border_color = ACCENT
	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.04, 0.05, 0.09, 0.95)
	pressed.border_color = ACCENT2
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", hover.duplicate())
	b.add_theme_color_override("font_color", Color(0.9, 0.97, 1.0))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.mouse_entered.connect(func() -> void: Sfx.play("ui_hover", -14.0))
	b.pressed.connect(func() -> void: Sfx.play("ui_click", -8.0))
	b.pressed.connect(cb)
	return b

func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

func _lan_ip() -> String:
	for a in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10.") or a.begins_with("172."):
			return a
	return "127.0.0.1"

func _on_play() -> void:
	Net.start_pve()

func _on_multiplayer() -> void:
	if OS.has_feature("web"):
		status_label.text = "PvP needs the desktop version — browsers can't do UDP networking"
		return
	main_box.visible = false
	mp_box.visible = true
	status_label.text = ""

func _on_back() -> void:
	mp_box.visible = false
	main_box.visible = true
	status_label.text = ""

func _on_quit() -> void:
	get_tree().quit()

func _on_host() -> void:
	var err := Net.host_pvp()
	if err != "":
		status_label.text = err

func _on_join() -> void:
	var err := Net.join_pvp(ip_edit.text.strip_edges())
	status_label.text = "connecting…" if err == "" else err

func _on_join_failed(reason: String) -> void:
	status_label.text = reason

class MenuBG extends Control:
	## Animated original backdrop: gradient, drifting neon motes, slow grid,
	## CRT-style scanlines. Pure _draw primitives, menu-only cost.
	var t := 0.0

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		var s := size
		if s.x <= 0.0 or s.y <= 0.0:
			return
		# Vertical gradient via a per-vertex-colored quad.
		draw_polygon(
				PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0), s, Vector2(0, s.y)]),
				PackedColorArray([
					Color(0.05, 0.04, 0.10), Color(0.07, 0.05, 0.13),
					Color(0.11, 0.06, 0.17), Color(0.07, 0.05, 0.12)]))
		# Slow-scrolling grid.
		var grid := Color(0.45, 0.95, 1.0, 0.045)
		var gx := 0.0
		while gx <= s.x:
			draw_line(Vector2(gx, 0), Vector2(gx, s.y), grid, 1.0)
			gx += 84.0
		var gy := fposmod(t * 14.0, 84.0)
		while gy <= s.y:
			draw_line(Vector2(0, gy), Vector2(s.x, gy), grid, 1.0)
			gy += 84.0
		# Drifting neon motes (deterministic paths from the index).
		for i in 36:
			var h := float(i) * 0.61803
			var px := fposmod(h * s.x * 7.3 + t * (10.0 + fposmod(h * 91.0, 22.0)), s.x)
			var py := fposmod(h * s.y * 3.7 + t * (4.0 + fposmod(h * 53.0, 12.0)), s.y)
			var col := Color(0.45, 0.95, 1.0, 0.10 + 0.07 * sin(t * 2.0 + i)) \
					if i % 3 != 0 else Color(1.0, 0.35, 0.62, 0.12)
			draw_circle(Vector2(px, py), 1.5 + fposmod(h * 13.0, 2.2), col)
		# Scanlines.
		var scan := Color(0, 0, 0, 0.13)
		var sy := 0.0
		while sy <= s.y:
			draw_line(Vector2(0, sy), Vector2(s.x, sy), scan, 1.0)
			sy += 4.0
