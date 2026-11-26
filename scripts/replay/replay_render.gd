class_name ReplayRender
extends Control
## Экран «Рендер в максимальной графике…» (сцена scenes/replay/replay_wait.tscn).
## Полигон к этому моменту выгружен (память свободна). Шаги:
##   1) дочерний процесс игры: сцена из клипа на «ультра», покадрово по записи
##      (--fixed-fps 60: время кадра всегда 1/60 с, сколько бы кадр ни считался),
##      кадры → user://replays/<id>/frames/*.jpg (ReplayPlayback);
##   2) второй процесс: кадры подряд + Movie Maker Godot → replay.ogv (ReplayEncode);
##   3) видео показывается здесь (VideoStreamPlayer) и лежит в папке реплеев.
## Если «ультра» не поместилась (процесс упал) — повтор на «высоком», затем «среднем»;
## что выключено — пишется на экране.

const WAIT_SCENE := "res://scenes/replay/replay_wait.tscn"
const ENCODE_SCENE := "res://scenes/replay/replay_encode.tscn"
const RES := "1920x1080"
const FPS := 60

static var clip_path := ""

var _dir := ""
var _pid := -1
var _stage := ""                # render | encode | done | failed
var _quality := 3
var _notes: PackedStringArray = []
var _title: Label
var _info: Label
var _bar: ProgressBar
var _video: VideoStreamPlayer
var _buttons: HBoxContainer
var _poll := 0.0
var _clip: Dictionary = {}

## Каталог для нового клипа и сохранение.
static func save_clip(c: Dictionary) -> String:
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	var dir := "user://replays/%s" % stamp
	DirAccess.make_dir_recursive_absolute(dir + "/frames")
	var path := dir + "/clip.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(c))
	f.close()
	return path

static func begin(tree: SceneTree, path: String) -> void:
	clip_path = path
	Game.end_session()
	tree.paused = false
	tree.change_scene_to_file(WAIT_SCENE)

## Аргументы запуска самой игры (в редакторе/из исходников — ещё путь проекта).
static func base_args() -> PackedStringArray:
	var a := PackedStringArray()
	if not OS.has_feature("template"):
		a.append_array(["--path", ProjectSettings.globalize_path("res://")])
	return a

static func render_args(clip_abs: String, quality: int, res: String = RES) -> PackedStringArray:
	var a := base_args()
	a.append_array(["--fixed-fps", str(FPS), "--resolution", res, "--", "--replay-render=" + clip_abs,
		"--replay-quality=%d" % quality])
	return a

static func encode_args(frames_abs: String, count: int, out_abs: String, res: String = RES) -> PackedStringArray:
	var a := base_args()
	a.append_array(["--write-movie", out_abs, "--fixed-fps", str(FPS), "--resolution", res, ENCODE_SCENE, "--",
		"--replay-frames=" + frames_abs, "--replay-count=%d" % count])
	return a

static func progress(dir: String) -> Dictionary:
	var p := dir + "/progress.json"
	if not FileAccess.file_exists(p):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	return d if d is Dictionary else {}

# ------------------------------------------------------------ экран ожидания

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.04)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_video = VideoStreamPlayer.new()
	_video.set_anchors_preset(Control.PRESET_FULL_RECT)
	_video.expand = true
	_video.visible = false
	add_child(_video)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.position = Vector2(-320, -90)
	v.custom_minimum_size = Vector2(640, 0)
	add_child(v)
	_title = Label.new()
	_title.text = "Рендер в максимальной графике…"
	_title.add_theme_font_size_override(&"font_size", 28)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_title)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(640, 26)
	v.add_child(_bar)
	_info = Label.new()
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(_info)
	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_buttons)
	_buttons.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_buttons.position = Vector2(-330, -70)
	_buttons.custom_minimum_size = Vector2(660, 44)
	_btn("Открыть папку с видео", func() -> void: OS.shell_open(ProjectSettings.globalize_path(_dir)))
	_btn("Смотреть ещё раз", func() -> void:
		if _video.stream:
			_video.play())
	_btn("← На полигон", _back)
	if clip_path == "" or not FileAccess.file_exists(clip_path):
		_fail("Нет записи для реплея.")
		return
	_dir = clip_path.get_base_dir()
	var d = JSON.parse_string(FileAccess.get_file_as_string(clip_path))
	_clip = d if d is Dictionary else {}
	_quality = 3
	_start_render()

func _btn(t: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(210, 40)
	b.pressed.connect(cb)
	_buttons.add_child(b)

func _start_render() -> void:
	_stage = "render"
	var f := FileAccess.open(_dir + "/progress.json", FileAccess.WRITE)
	f.store_string("{}")
	f.close()
	var args := render_args(ProjectSettings.globalize_path(clip_path), _quality)
	_pid = OS.create_process(OS.get_executable_path(), args)
	_info.text = "Качество: %s. Кадры считаются не в реальном времени — это может занять несколько минут." % \
		GraphicsQuality.NAMES[_quality]
	if _pid <= 0:
		_fail("Не удалось запустить рендер.")

func _start_encode(count: int) -> void:
	_stage = "encode"
	var out := ProjectSettings.globalize_path(_dir + "/replay.ogv")
	_pid = OS.create_process(OS.get_executable_path(), encode_args(ProjectSettings.globalize_path(_dir + "/frames"), count, out))
	_title.text = "Сборка видео…"
	if _pid <= 0:
		_fail("Не удалось запустить сборку видео.")

func _process(delta: float) -> void:
	_poll -= delta
	if _poll > 0.0 or _stage in ["done", "failed", ""]:
		return
	_poll = 0.4
	var pr := progress(_dir)
	var running := _pid > 0 and OS.is_process_running(_pid)
	match _stage:
		"render":
			var total := maxi(1, int(pr.get("total", 1)))
			_bar.value = 100.0 * float(pr.get("frame", 0)) / total
			if pr.get("stage", "") == "render":
				_title.text = "Рендер в максимальной графике… кадр %d из %d" % [int(pr.get("frame", 0)), total]
			if not running:
				if pr.get("stage", "") == "done":
					_start_encode(int(pr.get("frames", total)))
				elif _quality > 1:
					_notes.append("«%s» не поместилась в память видеокарты" % GraphicsQuality.NAMES[_quality])
					_quality -= 1
					_notes.append("рендер на «%s» (выключено: %s)" % [GraphicsQuality.NAMES[_quality], _disabled(_quality)])
					_start_render()
					_info.text += "\n" + "; ".join(_notes)
				else:
					_fail("Рендер не удался.")
		"encode":
			var total2 := maxi(1, int(pr.get("count", 1)))
			_bar.value = 100.0 * float(pr.get("shown", 0)) / total2
			if not running:
				_show_video()

static func _disabled(q: int) -> String:
	var hi := GraphicsQuality.PRESETS[3]
	var lo := GraphicsQuality.PRESETS[q]
	var off := PackedStringArray()
	for k: String in ["sdfgi", "vol_fog", "ssil", "ssao", "glow"]:
		if bool(hi.get(k, false)) and not bool(lo.get(k, false)):
			off.append({"sdfgi": "глобальное освещение SDFGI", "vol_fog": "объёмный туман", "ssil": "SSIL",
				"ssao": "SSAO", "glow": "свечение"}[k])
	return ", ".join(off) if not off.is_empty() else "ничего"

func _show_video() -> void:
	var ogv := _dir + "/replay.ogv"
	if not FileAccess.file_exists(ogv):
		_fail("Видео не собралось.")
		return
	_stage = "done"
	# кадры больше не нужны — видео готово
	var fd := _dir + "/frames"
	for fn in DirAccess.get_files_at(fd):
		DirAccess.remove_absolute(fd + "/" + fn)
	var vs := VideoStreamTheora.new()
	vs.file = ProjectSettings.globalize_path(ogv)
	_video.stream = vs
	_video.visible = true
	_video.play()
	_title.text = ""
	_bar.visible = false
	_info.text = ("Готово: %s" % ProjectSettings.globalize_path(ogv)) + ("" if _notes.is_empty() else "\n" + "; ".join(_notes))

func _fail(msg: String) -> void:
	_stage = "failed"
	_title.text = msg
	_bar.visible = false

func _back() -> void:
	var m: Dictionary = _clip.get("meta", {})
	if String(m.get("scene", "polygon")) == "island":
		PolygonIslandStage.open(get_tree(), String(m.get("island", "volcanic")))
	else:
		var opts := {}
		if String(m.get("section", "")) != "":
			opts["section"] = StringName(m.section)
		Polygon.start(get_tree(), opts)
