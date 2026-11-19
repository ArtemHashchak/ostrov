class_name ChoppableTree
extends StaticBody3D
## Дерево, которое можно срубить (как в The Forest):
## удары оставляют зарубку на высоте первого удара; когда здоровье кончается —
## ствол выше зарубки падает (RigidBody), пень остаётся НАВСЕГДА.
## Пальма роняет кокосы при ударах и по E («потрясти»).

signal fell_down(tree: ChoppableTree)

## Запас прочности по видам: баньян — огромный, мангр — тонкий, но вязкий.
const HEALTH := {&"palm": 90.0, &"broadleaf": 130.0, &"mangrove": 110.0, &"banyan": 320.0}

const TOOL_DAMAGE := {&"axe": 22.0, &"axe_modern": 34.0, &"axe_crude": 22.0, &"rock": 7.0, &"hand": 2.5, &"spear": 5.0, &"sword": 9.0, &"stick": 3.0}

## Урон по дереву: по типу инструмента; у топоров масштаб от силы самого топора (каменный 14 → x1).
static func tree_damage(tool: StringName, hit: Dictionary) -> float:
	var base: float = TOOL_DAMAGE.get(tool, 2.0)
	if tool == &"axe" and hit.has("damage"):
		base *= clampf(float(hit["damage"]) / 14.0, 0.7, 2.0)
	return base

var variant: Dictionary = {}
var kind: StringName = &"palm"
var max_health: float = 100.0
var health: float = 100.0
var cut_h: float = -1.0
var felled: bool = false
var coconuts: int = 0
var notch_side: Vector3 = Vector3.FORWARD
var coconuts0: int = 0

var _trunk: MeshInstance3D
var _crown: MeshInstance3D
var _coconut_nodes: Array[MeshInstance3D] = []
var _notch: MeshInstance3D
var _shape: CollisionShape3D
var _last_hitter: Node = null
var _shake_t: float = 0.0

func setup(v: Dictionary) -> void:
	variant = v
	kind = v["kind"]
	max_health = float(HEALTH.get(kind, 130.0))
	health = max_health
	coconuts = int(v.get("coconuts", 0))
	coconuts0 = coconuts

## Дерево, разбуженное вдали от игрока (рядом с ботом): тень рисует лёгкий меш
## (FloraLib.shadow_tree_mesh), сам детальный меш в карту теней не идёт.
var shadow_proxy := false
var _shadow_mi: MeshInstance3D

func _set_shadow_proxy(on: bool) -> void:
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if on else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for mi: MeshInstance3D in [_trunk, _crown]:
		if mi:
			mi.cast_shadow = mode
	if _crown and not felled:
		# вдали от игрока — облегчённая крона (у пальмы та же)
		_crown.mesh = FloraLib.crown_mesh(variant, 1 if on else 0)
	if on and _shadow_mi == null:
		_shadow_mi = MeshInstance3D.new()
		_shadow_mi.name = "ShadowProxy"
		_shadow_mi.mesh = FloraLib.shadow_tree_mesh(variant)
		_shadow_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		_shadow_mi.visibility_range_end = Flora.LOD_DIST
		_shadow_mi.set_meta(&"no_auto_lod", true)
		add_child(_shadow_mi)
	elif not on and _shadow_mi != null:
		_shadow_mi.queue_free()
		_shadow_mi = null

## Игрок подошёл к дереву, разбуженному ботом, — вернуть полную детализацию.
func set_full_detail() -> void:
	if shadow_proxy:
		shadow_proxy = false
		_set_shadow_proxy(false)

func _ready() -> void:
	add_to_group(&"choppable")
	add_to_group(&"trees")
	set_process(false) # _process нужен только во время тряски кроны (_shake включает)
	_trunk = MeshInstance3D.new()
	_trunk.name = "Trunk"
	_trunk.mesh = _trunk_full_mesh()
	_trunk.visibility_range_end = Flora.TREE_VIS_RANGE
	add_child(_trunk)
	_crown = MeshInstance3D.new()
	_crown.name = "Crown"
	_crown.mesh = FloraLib.crown_mesh(variant)
	_crown.visibility_range_end = Flora.TREE_VIS_RANGE
	add_child(_crown)
	var rm := FloraLib.roots_mesh(variant)
	if rm.get_surface_count() > 0:
		var roots := MeshInstance3D.new()
		roots.name = "Roots" # корни остаются и после рубки
		roots.mesh = rm
		roots.visibility_range_end = Flora.TREE_VIS_RANGE
		add_child(roots)
	if shadow_proxy:
		_set_shadow_proxy(true)
	if kind == &"palm":
		var top := FloraLib.trunk_point(variant, variant["H"])
		var rng := RandomNumberGenerator.new()
		rng.seed = int(variant["seed"]) + get_instance_id()
		for i in coconuts:
			var c := MeshInstance3D.new()
			c.mesh = FloraLib.coconut_mesh()
			var a := TAU * float(i) / float(maxi(coconuts, 1)) + rng.randf_range(-0.3, 0.3)
			c.position = top + Vector3(cos(a) * 0.22, -0.32 - rng.randf() * 0.18, sin(a) * 0.22)
			c.visibility_range_end = 80.0
			add_child(c)
			_coconut_nodes.append(c)
	_shape = CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	var hh := minf(4.0, (variant["H"] as float) * 0.5)
	cyl.radius = FloraLib.trunk_radius(variant, 0.6) * 1.05
	cyl.height = hh
	_shape.shape = cyl
	_shape.position = Vector3(FloraLib.trunk_point(variant, hh * 0.5).x * 0.5, hh * 0.5, 0)
	add_child(_shape)

func _trunk_full_mesh() -> Mesh:
	var key := "trunkfull_%s_%d" % [variant["kind"], variant["idx"]]
	if FloraLib._mesh_cache.has(key):
		return FloraLib._mesh_cache[key]
	var m := FloraLib.trunk_mesh(variant, 0.0, (variant["H"] as float) * (1.0 if kind == &"palm" else 1.02), 0, 12)
	FloraLib._mesh_cache[key] = m
	return m

func _process(delta: float) -> void:
	var __pt := PerfStats.begin()
	_perf_process(delta)
	PerfStats.end(&"flora_trees", __pt)

func _perf_process(delta: float) -> void:
	if _shake_t > 0.0:
		_shake_t -= delta
		var s := sin(_shake_t * 40.0) * 0.012 * _shake_t
		_crown.rotation = Vector3(s, 0, s * 0.7)
		if _shake_t <= 0.0:
			_crown.rotation = Vector3.ZERO
			set_process(false)

# --------------------------------------------------------------- взаимодействие

func get_interact_text(_player: Node) -> String:
	if felled:
		return ""
	if kind == &"palm" and coconuts > 0:
		return "E — потрясти пальму"
	return ""

func interact(player: Node) -> void:
	if felled or kind != &"palm":
		return
	_shake(0.8)
	Flora.play_sfx(self, "WOODFric_CreaksCreepy_OS_02", global_position + Vector3.UP * 3.0, -8.0, 1.3)
	if coconuts > 0 and randf() < 0.55:
		_drop_coconut(player)

func on_hit(by: Node, hit: Dictionary) -> void:
	if felled:
		return
	_last_hitter = by
	var tool := Flora.tool_of(by, hit)
	var dmg: float = tree_damage(tool, hit)
	var pos: Vector3 = hit.get("position", global_position + Vector3.UP)
	var local := to_local(pos)
	if cut_h < 0.0:
		cut_h = clampf(local.y * 0.55, 0.3, 0.75)
		var hv := Vector3(local.x, 0, local.z)
		if by is Node3D:
			var d := to_local((by as Node3D).global_position)
			hv = Vector3(d.x, 0, d.z)
		notch_side = hv.normalized() if hv.length() > 0.01 else Vector3.FORWARD
	health -= dmg
	_shake(0.25)
	_update_notch()
	Flora.chips(get_parent(), pos, Color(0.78, 0.62, 0.40) if tool != &"hand" else Color(0.4, 0.32, 0.2), 10)
	if tool == &"hand":
		Flora.play_sfx(self, "FGHTImpt_PunchRegular_OS_01", pos, -4.0, 1.0)
	else:
		Flora.play_sfx(self, "WEAPAxe_WoodCutAxe_OS_01", pos, 0.0, randf_range(0.9, 1.1))
	if kind == &"palm" and coconuts > 0 and randf() < 0.3:
		_drop_coconut(by)
	if health <= 0.0:
		fell(by)

func _shake(t: float) -> void:
	_shake_t = t
	set_process(true)

func _update_notch() -> void:
	var k := clampf(1.0 - health / max_health, 0.0, 1.0)
	var depth := 0.12 + 0.6 * k
	# та же верхняя граница, что у целого ствола — макушка не «прыгает» при первом ударе
	_trunk.mesh = FloraLib.trunk_mesh(variant, 0.0, (variant["H"] as float) * (1.0 if kind == &"palm" else 1.02), 0, 12, Vector3.ZERO, {"h": cut_h, "dir": notch_side, "depth": depth})

func _drop_coconut(by: Node) -> void:
	if coconuts <= 0:
		return
	coconuts -= 1
	var node: MeshInstance3D = _coconut_nodes.pop_back() if not _coconut_nodes.is_empty() else null
	var from := global_transform * (node.position if node else FloraLib.trunk_point(variant, variant["H"]))
	if node:
		node.queue_free()
	var p := FloraPickup.make_coconut()
	get_parent().add_child(p)
	p.global_position = from
	p.freeze = false
	var push := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 0.8
	if by is Node3D:
		push += ((by as Node3D).global_position - global_position).normalized() * 0.6
	p.linear_velocity = push

# --------------------------------------------------------------- падение

func fell(by: Node) -> void:
	if felled:
		return
	felled = true
	remove_from_group(&"choppable")
	var H: float = variant["H"]
	# направление падения — от рубящего
	var away := global_basis * -notch_side
	if by is Node3D:
		var d := global_position - (by as Node3D).global_position
		d.y = 0.0
		if d.length() > 0.05:
			away = d.normalized()
	# пень
	_trunk.mesh = FloraLib.trunk_mesh(variant, 0.0, cut_h, 2, 12)
	_trunk.visibility_range_end = 160.0
	_crown.visible = false
	_set_shadow_proxy(false)
	for c in _coconut_nodes:
		c.queue_free()
	var left_coconuts := coconuts
	_coconut_nodes.clear()
	coconuts = 0
	if _notch:
		_notch.queue_free()
		_notch = null
	var cyl := _shape.shape as CylinderShape3D
	cyl.height = cut_h
	_shape.position = Vector3(0, cut_h * 0.5, 0)
	add_to_group(&"stumps")
	# падающий ствол
	var trunk := FallenTrunk.new()
	trunk.setup(variant, cut_h, transform, left_coconuts)
	get_parent().add_child(trunk)
	trunk.add_collision_exception_with(self)
	if by is PhysicsBody3D:
		trunk.add_collision_exception_with(by)
	trunk.start_fall(away)
	Flora.play_sfx(self, "WOODFric_CreaksCreepy_OS_01", global_position + Vector3.UP * cut_h, 2.0, 0.9)
	Events.toast.emit("Дерево падает!")
	fell_down.emit(self)

## Нетронутое дерево (можно вернуть в MultiMesh при удалении игроков).
func is_pristine() -> bool:
	return not felled and health >= max_health and coconuts == coconuts0

func is_stump() -> bool:
	return felled
