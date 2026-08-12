class_name Player
extends CharacterBody2D

signal health_changed(hp: int)
signal damaged
signal died

const SPEED: float = 300.0
const MAX_HP: int = 100
const FIRE_COOLDOWN: float = 0.2
const INVULN_TIME: float = 0.5
const BULLET_SCENE: PackedScene = preload("res://scenes/bullet.tscn")

var hp: int = MAX_HP
var _fire_timer: float = 0.0
var _invuln_timer: float = 0.0
var _dead: bool = false

@onready var muzzle: Marker2D = $Muzzle
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	add_to_group("player")


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_fire_timer = maxf(_fire_timer - delta, 0.0)
	_invuln_timer = maxf(_invuln_timer - delta, 0.0)

	var dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = dir * SPEED
	move_and_slide()

	var mouse_pos: Vector2 = get_global_mouse_position()
	if global_position.distance_squared_to(mouse_pos) > 1.0:
		look_at(mouse_pos)

	# Blink while invulnerable.
	modulate.a = 0.5 if _invuln_timer > 0.0 else 1.0

	if Input.is_action_pressed("shoot") and _fire_timer <= 0.0:
		_shoot()
		_fire_timer = FIRE_COOLDOWN


func _shoot() -> void:
	var bullet: Node2D = BULLET_SCENE.instantiate()
	bullet.position = muzzle.global_position
	bullet.rotation = global_rotation
	get_tree().current_scene.add_child(bullet)


func take_damage(amount: int) -> void:
	if _dead or _invuln_timer > 0.0:
		return
	hp = maxi(hp - amount, 0)
	_invuln_timer = INVULN_TIME
	health_changed.emit(hp)
	damaged.emit()
	if hp == 0:
		_die()


func _die() -> void:
	_dead = true
	remove_from_group("player")
	hide()
	collision_shape.set_deferred("disabled", true)
	set_physics_process(false)
	died.emit()
