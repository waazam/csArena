extends Control
## Main menu: PLAY (PvE waves), MULTIPLAYER (host / join PvP deathmatch), QUIT.

var status_label: Label
var main_box: VBoxContainer
var mp_box: VBoxContainer
var ip_edit: LineEdit

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not Net.join_failed.is_connected(_on_join_failed):
		Net.join_failed.connect(_on_join_failed)

	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.07, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(v)

	var title := Label.new()
	title.text = "CS STICK ARENA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(1.0, 0.38, 0.58))
	v.add_child(title)

	var sub := Label.new()
	sub.text = "top-down stick shooter"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
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
	mp_box.add_child(mp_title)
	mp_box.add_child(_button("HOST GAME", _on_host))
	ip_edit = LineEdit.new()
	ip_edit.text = "127.0.0.1"
	ip_edit.placeholder_text = "host IP address"
	ip_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	ip_edit.custom_minimum_size = Vector2(360, 44)
	mp_box.add_child(ip_edit)
	mp_box.add_child(_button("JOIN GAME", _on_join))
	mp_box.add_child(_button("BACK", _on_back))
	var lan := Label.new()
	lan.text = "your LAN IP: %s   ·   port %d" % [_lan_ip(), Net.PORT]
	lan.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lan.add_theme_font_size_override("font_size", 13)
	lan.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
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
	help.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
	v.add_child(help)

func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(360, 52)
	b.add_theme_font_size_override("font_size", 22)
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
