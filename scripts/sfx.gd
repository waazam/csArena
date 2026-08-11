extends Node
## Autoload "Sfx" — fully procedural sound effects. Every sound is synthesized
## once at startup into a cached AudioStreamWAV (16-bit mono PCM @ 22050 Hz):
## layered noise bursts with exponential envelopes, one-pole lowpass filtering,
## sine sweeps and tone blips. No audio asset files anywhere.
##
## play(name, ...)        -> non-positional (UI, local player feedback)
## play_at(name, pos, ...) -> positional via a pooled AudioStreamPlayer2D
## All calls are cosmetic-only and safe under the headless dummy audio driver.

const RATE := 22050
const POOL_2D := 16
const POOL_UI := 6

var sounds := {}  # name -> AudioStreamWAV
var _pool_2d: Array = []
var _pool_ui: Array = []
var _idx_2d := 0
var _idx_ui := 0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = 0x57C4  # deterministic library; playback jitter stays random
	var t0 := Time.get_ticks_msec()
	_generate_all()
	if OS.is_stdout_verbose():
		print("Sfx: generated %d sounds in %d ms" % [sounds.size(), Time.get_ticks_msec() - t0])
	# Soft-clip protection so stacked gunfire can't slam the master bus.
	AudioServer.add_bus_effect(0, AudioEffectHardLimiter.new())
	for i in POOL_2D:
		var p := AudioStreamPlayer2D.new()
		p.max_distance = 1600.0
		p.attenuation = 1.3
		add_child(p)
		_pool_2d.append(p)
	for i in POOL_UI:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool_ui.append(p)

# ---------------------------------------------------------------- playback

func play(sname: String, volume_db := 0.0, pitch_jitter := 0.05) -> void:
	var s = sounds.get(sname)
	if s == null or _pool_ui.is_empty():
		return
	var p: AudioStreamPlayer = _pool_ui[_idx_ui]
	_idx_ui = (_idx_ui + 1) % _pool_ui.size()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()

func play_at(sname: String, pos: Vector2, volume_db := 0.0, pitch_jitter := 0.05) -> void:
	var s = sounds.get(sname)
	if s == null or _pool_2d.is_empty():
		return
	var p: AudioStreamPlayer2D = _pool_2d[_idx_2d]
	_idx_2d = (_idx_2d + 1) % _pool_2d.size()
	p.global_position = pos
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()

# ---------------------------------------------------------------- synthesis

func _buf(dur: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(maxi(1, int(dur * RATE)))
	return b

## Lowpass-filtered white noise burst with exponential decay.
## fc = one-pole lowpass cutoff in Hz (higher = brighter crack).
func _layer_noise(b: PackedFloat32Array, amp: float, decay: float, fc: float,
		start := 0.0) -> void:
	var a := 1.0 - exp(-TAU * fc / RATE)
	var y := 0.0
	var i0 := int(start * RATE)
	for i in range(i0, b.size()):
		var t := float(i - i0) / RATE
		var x := _rng.randf_range(-1.0, 1.0) * amp * exp(-t * decay)
		y += a * (x - y)
		b[i] += y

## Sine sweep from f0 to f1 across the whole buffer (the "body" of a shot).
func _layer_sweep(b: PackedFloat32Array, f0: float, f1: float, amp: float,
		decay: float, attack := 0.0) -> void:
	var phase := 0.0
	var n := b.size()
	for i in n:
		var t := float(i) / RATE
		var f := lerpf(f0, f1, float(i) / maxf(1.0, n - 1))
		phase += TAU * f / RATE
		var env := exp(-t * decay)
		if attack > 0.0 and t < attack:
			env *= t / attack
		b[i] += sin(phase) * amp * env

## Tone blip at an offset. square=true soft-clips the sine for a harder edge.
func _layer_tone(b: PackedFloat32Array, freq: float, amp: float, decay: float,
		start: float, dur: float, attack := 0.005, square := false) -> void:
	var i0 := int(start * RATE)
	var n := mini(int(dur * RATE), b.size() - i0)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		phase += TAU * freq / RATE
		var s := sin(phase)
		if square:
			s = clampf(s * 3.0, -1.0, 1.0)
		var env := exp(-t * decay)
		if t < attack:
			env *= t / attack
		b[i0 + i] += s * amp * env

## Very short mechanical tick (a few ms of shaped noise) at an offset.
func _layer_click(b: PackedFloat32Array, start: float, amp: float, fc: float) -> void:
	var a := 1.0 - exp(-TAU * fc / RATE)
	var y := 0.0
	var i0 := int(start * RATE)
	var n := mini(int(0.018 * RATE), b.size() - i0)
	for i in n:
		var t := float(i) / RATE
		var x := _rng.randf_range(-1.0, 1.0) * amp * exp(-t * 300.0)
		y += a * (x - y)
		b[i0 + i] += y

## Arch-enveloped sustained tone across the whole buffer (swells/pads).
func _layer_pad(b: PackedFloat32Array, freq: float, amp: float) -> void:
	var phase := 0.0
	var n := b.size()
	for i in n:
		var k := float(i) / maxf(1.0, n - 1)
		phase += TAU * freq / RATE
		b[i] += sin(phase) * amp * sin(PI * k)

func _to_wav(b: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(b.size() * 2)
	for i in b.size():
		bytes.encode_s16(i * 2, int(clampf(b[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	return wav

## Generic gunshot: bright noise crack + descending sine body (+ optional
## low thump for heavy guns).
func _gun(dur: float, crack_amp: float, crack_decay: float, crack_fc: float,
		f0: float, f1: float, body_amp: float, body_decay: float,
		thump_amp := 0.0, thump_f := 75.0, thump_decay := 12.0) -> AudioStreamWAV:
	var b := _buf(dur)
	_layer_noise(b, crack_amp, crack_decay, crack_fc)
	_layer_sweep(b, f0, f1, body_amp, body_decay)
	if thump_amp > 0.0:
		_layer_tone(b, thump_f, thump_amp, thump_decay, 0.0, dur, 0.002)
	return _to_wav(b)

func _generate_all() -> void:
	# --- gunshots (one per weapon family, aliased per weapon id) ---
	sounds["shot_glock"] = _gun(0.16, 0.85, 45.0, 4500.0, 300.0, 110.0, 0.50, 25.0)
	sounds["shot_usp"] = _gun(0.14, 0.60, 55.0, 2200.0, 260.0, 100.0, 0.45, 30.0)   # suppressed: duller
	sounds["shot_mp5"] = _gun(0.10, 0.55, 70.0, 2600.0, 240.0, 110.0, 0.35, 40.0)   # light fast tick
	sounds["shot_m4a4"] = _gun(0.25, 0.90, 35.0, 5000.0, 260.0, 90.0, 0.60, 18.0, 0.35, 85.0)
	sounds["shot_ak47"] = _gun(0.28, 1.00, 30.0, 4200.0, 230.0, 80.0, 0.65, 15.0, 0.42, 75.0)
	sounds["shot_nova"] = _gun(0.50, 0.80, 25.0, 1500.0, 150.0, 55.0, 0.80, 8.0, 0.50, 55.0, 6.0)
	var awp := _buf(0.75)
	_layer_noise(awp, 1.0, 40.0, 6000.0)          # sharp crack
	_layer_noise(awp, 0.45, 6.0, 900.0)           # long rumble tail
	_layer_sweep(awp, 200.0, 60.0, 0.70, 7.0)     # deep body
	_layer_tone(awp, 55.0, 0.35, 5.0, 0.0, 0.75, 0.002)
	sounds["shot_awp"] = _to_wav(awp)

	# --- mechanics ---
	var dry := _buf(0.05)
	_layer_click(dry, 0.0, 0.50, 3000.0)
	_layer_tone(dry, 1200.0, 0.15, 200.0, 0.0, 0.03, 0.001, true)
	sounds["dry"] = _to_wav(dry)
	var rl0 := _buf(0.12)
	_layer_click(rl0, 0.0, 0.50, 1800.0)
	_layer_click(rl0, 0.05, 0.45, 900.0)          # mag-out thunk (lower)
	sounds["reload_start"] = _to_wav(rl0)
	var rl1 := _buf(0.15)
	_layer_click(rl1, 0.0, 0.45, 2500.0)
	_layer_click(rl1, 0.07, 0.60, 3500.0)         # slide rack (brighter)
	sounds["reload_end"] = _to_wav(rl1)

	# --- impacts ---
	var wall := _buf(0.08)
	_layer_noise(wall, 0.70, 60.0, 1200.0)
	_layer_sweep(wall, 200.0, 90.0, 0.20, 50.0)
	sounds["hit_wall"] = _to_wav(wall)
	var flesh := _buf(0.12)
	_layer_noise(flesh, 0.50, 40.0, 500.0)
	_layer_sweep(flesh, 160.0, 70.0, 0.50, 30.0)
	sounds["hit_flesh"] = _to_wav(flesh)
	var death := _buf(0.35)
	_layer_noise(death, 0.60, 12.0, 400.0)        # heavy thud
	_layer_noise(death, 0.35, 25.0, 1800.0)       # splat-ish mid noise
	_layer_sweep(death, 130.0, 45.0, 0.60, 10.0)
	sounds["death"] = _to_wav(death)

	# --- pickups ---
	var pw := _buf(0.18)
	_layer_click(pw, 0.0, 0.50, 2200.0)
	_layer_click(pw, 0.06, 0.50, 1400.0)
	_layer_tone(pw, 320.0, 0.15, 40.0, 0.02, 0.08, 0.002, true)
	sounds["pickup_weapon"] = _to_wav(pw)
	var ph := _buf(0.45)
	_layer_tone(ph, 660.0, 0.25, 12.0, 0.0, 0.20, 0.01)
	_layer_tone(ph, 880.0, 0.25, 10.0, 0.15, 0.30, 0.01)
	sounds["pickup_health"] = _to_wav(ph)

	# --- stingers ---
	var ws := _buf(0.8)
	_layer_pad(ws, 110.0, 0.28)                   # low horn-ish swell
	_layer_pad(ws, 112.5, 0.28)                   # detune for width
	_layer_pad(ws, 55.0, 0.18)
	sounds["wave_start"] = _to_wav(ws)
	var wc := _buf(0.5)
	_layer_tone(wc, 523.25, 0.30, 15.0, 0.0, 0.20, 0.005)
	_layer_tone(wc, 783.99, 0.30, 10.0, 0.18, 0.32, 0.005)
	sounds["wave_clear"] = _to_wav(wc)
	var go := _buf(0.9)
	_layer_tone(go, 392.0, 0.30, 8.0, 0.0, 0.40, 0.005)
	_layer_tone(go, 311.13, 0.30, 8.0, 0.25, 0.40, 0.005)
	_layer_tone(go, 233.08, 0.32, 6.0, 0.50, 0.40, 0.005)
	sounds["game_over"] = _to_wav(go)
	var fr := _buf(0.15)
	_layer_tone(fr, 880.0, 0.30, 40.0, 0.0, 0.08, 0.002)
	_layer_tone(fr, 1318.5, 0.20, 50.0, 0.04, 0.10, 0.002)
	sounds["frag"] = _to_wav(fr)
	var win := _buf(0.9)
	_layer_tone(win, 523.25, 0.28, 6.0, 0.0, 0.50, 0.005, true)
	_layer_tone(win, 659.26, 0.28, 6.0, 0.18, 0.50, 0.005, true)
	_layer_tone(win, 783.99, 0.28, 6.0, 0.36, 0.54, 0.005, true)
	_layer_tone(win, 1568.0, 0.12, 8.0, 0.36, 0.54, 0.005)
	sounds["win"] = _to_wav(win)
	var an := _buf(0.06)
	_layer_tone(an, 1200.0, 0.15, 90.0, 0.0, 0.06, 0.002)
	sounds["announce"] = _to_wav(an)

	# --- UI / movement ---
	var uh := _buf(0.03)
	_layer_click(uh, 0.0, 0.20, 4000.0)
	sounds["ui_hover"] = _to_wav(uh)
	var uc := _buf(0.06)
	_layer_click(uc, 0.0, 0.35, 2800.0)
	_layer_tone(uc, 700.0, 0.15, 80.0, 0.0, 0.05, 0.002)
	sounds["ui_click"] = _to_wav(uc)
	var fs := _buf(0.07)
	_layer_noise(fs, 0.30, 45.0, 350.0)
	sounds["footstep"] = _to_wav(fs)
