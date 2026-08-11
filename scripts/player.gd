class_name Player
extends CharacterBody2D
## A stick-figure combatant. Driven by input on its multiplayer-authority peer;
## remote instances interpolate RPC'd state. Works identically offline in PvE
## (the default OfflineMultiplayerPeer runs call_local RPCs locally).

const MAX_HP := 100
const SPEED := 270.0
const COLORS: Array[Color] = [
	Color(0.40, 0.85, 1.00), Color(1.00, 0.62, 0.25), Color(0.55, 1.00, 0.55),
	Color(0.85, 0.55, 1.00), Color(1.00, 0.90, 0.35), Color(1.00, 0.45, 0.55),
	Color(0.60, 0.75, 1.00), Color(0.75, 1.00, 0.85),
]

var peer_id := 1
var color_index := 0
var hp := MAX_HP
var alive := true
var aim_angle := 0.0
var weapon_id := "glock"
var mag := 0
var reserve := 0
var reloading := false
var reload_left := 0.0
var cooldown := 0.0
var trigger_prev := false
var flash := 0.0
var shake := 0.0
var net_pos := Vector2.ZERO
var cam: Camera2D
# --- cosmetic-only state (never read by gameplay logic) ---
var walk_phase := 0.0    # advances with distance travelled, drives feet/hands
var stride := 0.0        # 0..1 smoothed "how fast am I moving"
var display_aim := 0.0   # smoothed aim used only for drawing remote players
var prev_pos := Vector2.ZERO
var light: PointLight2D
var last_dry := 0       # msec of last dry-fire click (rate limit, cosmetic)
var last_step := 0      # walk-cycle step index for footstep sounds (cosmetic)

func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 2
	collision_mask = 1 | 2 | 4
	z_index = 5
	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = 13.0
	cs.shape = sh
	add_child(cs)
	give_weapon("glock")
	net_pos = position
	prev_pos = position
	display_aim = aim_angle
	if peer_id == multiplayer.get_unique_id():
		# Personal light: brightens the area around you and pulses on muzzle
		# flash; walls carry occluders so it throws real 2D shadows.
		light = PointLight2D.new()
		light.texture = _make_light_tex()
		light.texture_scale = 4.2
		light.energy = 1.05
		light.color = Color(1.0, 0.97, 0.92)
		light.shadow_enabled = true
		light.shadow_filter = PointLight2D.SHADOW_FILTER_PCF5
		light.shadow_filter_smooth = 2.0
		add_child(light)
		cam = Camera2D.new()
		cam.position_smoothing_enabled = true
		cam.position_smoothing_speed = 8.0
		var g = _game()
		if g:
			cam.limit_left = int(g.ARENA.position.x)
			cam.limit_top = int(g.ARENA.position.y)
			cam.limit_right = int(g.ARENA.end.x)
			cam.limit_bottom = int(g.ARENA.end.y)
		add_child(cam)
		cam.make_current()

func _game():
	return get_tree().get_first_node_in_group("game")

func _physics_process(delta: float) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	flash = maxf(0.0, flash - delta)
	if reloading:
		reload_left -= delta
		if reload_left <= 0.0:
			_finish_reload()
	if is_multiplayer_authority():
		_local_tick(delta)
		display_aim = aim_angle
	else:
		position = position.lerp(net_pos, minf(1.0, delta * 14.0))
		# Smooth the *drawn* aim only; aim_angle itself stays authoritative.
		display_aim = lerp_angle(display_aim, aim_angle, minf(1.0, delta * 16.0))
	# Walk-cycle bookkeeping (cosmetic).
	var moved := (position - prev_pos).length()
	prev_pos = position
	stride = lerpf(stride, clampf((moved / maxf(delta, 0.0001)) / SPEED, 0.0, 1.0),
			minf(1.0, delta * 10.0))
	walk_phase += moved * 0.05
	# Quiet footsteps for the local player only, on each half-stride.
	if cam and alive and stride > 0.4:
		var step_i := int(walk_phase / PI)
		if step_i != last_step:
			last_step = step_i
			Sfx.play("footstep", -20.0, 0.15)
	if light:
		light.energy = (1.05 + flash * 9.0) * (1.0 if alive else 0.35)
	queue_redraw()

func _local_tick(delta: float) -> void:
	var g = _game()
	var can: bool = alive and g != null and g.can_play()
	var dir := Vector2.ZERO
	if can:
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			dir.y -= 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			dir.y += 1.0
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			dir.x -= 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			dir.x += 1.0
	velocity = dir.normalized() * SPEED if dir != Vector2.ZERO else Vector2.ZERO
	move_and_slide()
	if can:
		aim_angle = (get_global_mouse_position() - global_position).angle()
		_handle_trigger()
		if Input.is_key_pressed(KEY_R):
			start_reload()
	if cam:
		shake = maxf(0.0, shake - delta * 30.0)
		cam.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake
	if Net.online:
		rpc("net_state", position, aim_angle, Weapons.ORDER.find(weapon_id))

func _handle_trigger() -> void:
	var pressed := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var data: Dictionary = Weapons.DATA[weapon_id]
	var want: bool = pressed if data.auto else (pressed and not trigger_prev)
	if want and cooldown <= 0.0 and not reloading:
		if mag <= 0:
			if Time.get_ticks_msec() - last_dry > 250:
				last_dry = Time.get_ticks_msec()
				Sfx.play("dry", -8.0)
			start_reload()
		else:
			_fire(data)
	trigger_prev = pressed

func _fire(data: Dictionary) -> void:
	mag -= 1
	cooldown = data.interval
	flash = 0.09
	shake += data.recoil
	var angles := PackedFloat32Array()
	for i in data.pellets:
		angles.append(aim_angle + deg_to_rad(randf_range(-data.spread, data.spread)))
	_spawn_shots(angles)
	if Net.online:
		rpc("net_shoot", angles)

func _spawn_shots(angles: PackedFloat32Array) -> void:
	var g = _game()
	if g == null:
		return
	# Start at the body so point-blank shots can't skip past a wall.
	var muzzle := global_position + Vector2.from_angle(aim_angle) * 10.0
	for a in angles:
		g.spawn_bullet(muzzle, a, weapon_id, self, "player", 1.0)
	g.fx.eject_shell(global_position, aim_angle, weapon_id)
	# Runs on every peer (local fire + net_shoot), so shots are audible for all.
	Sfx.play_at("shot_" + weapon_id, global_position)

func start_reload() -> void:
	var data: Dictionary = Weapons.DATA[weapon_id]
	if reloading or reserve <= 0 or mag >= data.mag:
		return
	reloading = true
	reload_left = data.reload
	Sfx.play("reload_start", -8.0)

func _finish_reload() -> void:
	reloading = false
	var data: Dictionary = Weapons.DATA[weapon_id]
	var take: int = mini(data.mag - mag, reserve)
	mag += take
	reserve -= take
	Sfx.play("reload_end", -8.0)

func give_weapon(id: String) -> void:
	var data: Dictionary = Weapons.DATA[id]
	weapon_id = id
	mag = data.mag
	reserve = data.reserve
	reloading = false
	cooldown = 0.0

## Server-only entry point (bullets call this on the server instance).
func receive_hit(dmg: int, attacker_peer: int, dir: Vector2) -> void:
	if not alive:
		return
	hp = maxi(0, hp - dmg)
	rpc("net_health_fx", hp, global_position + dir * 8.0)
	if hp <= 0:
		rpc("net_die", attacker_peer)
		var g = _game()
		if g:
			g.on_player_killed(self, attacker_peer)

@rpc("authority", "call_remote", "unreliable_ordered")
func net_state(pos: Vector2, aim: float, widx: int) -> void:
	net_pos = pos
	aim_angle = aim
	var id: String = Weapons.ORDER[clampi(widx, 0, Weapons.ORDER.size() - 1)]
	if id != weapon_id:
		weapon_id = id

@rpc("authority", "call_remote", "reliable")
func net_shoot(angles: PackedFloat32Array) -> void:
	flash = 0.09
	_spawn_shots(angles)

@rpc("any_peer", "call_local", "reliable")
func net_health_fx(new_hp: int, splat_pos: Vector2) -> void:
	hp = new_hp
	var g = _game()
	if g:
		g.gore.add_spray(global_position, splat_pos - global_position)
	if cam:
		Sfx.play("hit_flesh", -2.0)  # heavier when it's you
		shake += 3.0
		if g:
			g.hud.hit_flash(0.5)
	else:
		Sfx.play_at("hit_flesh", global_position, -6.0)

@rpc("any_peer", "call_local", "reliable")
func net_die(_attacker_peer: int) -> void:
	if not alive:
		return
	alive = false
	hp = 0
	velocity = Vector2.ZERO
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 1)
	var g = _game()
	Sfx.play_at("death", global_position, -2.0)
	if g:
		g.gore.add_corpse(global_position, COLORS[color_index % COLORS.size()])
		g.fx.death_burst(global_position, COLORS[color_index % COLORS.size()])
	if cam and g:
		g.hud.hit_flash(0.85)
		shake += 6.0
	if is_multiplayer_authority() and Net.online and g:
		g.hud.flash_message("RESPAWNING…")

@rpc("any_peer", "call_local", "reliable")
func net_respawn(pos: Vector2) -> void:
	global_position = pos
	net_pos = pos
	hp = MAX_HP
	alive = true
	set_deferred("collision_layer", 2)
	set_deferred("collision_mask", 1 | 2 | 4)
	give_weapon("glock")

@rpc("any_peer", "call_local", "reliable")
func net_give_weapon(id: String) -> void:
	give_weapon(id)
	Sfx.play_at("pickup_weapon", global_position, -6.0)

@rpc("any_peer", "call_local", "reliable")
func net_heal(amount: int) -> void:
	hp = mini(MAX_HP, hp + amount)
	Sfx.play_at("pickup_health", global_position, -6.0)

func _make_light_tex() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 256
	tex.height = 256
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	return tex

func _draw() -> void:
	if not alive:
		return
	var tag := ("P%d" % peer_id) if Net.online else ""
	var rf := -1.0
	if reloading:
		var data: Dictionary = Weapons.DATA[weapon_id]
		rf = clampf(1.0 - reload_left / data.reload, 0.0, 1.0)
	StickRender.draw_stick(self, display_aim, weapon_id,
			COLORS[color_index % COLORS.size()], flash, reloading, hp, MAX_HP, tag,
			walk_phase, stride, peer_id == multiplayer.get_unique_id(), rf)
