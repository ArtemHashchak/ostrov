class_name FallenTrunk
extends RigidBody3D
## Падающий / лежащий ствол. Логически состоит из участков по ~2 м (будущие брёвна: коллизии,
## `segments`) и кроны, но ВИДИМЫЙ ствол — цельный меш на каждый непрерывный кусок: без швов и
## торцов посередине. Удары по стволу сначала делают надпил на границе участка, затем отделяют
## бревно (FloraLog); оставшиеся куски перестраиваются, на распиле — торец с годичными кольцами.
## Удары по кроне дают листья и палки.

const LOG_CUT_DMG := 55.0
const SETTLE_SPEED := 0.15

var variant: Dictionary = {}
var cut_h: float = 1.0
var segments: Array[Dictionary] = [] # {mesh, shape, h0, h1}; mesh — общий меш непрерывного куска
var crown: MeshInstance3D = null
var crown_shape: CollisionShape3D = null
var crown_hp: float = 60.0
var coconuts_left: int = 0
var chop_acc: float = 0.0
var landed: bool = false
var settled: bool = false
var _t: float = 0.0
var _pieces: Array[MeshInstance3D] = []
var _notch: Dictionary = {} # надпил под текущий распил: {h, dir, depth}
var _butt_ext: Dictionary = {} # удлинённая капсула комля {height, center} — до наклона ствола

func setup(v: Dictionary, cut: float, xform: Transform3D, coconuts: int = 0) -> void:
	variant = v
	cut_h = cut
	transform = xform
	coconuts_left = coconuts

func _ready() -> void:
	add_to_group(&"fallen_trunks")
	add_to_group(&"choppable")
	var H: float = variant["H"]
	var h := cut_h + 0.02
	var total_mass := 0.0
	while h < H - 0.3:
		var h1 := minf(h + FloraLib.LOG_LEN, H)
		if H - h1 < 0.8:
			h1 = H
		_add_segment(h, h1)
		total_mass += 70.0 * (h1 - h)
		h = h1
	crown = MeshInstance3D.new()
	crown.name = "Crown"
	crown.mesh = FloraLib.crown_mesh(variant)
	add_child(crown)
	crown_shape = CollisionShape3D.new()
	var sph := SphereShape3D.new()
	var cc := FloraLib.crown_center(variant)
	if variant["kind"] == &"palm":
		sph.radius = 0.9
		crown_hp = 30.0
	else:
		sph.radius = (variant["crown_r"] as float) * 0.3
		crown_hp = 60.0
	crown_shape.shape = sph
	crown_shape.position = cc
	crown_shape.disabled = true # включается, когда ствол наклонился (иначе цепляет соседей)
	add_child(crown_shape)
	_rebuild_mesh()
	mass = maxf(80.0, total_mass)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = FloraLib.trunk_point(variant, lerpf(cut_h, H, 0.42))
	angular_damp = 0.6
	linear_damp = 0.2
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.05
	physics_material_override = pm

func _add_segment(h0: float, h1: float) -> void:
	var cs := CollisionShape3D.new()
	var a := FloraLib.trunk_point(variant, h0)
	var b := FloraLib.trunk_point(variant, h1)
	# радиус — по середине участка, пока ствол стоит; когда лёг — по толстому торцу
	# (_extend_butt: комель с расширением у корня толще середины и иначе тонет в земле)
	var r := FloraLib.trunk_radius(variant, (h0 + h1) * 0.5)
	var r_thick := maxf(FloraLib.trunk_radius(variant, h0), FloraLib.trunk_radius(variant, h1))
	var cap := CapsuleShape3D.new()
	cap.radius = r
	cap.height = maxf(a.distance_to(b) + r * 0.5, r * 2.1)
	var y := (b - a).normalized()
	var center := (a + b) * 0.5
	if segments.is_empty() and a.distance_to(b) > r:
		# комель: цилиндрическая часть капсулы — от самого среза (иначе скруглённый конец
		# капсулы оставляет край комля без опоры, и он уходит в землю); полусфера за срезом
		# не ниже образующей — ствол не приподнимает. Включается, когда ствол уже наклонился
		# (_extend_butt): у стоящего полусфера под срезом цепляет землю и валит его не туда.
		var cyl := a.distance_to(b) - r_thick * 0.75
		_butt_ext = {"height": cyl + r_thick * 2.0, "center": a + y * cyl * 0.5}
	cs.shape = cap
	var x := y.cross(Vector3.FORWARD).normalized()
	if x.length() < 0.5:
		x = Vector3.RIGHT
	var z := x.cross(y).normalized()
	cs.transform = Transform3D(Basis(x, y, z), center)
	add_child(cs)
	segments.append({"mesh": null, "shape": cs, "h0": h0, "h1": h1, "r_thick": r_thick})

## Непрерывные куски ствола: [[i0, i1], ...] — индексы участков подряд без распила между ними.
func _runs() -> Array:
	var out: Array = []
	for i in segments.size():
		if i > 0 and absf(float(segments[i]["h0"]) - float(segments[i - 1]["h1"])) < 0.001:
			out[-1][1] = i
		else:
			out.append([i, i])
	return out

## Перестроить видимый ствол: по одному цельному мешу на непрерывный кусок. Торцы (годичные
## кольца) — только на настоящих срезах: у пня и на распилах; надпил — если идёт распил.
func _rebuild_mesh() -> void:
	for mi in _pieces:
		mi.queue_free()
	_pieces.clear()
	var H: float = variant["H"]
	for run: Array in _runs():
		var lo: float = segments[run[0]]["h0"]
		var hi: float = segments[run[1]]["h1"]
		var caps := 1
		var top := hi
		if hi >= H - 0.001 and crown != null:
			top = H * (1.0 if variant["kind"] == &"palm" else 1.02) # как у стоящего дерева: уходит в крону
		else:
			caps = 3
		var notch: Dictionary = {}
		if not _notch.is_empty() and float(_notch["h"]) > lo + 0.05 and float(_notch["h"]) < hi - 0.05:
			notch = _notch
		var mi := MeshInstance3D.new()
		mi.name = "Trunk%d" % _pieces.size()
		mi.mesh = FloraLib.trunk_mesh(variant, lo, top, caps, 12, Vector3.ZERO, notch)
		add_child(mi)
		_pieces.append(mi)
		for i in range(run[0], run[1] + 1):
			segments[i]["mesh"] = mi

## Число видимых кусков ствола (для тестов).
func piece_count() -> int:
	return _pieces.size()

var _fall_axis: Vector3 = Vector3.ZERO

func start_fall(away: Vector3) -> void:
	var axis := Vector3.UP.cross(away).normalized()
	_fall_axis = axis
	angular_velocity = axis * 0.35
	# импульс тут не годится: в кадре добавления масса ещё не дошла до физ. сервера (Δv = импульс/1)
	linear_velocity = away * 0.25

func _physics_process(delta: float) -> void:
	var __pt := PerfStats.begin()
	_perf_physics(delta)
	PerfStats.end(&"flora_trees", __pt)

func _perf_physics(delta: float) -> void:
	if settled:
		return
	_t += delta
	# на шарнире недорубленной «петли» ствол валится в сторону от рубящего (первые ~50°)
	if _fall_axis != Vector3.ZERO and _t < 3.0 and global_transform.basis.y.angle_to(Vector3.UP) < 0.9:
		var along := angular_velocity.dot(_fall_axis)
		var want := _fall_axis * maxf(along, 0.25 + _t * 0.6)
		angular_velocity = angular_velocity.lerp(want, 0.2)
	if crown_shape and crown_shape.disabled and global_transform.basis.y.angle_to(Vector3.UP) > 0.6:
		crown_shape.disabled = false
	if not _butt_ext.is_empty() and global_transform.basis.y.angle_to(Vector3.UP) > 1.0:
		_extend_butt()
	if linear_velocity.length() > 14.0:
		linear_velocity = linear_velocity.limit_length(14.0)
	if angular_velocity.length() > 3.0:
		angular_velocity = angular_velocity.limit_length(3.0)
	if (_t > 2.5 and linear_velocity.length() < SETTLE_SPEED and angular_velocity.length() < 0.12) or _t > 12.0:
		settled = true
		set_deferred(&"freeze_mode", RigidBody3D.FREEZE_MODE_STATIC)
		set_deferred(&"freeze", true)

func _extend_butt() -> void:
	var ext := _butt_ext
	_butt_ext = {}
	for i in segments.size():
		var cs := segments[i]["shape"] as CollisionShape3D
		if cs == null or not is_instance_valid(cs) or not segments[i].has("r_thick"):
			continue
		var cap := (cs.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
		var rt := float(segments[i]["r_thick"])
		cap.height = maxf(cap.height + (rt - cap.radius) * 0.5, rt * 2.1)
		cap.radius = rt
		if i == 0 and float(segments[0]["h0"]) <= cut_h + 0.05:   # комель ещё не отпилен
			cap.height = float(ext["height"])
			cs.position = ext["center"]
		cs.shape = cap

func _on_body_entered(_b: Node) -> void:
	if landed or _t < 0.6:
		return
	landed = true
	var p := global_transform * FloraLib.crown_center(variant)
	Flora.play_sfx(self, "WOODImpt_LargeWoodDrop_OS_01", p, 4.0, 0.8)
	Flora.chips(get_parent(), p, Color(0.35, 0.5, 0.2), 24)

func _wake() -> void:
	settled = false
	_t = 1.5
	freeze = false

# --------------------------------------------------------------- рубка

func on_hit(by: Node, hit: Dictionary) -> void:
	var tool := Flora.tool_of(by, hit)
	var dmg: float = ChoppableTree.tree_damage(tool, hit)
	var pos: Vector3 = hit.get("position", global_position)
	var near_crown := pos.distance_to(global_transform * FloraLib.crown_center(variant)) < (1.4 if variant["kind"] == &"palm" else (variant["crown_r"] as float) * 0.8)
	if segments.is_empty() or (near_crown and crown != null):
		_hit_crown(by, dmg, pos)
		return
	Flora.chips(get_parent(), pos, Color(0.8, 0.65, 0.42), 8)
	Flora.play_sfx(self, "WEAPAxe_WoodCutAxe_OS_01", pos, -1.0, randf_range(0.95, 1.15))
	chop_acc += dmg
	if chop_acc >= LOG_CUT_DMG:
		chop_acc = 0.0
		_split_log(pos)
	else:
		_update_notch(pos, hit, by)

func _nearest_segment(near: Vector3) -> int:
	var best := 0
	var best_d := INF
	for i in segments.size():
		var s: Dictionary = segments[i]
		var mid := global_transform * FloraLib.trunk_point(variant, ((s["h0"] as float) + (s["h1"] as float)) * 0.5)
		var d := mid.distance_to(near)
		if d < best_d:
			best_d = d
			best = i
	return best

## Надпил на границе отделяемого участка (там, где пройдёт распил), глубина растёт с ударами.
func _update_notch(pos: Vector3, hit: Dictionary, by: Node) -> void:
	var i := _nearest_segment(pos)
	var s: Dictionary = segments[i]
	var lp := to_local(pos)
	var cand: Array[float] = []
	if i > 0 and absf(float(segments[i - 1]["h1"]) - float(s["h0"])) < 0.001:
		cand.append(s["h0"])
	if i < segments.size() - 1 and absf(float(segments[i + 1]["h0"]) - float(s["h1"])) < 0.001:
		cand.append(s["h1"])
	if cand.is_empty():
		return # участок и так отделён с обеих сторон — пилить нечего
	var nh: float = cand[0]
	if cand.size() > 1 and FloraLib.trunk_point(variant, cand[1]).distance_to(lp) < FloraLib.trunk_point(variant, cand[0]).distance_to(lp):
		nh = cand[1]
	var c := FloraLib.trunk_point(variant, nh)
	var ax := (FloraLib.trunk_point(variant, nh + 0.05) - c).normalized()
	# сторона надпила: откуда пришёл удар (нормаль), иначе — к рубящему, иначе — вверх
	var tries: Array[Vector3] = []
	if hit.has("normal"):
		tries.append(global_basis.inverse() * (hit["normal"] as Vector3))
	if by is Node3D:
		tries.append(to_local((by as Node3D).global_position) - c)
	tries.append(lp - c)
	tries.append(global_basis.inverse() * Vector3.UP)
	var dir := Vector3.ZERO
	for t in tries:
		var d := t - ax * t.dot(ax)
		if d.length() > 0.05:
			dir = d.normalized()
			break
	if dir == Vector3.ZERO:
		return
	if not _notch.is_empty() and absf(float(_notch["h"]) - nh) < 0.001:
		dir = _notch["dir"] # зарубка не «прыгает» по кругу от удара к удару
	_notch = {"h": nh, "dir": dir, "depth": 0.1 + 0.35 * clampf(chop_acc / LOG_CUT_DMG, 0.0, 1.0)}
	_rebuild_mesh()

func _split_log(near: Vector3) -> void:
	var best := _nearest_segment(near)
	var seg: Dictionary = segments[best]
	segments.remove_at(best)
	var lg := FloraLog.from_segment(variant, seg["h0"], seg["h1"], global_transform)
	get_parent().add_child(lg)
	(seg["shape"] as Node).queue_free()
	_notch = {}
	_rebuild_mesh()
	Flora.play_sfx(self, "WOODImpt_LargeWoodDrop_OS_01", lg.global_position, -6.0, 1.3)
	if segments.is_empty() and crown == null:
		queue_free()
	else:
		_wake()

func _hit_crown(by: Node, dmg: float, pos: Vector3) -> void:
	if crown == null:
		return
	crown_hp -= dmg
	Flora.chips(get_parent(), pos, Color(0.3, 0.5, 0.18), 12)
	Flora.play_sfx(self, "CLOTHMvmt_ClothingMovement_OS_01", pos, 0.0, 0.8)
	if randf() < 0.5:
		Flora.give(by, &"leaf", 1)
	if crown_hp > 0.0:
		return
	Flora.give(by, &"leaf", randi_range(3, 5))
	Flora.give(by, &"stick", randi_range(2, 4))
	var cp := global_transform * FloraLib.crown_center(variant)
	for i in coconuts_left:
		var c := FloraPickup.make_coconut()
		get_parent().add_child(c)
		c.global_position = cp + Vector3(randf_range(-0.6, 0.6), 0.5, randf_range(-0.6, 0.6))
		c.freeze = false
	coconuts_left = 0
	crown.queue_free()
	crown_shape.queue_free()
	crown = null
	crown_shape = null
	if segments.is_empty():
		queue_free()
	else:
		_rebuild_mesh() # верх ствола теперь срез — торец
		_wake()

func logs_left() -> int:
	return segments.size()

func has_crown() -> bool:
	return crown != null

func crown_global_position() -> Vector3:
	return global_transform * FloraLib.crown_center(variant)
