class_name SvWild
extends SvStation
## Дикое растение (не возобновляется): таро, ягодник, лечебная трава.
## E — собрать (еда + семена/черенок). Ягодник после сбора остаётся без ягод.

const LOOT := {
	&"taro": {"name": "Дикий таро", "give": {&"taro": 2, &"seed_taro": 1}},
	&"berry": {"name": "Дикий ягодник", "give": {&"berries": 4, &"seed_berry": 1}},
	&"herb": {"name": "Лечебная трава", "give": {&"herb": 3}},
}

var picked := false

func _ready() -> void:
	name = "SvWild_" + String(kind)
	remove_from_group(&"buildable")
	add_to_group(&"sv_wild")
	max_hp = 10.0
	hp = max_hp
	model = SurvivalModels.wild_plant(kind, int(get_instance_id() % 997))
	add_child(model)
	collision_layer = 1
	add_shape(Vector3(0.7, 0.6, 0.7), Vector3.ZERO, true)

func get_interact_text(_ch: Node) -> String:
	var nm := String(LOOT.get(kind, {}).get("name", "Растение"))
	if picked:
		return nm + " — обобран"
	return nm + " — E: собрать"

func interact(ch: Node) -> void:
	pick(ch)

func pick(ch: Node) -> Dictionary:
	if picked:
		return {}
	picked = true
	var g: Dictionary = LOOT.get(kind, {}).get("give", {})
	for id in g.keys():
		Survival.give(ch, StringName(id), int(g[id]), global_position + Vector3.UP * 0.5)
	if kind == &"berry":
		model.queue_free()
		model = SurvivalModels.plant(&"berry", 2, 0.25, 5)
		add_child(model)
	else:
		queue_free()
	return g

func on_hit(by: Node, _hit: Dictionary) -> void:
	if not picked:
		pick(by)
