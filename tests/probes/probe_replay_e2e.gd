## test-timeout: 3000
extends TestCase
## test-class: render
## Сквозная проверка реплея с настоящими процессами (нужен рендер, xvfb):
## запись 2 с на полигоне → дочерний процесс рендерит кадры (низкое качество, 640×360)
## → второй процесс собирает replay.ogv → файл видео есть и открывается VideoStreamTheora.

## Сервер тестов — без Vulkan: дочерним процессам тот же рендер, что у раннера.
const COMPAT := ["--rendering-driver", "opengl3", "--rendering-method", "gl_compatibility"]

func _init() -> void:
	scene_path = "res://scenes/polygon/polygon.tscn"
	timeout_sec = 2900.0

func run() -> void:
	var pg := scene as Polygon
	var t0 := Time.get_ticks_msec()
	while not pg.is_built and Time.get_ticks_msec() - t0 < 900000:
		await wait(0.5)
	check(pg.is_built, "полигон собран")
	var p0 := pg.player.global_position
	pg.recorder.frames.clear()
	for i in 70:
		pg.player.global_position = p0 + Vector3(0, 0, i * 0.06)
		pg.player.set_look(float(i) * 0.012, -0.05)
		await wait_frames(1)
	var c := pg.recorder.clip(2.0)
	var path := ReplayRender.save_clip(c)
	var dir := path.get_base_dir()
	var out: Array = []
	var t1 := Time.get_ticks_msec()
	var ra := PackedStringArray(COMPAT) + ReplayRender.render_args(ProjectSettings.globalize_path(path), 0, "640x360")
	var rc := OS.execute(OS.get_executable_path(), ra, out, true)
	var pr := ReplayRender.progress(dir)
	var frames := DirAccess.get_files_at(dir + "/frames").size()
	check(rc == 0 and pr.get("stage", "") == "done", "рендер кадров: код %d, %s, кадров %d, %d с" % [rc, str(pr), frames, (Time.get_ticks_msec() - t1) / 1000])
	if frames == 0:
		print("\n".join(PackedStringArray(out)).right(3000))
		return
	var ogv := ProjectSettings.globalize_path(dir + "/replay.ogv")
	out.clear()
	rc = OS.execute(OS.get_executable_path(), PackedStringArray(COMPAT) + ReplayRender.encode_args(ProjectSettings.globalize_path(dir + "/frames"), frames, ogv, "640x360"), out, true)
	check(rc == 0 and FileAccess.file_exists(ogv) and FileAccess.get_file_as_bytes(ogv).size() > 1000,
		"видео собрано: %s (%d байт)" % [ogv, FileAccess.get_file_as_bytes(ogv).size() if FileAccess.file_exists(ogv) else 0])
	var vs := VideoStreamTheora.new()
	vs.file = ogv
	var pb: Object = vs.instantiate_playback()
	check(pb != null, "видео открывается проигрывателем")
	print("[probe] видео: ", ogv)
