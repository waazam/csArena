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
	active = v

func _draw() -> void:
	if not active:
		return
	var o := Vector2(0, sin(t * 3.0) * 2.0)
	var font := ThemeDB.fallback_font
	if kind == "medkit":
		draw_rect(Rect2(o + Vector2(-11, -9), Vector2(22, 18)), Color(0.9, 0.92, 0.95))
		draw_rect(Rect2(o + Vector2(-3, -6), Vector2(6, 12)), Color(0.85, 0.15, 0.2))
		draw_rect(Rect2(o + Vector2(-6, -3), Vector2(12, 6)), Color(0.85, 0.15, 0.2))
	else:
		var data: Dictionary = Weapons.DATA[weapon_id]
		var pulse: float = 0.25 + 0.1 * sin(t * 2.0)
		draw_arc(o, 16.0, 0, TAU, 24, Color(1, 1, 1, pulse), 2.0)
		var half: float = data.length * 0.6
		draw_line(o + Vector2(-half, 0), o + Vector2(half, 0), Color(0.08, 0.08, 0.1), 5.0)
		draw_line(o + Vector2(-half, 0), o + Vector2(half, 0), data.color, 3.0)
		draw_line(o + Vector2(-half * 0.4, 0), o + Vector2(-half * 0.4 - 3, 8), Color(0.08, 0.08, 0.1), 3.0)
		draw_string(font, o + Vector2(-40, 32), data.name,
				HORIZONTAL_ALIGNMENT_CENTER, 80, 11, Color(1, 1, 1, 0.7))
