class_name SandboxPack
extends RefCounted
## Зона «Пак моделей» на полигоне: модели из пака пользователя после нормализации
## (tools/asset_normalize.py) рядом с картинками «оригинал → после» и цифрами из отчёта.
## Акула: экспонат на подставке + живая акула, плавающая кругом у пирса.
## Водоросли: «карточные» кусты из атласа пользователя с покачиванием и расталкиванием пловцом.

const P := preload("res://scripts/sandbox/sandbox_props.gd")
const DIR := "res://assets/user_pack/"
const SHARK := DIR + "animals/animal_shark_great_white.glb"
const PALM := DIR + "trees/tree_palm_coconut_user.glb"
const ATLAS := DIR + "seaweed/seaweed_algae_atlas.png"
const SEAWEED_SHADER := "res://scripts/sandbox/shaders/seaweed_card.gdshader"
const ATLAS_CELLS := 8

static var seaweed_mat: ShaderMaterial


## Площадка на суше: c — центр зоны (x, z). Возвращает точки {id: [pos, look, name]}.
static func build(zones: SandboxZones, root: Node3D, c: Vector2) -> void:
	var rep := _report()
	P.signpost(root, c.x - 10.0, c.y - 9.0, "ПАК МОДЕЛЕЙ", "Модели пользователя после выравнивания по бюджету\nслева — оригинал, справа — в игре")
	# --- пальма: три экземпляра (разные повороты) + сравнение
	var palm_ps := load(PALM) as PackedScene
	if palm_ps:
		for i in 3:
			var p := palm_ps.instantiate() as Node3D
			root.add_child(p)
			var x := c.x - 6.0 + i * 6.0
			var z := c.y + 6.0
			p.global_position = Vector3(x, P.ground(x, z) - 0.05, z)
			p.rotation.y = i * 2.1
		var r: Dictionary = rep.get("tree_palm_coconut_user", {})
		P.tag(root, c.x, c.y + 2.0, "Кокосовая пальма (SpeedTree)\n%s → %s треуг. · %d → %d материалов\nтекстур в архиве нет — кора проекта, листва цветом" % [
			_n(r.get("before_tris")), _n(r.get("after_tris")), int(r.get("before_surfaces", 0)), int(r.get("after_surfaces", 0))], 2.6, 45.0)
		_board(root, Vector3(c.x - 14.0, 0.0, c.y + 6.0), DIR + "preview/palm_compare.png", "Пальма: оригинал (без текстур) → в игре")
	# --- акула: экспонат
	var shark_ps := load(SHARK) as PackedScene
	if shark_ps:
		var sx := c.x + 12.0
		var sz := c.y - 2.0
		var g := P.ground(sx, sz)
		var stand := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.25
		cm.bottom_radius = 0.35
		cm.height = 1.2
		stand.mesh = cm
		stand.material_override = P._post_mat()
		root.add_child(stand)
		stand.global_position = Vector3(sx, g + 0.6, sz)
		var s := shark_ps.instantiate() as Node3D
		root.add_child(s)
		s.global_position = Vector3(sx, g + 1.9, sz)
		s.rotation.y = PI * 0.5
		play_loop(s, &"swim")
		var r2: Dictionary = rep.get("animal_shark_great_white", {})
		var anims := []
		for a: Dictionary in r2.get("animations", []):
			anims.append(a.get("name", ""))
		var half := ceili(anims.size() / 2.0)
		P.tag(root, sx, sz + 2.2, "Большая белая акула (анимированная)\n%s → %s треуг. · %d костей · текстуры ≈ %s МБ\nанимации: %s\n%s" % [
			_n(r2.get("before_tris")), _n(r2.get("after_tris")), int(r2.get("bones", 0)), str(r2.get("tex_mb_vram_est", "?")),
			", ".join(anims.slice(0, half)), ", ".join(anims.slice(half))], 3.4, 45.0)
		_board(root, Vector3(sx + 7.0, 0.0, sz - 4.0), DIR + "preview/shark_compare.png", "Акула: оригинал (без текстур) → в игре")
	zones._stand(&"pack", "Пак моделей", c.x, c.y - 12.0, c.x + 2.0, c.y + 2.0, 2.5)


## Живая акула у пирса и водоросли на мелководье острова.
static func build_sea(zones: SandboxZones, root: Node3D) -> void:
	var w := zones.world
	if w == null:
		return
	var I: Dictionary = w.arch.islands[0]
	var cc: Vector2 = I.center
	# мелководье 1.5–3.5 м рядом с пирсом (пирс идёт под углом −π/2+0.25)
	var spot := Vector2.INF
	for k in 24:
		var a := -PI * 0.5 + 0.7 + k * 0.05
		var dir := Vector2.from_angle(a)
		for st in range(20, 260, 2):
			var q := cc + dir * float(st)
			var gh := P.ground(q.x, q.y)
			if gh < -1.6 and gh > -3.4:
				spot = q
				break
		if spot.x < INF:
			break
	if spot.x < INF:
		_seaweed_patch(root, spot, 5.0, 70)
		var gy := P.ground(spot.x, spot.y)
		zones._point(&"pack_seaweed", "Пак: водоросли (под водой)", Vector3(spot.x - 4.0, gy + 1.0, spot.y - 4.0), Vector3(spot.x, gy + 0.6, spot.y))
		P.label(root, Vector3(spot.x + 3.0, 2.6, spot.y + 3.0), "Водоросли из пака · проплывите сквозь них", 34, P.SIGN_COLOR, 50.0)
	# живая акула: кругом над глубиной у конца пирса
	var deep := Vector2.INF
	var dir2 := Vector2.from_angle(-PI * 0.5 + 0.25)
	for st in range(30, 300, 3):
		var q := cc + dir2 * float(st)
		if P.ground(q.x, q.y) < -7.0:
			deep = q + dir2 * 10.0
			break
	var ps := load(SHARK) as PackedScene
	if ps and deep.x < INF:
		var sw := PackSwimmer.new()
		sw.name = "PackShark"
		sw.center = Vector3(deep.x, -2.6, deep.y)
		root.add_child(sw)
		var s := ps.instantiate() as Node3D
		sw.add_child(s)
		play_loop(s, &"swim")
		# стая из 12 акул на VAT: без скелетов, один MultiMesh — один вызов отрисовки
		var vat := make_vat_school(12, Vector3(deep.x, -5.5, deep.y) + Vector3(dir2.x, 0, dir2.y) * 22.0)
		if vat:
			root.add_child(vat)
			var vc: Vector3 = (vat as PackVatSchool).center
			var cp: Vector3 = vc - Vector3(dir2.x, 0.0, dir2.y) * 17.0
			cp.y = maxf(-3.5, P.ground(cp.x, cp.z) + 2.0)
			zones._point(&"pack_vat", "Пак: стая акул (VAT)", cp, vc)
		zones._point(&"pack_shark", "Пак: акула в море", Vector3(deep.x, -2.2, deep.y) - Vector3(dir2.x, 0, dir2.y) * 14.0, Vector3(deep.x, -2.6, deep.y))


## Стая акул из VAT (tools/bake_vat.gd): статичный меш + текстура смещений вершин.
static func make_vat_school(n: int, center: Vector3) -> Node3D:
	var base := DIR + "animals/animal_shark_great_white_vat"
	if not ResourceLoader.exists(base + "_mesh.res") or not ResourceLoader.exists(base + "_tex.res"):
		return null
	var info = JSON.parse_string(FileAccess.get_file_as_string(base + ".json")) if FileAccess.file_exists(base + ".json") else {}
	var mesh := load(base + "_mesh.res") as Mesh
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/sandbox/shaders/shark_vat.gdshader")
	mat.set_shader_parameter(&"vat_tex", load(base + "_tex.res"))
	mat.set_shader_parameter(&"vat_frames", float(info.get("frames", 32)) if info is Dictionary else 32.0)
	mat.set_shader_parameter(&"vat_length", float(info.get("length", 1.0)) if info is Dictionary else 1.0)
	var src := mesh.surface_get_material(0) as StandardMaterial3D
	if src:
		mat.set_shader_parameter(&"albedo_tex", src.albedo_texture)
		mat.set_shader_parameter(&"normal_tex", src.normal_texture)
		mat.set_shader_parameter(&"orm_tex", src.roughness_texture)
	var sch := PackVatSchool.new()
	sch.name = "PackVatSharks"
	sch.center = center
	sch.count = n
	sch.mesh = mesh
	sch.mat = mat
	return sch


static func play_loop(model: Node, anim: StringName) -> void:
	for ap in model.find_children("*", "AnimationPlayer", true, false):
		var p := ap as AnimationPlayer
		for an in p.get_animation_list():
			if String(an) == String(anim) or String(an).ends_with("/" + String(anim)):
				p.get_animation(an).loop_mode = Animation.LOOP_LINEAR
				p.play(an)
				return


## Куст-карточка: две перекрещенные полосы по 6 сегментов (гнутся по высоте).
static func seaweed_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := 6
	for plane in 2:
		var ang := plane * PI * 0.5
		var ax := Vector3(cos(ang), 0, sin(ang)) * 0.5
		var nrm := Vector3(-sin(ang), 0, cos(ang))
		for r in rows:
			var v0 := float(r) / rows
			var v1 := float(r + 1) / rows
			var a := -ax + Vector3.UP * v0
			var b := ax + Vector3.UP * v0
			var cq := ax + Vector3.UP * v1
			var d := -ax + Vector3.UP * v1
			for pr in [[a, Vector2(0, 1.0 - v0)], [b, Vector2(1, 1.0 - v0)], [cq, Vector2(1, 1.0 - v1)],
					[a, Vector2(0, 1.0 - v0)], [cq, Vector2(1, 1.0 - v1)], [d, Vector2(0, 1.0 - v1)]]:
				st.set_normal(nrm)
				st.set_uv(pr[1])
				st.add_vertex(pr[0])
	return st.commit()


static func seaweed_material() -> ShaderMaterial:
	if seaweed_mat:
		return seaweed_mat
	seaweed_mat = ShaderMaterial.new()
	seaweed_mat.shader = load(SEAWEED_SHADER)
	seaweed_mat.set_shader_parameter(&"atlas", load(ATLAS))
	seaweed_mat.set_shader_parameter(&"cells", float(ATLAS_CELLS))
	var sp = load("res://scripts/sea/sea_push.gd")   # общий SeaPush (модуль моря)
	if sp:
		sp.register(seaweed_mat)
	return seaweed_mat


static func _seaweed_patch(root: Node3D, c: Vector2, r: float, n: int) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = seaweed_mesh()
	mm.instance_count = n
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in n:
		var p := c + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * r
		var g := P.ground(p.x, p.y)
		var depth := -g
		var h := clampf(depth * rng.randf_range(0.45, 0.85), 0.6, 2.6)
		var wdt := h * rng.randf_range(0.3, 0.45)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(wdt, h, wdt))
		mm.set_instance_transform(i, Transform3D(b, Vector3(p.x, g - 0.05, p.y)))
		mm.set_instance_custom_data(i, Color(float(rng.randi_range(0, ATLAS_CELLS - 1)), rng.randf(), 0, 0))
	var mi := MultiMeshInstance3D.new()
	mi.name = "PackSeaweed"
	mi.multimesh = mm
	mi.material_override = seaweed_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 70.0
	mi.visibility_range_end_margin = 8.0
	root.add_child(mi)


static func _board(root: Node3D, pos: Vector3, img: String, title: String) -> void:
	var tex := load(img) as Texture2D
	if tex == null:
		return
	var g := P.ground(pos.x, pos.z)
	var sp := Sprite3D.new()
	sp.texture = tex
	sp.pixel_size = 6.0 / float(tex.get_width())
	sp.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sp.shaded = false
	sp.double_sided = true
	sp.visibility_range_end = 60.0
	root.add_child(sp)
	sp.global_position = Vector3(pos.x, g + 2.6, pos.z)
	P.label(root, Vector3(pos.x, g + 4.6, pos.z), title, 36, P.SIGN_COLOR, 60.0)


static func _report() -> Dictionary:
	var out := {}
	var path := DIR + "report.json"
	if not FileAccess.file_exists(path):
		return out
	var arr = JSON.parse_string(FileAccess.get_file_as_string(path))
	if arr is Array:
		for r in arr:
			out[String(r.get("name", ""))] = r
	return out


static func _n(v) -> String:
	if v == null:
		return "?"
	var i := int(v)
	return str(i) if i < 1000 else "%.1fk" % (i / 1000.0)


## Плывёт по кругу (поворачивается по курсу), чуть меняя глубину.
class PackSwimmer extends Node3D:
	var center := Vector3.ZERO
	var radius := 9.0
	var speed := 1.6
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta * speed / radius
		var p := center + Vector3(cos(_t) * radius, sin(_t * 0.7) * 0.6, sin(_t) * radius)
		var tangent := Vector3(-sin(_t), 0.0, cos(_t))
		global_position = p
		look_at(p + tangent, Vector3.UP)   # модель смотрит в −Z



## Стая VAT-акул: кружат на разных радиусах; на процессоре — только n матриц в кадр.
class PackVatSchool extends MultiMeshInstance3D:
	var center := Vector3.ZERO
	var count := 12
	var mesh: Mesh
	var mat: ShaderMaterial
	var _t := 0.0
	var _r: PackedFloat32Array
	var _ph: PackedFloat32Array

	func _ready() -> void:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = count
		multimesh = mm
		material_override = mat
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visibility_range_end = 120.0
		custom_aabb = AABB(Vector3(-30, -8, -30), Vector3(60, 16, 60))
		var rng := RandomNumberGenerator.new()
		rng.seed = 77
		_r.resize(count)
		_ph.resize(count)
		for i in count:
			_r[i] = rng.randf_range(7.0, 18.0)
			_ph[i] = rng.randf() * TAU
			mm.set_instance_custom_data(i, Color(rng.randf(), 0, 0, 0))
		global_position = center

	func _process(delta: float) -> void:
		_t += delta
		var mm := multimesh
		for i in count:
			var a := _ph[i] + _t * 1.5 / _r[i] * (1.0 if i % 2 == 0 else -1.0)
			var p := Vector3(cos(a) * _r[i], sin(a * 0.8 + _ph[i]) * 1.5 + (i % 3) * 1.4 - 1.4, sin(a) * _r[i])
			var tan := Vector3(-sin(a), 0.0, cos(a)) * (1.0 if i % 2 == 0 else -1.0)
			var b := Basis.looking_at(tan, Vector3.UP)
			mm.set_instance_transform(i, Transform3D(b, p))
