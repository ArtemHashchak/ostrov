## test-timeout: 1500
extends TestCase
## test-class: render
## Снимки v5.2 (агент K): коньки в морской траве, выдох дельфина, пальмовый вор с кокосом,
## чайка пикирует за едой, краб замер перед игроком, игуана греется.

var sea: Sea
var life: ReefLife
var cam: Camera3D
var w: World

func _init() -> void:
	scene_path = "res://scenes/world/world_view.tscn"
	timeout_sec = 1450.0

func _look(from: Vector3, at: Vector3) -> void:
	cam.global_position = from
	cam.look_at(at, Vector3.UP)

func run() -> void:
	await wait(1.0)
	w = get_tree().get_first_node_in_group(&"world") as World
	if w == null:
		return
	w.set_time_of_day(10.5)
	w.set_weather(&"clear", true)
	sea = Sea.new()
	sea.auto_populate = false
	scene.add_child(sea)
	sea._find_world()
	sea.populate()
	life = sea.reef_life as ReefLife
	cam = Camera3D.new()
	scene.add_child(cam)
	cam.current = true
	cam.fov = 60.0
	# ---------- коньки ----------
	var bed_found: Node3D = null
	for z: Dictionary in sea.reef_zones():
		var c: Vector2 = z.center
		life.stream_now(Vector3(c.x, sea.floor_at(c.x, c.y) + 1.4, c.y))
		var beds := life.find_children("Seahorses", "", true, false)
		if not beds.is_empty() and not (beds[0].get(&"critters") as Array).is_empty():
			bed_found = beds[0] as Node3D
			break
	if bed_found:
		var cr: Array = bed_found.get(&"critters")
		var hs := (cr[0] as Node3D).global_position
		_look(hs + Vector3(0.45, 0.12, 0.35), hs)
		cam.near = 0.02
		await wait(2.5)
		await shot("seahorse")
		var mid := hs
		_look(hs + Vector3(1.4, 0.5, 1.2), mid)
		await wait(1.0)
		await shot("seahorse_meadow")
		cam.near = 0.05
	# ---------- дельфин выдыхает ----------
	var dsp := OceanRoster.species("dolphin")
	if not dsp.is_empty():
		var wy := sea.water_y()
		var spot := Vector3(cam.global_position.x + 25, wy - 0.35, cam.global_position.z)
		var dol := SeaCritter.make(dsp, sea, spot, 5)
		if dol:
			scene.add_child(dol)
			dol.global_position = spot
			dol.hold(spot, Vector3(1, 0, 0))
			_look(spot + Vector3(-7, 1.6, 5), spot + Vector3(0, 0.8, 0))
			await wait(1.0)
			dol._blow()
			await wait(0.35)
			await shot("dolphin_blow")
	# ---------- суша: фауна ----------
	var fauna := (load("res://scenes/fauna/fauna.tscn") as PackedScene).instantiate() as Fauna
	fauna.set(&"auto_populate", false)
	scene.add_child(fauna)
	await wait(0.5)
	# пляж острова
	var beach := Vector3.INF
	for I in w.islands():
		var c: Vector2 = I.center
		for i in 200:
			var a := TAU * i / 200.0
			var r := float(I.radius) * 0.95
			var x := c.x + cos(a) * r
			var zz := c.y + sin(a) * r
			if w.biome_at(x, zz) == &"beach" and w.height_at(x, zz) > w.water_level() + 0.6:
				beach = Vector3(x, w.height_at(x, zz), zz)
				break
		if beach != Vector3.INF:
			break
	if beach == Vector3.INF:
		return
	Routines.debug_hour = 23.0
	w.set_time_of_day(21.5)
	var cc := fauna.spawn(&"coconut_crab", beach, 4.0)
	var nut := FloraPickup.make_coconut()
	scene.add_child(nut)
	var np := beach + Vector3(1.2, 0, 0.4)
	nut.global_position = Vector3(np.x, w.height_at(np.x, np.z) + 0.12, np.z)
	await wait(0.3)
	cc.home = beach + Vector3(-6, 0, 0)
	cc.state_t = 3.0
	for i in 140:
		cc._think_t = 0.0 if i == 0 else 1.0
		cc._routine_t = 1.0
		cc.tick(0.08)
		if cc.state == &"drag" and i > 60:
			break
	var lamp := OmniLight3D.new()
	lamp.omni_range = 6.0
	lamp.light_energy = 2.0
	scene.add_child(lamp)
	lamp.global_position = cc.global_position + Vector3(0.8, 1.6, 1.0)
	_look(cc.global_position + Vector3(1.4, 0.9, 1.6), cc.global_position + Vector3(0, 0.1, 0))
	await wait(0.6)
	await shot("coconut_crab_drag")
	lamp.queue_free()
	cc.queue_free()
	Routines.debug_hour = -1.0
	w.set_time_of_day(10.5)
	# чайка пикирует за едой
	var gulls := fauna.spawn_flock(&"gull", beach + Vector3(0, 0, 8), 3, 10.0)
	var food := ItemPickup.spawn(scene, beach + Vector3(2, 0.3, 2), [{"id": &"meat_raw", "n": 2}])
	await wait(0.4)
	var g := gulls[0]
	g.global_position = food.global_position + Vector3(-4, 3.0, -2)
	g.set_meta(&"dive", {"target": food, "phase": &"in", "t": 0.0})
	for i in 30:
		g.tick(0.05)
	_look(food.global_position + Vector3(3.5, 1.6, 3.0), (g.global_position + food.global_position) * 0.5)
	await wait(0.2)
	await shot("gull_dive")
	# игуана греется на солнце
	Routines.debug_hour = 8.0
	var ig := fauna.spawn(&"iguana", beach + Vector3(-4, 0, -3), 3.0)
	await wait(0.3)
	for i in 5:
		ig._routine_t = 0.0
		ig._think_t = 0.0
		ig.tick(0.3)
	_look(ig.global_position + Vector3(1.6, 0.7, 1.2), ig.global_position + Vector3(0, 0.15, 0))
	await wait(0.4)
	await shot("iguana_bask")
	Routines.debug_hour = -1.0
	print("[test] игуана: %s; пальмовый вор: снят" % ig.state)
