class_name Bullet
extends Area2D

const SPEED: float = 800.0
const DAMAGE: float = 25.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	$Lifetime.timeout.connect(queue_free)


func _physics_process(delta: float) -> void:
	position += transform.x * SPEED * delta


func _on_body_entered(body: Node2D) -> void:
	if body is Enemy:
		body.take_damage(DAMAGE)
	queue_free()
