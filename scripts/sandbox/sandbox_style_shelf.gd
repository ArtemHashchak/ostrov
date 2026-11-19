class_name SandboxStyleShelf
extends Node3D
## «Полка стиля» на полигоне: все модели пака пользователя рядом, при одном свете — видно, кто
## выбивается по яркости, насыщенности, блеску и фактуре. Эталоны рядом: серый 18 %, белый 80 %,
## чёрный 3 % (линейное альбедо). Переключатели:
##   F7 / рычаг — «до/после» (оригинальные текстуры из assets/user_pack/_style_orig + без LUT);
##   F8 / рычаг — свет: день / пасмурно / закат / ночь.
## Под водой у пирса — тот же ряд морских видов (точка «Полка стиля: под водой»).

const P := preload("res://scripts/sandbox/sandbox_props.gd")
const DIR := "res://assets/user_pack/"
const ORIG := "res://assets/user_pack/_style_orig/"
const LIGHTS := [["День", &"clear", 13.0], ["Пасмурно", &"cloudy", 13.0], ["Закат", &"clear", 18.6], ["Ночь", &"clear", 23.0]]

static var instance: SandboxStyleShelf

var showing_after := true
var light_i := 0
var after_nodes: Array[Node3D] = []
var before_nodes: Array[Node3D] = []
var zones: SandboxZones
var _report := {}
var _status: Label3D


static func build(zs: SandboxZones, root: Node3D, c: Vector2) -> SandboxStyleShelf:
	var s := SandboxStyleShelf.new()
	s.name = "StyleShelf"
	root.add_child(s)
	instance = s
	s.zones = zs
	s._report = _load_report()
	s._build_land(c)
	s._build_water()
	s._apply_toggle()
	return s


static func has_originals() -> bool:
	return DirAccess.dir_exists_absolute(ORIG)


# ------------------------------------------------------------------ суша
func _build_land(c: Vector2) -> void:
	var x0 := c.x - 11.0
	var za := c.y + 4.0      # ряд A — животные и морские виды
	var zb := c.y - 4.0      # ряд B — предметы, растения, эталоны
	var step := 2.2
	var row_a := _sea_entries()
	row_a.insert(0, {"kind": "glb", "path": "animals/animal_shark_great_white.glb", "len": 1.9, "anim": &"swim", "name": "Большая белая (×0.42)"})
	row_a.insert(1, {"kind": "crab", "len": 0.85, "name": "Краб (×1.5)"})
	for i in row_a.size():
		_exhibit(row_a[i], Vector3(x0 + i * step, 0.0, za), 1.05)
	var row_b := [
		{"kind": "glb", "path": "items/item_shell_junonia.glb", "len": 0.3, "name": "Ракушка (×3)"},
		{"kind": "glb", "path": "items/item_dried_fish.glb", "len": 0.75, "name": "Сушёная рыба"},
		{"kind": "algae", "len": 0.9, "name": "Водоросли (атлас)"},
		{"kind": "ref", "albedo": 0.18, "name": "Эталон: серый 18 %"},
		{"kind": "ref", "albedo": 0.80, "name": "Эталон: белый 80 %"},
		{"kind": "ref", "albedo": 0.03, "name": "Эталон: чёрный 3 %"},
	]
	for i in row_b.size():
		_exhibit(row_b[i], Vector3(x0 + 2.0 + i * 2.6, 0.0, zb), 0.85)
	# пальма — во весь рост позади ряда B
	_exhibit({"kind": "glb", "path": "trees/tree_palm_coconut_user.glb", "len": 0.0, "name": "Кокосовая пальма", "plinth": false},
		Vector3(c.x + 9.0, 0.0, zb - 3.5), 0.0)
	# рычаги и вывеска
	P.signpost(self, c.x - 13.5, c.y + 8.5, "Полка стиля", "все модели пака при одном свете")
	_lever(Vector3(c.x - 6.0, 0.0, c.y + 8.0), &"toggle")
	_lever(Vector3(c.x - 3.5, 0.0, c.y + 8.0), &"light")
	_status = P.label(self, Vector3(c.x - 4.75, P.ground(c.x - 4.75, c.y + 8.0) + 2.4, c.y + 8.0), "", 34, P.SIGN_COLOR, 40.0)
	zones._point(&"style", "Полка стиля (до/после — F7, свет — F8)",
		Vector3(c.x, P.ground(c.x, c.y + 11.0) + 1.7, c.y + 11.0), Vector3(c.x, P.ground(c.x, c.y) + 1.2, c.y))


# ------------------------------------------------------------------ под водой у пирса
func _build_water() -> void:
	var w := get_tree().get_first_node_in_group(&"world")
	if w == null or not zones.points.has(&"pier"):
		return
	var pier: Vector3 = zones.points[&"pier"].pos
	var dir := Vector2(pier.x, pier.z).normalized()
	var wl := float(w.call(&"water_level"))
	var spot := Vector2.ZERO
	var found := false
	for k in 80:
		var q := Vector2(pier.x, pier.z) + dir * (4.0 + k * 1.5)
		var h := float(w.call(&"height_at", q.x, q.y))
		if h < wl - 3.2 and h > wl - 7.0:
			spot = q
			found = true
			break
	if not found:
		return
	var side := Vector2(-dir.y, dir.x)
	var list := _sea_entries()
	list.append({"kind": "ref", "albedo": 0.18, "name": "Эталон 18 %"})
	for i in list.size():
		var q := spot + side * ((i - list.size() * 0.5) * 1.8)
		var e: Dictionary = list[i].duplicate()
		e["under"] = true
		_exhibit(e, Vector3(q.x, 0.0, q.y), 0.6)
	var gy := float(w.call(&"height_at", spot.x, spot.y))
	var eye := spot - dir * 4.0
	zones._point(&"style_underwater", "Полка стиля: под водой",
		Vector3(eye.x, gy + 1.6, eye.y), Vector3(spot.x, gy + 1.0, spot.y))


# ------------------------------------------------------------------ экспонаты
func _sea_entries() -> Array:
	var out: Array = []
	for d: Dictionary in UserSeaPack.species_list():
		var L := float(d.get("length", 0.4))
		var show := 0.7 if L < 0.5 else (0.9 if L < 1.5 else 1.8)
		out.append({"kind": "sea", "d": d, "len": show, "name": String(d.get("name", d.get("id")))})
	return out


func _exhibit(e: Dictionary, at: Vector3, plinth_h: float) -> void:
	var under := bool(e.get("under", false))
	var gy := P.ground(at.x, at.z)
	if under:
		var w := get_tree().get_first_node_in_group(&"world")
		gy = float(w.call(&"height_at", at.x, at.z)) if w else gy
	var top := gy
	if plinth_h > 0.0 and e.get("plinth", true):
		var post := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.32
		cm.bottom_radius = 0.38
		cm.height = plinth_h
		post.mesh = cm
		post.material_override = _plinth_mat()
		add_child(post)
		post.global_position = Vector3(at.x, gy + plinth_h * 0.5, at.z)
		top = gy + plinth_h
	var after := _make(e, false)
	var before := _make(e, true)
	var L := float(e.get("len", 0.5))
	for pair in [[after, after_nodes], [before, before_nodes]]:
		var n: Node3D = pair[0]
		if n == null:
			continue
		add_child(n)
		n.global_position = Vector3(at.x, top + (L * 0.35 if e.kind == "sea" else 0.02), at.z)
		if e.kind == "sea":
			n.rotation.y = PI * 0.5
		# без оригинала (эталоны) — виден всегда, в переключение не входит
		if before != null:
			(pair[1] as Array).append(n)
	var txt := String(e.get("name", ""))
	var r := _report_line(e)
	if r != "":
		txt += "\n" + r
	if not under:
		P.label(self, Vector3(at.x, top + maxf(L, 0.3) + 0.55, at.z), txt, 20, P.SIGN_COLOR, 18.0)


func _make(e: Dictionary, orig: bool) -> Node3D:
	var base := ORIG if orig else DIR
	match String(e.kind):
		"glb":
			var p := base + String(e.path)
			if not ResourceLoader.exists(p):
				return null
			var n := (load(p) as PackedScene).instantiate() as Node3D
			if float(e.len) > 0.0:
				_fit(n, float(e.len))
			if e.has("anim"):
				SandboxPack.play_loop(n, e.anim)
			return n
		"crab":
			if orig and not ResourceLoader.exists(base + "animals/crab/crab_albedo.png"):
				return null
			var n := (load(DIR + "animals/crab/crab_user.glb") as PackedScene).instantiate() as Node3D
			var m := _crab_mat(base + "animals/crab/crab_")
			for mi in n.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).material_override = m
			_fit(n, float(e.len))
			return n
		"sea":
			var d: Dictionary = (e.d as Dictionary).duplicate()
			if orig:
				var op := String(d.get("mesh", "")).replace(DIR, ORIG)
				if not ResourceLoader.exists(op):
					return null
				d["mesh"] = op
			var ex := UserSeaPack.exhibit(d)
			if ex:
				ex.scale = Vector3.ONE * (float(e.len) / maxf(0.05, float(d.get("length", 0.4))))
			return ex
		"algae":
			var patch := Node3D.new()
			var mesh := SandboxPack.seaweed_mesh()
			var mat := SandboxPack.seaweed_material().duplicate() as ShaderMaterial
			var ap := (ORIG if orig else DIR) + "seaweed/seaweed_algae_atlas.png"
			if orig and not ResourceLoader.exists(ap):
				return null
			mat.set_shader_parameter(&"atlas", load(ap))
			for k in 5:
				var mi := MeshInstance3D.new()
				mi.mesh = mesh
				mi.material_override = mat
				patch.add_child(mi)
				mi.position = Vector3(cos(k * 1.3) * 0.25, 0.0, sin(k * 1.3) * 0.25)
				mi.rotation.y = k * 0.7
				mi.scale = Vector3.ONE * 0.5
			return patch
		"ref":
			if orig:
				return null   # эталон один и тот же «до» и «после»
			var mi := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.22
			sm.height = 0.44
			mi.mesh = sm
			var m := StandardMaterial3D.new()
			var a := float(e.albedo)
			m.albedo_color = Color(a, a, a).linear_to_srgb()
			m.roughness = 0.5
			mi.material_override = m
			mi.position.y = 0.22
			var n := Node3D.new()
			n.add_child(mi)
			return n
	return null


static func _crab_mat(prefix: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(prefix + "albedo.png")
	m.normal_enabled = true
	m.normal_texture = load(prefix + "normal.png")
	m.normal_scale = 0.8
	var orm := load(prefix + "orm.png") as Texture2D
	m.ao_enabled = true
	m.ao_texture = orm
	m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.roughness_texture = orm
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.roughness = 1.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


static func _plinth_mat() -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.18, 0.18, 0.18).linear_to_srgb()   # нейтральный серый 18 %
	m.roughness = 0.85
	return m


## Масштабировать модель так, чтобы наибольший размер был len м.
static func _fit(n: Node3D, len: float) -> void:
	var aabb := AABB()
	var first := true
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh == null:
			continue
		var b := mi.mesh.get_aabb()
		var xf := Transform3D.IDENTITY
		var p: Node = mi
		while p and p != n:
			if p is Node3D:
				xf = (p as Node3D).transform * xf
			p = p.get_parent()
		b = xf * b
		aabb = b if first else aabb.merge(b)
		first = false
	var big := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	if big > 1e-4:
		n.scale = Vector3.ONE * (len / big)


# ------------------------------------------------------------------ отчёт
static func _load_report() -> Dictionary:
	var p := DIR + "style_report.json"
	if not FileAccess.file_exists(p):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
	var out := {}
	if data is Array:
		for r: Dictionary in data:
			out[String(r.get("model", "")).get_file().get_basename()] = r
	return out


func _report_line(e: Dictionary) -> String:
	var key := ""
	match String(e.kind):
		"glb": key = String(e.path).get_file().get_basename()
		"crab": key = "crab_user"
		"sea": key = String((e.d as Dictionary).get("mesh", "")).get_file().get_basename()
		"algae": key = "seaweed_algae_atlas"
	var r: Dictionary = _report.get(key, {})
	if r.is_empty():
		return ""
	for m: Dictionary in r.get("materials", []):
		if m.has("y_med_before"):
			return "%s · Y %.2f→%.2f · насыщ. %.2f→%.2f" % [String(m.get("class", "")), float(m.y_med_before), float(m.y_med_after),
				float(m.get("sat_before", 0.0)), float(m.get("sat_after", 0.0))]
	return String((r.get("materials", [{}]) as Array)[0].get("class", ""))


# ------------------------------------------------------------------ переключатели
func toggle() -> void:
	showing_after = not showing_after
	_apply_toggle()


func set_after(on: bool) -> void:
	showing_after = on
	_apply_toggle()


func _apply_toggle() -> void:
	for n in after_nodes:
		if is_instance_valid(n):
			n.visible = showing_after
	for n in before_nodes:
		if is_instance_valid(n):
			n.visible = not showing_after
	StyleGrade.set_enabled(showing_after)
	_update_status()


func next_light() -> void:
	set_light((light_i + 1) % LIGHTS.size())


func set_light(i: int) -> void:
	light_i = i
	var sb := _sandbox()
	if sb and sb.cheats:
		sb.cheats.set_weather(LIGHTS[i][1])
		sb.cheats.set_time(float(LIGHTS[i][2]))
	_update_status()


func _update_status() -> void:
	if _status:
		_status.text = "%s · свет: %s\nF7 — до/после · F8 — свет" % ["ПОСЛЕ (единый ряд)" if showing_after else "ДО (как у авторов)", LIGHTS[light_i][0]]


func _sandbox() -> Sandbox:
	var p: Node = self
	while p:
		if p is Sandbox:
			return p as Sandbox
		p = p.get_parent()
	return null


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if (ev as InputEventKey).keycode == KEY_F7:
			toggle()
			get_viewport().set_input_as_handled()
		elif (ev as InputEventKey).keycode == KEY_F8:
			next_light()
			get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	StyleGrade.set_enabled(true)
	if instance == self:
		instance = null


func _lever(at: Vector3, what: StringName) -> void:
	var b := ShelfLever.new()
	b.shelf = self
	b.what = what
	add_child(b)
	b.global_position = Vector3(at.x, P.ground(at.x, at.z), at.z)


class ShelfLever:
	extends StaticBody3D
	var shelf: SandboxStyleShelf
	var what: StringName

	func _ready() -> void:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.5, 1.2, 0.5)
		cs.shape = bs
		cs.position.y = 0.6
		add_child(cs)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.35, 1.1, 0.35)
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.85, 0.55, 0.15) if what == &"toggle" else Color(0.25, 0.55, 0.85)
		mi.material_override = m
		mi.position.y = 0.55
		add_child(mi)

	func get_interact_text(_by: Node) -> String:
		return "E — до/после (F7)" if what == &"toggle" else "E — свет: следующий (F8)"

	func interact(_by: Node) -> void:
		if what == &"toggle":
			shelf.toggle()
		else:
			shelf.next_light()
