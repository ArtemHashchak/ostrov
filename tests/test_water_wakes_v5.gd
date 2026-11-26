## test-timeout: 600
extends TestCase
## След на воде (WaterWakes): пловец оставляет след и кольца ряби, плот — след и бурун у носа,
## всплеск — пена + кольцо; старые точки исчезают; окно карты идёт за камерой.

class Swimmer extends Node3D:
	var swimming := true

func _init() -> void:
	scene_path = "res://scenes/world/world_view.tscn"

func _count(kind: int) -> int:
	var ww := get_node("/root/WaterWakes")
	var n := 0
	for p: Array in ww.pts:
		if int(p[5]) == kind:
			n += 1
	return n

func run() -> void:
	await wait(1.0)
	var w := get_tree().get_first_node_in_group(&"world") as World
	check(w != null, "мир есть")
	var ww := get_node_or_null("/root/WaterWakes")
	check(ww != null, "автозагрузка WaterWakes есть")
	if w == null or ww == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		cam = Camera3D.new()
		scene.add_child(cam)
		cam.make_current()
	var wl := w.water_level()
	var p := Vector3(5000, wl, 5000)
	cam.global_position = p + Vector3(0, 3, 0)
	await wait_frames(3)
	ww.clear()
	var s := Swimmer.new()
	s.add_to_group(&"characters")
	scene.add_child(s)
	s.global_position = p
	await wait_frames(2)
	for i in 90:
		s.global_position += Vector3(1.2 / 60.0, 0, 0)
		await wait_frames(1)
	check(_count(0) >= 3, "пловец оставляет след (%d)" % _count(0))
	check(_count(1) >= 1, "пловец даёт кольца ряби (%d)" % _count(1))
	check(_count(2) == 0, "у пловца нет буруна")
	s.queue_free()
	ww.clear()
	var r := Node3D.new()
	r.add_to_group(&"raft_deck")
	scene.add_child(r)
	r.global_position = p
	await wait_frames(2)
	for i in 90:
		r.global_position += Vector3(2.0 / 60.0, 0, 0)
		await wait_frames(1)
	check(_count(0) >= 3 and _count(2) >= 3, "плот: след %d и бурун %d" % [_count(0), _count(2)])
	r.queue_free()
	ww.clear()
	ww.splash(p, 1.0)
	check(_count(2) == 1 and _count(1) == 1, "всплеск: пена и кольцо")
	await wait(1.0)
	for i in 30:
		ww._process(0.3)
	check(ww.pts.is_empty(), "старые точки следа исчезают")
	var o0: Vector2 = ww.origin
	cam.global_position += Vector3(40, 0, 0)
	await wait_frames(2)
	check(ww.origin != o0, "окно карты следа идёт за камерой")
