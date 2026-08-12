extends Node2D

const SHAKE_ON_HIT: float = 8.0
const SHAKE_DECAY: float = 40.0

var score: int = 0
var current_wave: int = 0
var _shake_strength: float = 0.0

@onready var player: Player = $Player
@onready var spawner: Spawner = $Spawner
@onready var hud: Hud = $HUD
@onready var game_over: GameOverScreen = $GameOver
@onready var camera: Camera2D = $Camera2D


func _ready() -> void:
	player.health_changed.connect(hud.set_health)
	player.damaged.connect(_on_player_damaged)
	player.died.connect(_on_player_died)
	spawner.enemy_killed.connect(_on_enemy_killed)
	spawner.wave_started.connect(_on_wave_started)

	hud.set_health(player.hp)
	hud.set_score(score)
	spawner.start()


func _process(delta: float) -> void:
	if _shake_strength > 0.0:
		_shake_strength = maxf(_shake_strength - SHAKE_DECAY * delta, 0.0)
		camera.offset = Vector2(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)
		) * _shake_strength
	else:
		camera.offset = Vector2.ZERO


func _on_enemy_killed(value: int) -> void:
	score += value
	hud.set_score(score)


func _on_wave_started(n: int) -> void:
	current_wave = n
	hud.set_wave(n)
	hud.show_wave_banner(n)


func _on_player_damaged() -> void:
	_shake_strength = SHAKE_ON_HIT


func _on_player_died() -> void:
	_shake_strength = 0.0
	camera.offset = Vector2.ZERO
	spawner.stop()
	game_over.show_game_over(score, current_wave)
	get_tree().paused = true
