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

func _ready() -> void:
	can_damage = multiplayer.is_server()
	rotation = dir.angle()
	z_index = 6

func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
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
			g.gore.add_splat(hit.position, randf_range(2.0, 3.5), Color(0.55, 0.5, 0.6, 0.7))
	queue_free()

func _valid_target(col: Object) -> bool:
	# Enemies don't damage each other (their bodies still block shots).
	if source_group == "enemy" and col is Enemy:
		return false
	return true

func _draw() -> void:
	draw_line(Vector2(-10, 0), Vector2(2, 0), color, 2.5)
	draw_circle(Vector2(2, 0), 1.6, color)
