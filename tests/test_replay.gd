## test-timeout: 900
extends TestCase
## Реплей: запись на полигоне (игрок идёт, рядом зверь) → клип → сохранение/чтение →
## воспроизведение по записи в этой же сцене (без рендера кадров): игрок и существа
## стоят там же, где были в записи; аргументы дочерних процессов рендера и сборки.

var pg: Polygon

func _init() -> void:
	scene_path = "res://scenes/polygon/polygon.tscn"
	timeout_sec = 850.0

func run() -> void:
	Engine.max_physics_steps_per_frame = 30
	pg = scene as Polygon
	var t0 := Time.get_ticks_msec()
	while not pg.is_built and Time.get_ticks_msec() - t0 < 600000:
		await wait(0.5)
	check(pg.is_built, "полигон собран")
	if not pg.is_built:
		return
	var rec := pg.recorder
	check(rec != null, "запись идёт")
	# зверь рядом и проход игрока
	var p0 := pg.player.global_position
	var fa := Fauna.instance()
	var boar: Animal = fa.spawn(&"boar", p0 + Vector3(6, 0.3, 4), 6.0) if fa else null
	rec.frames.clear()
	rec.events.clear()
	for i in 90:
		pg.player.global_position = p0 + Vector3(i * 0.05, 0, i * 0.08)
		pg.player.set_look(float(i) * 0.01, -0.1)
		await wait_frames(1)
	await wait(0.5)
	var c := rec.clip(30.0)
	var fr: Array = c.frames
	check(fr.size() >= 20, "клип: %d кадров, %.1f с" % [fr.size(), float(c.duration)])
	check(int((c.actors as Dictionary).size()) >= 1, "в клипе есть существа (%d)" % (c.actors as Dictionary).size())
	var path := ReplayRender.save_clip(c)
	var back = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(back is Dictionary and (back.frames as Array).size() == fr.size(), "клип сохраняется и читается: " + path)
	# аргументы дочерних процессов
	var ra := ReplayRender.render_args("/x/clip.json", 3)
	check("--fixed-fps" in ra and "--replay-render=/x/clip.json" in ra and "--replay-quality=3" in ra, "аргументы рендера: " + " ".join(ra))
	var ea := ReplayRender.encode_args("/x/frames", 100, "/x/replay.ogv")
	check("--write-movie" in ea and "/x/replay.ogv" in ea and ReplayRender.ENCODE_SCENE in ea, "аргументы сборки видео: " + " ".join(ea))
	# воспроизведение в этой же сцене (без кадров): сравнить позиции
	if boar:
		boar.queue_free()
	ReplayPlayback.clip = back
	ReplayPlayback.capture = false
	var rp := ReplayPlayback.attach(pg)
	rp.frame = 0
	var err_pl := 0.0
	var err_act := 0.0
	var n := 0
	for k in 60:
		var t := float(k) / 60.0 * float(c.duration)
		rp.apply(t)
		await wait_frames(1)
		var fk := rp.frame_at(t)
		var a: Dictionary = fk[0]
		var b: Dictionary = fk[1]
		var kk: float = fk[2]
		var pa: Array = a.pl
		var pb: Array = b.pl
		var want := Vector3(float(pa[0]), float(pa[1]), float(pa[2])).lerp(Vector3(float(pb[0]), float(pb[1]), float(pb[2])), kk)
		rp.apply(t)
		err_pl = maxf(err_pl, pg.player.global_position.distance_to(want))
		n += 1
	for e: Dictionary in rp.applied:
		var fk2 := rp.frame_at(float(e.t))
		var ra2: Array = (fk2[0] as Dictionary).act.get(e.key, [])
		if ra2.is_empty():
			continue
		var xa := ReplayRecorder.xf_of(ra2)
		var rb: Array = (fk2[1] as Dictionary).act.get(e.key, ra2)
		var want2 := xa.interpolate_with(ReplayRecorder.xf_of(rb), float(fk2[2])).origin
		err_act = maxf(err_act, (e.pos as Vector3).distance_to(want2))
	check(err_pl < 0.05, "игрок в реплее там же, где в записи (ошибка %.3f м, %d проверок)" % [err_pl, n])
	check(rp.applied.size() > 0 and err_act < 0.05, "существа в реплее по записи (ошибка %.3f м, %d)" % [err_act, rp.applied.size()])
	ReplayPlayback.capture = true
	ReplayPlayback.clip = {}
	DirAccess.remove_absolute(path)
