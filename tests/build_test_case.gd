class_name BuildTestCase
extends TestCase
## Общие хелперы тестов стройки.

var p: Player
var mod: BuildModule

func setup_build() -> bool:
	await wait(1.0)
	p = get_tree().get_first_node_in_group(&"player") as Player
	if p == null:
		check(false, "игрок создан")
		return false
	mod = BuildModule.new()
	mod.name = "BuildModule"
	scene.add_child(mod)
	await wait_frames(3)
	check(p.get_node_or_null(^"BuildMode") != null, "BuildMode прицеплен к игроку")
	return true

func build_mode() -> BuildMode:
	return p.get_node(^"BuildMode") as BuildMode

func teleport(pos: Vector3) -> void:
	p.global_position = pos
	p.velocity = Vector3.ZERO

## Повернуть взгляд на точку.
func aim_at(target: Vector3) -> void:
	var d := target - p.get_eye_position()
	var yaw := atan2(-d.x, -d.z)
	var pitch := atan2(d.y, Vector2(d.x, d.z).length())
	p.set_look(yaw, pitch)

## Создать бревно (как TestProp) и взять его на плечо.
func give_log() -> void:
	var lg := TestProp.new()
	lg.kind = &"log"
	scene.add_child(lg)
	lg.global_position = p.global_position + Vector3(0, -5, 0)
	lg.interact(p)

## Отнести бревно в чертёж: игрок смотрит на чертёж и жмёт E.
func carry_log_into(bp: Blueprint, look_at: Vector3) -> bool:
	give_log()
	aim_at(look_at)
	await wait_frames(3)
	var before := bp.filled_count(&"log")
	await tap(&"interact")
	await wait_frames(2)
	return bp.filled_count(&"log") > before
