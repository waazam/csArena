extends Node2D
## Arena + mode orchestration. PvE: wave survival against bots.
## PvP: server-authoritative LAN/IP deathmatch, first to KILL_LIMIT frags.

const PlayerScript := preload("res://scripts/player.gd")
const EnemyScript := preload("res://scripts/enemy.gd")
const BulletScript := preload("res://scripts/bullet.gd")
const PickupScript := preload("res://scripts/pickup.gd")
const HudScript := preload("res://scripts/hud.gd")
const FxScript := preload("res://scripts/fx.gd")

const ARENA := Rect2(0, 0, 2400, 1600)
const KILL_LIMIT := 15
const MAX_ALIVE_ENEMIES := 10

const FLOOR_COLOR := Color(0.065, 0.06, 0.105)
const GRID_COLOR := Color(0.40, 0.45, 0.70, 0.06)
const WALL_COLOR := Color(0.17, 0.16, 0.24)
const WALL_EDGE := Color(0.55, 0.50, 0.80, 0.8)
const AMBIENT := Color(0.76, 0.76, 0.88)

## Cosmetic per-room floor tints (neon-noir zoning). Deterministic, static.
const ZONES := [
	[Rect2(40, 40, 780, 580), Color(0.20, 0.75, 1.00, 0.045)],   # NW — cyan
	[Rect2(1580, 40, 780, 580), Color(1.00, 0.30, 0.75, 0.040)], # NE — magenta
	[Rect2(40, 980, 780, 580), Color(1.00, 0.70, 0.25, 0.038)],  # SW — amber
	[Rect2(1580, 980, 780, 580), Color(0.55, 0.40, 1.00, 0.050)],# SE — violet
	[Rect2(1000, 620, 400, 360), Color(0.30, 1.00, 0.60, 0.040)],# center — green
]

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
var fx  # FxLayer (scripts/fx.gd) — cosmetic sparks / shells / rings
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
	fx = FxScript.new()
	fx.name = "Fx"
	add_child(fx)
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
	# Subtle ambient darkening; the local player carries a PointLight2D.
	var cm := CanvasModulate.new()
	cm.color = AMBIENT
	add_child(cm)
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
		# Light occluder so the player's light throws wall shadows.
		var occ := LightOccluder2D.new()
		var poly := OccluderPolygon2D.new()
		var hx := r.size.x / 2.0
		var hy := r.size.y / 2.0
		poly.polygon = PackedVector2Array([
			Vector2(-hx, -hy), Vector2(hx, -hy), Vector2(hx, hy), Vector2(-hx, hy)])
		occ.occluder = poly
		body.add_child(occ)
		walls_node.add_child(body)

## Deterministic 2D hash -> [0,1]. Same on every peer (pure function of ints),
## so cosmetic floor variation can never diverge between clients.
func _hash01(ix: int, iy: int) -> float:
	var h := ix * 374761393 + iy * 668265263 + 1442695040888963407
	h = (h ^ (h >> 13)) * 1274126177
	return float((h ^ (h >> 16)) & 0xFFFF) / 65535.0

func _wall_accent(r: Rect2) -> Color:
	if r.size == Vector2(80, 80):
		return Color(1.0, 0.7, 0.2, 0.45)      # crates — amber
	if r.size == Vector2(160, 160):
		return Color(0.45, 0.95, 1.0, 0.55)    # center pillar — cyan
	return Color(0.62, 0.50, 1.0, 0.30)        # walls — violet

func _draw() -> void:
	# Out-of-bounds apron + floor base.
	draw_rect(ARENA.grow(80), Color(0.02, 0.02, 0.04))
	draw_rect(ARENA, FLOOR_COLOR)
	# Tiles: checker + deterministic per-tile brightness variation.
	var ts := 100
	for iy in range(int(ARENA.size.y) / ts):
		for ix in range(int(ARENA.size.x) / ts):
			var a := 0.05 * _hash01(ix, iy) + (0.045 if (ix + iy) % 2 == 0 else 0.0)
			if a > 0.004:
				draw_rect(Rect2(ix * ts, iy * ts, ts, ts), Color(0.50, 0.55, 0.90, a))
	# Per-room neon tint zones with a thin trim.
	for z in ZONES:
		var zr: Rect2 = z[0]
		var zc: Color = z[1]
		draw_rect(zr, zc)
		draw_rect(zr, Color(zc.r, zc.g, zc.b, 0.22), false, 2.0)
	# Grid.
	var x := ARENA.position.x
	while x <= ARENA.end.x:
		draw_line(Vector2(x, ARENA.position.y), Vector2(x, ARENA.end.y), GRID_COLOR, 1.0)
		x += 100.0
	var y := ARENA.position.y
	while y <= ARENA.end.y:
		draw_line(Vector2(ARENA.position.x, y), Vector2(ARENA.end.x, y), GRID_COLOR, 1.0)
		y += 100.0
	# Deterministic scuff marks for grime.
	for i in 70:
		var hx := _hash01(i, 7)
		var hy := _hash01(i, 13)
		var ha := _hash01(i, 29)
		var p := ARENA.position + Vector2(hx * ARENA.size.x, hy * ARENA.size.y)
		var v := Vector2.from_angle(ha * TAU)
		draw_line(p - v * (6.0 + ha * 14.0), p + v * (6.0 + hx * 14.0),
				Color(0, 0, 0, 0.10 + hy * 0.08), 2.0)
	# Floor markings: ring around the center pillar, pads at spawn points.
	draw_arc(Vector2(1200, 800), 150.0, 0, TAU, 64, Color(0.45, 0.95, 1.0, 0.10), 3.0)
	for s in SPAWNS:
		draw_arc(s, 24.0, 0, TAU, 24, Color(0.45, 0.95, 1.0, 0.14), 2.0)
		draw_line(s + Vector2(-10, 0), s + Vector2(10, 0), Color(0.45, 0.95, 1.0, 0.12), 2.0)
		draw_line(s + Vector2(0, -10), s + Vector2(0, 10), Color(0.45, 0.95, 1.0, 0.12), 2.0)
	# Wall drop shadows (fake height), then wall bodies.
	for r in WALLS:
		draw_rect(Rect2(r.position + Vector2(6, 9), r.size), Color(0, 0, 0, 0.38))
	for r in WALLS:
		draw_rect(r, WALL_COLOR)
		draw_rect(r.grow(-5), WALL_COLOR.lightened(0.07))
		# Top-edge highlight / bottom-edge shade for fake depth.
		draw_line(r.position + Vector2(1, 1), r.position + Vector2(r.size.x - 1, 1), WALL_EDGE, 2.5)
		draw_line(r.position + Vector2(1, 1), r.position + Vector2(1, r.size.y - 1),
				Color(WALL_EDGE.r, WALL_EDGE.g, WALL_EDGE.b, 0.4), 2.0)
		draw_line(r.position + Vector2(1, r.size.y - 1), r.position + r.size - Vector2(1, 1),
				Color(0, 0, 0, 0.45), 2.5)
		draw_line(r.position + Vector2(r.size.x - 1, 1), r.position + r.size - Vector2(1, 1),
				Color(0, 0, 0, 0.35), 2.0)
		# Colored accent trim.
		draw_rect(r.grow(-3), _wall_accent(r), false, 1.5)
		# Crates get a cross-brace so they read as crates.
		if r.size == Vector2(80, 80):
			draw_line(r.position + Vector2(6, 6), r.end - Vector2(6, 6), Color(0, 0, 0, 0.30), 3.0)
			draw_line(Vector2(r.end.x - 6, r.position.y + 6),
					Vector2(r.position.x + 6, r.end.y - 6), Color(0, 0, 0, 0.30), 3.0)

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
	var wc: Color = data.color
	b.color = wc.lerp(Color(1.0, 0.95, 0.75), 0.6)  # hot tracer tinted per weapon
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
		Sfx.play("wave_clear", -6.0, 0.0)
		wave_break = 3.0

func _begin_wave() -> void:
	wave += 1
	enemies_to_spawn = mini(3 + wave * 2, 26)
	spawn_timer = 0.0
	hud.flash_message("WAVE %d" % wave)
	Sfx.play("wave_start", -6.0, 0.0)

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
	Sfx.play("game_over", -4.0, 0.0)
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
	# Frag confirm for the local killer (read-only compare, no state change).
	var me := multiplayer.get_unique_id()
	if int(d.get(me, 0)) > int(kills.get(me, 0)):
		Sfx.play("frag", -4.0)
	kills = d

@rpc("any_peer", "call_local", "reliable")
func net_announce(text: String) -> void:
	hud.flash_message(text)
	Sfx.play("announce", -10.0)

@rpc("any_peer", "call_local", "reliable")
func net_end_match(winner: int) -> void:
	match_over = true
	hud.flash_message("PLAYER %d WINS THE MATCH" % winner, 4.5)
	if winner == multiplayer.get_unique_id():
		Sfx.play("win", -4.0, 0.0)
	else:
		Sfx.play("game_over", -6.0, 0.0)

@rpc("any_peer", "call_local", "reliable")
func net_reset_match() -> void:
	match_over = false
	hud.flash_message("NEW ROUND — FIRST TO %d" % KILL_LIMIT)
	Sfx.play("wave_start", -8.0, 0.0)

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
	## Persistent blood splats + sprawled stick corpses over dark pools.
	var splats: Array = []
	var corpses: Array = []

	func _ready() -> void:
		z_index = 1

	func add_splat(pos: Vector2, r: float, col: Color) -> void:
		splats.append({pos = pos, r = r, col = col})
		if splats.size() > 500:
			splats.pop_front()
		queue_redraw()

	## Directional spray: droplets fan out along the hit direction, shrinking
	## with distance, plus a couple of trailing drips. Purely cosmetic.
	func add_spray(pos: Vector2, dir: Vector2) -> void:
		var n := dir.normalized() if dir.length() > 0.01 else Vector2.from_angle(randf() * TAU)
		add_splat(pos, randf_range(3.5, 6.0), Color(0.5, 0.06, 0.09, 0.85))
		for i in 5:
			var d := randf_range(8.0, 42.0)
			var p := pos + n.rotated(randf_range(-0.45, 0.45)) * d
			add_splat(p, maxf(1.2, randf_range(4.5, 7.5) - d * 0.12),
					Color(randf_range(0.40, 0.55), 0.05, 0.09, randf_range(0.5, 0.85)))
		for i in 2:
			add_splat(pos + Vector2(randf_range(-10, 10), randf_range(-10, 10)),
					randf_range(1.5, 2.5), Color(0.45, 0.05, 0.08, 0.8))

	func add_corpse(pos: Vector2, col: Color) -> void:
		corpses.append({pos = pos, col = col.darkened(0.35), rot = randf() * TAU})
		if corpses.size() > 80:
			corpses.pop_front()
		for i in 5:
			add_splat(pos + Vector2(randf_range(-18, 18), randf_range(-18, 18)),
					randf_range(4, 11), Color(0.42, 0.05, 0.08, 0.85))
		queue_redraw()

	func _draw() -> void:
		# Dark blood pools under corpses first, then splats, then bodies.
		for c in corpses:
			draw_circle(c.pos + Vector2(3, 4), 17.0, Color(0.30, 0.03, 0.05, 0.55))
		for s in splats:
			draw_circle(s.pos, s.r, s.col)
		for c in corpses:
			var v: Vector2 = Vector2.from_angle(c.rot)
			var col: Color = c.col
			draw_line(c.pos - v * 6.0, c.pos + v * 8.0, col, 8.0)
			draw_circle(c.pos + v * 14.0, 9.0, col)
			draw_circle(c.pos + v * 14.0, 9.0, col.darkened(0.35), false, 1.5)
			for i in 4:
				var limb: Vector2 = Vector2.from_angle(c.rot + 2.0 + i * 1.35) * 16.0
				draw_line(c.pos, c.pos + limb, col, 4.0)
				draw_circle(c.pos + limb, 2.6, col.darkened(0.2))

class Crosshair extends Node2D:
	## Dynamic crosshair: expands with movement and when firing.
	var expand := 0.0
	var game

	func _ready() -> void:
		z_index = 100

	func _process(delta: float) -> void:
		position = get_global_mouse_position()
		if game == null:
			game = get_tree().get_first_node_in_group("game")
		var target := 0.0
		if game != null:
			var p = game.local_player()
			if p != null and p.alive:
				if p.flash > 0.0:
					expand = maxf(expand, 7.0)
				target = clampf(p.velocity.length() / 270.0 * 2.5, 0.0, 3.0)
		expand = maxf(target, expand - delta * 34.0)
		visible = Input.mouse_mode == Input.MOUSE_MODE_HIDDEN
		queue_redraw()

	func _draw() -> void:
		var col := Color(0.55, 1.0, 1.0, 0.95)
		var sh := Color(0, 0, 0, 0.55)
		var gap := 5.0 + expand
		for i in 4:
			var v := Vector2.RIGHT.rotated(i * TAU / 4.0)
			draw_line(v * gap + Vector2(1, 1), v * (gap + 7.0) + Vector2(1, 1), sh, 3.0)
			draw_line(v * gap, v * (gap + 7.0), col, 1.6)
		draw_circle(Vector2(1, 1), 1.6, sh)
		draw_circle(Vector2.ZERO, 1.4, col)
