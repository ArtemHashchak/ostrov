class_name ResourceRock
extends StaticBody3D
## Валун — источник камня. Удары (камнем/топором/рукой) откалывают камни;
## выработанный валун превращается в щебень навсегда (мир не восстанавливается).
## ore = &"iron_ore" | &"sulfur" — рудная жила (редко, в скалах): каждая единица даёт руду
## (+ иногда камень), видны прожилки ржаво-бурого железа / жёлтой серы.

signal exhausted(rock: ResourceRock)

const TOOL_DAMAGE := {&"rock": 12.0, &"pickaxe": 25.0, &"axe": 7.0, &"axe_modern": 9.0, &"axe_crude": 7.0, &"hand": 2.0, &"spear": 3.0, &"stick": 1.0}
const PER_UNIT := 20.0

var units: int = 6
var acc: float = 0.0
var depleted: bool = false
var scene_path: String = "res://assets/models/polyhaven/boulder_01.glb"
var size: float = 1.3
var ore: StringName = &""
var units0: int = -1
var _visual: Node3D

func _ready() -> void:
	add_to_group(&"rocks")
	if units0 < 0:
		units0 = units
	if ore != &"":
		add_to_group(&"ore")
	if ResourceLoader.exists(scene_path):
		_visual = (load(scene_path) as PackedScene).instantiate() as Node3D
	else:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 0.8
		mi.mesh = sm
		_visual = mi
	add_child(_visual)
	var aabb := _aabb_of(_visual)
	_near_shadows_only(_visual)
	var k := size / maxf(0.01, aabb.get_longest_axis_size())
	_visual.scale = Vector3.ONE * k
	_visual.position = Vector3(-aabb.get_center().x * k, -aabb.position.y * k - 0.12, -aabb.get_center().z * k)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = aabb.size * k * 0.85
	cs.shape = bs
	cs.position = Vector3(0, aabb.size.y * k * 0.42, 0)
	add_child(cs)
	if ore != &"":
		_add_veins(AABB(Vector3(-aabb.size.x * k * 0.5, -0.12, -aabb.size.z * k * 0.5), aabb.size * k))

## Прожилки руды: сплюснутые наросты по поверхности (эллипсоид ≈ габарит валуна).
func _add_veins(box: AABB) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(position.x * 13.0 + position.z * 7.0)
	var iron := ore == &"iron_ore"
	var mat := FloraLib.plain_material("ore_" + String(ore), Color(0.50, 0.24, 0.12) if iron else Color(0.93, 0.80, 0.16), 0.55 if iron else 0.85)
	if iron:
		mat.metallic = 0.35
	else:
		mat.emission_enabled = true
		mat.emission = Color(0.25, 0.2, 0.0)
	var parts: Array = []
	var c := box.get_center()
	var ext := box.size * 0.5
	# прожилки: цепочки мелких плоских наростов вдоль «трещин» по поверхности
	for vein in rng.randi_range(4, 6):
		var d0 := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.2, 0.9), rng.randf_range(-1, 1)).normalized()
		var dd := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 0.6), rng.randf_range(-1, 1)).normalized() * 0.16
		for k in rng.randi_range(5, 8):
			var d := (d0 + dd * float(k)).normalized()
			var p := c + d * ext * 0.93
			var b := Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT).scaled(Vector3(rng.randf_range(0.07, 0.14), rng.randf_range(0.04, 0.09), 0.035) * size)
			parts.append([FloraLib._sphere(0.5, 1.0, 6), Transform3D(b, p), mat])
	var st := SurfaceTool.new()
	for pr in parts:
		st.append_from(pr[0], 0, pr[1])
	var mi := MeshInstance3D.new()
	mi.name = "Veins"
	mi.mesh = st.commit()
	mi.mesh.surface_set_material(0, mat)
	mi.visibility_range_end = 120.0
	mi.visibility_range_end_margin = 10.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(mi)

## Тень валуна — только вблизи: сам меш в карту теней не идёт, а теневой двойник
## (тот же меш, SHADOWS_ONLY) виден до SHADOW_NEAR м. Валунов в стриме сотни
## (вокруг игрока и ботов), и каждый рисовался во все каскады теней:
## было ≈260 вызовов отрисовки со спавна.
const SHADOW_NEAR := 45.0

static func _near_shadows_only(root: Node) -> void:
	var stack: Array[Node] = [root]
	var found: Array[MeshInstance3D] = []
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is MeshInstance3D and (c as MeshInstance3D).mesh:
			found.append(c)
		for ch in c.get_children():
			stack.append(ch)
	for mi in found:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var tw := MeshInstance3D.new()
		tw.name = "ShadowNear"
		tw.mesh = mi.mesh
		for s in mi.get_surface_override_material_count():
			tw.set_surface_override_material(s, mi.get_surface_override_material(s))
		tw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		tw.visibility_range_end = SHADOW_NEAR
		tw.visibility_range_end_margin = 4.0
		tw.set_meta(&"no_auto_lod", true)
		mi.add_child(tw)

static func _aabb_of(n: Node) -> AABB:
	var res := AABB()
	var first := true
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is MeshInstance3D and (c as MeshInstance3D).mesh:
			var a := (c as MeshInstance3D).mesh.get_aabb()
			a = ((c as Node3D).transform * a) if c != n else a
			res = a if first else res.merge(a)
			first = false
		for ch in c.get_children():
			stack.append(ch)
	return res if not first else AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)

func on_hit(by: Node, hit: Dictionary) -> void:
	var pos: Vector3 = hit.get("position", global_position + Vector3.UP * 0.5)
	var tool := Flora.tool_of(by, hit)
	Flora.chips(get_parent(), pos, Color(0.55, 0.55, 0.52), 8)
	Flora.play_sfx(self, "FGHTImpt_Kick_OS_01" if tool == &"hand" else "METLImpt_MetalHitSurface_OS_01", pos, -6.0, 0.55 if tool != &"hand" else 0.8)
	if depleted:
		return
	acc += float(TOOL_DAMAGE.get(tool, 2.0))
	while acc >= PER_UNIT and units > 0:
		acc -= PER_UNIT
		units -= 1
		if ore != &"":
			Flora.give(by, ore, 1)
			if randf() < 0.4:
				Flora.give(by, &"rock", 1)
		else:
			Flora.give(by, &"rock", 1)
	if units <= 0:
		_deplete()

func _deplete() -> void:
	depleted = true
	remove_from_group(&"rocks")
	remove_from_group(&"ore")
	add_to_group(&"rubble")
	exhausted.emit(self)
	var tw := create_tween()
	tw.tween_property(_visual, ^"scale", _visual.scale * 0.38, 0.6)
	tw.parallel().tween_property(_visual, ^"position:y", _visual.position.y - 0.25, 0.6)
	for c in get_children():
		if c is CollisionShape3D:
			((c as CollisionShape3D).shape as BoxShape3D).size *= 0.4

func get_interact_text(_player: Node) -> String:
	return ""

func is_pristine() -> bool:
	return not depleted and units == units0 and acc == 0.0
