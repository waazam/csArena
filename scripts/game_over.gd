class_name GameOverScreen
extends CanvasLayer

@onready var stats_label: Label = $Box/StatsLabel
@onready var restart_button: Button = $Box/RestartButton


func _ready() -> void:
	visible = false
	restart_button.pressed.connect(_restart)


func show_game_over(score: int, wave: int) -> void:
	stats_label.text = "Score: %d   —   Wave %d" % [score, wave]
	visible = true


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("restart"):
		_restart()


func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
