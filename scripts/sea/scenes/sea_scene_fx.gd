class_name SeaSceneFx
extends RefCounted
## Дешёвые эффекты сцен моря (CPUParticles3D — работают и в Compatibility), сами исчезают:
## облачко песка, муть, икра, пузыри, искры планктона, обломки и клочья водорослей в шторм.

static var _mat_alpha: StandardMaterial3D = null
static var _mat_add: StandardMaterial3D = null

static func clear_cache() -> void:
	_mat_alpha = null
	_mat_add = null

static func _soft_tex() -> GradientTexture2D:
	var g := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 1))
	gr.set_color(1, Color(1, 1, 1, 0))
	g.gradient = gr
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	g.width = 32
	g.height = 32
	return g

static func _mat(additive: bool) -> StandardMaterial3D:
	if additive and _mat_add:
		return _mat_add
	if not additive and _mat_alpha:
		return _mat_alpha
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_tex()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	if additive:
		_mat_add = m
	else:
		_mat_alpha = m
	return m

## Базовая система частиц. dur > 0 — испускать dur секунд, потом угаснуть и удалиться.
static func _make(parent: Node, at: Vector3, amount: int, life: float, col_a: Color, col_b: Color, size_a: float, size_b: float, additive: bool, dur: float) -> CPUParticles3D:
	if parent == null or not parent.is_inside_tree():
		return null
	# В Compatibility слоты частиц, которые ещё не «родились» (непрерывная/растянутая эмиссия,
	# explosiveness < 1), рисуются тёмным диском под туманом. Поэтому каждый выброс — мгновенный
	# (explosiveness = 1), а длинное облако на dur секунд — серия коротких выбросов.
	var bursts := 1 if dur <= 0.0 else clampi(int(ceil(dur / 0.6)), 2, 14)
	var p := CPUParticles3D.new()
	p.amount = maxi(int(ceil(float(amount) / bursts)), 1)
	p.lifetime = life
	p.local_coords = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.scale_amount_min = size_a
	p.scale_amount_max = size_b
	var grad := Gradient.new()
	grad.set_color(0, col_a)
	grad.set_color(1, col_b)
	p.color_ramp = grad
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = _mat(additive)
	p.mesh = q
	p.emitting = false
	parent.add_child(p)
	p.global_position = at
	var tw := p.create_tween()
	# первый выброс — на следующем кадре, когда вызывающий уже настроил форму/скорость
	tw.tween_interval(0.0)
	tw.tween_callback(func() -> void:
		p.explosiveness = 1.0
		p.emitting = true)
	for i in range(1, bursts):
		tw.tween_interval(dur / bursts)
		tw.tween_callback(func() -> void:
			if not is_instance_valid(p) or not p.is_inside_tree():
				return
			var c := p.duplicate() as CPUParticles3D
			p.get_parent().add_child(c)
			c.global_position = p.global_position
			c.explosiveness = 1.0
			c.emitting = true
			var tc := c.create_tween()
			tc.tween_interval(c.lifetime + 0.3)
			tc.tween_callback(c.queue_free))
	tw.tween_interval(life + 0.3)
	tw.tween_callback(p.queue_free)
	return p

## Облачко песка (скат взлетел со дна, рыба-попугай «пылит», краб закопался).
static func sand_plume(parent: Node, at: Vector3, size: float = 0.6, col: Color = Color(0.82, 0.76, 0.6)) -> void:
	var p := _make(parent, at, 18, 2.6, Color(col.r, col.g, col.b, 0.55), Color(col.r, col.g, col.b, 0.0), size * 0.5, size * 1.6, false, 0.0)
	if p:
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = size * 0.3
		p.direction = Vector3.UP
		p.spread = 70.0
		p.initial_velocity_min = 0.1
		p.initial_velocity_max = 0.5 * size + 0.2
		p.gravity = Vector3(0.0, -0.04, 0.0)
		p.damping_min = 0.4
		p.damping_max = 0.9

## Муть/икра/планктон в объёме: облако радиуса r на dur секунд.
static func cloud(parent: Node, at: Vector3, r: float, col: Color, amount: int, dur: float, size: float = 0.08, rise: float = 0.05) -> CPUParticles3D:
	var p := _make(parent, at, amount, 4.0, col, Color(col.r, col.g, col.b, 0.0), size * 0.6, size * 1.4, false, dur)
	if p:
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = r
		p.direction = Vector3.UP
		p.spread = 180.0
		p.initial_velocity_min = 0.0
		p.initial_velocity_max = 0.08
		p.gravity = Vector3(0.0, rise, 0.0)
	return p

## Искры планктона: голубые вспышки вокруг движущегося пловца (аддитивно, ночью).
static func sparkle(parent: Node, at: Vector3, r: float, amount: int = 20) -> CPUParticles3D:
	var p := _make(parent, at, amount, 1.2, Color(0.35, 0.95, 1.0, 1.0), Color(0.1, 0.5, 1.0, 0.0), 0.03, 0.07, true, 0.0)
	if p:
		p.explosiveness = 0.4
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = r
		p.direction = Vector3.UP
		p.spread = 180.0
		p.initial_velocity_min = 0.02
		p.initial_velocity_max = 0.15
		p.gravity = Vector3.ZERO
	return p

static func bubbles(parent: Node, at: Vector3, n: int = 10, size: float = 0.05) -> void:
	var p := _make(parent, at, n, 3.0, Color(0.85, 0.95, 1.0, 0.7), Color(0.85, 0.95, 1.0, 0.0), size * 0.5, size, false, 0.0)
	if p:
		p.explosiveness = 0.3
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.1
		p.direction = Vector3.UP
		p.spread = 20.0
		p.initial_velocity_min = 0.4
		p.initial_velocity_max = 0.9
		p.gravity = Vector3(0.0, 0.6, 0.0)

## Кусочки добычи (после атаки акулы) — тонут, к ним слетается мелочь.
static func scraps(parent: Node, at: Vector3) -> void:
	var p := _make(parent, at, 14, 5.0, Color(0.75, 0.68, 0.62, 0.9), Color(0.55, 0.48, 0.44, 0.0), 0.04, 0.09, false, 0.0)
	if p:
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.4
		p.direction = Vector3.DOWN
		p.spread = 60.0
		p.initial_velocity_min = 0.1
		p.initial_velocity_max = 0.4
		p.gravity = Vector3(0.0, -0.15, 0.0)
		p.damping_min = 0.5
		p.damping_max = 1.0
