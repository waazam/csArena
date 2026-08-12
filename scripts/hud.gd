class_name Hud
extends CanvasLayer

const HEALTH_BAR_WIDTH: float = 200.0
const MAX_HP: float = 100.0

var _banner_tween: Tween

@onready var health_fill: ColorRect = $HealthBarBG/HealthBarFill
@onready var score_label: Label = $ScoreLabel
@onready var wave_label: Label = $WaveLabel
@onready var banner: Label = $WaveBanner


func set_health(hp: int) -> void:
	var ratio: float = clampf(hp / MAX_HP, 0.0, 1.0)
	health_fill.size = Vector2(HEALTH_BAR_WIDTH * ratio, health_fill.size.y)
	health_fill.color = Color(0.9, 0.25, 0.2) if hp <= 30 else Color(0.3, 0.85, 0.35)


func set_score(score: int) -> void:
	score_label.text = "Score: %d" % score


func set_wave(n: int) -> void:
	wave_label.text = "Wave %d" % n


func show_wave_banner(n: int) -> void:
	banner.text = "Wave %d" % n
	banner.modulate.a = 1.0
	banner.show()
	if _banner_tween and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_interval(2.0)
	_banner_tween.tween_property(banner, "modulate:a", 0.0, 0.6)
	_banner_tween.tween_callback(banner.hide)
