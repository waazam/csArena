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

func _to_wav(b: PackedFloat32Array, rate := RATE) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(b.size() * 2)
	for i in b.size():
		bytes.encode_s16(i * 2, int(clampf(b[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = bytes
	return wav

# ------------------------------------------------- gunshot synthesis (44.1k)
# Physically-informed layering. Real gunshot anatomy, all layers summed then
# tanh-saturated: (1) muzzle blast = hard-clipped broadband impulse with ZERO
# attack, (2) fast-decaying high-frequency crack, (3) bandpassed low-mid body
# punch, (4) low sine sub for heavy guns, (5) reverb-like tail that grows
# progressively duller (time-varying lowpass = air absorption) plus a few
# delayed lowpassed echo taps faking environment reflections.

const SHOT_RATE := 44100
const ECHO_TAPS := [
	[0.055, 0.42, 2600.0], [0.100, 0.26, 1800.0],
	[0.160, 0.17, 1300.0], [0.235, 0.11, 950.0],
]
const ENV_CUT := 0.0005  # stop writing a layer once its envelope is inaudible

## (1) Muzzle blast: ~4 ms of full-scale hard-clipped noise starting at
## sample 0 — no attack ramp whatsoever.
func _shot_blast(b: PackedFloat32Array, rate: int, amp: float) -> void:
	var n := mini(int(0.004 * rate), b.size())
	var env := amp
	var dm := exp(-700.0 / rate)
	for i in n:
		b[i] += clampf(_rng.randf_range(-3.0, 3.0), -1.0, 1.0) * env
		env *= dm

## (2)/(3) Bandpassed noise (lowpass minus lowpass) with exponential decay.
## Used for the crack (2–10 kHz), body punch (80–420 Hz) and suppressor chuff.
func _shot_band(b: PackedFloat32Array, rate: int, amp: float, decay: float,
		f_lo: float, f_hi: float) -> void:
	var a_hi := 1.0 - exp(-TAU * f_hi / rate)
	var a_lo := 1.0 - exp(-TAU * f_lo / rate)
	var y_hi := 0.0
	var y_lo := 0.0
	var env := amp
	var dm := exp(-decay / rate)
	for i in b.size():
		var x := _rng.randf_range(-1.0, 1.0) * env
		y_hi += a_hi * (x - y_hi)
		y_lo += a_lo * (x - y_lo)
		b[i] += y_hi - y_lo
		env *= dm
		if env < ENV_CUT:
			break

## (4) Low sine sub (50–90 Hz) under rifles/shotgun/sniper.
func _shot_sub(b: PackedFloat32Array, rate: int, amp: float, freq: float,
		decay: float) -> void:
	var phase := 0.0
	var w := TAU * freq / rate
	var env := amp
	var dm := exp(-decay / rate)
	for i in b.size():
		phase += w
		b[i] += sin(phase) * env
		env *= dm
		if env < ENV_CUT:
			break

## Short mechanical action tick (bolt/slide) for suppressed weapons.
func _shot_click(b: PackedFloat32Array, rate: int, start: float, amp: float,
		fc: float) -> void:
	var a := 1.0 - exp(-TAU * fc / rate)
	var y := 0.0
	var i0 := int(start * rate)
	var n := mini(int(0.006 * rate), b.size() - i0)
	var env := amp
	var dm := exp(-500.0 / rate)
	for i in n:
		y += a * (_rng.randf_range(-1.0, 1.0) * env - y)
		env *= dm
		b[i0 + i] += y

## (5a) Reverb-like noise tail that gets progressively duller: the one-pole
## lowpass cutoff glides from fc0 to fc1 across the tail (air absorption).
func _shot_tail(b: PackedFloat32Array, rate: int, amp: float, decay: float,
		fc0 := 6000.0, fc1 := 1000.0, start := 0.015) -> void:
	var i0 := int(start * rate)
	var n := b.size() - i0
	if n <= 0:
		return
	var y := 0.0
	var env := amp
	var dm := exp(-decay / rate)
	var a := 1.0 - exp(-TAU * fc0 / rate)
	for i in n:
		if i % 64 == 0:  # refresh the gliding cutoff coefficient in blocks
			a = 1.0 - exp(-TAU * lerpf(fc0, fc1, float(i) / n) / rate)
		y += a * (_rng.randf_range(-1.0, 1.0) * env - y)
		b[i0 + i] += y
		env *= dm
		if env < ENV_CUT:
			break

## (5b) Discrete echo taps: delayed, attenuated, lowpassed copies of the
## first ~120 ms, with slight random jitter on the delays.
func _shot_echoes(b: PackedFloat32Array, rate: int, count: int) -> void:
	if count <= 0:
		return
	var src_n := mini(int(0.12 * rate), b.size())
	var src := b.slice(0, src_n)
	for ti in mini(count, ECHO_TAPS.size()):
		var tap: Array = ECHO_TAPS[ti]
		var d := int(float(tap[0]) * _rng.randf_range(0.85, 1.15) * rate)
		var g: float = tap[1]
		var a := 1.0 - exp(-TAU * float(tap[2]) / rate)
		var y := 0.0
		for i in src_n:
			var j := d + i
			if j >= b.size():
				break
			y += a * (src[i] - y)
			b[j] += y * g

## Sum -> tanh soft-clip (perceived "bang" comes from saturation density,
## not peak level) -> normalize just under full scale.
func _shot_finish(b: PackedFloat32Array, drive: float, norm: float) -> void:
	var peak := 0.0
	for i in b.size():
		var v := tanh(b[i] * drive)
		b[i] = v
		peak = maxf(peak, absf(v))
	if peak > 0.0001:
		var g := norm / peak
		for i in b.size():
			b[i] *= g

func _make_shot(cfg: Dictionary) -> AudioStreamWAV:
	var b := PackedFloat32Array()
	b.resize(int(float(cfg.dur) * SHOT_RATE))
	if float(cfg.get("blast", 0.0)) > 0.0:
		_shot_blast(b, SHOT_RATE, cfg.blast)
	var cr: Array = cfg.get("crack", [])
	if not cr.is_empty():
		_shot_band(b, SHOT_RATE, cr[0], cr[1], cr[2], cr[3])
	var ch: Array = cfg.get("chuff", [])
	if not ch.is_empty():
		_shot_band(b, SHOT_RATE, ch[0], ch[1], ch[2], ch[3])
	var bd: Array = cfg.get("body", [])
	if not bd.is_empty():
		_shot_band(b, SHOT_RATE, bd[0], bd[1], bd[2], bd[3])
	var sb: Array = cfg.get("sub", [])
	if not sb.is_empty():
		_shot_sub(b, SHOT_RATE, sb[0], sb[1], sb[2])
	for c in cfg.get("clicks", []):
		_shot_click(b, SHOT_RATE, c[0], c[1], c[2])
	var tl: Array = cfg.get("tail", [])
	if not tl.is_empty():
		_shot_tail(b, SHOT_RATE, tl[0], tl[1])
	_shot_echoes(b, SHOT_RATE, int(cfg.get("echoes", 0)))
	_shot_finish(b, float(cfg.get("drive", 3.0)), float(cfg.get("norm", 0.9)))
	return _to_wav(b, SHOT_RATE)

func _generate_all() -> void:
	# --- gunshots: physically-informed model @ 44.1 kHz (see helpers above).
	sounds["shot_glock"] = _make_shot({
		dur = 0.40, blast = 1.0,
		crack = [1.00, 40.0, 2000.0, 8000.0],
		body = [0.70, 14.0, 120.0, 420.0],
		tail = [0.30, 12.0],
		echoes = 2, drive = 3.0, norm = 0.85,
	})
	sounds["shot_usp"] = _make_shot({  # suppressed: chuff + action, no crack
		dur = 0.35, blast = 0.25,
		crack = [0.15, 60.0, 2000.0, 6000.0],
		chuff = [0.70, 28.0, 250.0, 1100.0],
		body = [0.45, 16.0, 100.0, 350.0],
		clicks = [[0.0, 0.35, 4000.0], [0.045, 0.30, 3000.0]],
		tail = [0.15, 15.0],
		echoes = 1, drive = 2.0, norm = 0.72,
	})
	sounds["shot_mp5"] = _make_shot({  # suppressed, kept tight for rapid fire
		dur = 0.30, blast = 0.20,
		crack = [0.12, 70.0, 2500.0, 7000.0],
		chuff = [0.65, 35.0, 300.0, 1300.0],
		body = [0.35, 22.0, 120.0, 400.0],
		clicks = [[0.0, 0.30, 4500.0], [0.035, 0.28, 3200.0]],
		tail = [0.10, 20.0],
		echoes = 0, drive = 2.0, norm = 0.68,
	})
	sounds["shot_m4a4"] = _make_shot({
		dur = 0.65, blast = 1.0,
		crack = [1.00, 35.0, 2500.0, 9000.0],
		body = [0.80, 11.0, 110.0, 420.0],
		sub = [0.50, 70.0, 9.0],
		tail = [0.40, 7.0],
		echoes = 3, drive = 3.5, norm = 0.92,
	})
	sounds["shot_ak47"] = _make_shot({  # slightly lower/duller than the M4
		dur = 0.70, blast = 1.0,
		crack = [0.95, 32.0, 1800.0, 7000.0],
		body = [0.90, 10.0, 100.0, 380.0],
		sub = [0.55, 62.0, 8.0],
		tail = [0.45, 6.5],
		echoes = 3, drive = 3.5, norm = 0.94,
	})
	sounds["shot_nova"] = _make_shot({  # massive slow low end
		dur = 0.90, blast = 1.0,
		crack = [0.70, 30.0, 1500.0, 5000.0],
		body = [1.00, 6.0, 80.0, 300.0],
		sub = [0.70, 55.0, 5.0],
		tail = [0.50, 5.0],
		echoes = 3, drive = 4.0, norm = 0.97,
	})
	sounds["shot_awp"] = _make_shot({  # everything maxed, longest tail
		dur = 1.30, blast = 1.2,
		crack = [1.10, 30.0, 2000.0, 10000.0],
		body = [0.90, 8.0, 90.0, 350.0],
		sub = [0.80, 50.0, 4.5],
		tail = [0.55, 3.6],
		echoes = 4, drive = 4.0, norm = 0.98,
	})

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
