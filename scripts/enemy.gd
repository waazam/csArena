class_name Enemy
extends CharacterBody2D
## PvE bot: hunts the player, strafes at its weapon's preferred range, and
## fires with a handicap (slower, less accurate, reduced damage).

var peer_id := 0  # bullets read this; 0 = "not a player"
var hp := 60
var max_hp := 60
var speed := 190.0
var weapon_id := "glock"
var damage_scale := 0.55
var aim_angle := 0.0
var cooldown := 1.0
var shots_left := 0
var los_time := 0.0
var strafe_sign := 1.0
var strafe_timer := 0.0
var flash := 0.0
var hurt := 0.0
var body_color := Color(0.95, 0.3, 0.35)

func setup(w: String, hp_v: int, spd: float) -> void:
	weapon_id = w
	hp = hp_v
	max_hp = hp_v
	speed = spd
	shots_left = Weapons.DATA[w].mag

func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	z_index = 5
	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = 13.0
	cs.shape = sh
	add_child(cs)
	cooldown = randf_range(0.6, 1.3)
	aim_angle = randf() * TAU
	body_color = Color(0.95, randf_range(0.22, 0.38), randf_range(0.28, 0.44))

func _game():
	return get_tree().get_first_node_in_group("game")

func _physics_process(delta: float) -> void:
	flash = maxf(0.0, flash - delta)
	hurt = maxf(0.0, hurt - delta * 4.0)
	cooldown -= delta
	queue_redraw()
	var g = _game()
	if g == null or not g.can_play():
		velocity = Vector2.ZERO
		return
	var p = g.local_player()
	if p == null or not p.alive:
		velocity = Vector2.ZERO
		return

	var to_p: Vector2 = p.global_position - global_position
	var dist := to_p.length()
	var data: Dictionary = Weapons.DATA[weapon_id]
	var los := _has_los(p)

	if los:
		los_time += delta
		aim_angle = to_p.angle()
	else:
		los_time = 0.0
		if velocity.length() > 5.0:
			aim_angle = velocity.angle()

	strafe_timer -= delta
	if strafe_timer <= 0.0:
		strafe_sign = -1.0 if randf() < 0.5 else 1.0
		strafe_timer = randf_range(0.8, 1.8)

	var reach: float = data.reach
	var move: Vector2
	if los and dist <= reach:
		move = to_p.orthogonal().normalized() * strafe_sign
		if dist < reach * 0.55:
			move -= to_p.normalized() * 0.8
	else:
		move = to_p.normalized() + to_p.orthogonal().normalized() * strafe_sign * 0.25
	velocity = move.normalized() * speed
	move_and_slide()
	# Flip strafe early if we got wedged against a wall.
	if velocity.length() > 10.0 and get_real_velocity().length() < 15.0:
		strafe_sign *= -1.0
		strafe_timer = 0.5

	if los and los_time > 0.35 and dist < reach * 1.6 and cooldown <= 0.0 and shots_left > 0:
		_fire(data)
	if shots_left <= 0:
		shots_left = data.mag
		cooldown = data.reload * 1.5

func _fire(data: Dictionary) -> void:
	shots_left -= 1
	cooldown = data.interval * 1.6
	flash = 0.09
	var g = _game()
	if g == null:
		return
	var muzzle := global_position + Vector2.from_angle(aim_angle) * 10.0
	for i in data.pellets:
		var wobble: float = data.spread * 2.5 + 1.5
		var a: float = aim_angle + deg_to_rad(randf_range(-wobble, wobble))
		g.spawn_bullet(muzzle, a, weapon_id, self, "enemy", damage_scale)

func _has_los(p) -> bool:
	var params := PhysicsRayQueryParameters2D.create(
			global_position, p.global_position, 1)
	return get_world_2d().direct_space_state.intersect_ray(params).is_empty()

func receive_hit(dmg: int, _attacker_peer: int, dir: Vector2) -> void:
	hp -= dmg
	hurt = 1.0
	var g = _game()
	if g:
		g.gore.add_splat(global_position + dir * 6.0, randf_range(3.0, 7.0),
				Color(0.5, 0.06, 0.09, 0.85))
	if hp <= 0:
		if g:
			g.gore.add_corpse(global_position, body_color)
			g.on_enemy_died(self)
		queue_free()

func _draw() -> void:
	var col := body_color.lerp(Color.WHITE, hurt * 0.6)
	StickRender.draw_stick(self, aim_angle, weapon_id, col, flash, false, hp, max_hp, "")
