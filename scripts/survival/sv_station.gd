class_name SvStation
extends StaticBody3D
## Базовая постройка/объект SURVIVAL: коллайдер, E-взаимодействие, удары, тик.
## Наследники: SvFire, SvSmoker, SvWater, SvGarden, SvWild, SvDebris.
## Survival зовёт tick(dt) у всех узлов группы `sv_station` (dt уже умножен на Survival.speed).

var kind: StringName = &""
var hp: float = 60.0
var max_hp: float = 60.0
## Что вернуть при разборе (удары/поломка): {item: n}
var salvage: Dictionary = {}
var _hits_shake := 0.0
var model: Node3D

func _init() -> void:
	add_to_group(&"sv_station")
	add_to_group(&"buildable") # BUILD/BOTS видят как постройку (ломается, горит)
	collision_layer = 1
	collision_mask = 0

## Коллайдер-цилиндр/коробка.
func add_shape(size: Vector3, offset: Vector3 = Vector3.ZERO, cylinder: bool = false) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	if cylinder:
		var c := CylinderShape3D.new()
		c.radius = size.x * 0.5
		c.height = size.y
		cs.shape = c
	else:
		var b := BoxShape3D.new()
		b.size = size
		cs.shape = b
	cs.position = offset + Vector3(0, size.y * 0.5, 0)
	add_child(cs)
	return cs

func tick(_dt: float) -> void:
	pass

func get_interact_text(_ch: Node) -> String:
	return ""

func interact(_ch: Node) -> void:
	pass

## Удар (Player/BOTS): ломается от урона; инструмент «hand» почти не вредит.
func on_hit(by: Node, hit: Dictionary) -> void:
	var tool := StringName(hit.get("tool", &"hand"))
	var dmg := float(hit.get("damage", 4.0))
	if tool == &"hand":
		dmg *= 0.25
	apply_damage(dmg, by, &"melee")

func apply_damage(amount: float, source: Node = null, _kind: StringName = &"melee") -> void:
	if hp <= 0.0:
		return
	hp -= amount
	_shake()
	if hp <= 0.0:
		break_apart(source)

func _shake() -> void:
	if model == null:
		return
	var tw := create_tween()
	tw.tween_property(model, ^"rotation:z", 0.05, 0.05)
	tw.tween_property(model, ^"rotation:z", 0.0, 0.12)

## Разрушение: выдать salvage тому, кто сломал (или выронить), удалить узел.
func break_apart(by: Node) -> void:
	for id in salvage.keys():
		Survival.give(by, StringName(id), int(salvage[id]), global_position + Vector3.UP * 0.5)
	Survival.sfx(global_position, "res://assets/sounds/sfx-kit/foley-wood-touch.wav")
	on_broken(by)
	queue_free()

func on_broken(_by: Node) -> void:
	pass

# ---------- удобства для наследников ----------

static func held(ch: Node) -> StringName:
	return Survival.held(ch)

static func inv_count(ch: Node, id: StringName) -> int:
	return Survival.count(ch, id)

func toast(ch: Node, text: String) -> void:
	Survival.toast(ch, text)

static func iname(id: StringName) -> String:
	return Items.item_name(id)
