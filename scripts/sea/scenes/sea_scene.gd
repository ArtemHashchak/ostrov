class_name SeaScene
extends Node3D
## Сцена моря: маленький «спектакль» из нескольких существ вокруг точки (SeaSceneDirector
## ставит её у игрока). Наследник задаёт _begin() (кого и где поставить) и _step(dt)
## (режиссура по времени и по игроку). Существа — SeaCritter / SeaSchool / краб фауны /
## акула моря / птицы фауны / пятна растений. Всё созданное сцена убирает сама (cleanup).

var id := ""
var title := ""
var director: Node = null
var sea: Object = null           # water_y / floor_at / depth_at (Sea или заглушка полигона/теста)
var at := Vector3.ZERO           # точка сцены на дне/в толще
var duration := 40.0             # сколько длится (сек); <0 — пока не остановят
var t := 0.0
var phase := 0                   # шаг сюжета
var phase_t := 0.0
var done := false
var cpu_us := 0.0                # средняя цена тика (мкс), для отчёта

var critters: Array[SeaCritter] = []
var schools: Array[SeaSchool] = []
var crabs: Array = []            # Animal
var sharks: Array = []           # Shark
var flocks: Array = []           # Animal (птицы)
var plants: Array[MultiMeshInstance3D] = []
var rng := RandomNumberGenerator.new()
var _seed := 1
var _cpu_acc := 0.0
var _cpu_n := 0

func start(p_dir: Node, p_sea: Object, p_at: Vector3, seed_i: int) -> void:
	director = p_dir
	sea = p_sea
	at = p_at
	rng.seed = seed_i
	_seed = seed_i
	_begin()

## Наследник: поставить существ.
func _begin() -> void:
	pass

## Наследник: режиссура.
func _step(_dt: float) -> void:
	pass

func tick(dt: float) -> void:
	if done:
		return
	var t0 := Time.get_ticks_usec()
	t += dt
	phase_t += dt
	_step(dt)
	for c in critters:
		if is_instance_valid(c):
			c.tick(dt)
	for s in schools:
		if is_instance_valid(s):
			s.tick(dt)
	if duration > 0.0 and t > duration:
		done = true
	_cpu_acc += float(Time.get_ticks_usec() - t0)
	_cpu_n += 1
	cpu_us = _cpu_acc / float(_cpu_n)

func next_phase() -> void:
	phase += 1
	phase_t = 0.0

func cleanup() -> void:
	for c in crabs:
		if is_instance_valid(c):
			var fa := Fauna.instance()
			if fa:
				fa.animals.erase(c)
			(c as Node).queue_free()
	crabs.clear()
	for s in sharks:
		if is_instance_valid(s) and sea is Sea:
			(sea as Sea).sharks.erase(s)
			(s as Node).queue_free()
	sharks.clear()
	var fa2 := Fauna.instance()
	for f in flocks:
		if is_instance_valid(f):
			if fa2:
				fa2.animals.erase(f)
				fa2.flocks.erase((f as Animal).flock)
			(f as Node).queue_free()
	flocks.clear()
	queue_free()

# --- окружение ------------------------------------------------------------------

func water_y() -> float:
	return float(sea.call(&"water_y")) if sea else 0.0

func floor_y(x: float, z: float) -> float:
	return float(sea.call(&"floor_at", x, z)) if sea else -5.0

func depth(x: float, z: float) -> float:
	return water_y() - floor_y(x, z)

## Точка на дне рядом с центром сцены.
func on_floor(off: Vector3) -> Vector3:
	var p := at + Vector3(off.x, 0.0, off.z)
	p.y = floor_y(p.x, p.z) + off.y
	return p

## Точка в толще: h над дном, но не выше воды−0.4.
func in_water(off: Vector3, h: float) -> Vector3:
	var p := at + Vector3(off.x, 0.0, off.z)
	var fl := floor_y(p.x, p.z)
	p.y = clampf(fl + h, fl + 0.2, water_y() - 0.4)
	return p

func player() -> Node3D:
	return get_tree().get_first_node_in_group(&"player") as Node3D if is_inside_tree() else null

## Ближайший «раздражитель»: пловец-игрок или камера под водой.
func swimmer_pos() -> Vector3:
	var pl := player()
	if pl and pl.has_method(&"is_in_water") and bool(pl.call(&"is_in_water")):
		return pl.global_position + Vector3(0.0, 0.6, 0.0)
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam and cam.global_position.y < water_y():
		return cam.global_position
	return Vector3.INF

func swimmer_dist(p: Vector3) -> float:
	var s := swimmer_pos()
	return INF if s == Vector3.INF else s.distance_to(p)

func is_night() -> bool:
	return bool(director.call(&"is_night")) if director and director.has_method(&"is_night") else false

# --- создание -------------------------------------------------------------------

func critter(sp_id: String, pos: Vector3) -> SeaCritter:
	var sp := OceanRoster.species(sp_id)
	if sp.is_empty():
		return null
	_seed += 1
	var c := SeaCritter.make(sp, sea, pos, _seed * 7919)
	if c == null:
		return null
	add_child(c)
	c.global_position = pos
	critters.append(c)
	return c

func school(sp_id: String, count: int, c: Vector3, r: float) -> SeaSchool:
	var sp := OceanRoster.species(sp_id)
	var vis := OceanRoster.visual(sp)
	var entry: Dictionary = vis.get("entry", {})
	if entry.is_empty():
		entry = OceanRoster.pack_entry("redfish_user")
	_seed += 1
	var s := SeaSchool.new()
	add_child(s)
	s.radius = r
	s.speed = float(sp.get("speed", 1.0))
	var tint := String(vis.get("tint", ((entry.get("params", {}) as Dictionary).get("tint", "#ffffff"))))
	s.setup(sea, entry, tint, count, float(sp.get("length", 0.16)), c, _seed * 31)
	schools.append(s)
	return s

## Краб фауны (модель пользователя) под управлением сцены. scale — 0.3..1 (рак-отшельник, лангуст).
func crab(pos: Vector3, scale_k: float = 1.0) -> Node3D:
	var fa := Fauna.instance()
	var a: Animal = null
	if fa:
		a = fa.spawn(&"crab", pos, 3.0)
	else:
		a = Animal.create(&"crab", pos, null)
		add_child(a)
	a.scripted = true
	a.set_growth(scale_k)
	a.global_position = pos
	a.home = pos
	a.state = &"idle"
	crabs.append(a)
	return a

func crab_go(a: Node3D, p: Vector3) -> void:
	if not is_instance_valid(a):
		return
	a.set(&"move_to", p)
	a.set(&"home", p)
	(a as Animal)._set_state(&"wander")

func crab_chase(a: Node3D, target: Node3D) -> void:
	if is_instance_valid(a):
		a.set(&"target", target)
		(a as Animal)._set_state(&"chase")

func crab_warn(a: Node3D, target: Node3D) -> void:
	if is_instance_valid(a):
		a.set(&"target", target)
		(a as Animal)._set_state(&"warn")

func crab_pinch(a: Node3D) -> void:
	if is_instance_valid(a):
		(a as Animal).anim_event(&"attack")

func crab_flee(a: Node3D, from: Node3D) -> void:
	if is_instance_valid(a):
		a.set(&"target", from)
		(a as Animal)._set_state(&"flee")

func crab_burrow(a: Node3D) -> void:
	if is_instance_valid(a):
		(a as Animal)._set_state(&"burrow")

## Акула моря (настоящий ИИ, модель пака). Только если сцена в настоящем море.
func shark(sp: StringName, c: Vector3, ring: float) -> Node3D:
	if not (sea is Sea):
		return null
	_seed += 1
	var s := (sea as Sea).spawn_shark(sp, Vector2(c.x, c.z), ring, _seed * 101)
	sharks.append(s)
	return s

## Пятно растений: count экземпляров вида (OceanRoster.plants) в круге r вокруг c (по дну
## или на поверхности для плавучих). Один MultiMesh — один вызов отрисовки.
func plant_patch(pl_id: String, c: Vector3, r: float, count: int, surge: float = 1.0) -> MultiMeshInstance3D:
	var d := OceanRoster.plant(pl_id)
	if d.is_empty():
		return null
	var si: Dictionary = d.get("stand_in", {})
	var mesh := SeaProxyMeshes.get_mesh(String(si.get("proxy", "grass")), si.get("colors", []))
	var hmin := float((d.get("height", [0.3, 0.6]) as Array)[0])
	var hmax := float((d.get("height", [0.3, 0.6]) as Array)[1])
	var floating := (d.get("habitat", []) as Array).has("surface")
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = count
	var aabb := mesh.get_aabb()
	var unit := maxf(aabb.size.y, 0.05) if not floating else maxf(aabb.size.x, 0.05)
	var placed := 0
	for i in count:
		var a := rng.randf() * TAU
		var rr := sqrt(rng.randf()) * r
		var p := c + Vector3(cos(a) * rr, 0.0, sin(a) * rr)
		var fl := floor_y(p.x, p.z)
		var wy := water_y()
		if not floating and fl > wy - 0.2:
			continue
		p.y = wy - 0.05 if floating else fl - 0.02
		var h := rng.randf_range(hmin, hmax)
		if not floating:
			h = minf(h, (wy - fl) * 0.85)
		var s := h / unit
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s)
		mm.set_instance_transform(placed, Transform3D(b, p))
		mm.set_instance_custom_data(placed, Color(0, 0, 0, rng.randf()))
		placed += 1
	mm.visible_instance_count = placed
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.top_level = true
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ShaderMaterial.new()
	m.shader = load("res://scripts/sea/scenes/sea_proxy.gdshader")
	m.set_shader_parameter(&"mode", 6 if float(d.get("sway", 0.3)) > 0.0 else 5)
	m.set_shader_parameter(&"sway", float(d.get("sway", 0.3)))
	m.set_shader_parameter(&"surge", surge)
	m.set_shader_parameter(&"rough", 0.55)
	m.set_shader_parameter(&"transl", float(d.get("translucent", 0.0)))
	SeaPush.register(m)
	mi.material_override = m
	add_child(mi)
	mi.global_transform = Transform3D.IDENTITY
	plants.append(mi)
	return mi

## Птицы фауны над точкой (чайки): стая кружит; возвращает стаю.
func birds(sp: StringName, c: Vector3, n: int) -> Array:
	var fa := Fauna.instance()
	if fa == null:
		return []
	var arr: Array = fa.spawn_flock(sp, c, n, 6.0)
	for b in arr:
		flocks.append(b)
	return arr

## Перенаправить стаю птиц к точке (над водой).
func birds_to(arr: Array, p: Vector3) -> void:
	if arr.is_empty() or not is_instance_valid(arr[0]):
		return
	var fl: Dictionary = (arr[0] as Animal).flock
	fl["target"] = p
	fl["pos"] = (fl.get("pos", p) as Vector3).lerp(p, 0.02)

## Точки укрытий: кораллы рифа рядом (если риф есть), иначе — случайные места на дне.
func cover_spots(c: Vector3, r: float, k: int) -> Array:
	var out: Array = director.call(&"coral_spots", c, r, k) if director and director.has_method(&"coral_spots") else []
	while out.size() < k:
		var a := rng.randf() * TAU
		var rr := rng.randf_range(0.5, r)
		out.append(on_floor(Vector3(cos(a) * rr, 0.25, sin(a) * rr) + (c - at)))
	return out
