## test-timeout: 900
extends TestCase
## test-class: render
## Лёгкие снимки морских моделей со скелетом (без полигона — тот не помещается в память контейнера
## тестов вместе со всеми моделями): каждая модель отдельным кадром в «аквариуме» (голубая вода,
## песок, солнце) в клипе плавания/покоя, затем действия (мурена — угроза, скат — в песке,
## манта — бочка, креветка — щелчок, кальмар — чернила) и стаи (сардины VAT, хирурги).
## Снимки: tests/shots/test_sea_skel_shots_*.png. SKEL_SHOTS_ONLY=id1,id2 — только эти.

class FakeSea extends RefCounted:
	func water_y() -> float:
		return 6.0
	func floor_at(_x: float, _z: float) -> float:
		return 0.0
	func depth_at(_x: float, _z: float) -> float:
		return 6.0

var root3: Node3D
var cam: Camera3D

func _init() -> void:
	scene_path = ""
	timeout_sec = 900.0

func run() -> void:
	root3 = Node3D.new()
	get_tree().root.add_child(root3)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.32, 0.42)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.75, 0.85)
	env.ambient_light_energy = 0.25
	env.fog_enabled = true
	env.fog_light_color = Color(0.12, 0.38, 0.48)
	env.fog_density = 0.035
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.85
	var we := WorldEnvironment.new()
	we.environment = env
	root3.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	root3.add_child(sun)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	fl.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.42, 0.38, 0.3)
	fm.roughness = 0.95
	fl.material_override = fm
	root3.add_child(fl)
	cam = Camera3D.new()
	cam.fov = 50.0
	root3.add_child(cam)
	cam.current = true
	var only := OS.get_environment("SKEL_SHOTS_ONLY")
	# --- каждая модель
	for id: String in SeaSkel.DEFS:
		if only != "" and not (id in only.split(",")):
			continue
		var d := SeaSkel.def(id)
		var s := SeaSkel.create(id, -1.0, 5)
		if s == null:
			continue
		root3.add_child(s)
		var ab := SeaSkel.bounds(id)
		var size := maxf(ab.size.z, ab.size.x)
		var ground := bool(d.get("ground", false))
		s.position = Vector3(0, 0.0 if ground else maxf(ab.size.y * 0.5 + 0.05, size * 0.25), 0)
		s.rotation.y = PI * 0.5        # голова влево кадра
		var role := "swim" if not ground else "idle"
		s.pose("")
		var ap := s.player()
		if ap:
			ap.play(s.clip(role))
			ap.seek(0.3, true)
		var dist := size * 0.95 + 0.08
		cam.position = s.position + Vector3(dist * 0.35, dist * (0.75 if ground else 0.3), dist)
		cam.look_at(s.position + Vector3(0, ab.size.y * 0.2, 0))
		await wait(0.6)
		await shot("01_%s" % id)
		s.queue_free()
		await wait_frames(2)
	if only != "":
		return
	# --- действия
	var sea := FakeSea.new()
	var acts := [["moray", "threat", true], ["stingray", "bury", true], ["manta", "roll", false], ["shrimp_pistol", "snap", false],
		["squid_red", "ink", false], ["giant_grouper", "gulp", false], ["barracuda", "bite", false], ["dolphin", "breathe", false],
		["turtle_green", "breathe", false], ["lobster", "threat", true]]
	for a: Array in acts:
		var id := String(a[0])
		var s := SeaSkel.create(id, -1.0, 9)
		var holder := Node3D.new()
		root3.add_child(holder)
		holder.add_child(s)
		var ab := SeaSkel.bounds(id)
		var size := maxf(ab.size.z, ab.size.x)
		holder.position = Vector3(0, 0.0 if bool(s.d.get("ground", false)) else maxf(ab.size.y * 0.5 + 0.05, size * 0.25), 0)
		holder.rotation.y = PI * 0.4
		s.on_event = func(ev: String, sk: SeaSkel) -> void:
			if ev == "snap":
				SeaSkelFx.cavitation(holder, sk.global_position + Vector3(-0.04, 0.02, 0.0), 0.23)
			elif ev == "ink":
				SeaSkelFx.ink(holder, sk.global_position + Vector3(0.25, 0, 0), 0.6)
		var ln := 0.0
		if bool(a[2]):
			s.pose(String(a[1]))
			ln = 1.6
		else:
			ln = s.act(String(a[1]))
		var dist := size * 1.0 + 0.1
		cam.position = holder.position + Vector3(dist * 0.5, dist * 0.35, dist)
		cam.look_at(holder.position)
		await wait(clampf(ln * 0.45, 0.25, 2.0))
		await shot("02_%s_%s" % [id, String(a[1])])
		holder.queue_free()
		await wait_frames(2)
	# --- стаи
	var sc := SeaScene.new()
	sc.sea = sea
	sc.duration = -1.0
	root3.add_child(sc)
	var s1 := sc.school("baitfish", 60, Vector3(0, 2.5, 0), 1.6)
	s1.mill(s1.center, 1.6)
	for i in 60:
		sc.tick(1.0 / 30.0)
		await wait_frames(1)
	cam.position = Vector3(0, 3.0, 6.0)
	cam.look_at(Vector3(0, 2.5, 0))
	await shot("03_school_sardine")
	var s2 := sc.school("surgeonfish", 14, Vector3(8, 1.5, 0), 1.2)
	for i in 40:
		sc.tick(1.0 / 30.0)
		await wait_frames(1)
	cam.position = Vector3(8, 2.0, 3.5)
	cam.look_at(s2.mean_pos())
	await shot("03_school_tangs")
	root3.queue_free()
