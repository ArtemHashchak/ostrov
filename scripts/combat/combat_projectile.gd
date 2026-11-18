class_name CombatProjectile
extends Node3D
## Снаряд с баллистикой: гравитация, сопротивление воздуха, луч от прошлой позиции к новой
## (не проскакивает тонкие цели). Стрелы/болты/копьё втыкаются (можно подобрать — E),
## пули — облачко пыли/щепки/кровь, молотов — разбивается и поджигает область, в т.ч. на воде.

const LIFE := 14.0

var shooter: Node
var weapon_id: StringName
var ammo_id: StringName
var damage := 10.0
var kind: StringName = &"bullet"
var on_fire := false
var thrown := false
var spin := false
var velocity := Vector3.ZERO
var gravity_scale := 1.0
var max_range := 300.0

var _v0 := 1.0
var _t := 0.0
var _travel := 0.0
var _model: Node3D
var _in_water := false
var _exclude: Array[RID] = []
var _done := false

func _ready() -> void:
	top_level = true
	_v0 = maxf(velocity.length(), 0.1)
	_model = CombatModels.projectile(ammo_id)
	add_child(_model)
	if on_fire:
		var fm := _model.find_child("Flame", true, false) as Node3D
		var fl := CombatFx.flames(fm if fm else _model, 0.12)
		(fl.get_node(^"Light") as OmniLight3D).omni_range = 3.0
	if ammo_id == &"musket_ball":
		_model.visible = false # пуля не видна глазом
	var s := shooter as CollisionObject3D
	if s:
		_exclude.append(s.get_rid())
	if velocity.length() > 0.1:
		_orient()

func _drag() -> float:
	match ammo_id:
		&"musket_ball": return 0.35
		&"arrow", &"arrow_fire": return 0.03
		&"bolt": return 0.02
	return 0.01

func _orient() -> void:
	if spin:
		_model.rotate_object_local(Vector3.RIGHT, -0.25)
		return
	var v := velocity.normalized()
	if absf(v.dot(Vector3.UP)) > 0.999:
		return
	look_at(global_position + v, Vector3.UP)

func _physics_process(delta: float) -> void:
	if _done:
		return
	_t += delta
	if _t > LIFE or _travel > max_range:
		queue_free()
		return
	var from := global_position
	velocity += Vector3.DOWN * 9.8 * gravity_scale * delta
	velocity *= 1.0 - _drag() * delta
	var to := from + velocity * delta
	_travel += from.distance_to(to)
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = _exclude
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		global_position = hit.position
		_impact(hit)
		return
	# вода
	var ws := BuildEnv.water_surface(to.x, to.z)
	if not _in_water and to.y < ws and from.y >= ws - 0.05:
		_in_water = true
		var wp := Vector3(to.x, ws, to.z)
		CombatFx.impact(self, wp, Vector3.UP, &"water")
		if ammo_id == &"molotov":
			global_position = wp
			_shatter(wp, null)
			return
		velocity *= 0.12
		gravity_scale = 0.08
		_t = maxf(_t, LIFE - 3.0)
	global_position = to
	_orient()

func _impact(hit: Dictionary) -> void:
	_done = true
	var col := hit.collider as Node
	var pos: Vector3 = hit.position
	var nrm: Vector3 = hit.normal
	var speed_k := clampf(velocity.length() / _v0, 0.45, 1.0)
	if ammo_id == &"molotov":
		CombatFx.sound_at(self, "glass_break", pos, 0.0)
		Combat.deliver(shooter, col, pos, nrm, damage, &"melee", weapon_id)
		_shatter(pos, col)
		return
	var dealt := Combat.deliver(shooter, col, pos, nrm, damage * speed_k, kind, weapon_id, false, on_fire)
	var target := Combat._find_with(col, &"apply_damage")
	var surface: StringName = &"ground"
	if target and not target.is_in_group(&"buildable"):
		surface = &"flesh"
	elif (target and target.is_in_group(&"buildable")) or _is_wood(col):
		surface = &"wood"
	CombatFx.impact(self, pos, nrm, surface)
	if on_fire and surface != &"flesh":
		# огненная стрела: маленький очаг (поджигает дерево построек)
		Combat.ignite_area(pos, 0.9, shooter, 4.0)
	match ammo_id:
		&"arrow", &"arrow_fire", &"bolt", &"spear":
			_stick(col, pos, surface == &"flesh")
		&"musket_ball":
			queue_free()
		_:
			if thrown and ammo_id != &"":
				var parent := get_parent()
				ItemPickup.spawn(parent, pos + nrm * 0.15, [{"id": ammo_id, "n": 1}])
			queue_free()
	if dealt <= 0.0 and surface == &"ground" and ammo_id == &"musket_ball":
		pass

func _is_wood(col: Node) -> bool:
	var cur := col
	for i in 4:
		if cur == null:
			return false
		if cur.is_in_group(&"trees") or cur.is_in_group(&"choppable") or cur.is_in_group(&"buildable"):
			return true
		cur = cur.get_parent()
	return false

## Воткнуться: модель остаётся в цели, можно подобрать (кроме попаданий в живых).
func _stick(col: Node, pos: Vector3, flesh: bool) -> void:
	var host := col as Node3D
	var xf := global_transform
	# чуть глубже по направлению полёта
	xf.origin = pos + velocity.normalized() * (0.12 if ammo_id != &"spear" else 0.25)
	remove_child(_model)
	var stuck := CombatStuck.new()
	stuck.item_id = ammo_id if ammo_id != &"arrow_fire" else &""
	stuck.lifetime = 8.0 if flesh else 60.0
	stuck.pickable = not flesh and stuck.item_id != &""
	if host == null or not host.is_inside_tree():
		host = get_parent() as Node3D
	host.add_child(stuck)
	stuck.global_transform = xf
	stuck.add_child(_model)
	_model.transform = Transform3D.IDENTITY
	queue_free()

func _shatter(pos: Vector3, col: Node) -> void:
	_done = true
	var w := Combat.weapon(&"molotov")
	var host: Node = null
	var bp := Combat._find_with(col, &"ignite") if col else null
	if bp and bp.is_in_group(&"buildable"):
		host = bp
	if host == null and col == null:
		# на воде — горящая плёнка спирта плывёт по волнам: ищем ближайший плот
		pass
	# брызги горящей жидкости
	CombatFx.particles(get_parent(), pos, 24, 0.7, "flame", true,
		CombatFx._ramp([Color(1, 0.9, 0.5, 1), Color(1, 0.5, 0.1, 0.8), Color(0.5, 0.15, 0.02, 0)]), 0.35, 5.0, 70.0, Vector3.UP, Vector3(0, -6, 0))
	CombatFx.sound_at(self, "fire_whoosh", pos, 0.0)
	Combat.ignite_area(pos + Vector3.UP * 0.05, float(w.radius), shooter, float(w.burn_sec), host)
	queue_free()


## Воткнувшаяся стрела/болт/копьё: E — подобрать.
class CombatStuck:
	extends Area3D
	var item_id: StringName
	var lifetime := 60.0
	var pickable := true
	var _t := 0.0

	func _ready() -> void:
		collision_layer = 1
		collision_mask = 0
		monitoring = false
		if not pickable:
			collision_layer = 0
			return
		var cs := CollisionShape3D.new()
		var sh := CapsuleShape3D.new()
		sh.radius = 0.06
		sh.height = 0.5
		cs.shape = sh
		cs.rotation = Vector3(PI / 2, 0, 0)
		cs.position = Vector3(0, 0, 0.25)
		add_child(cs)

	func _process(delta: float) -> void:
		_t += delta
		if _t > lifetime:
			queue_free()

	func interact(by: Node) -> void:
		var inv: Variant = by.get(&"inventory")
		if inv is Object and (inv as Object).has_method(&"add"):
			(inv as Object).call(&"add", item_id, 1)
		queue_free()

	func get_interact_text(_by: Node) -> String:
		return "E — подобрать: %s" % Items.item_name(item_id)
