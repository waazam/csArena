extends Node2D
## One-shot muzzle flash: an 8 px hot-yellow star that scales 1.4 -> 0 over
## 0.05 s, then frees itself. Spawn at the muzzle position, rotated to the
## fire direction. The weapon/sprite that spawns this should also apply its
## own 2 px recoil kick (offset opposite the fire direction, eased back).

const DURATION := 0.05

func _ready() -> void:
	scale = Vector2(1.4, 1.4)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2.ZERO, DURATION)
	tween.tween_callback(queue_free)
