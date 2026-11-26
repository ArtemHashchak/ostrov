class_name ReplayEncode
extends Control
## Второй шаг реплея: процесс игры, запущенный с `--write-movie replay.ogv --fixed-fps 60`
## прямо на этой сцене. Показывает готовые кадры frames/f00000.jpg… по одному за кадр —
## Movie Maker Godot записывает их в видео Ogg Theora (его умеет играть сама игра).

var _dir := ""
var _count := 0
var _i := 0
var _rect: TextureRect

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--replay-frames="):
			_dir = a.substr(16)
		elif a.begins_with("--replay-count="):
			_count = int(a.substr(15))
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_rect = TextureRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_rect)
	if _dir == "" or _count <= 0:
		get_tree().quit(3)
		return
	_show(0)

func _show(i: int) -> void:
	var img := Image.load_from_file("%s/f%05d.jpg" % [_dir, i])
	if img:
		_rect.texture = ImageTexture.create_from_image(img)

func _process(_delta: float) -> void:
	_i += 1
	if _i >= _count:
		_progress()
		get_tree().quit(0)
		return
	_show(_i)
	if _i % 30 == 0:
		_progress()

func _progress() -> void:
	var p := _dir.get_base_dir() + "/progress.json"
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"stage": "encode", "shown": _i, "count": _count}))
		f.close()
