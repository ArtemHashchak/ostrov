class_name CombatFx
extends RefCounted
## Эффекты боя: звук в точке, вспышка и дым выстрела, взрыв, искры/щепки/кровь
## при попадании, огонь (частицы + свет). Только CPUParticles3D — работает и в Compatibility.

const SND := "res://assets/sounds/combat/"
const OCULUS := "res://assets/sounds/oculus_pack/"
static var _cache: Dictionary = {}
static var _tex: Dictionary = {}

## Сброс кэшей (при выходе модуля из дерева — иначе ресурсы «утекают» при закрытии игры).
static func clear_caches() -> void:
	_cache.clear()
	_tex.clear()

static func stream(sound_name: String) -> AudioStream:
	if _cache.has(sound_name):
		return _cache[sound_name]
	var p := ""
	match sound_name:
		"swoosh": p = OCULUS + "SWSH_Swoosh_OS_0%d.ogg" % randi_range(1, 3)
		"hit_flesh": p = OCULUS + "GORESqsh_BloodSquishSlimy_OS_01.ogg"
		"hit_metal": p = OCULUS + "METLImpt_MetalHitSurface_OS_01.ogg"
		"hit_wood_big": p = OCULUS + "WOODImpt_LargeWoodDrop_OS_01.ogg"
		"punch": p = OCULUS + "FGHTImpt_PunchRegular_OS_01.ogg"
		"splash": p = "res://assets/sounds/sfx-kit/props-splash.wav"
		"thunder": p = "res://assets/sounds/sfx-kit/cinematic-thunder-big.wav"
		_: p = SND + sound_name + ".wav"
	var s: AudioStream = load(p) as AudioStream if ResourceLoader.exists(p) else null
	if s is AudioStreamWAV and sound_name.ends_with("_loop"):
		var w := (s as AudioStreamWAV).duplicate() as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = w.data.size() / 2
		s = w
	if sound_name != "swoosh":
		_cache[sound_name] = s
	return s

static func sound_at(ctx: Node, sound_name: String, pos: Vector3, db: float = 0.0, max_dist: float = 60.0) -> AudioStreamPlayer3D:
	var s := stream(sound_name)
	if s == null or ctx == null or not ctx.is_inside_tree():
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = db
	p.max_distance = max_dist
	p.unit_size = 6.0 if max_dist > 100.0 else 3.0
	p.pitch_scale = randf_range(0.94, 1.06)
	p.attenuation_filter_cutoff_hz = 9000.0
	_scene(ctx).add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)
	return p

static func loop_on(parent: Node3D, sound_name: String, db: float = -6.0) -> AudioStreamPlayer3D:
	var s := stream(sound_name)
	if s == null:
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = db
	p.max_distance = 30.0
	p.autoplay = true
	parent.add_child(p)
	return p

static func _scene(ctx: Node) -> Node:
	var t := ctx.get_tree()
	return t.current_scene if t and t.current_scene else ctx

# ---------- текстуры частиц ----------

static func soft_tex(kind: String) -> Texture2D:
	if _tex.has(kind):
		return _tex[kind]
	var g := Gradient.new()
	match kind:
		"smoke":
			g.set_color(0, Color(1, 1, 1, 0.55))
			g.set_color(1, Color(1, 1, 1, 0.0))
			g.add_point(0.5, Color(1, 1, 1, 0.3))
		"flame":
			g.set_color(0, Color(1, 1, 1, 1))
			g.set_color(1, Color(1, 1, 1, 0))
			g.add_point(0.35, Color(1, 1, 1, 0.7))
		_:
			g.set_color(0, Color(1, 1, 1, 1))
			g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	_tex[kind] = t
	return t

static func particle_mat(kind: String, additive: bool) -> StandardMaterial3D:
	var key := "pm_" + kind + str(additive)
	if _tex.has(key):
		return _tex[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if additive else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = soft_tex(kind)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	if not additive:
		m.roughness = 1.0
		m.backlight_enabled = true
		m.backlight = Color(0.3, 0.3, 0.3)
	_tex[key] = m
	return m

static func particles(parent: Node, pos: Vector3, amount: int, life: float, kind: String, additive: bool,
		ramp: Gradient, size: float, vel: float, spread: float, dir: Vector3, grav: Vector3, one_shot: bool = true,
		explosive: float = 1.0) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = one_shot
	p.explosiveness = explosive if one_shot else 0.0
	var qm := QuadMesh.new()
	qm.size = Vector2(size, size)
	qm.material = particle_mat(kind, additive)
	p.mesh = qm
	p.direction = dir
	p.spread = spread
	p.initial_velocity_min = vel * 0.5
	p.initial_velocity_max = vel
	p.gravity = grav
	p.damping_min = 1.0
	p.damping_max = 3.0
	p.color_ramp = ramp
	p.angle_min = 0.0
	p.angle_max = 360.0
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.4))
	sc.add_point(Vector2(1, 1.6))
	p.scale_amount_curve = sc
	p.local_coords = false
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	if one_shot:
		p.finished.connect(p.queue_free)
	return p

static func _ramp(cols: Array) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, cols[0])
	g.set_color(1, cols[cols.size() - 1])
	for i in range(1, cols.size() - 1):
		g.add_point(float(i) / (cols.size() - 1), cols[i])
	return g

static func flash_light(parent: Node, pos: Vector3, color: Color, energy: float, rng: float, sec: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = false
	parent.add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, sec).set_ease(Tween.EASE_OUT)
	tw.tween_callback(l.queue_free)

# ---------- выстрел ----------

static func muzzle(ctx: Node, pos: Vector3, dir: Vector3, size: float = 1.0) -> void:
	var root := _scene(ctx)
	# вспышка: короткий конус огня
	particles(root, pos, 14, 0.08, "flame", true, _ramp([Color(1, 0.95, 0.7, 1), Color(1, 0.5, 0.1, 0.8), Color(0.6, 0.2, 0.05, 0)]),
		0.16 * size, 7.0 * size, 12.0, dir, Vector3.ZERO)
	# облако чёрного порохового дыма — густое, медленно расплывается
	particles(root, pos + dir * 0.1, int(26 * size) + 6, 3.2, "smoke", false,
		_ramp([Color(0.75, 0.74, 0.72, 0.9), Color(0.7, 0.7, 0.7, 0.55), Color(0.72, 0.72, 0.72, 0.0)]),
		0.45 * size + 0.2, 3.5 * size, 18.0, dir, Vector3(0.15, 0.25, 0.0))
	# дым из полки замка
	particles(root, pos - dir * 1.0 + Vector3.UP * 0.05, 8, 1.6, "smoke", false,
		_ramp([Color(0.8, 0.8, 0.78, 0.7), Color(0.75, 0.75, 0.75, 0.0)]), 0.18, 0.6, 60.0, Vector3.UP, Vector3(0.0, 0.3, 0.0))
	flash_light(root, pos, Color(1.0, 0.7, 0.35), 6.0 * size, 7.0, 0.09)

## SUPPLY: современный (бездымный) выстрел — короткая вспышка, лёгкий сизый дымок.
static func muzzle_modern(ctx: Node, pos: Vector3, dir: Vector3, size: float = 0.5) -> void:
	var root := _scene(ctx)
	particles(root, pos, 8, 0.05, "flame", true, _ramp([Color(1, 0.95, 0.75, 1), Color(1, 0.6, 0.2, 0.7), Color(0.6, 0.25, 0.05, 0)]),
		0.12 * size + 0.06, 6.0 * size, 14.0, dir, Vector3.ZERO)
	particles(root, pos + dir * 0.05, 4, 0.9, "smoke", false, _ramp([Color(0.8, 0.8, 0.82, 0.35), Color(0.8, 0.8, 0.8, 0.0)]),
		0.12 + 0.1 * size, 1.2, 25.0, dir, Vector3(0.0, 0.3, 0.0))
	flash_light(root, pos, Color(1.0, 0.75, 0.4), 4.0 * size + 1.0, 5.0, 0.05)

# ---------- попадания ----------

static func impact(ctx: Node, pos: Vector3, normal: Vector3, surface: StringName) -> void:
	var root := _scene(ctx)
	match surface:
		&"flesh":
			particles(root, pos, 14, 0.5, "smoke", false, _ramp([Color(0.45, 0.02, 0.02, 0.95), Color(0.3, 0.0, 0.0, 0.0)]),
				0.07, 2.5, 35.0, normal, Vector3(0, -9.8, 0))
			sound_at(ctx, "hit_flesh", pos, -4.0)
		&"water":
			particles(root, pos, 18, 0.8, "smoke", false, _ramp([Color(0.85, 0.92, 0.95, 0.8), Color(0.9, 0.95, 1.0, 0.0)]),
				0.12, 4.0, 15.0, Vector3.UP, Vector3(0, -9.8, 0))
			sound_at(ctx, "splash", pos, -8.0)
		&"wood":
			particles(root, pos, 10, 0.7, "smoke", false, _ramp([Color(0.5, 0.38, 0.24, 0.9), Color(0.5, 0.4, 0.3, 0.0)]),
				0.05, 3.0, 40.0, normal, Vector3(0, -9.8, 0))
			sound_at(ctx, "arrow_hit_wood", pos, -2.0)
		_:
			particles(root, pos, 10, 0.9, "smoke", false, _ramp([Color(0.55, 0.5, 0.45, 0.7), Color(0.6, 0.55, 0.5, 0.0)]),
				0.12, 1.5, 40.0, normal, Vector3(0, -2.0, 0))
			sound_at(ctx, "arrow_hit_soft", pos, -6.0)

# ---------- огонь ----------

## Пламя (непрерывное) как ребёнок узла. scale — размер костра.
static func flames(parent: Node3D, scale: float, extents: Vector3 = Vector3.ZERO) -> Node3D:
	var root := Node3D.new()
	root.name = "Flames"
	parent.add_child(root)
	var f := CPUParticles3D.new()
	f.amount = int(clampf(28.0 * scale, 8.0, 90.0))
	f.lifetime = 0.7
	var qm := QuadMesh.new()
	qm.size = Vector2(0.45, 0.6) * clampf(scale, 0.15, 1.4)
	qm.material = particle_mat("flame", true)
	f.mesh = qm
	f.direction = Vector3.UP
	f.spread = 12.0
	f.initial_velocity_min = 0.6
	f.initial_velocity_max = 1.6 * maxf(scale, 0.4)
	f.gravity = Vector3(0, 1.5, 0)
	f.color_ramp = _ramp([Color(1, 0.85, 0.45, 0.0), Color(1, 0.7, 0.25, 0.95), Color(1, 0.35, 0.05, 0.7), Color(0.4, 0.1, 0.02, 0.0)])
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.7))
	sc.add_point(Vector2(0.4, 1.0))
	sc.add_point(Vector2(1, 0.25))
	f.scale_amount_curve = sc
	f.angle_min = -20.0
	f.angle_max = 20.0
	if extents != Vector3.ZERO:
		f.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		f.emission_box_extents = extents
	f.local_coords = false
	root.add_child(f)
	var s := CPUParticles3D.new()
	s.amount = int(clampf(12.0 * scale, 4.0, 40.0))
	s.lifetime = 3.0
	var sm := QuadMesh.new()
	sm.size = Vector2.ONE * 0.9 * clampf(scale, 0.2, 1.5)
	sm.material = particle_mat("smoke", false)
	s.mesh = sm
	s.direction = Vector3.UP
	s.spread = 15.0
	s.initial_velocity_min = 0.8
	s.initial_velocity_max = 1.8
	s.gravity = Vector3(0.3, 0.6, 0)
	s.color_ramp = _ramp([Color(0.15, 0.13, 0.12, 0.0), Color(0.18, 0.16, 0.15, 0.55), Color(0.3, 0.3, 0.3, 0.0)])
	var sc2 := Curve.new()
	sc2.add_point(Vector2(0, 0.5))
	sc2.add_point(Vector2(1, 2.2))
	s.scale_amount_curve = sc2
	if extents != Vector3.ZERO:
		s.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		s.emission_box_extents = extents
	s.local_coords = false
	s.position = Vector3(0, 0.5 * scale, 0)
	root.add_child(s)
	var l := OmniLight3D.new()
	l.name = "Light"
	l.light_color = Color(1.0, 0.55, 0.2)
	l.light_energy = 1.5 * clampf(scale, 0.3, 2.0)
	l.omni_range = 4.0 + 4.0 * scale
	l.position = Vector3(0, 0.5, 0)
	root.add_child(l)
	var flick := Flicker.new()
	flick.light = l
	flick.base = l.light_energy
	root.add_child(flick)
	return root

class Flicker:
	extends Node
	var light: OmniLight3D
	var base := 1.0
	var _t := randf() * 10.0
	func _process(delta: float) -> void:
		_t += delta
		if light:
			light.light_energy = base * (0.8 + 0.2 * sin(_t * 13.0) * sin(_t * 7.3 + 1.0) + randf() * 0.1)

# ---------- взрыв ----------

static func explosion(pos: Vector3, radius: float) -> void:
	var t := Engine.get_main_loop() as SceneTree
	if t == null or t.current_scene == null:
		return
	var root := t.current_scene
	var s := radius / 6.0
	particles(root, pos, 40, 0.5, "flame", true,
		_ramp([Color(1, 0.95, 0.8, 1), Color(1, 0.6, 0.15, 0.95), Color(0.6, 0.2, 0.05, 0.6), Color(0.1, 0.05, 0.02, 0)]),
		1.4 * s, 14.0 * s, 180.0, Vector3.UP, Vector3(0, 2.0, 0))
	particles(root, pos, 46, 5.0, "smoke", false,
		_ramp([Color(0.18, 0.16, 0.14, 0.95), Color(0.3, 0.28, 0.26, 0.7), Color(0.45, 0.44, 0.42, 0.0)]),
		2.2 * s, 8.0 * s, 180.0, Vector3.UP, Vector3(0, 1.2, 0))
	# комья земли/щепки
	particles(root, pos, 40, 1.6, "smoke", false, _ramp([Color(0.25, 0.2, 0.15, 1), Color(0.25, 0.2, 0.15, 0.0)]),
		0.12, 16.0 * s, 70.0, Vector3.UP, Vector3(0, -9.8, 0))
	flash_light(root, pos + Vector3.UP, Color(1.0, 0.65, 0.3), 16.0, radius * 4.0, 0.45)
	var p := AudioStreamPlayer3D.new()
	p.stream = stream("explosion")
	p.max_distance = 400.0
	p.unit_size = 12.0
	p.volume_db = 6.0
	root.add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)
