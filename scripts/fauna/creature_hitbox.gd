class_name CreatureHitbox
extends StaticBody3D
## Хитбокс для существ и моделей без своего (морские особи — SeaCritter/UserSeaActor, витрины,
## существа каталога v5): попадание пули, остроги, стрелы, удара — урон, испуг, смерть с добычей.
## Ставится одной строкой: CreatureHitbox.attach(узел, {hp, solid, drops, size}).
##  • форма — коробка по габариту видимых мешей узла (в его осях) с запасом; или size;
##  • слой — Shark.HIT_LAYER (лучи пуль и остроги видят, игрок нет); solid = true — ещё и слой 1:
##    игрок не проходит сквозь крупное (кит, групер, ящики, лодка…);
##  • урон: hp; у цели вызываются, если есть: on_hurt(source, amount), startle(from), die();
##    иначе смерть по умолчанию — в воде всплывает брюхом вверх, на суше заваливается на бок,
##    через corpse_time исчезает; добыча drops выпадает предметами.
## Combat находит apply_damage у самого хитбокса (Combat._find_with идёт вверх от коллайдера).

const SOLID_MIN := 0.9          # крупнее этого (наибольшая сторона, м) — по умолчанию твёрдое
const CORPSE_TIME := 40.0

var target: Node3D
var hp := 20.0
var hp_max := 20.0
var solid := false
var drops: Array[Dictionary] = []
var dead := false
var shape: CollisionShape3D

## Повесить хитбокс на узел. opts: hp, solid (bool), drops [{id, n}], size (Vector3), pad (доля запаса),
## center (Vector3 локальный центр), name.
static func attach(t: Node3D, opts: Dictionary = {}) -> CreatureHitbox:
	if t == null:
		return null
	var old := t.get_node_or_null(^"CreatureHitbox") as CreatureHitbox
	if old:
		return old
	var hb := CreatureHitbox.new()
	hb.name = "CreatureHitbox"
	hb.target = t
	var ab := AABB()
	if opts.has("size"):
		var sz: Vector3 = opts["size"]
		ab = AABB(-sz * 0.5 + Vector3(opts.get("center", Vector3.ZERO)), sz)
	else:
		ab = local_bounds(t)
	var pad := float(opts.get("pad", 0.08))
	ab = ab.grow(maxf(ab.get_longest_axis_size() * pad, 0.02))
	var bs := BoxShape3D.new()
	bs.size = ab.size.max(Vector3.ONE * 0.04)
	hb.shape = CollisionShape3D.new()
	hb.shape.shape = bs
	hb.shape.position = ab.get_center()
	hb.add_child(hb.shape)
	var big: bool = ab.get_longest_axis_size() >= SOLID_MIN
	hb.solid = bool(opts.get("solid", big))
	hb.collision_layer = Shark.HIT_LAYER | (1 if hb.solid else 0)
	hb.collision_mask = 0
	hb.hp_max = float(opts.get("hp", clampf(ab.get_volume() * 60.0, 4.0, 400.0)))
	hb.hp = hb.hp_max
	var dl: Array = opts.get("drops", [])
	for e: Variant in dl:
		if e is Dictionary:
			hb.drops.append(e)
	hb.add_to_group(&"creature_hitbox")
	t.add_child(hb)
	return hb

## Габарит видимых мешей в осях узла (без хитбоксов и частиц).
static func local_bounds(t: Node3D) -> AABB:
	var inv := t.global_transform.affine_inverse() if t.is_inside_tree() else Transform3D.IDENTITY
	var out := AABB()
	var first := true
	for gi: Node in t.find_children("*", "GeometryInstance3D", true, false):
		var g := gi as GeometryInstance3D
		if g is GPUParticles3D or g is CPUParticles3D:
			continue
		var la := g.get_aabb()
		if la.size == Vector3.ZERO:
			continue
		var xf: Transform3D
		if t.is_inside_tree() and g.is_inside_tree():
			xf = inv * g.global_transform
		else:
			xf = _rel_xform(t, g)
		var box := xf * la
		if first:
			out = box
			first = false
		else:
			out = out.merge(box)
	if first:
		out = AABB(Vector3(-0.15, -0.15, -0.15), Vector3(0.3, 0.3, 0.3))
	return out

static func _rel_xform(root: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf

# ============================== урон ==============================

func apply_damage(amount: float, source: Node = null, _kind: StringName = &"") -> void:
	if dead:
		return
	hp -= amount
	if is_instance_valid(target):
		if target.has_method(&"on_hurt"):
			target.call(&"on_hurt", source, amount)
		if target.has_method(&"startle") and source is Node3D:
			target.call(&"startle", (source as Node3D).global_position)
		elif target.has_method(&"flee") and source is Node3D:
			target.call(&"flee", (source as Node3D).global_position)
	if hp <= 0.0:
		_die()

func is_dead() -> bool:
	return dead

func _die() -> void:
	dead = true
	collision_layer = 0
	if not is_instance_valid(target):
		return
	var pos := target.global_position
	if not drops.is_empty() and target.is_inside_tree():
		var host := target.get_parent()
		ItemPickup.spawn(host if host else target, pos + Vector3.UP * 0.2, drops)
	if target.has_method(&"die"):
		target.call(&"die")
		return
	target.set_process(false)
	target.set_physics_process(false)
	var ws := _water_y()
	var tw := target.create_tween()
	if ws > -1e5 and pos.y < ws - 0.2:
		# в воде — медленно всплывает брюхом вверх
		tw.set_parallel(true)
		tw.tween_property(target, ^"rotation:z", target.rotation.z + PI, 2.5).set_trans(Tween.TRANS_SINE)
		tw.tween_property(target, ^"global_position:y", ws - 0.15, maxf(4.0, (ws - pos.y) * 1.5))
		tw.set_parallel(false)
	else:
		tw.tween_property(target, ^"rotation:z", target.rotation.z + PI * 0.5, 0.6).set_trans(Tween.TRANS_BOUNCE)
	tw.tween_interval(CORPSE_TIME)
	tw.tween_callback(target.queue_free)

func _water_y() -> float:
	if target and target.has_method(&"water_y"):
		return float(target.call(&"water_y"))
	return BuildEnv.water_surface(target.global_position.x, target.global_position.z)
