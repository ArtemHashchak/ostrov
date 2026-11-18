class_name BuildMats
extends RefCounted
## Материалы и меши модуля BUILD (кэшируются). Реализм: кора bark_brown_02,
## спил — rough_wood, верёвка Rope001, камень mossy_rock, ткань флага.

static var _mats: Dictionary = {}
static var _meshes: Dictionary = {}

static func mat(id: StringName) -> Material:
	if _mats.has(id):
		return _mats[id]
	var m: Material = null
	match id:
		&"log":
			m = _pbr("bark_brown_02", Vector3(2.0, 1.5, 1.0), Color(1.55, 1.32, 1.1))
		&"stick":
			m = _pbr("bark_brown_02", Vector3(1.0, 3.0, 1.0), Color(1.35, 1.2, 1.0))
		&"pole":
			m = _pbr("rough_wood", Vector3(1.0, 3.0, 1.0), Color(1, 1, 1))
		&"rope":
			m = _pbr("Rope001", Vector3(6.0, 1.0, 1.0), Color(1, 1, 1))
		&"stone":
			m = _pbr("mossy_rock", Vector3(1.0, 1.0, 1.0), Color(1, 1, 1))
		&"charred":
			var c := _pbr("bark_brown_02", Vector3(2.0, 1.5, 1.0), Color(0.18, 0.15, 0.13)) as StandardMaterial3D
			c.roughness = 1.0
			m = c
		&"ghost":
			m = _ghost(Color(0.80, 0.92, 1.0, 0.26))
		&"ghost_ok":
			m = _ghost(Color(0.55, 1.0, 0.6, 0.34))
		&"ghost_bad":
			m = _ghost(Color(1.0, 0.35, 0.3, 0.34))
		&"flame":
			var f := StandardMaterial3D.new()
			f.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			f.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			f.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			f.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			f.vertex_color_use_as_albedo = true
			f.albedo_texture = _soft_dot()
			f.albedo_color = Color(1.0, 0.55, 0.15, 0.85)
			m = f
		&"smoke":
			var s := StandardMaterial3D.new()
			s.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			s.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			s.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			s.vertex_color_use_as_albedo = true
			s.albedo_texture = _soft_dot()
			s.albedo_color = Color(0.25, 0.24, 0.23, 0.35)
			m = s
		_:
			m = StandardMaterial3D.new()
	_mats[id] = m
	return m

static func _pbr(set_name: String, uv: Vector3, tint: Color) -> StandardMaterial3D:
	var m: StandardMaterial3D = TerrainMaterial.pbr(set_name, 1.0)
	m.uv1_scale = uv
	m.albedo_color = tint
	return m

static func _ghost(c: Color) -> StandardMaterial3D:
	var g := StandardMaterial3D.new()
	g.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	g.albedo_color = c
	g.cull_mode = BaseMaterial3D.CULL_DISABLED
	g.no_depth_test = false
	return g

static var _dot: Texture2D = null
static func _soft_dot() -> Texture2D:
	if _dot:
		return _dot
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5).length() / 16.0
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	_dot = ImageTexture.create_from_image(img)
	return _dot

## Цилиндр (ось Y) с кэшированием по размеру.
static func cylinder(radius: float, length: float, sides: int = 10) -> CylinderMesh:
	var key := "c%.3f_%.3f_%d" % [radius, length, sides]
	if _meshes.has(key):
		return _meshes[key]
	var c := CylinderMesh.new()
	c.top_radius = radius * 0.93
	c.bottom_radius = radius
	c.height = length
	c.radial_segments = sides
	c.rings = 1
	_meshes[key] = c
	return c

static func torus(inner: float, outer: float) -> TorusMesh:
	var key := "t%.3f_%.3f" % [inner, outer]
	if _meshes.has(key):
		return _meshes[key]
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 12
	t.ring_segments = 6
	_meshes[key] = t
	return t

static func rock_mesh(size: float) -> SphereMesh:
	var key := "s%.3f" % size
	if _meshes.has(key):
		return _meshes[key]
	var s := SphereMesh.new()
	s.radius = size
	s.height = size * 1.3
	s.radial_segments = 7
	s.rings = 4
	_meshes[key] = s
	return s
