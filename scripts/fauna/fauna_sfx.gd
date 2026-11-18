class_name FaunaSfx
extends RefCounted
## Звуки животных: файлы из assets/sounds (свинья, утка/птицы, ночь) +
## процедурные AudioStreamWAV (шипение змеи, клики краба, рык крокодила, визг обезьяны,
## писк летучих мышей, стрекот скорпиона, крики попугая/чайки). Всё кэшируется.
## play(at_node, kind, volume_db) — одноразовый 3D-звук.

const RATE := 22050
const FILES := {
	&"boar_squeal": ["res://assets/sounds/oculus_pack/ANMLFarm_PigSqueal_OS_01.ogg", "res://assets/sounds/oculus_pack/ANMLFarm_PigSqueal_OS_02.ogg"],
	&"duck": ["res://assets/sounds/oculus_pack/BIRDFowl_Duck_OS_01.ogg"],
	&"splash": ["res://assets/sounds/sfx-kit/props-splash.wav"],
}

static var _cache: Dictionary = {}

static func stream(kind: StringName) -> AudioStream:
	var key := String(kind)
	if FILES.has(kind):
		var arr: Array = FILES[kind]
		var path: String = arr[randi() % arr.size()]
		if ResourceLoader.exists(path):
			return load(path) as AudioStream
	var variant := randi() % 3
	key += "_%d" % variant
	if _cache.has(key):
		return _cache[key]
	var s := _make(kind, variant)
	_cache[key] = s
	return s

static func play(at: Node3D, kind: StringName, volume_db: float = 0.0, unit_size: float = 6.0, pitch: float = 1.0) -> void:
	if at == null or not at.is_inside_tree():
		return
	# дальше слышимости — не создаём плеер вовсе (звери и боты далеко от камеры)
	var cam := at.get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_to(at.global_position) > unit_size * 12.0:
		return
	var st := stream(kind)
	if st == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = st
	p.volume_db = volume_db
	p.unit_size = unit_size
	p.max_distance = unit_size * 12.0
	p.pitch_scale = pitch * randf_range(0.92, 1.08)
	p.bus = &"Master"
	at.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

# ------------------------------------------------------------------------

static func _make(kind: StringName, v: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(kind)) + v * 7919
	var data: PackedFloat32Array
	match kind:
		&"hiss": data = _hiss(rng, 1.1 + v * 0.2)
		&"crab_click": data = _clicks(rng, 0.35, 5 + v * 2, 2600.0)
		&"scorpion": data = _clicks(rng, 0.5, 12, 4200.0)
		&"croc_growl": data = _growl(rng, 1.2, 55.0 + v * 6.0, 0.9)
		&"croc_snap": data = _snap(rng)
		&"boar_grunt": data = _growl(rng, 0.45, 95.0 + v * 12.0, 0.6)
		&"monkey": data = _screech(rng, 0.7, 900.0 + v * 140.0, 4)
		&"parrot": data = _screech(rng, 0.45, 1500.0 + v * 220.0, 2)
		&"gull": data = _screech(rng, 0.6, 1100.0 + v * 120.0, 3)
		&"bat": data = _chirps(rng, 0.4, 6500.0)
		&"lizard": data = _hiss(rng, 0.45)
		&"bite": data = _snap(rng)
		&"wings": data = _flutter(rng, 0.6)
		&"egg_dig": data = _dig(rng, 0.8)
		_: data = _hiss(rng, 0.3)
	return _to_wav(data)

static func _env(t: float, dur: float, att: float = 0.02, rel: float = 0.2) -> float:
	return clampf(t / att, 0.0, 1.0) * clampf((dur - t) / rel, 0.0, 1.0)

static func _hiss(rng: RandomNumberGenerator, dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var hp := 0.0
	var prev := 0.0
	for i in n:
		var t := float(i) / RATE
		var w := rng.randf_range(-1.0, 1.0)
		hp = 0.86 * (hp + w - prev)  # высокочастотный шум
		prev = w
		var am := 0.75 + 0.25 * sin(t * 23.0)
		out[i] = hp * 0.45 * am * _env(t, dur, 0.08, 0.35)
	return out

static func _clicks(rng: RandomNumberGenerator, dur: float, count: int, freq: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for c in count:
		var start := int(rng.randf_range(0.0, dur - 0.02) * RATE)
		var f := freq * rng.randf_range(0.8, 1.25)
		for k in int(0.012 * RATE):
			var i := start + k
			if i >= n:
				break
			var t := float(k) / RATE
			out[i] += sin(TAU * f * t) * exp(-t * 520.0) * 0.6 + rng.randf_range(-0.2, 0.2) * exp(-t * 900.0)
	return out

static func _growl(rng: RandomNumberGenerator, dur: float, f0: float, rough: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := f0 * (1.0 + 0.15 * sin(t * 7.0) + 0.06 * rng.randf_range(-1, 1))
		ph += TAU * f / RATE
		var saw := fmod(ph / TAU, 1.0) * 2.0 - 1.0
		var flutter := 0.6 + 0.4 * absf(sin(t * TAU * 18.0 * rough))
		var x := (saw * 0.7 + rng.randf_range(-1, 1) * 0.25 * rough) * flutter
		lp += (x - lp) * 0.12
		out[i] = lp * 0.9 * _env(t, dur, 0.06, 0.3)
	return out

static func _snap(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var dur := 0.25
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = (rng.randf_range(-1, 1) * 0.8 + sin(TAU * 180.0 * t) * 0.5) * exp(-t * 30.0)
	return out

static func _screech(rng: RandomNumberGenerator, dur: float, f0: float, calls: int) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var seg := dur / calls
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var local := fmod(t, seg) / seg
		var f := f0 * (1.0 + 0.5 * sin(local * PI) - 0.2 * local) * (1.0 + 0.02 * rng.randf_range(-1, 1))
		ph += TAU * f / RATE
		var x := sin(ph) * 0.6 + sin(ph * 2.0) * 0.25 + sin(ph * 3.01) * 0.12
		var e := sin(clampf(local, 0.0, 1.0) * PI)
		out[i] = x * e * 0.5 * _env(t, dur, 0.01, 0.05)
	return out

static func _chirps(rng: RandomNumberGenerator, dur: float, f0: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var count := 6
	for c in count:
		var start := int(rng.randf_range(0.0, dur - 0.03) * RATE)
		var ph := 0.0
		for k in int(0.02 * RATE):
			var i := start + k
			if i >= n:
				break
			var t := float(k) / RATE
			ph += TAU * (f0 - t * 90000.0) / RATE
			out[i] += sin(ph) * sin(t / 0.02 * PI) * 0.35
	return out

static func _flutter(rng: RandomNumberGenerator, dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (rng.randf_range(-1, 1) - lp) * 0.25
		out[i] = lp * absf(sin(t * TAU * 9.0)) * 0.6 * _env(t, dur, 0.03, 0.2)
	return out

static func _dig(rng: RandomNumberGenerator, dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (rng.randf_range(-1, 1) - lp) * 0.4
		out[i] = lp * pow(absf(sin(t * TAU * 3.0)), 3.0) * 0.6
	return out

static func _to_wav(data: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		var s := int(clampf(data[i], -1.0, 1.0) * 32000.0)
		bytes.encode_s16(i * 2, s)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w
