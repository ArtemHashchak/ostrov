extends TestCase
## Анимация рептилий: змея (ползёт по следу, кольцо, стойка и бросок, плывёт), крокодил
## (высокий ход, пасть, хвост в воде, кувырок), игуана и варан (походка, S-изгиб, кивки),
## черепаха (ползёт, роет, плывёт, прячется). Серии кадров — tests/shots/test_anim_reptiles_*.png

func _init() -> void:
	scene_path = ""
	timeout_sec = 1500.0

const STUB := """extends Node3D
func height_at(x: float, z: float) -> float:
	var t := clampf((x - 4.0) / 5.0, 0.0, 1.0)
	return lerpf(0.5, -2.2, t * t * (3.0 - 2.0 * t)) + sin(z * 0.7) * 0.04
func water_level() -> float:
	return 0.0
func biome_at(_x: float, _z: float) -> StringName:
	return &\"beach\"
func is_land(x: float, z: float) -> bool:
	return height_at(x, z) > 0.0
func is_night() -> bool:
	return false
"""

var root: Node3D
var cam: Camera3D
var world: Node3D
var fauna: Fauna
var force := {}      # Animal -> Dictionary {state, move_to, target}
var dummy: Node3D

func _physics_process(_dt: float) -> void:
	for an: Animal in force.keys():
		if not is_instance_valid(an) or an.dead:
			continue
		var f: Dictionary = force[an]
		an._think_t = 999.0
		if an.state != f["state"]:
			an.state = f["state"]
			an.state_t = 0.0
		if f.has("move_to"):
			an.move_to = f["move_to"]
		if f.has("target"):
			an.target = f["target"]

func _look(from: Vector3, at: Vector3, fov: float = 50.0) -> void:
	cam.position = from
	cam.look_at(at)
	cam.fov = fov

func _ground_mesh(w: Node3D) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 80
	var size := 40.0
	var h := func(x: float, z: float) -> float: return float(w.call(&"height_at", x, z))
	for i in n:
		for j in n:
			var x0 := -size * 0.5 + size * i / n
			var z0 := -size * 0.5 + size * j / n
			var x1 := x0 + size / n
			var z1 := z0 + size / n
			var a := Vector3(x0, h.call(x0, z0), z0)
			var b := Vector3(x1, h.call(x1, z0), z0)
			var c := Vector3(x1, h.call(x1, z1), z1)
			var d := Vector3(x0, h.call(x0, z1), z1)
			for v: Vector3 in [a, c, b, a, d, c]:
				st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.8, 0.72, 0.55)
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	return mi

func _spawn(sp: StringName, pos: Vector3, st: StringName, extra := {}) -> Animal:
	var an := fauna.spawn(sp, pos, 30.0)
	an.heading = 0.0
	var f := {"state": st}
	f.merge(extra)
	force[an] = f
	return an

func _force(an: Animal, st: StringName, extra := {}) -> void:
	var f := {"state": st}
	f.merge(extra)
	force[an] = f

func _spine_bent(an: Animal) -> float:
	var ctl := an.anim_ctrl as ReptileAnim
	if ctl == null:
		return 0.0
	var mx := 0.0
	for p in ctl.pts:
		mx = maxf(mx, absf(p.x))
	return mx

func run() -> void:
	root = Node3D.new()
	add_child(root)
	var env := WorldEnvironment.new()
	env.environment = RenderProfile.make_environment()
	root.add_child(env)
	root.add_child(RenderProfile.make_sun())
	var scr := GDScript.new()
	scr.source_code = STUB
	scr.reload()
	world = Node3D.new()
	world.set_script(scr)
	world.add_to_group(&"world")
	root.add_child(world)
	root.add_child(_ground_mesh(world))
	var water := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	water.mesh = pm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.1, 0.35, 0.42, 0.55)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.roughness = 0.1
	water.material_override = wm
	water.position = Vector3(0, 0.0, 0)
	root.add_child(water)
	cam = Camera3D.new()
	root.add_child(cam)
	cam.current = true
	dummy = Node3D.new()
	root.add_child(dummy)
	fauna = Fauna.new()
	fauna.auto_populate = false
	root.add_child(fauna)
	await wait(0.3)
	fauna.world = world

	# ---------------- змея ----------------
	var sn := _spawn(&"snake", Vector3(-6, 0.5, 4), &"wander", {"move_to": Vector3(-6, 0.5, -6)})
	check(sn.anim_ctrl is ReptileAnim, "у змеи контроллер рептилий")
	await wait(1.6)
	_look(sn.global_position + Vector3(1.2, 1.3, 0.6), sn.global_position + Vector3(0, 0, 0.3))
	check(_spine_bent(sn) > 0.03, "змея извивается на ходу (%.3f)" % _spine_bent(sn))
	await shot("snake_slither_a")
	await wait(0.35)
	await shot("snake_slither_b")
	# поворот: тело повторяет дугу пути
	_force(sn, &"wander", {"move_to": sn.global_position + Vector3(6, 0, 0)})
	await wait(1.6)
	_look(sn.global_position + Vector3(0.3, 2.6, 1.6), sn.global_position)
	await shot("snake_turn")
	# кольцо в покое
	_force(sn, &"idle")
	await wait(6.0)
	_look(sn.global_position + Vector3(0.0, 1.5, 1.3), sn.global_position)
	check((sn.anim_ctrl as ReptileAnim).coil_w > 0.8, "змея свернулась кольцом")
	await shot("snake_coil")
	# стойка угрозы и бросок
	dummy.global_position = sn.global_position + Vector3(0, 0.5, -1.5)
	_force(sn, &"warn", {"target": dummy})
	await wait(1.5)
	_look(sn.global_position + Vector3(1.4, 0.6, 0.2), sn.global_position + Vector3(0, 0.2, 0))
	await shot("snake_warn")
	sn.anim_event(&"attack")
	await wait(0.12)
	await shot("snake_strike")
	# плывёт
	sn.global_position = Vector3(10, 0.0, 4)
	(sn.anim_ctrl as ReptileAnim).trail.clear()
	_force(sn, &"wander", {"move_to": Vector3(10, 0, -6)})
	await wait(2.0)
	_look(sn.global_position + Vector3(1.8, 1.8, 1.2), sn.global_position)
	check(sn._model.position.y + sn.global_position.y > -0.2, "змея держится у поверхности")
	await shot("snake_swim")
	sn.queue_free()
	force.erase(sn)

	# ---------------- крокодил ----------------
	var cr := _spawn(&"croc", Vector3(-4, 0.5, 6), &"wander", {"move_to": Vector3(-4, 0.5, -8)})
	cr.speed = 0.0
	await wait(1.5)
	_look(cr.global_position + Vector3(3.6, 1.6, -1.0), cr.global_position + Vector3(0, 0.3, 0))
	await shot("croc_walk_a")
	await wait(0.3)
	await shot("croc_walk_b")
	var legs: Array = cr._model.get_meta(&"legs")
	check(absf((legs[0] as Node3D).rotation.y) > 0.05 or absf((legs[1] as Node3D).rotation.y) > 0.05, "крокодил переставляет лапы")
	_force(cr, &"idle")
	await wait(6.0)
	_look(cr.global_position + Vector3(1.3, 0.8, -2.6), cr.global_position + Vector3(0, 0.3, -1.2))
	check((cr.anim_ctrl as ReptileAnim).jaw > 0.2, "крокодил греется с открытой пастью")
	await shot("croc_jaw")
	# в воде: хвост гребёт
	cr.global_position = Vector3(11, -0.3, 6)
	(cr.anim_ctrl as ReptileAnim).trail.clear()
	_force(cr, &"wander", {"move_to": Vector3(11, -0.3, -8)})
	await wait(2.0)
	_look(cr.global_position + Vector3(2.5, 2.5, 2.0), cr.global_position)
	check(_spine_bent(cr) > 0.05, "крокодил гребёт хвостом (%.3f)" % _spine_bent(cr))
	await shot("croc_swim")
	cr.anim_event(&"attack")
	await wait(0.45)
	await shot("croc_roll")
	await wait(1.2)
	cr.queue_free()
	force.erase(cr)

	# ---------------- игуана и варан ----------------
	var mo := _spawn(&"monitor", Vector3(-3, 0.5, 5), &"wander", {"move_to": Vector3(-3, 0.5, -8)})
	var ig := _spawn(&"iguana", Vector3(-1.5, 0.5, 5), &"wander", {"move_to": Vector3(-1.5, 0.5, -8)})
	await wait(1.5)
	_look(mo.global_position + Vector3(2.4, 1.4, -0.4), mo.global_position + Vector3(0.7, 0.1, -0.3))
	await shot("lizards_walk_a")
	await wait(0.12)
	await shot("lizards_walk_b")
	await wait(0.12)
	await shot("lizards_walk_c")
	_look(mo.global_position + Vector3(0.6, 3.0, 0.2), mo.global_position + Vector3(0.7, 0.0, -0.2))
	await shot("lizards_top")
	check(_spine_bent(mo) > 0.02, "варан изгибается на ходу (%.3f)" % _spine_bent(mo))
	_force(ig, &"idle")
	_force(mo, &"idle")
	(ig.anim_ctrl as ReptileAnim).bob_next = 0.0
	await wait(1.2)
	_look(ig.global_position + Vector3(0.9, 0.35, -0.5), ig.global_position + Vector3(0, 0.12, -0.3))
	await shot("iguana_bob")
	mo.queue_free(); ig.queue_free()
	force.erase(mo); force.erase(ig)

	# ---------------- черепаха ----------------
	var tu := _spawn(&"turtle", Vector3(-2, 0.5, 3), &"wander", {"move_to": Vector3(-2, 0.5, -8)})
	await wait(2.0)
	_look(tu.global_position + Vector3(1.6, 1.0, -1.3), tu.global_position + Vector3(0, 0.15, -0.3))
	await shot("turtle_crawl_a")
	await wait(0.4)
	await shot("turtle_crawl_b")
	_force(tu, &"nest")
	tu.set(&"_nest_done", true)
	await wait(1.5)
	_look(tu.global_position + Vector3(-1.4, 0.8, 1.4), tu.global_position)
	await shot("turtle_dig")
	_force(tu, &"stay")
	await wait(1.5)
	_look(tu.global_position + Vector3(0.6, 0.6, -1.6), tu.global_position + Vector3(0, 0.15, -0.4))
	await shot("turtle_hide")
	tu.global_position = Vector3(11, -0.4, 4)
	_force(tu, &"wander", {"move_to": Vector3(11, -0.4, -8)})
	await wait(1.8)
	_look(tu.global_position + Vector3(2.0, 1.2, 0.5), tu.global_position)
	await shot("turtle_swim")
	check(true, "сцены отрисованы")
