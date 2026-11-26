## test-timeout: 600
extends TestCase
## Следы v5: (1) сдвиг окна карты следов перерисовывает карту в том же кадре (баг «тропинка следов
## впереди бегущего»); (2) в воздухе следов нет, толчок — пара FOOT_TOE, приземление — пара FOOT_HEEL;
## (3) на бегу шаг длиннее (следы реже); (4) присед на месте — отпечаток колена.

class Walker extends Node3D:
	var velocity := Vector3.ZERO
	var on_floor := true
	var crouching := false
	func is_on_floor() -> bool:
		return on_floor

var w: World
var st: Node

func _init() -> void:
	scene_path = "res://scenes/world/world_view.tscn"

func _beach_spot() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for I in w.islands():
		var c: Vector2 = I.center
		var R: float = I.radius
		for i in 800:
			var a := rng.randf() * TAU
			var p := c + Vector2(cos(a), sin(a)) * rng.randf_range(0.5, 1.3) * R
			if w.biome_at(p.x, p.y) != &"beach" or w.normal_at(p.x, p.y).y < 0.95:
				continue
			var t := Vector2(-sin(a), cos(a))      # вдоль берега
			var ok := true
			for k in range(-12, 13):
				var q := p + t * k
				if w.biome_at(q.x, q.y) != &"beach":
					ok = false
					break
			if ok:
				return {"p": p, "t": t}
	return {}

func _count(type: int) -> int:
	var n := 0
	for p: Array in st.prints:
		if int(p[7]) == type:
			n += 1
	return n

func _move(n: Walker, p: Vector2, steps: int, dir: Vector2, speed: float) -> Vector2:
	n.velocity = Vector3(dir.x, 0, dir.y) * speed
	for i in steps:
		p += dir * speed / 60.0
		n.global_position = Vector3(p.x, w.height_at(p.x, p.y), p.y)
		await wait_frames(1)
	return p

func run() -> void:
	w = get_tree().get_first_node_in_group(&"world") as World
	var t0 := Time.get_ticks_msec()
	while w == null and Time.get_ticks_msec() - t0 < 120000:
		await wait(0.5)
		w = get_tree().get_first_node_in_group(&"world") as World
	check(w != null, "мир есть")
	if w == null:
		return
	st = get_node_or_null("/root/SandTracks")
	check(st != null, "SandTracks есть")
	var spot := _beach_spot()
	check(not spot.is_empty(), "найден прямой пляж")
	if st == null or spot.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		cam = Camera3D.new()
		get_tree().current_scene.add_child(cam)
		cam.make_current()
	var p: Vector2 = spot.p
	var dir: Vector2 = spot.t
	var gy := w.height_at(p.x, p.y)
	cam.global_position = Vector3(p.x, gy + 1.7, p.y)
	await wait(1.0)
	check(bool(st.get("_active")), "следы активны на пляжном песке")
	st.clear()
	var n := Walker.new()
	n.add_to_group(&"characters")
	get_tree().current_scene.add_child(n)
	n.global_position = Vector3(p.x, gy, p.y)
	await wait_frames(3)

	# ---- ходьба: шаг ~0.72 м
	var a := p
	p = await _move(n, p, 120, dir, 1.6)
	var walk_n: int = st.prints.size()
	var walk_len := (p - a).length()
	var walk_stride := walk_len / maxf(walk_n, 1)
	print("[test] ходьба: %d отпечатков на %.1f м (шаг %.2f)" % [walk_n, walk_len, walk_stride])
	check(walk_stride > 0.6 and walk_stride < 0.9, "ходьба: шаг 0.6–0.9 м (%.2f)" % walk_stride)

	# ---- бег: шаг длиннее, отпечатки FOOT_TOE
	st.clear()
	n.global_position = Vector3(p.x, w.height_at(p.x, p.y), p.y)
	await wait_frames(2)
	a = p
	p = await _move(n, p, 60, -dir, 6.4)
	var run_n: int = st.prints.size()
	var run_stride := (p - a).length() / maxf(run_n, 1)
	print("[test] бег: %d отпечатков на %.1f м (шаг %.2f)" % [run_n, (p - a).length(), run_stride])
	check(run_stride > 1.1, "бег: шаг длиннее 1.1 м (%.2f)" % run_stride)
	check(_count(6) >= run_n - 1, "бег: отпечатки с упором на носок (FOOT_TOE)")

	# ---- прыжок: в воздухе нет следов, толчок и приземление — по паре
	st.clear()
	await wait_frames(2)
	n.on_floor = false
	p = await _move(n, p, 1, dir, 5.0)
	var toe_n := _count(6)
	check(toe_n == 2, "толчок: пара FOOT_TOE (%d)" % toe_n)
	var before_air: int = st.prints.size()
	p = await _move(n, p, 30, dir, 5.0)
	check(st.prints.size() == before_air, "в воздухе следов нет (%d → %d)" % [before_air, st.prints.size()])
	n.on_floor = true
	p = await _move(n, p, 1, dir, 5.0)
	var heel_n := _count(7)
	check(heel_n == 2, "приземление: пара FOOT_HEEL (%d)" % heel_n)

	# ---- присед на месте — колено
	n.velocity = Vector3.ZERO
	n.crouching = true
	await wait_frames(3)
	check(_count(8) == 1, "присед: один отпечаток колена (%d)" % _count(8))
	await wait_frames(3)
	check(_count(8) == 1, "колено не дублируется за один присед")

	# ---- сдвиг окна: карта перерисовывается в том же кадре
	var o0: Vector2 = st.origin
	cam.global_position += Vector3(20, 0, 20)
	await wait_frames(1)
	check(st.origin != o0, "окно следов сдвинулось за камерой")
	check(not bool(st.get("_dirty")), "после сдвига окна карта перерисована сразу (нет отложенной перерисовки)")
	n.queue_free()
