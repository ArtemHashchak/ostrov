## test-timeout: 1500
extends TestCase
## Мир v5 + игрок: звериная тропа (пригнувшись ≈70 % шага), густые джунгли вне троп
## замедляют, мачете срубает подлесок и прорубает проход (тропа &"cut", 100 %).

func _init() -> void:
	OS.set_environment("OSTROVA_GEN", "5")
	scene_path = "res://scenes/world/match.tscn"
	timeout_sec = 1450.0

func run() -> void:
	await wait(2.0)
	var w := get_tree().get_first_node_in_group(&"world") as World
	check(w != null and w.is_ready and w.arch is ArchipelagoV5, "мир v5 готов")
	if w == null:
		return
	var p := get_tree().get_first_node_in_group(&"player") as Player
	check(p != null, "игрок есть")
	if p == null:
		return
	# 1) точка на звериной тропе
	var tp := Vector2.INF
	for i in w.trails.trails.size():
		if w.trails.kinds[i] == &"animal" and w.trails.trails[i].size() > 4:
			tp = w.trails.trails[i][2]
			break
	check(tp != Vector2.INF, "есть звериная тропа")
	if tp == Vector2.INF:
		return
	p.global_position = Vector3(tp.x, w.height_at(tp.x, tp.y) + 0.2, tp.y)
	await wait(0.3)
	p._update_trail(true)
	check(p.trail_kind == &"animal", "на тропе: trail_kind=%s" % p.trail_kind)
	check(p.veg_drag < 0.01, "на тропе джунгли не мешают (drag=%.2f)" % p.veg_drag)
	var on_trail_speed := Player.WALK_SPEED * Player.TRAIL_CROUCH_MUL
	check(on_trail_speed > Player.CROUCH_SPEED * 1.3, "пригнувшись по тропе быстрее обычного приседа (%.2f > %.2f)" % [on_trail_speed, Player.CROUCH_SPEED])
	# 2) густые джунгли вне тропы
	var best := Vector2.INF
	var best_d := 0.0
	for dx in range(-40, 41, 4):
		for dz in range(-40, 41, 4):
			var q := tp + Vector2(dx, dz)
			if w.trail_dist(q.x, q.y) < 3.0:
				continue
			var d := w.vegetation_drag(q.x, q.y)
			if d > best_d and w.height_at(q.x, q.y) > 1.0:
				best_d = d
				best = q
	check(best_d > 0.4, "рядом есть густые джунгли (drag=%.2f)" % best_d)
	if best == Vector2.INF:
		return
	p.global_position = Vector3(best.x, w.height_at(best.x, best.y) + 0.2, best.y)
	await wait(0.3)
	p._update_trail(true)
	var env := p._env_speed()
	print("[test] джунгли: drag=%.2f env_speed=%.2f" % [p.veg_drag, env])
	check(env < 0.75, "в зарослях вне тропы медленнее (×%.2f)" % env)
	# 3) мачете: прорубить проход 3 удара по 1,5 м
	var fl := get_tree().get_first_node_in_group(&"flora") as Flora
	var cut0 := int(fl.stats.get("brush_cut", 0)) if fl else 0
	var dir := Vector2(1, 0)
	for k in 4:
		var q2 := best + dir * (1.5 * k)
		w.cut_vegetation(p, Vector3(q2.x, w.height_at(q2.x, q2.y), q2.y))
	var mid := best + dir * 2.25
	check(w.trail_at(mid.x, mid.y) == &"cut", "прорубленный проход: trail_at=%s" % w.trail_at(mid.x, mid.y))
	check(w.vegetation_drag(mid.x, mid.y) < 0.01, "на прорубленном проходе не мешает")
	print("[test] срублено подлеска: %d" % (int(fl.stats.get("brush_cut", 0)) - cut0 if fl else -1))
