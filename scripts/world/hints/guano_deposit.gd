class_name GuanoDeposit
extends StaticBody3D
## Залежь гуано на птичьем базаре (пункт 27): белая корка помёта на карнизе скалы.
## E — соскрести гуано (3 раза, потом пусто). Из гуано у костра — селитра для пороха
## (рецепт r_saltpeter_guano, регистрирует WorldHints.ensure_items()).

var left := 3
var _mi: MeshInstance3D

func _ready() -> void:
	add_to_group(&"interactable")
	add_to_group(&"guano_deposits")
	collision_layer = 1
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.9, 0.25, 0.9)
	cs.shape = bs
	cs.position.y = 0.1
	add_child(cs)
	_mi = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.45
	sm.height = 0.22
	sm.radial_segments = 12
	sm.rings = 5
	_mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.93, 0.92, 0.86)
	m.roughness = 0.95
	_mi.material_override = m
	_mi.scale = Vector3(1.0, 0.45, 0.8)
	add_child(_mi)

func get_interact_text(_ch: Node) -> String:
	if left <= 0:
		return "Гуано — соскребли дочиста"
	return "Гуано (птичий помёт) — E: соскрести (селитра для пороха)"

func interact(ch: Node) -> void:
	if left <= 0:
		return
	left -= 1
	Survival.give(ch, &"guano", 2, global_position + Vector3.UP * 0.4)
	_mi.scale = Vector3(1.0, 0.45, 0.8) * (0.4 + 0.2 * left)
	if left == 0:
		_mi.visible = false

func on_hit(by: Node, _hit: Dictionary) -> void:
	interact(by)
