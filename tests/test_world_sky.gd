extends TestCase
## WORLD G1: небо, время суток, погода, подводный вид (скриншоты).

func _init() -> void:
	scene_path = "res://scenes/world/match.tscn"
	timeout_sec = 1400.0

var cam: Camera3D

func run() -> void:
	await wait(1.0)
	var w := get_tree().get_first_node_in_group(&"world") as World
	check(w != null and w.is_ready, "мир готов")
	if w == null:
		return
	cam = Camera3D.new()
	cam.far = 4000.0
	w.add_child(cam)
	cam.make_current()
	var pl := get_tree().get_first_node_in_group(&"player") as Node
	if pl:
		pl.process_mode = Node.PROCESS_MODE_DISABLED
	for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	var b := preload("res://tests/test_world_g1.gd").beach_spot(w, 80.0)
	w.set_time_paused(true)
	w.set_time_of_day(17.0)
	await wait(1.0)
	check(not w.is_night(), "17:15 ещё не ночь")
	await _view(Vector3(115.0, 2.5, 30.0), Vector3(300.0, 4.0, -20.0), "06_sunset")
	w.set_time_of_day(23.0)
	await wait(1.0)
	check(w.is_night(), "23:00 — ночь")
	await _view(b, b + Vector3(60.0, -1.0, 60.0), "07_night")
	w.set_time_of_day(10.0)
	w.set_weather(&"fog", true)
	await wait(1.0)
	await _view(b, Vector3(b.x * 0.2, 6.0, b.z * 0.2), "08_fog")
	w.set_weather(&"storm", true)
	await wait(1.5)
	await _view(Vector3(115.0, 3.0, -10.0), Vector3(225.0, 1.0, -70.0), "09_storm")
	check(w.sky.rain_factor() > 0.5 and w.sky.wave_scale() > 2.0, "шторм: дождь и волны")
	w.set_weather(&"clear", true)
	await wait(0.5)
	var dir := Vector2(b.x, b.z).normalized()
	var r := Vector2(b.x, b.z).length()
	while r < 260.0 and w.height_at(dir.x * r, dir.y * r) > -4.0:
		r += 1.0
	var u := Vector3(dir.x * r, w.water_level() - 1.6, dir.y * r)
	await _view(u, u + Vector3(-dir.x * 20.0, -2.5, -dir.y * 20.0), "10_underwater")
	check(w.sky.is_underwater_view(), "подводный вид включается")
	w.set_time_of_day(12.0)
	await wait(0.5)
	await _view(Vector3(150.0, 30.0, 120.0), Vector3(40.0, 0.0, 40.0), "11_lagoon_cliffs")

func _view(from: Vector3, to: Vector3, name: String) -> void:
	cam.global_position = from
	cam.look_at(to)
	await wait(0.6)
	await shot(name)
