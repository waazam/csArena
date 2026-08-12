class_name Enemy
extends CharacterBody2D

signal died(score_value: int)

const TOUCH_COOLDOWN: float = 0.5

@export var max_hp: float = 50.0
@export var speed: float = 120.0
@export var contact_damage: int = 10
@export var score_value: int = 10

var hp: float
var _touch_timer: float = 0.0
var _base_color: Color

@onready var body_polygon: Polygon2D = $Body


func _ready() -> void:
	hp = max_hp
	_base_color = body_polygon.color


func _physics_process(delta: float) -> void:
	_touch_timer = maxf(_touch_timer - delta, 0.0)

	var player: Player = _get_player()
	if player == null:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var to_player: Vector2 = player.global_position - global_position
	velocity = to_player.normalized() * speed
	if to_player.length_squared() > 1.0:
		rotation = to_player.angle()
	move_and_slide()

	if _touch_timer <= 0.0:
		for i in get_slide_collision_count():
			if get_slide_collision(i).get_collider() == player:
				player.take_damage(contact_damage)
				_touch_timer = TOUCH_COOLDOWN
				break


func take_damage(amount: float) -> void:
	if hp <= 0.0:
		return
	hp -= amount
	_flash()
	if hp <= 0.0:
		died.emit(score_value)
		queue_free()


func _flash() -> void:
	body_polygon.color = Color.WHITE
	var tween: Tween = create_tween()
	tween.tween_property(body_polygon, "color", _base_color, 0.12)


func _get_player() -> Player:
	var nodes: Array[Node] = get_tree().get_nodes_in_group("player")
	if nodes.is_empty():
		return null
	return nodes[0] as Player
