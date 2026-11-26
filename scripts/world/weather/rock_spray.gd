class_name RockSpray
extends Node3D
## Брызги о скалы (v5, агент D): вдоль скалистого берега рядом с камерой (60–80 м) ищутся точки удара
## волны; когда гребень у точки поднимается выше порога, вылетает веер брызг (пул эмиттеров,
## без симуляции жидкости). Сила и частота — от волн/шторма. Пресет: Низкое/Среднее — 4/8 точек и
## меньше частиц, Высокое/Ультра — 12 точек и полный веер.

const SCAN_EVERY := 3.0
const RADIUS := 75.0
const STEP := 6.0

var _pts: Array = []        # [Vector3 точка, Vector2 к морю, prev_h, cooldown]
var _pool: Array[CPUParticles3D] = []
var _next := 0
var _scan_t := 99.0
var _world: Node = null

func update_spray(dt: float, world: Node, cam: Camera3D, storm: float) -> void:
	_world = world
	if world == null or cam == null or not world.has_method(&"wave_height"):
		return
	_scan_t += dt
	if _scan_t >= SCAN_EVERY:
		_scan_t = 0.0
		_scan(cam.global_position)
	var wl := float(world.water_level())
	var thr := lerpf(0.55, 0.3, storm)
	for e: Array in _pts:
		var p: Vector3 = e[0]
		e[3] = maxf(float(e[3]) - dt, 0.0)
		var h := float(world.wave_height(p.x, p.z)) - wl
		var prev := float(e[2])
		e[2] = h
		# гребень дошёл до скалы: рост сменился спадом выше порога
		if prev > h and prev > thr and float(e[3]) <= 0.0:
			e[3] = lerpf(2.5, 1.0, storm)
			_burst(p + Vector3(0, prev, 0), e[1], clampf(prev / 1.2, 0.3, 1.6) * (0.6 + 0.6 * storm))

func _scan(c: Vector3) -> void:
	var q := Settings.graphics_quality
	var maxn := 4 if q <= 0 else (8 if q == 1 else 12)
	var wl := float(_world.water_level())
	var found: Array = []
	var x := -RADIUS
	while x <= RADIUS:
		var z := -RADIUS
		while z <= RADIUS:
			var px := c.x + x
			var pz := c.z + z
			var h := float(_world.height_at(px, pz))
			if h > wl - 0.4 and h < wl + 1.6 and _world.biome_at(px, pz) == &"rocky":
				# к морю — направление спуска рельефа
				var gx := float(_world.height_at(px + 2.0, pz)) - float(_world.height_at(px - 2.0, pz))
				var gz := float(_world.height_at(px, pz + 2.0)) - float(_world.height_at(px, pz - 2.0))
				var sea := -Vector2(gx, gz)
				if sea.length() > 0.2 and float(_world.height_at(px + sea.normalized().x * 4.0, pz + sea.normalized().y * 4.0)) < wl - 0.3:
					found.append([Vector3(px, h, pz), sea.normalized(), 0.0, randf() * 2.0, Vector2(x, z).length_squared()])
			z += STEP
		x += STEP
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[4] < b[4])
	_pts = found.slice(0, maxn)

func _burst(at: Vector3, sea: Vector2, k: float) -> void:
	var q := Settings.graphics_quality
	if _pool.size() < (6 if q <= 1 else 10):
		var e := CPUParticles3D.new()
		e.one_shot = true
		e.explosiveness = 0.85
		e.lifetime = 1.4
		e.local_coords = false
		e.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		e.emission_box_extents = Vector3(1.2, 0.2, 1.2)
		e.spread = 28.0
		e.gravity = Vector3(0, -9.8, 0)
		e.damping_min = 0.5
		e.damping_max = 1.5
		var m := QuadMesh.new()
		m.size = Vector2.ONE
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.92, 0.96, 0.98, 0.7)
		mat.vertex_color_use_as_albedo = true
		m.material = mat
		e.mesh = m
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 0.85))
		g.set_color(1, Color(1, 1, 1, 0.0))
		e.color_ramp = g
		var sc := Curve.new()
		sc.add_point(Vector2(0, 0.5))
		sc.add_point(Vector2(1, 1.6))
		e.scale_amount_curve = sc
		add_child(e)
		_pool.append(e)
	var e2: CPUParticles3D = _pool[_next % _pool.size()]
	_next += 1
	e2.global_position = at
	# брызги летят вверх и назад от моря (на скалу)
	e2.direction = Vector3(-sea.x * 0.6, 1.0, -sea.y * 0.6).normalized()
	e2.amount = int((18 if q <= 1 else 40) * clampf(k, 0.3, 1.5))
	e2.initial_velocity_min = 3.0 * k
	e2.initial_velocity_max = 7.5 * k
	e2.scale_amount_min = 0.25 * k
	e2.scale_amount_max = 0.7 * k
	e2.restart()
	e2.emitting = true

func points() -> int:
	return _pts.size()
