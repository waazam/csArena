class_name Bullet
extends Node2D
## Raycast-stepped projectile (no tunneling). Bullets exist on every peer for
## visuals, but only the server instance applies damage.

var dir := Vector2.RIGHT
var speed := 1000.0
var damage := 10
var shooter_rid := RID()
var shooter_peer := 0
var source_group := "player"  # "player" or "enemy"
var life := 1.3
var can_damage := true
var color := Color(1.0, 0.85, 0.4)
var trail: Array[Vector2] = []  # recent global positions, newest first (cosmetic)

func _ready() -> void:
	can_damage = multiplayer.is_server()
	rotation = dir.angle()
	z_index = 6

func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	trail.push_front(global_position)
	if trail.size() > 7:
		trail.resize(7)
	queue_redraw()
	var step := dir * speed * delta
	var params := PhysicsRayQueryParameters2D.create(
			global_position, global_position + step, 1 | 2 | 4, [shooter_rid])
	var hit := get_world_2d().direct_space_state.intersect_ray(params)
	if hit.is_empty():
		global_position += step
		return
	var col: Object = hit.collider
	if can_damage and col.has_method("receive_hit") and _valid_target(col):
		col.receive_hit(damage, shooter_peer, dir)
	if col is StaticBody2D:
		var g = get_tree().get_first_node_in_group("game")
		if g:
			var nrm: Vector2 = hit.get("normal", -dir)
			g.fx.impact(hit.position, nrm, color)
			g.gore.add_splat(hit.position, randf_range(2.0, 3.0), Color(0.07, 0.07, 0.10, 0.6))
		Sfx.play_at("hit_wall", hit.position, -12.0, 0.2)
	queue_free()

func _valid_target(col: Object) -> bool:
	# Enemies don't damage each other (their bodies still block shots).
	if source_group == "enemy" and col is Enemy:
		return false
	return true

func _draw() -> void:
	# Fading trail behind the round (drawn in local space).
	for i in range(trail.size() - 1):
		var a := 0.45 * (1.0 - float(i) / 6.0)
		draw_line(to_local(trail[i]), to_local(trail[i + 1]),
				Color(color.r, color.g, color.b, a), maxf(1.0, 2.4 - i * 0.3))
	# Glow + hot core.
	draw_circle(Vector2(2, 0), 4.0, Color(color.r, color.g, color.b, 0.22))
	draw_line(Vector2(-10, 0), Vector2(2, 0), Color(color.r, color.g, color.b, 0.85), 2.5)
	draw_line(Vector2(-6, 0), Vector2(2, 0), color.lightened(0.45), 1.4)
	draw_circle(Vector2(2, 0), 1.7, Color(1.0, 1.0, 0.9))
