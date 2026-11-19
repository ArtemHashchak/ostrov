class_name IslandDecor
extends Node3D
## Декор островов, который рельефом не передать (по IslandGen.features):
##   • ручьи — лента воды по руслу с течением (шейдер stream.gdshader);
##   • водопады — изогнутая завеса воды со струями, пена и брызги у подножия;
##   • гроты — каменная арка-свод над протокой в стене карста (тёмный зев);
##   • птичий базар — белые потёки помёта на карнизах скалы.
## Всё строится один раз; дальность ограничена visibility_range, теней нет у воды.

const STREAM_SHADER := "res://scripts/world/islands/shaders/stream.gdshader"
const FALL_SHADER := "res://scripts/world/islands/shaders/waterfall.gdshader"
const GUANO_SHADER := "res://scripts/world/islands/shaders/guano.gdshader"

var world: World
var gen: IslandGen
var stats := {"streams": 0, "waterfalls": 0, "grottos": 0, "guano": 0}

var _stream_mat: ShaderMaterial
var _fall_mat: ShaderMaterial
var _guano_mat: ShaderMaterial

func build(w: World, g: IslandGen) -> void:
	world = w
	gen = g
	_stream_mat = ShaderMaterial.new()
	_stream_mat.shader = load(STREAM_SHADER) as Shader
	_fall_mat = ShaderMaterial.new()
	_fall_mat.shader = load(FALL_SHADER) as Shader
	_guano_mat = ShaderMaterial.new()
	_guano_mat.shader = load(GUANO_SHADER) as Shader
	var nrm := "res://addons/ostrova_water/lesusx_gerstner/textures/Water 0339normal.jpg"
	if ResourceLoader.exists(nrm):
		_stream_mat.set_shader_parameter(&"normal_tex", load(nrm))
	for f: Dictionary in g.features:
		match StringName(f.type):
			&"stream":
				_stream(f)
			&"waterfall":
				_waterfall(f)
			&"grotto":
				_grotto(f)
			&"ledges":
				_ledges(f)

func _h(p: Vector2) -> float:
	return world.height_at(p.x, p.y)

# ------------------------------------------------------------ ручей

## Лента по руслу: вершины на дне русла + глубина воды; v — вдоль течения (м).
func _stream(f: Dictionary) -> void:
	var pts: PackedVector2Array = f.pts
	var w: float = f.width
	# пересэмплировать через ~2 м
	var path := PackedVector2Array()
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var n := maxi(1, int(a.distance_to(b) / 2.0))
		for s in n:
			path.append(a.lerp(b, float(s) / float(n)))
	path.append(pts[pts.size() - 1])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var along := 0.0
	var prev_y := 1e9
	var verts: Array = []
	for k in path.size():
		var p := path[k]
		var t := (path[mini(k + 1, path.size() - 1)] - path[maxi(k - 1, 0)]).normalized()
		var side := Vector2(-t.y, t.x)
		# поверхность воды: чуть выше дна русла, не выше берегов, только вниз по течению
		var bed := minf(_h(p), minf(_h(p + side * w * 0.5), _h(p - side * w * 0.5)))
		var y := minf(bed + 0.28, prev_y)
		y = maxf(y, world.water_level() + 0.02) if bed > world.water_level() else y
		prev_y = y
		if k > 0:
			along += path[k].distance_to(path[k - 1])
		verts.append([p + side * w * 0.5, p - side * w * 0.5, y, along])
	for k in verts.size() - 1:
		var A: Array = verts[k]
		var B: Array = verts[k + 1]
		var a0 := Vector3((A[0] as Vector2).x, A[2], (A[0] as Vector2).y)
		var a1 := Vector3((A[1] as Vector2).x, A[2], (A[1] as Vector2).y)
		var b0 := Vector3((B[0] as Vector2).x, B[2], (B[0] as Vector2).y)
		var b1 := Vector3((B[1] as Vector2).x, B[2], (B[1] as Vector2).y)
		var slope := clampf((float(A[2]) - float(B[2])) / maxf(float(B[3]) - float(A[3]), 0.1), 0.0, 1.0)
		for q: Array in [[a0, Vector2(0, A[3]), slope], [b0, Vector2(0, B[3]), slope], [b1, Vector2(1, B[3]), slope],
				[a0, Vector2(0, A[3]), slope], [b1, Vector2(1, B[3]), slope], [a1, Vector2(1, A[3]), slope]]:
			st.set_color(Color(q[2], 0, 0, 1))
			st.set_uv(q[1])
			st.set_normal(Vector3.UP)
			st.add_vertex(q[0])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _stream_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 700.0
	mi.name = "Stream_%d" % stats.streams
	add_child(mi)
	stats.streams += 1

# ------------------------------------------------------------ водопад

## Завеса: полоса от кромки вниз по дуге свободного падения, расширяется книзу;
## у подножия — пена (кольцо) и облако брызг (частицы).
func _waterfall(f: Dictionary) -> void:
	var top2: Vector2 = f.top
	var bot2: Vector2 = f.bottom
	var w: float = f.width
	var sea: bool = f.sea
	var y_top := _h(top2) + 0.3
	var y_bot := world.water_level() if sea else _h(bot2) + 0.4
	# поверхность пруда под водопадом, если есть
	var ll := world.lake_level_at(bot2.x, bot2.y)
	if ll > -1000.0:
		y_bot = ll
	var dir := (bot2 - top2).normalized()
	var side := Vector3(-dir.y, 0, dir.x)
	var fall_h := maxf(y_top - y_bot, 1.0)
	var t_fall := sqrt(2.0 * fall_h / 9.8)
	var v0 := 2.2     # горизонтальная скорость воды на кромке, м/с
	var rows := 24
	var cols := 6
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grid: Array = []
	for j in rows + 1:
		var tt := float(j) / float(rows)
		var tsec := tt * t_fall
		var fwd := v0 * tsec
		var y := y_top - 0.5 * 9.8 * tsec * tsec
		var spread := w * (1.0 + 0.35 * tt)
		var row: Array = []
		for i in cols + 1:
			var s := float(i) / float(cols) - 0.5
			var base := Vector3(top2.x, y, top2.y) + Vector3(dir.x, 0, dir.y) * fwd + side * s * spread
			row.append([base, Vector2(float(i) / float(cols), tt * fall_h)])
		grid.append(row)
	for j in rows:
		for i in cols:
			var q00: Array = grid[j][i]
			var q10: Array = grid[j][i + 1]
			var q01: Array = grid[j + 1][i]
			var q11: Array = grid[j + 1][i + 1]
			for q: Array in [q00, q01, q11, q00, q11, q10]:
				st.set_uv(q[1])
				st.set_normal(Vector3(dir.x, 0.0, dir.y))
				st.add_vertex(q[0])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _fall_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 900.0
	mi.name = "Waterfall_%d" % stats.waterfalls
	add_child(mi)
	_fall_material_params(fall_h)
	# пена у подножия: плоское кольцо с шумом (тот же шейдер ручья, режим пены)
	var foot := Vector3(top2.x, y_bot + 0.05, top2.y) + Vector3(dir.x, 0, dir.y) * v0 * t_fall
	var foam := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w * 2.4, w * 2.0)
	foam.mesh = pm
	var fm := ShaderMaterial.new()
	fm.shader = _stream_mat.shader
	fm.set_shader_parameter(&"foam_only", true)
	foam.material_override = fm
	foam.position = foot
	foam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	foam.visibility_range_end = 600.0
	add_child(foam)
	_spray(foot, w)
	stats.waterfalls += 1

func _fall_material_params(fall_h: float) -> void:
	_fall_mat.set_shader_parameter(&"fall_h", fall_h)

## Облако водяной пыли у подножия (частицы-квады, без теней).
func _spray(at: Vector3, w: float) -> void:
	var p := GPUParticles3D.new()
	p.amount = 48
	p.lifetime = 2.6
	p.preprocess = 2.6
	p.visibility_aabb = AABB(Vector3(-w * 2.0, -1.0, -w * 2.0), Vector3(w * 4.0, w * 2.5, w * 4.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(w * 0.5, 0.2, w * 0.3)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 70.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 2.2
	pm.gravity = Vector3(0, -0.4, 0)
	pm.damping_min = 0.4
	pm.damping_max = 0.9
	pm.scale_min = 1.6
	pm.scale_max = 3.4
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.0))
	curve.add_point(Vector2(0.25, 0.7))
	curve.add_point(Vector2(1, 0.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.alpha_curve = ct
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.92, 0.95, 0.97, 0.22)
	m.albedo_texture = _soft_dot()
	m.disable_receive_shadows = true
	q.material = m
	p.draw_pass_1 = q
	p.position = at
	p.visibility_range_end = 400.0
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)

static var _dot: ImageTexture
static func _soft_dot() -> ImageTexture:
	if _dot:
		return _dot
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for j in n:
		for i in n:
			var d := Vector2(i - n * 0.5 + 0.5, j - n * 0.5 + 0.5).length() / (n * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(i, j, Color(1, 1, 1, a * a))
	_dot = ImageTexture.create_from_image(img)
	return _dot

# ------------------------------------------------------------ грот

## Грот: рельеф прорезает в стене карста щель-протоку до воды; здесь щель
## закрывается каменной «пробкой» со сводом-аркой внизу — снаружи видна стена
## с тёмным зевом, внутри — низкий свод над водой, к концу сходится.
## Сечение: арка (полуэллипс) + прямоугольник до верха стены по бокам щели.
func _grotto(f: Dictionary) -> void:
	var mouth: Vector2 = f.mouth
	var inner: Vector2 = f.inner
	var w: float = f.width
	var hgt: float = f.height
	var dir := (inner - mouth).normalized()
	var side2 := Vector2(-dir.y, dir.x)
	var side := Vector3(side2.x, 0, side2.y)
	var length := mouth.distance_to(inner)
	var noise := FastNoiseLite.new()
	noise.seed = int(mouth.x * 13.0 + mouth.y)
	noise.frequency = 0.3
	var segs := int(length / 1.5) + 1
	var ring := 12
	var half := w * 1.75          # пробка шире зоны врезки рельефа (1.6·w)
	var base_y := -2.2
	var secs: Array = []          # [PackedVector2Array сечения (x — вбок, y — высота)]
	var ctrs: Array = []
	for j in segs + 1:
		var t := float(j) / float(segs)
		var c2 := mouth.lerp(inner, t)
		var rad_w := w * (0.6 + 0.12 * sin(t * 3.0 + 0.5)) * (1.0 - 0.6 * smoothstep(0.75, 1.0, t))
		var rad_h := hgt * (1.0 - 0.5 * t) * (1.0 - 0.5 * smoothstep(0.8, 1.0, t))
		var top := maxf(_h(c2 + side2 * half * 1.1), _h(c2 - side2 * half * 1.1)) + 0.4
		top = maxf(top, rad_h + base_y + 2.0)
		var poly := PackedVector2Array()
		# по часовой: правая база арки → свод → левая база арки → левый низ → левый верх → правый верх → правый низ
		for i in ring + 1:
			var a := PI * float(i) / float(ring)
			var rough := 1.0 + 0.18 * noise.get_noise_3d(c2.x, a * 5.0, c2.y)
			poly.append(Vector2(cos(a) * rad_w * rough, base_y + sin(a) * rad_h * rough))
		var lt := top + noise.get_noise_2d(c2.x - 50.0, c2.y) * 0.8
		var rt := top + noise.get_noise_2d(c2.x + 50.0, c2.y) * 0.8
		poly.append(Vector2(-half, base_y))
		poly.append(Vector2(-half, lt))
		poly.append(Vector2(half, rt))
		poly.append(Vector2(half, base_y))
		secs.append(poly)
		ctrs.append(c2)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rock := Color(0.0, 0.0, 1.0, 0.0)
	var to3 := func(c2: Vector2, q: Vector2) -> Vector3:
		return Vector3(c2.x, q.y, c2.y) + side * q.x
	var np := (secs[0] as PackedVector2Array).size()
	for j in segs:
		var A: PackedVector2Array = secs[j]
		var B: PackedVector2Array = secs[j + 1]
		for i in np:
			var i2 := (i + 1) % np
			var a0: Vector3 = to3.call(ctrs[j], A[i])
			var a1: Vector3 = to3.call(ctrs[j], A[i2])
			var b0: Vector3 = to3.call(ctrs[j + 1], B[i])
			var b1: Vector3 = to3.call(ctrs[j + 1], B[i2])
			for v: Vector3 in [a0, b0, b1, a0, b1, a1]:
				st.set_color(rock)
				st.add_vertex(v)
	# торцы: у зева (с отверстием-аркой) и в глубине (сплошной)
	for e in [0, segs]:
		var P: PackedVector2Array = secs[e]
		var tri := Geometry2D.triangulate_polygon(P) if e == 0 else PackedInt32Array()
		if e == segs:
			# в глубине — закрыть целиком (контур без отверстия)
			var full := PackedVector2Array([Vector2(-half, base_y), Vector2(-half, P[np - 3].y), Vector2(half, P[np - 2].y), Vector2(half, base_y)])
			tri = Geometry2D.triangulate_polygon(full)
			P = full
		for k in range(0, tri.size(), 3):
			var vs: Array = [to3.call(ctrs[e], P[tri[k]]), to3.call(ctrs[e], P[tri[k + 1]]), to3.call(ctrs[e], P[tri[k + 2]])]
			if e == segs:
				vs.reverse()
			for v: Vector3 in vs:
				st.set_color(rock)
				st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = world.terrain_material
	mi.visibility_range_end = 1500.0
	mi.name = "Grotto_%d" % stats.grottos
	add_child(mi)
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cm := ConcavePolygonShape3D.new()
	cm.backface_collision = true
	cm.set_faces(mi.mesh.get_faces())
	cs.shape = cm
	sb.add_child(cs)
	mi.add_child(sb)
	stats.grottos += 1

# ------------------------------------------------------------ птичий базар

## Белые потёки помёта на кромках карнизов: плоские квады по полке, с
## «стекающим» вниз продолжением на стене. Шейдер — рваное пятно.
func _ledges(f: Dictionary) -> void:
	var c: Vector2 = f.center
	var R: float = f.radius
	var rng := RandomNumberGenerator.new()
	rng.seed = int(c.x)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.orientation = PlaneMesh.FACE_Y
	mm.mesh = q
	var xf: Array[Transform3D] = []
	for k in 900:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * R * 0.98
		var p := c + Vector2.from_angle(a) * r
		var h := _h(p)
		if h < 2.5:
			continue
		var n := world.normal_at(p.x, p.y)
		# на полках (ровно) и у их кромок (где сразу за ними обрыв)
		var ahead := p + Vector2(n.x, n.z).normalized() * 1.6
		var drop := h - _h(ahead)
		if n.y < 0.8 and drop < 1.5:
			continue
		var s := rng.randf_range(0.6, 2.2)
		var b := Basis(Vector3.UP, rng.randf() * TAU)
		b = Basis(Quaternion(Vector3.UP, n)) * b
		xf.append(Transform3D(b.scaled(Vector3(s, 1.0, s * rng.randf_range(0.6, 1.4))), Vector3(p.x, h + 0.04, p.y)))
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _guano_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 500.0
	mmi.name = "Guano"
	add_child(mmi)
	stats.guano += xf.size()
