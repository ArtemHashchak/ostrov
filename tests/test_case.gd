class_name TestCase
extends Node
## Базовый класс теста. Переопредели scene_path и run().
## Хелперы: wait(), press(), tap(), shot(), check(), finish().

var scene_path: String = "res://scenes/test/test_island.tscn"
var timeout_sec: float = 120.0
var scene: Node = null
var failures: Array[String] = []
var shots_dir: String = "res://tests/shots"
var test_name: String = "test"

func run() -> void:
	pass

func wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, true).timeout

func wait_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

## Держать действие sec секунд.
func press(action: StringName, sec: float) -> void:
	Input.action_press(action)
	await wait(sec)
	Input.action_release(action)

## Короткое нажатие (доходит до _unhandled_input).
func tap(action: StringName) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await wait_frames(2)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await wait_frames(1)

func shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var dir := ProjectSettings.globalize_path(shots_dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var path := "%s/%s_%s.png" % [dir, test_name, shot_name]
	img.save_png(path)
	print("[test] shot ", path)

func check(cond: bool, msg: String) -> void:
	if cond:
		print("[test] OK   ", msg)
	else:
		print("[test] FAIL ", msg)
		failures.append(msg)
