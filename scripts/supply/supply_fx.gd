class_name SupplyFx
extends RefCounted
## Эффекты SUPPLY: столб цветного дыма (видно издалека), сигнальная ракета (красный
## свет + дым), пламя горелки, процедурный звук мотора (самолёт, бензопила, горелка) —
## подходящих записей в assets/sounds нет, поэтому шум синтезируется (AudioStreamGenerator).

## Столб дыма шашки: густое основание + высокий шлейф, сносимый ветром.
static func smoke_column(parent: Node3D, color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "SmokeColumn"
	parent.add_child(root)
	# у шашки — плотная струя (небольшие клубы), выше — широкий шлейф, сносимый ветром
	var base := CombatFx.particles(root, parent.global_position, 20, 3.0, "smoke", false,
		CombatFx._ramp([Color(color, 0.85), Color(color.lightened(0.1), 0.7), Color(color.lightened(0.3), 0.35), Color(color.lightened(0.5), 0.0)]),
		0.9, 3.0, 12.0, Vector3.UP, Vector3(0.3, 1.0, 0.1), false)
	base.name = "Base"
	var plume := CombatFx.particles(root, parent.global_position + Vector3.UP * 4.0, 70, 22.0, "smoke", false,
		CombatFx._ramp([Color(color, 0.0), Color(color, 0.85), Color(color.lightened(0.2), 0.6), Color(color.lightened(0.45), 0.0)]),
		4.0, 2.6, 8.0, Vector3.UP, Vector3(0.45, 0.25, 0.18), false)
	plume.name = "Plume"
	var sc := Curve.new()
	sc.max_value = 4.0
	sc.add_point(Vector2(0, 0.6))
	sc.add_point(Vector2(0.3, 1.6))
	sc.add_point(Vector2(1, 4.0))
	plume.scale_amount_curve = sc
	plume.damping_min = 0.05
	plume.damping_max = 0.15
	for p: CPUParticles3D in [base, plume]:
		p.local_coords = false
		p.preprocess = 4.0
		(p.mesh as QuadMesh).material = smoke_mat()
	var snd := AudioStreamPlayer3D.new()
	snd.stream = CombatFx.stream("fuse_loop")
	snd.volume_db = -14.0
	snd.max_distance = 25.0
	snd.autoplay = true
	root.add_child(snd)
	return root

static var _smoke_mat: StandardMaterial3D

## Цветной дым шашки: без затенения (иначе против солнца он чёрный), мягкие края.
static func smoke_mat() -> StandardMaterial3D:
	if _smoke_mat:
		return _smoke_mat
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = CombatFx.soft_tex("smoke")
	m.albedo_color = Color(0.85, 0.85, 0.85)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	_smoke_mat = m
	return m

static func stop_smoke(col: Node3D) -> void:
	if col == null or not is_instance_valid(col):
		return
	for c in col.get_children():
		if c is CPUParticles3D:
			(c as CPUParticles3D).emitting = false
		elif c is AudioStreamPlayer3D:
			(c as AudioStreamPlayer3D).stop()
	col.get_tree().create_timer(17.0).timeout.connect(col.queue_free)

## Пламя горелки (короткий голубой факел) у узла-маркера.
static func torch_flame(parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "TorchFlame"
	parent.add_child(root)
	var core := CPUParticles3D.new()
	core.amount = 24
	core.lifetime = 0.12
	var qm := QuadMesh.new()
	qm.size = Vector2(0.025, 0.04)
	qm.material = CombatFx.particle_mat("flame", true)
	core.mesh = qm
	core.direction = Vector3(0, 0, -1)
	core.spread = 6.0
	core.gravity = Vector3.ZERO
	core.initial_velocity_min = 0.7
	core.initial_velocity_max = 1.1
	core.color_ramp = CombatFx._ramp([Color(0.35, 0.45, 1.0, 0.9), Color(0.25, 0.35, 1.0, 0.55), Color(1.0, 0.55, 0.2, 0.25), Color(1.0, 0.4, 0.1, 0.0)])
	core.local_coords = true
	root.add_child(core)
	var l := OmniLight3D.new()
	l.light_color = Color(0.6, 0.7, 1.0)
	l.light_energy = 0.8
	l.omni_range = 1.6
	l.position = Vector3(0, 0, -0.05)
	root.add_child(l)
	return root

## Сигнальная ракета: красный свет + дым. Пока летит — следует за снарядом, потом
## догорает на месте падения (на воде — плавает).
class FlareGlow:
	extends Node3D
	var target: Node3D
	var burn := 28.0
	var _t := 0.0
	var _light: OmniLight3D
	var _sparks: CPUParticles3D
	var _smoke: CPUParticles3D

	func _ready() -> void:
		top_level = true
		add_to_group(&"supply_flares")
		_light = OmniLight3D.new()
		_light.light_color = Color(1.0, 0.18, 0.1)
		_light.light_energy = 6.0
		_light.omni_range = 26.0
		_light.omni_attenuation = 1.2
		_light.shadow_enabled = false
		add_child(_light)
		_sparks = CombatFx.particles(self, global_position, 30, 0.5, "flame", true,
			CombatFx._ramp([Color(1, 0.9, 0.8, 1), Color(1, 0.25, 0.1, 0.9), Color(0.6, 0.05, 0.02, 0)]), 0.18, 1.2, 50.0, Vector3.UP, Vector3(0, -2, 0), false)
		_smoke = CombatFx.particles(self, global_position, 24, 5.0, "smoke", false,
			CombatFx._ramp([Color(0.9, 0.3, 0.25, 0.0), Color(0.95, 0.45, 0.4, 0.55), Color(0.9, 0.7, 0.68, 0.0)]), 0.8, 1.0, 20.0, Vector3.UP, Vector3(0.2, 0.9, 0), false)
		for p: CPUParticles3D in [_sparks, _smoke]:
			p.local_coords = false

	func _process(delta: float) -> void:
		_t += delta
		if target and is_instance_valid(target) and not target.is_queued_for_deletion():
			global_position = target.global_position
		else:
			target = null
			var ws := BuildEnv.water_surface(global_position.x, global_position.z)
			if global_position.y < ws + 0.05:
				global_position.y = ws + 0.05
			burn -= delta
		for p: CPUParticles3D in [_sparks, _smoke]:
			p.global_position = global_position
		_light.light_energy = (5.0 + randf() * 2.0) * clampf(burn / 4.0, 0.0, 1.0)
		if burn <= 0.0:
			_sparks.emitting = false
			_smoke.emitting = false
			if burn < -5.0:
				queue_free()

## Процедурный звук мотора: низкий гул (самолёт), визг двухтактника (пила), шипение (горелка).
class Motor:
	extends AudioStreamPlayer3D
	var kind := &"plane"
	var rpm := 1.0
	var _gen: AudioStreamGeneratorPlayback
	var _ph := 0.0
	var _ph2 := 0.0
	var _lp := 0.0
	var _rate := 22050.0

	func _ready() -> void:
		var g := AudioStreamGenerator.new()
		g.mix_rate = _rate
		g.buffer_length = 0.25
		stream = g
		match kind:
			&"plane":
				max_distance = 900.0
				unit_size = 60.0
				volume_db = 6.0
			&"saw":
				max_distance = 220.0
				unit_size = 8.0
				volume_db = -4.0
			_:
				max_distance = 14.0
				unit_size = 2.0
				volume_db = -12.0
		attenuation_filter_cutoff_hz = 6000.0
		if DisplayServer.get_name() == "headless":
			return
		play()
		_gen = get_stream_playback() as AudioStreamGeneratorPlayback

	func _process(_d: float) -> void:
		if _gen == null:
			return
		var n := mini(_gen.get_frames_available(), 2048)
		var f0 := 0.0
		match kind:
			&"plane": f0 = 72.0 * rpm
			&"saw": f0 = 95.0 + 120.0 * rpm
		for i in n:
			var s := 0.0
			match kind:
				&"plane":
					_ph = fmod(_ph + f0 / _rate, 1.0)
					_ph2 = fmod(_ph2 + f0 * 1.51 / _rate, 1.0)
					var buzz := (_ph * 2.0 - 1.0) * 0.35 + (_ph2 * 2.0 - 1.0) * 0.2
					var wob := 0.7 + 0.3 * sin(_ph * TAU * 0.0625)
					_lp = lerpf(_lp, buzz + randf_range(-0.25, 0.25), 0.18)
					s = _lp * wob
				&"saw":
					_ph = fmod(_ph + f0 / _rate, 1.0)
					var pulse := 1.0 if _ph < 0.22 else -0.25
					_lp = lerpf(_lp, pulse * 0.5 + randf_range(-0.3, 0.3), 0.45)
					s = _lp
				_:
					_lp = lerpf(_lp, randf_range(-1.0, 1.0), 0.6)
					s = _lp * 0.4
			_gen.push_frame(Vector2(s, s))
