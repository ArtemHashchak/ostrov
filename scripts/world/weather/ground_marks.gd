class_name GroundMarks
## v5.2: долговечные следы на земле, которые не умещаются в карту глубины SandTracks:
##  · кострище — чёрное пятно гари с серым пеплом и обугленными головешками после костра.
## Плоский квад по нормали земли, процедурная текстура (кешируется). Не больше MAX_PITS — старые
## тускнеют и уходят. В дождь пепел смывается медленно (кострище остаётся темнее земли).

const MAX_PITS := 24
static var _pits: Array[Node3D] = []
static var _tex: ImageTexture
static var _mat: StandardMaterial3D

static func fire_pit(host: Node, pos: Vector3, radius: float = 0.75) -> Node3D:
	if host == null or not host.is_inside_tree():
		return null
	_pits = _pits.filter(func(n: Node3D) -> bool: return is_instance_valid(n))
	# рядом уже есть кострище — просто обновить
	for n in _pits:
		if n.global_position.distance_to(pos) < 0.5:
			return n
	if _pits.size() >= MAX_PITS:
		var o: Node3D = _pits.pop_front()
		if is_instance_valid(o):
			o.queue_free()
	var mi := MeshInstance3D.new()
	mi.name = "FirePit"
	var q := QuadMesh.new()
	q.size = Vector2(radius * 2.0, radius * 2.0)
	q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	mi.material_override = _material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(mi)
	var y := pos.y
	var w := BuildEnv.world()
	if w and w.has_method(&"height_at"):
		y = float(w.call(&"height_at", pos.x, pos.z))
	mi.global_position = Vector3(pos.x, y + 0.015, pos.z)
	mi.rotation.y = randf() * TAU
	mi.add_to_group(&"fire_pit_mark")
	_pits.append(mi)
	return mi

static func count() -> int:
	_pits = _pits.filter(func(n: Node3D) -> bool: return is_instance_valid(n))
	return _pits.size()

static func _material() -> StandardMaterial3D:
	if _mat:
		return _mat
	_mat = StandardMaterial3D.new()
	_mat.albedo_texture = _texture()
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.roughness = 0.95
	_mat.render_priority = 1
	return _mat

static func _texture() -> ImageTexture:
	if _tex:
		return _tex
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7171
	var noise := FastNoiseLite.new()
	noise.seed = 31
	noise.frequency = 0.09
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5) / n * 2.0 - Vector2.ONE
			var r := p.length() + noise.get_noise_2d(x, y) * 0.18
			var char_a := 1.0 - smoothstep(0.55, 1.0, r)            # гарь
			var ash := 1.0 - smoothstep(0.0, 0.5, r)                  # пепел в центре
			var nn := noise.get_noise_2d(x * 3.0, y * 3.0) * 0.5 + 0.5
			var c := Color(0.06, 0.055, 0.05).lerp(Color(0.48, 0.46, 0.44), ash * (0.55 + 0.45 * nn))
			img.set_pixel(x, y, Color(c.r, c.g, c.b, clampf(char_a * (0.75 + 0.25 * nn), 0.0, 1.0)))
	# обугленные головешки — тёмные полоски крест-накрест
	for k in 5:
		var a := rng.randf() * TAU
		var c0 := Vector2(n * 0.5, n * 0.5) + Vector2(rng.randf_range(-10, 10), rng.randf_range(-10, 10))
		var d := Vector2(cos(a), sin(a))
		for t in range(-24, 25):
			for wv in range(-2, 3):
				var q := c0 + d * t + Vector2(-d.y, d.x) * wv
				if q.x >= 0 and q.y >= 0 and q.x < n and q.y < n:
					img.set_pixel(int(q.x), int(q.y), Color(0.03, 0.025, 0.02, 1.0))
	_tex = ImageTexture.create_from_image(img)
	return _tex
