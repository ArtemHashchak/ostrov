class_name GunFx
extends RefCounted
## Эффекты современного огнестрела (WeaponDef): короткая вспышка у дула (меш-«звезда» +
## свет), пороховые газы и дымок из ствола (греется при очереди), газы из окна выброса,
## гильзы с физикой (исчезают, лимит), трассеры, попадания по поверхностям (рельеф/песок/
## дерево/камень/металл/вода/плоть/солома — свои искры, щепки, пыль, брызги) и следы-декали
## (квад с текстурой — работает и в Compatibility; лимит). Только CPUParticles3D.

const MAX_CASINGS := 24
const MAX_DECALS := 48
const CASING_LIFE := 6.0
const DECAL_LIFE := 90.0

static var _tex: Dictionary = {}
static var _casings: Array = []
static var _decals: Array = []
static var _clink_t := 0.0

static func clear_caches() -> void:
	_tex.clear()
	_casings.clear()
	_decals.clear()

static func _scene(ctx: Node) -> Node:
	return CombatFx._scene(ctx)

## Сколько гильз/декалей сейчас в мире (для тестов и отладки).
static func casing_count() -> int:
	_casings = _casings.filter(func(n: Variant) -> bool: return is_instance_valid(n) and not (n as Node).is_queued_for_deletion())
	return _casings.size()

static func decal_count() -> int:
	_decals = _decals.filter(func(n: Variant) -> bool: return is_instance_valid(n) and not (n as Node).is_queued_for_deletion())
	return _decals.size()

# ======================= выстрел =======================

## Выстрел: вспышка (на сокете дула, если дан — следует за моделью), газы, звук.
static func shot(ctx: Node, pos: Vector3, dir: Vector3, d: WeaponDef, muzzle: Node3D = null) -> void:
	if ctx == null or not ctx.is_inside_tree():
		return
	var root := _scene(ctx)
	muzzle_flash(root, pos, dir, d.flash_size, muzzle)
	# пороховые газы: быстрый сизый выхлоп вперёд + медленное облачко
	var s := d.smoke
	CombatFx.particles(root, pos + dir * 0.03, int(4 + 6 * s), 0.35, "smoke", false,
		CombatFx._ramp([Color(0.85, 0.85, 0.86, 0.45 * s), Color(0.8, 0.8, 0.8, 0.0)]), 0.08 + 0.08 * s, 4.0, 18.0, dir, Vector3(0, 0.2, 0))
	CombatFx.particles(root, pos + dir * 0.1, int(2 + 3 * s), 1.4, "smoke", false,
		CombatFx._ramp([Color(0.82, 0.82, 0.84, 0.25 * s), Color(0.8, 0.8, 0.8, 0.0)]), 0.2 + 0.15 * s, 0.8, 40.0, dir, Vector3(0.05, 0.35, 0))
	if d.muzzle_brake:
		# дульный тормоз-компенсатор (АК): газы бьют в стороны и вверх — два боковых «уса»
		# и короткая вспышка сбоку
		var side := dir.cross(Vector3.UP)
		if side.length() < 0.1:
			side = Vector3.RIGHT
		side = side.normalized()
		for sg: float in [-1.0, 1.0]:
			var sd := (side * sg + Vector3.UP * 0.35 + dir * 0.2).normalized()
			CombatFx.particles(root, pos + dir * 0.02, int(3 + 4 * s), 0.3, "smoke", false,
				CombatFx._ramp([Color(0.86, 0.86, 0.87, 0.5 * s), Color(0.8, 0.8, 0.8, 0.0)]), 0.06 + 0.06 * s, 3.2, 14.0, sd, Vector3(0, 0.25, 0))
		muzzle_flash(root, pos + Vector3.UP * 0.012, (Vector3.UP * 0.6 + dir).normalized(), d.flash_size * 0.45, muzzle)
	var a := CombatFx.sound_at(ctx, d.sound_shot, pos, d.sound_volume, 260.0)
	if a:
		a.pitch_scale = d.sound_pitch * randf_range(0.96, 1.04)

static func _flash_mat() -> StandardMaterial3D:
	if _tex.has("flash_mat"):
		return _tex["flash_mat"]
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 0.9, 1))
	g.add_point(0.25, Color(1, 0.85, 0.45, 0.95))
	g.add_point(0.6, Color(1, 0.45, 0.1, 0.45))
	g.set_color(1, Color(1, 0.3, 0.05, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = t
	m.albedo_color = Color(1.0, 0.9, 0.7)
	m.disable_receive_shadows = true
	_tex["flash_mat"] = m
	return m

## Вспышка: «звезда» из трёх квадов (поперёк ствола + два вдоль) и свет, ~50 мс.
static func muzzle_flash(root: Node, pos: Vector3, dir: Vector3, size: float, attach: Node3D = null) -> Node3D:
	var f := Node3D.new()
	f.name = "MuzzleFlash"
	var m := _flash_mat()
	var k := size * randf_range(0.8, 1.2)
	var face := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.11, 0.11) * k
	face.mesh = q
	face.material_override = m
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	face.rotation.z = randf() * TAU
	f.add_child(face)
	for i in 2:
		var side := MeshInstance3D.new()
		var qs := QuadMesh.new()
		qs.size = Vector2(0.07, 0.2) * k
		side.mesh = qs
		side.material_override = m
		side.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# вдоль ствола (-Z), развёрнуто на 90° друг к другу
		side.basis = Basis(Vector3.FORWARD, PI * 0.5 * i + randf_range(-0.3, 0.3)) * Basis(Vector3.RIGHT, -PI * 0.5)
		side.position = Vector3(0, 0, -0.08 * k)
		f.add_child(side)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.72, 0.38)
	l.light_energy = 3.0 + 4.0 * size
	l.omni_range = 4.0 + 3.0 * size
	l.shadow_enabled = false
	l.position = Vector3(0, 0, -0.05)
	f.add_child(l)
	if attach and attach.is_inside_tree():
		attach.add_child(f)
	else:
		root.add_child(f)
		var xf := Transform3D.IDENTITY
		xf.origin = pos
		if absf(dir.normalized().dot(Vector3.UP)) < 0.99:
			xf = xf.looking_at(pos + dir, Vector3.UP)
		f.global_transform = xf
	var tw := f.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.06)
	tw.parallel().tween_property(f, "scale", Vector3.ONE * 0.4, 0.05)
	tw.tween_callback(f.queue_free)
	return f

## Газы из окна выброса (вбок-вверх).
static func port_gas(ctx: Node, pos: Vector3, side: Vector3, s: float) -> void:
	CombatFx.particles(_scene(ctx), pos, int(2 + 3 * s), 0.6, "smoke", false,
		CombatFx._ramp([Color(0.8, 0.8, 0.82, 0.3 * s), Color(0.8, 0.8, 0.8, 0.0)]), 0.05, 0.7, 35.0, (side + Vector3.UP * 0.6).normalized(), Vector3(0, 0.3, 0))

## Дымок из нагретого ствола: постоянный эмиттер на сокете дула (CombatController включает
## его после очереди; .color.a — сила).
static func barrel_smoke(muzzle: Node3D) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "BarrelSmoke"
	p.amount = 14
	p.lifetime = 1.6
	p.one_shot = false
	var qm := QuadMesh.new()
	qm.size = Vector2(0.05, 0.05)
	qm.material = CombatFx.particle_mat("smoke", false)
	p.mesh = qm
	p.direction = Vector3.UP
	p.spread = 12.0
	p.initial_velocity_min = 0.08
	p.initial_velocity_max = 0.22
	p.gravity = Vector3(0.02, 0.25, 0.0)
	p.damping_min = 0.2
	p.damping_max = 0.6
	p.color_ramp = CombatFx._ramp([Color(0.85, 0.85, 0.87, 0.0), Color(0.82, 0.82, 0.84, 0.35), Color(0.8, 0.8, 0.8, 0.0)])
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.6))
	sc.add_point(Vector2(1, 3.0))
	p.scale_amount_curve = sc
	p.local_coords = false
	p.emitting = false
	muzzle.add_child(p)
	return p

# ======================= гильзы =======================

static func _brass() -> Material:
	if not _tex.has("brass"):
		var m := HeldModels.color_mat(Color(0.78, 0.6, 0.28), 0.32, 0.9)
		_tex["brass"] = m
	return _tex["brass"]

## Гильза из окна выброса: вправо-вверх-назад, вращается, звенит при падении, через
## CASING_LIFE с исчезает. Не больше MAX_CASINGS (старые убираются).
static func eject_casing(ctx: Node, port: Transform3D, right: Vector3, up: Vector3, back: Vector3, inherit: Vector3, d: WeaponDef) -> RigidBody3D:
	if ctx == null or not ctx.is_inside_tree():
		return null
	casing_count()
	while _casings.size() >= MAX_CASINGS:
		var old: Variant = _casings.pop_front()
		if is_instance_valid(old):
			(old as Node).queue_free()
	var b := RigidBody3D.new()
	b.name = "Casing"
	b.mass = 0.012
	b.collision_layer = 0
	b.collision_mask = 1
	b.continuous_cd = true
	b.contact_monitor = true
	b.max_contacts_reported = 1
	b.angular_damp = 1.5
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.35
	pm.friction = 0.7
	b.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(d.casing_r * 2.0, d.casing_len, d.casing_r * 2.0)
	cs.shape = sh
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = d.casing_r * 0.85
	cm.bottom_radius = d.casing_r
	cm.height = d.casing_len
	cm.radial_segments = 8
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = _brass()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.add_child(mi)
	_scene(ctx).add_child(b)
	# ось гильзы — поперёк ствола (вдоль right)
	var bas := Basis(right.cross(up).normalized(), right.normalized(), up.normalized()).orthonormalized()
	b.global_transform = Transform3D(bas, port.origin)
	b.linear_velocity = inherit + right * randf_range(1.6, 2.6) + up * randf_range(1.2, 2.0) + back * randf_range(0.1, 0.6)
	b.angular_velocity = Vector3(randf_range(-25, 25), randf_range(-8, 8), randf_range(-25, 25))
	b.body_entered.connect(GunFx._on_casing_hit.bind(b), CONNECT_ONE_SHOT)
	var tw := b.create_tween()
	tw.tween_interval(CASING_LIFE)
	tw.tween_property(mi, "scale", Vector3.ONE * 0.05, 0.4)
	tw.tween_callback(b.queue_free)
	_casings.append(b)
	return b

static func _on_casing_hit(_other: Node, b: RigidBody3D) -> void:
	if not is_instance_valid(b):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _clink_t < 0.07:
		return
	_clink_t = now
	var a := CombatFx.sound_at(b, "hit_metal", b.global_position, -24.0, 18.0)
	if a:
		a.pitch_scale = randf_range(2.4, 3.0)

# ======================= трассер =======================

## Светящийся штрих позади пули (узел снаряда смотрит -Z по скорости). Длину задаёт снаряд.
static func tracer(parent: Node3D, col: Color) -> MeshInstance3D:
	var key := "tracer_%s" % col.to_html()
	var m: StandardMaterial3D = _tex.get(key)
	if m == null:
		m = StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = Color(col.r, col.g, col.b, 0.95)
		m.disable_receive_shadows = true
		_tex[key] = m
	var mi := MeshInstance3D.new()
	mi.name = "Tracer"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.022, 0.022, 1.0)
	mi.mesh = bm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	parent.add_child(mi)
	return mi

# ======================= попадания =======================

## Материал поверхности по коллайдеру: meta "surface" у узла или предка, затем группы.
static func surface_of(col: Node, pos: Vector3, normal: Vector3 = Vector3.UP) -> StringName:
	var cur := col
	for i in 6:
		if cur == null:
			break
		if cur.has_meta(&"surface"):
			return StringName(cur.get_meta(&"surface"))
		if cur.is_in_group(&"rocks") or cur.is_in_group(&"ore") or cur.is_in_group(&"rubble"):
			return &"stone"
		if cur.is_in_group(&"trees") or cur.is_in_group(&"choppable") or cur.is_in_group(&"buildable") \
				or cur.is_in_group(&"log") or cur.is_in_group(&"stumps") or cur.is_in_group(&"raft_deck"):
			return &"wood"
		if cur.is_in_group(&"wrecks") or cur.is_in_group(&"supply_crates") or cur.is_in_group(&"supply_planes"):
			return &"metal"
		if cur.is_in_group(&"characters") or cur.is_in_group(&"animals") or cur.is_in_group(&"sharks") or cur.is_in_group(&"player"):
			return &"flesh"
		if cur.is_in_group(&"terrain"):
			if normal.y < 0.6:
				return &"stone"
			return &"sand" if pos.y < BuildEnv.water_level() + 1.3 else &"dirt"
		cur = cur.get_parent()
	return &"dirt"

## Попадание пули: частицы/звук по материалу + декаль (кроме воды и плоти).
static func bullet_impact(ctx: Node, col: Node, pos: Vector3, normal: Vector3, surface: StringName, vel: Vector3 = Vector3.ZERO) -> void:
	if ctx == null or not ctx.is_inside_tree():
		return
	var root := _scene(ctx)
	var n := normal.normalized() if normal.length() > 0.01 else Vector3.UP
	var refl := (vel.normalized().bounce(n) if vel.length() > 0.1 else n).normalized()
	var a: AudioStreamPlayer3D = null
	match surface:
		&"flesh":
			CombatFx.impact(ctx, pos, n, &"flesh")
		&"water":
			CombatFx.particles(root, pos, 16, 0.9, "smoke", false, CombatFx._ramp([Color(0.9, 0.95, 1.0, 0.85), Color(0.9, 0.95, 1.0, 0.0)]),
				0.09, 5.5, 10.0, Vector3.UP, Vector3(0, -9.8, 0))
			CombatFx.particles(root, pos, 6, 1.2, "smoke", false, CombatFx._ramp([Color(0.92, 0.96, 1.0, 0.5), Color(0.9, 0.95, 1.0, 0.0)]),
				0.3, 0.8, 80.0, Vector3.UP, Vector3(0, -0.5, 0))
			a = CombatFx.sound_at(ctx, "splash", pos, -12.0, 50.0)
			if a:
				a.pitch_scale = randf_range(1.5, 1.9)
		&"wood":
			CombatFx.particles(root, pos, 12, 0.8, "smoke", false, CombatFx._ramp([Color(0.72, 0.56, 0.36, 1.0), Color(0.6, 0.45, 0.3, 0.0)]),
				0.03, 4.5, 35.0, refl, Vector3(0, -9.8, 0))
			CombatFx.particles(root, pos, 5, 0.9, "smoke", false, CombatFx._ramp([Color(0.55, 0.45, 0.32, 0.5), Color(0.55, 0.45, 0.32, 0.0)]),
				0.12, 0.9, 50.0, n, Vector3(0, -0.4, 0))
			a = CombatFx.sound_at(ctx, "arrow_hit_wood", pos, -6.0, 50.0)
			if a:
				a.pitch_scale = randf_range(1.3, 1.6)
		&"stone":
			_sparks(root, pos, refl, 9, 0.22)
			CombatFx.particles(root, pos, 8, 1.0, "smoke", false, CombatFx._ramp([Color(0.7, 0.68, 0.64, 0.7), Color(0.7, 0.68, 0.64, 0.0)]),
				0.12, 1.6, 45.0, n, Vector3(0, -1.0, 0))
			CombatFx.particles(root, pos, 6, 0.6, "smoke", false, CombatFx._ramp([Color(0.5, 0.48, 0.45, 1.0), Color(0.5, 0.48, 0.45, 0.0)]),
				0.025, 4.0, 40.0, refl, Vector3(0, -9.8, 0))
			a = CombatFx.sound_at(ctx, "hit_metal", pos, -14.0, 50.0)
			if a:
				a.pitch_scale = randf_range(1.7, 2.1)
		&"metal":
			_sparks(root, pos, refl, 16, 0.3)
			CombatFx.flash_light(root, pos + n * 0.05, Color(1.0, 0.8, 0.5), 2.0, 2.5, 0.05)
			a = CombatFx.sound_at(ctx, "hit_metal", pos, -2.0, 90.0)
			if a:
				a.pitch_scale = randf_range(1.15, 1.35)
		&"straw":
			CombatFx.particles(root, pos, 10, 0.9, "smoke", false, CombatFx._ramp([Color(0.9, 0.78, 0.45, 1.0), Color(0.85, 0.72, 0.4, 0.0)]),
				0.035, 2.5, 50.0, refl, Vector3(0, -6.0, 0))
			CombatFx.particles(root, pos, 4, 0.8, "smoke", false, CombatFx._ramp([Color(0.8, 0.72, 0.5, 0.4), Color(0.8, 0.72, 0.5, 0.0)]),
				0.12, 0.6, 50.0, n, Vector3(0, -0.3, 0))
			CombatFx.sound_at(ctx, "arrow_hit_soft", pos, -6.0, 40.0)
		_: # рельеф / песок
			var sand := surface == &"sand"
			var dust := Color(0.78, 0.7, 0.55) if sand else Color(0.45, 0.37, 0.28)
			CombatFx.particles(root, pos, 10, 1.1, "smoke", false, CombatFx._ramp([Color(dust, 0.75), Color(dust, 0.0)]),
				0.14, 1.8, 30.0, n, Vector3(0, -1.2, 0))
			CombatFx.particles(root, pos, 8, 0.7, "smoke", false, CombatFx._ramp([Color(dust.darkened(0.3), 1.0), Color(dust.darkened(0.3), 0.0)]),
				0.03, 3.6, 30.0, n, Vector3(0, -9.8, 0))
			CombatFx.sound_at(ctx, "arrow_hit_soft", pos, -8.0, 40.0)
	if surface != &"water" and surface != &"flesh":
		decal(ctx, col, pos, n, surface)

static func _sparks(root: Node, pos: Vector3, dir: Vector3, amount: int, life: float) -> void:
	var p := CombatFx.particles(root, pos, amount, life, "flame", true,
		CombatFx._ramp([Color(1, 0.95, 0.7, 1), Color(1, 0.6, 0.15, 0.9), Color(1, 0.3, 0.05, 0)]), 0.025, 9.0, 40.0, dir, Vector3(0, -9.8, 0))
	p.damping_min = 0.0
	p.damping_max = 0.5

static func _decal_mat(surface: StringName) -> StandardMaterial3D:
	var key := "decal_" + String(surface)
	if _tex.has(key):
		return _tex[key]
	var hole := Color(0.06, 0.05, 0.04)
	var ring := Color(0.3, 0.24, 0.17)
	match surface:
		&"sand":
			hole = Color(0.42, 0.35, 0.24)
			ring = Color(0.55, 0.47, 0.34)
		&"wood":
			hole = Color(0.07, 0.045, 0.025)
			ring = Color(0.78, 0.62, 0.42)
		&"stone":
			hole = Color(0.2, 0.19, 0.18)
			ring = Color(0.82, 0.8, 0.76)
		&"metal":
			hole = Color(0.04, 0.04, 0.045)
			ring = Color(0.85, 0.85, 0.88)
		&"straw":
			hole = Color(0.12, 0.09, 0.04)
			ring = Color(0.5, 0.4, 0.2)
	var g := Gradient.new()
	g.set_color(0, Color(hole, 1.0))
	g.add_point(0.3, Color(hole, 1.0))
	g.add_point(0.42, Color(ring, 0.95))
	g.add_point(0.7, Color(ring, 0.35))
	g.set_color(1, Color(ring, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	var m := StandardMaterial3D.new()
	m.albedo_texture = t
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.9 if surface != &"metal" else 0.35
	m.metallic = 0.6 if surface == &"metal" else 0.0
	m.cull_mode = BaseMaterial3D.CULL_BACK
	m.render_priority = 1
	_tex[key] = m
	return m

const DECAL_SIZE := {&"dirt": 0.07, &"sand": 0.08, &"wood": 0.05, &"stone": 0.055, &"metal": 0.04, &"straw": 0.05}

## След от пули: квад по нормали поверхности. Движущиеся цели (meta "decals_follow" или
## персонажи) несут след на себе. Не больше MAX_DECALS — старые убираются.
static func decal(ctx: Node, col: Node, pos: Vector3, normal: Vector3, surface: StringName) -> MeshInstance3D:
	decal_count()
	while _decals.size() >= MAX_DECALS:
		var old: Variant = _decals.pop_front()
		if is_instance_valid(old):
			(old as Node).queue_free()
	var mi := MeshInstance3D.new()
	mi.name = "BulletDecal"
	var q := QuadMesh.new()
	var s := float(DECAL_SIZE.get(surface, 0.06)) * randf_range(0.85, 1.15)
	q.size = Vector2(s, s)
	mi.mesh = q
	mi.material_override = _decal_mat(surface)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var host: Node = _scene(ctx)
	if col is Node3D and (col.has_meta(&"decals_follow") or col.is_in_group(&"characters")):
		host = col
	host.add_child(mi)
	var z := normal.normalized()
	var x := z.cross(Vector3.UP if absf(z.y) < 0.95 else Vector3.RIGHT).normalized()
	var y := z.cross(x).normalized()
	var bas := Basis(x, y, z) * Basis(Vector3.BACK, randf() * TAU)
	mi.global_transform = Transform3D(bas, pos + z * 0.004)
	var tw := mi.create_tween()
	tw.tween_interval(DECAL_LIFE)
	tw.tween_callback(mi.queue_free)
	_decals.append(mi)
	return mi
