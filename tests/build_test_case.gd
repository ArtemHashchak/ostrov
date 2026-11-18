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

## Простой «чужак» для тестов: капсула, идёт к цели, получает урон.
class Walker extends CharacterBody3D:
	var team: int = 1
	var health: float = 100.0
	var target: Vector3 = Vector3.ZERO
	var walking: bool = false
	var speed: float = 3.0
	var hits: int = 0

	func _ready() -> void:
		add_to_group(&"characters")
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.35
		cap.height = 1.8
		cs.shape = cap
		cs.position.y = 0.9
		add_child(cs)
		var mi := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.35
		cm.height = 1.8
		mi.mesh = cm
		mi.position.y = 0.9
		var m := StandardMaterial3D.new()
		m.albedo_color = Game.team_color(team)
		mi.material_override = m
		add_child(mi)

	func apply_damage(amount: float, _source: Node = null, _kind: StringName = &"melee") -> void:
		health -= amount
		hits += 1

	func is_dead() -> bool:
		return health <= 0.0

	func _physics_process(delta: float) -> void:
		var v := velocity
		v.y -= 20.0 * delta
		if walking:
			var d := target - global_position
			d.y = 0.0
			if d.length() > 0.3:
				var h := d.normalized() * speed
				v.x = move_toward(v.x, h.x, 30.0 * delta)
				v.z = move_toward(v.z, h.z, 30.0 * delta)
			else:
				v.x = 0.0
				v.z = 0.0
		else:
			v.x = move_toward(v.x, 0.0, 20.0 * delta)
			v.z = move_toward(v.z, 0.0, 20.0 * delta)
		velocity = v
		move_and_slide()

func spawn_walker(pos: Vector3, team: int = 1) -> Walker:
	var w := Walker.new()
	w.team = team
	scene.add_child(w)
	w.global_position = pos
	return w

## Достроить постройку всеми материалами.
func finish(b: Blueprint) -> void:
	for t: StringName in [&"log", &"stick", &"rope", &"stone"]:
		b.add_material(t, 99)

## Точка на земле.
func ground(x: float, z: float) -> Vector3:
	return Vector3(x, BuildEnv.height_at(x, z), z)
