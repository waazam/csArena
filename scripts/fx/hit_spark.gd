extends CPUParticles2D
## One-shot bullet impact spark: 4-6 additive sparks flying opposite the
## bullet's travel direction, 0.15 s lifetime, frees itself when finished.
##
## Usage:
##   var spark := HIT_SPARK_SCENE.instantiate()
##   spark.global_position = impact_position
##   spark.setup(bullet_velocity, Color("FFE94A"))  # before or after add_child
##   parent.add_child(spark)

func _ready() -> void:
	one_shot = true
	emitting = true
	finished.connect(queue_free)

## travel_direction: the bullet's direction of travel (sparks fly back the
## other way). impact_color: #FFE94A for player bullets, #FF3B5C for enemy
## projectiles (match the owner).
func setup(travel_direction: Vector2, impact_color: Color = Color(1.0, 0.913725, 0.290196)) -> void:
	if travel_direction.length_squared() > 0.0:
		direction = -travel_direction.normalized()
	color = impact_color
