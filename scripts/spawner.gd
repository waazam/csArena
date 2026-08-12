class_name Spawner
extends Node2D

signal wave_started(wave: int)
signal enemy_killed(score_value: int)

const CHASER_SCENE: PackedScene = preload("res://scenes/enemy_chaser.tscn")
const SPRINTER_SCENE: PackedScene = preload("res://scenes/enemy_sprinter.tscn")
const SPAWN_INTERVAL: float = 0.5
const INTERMISSION: float = 3.0
const SPAWN_MARGIN: float = 48.0
const VIEW_SIZE: Vector2 = Vector2(1152, 648)
const HP_GROWTH: float = 1.1
const SPEED_GROWTH: float = 0.03
const SPEED_CAP: float = 1.6

var wave: int = 0
var _queue: Array[PackedScene] = []
var _alive: int = 0
var _stopped: bool = false

var _spawn_timer: Timer
var _wave_timer: Timer


func _ready() -> void:
	_spawn_timer = Timer.new()
	_spawn_timer.wait_time = SPAWN_INTERVAL
	_spawn_timer.timeout.connect(_spawn_next)
	add_child(_spawn_timer)

	_wave_timer = Timer.new()
	_wave_timer.one_shot = true
	_wave_timer.timeout.connect(_begin_spawning)
	add_child(_wave_timer)


func start() -> void:
	_start_next_wave()


func stop() -> void:
	_stopped = true
	_spawn_timer.stop()
	_wave_timer.stop()


func _start_next_wave() -> void:
	if _stopped:
		return
	wave += 1
	_queue = _compose_wave(wave)
	wave_started.emit(wave)
	_wave_timer.start(INTERMISSION)


func _begin_spawning() -> void:
	_spawn_next()
	if not _queue.is_empty():
		_spawn_timer.start()


func _compose_wave(n: int) -> Array[PackedScene]:
	var count: int = 4 + 2 * n
	var sprinter_share: float = minf(0.5, 0.1 * n)
	var sprinters: int = roundi(count * sprinter_share)
	var list: Array[PackedScene] = []
	for i in count:
		list.append(SPRINTER_SCENE if i < sprinters else CHASER_SCENE)
	list.shuffle()
	return list


func _spawn_next() -> void:
	if _stopped or _queue.is_empty():
		_spawn_timer.stop()
		return

	var scene: PackedScene = _queue.pop_back()
	var enemy: Enemy = scene.instantiate() as Enemy
	# Wave 1 uses base stats; each later wave scales up (speed bonus capped at +60%).
	enemy.max_hp *= pow(HP_GROWTH, wave - 1)
	enemy.speed *= minf(SPEED_CAP, 1.0 + SPEED_GROWTH * (wave - 1))
	enemy.position = _random_edge_position()
	enemy.died.connect(_on_enemy_died)
	_alive += 1
	get_parent().add_child(enemy)

	if _queue.is_empty():
		_spawn_timer.stop()


func _random_edge_position() -> Vector2:
	match randi() % 4:
		0:
			return Vector2(randf_range(0.0, VIEW_SIZE.x), -SPAWN_MARGIN)
		1:
			return Vector2(randf_range(0.0, VIEW_SIZE.x), VIEW_SIZE.y + SPAWN_MARGIN)
		2:
			return Vector2(-SPAWN_MARGIN, randf_range(0.0, VIEW_SIZE.y))
		_:
			return Vector2(VIEW_SIZE.x + SPAWN_MARGIN, randf_range(0.0, VIEW_SIZE.y))


func _on_enemy_died(value: int) -> void:
	_alive -= 1
	enemy_killed.emit(value)
	if not _stopped and _queue.is_empty() and _alive == 0:
		_start_next_wave()
