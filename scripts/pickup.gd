class_name Pickup
extends Area2D
## Walk-over pickup: a weapon (swaps your gun, refills ammo) or a medkit.
## The server decides who takes it; results are RPC'd (runs locally in PvE).

const RESPAWN_TIME := 14.0
const HEAL_AMOUNT := 50

var kind := "weapon"  # "weapon" or "medkit"
var weapon_id := "mp5"
var respawns := true
var active := true
var t := 0.0

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	z_index = 2
	t = randf() * TAU
	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = 18.0
	cs.shape = sh
	add_child(cs)

func _physics_process(delta: float) -> void:
	t += delta
	if active and multiplayer.is_server():
		for b in get_overlapping_bodies():
			if b is Player and b.alive:
				_give(b)
				break
	queue_redraw()

func _give(p) -> void:
	if kind == "medkit":
		if p.hp >= p.MAX_HP:
			return
		p.rpc("net_heal", HEAL_AMOUNT)
	else:
		p.rpc("net_give_weapon", weapon_id)
	rpc("net_set_active", false)
	if respawns:
		get_tree().create_timer(RESPAWN_TIME).timeout.connect(_respawn)
	else:
		queue_free()

func _respawn() -> void:
	if is_instance_valid(self):
		rpc("net_set_active", true)

@rpc("any_peer", "call_local", "reliable")
func net_set_active(v: bool) -> void:
	if v != active:
		# Cosmetic ring on take / respawn (runs on every peer via this RPC).
		var g = get_tree().get_first_node_in_group("game")
		if g:
			if v:
				g.fx.ring(global_position, 20.0, Color(0.5, 1.0, 0.7, 0.5))
			else:
				g.fx.ring(global_position, 30.0, Color(1.0, 0.4, 0.7, 0.6))
	active = v

func _draw() -> void:
	if not active:
		return
	var o := Vector2(0, sin(t * 3.0) * 2.5)  # hover bob
	var font := ThemeDB.fallback_font
	# Ground shadow (squashed circle) under the floating item.
	draw_set_transform(Vector2(0, 12), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 11.0, Color(0, 0, 0, 0.30))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if kind == "medkit":
		# Soft red glow + white kit with a cross, pulsing ring.
		for i in 3:
			draw_circle(o, 12.0 + i * 5.0, Color(1.0, 0.25, 0.3, 0.05))
		var pr := fposmod(t, 1.8) / 1.8
		draw_arc(o, 13.0 + pr * 12.0, 0, TAU, 20,
				Color(1.0, 0.35, 0.4, 0.35 * (1.0 - pr)), 2.0)
		draw_rect(Rect2(o + Vector2(-12, -10), Vector2(24, 20)), Color(0.06, 0.06, 0.09))
		draw_rect(Rect2(o + Vector2(-11, -9), Vector2(22, 18)), Color(0.92, 0.94, 0.97))
		draw_rect(Rect2(o + Vector2(-3, -6), Vector2(6, 12)), Color(0.85, 0.15, 0.2))
		draw_rect(Rect2(o + Vector2(-6, -3), Vector2(12, 6)), Color(0.85, 0.15, 0.2))
	else:
		var data: Dictionary = Weapons.DATA[weapon_id]
		var gc: Color = data.color
		# Soft glow in the weapon's tint.
		for i in 3:
			draw_circle(o, 10.0 + i * 5.0, Color(gc.r, gc.g, gc.b, 0.05))
		# Rotating orbit arcs.
		var aa := t * 1.2
		draw_arc(o, 17.0, aa, aa + PI * 0.6, 14, Color(1, 1, 1, 0.45), 1.5)
		draw_arc(o, 17.0, aa + PI, aa + PI * 1.6, 14, Color(1, 1, 1, 0.45), 1.5)
		# Expanding pulse ring.
		var pr2 := fposmod(t, 1.6) / 1.6
		draw_arc(o, 12.0 + pr2 * 14.0, 0, TAU, 20,
				Color(gc.r, gc.g, gc.b, 0.35 * (1.0 - pr2)), 2.0)
		# The gun itself, gently swaying, with its real silhouette details.
		var v := Vector2.RIGHT.rotated(sin(t * 0.9) * 0.15)
		var wlen: float = data.length * 1.1
		StickRender.draw_gun(self, o - v * wlen * 0.55, v, weapon_id, wlen)
		draw_string(font, o + Vector2(-40, 34), data.name,
				HORIZONTAL_ALIGNMENT_CENTER, 80, 11, Color(0.85, 0.95, 1.0, 0.8))
