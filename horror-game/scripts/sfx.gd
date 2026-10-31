class_name Sfx
extends RefCounted
## Procedural horror sound bank. Every sound is synthesised at startup so the
## project ships without any audio assets. Results are cached in a static
## dictionary and survive scene reloads.

const RATE := 22050

static var cache: Dictionary = {}
static var ready := false

static func get_sound(sound_name: String) -> AudioStreamWAV:
	return cache.get(sound_name)

static func generate_all() -> void:
	if ready:
		return
	seed(1337)
	cache["drone"] = _drone()
	cache["heartbeat"] = _heartbeat()
	cache["screech"] = _screech(1.7, 1.0)
	cache["sting"] = _sting()
	cache["step"] = _step(0.16, 0.45, 140.0)
	cache["monster_step"] = _step(0.32, 1.0, 55.0)
	cache["whisper"] = _whisper()
	cache["bang"] = _bang()
	cache["growl"] = _growl()
	cache["static"] = _static()
	cache["breath"] = _breath()
	cache["pickup"] = _pickup()
	cache["click"] = _click()
	cache["laugh"] = _laugh()
	randomize()
	ready = true

# --------------------------------------------------------------------------
static func _to_wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		var v := clampf(samples[i], -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w

static func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b

static func _normalize(b: PackedFloat32Array, peak := 0.95) -> void:
	var m := 0.0001
	for v in b:
		m = maxf(m, absf(v))
	var k := peak / m
	for i in b.size():
		b[i] *= k

# --------------------------------------------------------------------------
static func _drone() -> AudioStreamWAV:
	# Seamless 8 second loop: beating sub tones + slowly breathing dark noise.
	var secs := 8.0
	var b := _buf(secs)
	var n := b.size()
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var ph := t / secs * TAU
		var v := sin(TAU * 41.0 * t) * 0.35
		v += sin(TAU * 41.5 * t) * 0.3
		v += sin(TAU * 61.75 * t) * 0.12 * (0.5 + 0.5 * sin(ph * 2.0))
		v += sin(TAU * 123.0 * t + sin(TAU * 0.25 * t) * 2.0) * 0.05
		var noise := randf() * 2.0 - 1.0
		lp += (noise - lp) * 0.02
		lp2 += (lp - lp2) * 0.05
		v += lp2 * 2.2 * (0.6 + 0.4 * sin(ph * 3.0))
		b[i] = v
	_normalize(b, 0.7)
	return _to_wav(b, true)

static func _heartbeat() -> AudioStreamWAV:
	var b := _buf(0.7)
	for i in b.size():
		var t := float(i) / RATE
		var v := 0.0
		for beat in [[0.0, 1.0], [0.24, 0.75]]:
			var bt: float = t - beat[0]
			if bt >= 0.0:
				var env := exp(-bt * 18.0) * minf(bt * 300.0, 1.0)
				var f := 52.0 + 30.0 * exp(-bt * 30.0)
				v += sin(TAU * f * bt) * env * beat[1]
		b[i] = v
	_normalize(b, 0.95)
	return _to_wav(b)

static func _screech(secs: float, intensity: float) -> AudioStreamWAV:
	var b := _buf(secs)
	var phases := [0.0, 0.0, 0.0, 0.0, 0.0]
	var det := [1.0, 1.013, 0.987, 1.5, 2.03]
	var hp_prev := 0.0
	var hp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var env := minf(t * 60.0, 1.0) * clampf((secs - t) * 2.5, 0.0, 1.0)
		var base := 700.0 + 900.0 * (1.0 - exp(-t * 3.0)) + sin(TAU * 7.0 * t) * 90.0
		var v := 0.0
		for k in phases.size():
			phases[k] = fmod(phases[k] + base * det[k] / RATE, 1.0)
			v += (phases[k] * 2.0 - 1.0) * (0.5 if k < 3 else 0.25)
		var noise := randf() * 2.0 - 1.0
		hp = 0.9 * (hp + noise - hp_prev)
		hp_prev = noise
		v += hp * 0.8 * intensity
		v = tanh(v * 2.5)
		b[i] = v * env
	_normalize(b, 0.98)
	return _to_wav(b)

static func _sting() -> AudioStreamWAV:
	# Dissonant string-like stab (cluster of detuned saws).
	var secs := 2.2
	var b := _buf(secs)
	var freqs := [220.0, 233.08, 311.13, 329.63, 466.16, 622.25]
	var ph := PackedFloat32Array()
	ph.resize(freqs.size())
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var env := minf(t * 80.0, 1.0) * exp(-t * 1.8)
		var v := 0.0
		for k in freqs.size():
			var f: float = freqs[k] * (1.0 + 0.004 * sin(TAU * (5.0 + k) * t))
			ph[k] = fmod(ph[k] + f / RATE, 1.0)
			v += ph[k] * 2.0 - 1.0
		lp += (v - lp) * 0.35
		b[i] = tanh(lp * 0.6) * env
	_normalize(b, 0.95)
	return _to_wav(b)

static func _step(secs: float, gain: float, f: float) -> AudioStreamWAV:
	var b := _buf(secs)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var env := exp(-t * (18.0 / secs * 0.16))
		lp += ((randf() * 2.0 - 1.0) - lp) * 0.12
		var v := lp * 1.5 + sin(TAU * f * t) * 0.6 * exp(-t * 25.0)
		b[i] = v * env
	_normalize(b, gain)
	return _to_wav(b)

static func _whisper() -> AudioStreamWAV:
	var secs := 2.6
	var b := _buf(secs)
	var hp := 0.0
	var prev := 0.0
	var bp := 0.0
	var syl_rate := 5.5
	for i in b.size():
		var t := float(i) / RATE
		var noise := randf() * 2.0 - 1.0
		hp = 0.97 * (hp + noise - prev)
		prev = noise
		bp += (hp - bp) * 0.45
		var syl := pow(maxf(sin(TAU * syl_rate * t + sin(TAU * 1.3 * t) * 2.0), 0.0), 2.0)
		var env := minf(t * 4.0, 1.0) * clampf((secs - t) * 3.0, 0.0, 1.0)
		var formant := sin(TAU * (900.0 + 400.0 * sin(TAU * 2.1 * t)) * t) * 0.15
		b[i] = (bp + formant * bp) * syl * env
	_normalize(b, 0.8)
	return _to_wav(b)

static func _bang() -> AudioStreamWAV:
	var b := _buf(1.2)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += ((randf() * 2.0 - 1.0) - lp) * 0.08
		var v := lp * 3.0 * exp(-t * 6.0)
		v += sin(TAU * (45.0 + 40.0 * exp(-t * 10.0)) * t) * exp(-t * 4.0)
		# metallic ring
		v += sin(TAU * 311.0 * t) * 0.15 * exp(-t * 3.0) + sin(TAU * 497.0 * t) * 0.1 * exp(-t * 4.0)
		b[i] = tanh(v * 1.5)
	_normalize(b, 1.0)
	return _to_wav(b)

static func _growl() -> AudioStreamWAV:
	var secs := 3.0
	var b := _buf(secs)
	var ph := 0.0
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var f := 58.0 + 14.0 * sin(TAU * t / secs * 2.0)
		ph = fmod(ph + f / RATE, 1.0)
		var saw := ph * 2.0 - 1.0
		var rough := 0.6 + 0.4 * sin(TAU * 23.0 * t) * sin(TAU * 31.0 * t)
		lp += ((randf() * 2.0 - 1.0) - lp) * 0.1
		var v := (saw * 0.7 + lp * 1.4) * rough
		var env := 0.65 + 0.35 * sin(TAU * t / secs)
		b[i] = tanh(v * 1.4) * env
	_normalize(b, 0.9)
	return _to_wav(b, true)

static func _static() -> AudioStreamWAV:
	var b := _buf(0.6)
	var hold := 0.0
	for i in b.size():
		if i % 6 == 0:
			hold = randf() * 2.0 - 1.0
		var t := float(i) / RATE
		b[i] = hold * (0.5 + 0.5 * signf(sin(TAU * 17.0 * t))) * 0.9
	return _to_wav(b)

static func _breath() -> AudioStreamWAV:
	var secs := 2.4
	var b := _buf(secs)
	var lp := 0.0
	var lp2 := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += ((randf() * 2.0 - 1.0) - lp) * 0.25
		lp2 += (lp - lp2) * 0.3
		var env := pow(maxf(sin(PI * t / 1.1), 0.0), 1.5) if t < 1.1 else pow(maxf(sin(PI * (t - 1.2) / 1.2), 0.0), 2.0) * 0.8
		if t >= 1.1 and t < 1.2:
			env = 0.0
		b[i] = (lp - lp2 * 0.5) * env * (1.0 + 0.3 * sin(TAU * 90.0 * t))
	_normalize(b, 0.85)
	return _to_wav(b)

static func _pickup() -> AudioStreamWAV:
	var b := _buf(2.0)
	for i in b.size():
		var t := float(i) / RATE
		var v := sin(TAU * 880.0 * t) + sin(TAU * 932.3 * t) * 0.8 + sin(TAU * 1318.5 * t) * 0.4
		b[i] = v * exp(-t * 2.2) * minf(t * 200.0, 1.0)
	_normalize(b, 0.6)
	return _to_wav(b)

static func _click() -> AudioStreamWAV:
	var b := _buf(0.06)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = (randf() * 2.0 - 1.0) * exp(-t * 120.0) + sin(TAU * 2200.0 * t) * exp(-t * 90.0) * 0.5
	_normalize(b, 0.6)
	return _to_wav(b)

static func _laugh() -> AudioStreamWAV:
	# A distorted, child-like "he-he-he" made from pulsed formants.
	var secs := 1.8
	var b := _buf(secs)
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var f := 420.0 - t * 90.0 + sin(TAU * 6.0 * t) * 20.0
		ph = fmod(ph + f / RATE, 1.0)
		var src := sin(TAU * ph) + 0.5 * sin(TAU * ph * 2.0) + 0.3 * sin(TAU * ph * 3.0)
		var pulse := pow(maxf(sin(TAU * 4.2 * t), 0.0), 3.0)
		var env := clampf((secs - t) * 2.0, 0.0, 1.0)
		b[i] = tanh(src * 1.5) * pulse * env
	_normalize(b, 0.7)
	return _to_wav(b)
