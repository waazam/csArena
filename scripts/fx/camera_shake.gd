extends Camera2D
class_name ShakeCamera
## Noise-driven camera shake with ~0.15 s decay. Attach to (or replace) the
## gameplay Camera2D, then call:
##   camera.shake_player_hit()  # 3-5 px kick when the player takes damage
##   camera.shake_kill()        # 1-2 px kick on an enemy kill
## or camera.add_trauma(amount 0..1) directly. Shake offset is applied via
## `offset`, so camera position/limits are untouched.

@export var max_offset := Vector2(5.0, 5.0)
## Trauma removed per second (1.0 / 0.15 s = full shake decays in ~0.15 s).
@export var decay := 6.7
@export var noise_speed := 60.0

var _trauma := 0.0
var _time := 0.0
var _noise := FastNoiseLite.new()

func _ready() -> void:
	_noise.seed = randi()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 0.7

func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)

func shake_player_hit() -> void:
	add_trauma(1.0)

func shake_kill() -> void:
	add_trauma(0.45)

func _process(delta: float) -> void:
	if _trauma <= 0.0:
		if offset != Vector2.ZERO:
			offset = Vector2.ZERO
		return
	_time += delta * noise_speed
	var amount := _trauma * _trauma
	offset = Vector2(
		max_offset.x * amount * _noise.get_noise_2d(_time, 0.0),
		max_offset.y * amount * _noise.get_noise_2d(0.0, _time)
	)
	_trauma = maxf(_trauma - decay * delta, 0.0)
