class_name FxLayer
extends Node2D
## Purely cosmetic, local-only effect layer: impact sparks, ejected shell
## casings that tumble and settle on the floor, and expanding rings.
## Nothing in here touches gameplay state and nothing is networked.

const MAX_SPARKS := 320
const MAX_SHELLS := 90
const MAX_SETTLED := 260
const MAX_RINGS := 24

var sparks: Array = []
var shells: Array = []
var settled: Array = []  # shells at rest, drawn until the cap recycles them
var rings: Array = []

func _ready() -> void:
	z_index = 4  # above floor/gore, below actors

func impact(pos: Vector2, normal: Vector2, col: Color, count := 6) -> void:
	var n := normal.normalized() if normal.length() > 0.01 else Vector2.UP
	for i in count:
		if sparks.size() >= MAX_SPARKS:
			break
		var ang := n.angle() + randf_range(-1.1, 1.1)
		sparks.append({
			pos = pos, vel = Vector2.from_angle(ang) * randf_range(90.0, 320.0),
			life = randf_range(0.12, 0.30), max_life = 0.30, col = col,
		})
	ring(pos, randf_range(10.0, 16.0), Color(col.r, col.g, col.b, 0.30))
	queue_redraw()

func death_burst(pos: Vector2, col: Color) -> void:
	for i in 14:
		if sparks.size() >= MAX_SPARKS:
			break
		sparks.append({
			pos = pos, vel = Vector2.from_angle(randf() * TAU) * randf_range(60.0, 260.0),
			life = randf_range(0.20, 0.45), max_life = 0.45, col = col,
		})
	ring(pos, 44.0, Color(1, 1, 1, 0.55))
	ring(pos, 30.0, Color(col.r, col.g, col.b, 0.5))
	queue_redraw()

func ring(pos: Vector2, max_r: float, col: Color) -> void:
	if rings.size() >= MAX_RINGS:
		rings.pop_front()
	rings.append({pos = pos, max_r = max_r, life = 0.35, max_life = 0.35, col = col})
	queue_redraw()

func eject_shell(pos: Vector2, aim: float, weapon_id: String) -> void:
	if shells.size() >= MAX_SHELLS:
		return
	var v := Vector2.from_angle(aim)
	var perp := v.orthogonal()
	var col := Color(0.82, 0.28, 0.22) if weapon_id == "nova" else Color(0.85, 0.68, 0.28)
	shells.append({
		pos = pos + v * 8.0,
		vel = perp * randf_range(80.0, 160.0) - v * randf_range(10.0, 50.0),
		rot = aim + randf_range(-0.4, 0.4), rv = randf_range(-14.0, 14.0),
		life = randf_range(0.35, 0.60), col = col,
	})
	queue_redraw()

func _physics_process(delta: float) -> void:
	if sparks.is_empty() and shells.is_empty() and rings.is_empty():
		return
	var i := sparks.size() - 1
	while i >= 0:
		var s: Dictionary = sparks[i]
		s.life -= delta
		if s.life <= 0.0:
			sparks.remove_at(i)
		else:
			s.pos += s.vel * delta
			s.vel = s.vel.lerp(Vector2.ZERO, minf(1.0, delta * 7.0))
		i -= 1
	i = shells.size() - 1
	while i >= 0:
		var sh: Dictionary = shells[i]
		sh.life -= delta
		if sh.life <= 0.0:
			settled.append({pos = sh.pos, rot = sh.rot, col = sh.col})
			if settled.size() > MAX_SETTLED:
				settled.pop_front()
			shells.remove_at(i)
		else:
			sh.pos += sh.vel * delta
			sh.vel = sh.vel.lerp(Vector2.ZERO, minf(1.0, delta * 5.0))
			sh.rot += sh.rv * delta
		i -= 1
	i = rings.size() - 1
	while i >= 0:
		var rg: Dictionary = rings[i]
		rg.life -= delta
		if rg.life <= 0.0:
			rings.remove_at(i)
		i -= 1
	queue_redraw()

func _draw() -> void:
	# Settled brass first (dimmer), then airborne shells.
	for sh in settled:
		draw_set_transform(sh.pos, sh.rot, Vector2.ONE)
		draw_rect(Rect2(-2.5, -1.0, 5.0, 2.0), sh.col.darkened(0.3))
	for sh in shells:
		draw_set_transform(sh.pos, sh.rot, Vector2.ONE)
		draw_rect(Rect2(-2.5, -1.0, 5.0, 2.0), sh.col)
		draw_rect(Rect2(1.0, -1.0, 1.5, 2.0), sh.col.lightened(0.3))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for s in sparks:
		var a: float = clampf(s.life / s.max_life, 0.0, 1.0)
		var tail: Vector2 = s.pos - s.vel * 0.03
		draw_line(tail, s.pos, Color(s.col.r, s.col.g, s.col.b, a), 1.8)
		draw_circle(s.pos, 1.4, Color(1.0, 1.0, 0.9, a * 0.8))
	for rg in rings:
		var a2: float = clampf(rg.life / rg.max_life, 0.0, 1.0)
		var rr: float = lerpf(rg.max_r, 4.0, a2)
		draw_arc(rg.pos, rr, 0.0, TAU, 28,
				Color(rg.col.r, rg.col.g, rg.col.b, rg.col.a * a2), 2.5)
