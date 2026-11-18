class_name SeaTrap
extends Node3D
## Верша на дне: плетёная корзина-конус с поплавком на верёвке. Пока в округе есть
## рыба (Sea.take_fish), раз в CATCH_SEC ловит одну, держит до MAX_HELD.
## E — достать улов; пустую — забрать обратно. Группа `fish_traps`.

const CATCH_SEC := 75.0
const MAX_HELD := 5

var sea: Node = null
var owner_node: Node = null
var held: int = 0
var _t: float = 0.0
var _rng := RandomNumberGenerator.new()
var _buoy: MeshInstance3D
var _line: MeshInstance3D
var _fish_vis: Array[MeshInstance3D] = []
var _bob: float = 0.0

## Ускорение для тестов.
static var speed: float = 1.0

func _ready() -> void:
	add_to_group(&"fish_traps")
	add_to_group(&"interactable")
	_rng.randomize()
	_t = _rng.randf() * CATCH_SEC * 0.3
	_bob = _rng.randf() * TAU
	var wood := SeaMeshes.mat_vc(0.85)
	var basket := MeshInstance3D.new()
	basket.mesh = SeaMeshes.trap_basket()
	basket.material_override = wood
	basket.rotation.z = PI * 0.5
	basket.position.y = 0.26
	add_child(basket)
	for i in 3:
		var f := MeshInstance3D.new()
		f.mesh = FishSchool.make_fish_mesh(0.26)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.7, 0.74, 0.78)
		m.metallic = 0.3
		m.roughness = 0.4
		f.material_override = m
		f.position = Vector3(-0.15 + i * 0.16, 0.3 + (i % 2) * 0.08, (i - 1) * 0.08)
		f.rotation.y = PI * 0.5 + i * 0.4
		f.visible = false
		add_child(f)
		_fish_vis.append(f)
	_buoy = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.13
	sm.height = 0.22
	_buoy.mesh = sm
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.86, 0.36, 0.14)
	bm.roughness = 0.6
	_buoy.material_override = bm
	_buoy.top_level = true
	add_child(_buoy)
	_line = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.008
	cm.bottom_radius = 0.008
	cm.height = 1.0
	cm.radial_segments = 4
	_line.mesh = cm
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(0.55, 0.47, 0.32)
	_line.material_override = lm
	_line.top_level = true
	add_child(_line)
	# зона взаимодействия: и корзина, и поплавок (игрок может достать с плота)
	var area := Area3D.new()
	area.collision_layer = 1
	area.collision_mask = 0
	area.monitoring = false
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.0, 0.8, 1.0)
	cs.shape = bs
	cs.position.y = 0.35
	area.add_child(cs)
	var cs2 := CollisionShape3D.new()
	var ss := SphereShape3D.new()
	ss.radius = 0.45
	cs2.shape = ss
	cs2.name = "BuoyShape"
	area.add_child(cs2)
	add_child(area)
	_update_vis()

func _wy() -> float:
	return float(sea.call(&"water_y")) if sea else 0.0

func _physics_process(delta: float) -> void:
	_t += delta * speed
	if _t >= CATCH_SEC:
		_t = 0.0
		if held < MAX_HELD and sea and int(sea.call(&"take_fish", global_position, 1)) > 0:
			held += 1
			_update_vis()
	_bob += delta * 1.3
	var wy := _wy()
	var bp := Vector3(global_position.x + 0.3, wy + 0.02 + sin(_bob) * 0.04, global_position.z + 0.2)
	_buoy.global_position = bp
	var a := global_position + Vector3(0, 0.6, 0)
	var mid := (a + bp) * 0.5
	var ln := a.distance_to(bp)
	_line.global_transform = Transform3D(Basis(), mid)
	if ln > 0.05:
		var up := (bp - a) / ln
		var x := up.cross(Vector3.FORWARD)
		if x.length() < 0.01:
			x = Vector3.RIGHT
		x = x.normalized()
		_line.global_transform = Transform3D(Basis(x, up * ln, x.cross(up)), mid)
	var area := get_child(get_child_count() - 1) as Area3D
	if area:
		var bs := area.get_node_or_null(^"BuoyShape") as Node3D
		if bs:
			bs.global_position = bp

func _update_vis() -> void:
	for i in _fish_vis.size():
		_fish_vis[i].visible = i < held

func get_interact_text(_by: Node) -> String:
	if held > 0:
		return "E — достать рыбу из верши (%d)" % held
	return "E — забрать вершу (пусто)"

func interact(by: Node) -> void:
	var inv := by.get_node_or_null(^"Inventory")
	if inv == null:
		return
	if held > 0:
		var left: int = inv.call(&"add", &"fish_raw", held)
		var got := held - left
		held = left
		_update_vis()
		if got > 0:
			Events.toast.emit("Улов: %d рыб" % got)
		return
	if int(inv.call(&"add", &"fish_trap", 1)) == 0:
		if sea and "traps" in sea:
			(sea.get(&"traps") as Array).erase(self)
		queue_free()

## Для ботов: забрать улов напрямую.
func collect(by: Node) -> int:
	var n := held
	interact(by)
	return n - held
