extends RefCounted
## Deterministic procedural sound effects generated in memory (no binary assets).
## Kinds: "flap", "blast", "channel" (seamless loop), "charge".

const MIX_RATE: int = 22050
const LOOP_KINDS: Array[String] = ["channel"]

static var _cache: Dictionary = {}


static func stream(kind: String) -> AudioStreamWAV:
	if _cache.has(kind):
		return _cache[kind] as AudioStreamWAV
	var samples: PackedFloat32Array
	match kind:
		"flap":
			samples = _flap()
		"blast":
			samples = _blast()
		"channel":
			samples = _channel()
		"charge":
			samples = _charge()
		_:
			push_warning("SynthAudio: unknown kind '%s'" % kind)
			return null
	var wav: AudioStreamWAV = _to_wav(samples, kind in LOOP_KINDS)
	_cache[kind] = wav
	return wav


## Raw float samples (same data as the stream) for tests and tools.
static func samples_for(kind: String) -> PackedFloat32Array:
	match kind:
		"flap":
			return _flap()
		"blast":
			return _blast()
		"channel":
			return _channel()
		"charge":
			return _charge()
	return PackedFloat32Array()


static func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


static func _normalize(s: PackedFloat32Array, peak: float) -> void:
	var m: float = 0.0001
	for v: float in s:
		m = maxf(m, absf(v))
	var k: float = peak / m
	for i in s.size():
		s[i] *= k


static func _to_wav(s: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(s.size() * 2)
	for i in s.size():
		bytes.encode_s16(i * 2, clampi(roundi(s[i] * 32767.0), -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = s.size()
	return wav


static func _flap() -> PackedFloat32Array:
	var n: int = roundi(0.6 * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng: RandomNumberGenerator = _rng(1101)
	var starts: Array[float] = [0.02, 0.27]
	var lp: float = 0.0
	for i in n:
		var t: float = float(i) / MIX_RATE
		var env: float = 0.0
		for k in starts.size():
			var u: float = (t - starts[k]) / 0.22
			if u >= 0.0 and u < 1.0:
				env = maxf(env, pow(sin(PI * u), 2.0) * (1.0 - 0.25 * k))
		var noise: float = rng.randf() * 2.0 - 1.0
		lp += (noise - lp) * (0.05 + 0.25 * env)
		out[i] = lp * env * 2.2 + sin(TAU * 70.0 * t) * 0.2 * env
	_normalize(out, 0.8)
	return out


static func _blast() -> PackedFloat32Array:
	var n: int = roundi(1.6 * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng: RandomNumberGenerator = _rng(2202)
	var boom_phase: float = 0.0
	var zap_phase: float = 0.0
	var lp: float = 0.0
	for i in n:
		var t: float = float(i) / MIX_RATE
		boom_phase += TAU * (45.0 + 160.0 * exp(-t * 9.0)) / MIX_RATE
		var boom: float = sin(boom_phase) * exp(-t * 3.2)
		var noise: float = rng.randf() * 2.0 - 1.0
		lp += (noise - lp) * 0.3
		var hp: float = noise - lp
		var crack: float = noise * exp(-t * 40.0)
		var gate: float = pow(absf(sin(t * 190.0) * sin(t * 77.0 + 1.0)), 3.0)
		var sizzle: float = hp * gate * exp(-t * 3.0) * 1.2
		zap_phase += TAU * (300.0 + 1700.0 * exp(-t * 6.0)) / MIX_RATE
		var zap: float = sin(zap_phase) * exp(-t * 6.0) * 0.25
		var rumble: float = lp * exp(-t * 4.0) * 0.5
		out[i] = tanh((boom * 1.4 + crack + sizzle + zap + rumble) * 1.2)
	for i in 64:
		out[n - 1 - i] *= float(i) / 64.0
	_normalize(out, 0.9)
	return out


## Exactly 2.0 s; every periodic component has an integer number of cycles and
## the filtered noise is cross-faded so the loop point is seamless.
static func _channel() -> PackedFloat32Array:
	var n: int = 2 * MIX_RATE
	var xf: int = roundi(0.15 * MIX_RATE)
	var rng: RandomNumberGenerator = _rng(3303)
	var filtered := PackedFloat32Array()
	filtered.resize(n + xf)
	var lp: float = 0.0
	var lp2: float = 0.0
	for i in n + xf:
		var noise: float = rng.randf() * 2.0 - 1.0
		lp += (noise - lp) * 0.5
		lp2 += (lp - lp2) * 0.08
		filtered[i] = lp - lp2  # band-pass hiss
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t: float = float(i) / MIX_RATE
		var hum: float = sin(TAU * 55.0 * t) * 0.5 + sin(TAU * 110.0 * t) * 0.35 \
			+ sin(TAU * 165.0 * t) * 0.2 + sin(TAU * 330.0 * t) * 0.12
		var buzz: float = signf(sin(TAU * 220.0 * t)) * 0.08
		var trem: float = 0.75 + 0.25 * sin(TAU * 6.0 * t)
		var gate: float = pow(maxf(sin(TAU * 17.0 * t) * sin(TAU * 5.0 * t + 0.7), 0.0), 2.0)
		var nz: float
		if i < xf:
			var w: float = float(i) / xf
			nz = filtered[i] * w + filtered[n + i] * (1.0 - w)
		else:
			nz = filtered[i]
		out[i] = (hum + buzz) * trem * 0.6 + nz * (0.35 + gate * 2.2)
	_normalize(out, 0.7)
	return out


static func _charge() -> PackedFloat32Array:
	var dur: float = 2.4
	var n: int = roundi(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng: RandomNumberGenerator = _rng(4404)
	var ph: float = 0.0
	var ph2: float = 0.0
	var mod_ph: float = 0.0
	var lp: float = 0.0
	for i in n:
		var t: float = float(i) / MIX_RATE
		var u: float = t / dur
		var f: float = 180.0 * (1.0 + u * u * 7.0)
		ph += TAU * f / MIX_RATE
		ph2 += TAU * f * 2.01 / MIX_RATE
		mod_ph += TAU * (8.0 + 32.0 * u) / MIX_RATE
		var amp: float = pow(u, 1.5) * 0.9 + 0.1
		var tone: float = sin(ph) + 0.4 * sin(ph2)
		var noise: float = rng.randf() * 2.0 - 1.0
		lp += (noise - lp) * 0.4
		var crackle: float = (noise - lp) * u * u * pow(absf(sin(t * 130.0)), 4.0)
		out[i] = (tone * (0.7 + 0.3 * sin(mod_ph)) * amp + crackle * 1.2)
	for i in 400:
		out[n - 1 - i] *= float(i) / 400.0
		out[i] *= float(i) / 400.0
	_normalize(out, 0.8)
	return out
