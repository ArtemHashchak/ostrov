class_name HeldModels
extends RefCounted
## Модели предметов в руке от первого лица. Реалистичные PBR-материалы из
## assets/textures (CC0) и модели из assets/models. Корень модели — точка хвата
## правой руки; ось +Y — вдоль рукояти вверх, -Z — вперёд.

const TEX := "res://assets/textures/"
static var _mat_cache: Dictionary = {}

static func build(id: StringName) -> Node3D:
	var root := Node3D.new()
	root.name = "Held_" + String(id)
	var um := UserHeld.build(id)   # v5: модель пользователя (топор, бутылка, мясо…), если есть
	if um:
		root.add_child(um)
		_no_shadows(root)
		return root
	match id:
		&"axe_crude": _axe_crude(root)
		&"axe_modern": _axe_modern(root)
		&"spear": _spear(root)
		&"stick": _stick(root)
		&"rock", &"stone": _rock(root)
		&"coconut": _coconut(root)
		&"water_bottle": _bottle(root)
		&"flag": _flag(root)
		&"rope", &"fiber": _rope_coil(root)
		&"cloth", &"bandage": _cloth_roll(root)
		&"leaf": _leaf(root)
		&"meat_raw", &"meat_cooked", &"fish_raw": _meat(root, id)
		&"": pass
		_:
			if not CombatModels.build_into(root, id): # COMBAT: модели оружия
				_generic(root, id)
	_no_shadows(root)
	return root

# --- материалы ---

static func pbr(set_name: String, uv: Vector3 = Vector3.ONE, tint: Color = Color.WHITE) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [set_name, uv, tint]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	var a := _t(set_name, "albedo")
	if a:
		m.albedo_texture = a
	m.albedo_color = tint
	var n := _t(set_name, "normal")
	if n:
		m.normal_enabled = true
		m.normal_texture = n
	var r := _t(set_name, "roughness")
	if r:
		m.roughness_texture = r
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	var ao := _t(set_name, "ao")
	if ao:
		m.ao_enabled = true
		m.ao_texture = ao
	m.uv1_scale = uv
	_mat_cache[key] = m
	return m

static func _t(set_name: String, kind: String) -> Texture2D:
	var p := "%s%s/%s_%s.png" % [TEX, set_name, set_name, kind]
	return load(p) as Texture2D if ResourceLoader.exists(p) else null

static func color_mat(c: Color, rough: float = 0.8, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

# --- примитивы ---

static func _cyl(parent: Node3D, r_top: float, r_bot: float, h: float, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, segs: int = 10) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = segs
	cm.rings = 2
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi

static func _box(parent: Node3D, size: Vector3, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi

static func _sphere(parent: Node3D, r: float, mat: Material, pos: Vector3, scale: Vector3 = Vector3.ONE, segs: int = 14) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = segs
	sm.rings = maxi(4, segs / 2)
	mi.mesh = sm
	mi.material_override = mat
	mi.position = pos
	mi.scale = scale
	parent.add_child(mi)
	return mi

## Неровный камень: сфера с шумовым смещением вершин (ArrayMesh).
static func rough_stone_mesh(r: float, seed_v: int) -> ArrayMesh:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 10
	sm.rings = 6
	var arr := sm.get_mesh_arrays()
	var verts := arr[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var noise := FastNoiseLite.new()
	noise.seed = seed_v
	noise.frequency = 6.0
	for i in verts.size():
		var v := verts[i]
		var k := 1.0 + noise.get_noise_3dv(v) * 0.28
		verts[i] = Vector3(v.x * k * 1.15, v.y * k * 0.8, v.z * k)
	arr[Mesh.ARRAY_VERTEX] = verts
	var st := SurfaceTool.new()
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	st.create_from(am, 0)
	st.generate_normals()
	st.generate_tangents()
	return st.commit()

# --- предметы ---

static func _handle(root: Node3D, length: float, r: float) -> void:
	_cyl(root, r * 0.85, r, length, pbr("rough_wood", Vector3(0.6, 2.0, 1.0)), Vector3(0, length * 0.5 - 0.08, 0))

static func _axe_crude(root: Node3D) -> void:
	# Сучковатая палка + каменное лезвие, примотанное верёвкой.
	_cyl(root, 0.017, 0.021, 0.56, pbr("bark_brown_02", Vector3(0.5, 2.0, 1.0)), Vector3(0, 0.2, 0))
	var head := MeshInstance3D.new()
	head.mesh = rough_stone_mesh(0.055, 7)
	head.material_override = pbr("dark_rock", Vector3(0.7, 0.7, 0.7))
	head.position = Vector3(0.0, 0.42, -0.05)
	head.scale = Vector3(0.55, 1.0, 1.35)
	root.add_child(head)
	var rope := pbr("Rope001", Vector3(2.0, 1.0, 1.0))
	for i in 3:
		_cyl(root, 0.026, 0.026, 0.012, rope, Vector3(0, 0.39 + i * 0.022, -0.005), Vector3(0, 0, deg_to_rad(8.0 * (i - 1))), 10)

static func _axe_modern(root: Node3D) -> void:
	_handle(root, 0.6, 0.019)
	var steel := color_mat(Color(0.56, 0.58, 0.6), 0.32, 0.9)
	var blade := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.13, 0.16, 0.022)
	pm.left_to_right = 0.0
	blade.mesh = pm
	blade.material_override = steel
	blade.position = Vector3(0.0, 0.43, -0.085)
	blade.rotation = Vector3(0.0, deg_to_rad(90.0), deg_to_rad(-90.0))
	root.add_child(blade)
	_box(root, Vector3(0.034, 0.07, 0.06), color_mat(Color(0.3, 0.31, 0.33), 0.45, 0.85), Vector3(0, 0.43, -0.005))
	# Кромка лезвия — светлее (заточка).
	_box(root, Vector3(0.024, 0.16, 0.008), color_mat(Color(0.82, 0.84, 0.86), 0.18, 1.0), Vector3(0, 0.43, -0.152))

static func _spear(root: Node3D) -> void:
	_cyl(root, 0.014, 0.018, 1.7, pbr("bark_brown_02", Vector3(0.4, 5.0, 1.0)), Vector3(0, 0.55, 0))
	var tip := MeshInstance3D.new()
	tip.mesh = rough_stone_mesh(0.03, 3)
	tip.material_override = pbr("dark_rock")
	tip.scale = Vector3(0.6, 2.6, 0.45)
	tip.position = Vector3(0, 1.45, 0)
	root.add_child(tip)
	var rope := pbr("Rope001", Vector3(2.0, 1.0, 1.0))
	for i in 3:
		_cyl(root, 0.021, 0.021, 0.012, rope, Vector3(0, 1.36 + i * 0.02, 0), Vector3.ZERO, 8)

static func _stick(root: Node3D) -> void:
	_cyl(root, 0.012, 0.017, 0.62, pbr("bark_brown_02", Vector3(0.4, 2.0, 1.0)), Vector3(0, 0.22, 0), Vector3(0, 0, deg_to_rad(3.0)))

static func _rock(root: Node3D) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = rough_stone_mesh(0.065, 11)
	mi.material_override = pbr("dark_rock", Vector3(0.8, 0.8, 0.8))
	mi.position = Vector3(0, 0.04, -0.02)
	root.add_child(mi)

static func _coconut(root: Node3D) -> void:
	_sphere(root, 0.075, pbr("palm_bark", Vector3(1.5, 1.5, 1.5), Color(0.75, 0.6, 0.45)), Vector3(0, 0.05, -0.02), Vector3(1, 1.15, 1))

static func _bottle(root: Node3D) -> void:
	const P := "res://assets/models/khronos/WaterBottle.glb"
	if ResourceLoader.exists(P):
		var n := (load(P) as PackedScene).instantiate() as Node3D
		n.scale = Vector3.ONE * 0.7
		n.position = Vector3(0, 0.05, -0.02)
		root.add_child(n)
	else:
		var glass := color_mat(Color(0.7, 0.85, 0.95, 0.45), 0.08)
		glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_cyl(root, 0.035, 0.035, 0.2, glass, Vector3(0, 0.08, 0))

static func _flag(root: Node3D) -> void:
	_cyl(root, 0.014, 0.016, 1.2, pbr("rough_wood", Vector3(0.4, 3.0, 1.0)), Vector3(0, 0.45, 0))
	var cloth := pbr("Fabric004", Vector3(1.0, 1.0, 1.0), Color(0.85, 0.29, 0.24))
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	_box(root, Vector3(0.008, 0.28, 0.42), cloth, Vector3(0, 0.88, -0.22))

static func _rope_coil(root: Node3D) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.045
	tm.outer_radius = 0.075
	tm.rings = 18
	tm.ring_segments = 8
	mi.mesh = tm
	mi.material_override = pbr("Rope001", Vector3(4.0, 1.0, 1.0))
	mi.rotation = Vector3(deg_to_rad(80.0), 0, 0)
	mi.position = Vector3(0, 0.04, -0.03)
	root.add_child(mi)

static func _cloth_roll(root: Node3D) -> void:
	_cyl(root, 0.035, 0.035, 0.12, pbr("Fabric004", Vector3(1, 1, 1), Color(0.92, 0.88, 0.8)), Vector3(0, 0.04, -0.02), Vector3(0, 0, PI / 2.0), 12)

static func _leaf(root: Node3D) -> void:
	var m := pbr("Leaf001")
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.18, 0.26)
	mi.mesh = q
	mi.material_override = m
	mi.position = Vector3(0, 0.12, -0.05)
	root.add_child(mi)

static func _meat(root: Node3D, id: StringName) -> void:
	var c := PlayerItems.color_of(id)
	var mi := MeshInstance3D.new()
	mi.mesh = rough_stone_mesh(0.07, 21)
	mi.material_override = color_mat(c, 0.55 if id != &"meat_cooked" else 0.8)
	mi.scale = Vector3(1.0, 0.55, 1.3)
	mi.position = Vector3(0, 0.03, -0.03)
	root.add_child(mi)

static func _generic(root: Node3D, id: StringName) -> void:
	# Модуль может дать свою модель: data["held"] — Callable() -> Node3D (SURVIVAL).
	var hb: Variant = PlayerItems.data(id).get("held")
	if hb is Callable and (hb as Callable).is_valid():
		var n: Variant = (hb as Callable).call()
		if n is Node3D:
			root.add_child(n as Node3D)
			return
	var mi := MeshInstance3D.new()
	mi.mesh = rough_stone_mesh(0.05, 5)
	mi.material_override = color_mat(PlayerItems.color_of(id), 0.7)
	mi.position = Vector3(0, 0.03, -0.02)
	root.add_child(mi)

static func _no_shadows(n: Node) -> void:
	for c in n.get_children():
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_no_shadows(c)
