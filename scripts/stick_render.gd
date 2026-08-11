class_name StickRender
## Shared top-down stick-figure drawing (original neon-noir look):
## a head seen from above with shoulders, striding feet, two hands gripping
## the current gun (with per-weapon silhouette details), a star-shaped muzzle
## flash, a reload progress arc and a health bar. Everything is primitives.

static func draw_gun(ci: CanvasItem, origin: Vector2, v: Vector2, weapon_id: String,
		wlen: float) -> void:
	var data: Dictionary = Weapons.DATA[weapon_id]
	var perp := v.orthogonal()
	var dark := Color(0.06, 0.06, 0.09)
	var tip := origin + v * wlen
	# Stock behind the grip for long guns.
	if weapon_id == "m4a4" or weapon_id == "ak47" or weapon_id == "awp" \
			or weapon_id == "nova" or weapon_id == "mp5":
		ci.draw_line(origin - v * 8.0, origin, dark, 6.0)
		ci.draw_line(origin - v * 8.0, origin, data.color.darkened(0.4), 4.0)
	# Barrel: dark base line with the weapon's tint on top.
	ci.draw_line(origin - v * 3.0, tip, dark, 5.0)
	ci.draw_line(origin - v * 3.0, tip, data.color, 3.0)
	# Per-weapon silhouette details.
	match weapon_id:
		"awp":
			var sc: Vector2 = origin + v * wlen * 0.40
			ci.draw_circle(sc, 3.8, dark)
			ci.draw_circle(sc, 2.4, Color(0.55, 0.95, 0.65))
			ci.draw_line(tip - v * 3.0, tip, dark, 5.5)
		"nova":
			var pump: Vector2 = origin + v * wlen * 0.55 + perp * 3.0
			ci.draw_line(pump - v * 4.5, pump + v * 4.5, dark, 4.0)
			ci.draw_line(pump - v * 4.5, pump + v * 4.5, Color(0.78, 0.52, 0.30), 2.2)
		"mp5":
			ci.draw_line(tip - v * 6.0, tip, dark, 4.5)
			var magp: Vector2 = origin + v * wlen * 0.40
			ci.draw_line(magp, magp + perp * 5.0 - v * 1.5, dark, 3.0)
		"usp":
			ci.draw_line(tip - v * 5.0, tip, Color(0.22, 0.22, 0.27), 4.2)
		"m4a4", "ak47":
			var mag2: Vector2 = origin + v * wlen * 0.35
			ci.draw_line(mag2, mag2 + perp * 5.5 - v * 1.5, dark, 3.2)

static func draw_stick(ci: CanvasItem, aim: float, weapon_id: String, body: Color,
		flash: float, reloading: bool, hp: int, max_hp: int, tag: String,
		walk_phase := 0.0, stride := 0.0, is_local := false, reload_frac := -1.0) -> void:
	var data: Dictionary = Weapons.DATA[weapon_id]
	var v := Vector2.from_angle(aim)
	var perp := v.orthogonal()
	var outline := Color(0.05, 0.05, 0.08)
	var wlen: float = data.length * (0.55 if reloading else 1.0)
	var grip := v * 15.0

	# Soft aura so you always spot yourself.
	if is_local:
		var glow := Color(body.r, body.g, body.b, 0.045)
		for i in 3:
			ci.draw_circle(Vector2.ZERO, 16.0 + i * 5.0, glow)

	# Feet: stride along the facing axis while moving, tucked in when idle.
	var shoe := body.darkened(0.55)
	for side in [-1.0, 1.0]:
		var swing: float = sin(walk_phase + (PI if side > 0.0 else 0.0)) * 7.0 * stride
		var foot: Vector2 = perp * 7.5 * side + v * (swing - 2.0)
		ci.draw_circle(foot, 3.6, outline)
		ci.draw_circle(foot, 2.5, shoe)

	# Gun with silhouette details.
	draw_gun(ci, grip - v * 2.0, v, weapon_id, wlen)

	# Hands (subtle bob with the stride; pulled back while reloading).
	var bob := sin(walk_phase * 2.0) * 1.2 * stride
	for side in [-1.0, 1.0]:
		var hand: Vector2 = grip + perp * (6.0 + bob * side) * side
		if reloading:
			hand -= v * 5.0
		ci.draw_circle(hand, 4.5, outline)
		ci.draw_circle(hand, 3.2, body)

	# Shoulders poking out beside the head, then the head itself.
	ci.draw_line(-perp * 14.0, perp * 14.0, outline, 8.0)
	ci.draw_line(-perp * 13.0, perp * 13.0, body.darkened(0.2), 5.0)
	ci.draw_circle(Vector2.ZERO, 13.0, outline)
	ci.draw_circle(Vector2.ZERO, 10.5, body)
	ci.draw_circle(v * 2.5, 6.0, body.lightened(0.13))
	ci.draw_circle(v * 5.5, 2.2, outline)

	# Star-shaped muzzle flash with a warm glow halo.
	if flash > 0.0:
		var a := clampf(flash / 0.09, 0.0, 1.0)
		var m := grip + v * (wlen + 6.0)
		ci.draw_circle(m, 15.0, Color(1.0, 0.72, 0.28, 0.22 * a))
		var pts := PackedVector2Array()
		for i in 10:
			var ang := aim + float(i) * TAU / 10.0
			var rad := (11.0 if i % 2 == 0 else 4.0) * (0.65 + 0.35 * a)
			pts.append(m + Vector2.from_angle(ang) * rad)
		ci.draw_colored_polygon(pts, Color(1.0, 0.88, 0.45, 0.95 * a))
		ci.draw_circle(m, 3.5, Color(1.0, 1.0, 0.85, a))
		ci.draw_line(m, m + v * 16.0, Color(1.0, 0.85, 0.4, 0.8 * a), 2.0)

	# Reload progress arc around the head.
	if reload_frac >= 0.0:
		ci.draw_arc(Vector2.ZERO, 17.5, -PI / 2.0, -PI / 2.0 + TAU * clampf(reload_frac, 0.0, 1.0),
				20, Color(1.0, 0.85, 0.35, 0.9), 2.5)

	# Health bar.
	var frac := clampf(float(hp) / float(max_hp), 0.0, 1.0)
	ci.draw_rect(Rect2(-17, -28, 34, 6), Color(0, 0, 0, 0.65))
	var bar_col := Color.from_hsv(0.34 * frac, 0.85, 1.0)
	ci.draw_rect(Rect2(-16, -27, 32.0 * frac, 4), bar_col)
	ci.draw_rect(Rect2(-17, -28, 34, 6), Color(1, 1, 1, 0.12), false, 1.0)

	# Name tag (multiplayer).
	if tag != "":
		var font := ThemeDB.fallback_font
		ci.draw_string(font, Vector2(-30, -33), tag,
				HORIZONTAL_ALIGNMENT_CENTER, 60, 12, Color(1, 1, 1, 0.85))
