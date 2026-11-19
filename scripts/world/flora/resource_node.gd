class_name ResourceNode
extends Area3D
## Узел-ресурс FLORA: лиана, лечебные травы, дикие культуры (таро/кукуруза/дыня), ягодный куст, хлопок.
## E (interact) или удар — собрать. Мир невосстанавливаем: собранное растение исчезает навсегда,
## ягодный куст и хлопчатник остаются голыми.
## Боты: `harvest(by) -> Dictionary` (выданные предметы), `can_harvest()`.

signal harvested(node: ResourceNode, removed: bool)

## kind → {verb, drops: [[item, min, max, chance]], remove, shape: [radius, height]}
const INFO := {
	&"liana": {"title": "лиану", "verb": "сорвать", "drops": [[&"liana", 2, 2, 1.0], [&"fiber", 1, 2, 1.0]], "remove": true, "shape": [0.45, 2.6]},
	&"herb": {"title": "лечебные травы", "verb": "собрать", "drops": [[&"herb", 1, 2, 1.0]], "remove": true, "shape": [0.35, 0.7]},
	&"wild_taro": {"title": "дикий таро", "verb": "выкопать", "drops": [[&"taro", 2, 3, 1.0], [&"seed_taro", 1, 2, 1.0]], "remove": true, "shape": [0.5, 1.0]},
	&"wild_maize": {"title": "дикую кукурузу", "verb": "сорвать", "drops": [[&"maize", 1, 2, 1.0], [&"seed_maize", 2, 3, 1.0]], "remove": true, "shape": [0.4, 2.0]},
	&"wild_melon": {"title": "дикую дыню", "verb": "сорвать", "drops": [[&"melon", 1, 1, 1.0], [&"seed_melon", 2, 3, 1.0]], "remove": true, "shape": [0.5, 0.5]},
	&"berries": {"title": "ягоды", "verb": "собрать", "drops": [[&"berries", 3, 5, 1.0], [&"seed_berry", 1, 1, 0.3]], "remove": false, "shape": [0.65, 1.1]},
	&"cotton": {"title": "хлопок", "verb": "собрать", "drops": [[&"cotton", 2, 3, 1.0]], "remove": false, "shape": [0.5, 1.3]},
}

var kind: StringName = &"herb"
var vidx: int = 0
var is_harvested: bool = false
var _mi: MeshInstance3D

func setup(k: StringName, idx: int) -> ResourceNode:
	kind = k
	vidx = idx
	return self

func _ready() -> void:
	add_to_group(&"resources")
	add_to_group(StringName("res_" + String(kind)))
	monitoring = false
	monitorable = false
	_mi = MeshInstance3D.new()
	_mi.name = "Mesh"
	_mi.mesh = FloraLib.resource_mesh(kind, vidx, is_harvested)
	_mi.visibility_range_end = 95.0
	_mi.visibility_range_end_margin = 10.0
	_mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if kind in [&"liana", &"wild_maize", &"berries", &"cotton"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mi)
	var info: Dictionary = INFO.get(kind, INFO[&"herb"])
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = float(info["shape"][0])
	cap.height = maxf(float(info["shape"][1]), cap.radius * 2.0)
	cs.shape = cap
	cs.position = Vector3(0, cap.height * 0.5, 0)
	add_child(cs)

func can_harvest() -> bool:
	return not is_harvested

func get_interact_text(_player: Node) -> String:
	if is_harvested:
		return ""
	var info: Dictionary = INFO.get(kind, {})
	return "E — %s %s" % [info.get("verb", "собрать"), info.get("title", String(kind))]

func interact(player: Node) -> void:
	harvest(player)

func on_hit(by: Node, _hit: Dictionary) -> void:
	harvest(by)

## Собрать: выдаёт предметы `by` (через Flora.give), возвращает {item: count}.
func harvest(by: Node) -> Dictionary:
	if is_harvested:
		return {}
	is_harvested = true
	var info: Dictionary = INFO.get(kind, INFO[&"herb"])
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var got: Dictionary = {}
	for d in info["drops"]:
		if rng.randf() <= float(d[3]):
			var n := rng.randi_range(int(d[1]), int(d[2]))
			if n > 0:
				got[d[0]] = n
				Flora.give(by, d[0], n)
	Flora.play_sfx(self, "OBJBag_KnapsackLeatherClose_OS_01", global_position + Vector3.UP * 0.5, -6.0, 0.8)
	Flora.chips(get_parent(), global_position + Vector3.UP * 0.6, Color(0.35, 0.55, 0.22), 10)
	var removed := bool(info["remove"])
	harvested.emit(self, removed)
	if removed:
		for c in get_children():
			if c is CollisionShape3D:
				(c as CollisionShape3D).disabled = true
		var tw := create_tween()
		tw.tween_property(_mi, ^"scale", Vector3(0.05, 0.05, 0.05), 0.45).set_ease(Tween.EASE_IN)
		tw.tween_callback(queue_free)
	else:
		_mi.mesh = FloraLib.resource_mesh(kind, vidx, true)
	return got

## Состояние для стриминга (рекорд Flora хранит его, пока узел выгружен).
func is_pristine() -> bool:
	return not is_harvested
