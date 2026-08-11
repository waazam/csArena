extends Node2D
## Arena + mode orchestration. PvE: wave survival against bots.
## PvP: server-authoritative LAN/IP deathmatch, first to KILL_LIMIT frags.

const PlayerScript := preload("res://scripts/player.gd")
const EnemyScript := preload("res://scripts/enemy.gd")
const BulletScript := preload("res://scripts/bullet.gd")
const PickupScript := preload("res://scripts/pickup.gd")
const HudScript := preload("res://scripts/hud.gd")

const ARENA := Rect2(0, 0, 2400, 1600)
const KILL_LIMIT := 15
const MAX_ALIVE_ENEMIES := 10

const FLOOR_COLOR := Color(0.12, 0.11, 0.15)
const GRID_COLOR := Color(0.155, 0.145, 0.195)
const WALL_COLOR := Color(0.24, 0.22, 0.30)
const WALL_EDGE := Color(0.45, 0.40, 0.60)

const WALLS: Array[Rect2] = [
	# Border.
	Rect2(0, 0, 2400, 40), Rect2(0, 1560, 2400, 40),
	Rect2(0, 40, 40, 1520), Rect2(2360, 40, 40, 1520),
	# Center pillar.
	Rect2(1120, 720, 160, 160),
	# Four L-shaped rooms.
	Rect2(500, 260, 40, 360), Rect2(540, 260, 280, 40),
	Rect2(1860, 260, 40, 360), Rect2(1580, 260, 280, 40),
	Rect2(500, 980, 40, 360), Rect2(540, 1300, 280, 40),
	Rect2(1860, 980, 40, 360), Rect2(1580, 1300, 280, 40),
	# Crates / cover.
	Rect2(1000, 400, 80, 80), Rect2(1320, 400, 80, 80),
	Rect2(1000, 1120, 80, 80), Rect2(1320, 1120, 80, 80),
	Rect2(700, 760, 80, 80), Rect2(1620, 760, 80, 80),
]

const SPAWNS: Array[Vector2] = [
	Vector2(160, 160), Vector2(2240, 160), Vector2(160, 1440), Vector2(2240, 1440),
	Vector2(1200, 140), Vector2(1200, 1460), Vector2(140, 800), Vector2(2260, 800),
]

const WEAPON_SPOTS := [
	["mp5", Vector2(660, 660)], ["nova", Vector2(1740, 660)],
	["ak47", Vector2(1200, 330)], ["m4a4", Vector2(1200, 1270)],
	["awp", Vector2(1200, 960)],
	["usp", Vector2(660, 940)], ["mp5", Vector2(1740, 940)],
]
const MEDKIT_SPOTS := [Vector2(300, 800), Vector2(2100, 800), Vector2(1200, 560)]

var running := true
var match_over := false
var wave := 0
var score := 0
var wave_break := 0.0
var spawn_timer := 0.0
var enemies_to_spawn := 0
var enemies_alive := 0
var kills := {}  # PvP: peer_id -> frags

var walls_node: Node2D
var gore: Gore
var pickups: Node2D
var actors: Node2D
var bullets: Node2D
var hud  # hud.gd instance (untyped: we call its custom methods dynamically)

func _ready() -> void:
	add_to_group("game")
	randomize()
	_build_world()
	gore = Gore.new()
	add_child(gore)
	pickups = Node2D.new()
	pickups.name = "Pickups"
	add_child(pickups)
	actors = Node2D.new()
	actors.name = "Actors"
	add_child(actors)
	bullets = Node2D.new()
	bullets.name = "Bullets"
	add_child(bullets)
	add_child(Crosshair.new())
	hud = HudScript.new()
	hud.name = "HUD"
	add_child(hud)
	hud.retry_pressed.connect(func() -> void: get_tree().reload_current_scene())
	hud.menu_pressed.connect(func() -> void: Net.leave_to_menu())
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_place_pickups()
	if Net.mode == Net.MODE_PVP:
		_setup_pvp()
	else:
		net_spawn_player(1, SPAWNS[0], 0)
		wave_break = 2.0
		hud.flash_message("SURVIVE THE WAVES")

func can_play() -> bool:
	return running and not match_over

func local_player() -> Player:
	return actors.get_node_or_null("Player_%d" % multiplayer.get_unique_id()) as Player

func _process(delta: float) -> void:
	if Net.mode == Net.MODE_PVE and running:
		_pve_tick(delta)
	hud.update_hud(self)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and \
			(event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE):
		Net.leave_to_menu()

# ---------------------------------------------------------------- world

func _build_world() -> void:
	walls_node = Node2D.new()
	walls_node.name = "Walls"
	add_child(walls_node)
	for r in WALLS:
		var body := StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = r.position + r.size / 2.0
		var cs := CollisionShape2D.new()
		var sh := RectangleShape2D.new()
		sh.size = r.size
		cs.shape = sh
		body.add_child(cs)
		walls_node.add_child(body)

func _draw() -> void:
	draw_rect(ARENA, FLOOR_COLOR)
	var x := ARENA.position.x
	while x <= ARENA.end.x:
		draw_line(Vector2(x, ARENA.position.y), Vector2(x, ARENA.end.y), GRID_COLOR, 1.0)
		x += 100.0
	var y := ARENA.position.y
	while y <= ARENA.end.y:
		draw_line(Vector2(ARENA.position.x, y), Vector2(ARENA.end.x, y), GRID_COLOR, 1.0)
		y += 100.0
	for r in WALLS:
		draw_rect(r, WALL_COLOR)
		draw_rect(r, WALL_EDGE, false, 2.0)

func _place_pickups() -> void:
	var i := 0
	for spot in WEAPON_SPOTS:
		_make_pickup("weapon", spot[0], spot[1], true, "Pickup_%d" % i)
		i += 1
	for m in MEDKIT_SPOTS:
		_make_pickup("medkit", "", m, true, "Pickup_%d" % i)
		i += 1

func _make_pickup(kind: String, wid: String, pos: Vector2, respawns: bool, node_name := "") -> void:
	var pk = PickupScript.new()
	if node_name != "":
		pk.name = node_name
	pk.kind = kind
	pk.weapon_id = wid
	pk.respawns = respawns
	pk.position = pos
	pickups.add_child(pk)

func spawn_bullet(pos: Vector2, angle: float, wid: String, shooter, group: String, dmg_scale := 1.0) -> void:
	var data: Dictionary = Weapons.DATA[wid]
	var b = BulletScript.new()
	b.position = pos
	b.dir = Vector2.from_angle(angle)
	b.speed = data.speed
	b.damage = maxi(1, int(round(data.damage * dmg_scale)))
	b.shooter_rid = shooter.get_rid()
	b.shooter_peer = shooter.peer_id
	b.source_group = group
	bullets.add_child(b)

# ---------------------------------------------------------------- players

@rpc("any_peer", "call_local", "reliable")
func net_spawn_player(pid: int, pos: Vector2, color_idx: int) -> void:
	if actors.has_node("Player_%d" % pid):
		return
	var p = PlayerScript.new()
	p.name = "Player_%d" % pid
	p.peer_id = pid
	p.color_index = color_idx
	p.position = pos
	p.set_multiplayer_authority(pid)
	actors.add_child(p)

@rpc("any_peer", "call_local", "reliable")
func net_remove_player(pid: int) -> void:
	var n := actors.get_node_or_null("Player_%d" % pid)
	if n:
		n.queue_free()

## Server-side: called by Player.receive_hit when someone dies.
func on_player_killed(victim: Player, attacker_peer: int) -> void:
	if Net.mode != Net.MODE_PVP:
		_pve_game_over()
		return
	if attacker_peer != victim.peer_id and kills.has(attacker_peer):
		kills[attacker_peer] += 1
	rpc("net_set_scores", kills)
	rpc("net_announce", "P%d fragged P%d" % [attacker_peer, victim.peer_id])
	if kills.get(attacker_peer, 0) >= KILL_LIMIT and not match_over:
		rpc("net_end_match", attacker_peer)
		get_tree().create_timer(5.0).timeout.connect(_reset_match)
		return
	var vid := victim.peer_id
	get_tree().create_timer(3.0).timeout.connect(func() -> void:
		if not is_instance_valid(self) or match_over:
			return
		var n := actors.get_node_or_null("Player_%d" % vid)
		if n:
			n.rpc("net_respawn", _pick_spawn())
	)

func _pick_spawn() -> Vector2:
	var best: Vector2 = SPAWNS[randi() % SPAWNS.size()]
	var best_d := -1.0
	for i in 3:
		var cand: Vector2 = SPAWNS[randi() % SPAWNS.size()]
		var d := INF
		for child in actors.get_children():
			if child is Player and child.alive:
				d = minf(d, cand.distance_to(child.global_position))
		if d > best_d:
			best_d = d
			best = cand
	return best

# ---------------------------------------------------------------- PvE waves

func _pve_tick(delta: float) -> void:
	if wave_break > 0.0:
		wave_break -= delta
		if wave_break <= 0.0:
			_begin_wave()
		return
	if enemies_to_spawn > 0:
		spawn_timer -= delta
		if spawn_timer <= 0.0 and enemies_alive < MAX_ALIVE_ENEMIES:
			_spawn_enemy()
			enemies_to_spawn -= 1
			enemies_alive += 1
			spawn_timer = 0.9
	elif enemies_alive <= 0:
		score += wave * 100
		var p := local_player()
		if p and p.alive:
			p.rpc("net_heal", 25)
		hud.flash_message("WAVE %d CLEARED  +%d" % [wave, wave * 100])
		wave_break = 3.0

func _begin_wave() -> void:
	wave += 1
	enemies_to_spawn = mini(3 + wave * 2, 26)
	spawn_timer = 0.0
	hud.flash_message("WAVE %d" % wave)

func _wave_weapons() -> Array:
	if wave <= 1:
		return ["glock"]
	if wave == 2:
		return ["glock", "usp"]
	if wave == 3:
		return ["usp", "mp5"]
	if wave == 4:
		return ["mp5", "nova"]
	if wave == 5:
		return ["mp5", "ak47", "nova"]
	var pool := ["ak47", "m4a4", "nova", "mp5"]
	if randf() < 0.2:
		pool.append("awp")
	return pool

func _spawn_enemy() -> void:
	var p := local_player()
	var far: Array[Vector2] = []
	var fallback: Vector2 = SPAWNS[0]
	var fd := -1.0
	for s in SPAWNS:
		var d := s.distance_to(p.global_position) if p != null else 9999.0
		if d > fd:
			fd = d
			fallback = s
		if d > 600.0:
			far.append(s)
	var pos: Vector2 = far.pick_random() if not far.is_empty() else fallback
	pos += Vector2(randf_range(-50, 50), randf_range(-50, 50))
	var e = EnemyScript.new()
	e.setup(_wave_weapons().pick_random(),
			mini(40 + wave * 12, 160), minf(170.0 + wave * 10.0, 265.0))
	e.position = pos
	actors.add_child(e)

func on_enemy_died(e) -> void:
	enemies_alive -= 1
	score += 50 + wave * 10
	var r := randf()
	if r < 0.20:
		_make_pickup("weapon", e.weapon_id, e.global_position, false)
	elif r < 0.32:
		_make_pickup("medkit", "", e.global_position, false)

func _pve_game_over() -> void:
	running = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_overlay("YOU DIED",
			"score %d — reached wave %d" % [score, wave], "RETRY")

# ---------------------------------------------------------------- PvP

func _setup_pvp() -> void:
	if multiplayer.is_server():
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		kills[1] = 0
		net_spawn_player(1, _pick_spawn(), 0)
		hud.flash_message("PVP — FIRST TO %d FRAGS" % KILL_LIMIT)
	else:
		rpc_id(1, "net_request_spawn")

@rpc("any_peer", "reliable")
func net_request_spawn() -> void:
	if not multiplayer.is_server():
		return
	var pid := multiplayer.get_remote_sender_id()
	# Bring the newcomer up to date, then broadcast their spawn.
	for child in actors.get_children():
		if child is Player:
			rpc_id(pid, "net_spawn_player", child.peer_id, child.global_position, child.color_index)
	kills[pid] = 0
	rpc("net_spawn_player", pid, _pick_spawn(), kills.size() - 1)
	rpc("net_set_scores", kills)
	rpc("net_announce", "P%d joined — first to %d frags" % [pid, KILL_LIMIT])

func _on_peer_disconnected(pid: int) -> void:
	kills.erase(pid)
	rpc("net_remove_player", pid)
	rpc("net_set_scores", kills)
	rpc("net_announce", "P%d left" % pid)

@rpc("any_peer", "call_local", "reliable")
func net_set_scores(d: Dictionary) -> void:
	kills = d

@rpc("any_peer", "call_local", "reliable")
func net_announce(text: String) -> void:
	hud.flash_message(text)

@rpc("any_peer", "call_local", "reliable")
func net_end_match(winner: int) -> void:
	match_over = true
	hud.flash_message("PLAYER %d WINS THE MATCH" % winner, 4.5)

@rpc("any_peer", "call_local", "reliable")
func net_reset_match() -> void:
	match_over = false
	hud.flash_message("NEW ROUND — FIRST TO %d" % KILL_LIMIT)

func _reset_match() -> void:
	if not is_instance_valid(self) or not multiplayer.is_server():
		return
	for k in kills.keys():
		kills[k] = 0
	rpc("net_set_scores", kills)
	rpc("net_reset_match")
	for child in actors.get_children():
		if child is Player:
			child.rpc("net_respawn", _pick_spawn())

# ---------------------------------------------------------------- helpers

class Gore extends Node2D:
	## Persistent blood splats + sprawled stick corpses, Hotline Miami style.
	var splats: Array = []
	var corpses: Array = []

	func _ready() -> void:
		z_index = 1

	func add_splat(pos: Vector2, r: float, col: Color) -> void:
		splats.append({pos = pos, r = r, col = col})
		if splats.size() > 500:
			splats.pop_front()
		queue_redraw()

	func add_corpse(pos: Vector2, col: Color) -> void:
		corpses.append({pos = pos, col = col.darkened(0.35), rot = randf() * TAU})
		if corpses.size() > 80:
			corpses.pop_front()
		for i in 5:
			add_splat(pos + Vector2(randf_range(-18, 18), randf_range(-18, 18)),
					randf_range(4, 11), Color(0.42, 0.05, 0.08, 0.85))
		queue_redraw()

	func _draw() -> void:
		for s in splats:
			draw_circle(s.pos, s.r, s.col)
		for c in corpses:
			var v: Vector2 = Vector2.from_angle(c.rot)
			draw_line(c.pos - v * 6.0, c.pos + v * 8.0, c.col, 8.0)
			draw_circle(c.pos + v * 14.0, 9.0, c.col)
			for i in 4:
				var limb: Vector2 = Vector2.from_angle(c.rot + 2.0 + i * 1.35) * 16.0
				draw_line(c.pos, c.pos + limb, c.col, 4.0)

class Crosshair extends Node2D:
	func _ready() -> void:
		z_index = 100

	func _process(_delta: float) -> void:
		position = get_global_mouse_position()

	func _draw() -> void:
		var c := Color(1, 1, 1, 0.9)
		draw_arc(Vector2.ZERO, 7.0, 0, TAU, 24, c, 1.5)
		for i in 4:
			var v := Vector2.RIGHT.rotated(i * TAU / 4.0)
			draw_line(v * 4.0, v * 10.0, c, 1.5)
