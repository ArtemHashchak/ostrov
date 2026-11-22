extends TestCase
## test-class: render
## Замер (не проверка): растения пака в матче. FLORA_PACK=0 — прежняя процедурная флора (для «до»).
## Со спавна и на виды пляж/джунгли/мангры: вызовы отрисовки и примитивы всего кадра и FLORA
## (FLORA прячется — разница). Снимки — tests/shots/probe_flora_pack_*.png.
## Вывод: [fpack] … и tests/logs/flora_pack_perf_<pack|old>.txt.

var _out: PackedStringArray = []
var _mode := "pack"

func _init() -> void:
	scene_path = "res://scenes/world/match.tscn"
	timeout_sec = 1500.0
	if OS.get_environment("FLORA_PACK") == "0":
		FloraPack.enabled = false
		_mode = "old"
	Game.pending_config = {"mode": "ffa", "minutes": 180, "bots_enemy": 1, "bots_ally": 0, "auto_flags": true}

func _ln(s: String) -> void:
	print("[fpack] ", s)
	_out.append(s)

func _match_ready() -> bool:
	for i in 1800:
		if scene and scene.is_inside_tree() and not (scene.get(&"loaded_modules") as Array).is_empty() \
				and Game.is_playing() and get_tree().get_first_node_in_group(&"player") != null:
			return true
		await wait(0.5)
	return false

func _measure() -> Vector2i:
	await wait_frames(8)
	var d := 0
	var p := 0
	for i in 3:
		await RenderingServer.frame_post_draw
		d += int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		p += int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	return Vector2i(d / 3, p / 3)

func run() -> void:
	check(await _match_ready(), "матч загрузился")
	await wait(4.0)
	var fl := Flora.instance()
	var p := get_tree().get_first_node_in_group(&"player") as Node3D
	var cam := Camera3D.new()
	cam.far = 4000.0
	scene.add_child(cam)
	cam.make_current()
	var sp: Vector3 = p.global_position
	var views := [["spawn_eye", sp + Vector3(0, 1.7, 0), sp + Vector3(20, 1.5, 20)],
		["spawn_to_center", sp + Vector3(0, 1.7, 0), Vector3(0, sp.y, 0)]]
	# виды по записям флоры: ближайшая пальма у воды, мангр, лиственное в джунглях
	for kind in [&"palm", &"mangrove", &"broadleaf"]:
		var best: Dictionary = {}
		var bd := 1e9
		for rec: Dictionary in fl._tree_recs:
			if rec["kind"] == kind:
				var d := (rec["pos"] as Vector3).distance_to(sp)
				if d < bd:
					bd = d
					best = rec
		if not best.is_empty():
			var tp: Vector3 = best["pos"]
			var dir := Vector3(sp.x - tp.x, 0, sp.z - tp.z).normalized()
			views.append([String(kind), tp + dir * 14.0 + Vector3(0, 3.0, 0), tp + Vector3(0, 3.0, 0)])
	_ln("режим %s, FloraPack=%s, деревья %s" % [_mode, FloraPack.available(), str({"palm": fl.stats.get("palm"), "mangrove": fl.stats.get("mangrove"), "broadleaf": fl.stats.get("broadleaf"), "bush": fl.stats.get("bush"), "fern": fl.stats.get("fern"), "epiphyte": fl.stats.get("epiphyte", 0)})])
	for v in views:
		cam.global_position = v[1]
		cam.look_at(v[2])
		await wait(2.5)
		var all := await _measure()
		fl.visible = false
		var nof := await _measure()
		fl.visible = true
		await wait_frames(4)
		_ln("%s: кадр %d вызовов / %d прим.; FLORA %d / %d" % [v[0], all.x, all.y, all.x - nof.x, all.y - nof.y])
		await shot("%s_%s" % [_mode, v[0]])
	var f := FileAccess.open("res://tests/logs/flora_pack_perf_%s.txt" % _mode, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_out) + "\n")
