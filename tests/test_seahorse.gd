## test-timeout: 600
extends TestCase
## test-class: render
## Морской конёк (модель автора как есть, 3 расцветки; скелет и клипы процедурные):
## реестр SeaSkel и клипы, состав океана (вид «морской конёк» — модель, не дублёр), сцена
## «коньки держатся хвостом за траву» (завиток хвоста на стебле, поза grip, кормёжка/взгляд не
## отпуская), консоль: spawn морской конёк 10. Без полигона (лёгкий). Снимки (не в быстром режиме):
## tests/shots/test_seahorse_*.png — расцветки, держится за траву, кормится, ход/плавник.

class FakeSea extends RefCounted:
	func water_y() -> float:
		return 4.0
	func floor_at(_x: float, _z: float) -> float:
		return 0.0
	func depth_at(_x: float, _z: float) -> float:
		return 4.0

## Мир-заглушка для CreatureSpawner (рельеф 0, вода 4 м).
class FakeWorld extends Node3D:
	func _ready() -> void:
		add_to_group(&"world")
	func height_at(_x: float, _z: float) -> float:
		return 0.0
	func water_level() -> float:
		return 4.0

const IDS := ["seahorse_yellow", "seahorse_lilac", "seahorse_red"]
const CLIPS := ["idle_hover", "swim", "swim_fast", "grip", "grip_eat", "grip_look", "eat", "look", "startle", "death"]

var root3: Node3D
var cam: Camera3D

func _init() -> void:
	scene_path = ""
	timeout_sec = 600.0

func run() -> void:
	root3 = Node3D.new()
	get_tree().root.add_child(root3)
	_aquarium()
	# ---- реестр и клипы
	for id: String in IDS:
		check(SeaSkel.has(id), "SeaSkel: %s есть (GLB импортирован)" % id)
		var s := SeaSkel.create(id, 0.14, 3)
		if s == null:
			continue
		root3.add_child(s)
		var ap := s.player()
		var miss := []
		for c: String in CLIPS:
			if ap == null or not ap.has_animation(c):
				miss.append(c)
		check(miss.is_empty(), "%s: все %d клипов (нет: %s)" % [id, CLIPS.size(), miss])
		check(ap != null and ap.get_animation("grip").loop_mode == Animation.LOOP_LINEAR, "%s: grip — цикл" % id)
		var ab := SeaSkel.bounds(id)
		check(absf(ab.size.y - 0.158) < 0.01, "%s: рост модели %.3f м (как у автора ×0.1)" % [id, ab.size.y])
		var g: Variant = s.bone_point("tail_grip")
		check(g != null and (g as Vector3).y < -0.035, "%s: кость tail_grip внизу, в завитке хвоста (%s)" % [id, g])
		var tris := 0
		for mi: MeshInstance3D in s.find_children("*", "MeshInstance3D", true, false):
			for si in mi.mesh.get_surface_count():
				tris += (mi.mesh as ArrayMesh).surface_get_array_len(si) / 3 if mi.mesh.surface_get_format(si) & Mesh.ARRAY_FORMAT_INDEX == 0 \
					else (mi.mesh as ArrayMesh).surface_get_array_index_len(si) / 3
		check(tris == int(SeaSkel.def(id).tris), "%s: треугольников %d = %d (без децимации)" % [id, tris, int(SeaSkel.def(id).tris)])
		var fin_ok := false
		for mi: MeshInstance3D in s.find_children("*", "MeshInstance3D", true, false):
			for si in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(si) as BaseMaterial3D
				if m and m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and m.albedo_color.a < 0.5:
					fin_ok = true
		check(fin_ok, "%s: полупрозрачный материал плавников" % id)
		s.queue_free()
	await wait_frames(2)

	# ---- состав океана: вид — модель (3 расцветки), не дублёр
	var sp := OceanRoster.species("seahorse")
	var vis := OceanRoster.visual(sp)
	check(String(vis.get("kind", "")) == "skel" and (vis.get("variants", []) as Array).size() == 3,
		"состав океана: морской конёк — модель, 3 расцветки (%s)" % vis)

	# ---- сцена «держатся хвостом за траву»
	var sea := FakeSea.new()
	var sc := SeaScenesLib.make("seahorse_grass")
	root3.add_child(sc)
	sc.start(null, sea, Vector3(0, 0, 0), 4242)
	var sh := sc as SeaScenesLib.SeahorseGrass
	check(sh != null and sh.horses.size() == 3 and sh.stalks.size() == 3, "сцена: 3 конька на 3 стеблях")
	var cols := {}
	var acts := {}
	var max_gap := 0.0
	var grip_frames := 0
	var frames := 0
	for i in 300:
		sc.tick(1.0 / 30.0)
		await wait_frames(1)
		if i < 20:
			continue
		for k in sh.horses.size():
			var c: SeaCritter = sh.horses[k]
			cols[c.skel.id] = true
			var g: Variant = c.skel.bone_point("tail_grip")
			if g != null:
				var gw: Vector3 = c.skel.global_transform * (g as Vector3)
				max_gap = maxf(max_gap, gw.distance_to(sh.stalks[k].grip_point()))
			var cur := c.skel._cur
			acts[cur] = true
			frames += 1
			if cur.begins_with("grip"):
				grip_frames += 1
	check(max_gap < 0.012, "завиток хвоста на стебле (макс. зазор %.1f мм)" % (max_gap * 1000.0))
	check(grip_frames > frames * 0.9, "держатся (клипы grip*) %d/%d кадров" % [grip_frames, frames])
	check(acts.has("grip_eat") or acts.has("grip_look"), "за 9 с кормились/косились, не отпуская (%s)" % [acts.keys()])
	print("[test] расцветки в сцене: %s" % [cols.keys()])
	if not is_fast():
		for pl in sc.plants:         # луг-дублёр без шейдера моря здесь чёрный — для крупных планов прячем
			if is_instance_valid(pl):
				pl.visible = false
		var c0: SeaCritter = sh.horses[0]
		var gp := sh.stalks[0].grip_point()
		cam.position = gp + c0.global_basis.x * 0.34 + Vector3(0, 0.12, 0) + c0.global_basis.z * 0.1
		cam.look_at(gp + Vector3(0, 0.08, 0))
		await wait(0.3)
		await shot("02_grip_grass")
		# кормление: наклон головы
		var c2: SeaCritter = sh.horses[2]
		c2.skel.act("grip_eat")
		for i in 18:
			sc.tick(1.0 / 30.0)
			await wait_frames(1)
		var gp2 := sh.stalks[2].grip_point()
		for k in sh.horses.size():
			if k != 2:
				sh.horses[k].visible = false
				sh.stalks[k].visible = false
		cam.position = gp2 + c2.global_basis.x * 0.26 + Vector3(0, 0.1, 0) - c2.global_basis.z * 0.05
		cam.look_at(gp2 + Vector3(0, 0.07, 0) - c2.global_basis.z * 0.02)
		await shot("03_grip_eat_coral")
	sc.cleanup()
	sc.queue_free()
	await wait_frames(2)

	# ---- консоль: spawn морской конёк 10
	var fw := FakeWorld.new()
	root3.add_child(fw)
	var info := CreatureSpawner.find("морской конёк")
	check(String(info.get("id", "")) == "seahorse", "консоль: «морской конёк» → seahorse (%s)" % info.get("id", ""))
	var cs := CreatureSpawner.instance()
	var made := cs.spawn_now("морской конёк", Vector3(40, 0, 0), 10, 3.0) if cs else -1
	var t1 := Time.get_ticks_msec()
	while cs and cs.queued() > 0 and Time.get_ticks_msec() - t1 < 60000:
		await get_tree().process_frame
	var vars := {}
	var n_skel := 0
	for e in cs.spawned if cs else []:
		var c := e.get("node") as SeaCritter
		if c and is_instance_valid(c) and c.skel:
			n_skel += 1
			vars[c.skel.id] = true
	check(made == 10 and n_skel == 10, "spawn морской конёк 10 → %d, моделей со скелетом %d" % [made, n_skel])
	check(vars.size() >= 2, "расцветки вперемешку: %s" % [vars.keys()])
	if cs:
		cs.clear(Vector3(40, 0, 0), 30.0)
	await wait_frames(2)

	# ---- витрина полигона (класс SandboxSeahorse.Clinger): ×4, держится на стебле, действия по очереди
	var hs := SeaHoldfast.create(0.3, "grass", 0.0)
	hs.scale = Vector3.ONE * SandboxSeahorse.SHOW
	root3.add_child(hs)
	hs.position = Vector3(-30, 0, 0)
	hs.rotation.y = PI * 0.5
	var cl := SandboxSeahorse.Clinger.new()
	cl.hs = hs
	cl.s = SeaSkel.create("seahorse_red", 0.14 * SandboxSeahorse.SHOW, 5)
	root3.add_child(cl)
	cl.add_child(cl.s)
	cl.s.rotation.y = PI * 0.5
	var gap := 0.0
	var cl_acts := {}
	for i in 240:
		await wait_frames(1)
		var g: Variant = cl.s.bone_point("tail_grip")
		if i > 10 and g != null:
			gap = maxf(gap, (cl.s.global_transform * (g as Vector3)).distance_to(hs.grip_point()))
		cl_acts[cl.s._cur] = true
	check(gap < 0.03, "витрина ×4: завиток на стебле (зазор %.1f мм)" % (gap * 1000.0))
	check(cl_acts.has("grip"), "витрина: поза grip (%s)" % [cl_acts.keys()])
	cl.queue_free()
	hs.queue_free()
	if is_fast():
		root3.queue_free()
		return
	# ---- снимки: три расцветки рядом (зависают), ход и плавник
	var row: Array[SeaSkel] = []
	for k in IDS.size():
		var s := SeaSkel.create(String(IDS[k]), 0.14, 11 + k)
		root3.add_child(s)
		s.position = Vector3((k - 1) * 0.16, 1.5, 0)
		s.rotation.y = PI * 0.5
		s.player().play("idle_hover")
		s.player().seek(0.6 + k * 0.9, true)
		row.append(s)
	cam.position = Vector3(0.02, 1.55, 0.42)
	cam.look_at(Vector3(0, 1.5, 0))
	await wait(0.4)
	await shot("01_colours_hover")
	for s in row:
		s.player().play("swim")
		s.player().seek(0.37, true)
	row[1].position = Vector3(0, 1.5, 0)
	row[0].visible = false
	row[2].visible = false
	cam.position = Vector3(0.12, 1.6, 0.2)
	cam.look_at(Vector3(-0.005, 1.505, 0))
	await wait(0.25)
	await shot("04_swim_fin")
	root3.queue_free()

func _aquarium() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.32, 0.42)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.75, 0.85)
	env.ambient_light_energy = 0.3
	env.fog_enabled = true
	env.fog_light_color = Color(0.12, 0.38, 0.48)
	env.fog_density = 0.05
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	root3.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	root3.add_child(sun)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	fl.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.45, 0.41, 0.32)
	fm.roughness = 0.95
	fl.material_override = fm
	root3.add_child(fl)
	cam = Camera3D.new()
	cam.fov = 45.0
	cam.near = 0.01
	root3.add_child(cam)
	cam.current = true
