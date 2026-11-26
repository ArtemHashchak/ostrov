## test-timeout: 1500
extends TestCase
## Снимки для сравнения «до/после» визуала v5 (агент D). Не проверки — только кадры.
## Окружение: VIS_TAG=before|after (в имени файла), VIS_SET=light|wind|water|weather|all.
## Виды: пляж в полдень, джунгли в полдень, закат с моря, ночь (полная и новая луна), море у берега.

func _init() -> void:
	scene_path = "res://scenes/world/world_view.tscn"
	timeout_sec = 1500.0

var w: World
var cam: Camera3D
var tag := "after"
var sets := "all"

func _views() -> Dictionary:
	var I: Dictionary = w.islands()[0]
	var c: Vector2 = I.center
	var r: float = I.radius
	var beach := Vector2.ZERO
	var sea := Vector2.ZERO
	var jungle := c
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 3000:
		var a := rng.randf() * TAU
		var p := c + Vector2(cos(a), sin(a)) * rng.randf_range(0.3, 1.3) * r
		var b := w.biome_at(p.x, p.y)
		if beach == Vector2.ZERO and b == &"beach":
			var out := (p - c).normalized()
			var q := p + out * 25.0
			if w.biome_at(q.x, q.y) == &"water":
				beach = p
				sea = p + out * 70.0
		if jungle == c and (b == &"jungle" or b == &"forest"):
			jungle = p
	return {"beach": beach, "sea": sea, "jungle": jungle, "center": c}

func _look(from: Vector3, at: Vector3) -> void:
	cam.global_position = from
	cam.look_at(at, Vector3.UP)
	await wait(1.2)

func _snap(name: String) -> void:
	await shot("%s_%s" % [tag, name])

func run() -> void:
	tag = OS.get_environment("VIS_TAG") if OS.get_environment("VIS_TAG") != "" else "after"
	sets = OS.get_environment("VIS_SET") if OS.get_environment("VIS_SET") != "" else "all"
	await wait(1.0)
	w = get_tree().get_first_node_in_group(&"world") as World
	if w == null:
		check(false, "мир готов")
		return
	Settings.graphics_quality = 2
	Settings.graphics_changed.emit()
	cam = Camera3D.new()
	scene.add_child(cam)
	cam.current = true
	cam.far = 4000.0
	var v := _views()
	var bp: Vector2 = v.beach
	var sp: Vector2 = v.sea
	var jp: Vector2 = v.jungle
	var bh := w.height_at(bp.x, bp.y)
	var out := (sp - bp).normalized()
	w.set_weather(&"clear", true)
	w.set_time_paused(true)
	if sets in ["light", "all"]:
		w.set_time_of_day(12.5)
		await _look(Vector3(bp.x - out.x * 6.0, bh + 1.7, bp.y - out.y * 6.0), Vector3(sp.x, 0.5, sp.y))
		await _snap("beach_noon")
		await _look(Vector3(bp.x + out.x * 3.0, bh + 1.7, bp.y + out.y * 3.0), Vector3(v.center.x, bh + 4.0, v.center.y))
		await _snap("beach_to_island_noon")
		var jh := w.height_at(jp.x, jp.y)
		await _look(Vector3(jp.x, jh + 1.7, jp.y), Vector3(jp.x + 10.0, jh + 1.5, jp.y + 4.0))
		await _snap("jungle_noon")
		w.set_time_of_day(18.3)
		await _look(Vector3(sp.x, 3.0, sp.y), Vector3(bp.x, bh + 3.0, bp.y))
		await _snap("sunset_from_sea")
		w.set_time_of_day(23.0)
		await _look(Vector3(bp.x - out.x * 4.0, bh + 1.7, bp.y - out.y * 4.0), Vector3(sp.x, 6.0, sp.y))
		var sw = w.get("sky")
		if sw == null:
			for c in w.get_children():
				if c is SkyWeather:
					sw = c
		if sw:
			var e: Environment = sw.sky3d.environment
			print("[test] ночь: луна %.2f свет луны %.2f  ambient %s x%.2f sky_contrib %.2f  src %d" % [sw.moon_illumination(), sw.moon_light(), e.ambient_light_color, e.ambient_light_energy, e.ambient_light_sky_contribution, e.ambient_light_source])
		await _snap("night_beach")
	if sets in ["water", "all"]:
		w.set_time_of_day(10.0)
		await _look(Vector3(bp.x + out.x * 6.0, bh + 1.6, bp.y + out.y * 6.0), Vector3(bp.x + out.x * 40.0, 0.0, bp.y + out.y * 40.0))
		await _snap("surf_morning")
		w.set_weather(&"storm", true)
		await wait(2.0)
		await _look(Vector3(bp.x - out.x * 8.0, bh + 2.0, bp.y - out.y * 8.0), Vector3(sp.x, 0.0, sp.y))
		await _snap("storm_shore")
		w.set_weather(&"clear", true)
	if sets in ["weather", "all"]:
		w.set_time_of_day(15.0)
		w.set_weather(&"rain", true)
		await wait(2.0)
		await _look(Vector3(bp.x - out.x * 6.0, bh + 1.7, bp.y - out.y * 6.0), Vector3(sp.x, 1.0, sp.y))
		await _snap("rain_beach")
		w.set_weather(&"clear", true)
	check(true, "снимки сделаны")
