extends Node2D
## One-shot enemy death effect: 12-particle burst in the enemy's color plus
## an expanding ring (0 -> 24 px, fading over 0.25 s) and a brief hit-stop
## (Engine.time_scale 0.05 for 0.05 s of real time). Frees itself when the
## particle burst finishes.
##
## Usage:
##   var fx := ENEMY_DEATH_SCENE.instantiate()
##   fx.global_position = enemy.global_position
##   fx.setup(Color("FF3B5C"))          # or Color("FF9F1C") for elites
##   parent.add_child(fx)

const RING_MAX_RADIUS := 24.0
const RING_DURATION := 0.25
const RING_WIDTH := 2.0
const HIT_STOP_SCALE := 0.05
const HIT_STOP_DURATION := 0.05

## Enemy magenta-red by default; elites should pass amber #FF9F1C.
@export var fx_color: Color = Color(1.0, 0.231373, 0.360784)
## Disable if several enemies can die in the same frame and you only want
## one hit-stop (apply it once from gameplay code instead).
@export var apply_hit_stop: bool = true

var _ring_progress := 0.0

func _ready() -> void:
	var burst: CPUParticles2D = $Burst
	burst.color = fx_color
	burst.emitting = true
	burst.finished.connect(queue_free)

	if apply_hit_stop:
		Engine.time_scale = HIT_STOP_SCALE
		# Timer ignores time scale so the freeze lasts 0.05 s of real time.
		get_tree().create_timer(HIT_STOP_DURATION, true, false, true).timeout.connect(
			func() -> void: Engine.time_scale = 1.0
		)

	var tween := create_tween()
	tween.tween_method(_animate_ring, 0.0, 1.0, RING_DURATION)

## Call before add_child() so the burst picks up the color in _ready().
func setup(enemy_color: Color) -> void:
	fx_color = enemy_color

func _animate_ring(t: float) -> void:
	_ring_progress = t
	queue_redraw()

func _draw() -> void:
	if _ring_progress <= 0.0 or _ring_progress >= 1.0:
		return
	var col := fx_color
	col.a = 1.0 - _ring_progress
	draw_arc(Vector2.ZERO, RING_MAX_RADIUS * _ring_progress, 0.0, TAU, 32, col, RING_WIDTH, true)
