extends TestCase
## Проба: столб цветного дыма вблизи и издалека.
func _init() -> void:
	timeout_sec = 300.0

func look(p: Player, at: Vector3) -> void:
	var d := at - p.get_eye_position()
	p.set_look(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))

func run() -> void:
	await wait(1.0)
	var p := get_tree().get_first_node_in_group(&"player") as Player
	p.inventory.clear()
	p.global_position = Vector3(40, BuildEnv.height_at(40, 0) + 0.1, 0)
	var y := BuildEnv.height_at(52, 0)
	var n := Node3D.new()
	scene.add_child(n)
	n.global_position = Vector3(52, y, 0)
	SupplyFx.smoke_column(n, SupplyModels.TIER_COLORS[1])
	await wait(0.3)
	look(p, Vector3(52, y + 12.0, 0))
	await wait(3.0)
	await shot("near")
	p.global_position = Vector3(-10, BuildEnv.height_at(-10, 0) + 0.1, 0)
	await wait(0.3)
	look(p, Vector3(52, y + 18.0, 0))
	await wait(1.0)
	await shot("far")
