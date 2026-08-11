extends CanvasLayer
## In-game HUD: health bar, ammo, wave/score (PvE) or scoreboard (PvP),
## center flash messages, and the game-over overlay.

signal retry_pressed
signal menu_pressed

var hp_fg: ColorRect
var hp_label: Label
var ammo_label: Label
var info_label: Label
var msg_label: Label
var msg_time := 0.0
var overlay: ColorRect
var ov_title: Label
var ov_sub: Label
var retry_btn: Button

func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0, 0, 0, 0.55)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_bg.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bar_bg.offset_left = 24
	bar_bg.offset_top = -58
	bar_bg.offset_right = 244
	bar_bg.offset_bottom = -34
	root.add_child(bar_bg)
	hp_fg = ColorRect.new()
	hp_fg.color = Color(0.25, 0.95, 0.4)
	hp_fg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_fg.position = Vector2(2, 2)
	hp_fg.size = Vector2(216, 20)
	bar_bg.add_child(hp_fg)
	hp_label = Label.new()
	hp_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_label.add_theme_font_size_override("font_size", 14)
	hp_label.add_theme_color_override("font_color", Color(0, 0, 0, 0.85))
	bar_bg.add_child(hp_label)

	ammo_label = Label.new()
	ammo_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ammo_label.offset_left = -420
	ammo_label.offset_top = -96
	ammo_label.offset_right = -24
	ammo_label.offset_bottom = -30
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ammo_label.add_theme_font_size_override("font_size", 24)
	root.add_child(ammo_label)

	info_label = Label.new()
	info_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	info_label.offset_left = 24
	info_label.offset_top = 18
	info_label.offset_right = 460
	info_label.offset_bottom = 240
	info_label.add_theme_font_size_override("font_size", 20)
	root.add_child(info_label)

	msg_label = Label.new()
	msg_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	msg_label.offset_top = 110
	msg_label.offset_bottom = 200
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_label.add_theme_font_size_override("font_size", 42)
	msg_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	msg_label.add_theme_constant_override("outline_size", 8)
	root.add_child(msg_label)

	overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.62)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	root.add_child(overlay)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(cc)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	cc.add_child(box)
	ov_title = Label.new()
	ov_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ov_title.add_theme_font_size_override("font_size", 54)
	ov_title.add_theme_color_override("font_color", Color(1.0, 0.38, 0.48))
	box.add_child(ov_title)
	ov_sub = Label.new()
	ov_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ov_sub.add_theme_font_size_override("font_size", 22)
	ov_sub.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
	box.add_child(ov_sub)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(hb)
	retry_btn = Button.new()
	retry_btn.text = "RETRY"
	retry_btn.custom_minimum_size = Vector2(200, 52)
	retry_btn.add_theme_font_size_override("font_size", 20)
	retry_btn.pressed.connect(func() -> void: retry_pressed.emit())
	hb.add_child(retry_btn)
	var menu_btn := Button.new()
	menu_btn.text = "MAIN MENU"
	menu_btn.custom_minimum_size = Vector2(200, 52)
	menu_btn.add_theme_font_size_override("font_size", 20)
	menu_btn.pressed.connect(func() -> void: menu_pressed.emit())
	hb.add_child(menu_btn)

func _process(delta: float) -> void:
	if msg_time > 0.0:
		msg_time -= delta
		msg_label.modulate.a = clampf(msg_time / 0.5, 0.0, 1.0)
		if msg_time <= 0.0:
			msg_label.text = ""

func flash_message(text: String, dur := 2.2) -> void:
	msg_label.text = text
	msg_time = dur
	msg_label.modulate.a = 1.0

func show_overlay(title: String, sub: String, retry_text := "") -> void:
	ov_title.text = title
	ov_sub.text = sub
	retry_btn.visible = retry_text != ""
	if retry_text != "":
		retry_btn.text = retry_text
	overlay.visible = true

func update_hud(game) -> void:
	var p = game.local_player()
	if p:
		hp_fg.size.x = 216.0 * clampf(float(p.hp) / float(p.MAX_HP), 0.0, 1.0)
		hp_label.text = "%d" % p.hp
		var data: Dictionary = Weapons.DATA[p.weapon_id]
		var status: String = "RELOADING…" if p.reloading else "%d / %d" % [p.mag, p.reserve]
		ammo_label.text = "%s\n%s" % [data.name, status]
	if Net.mode == Net.MODE_PVP:
		var lines := ["FIRST TO %d" % game.KILL_LIMIT]
		var ids: Array = game.kills.keys()
		ids.sort()
		for id in ids:
			var you: String = "  (you)" if id == multiplayer.get_unique_id() else ""
			lines.append("P%d%s   %d" % [id, you, game.kills[id]])
		info_label.text = "\n".join(lines)
	else:
		info_label.text = "WAVE %d\nSCORE %d\nENEMIES %d" % [
				game.wave, game.score, game.enemies_alive + game.enemies_to_spawn]
