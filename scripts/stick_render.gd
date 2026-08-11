class_name StickRender
## Shared top-down stick-figure drawing (Stick Arena / Hotline Miami style):
## a head seen from above, two hands gripping the current gun, facing the aim.

static func draw_stick(ci: CanvasItem, aim: float, weapon_id: String, body: Color,
		flash: float, reloading: bool, hp: int, max_hp: int, tag: String) -> void:
	var data: Dictionary = Weapons.DATA[weapon_id]
	var v := Vector2.from_angle(aim)
	var perp := v.orthogonal()
	var outline := Color(0.05, 0.05, 0.08)
	var wlen: float = data.length * (0.55 if reloading else 1.0)
	var grip := v * 15.0

	# Gun (dark base line with the weapon's tint on top).
	ci.draw_line(grip - v * 4.0, grip + v * wlen, Color(0.08, 0.08, 0.1), 5.0)
	ci.draw_line(grip - v * 4.0, grip + v * wlen, data.color, 3.0)

	# Hands.
	for side in [-1.0, 1.0]:
		var hand: Vector2 = grip + perp * 6.0 * side
		if reloading:
			hand -= v * 5.0
		ci.draw_circle(hand, 4.5, outline)
		ci.draw_circle(hand, 3.2, body)

	# Head / shoulders.
	ci.draw_circle(Vector2.ZERO, 13.0, outline)
	ci.draw_circle(Vector2.ZERO, 10.5, body)
	ci.draw_circle(v * 5.5, 2.2, outline)

	# Muzzle flash.
	if flash > 0.0:
		var m := grip + v * (wlen + 6.0)
		ci.draw_circle(m, 7.0, Color(1.0, 0.9, 0.4, clampf(flash * 10.0, 0.0, 1.0)))
		ci.draw_line(m, m + v * 14.0, Color(1.0, 0.8, 0.3, 0.9), 2.0)

	# Health bar.
	var frac := clampf(float(hp) / float(max_hp), 0.0, 1.0)
	ci.draw_rect(Rect2(-16, -27, 32, 5), Color(0, 0, 0, 0.6))
	var bar_col := Color(0.2, 1.0, 0.35) if frac > 0.35 else Color(1.0, 0.3, 0.25)
	ci.draw_rect(Rect2(-15, -26, 30.0 * frac, 3), bar_col)

	# Name tag (multiplayer).
	if tag != "":
		var font := ThemeDB.fallback_font
		ci.draw_string(font, Vector2(-30, -32), tag,
				HORIZONTAL_ALIGNMENT_CENTER, 60, 12, Color(1, 1, 1, 0.85))
