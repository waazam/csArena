extends CanvasLayer
## In-game HUD: styled health/ammo panels, wave/score (PvE) or scoreboard
## (PvP), center flash messages, ambient + hit vignettes, game-over overlay.

signal retry_pressed
signal menu_pressed

const ACCENT := Color(0.45, 0.95, 1.0)
const ACCENT2 := Color(1.0, 0.35, 0.62)
const PANEL_BG := Color(0.045, 0.05, 0.10, 0.80)
const PANEL_BORDER := Color(0.45, 0.95, 1.0, 0.28)

var hp_fill: Panel
var hp_fill_sb: StyleBoxFlat
var hp_label: Label
var weapon_label: Label
var ammo_label: Label
var info_label: Label
var msg_label: Label
var msg_time := 0.0
var overlay: ColorRect
var ov_title: Label
var ov_sub: Label
var retry_btn: Button
var hit_rect: TextureRect
var hit_a := 0.0
var low_hp := false
var t := 0.0

func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Ambient vignette (always on, very subtle).
	var vin := _fullscreen_tex(_radial_tex(Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.40), 0.55))
	root.add_child(vin)
	# Hit vignette (red), alpha driven from _process.
	hit_rect = _fullscreen_tex(_radial_tex(Color(0.9, 0.05, 0.1, 0.0), Color(0.9, 0.05, 0.12, 0.6), 0.40))
	hit_rect.modulate.a = 0.0
	root.add_child(hit_rect)

	# ---- health panel (bottom left) ----
	var hp_panel := Panel.new()
	hp_panel.add_theme_stylebox_override("panel", _panel_style())
	hp_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hp_panel.offset_left = 24
	hp_panel.offset_top = -62
	hp_panel.offset_right = 268
	hp_panel.offset_bottom = -28
	root.add_child(hp_panel)
	hp_fill = Panel.new()
	hp_fill_sb = StyleBoxFlat.new()
	hp_fill_sb.bg_color = Color(0.25, 0.95, 0.4)
	hp_fill_sb.set_corner_radius_all(4)
	hp_fill.add_theme_stylebox_override("panel", hp_fill_sb)
	hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_fill.position = Vector2(4, 4)
	hp_fill.size = Vector2(236, 26)
	hp_panel.add_child(hp_fill)
	hp_label = Label.new()
	hp_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_label.add_theme_font_size_override("font_size", 15)
	hp_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	hp_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	hp_label.add_theme_constant_override("outline_size", 4)
	hp_panel.add_child(hp_label)

	# ---- ammo panel (bottom right) ----
	var ammo_panel := PanelContainer.new()
	ammo_panel.add_theme_stylebox_override("panel", _panel_style())
	ammo_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ammo_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ammo_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ammo_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ammo_panel.offset_right = -24
	ammo_panel.offset_bottom = -28
	root.add_child(ammo_panel)
	var am := MarginContainer.new()
	am.add_theme_constant_override("margin_left", 16)
	am.add_theme_constant_override("margin_right", 16)
	am.add_theme_constant_override("margin_top", 8)
	am.add_theme_constant_override("margin_bottom", 8)
	ammo_panel.add_child(am)
	var av := VBoxContainer.new()
	am.add_child(av)
	weapon_label = Label.new()
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	weapon_label.add_theme_font_size_override("font_size", 15)
	weapon_label.add_theme_color_override("font_color", ACCENT)
	av.add_child(weapon_label)
	ammo_label = Label.new()
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ammo_label.add_theme_font_size_override("font_size", 26)
	av.add_child(ammo_label)

	# ---- info panel (top left) ----
	var info_panel := PanelContainer.new()
	info_panel.add_theme_stylebox_override("panel", _panel_style())
	info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	info_panel.offset_left = 24
	info_panel.offset_top = 18
	root.add_child(info_panel)
	var im := MarginContainer.new()
	im.add_theme_constant_override("margin_left", 14)
	im.add_theme_constant_override("margin_right", 14)
	im.add_theme_constant_override("margin_top", 8)
	im.add_theme_constant_override("margin_bottom", 8)
	info_panel.add_child(im)
	info_label = Label.new()
	info_label.add_theme_font_size_override("font_size", 17)
	im.add_child(info_label)

	# ---- center flash message ----
	msg_label = Label.new()
	msg_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	msg_label.offset_top = 110
	msg_label.offset_bottom = 200
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_label.add_theme_font_size_override("font_size", 42)
	msg_label.add_theme_color_override("font_color", Color(0.9, 0.98, 1.0))
	msg_label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.08, 0.9))
	msg_label.add_theme_constant_override("outline_size", 10)
	root.add_child(msg_label)

	# ---- game-over overlay ----
	overlay = ColorRect.new()
	overlay.color = Color(0.01, 0.01, 0.03, 0.72)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	root.add_child(overlay)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(cc)
	var panel := PanelContainer.new()
	var psb := _panel_style()
	psb.set_corner_radius_all(14)
	psb.border_color = Color(ACCENT2.r, ACCENT2.g, ACCENT2.b, 0.4)
	psb.set_content_margin_all(38)
	panel.add_theme_stylebox_override("panel", psb)
	cc.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)
	ov_title = Label.new()
	ov_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ov_title.add_theme_font_size_override("font_size", 54)
	ov_title.add_theme_color_override("font_color", ACCENT2)
	ov_title.add_theme_color_override("font_outline_color", Color(0.2, 0.02, 0.08, 0.7))
	ov_title.add_theme_constant_override("outline_size", 10)
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
	_style_button(retry_btn)
	retry_btn.pressed.connect(func() -> void: retry_pressed.emit())
	hb.add_child(retry_btn)
	var menu_btn := Button.new()
	menu_btn.text = "MAIN MENU"
	menu_btn.custom_minimum_size = Vector2(200, 52)
	menu_btn.add_theme_font_size_override("font_size", 20)
	_style_button(menu_btn)
	menu_btn.pressed.connect(func() -> void: menu_pressed.emit())
	hb.add_child(menu_btn)

# ---------------------------------------------------------------- styling

func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = PANEL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	return sb

func _style_button(b: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.07, 0.08, 0.15, 0.95)
	normal.border_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.45)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(8)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.10, 0.13, 0.22, 0.95)
	hover.border_color = ACCENT
	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.05, 0.06, 0.10, 0.95)
	pressed.border_color = ACCENT2
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", hover.duplicate())
	b.add_theme_color_override("font_color", Color(0.9, 0.97, 1.0))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.mouse_entered.connect(func() -> void: Sfx.play("ui_hover", -14.0))
	b.pressed.connect(func() -> void: Sfx.play("ui_click", -8.0))

func _radial_tex(inner: Color, outer: Color, mid: float) -> GradientTexture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, mid, 1.0])
	grad.colors = PackedColorArray([inner, inner, outer])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 256
	tex.height = 256
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	return tex

func _fullscreen_tex(tex: Texture2D) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

# ---------------------------------------------------------------- runtime

func _process(delta: float) -> void:
	t += delta
	if msg_time > 0.0:
		msg_time -= delta
		msg_label.modulate.a = clampf(msg_time / 0.5, 0.0, 1.0)
		if msg_time <= 0.0:
			msg_label.text = ""
	hit_a = maxf(0.0, hit_a - delta * 2.2)
	var a := hit_a
	if low_hp:
		a = maxf(a, 0.14 + 0.08 * sin(t * 6.0))
	hit_rect.modulate.a = a

## Brief red vignette pulse when the local player takes damage.
func hit_flash(strength := 0.5) -> void:
	hit_a = maxf(hit_a, strength)

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
		var frac := clampf(float(p.hp) / float(p.MAX_HP), 0.0, 1.0)
		hp_fill.size.x = 236.0 * frac
		hp_fill_sb.bg_color = Color.from_hsv(0.34 * frac, 0.85, 1.0)
		hp_label.text = "%d" % p.hp
		low_hp = p.alive and p.hp <= 30
		var data: Dictionary = Weapons.DATA[p.weapon_id]
		weapon_label.text = data.name
		ammo_label.text = "RELOADING…" if p.reloading else "%d / %d" % [p.mag, p.reserve]
	else:
		low_hp = false
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
