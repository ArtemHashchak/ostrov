class_name SandboxLand2
extends RefCounted
## «Пак моделей», третья волна (модели чата моделирования, 2026-11-22): сухопутные существа с клипами
## автора — загоны с живыми особями (поведение игры, клипы через UserClipRig) и жёрдочка с попугаями.
## Площадка — к востоку от прежних экспонатов пака (свободный берег между ними и морем).

const P := preload("res://scripts/sandbox/sandbox_props.gd")

## Треугольники игровых GLB (замер при вставке; LOD — автоматический импорт Godot).
const TRIS := {"green_pit_viper": 8912, "blue_pit_viper": 40708, "ball_python": 7504, "carpet_python": 8764,
	"varan_komodo": 38660, "iguana_green": 40910, "salamander_fire": 7820, "centipede_giant": 17912,
	"hermit_crab_brown": 49063, "pionus_bluehead": 16820, "kea": 33472}
## Поведение в игре — одной строкой на вид.
const HOW := {
	&"snake": "угроза: стойка (синяя — кольцо → стойка) → бросок, яд; язык и «нюханье» в покое",
	&"python": "без яда: стойка → бросок; ползёт, язык, «нюханье»",
	&"monitor": "патруль, язык каждые 3–8 с; угроза — поворот к цели, выпад с места / укус вблизи; плывёт в воде",
	&"iguana": "пуглива: бег прочь; кивки, моргание, греется; удар хвостом при ранении",
	&"salamander": "медленная, пуглива; ест, оборонительная поза",
	&"centipede": "угроза — встаёт на дыбы → укус с ядом; быстрый бег",
	&"hermit_crab": "человек ближе 1.5 м — прячется в раковину на 3–6 с, выглядывает и уползает",
}

const COLS := 4
const STEP_X := 6.5
const STEP_Z := 7.5

static func build(zones: SandboxZones, root: Node3D, c: Vector2) -> void:
	var fa := Fauna.instance()
	var x0 := c.x + 26.0
	var z0 := c.y - 11.0
	P.signpost(root, x0 - 4.5, z0 - 3.5, "ПАК №3: РЕПТИЛИИ, ПТИЦЫ",
		"Модели чата моделирования · свои скелеты и клипы автора\nзмеи, питоны, варан, игуана, саламандра, сколопендра, отшельник, попугаи")
	var slot := 0
	for sp: StringName in [&"snake", &"python", &"monitor", &"iguana", &"salamander", &"centipede", &"hermit_crab"]:
		if not UserClipRig.available(sp):
			continue
		var vs: Array = UserClipRig.variants(sp)
		for vi in vs.size():
			var v: Dictionary = vs[vi]
			var x := x0 + (slot % COLS) * STEP_X
			var z := z0 + (slot / COLS) * STEP_Z
			slot += 1
			var r := 3.0 if sp == &"monitor" else (2.6 if sp in [&"python", &"iguana"] else 2.2)
			P.pen(root, x, z, r)
			if fa:
				zones._penned(fa, sp, Vector2(x, z), r, vi)
			P.tag(root, x, z + r + 0.5, _info(sp, v), 1.9, 30.0)
			var id := StringName("pack3_" + String(v["id"]))
			zones._point(id, "Пак: " + String(v["name"]),
				Vector3(x - r * 0.7, P.ground(x - r * 0.7, z - r - 1.6) + 0.9, z - r - 1.6),
				Vector3(x, P.ground(x, z) + 0.15, z))
	# попугаи: жёрдочка с обоими видами (клипы по кругу) + живая стайка над загонами
	if UserClipRig.available(&"parrot"):
		var x := x0 + (slot % COLS) * STEP_X
		var z := z0 + (slot / COLS) * STEP_Z
		_perch(root, x, z)
		var vs: Array = UserClipRig.variants(&"parrot")
		var names := []
		for v: Dictionary in vs:
			names.append("%s (%s треуг.)" % [v["name"], _n(TRIS.get(v["id"], 0))])
		P.tag(root, x, z + 1.8, "Попугаи: %s\nклипы: сидит, чистит перья, кричит, клюёт, прыжок, взлёт, полёт, планирование, посадка\nв игре — стайки джунглей (вариант на особь)" % ", ".join(names), 2.3, 30.0)
		zones._point(&"pack3_parrots", "Пак: попугаи", Vector3(x - 1.6, P.ground(x - 1.6, z - 2.2) + 1.6, z - 2.2), Vector3(x, P.ground(x, z) + 1.4, z))
		if fa:
			zones._flock(fa, &"parrot", Vector3(x0 + 10.0, P.ground(x0 + 10.0, z0 + 8.0) + 6.0, z0 + 8.0), 4)

static func _info(sp: StringName, v: Dictionary) -> String:
	var clips: Array = []
	for role: String in (v["clips"] as Dictionary):
		var cn := String(v["clips"][role])
		if not (cn in clips):
			clips.append(cn)
	for e: Array in v.get("extras", []):
		if not (String(e[0]) in clips):
			clips.append(String(e[0]))
	return "%s · %s треуг. · длина %.2f м\nклипы: %s\n%s" % [v["name"], _n(TRIS.get(v["id"], 0)),
		float(v["len"]) * float(v.get("scale", 1.0)), ", ".join(clips), HOW.get(sp, "")]

static func _n(v: Variant) -> String:
	var s := str(int(v))
	var out := ""
	while s.length() > 3:
		out = " " + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out

## Жёрдочка: столбик с перекладиной, на ней оба попугая; клипы покоя сменяют друг друга.
static func _perch(root: Node3D, x: float, z: float) -> void:
	var g := P.ground(x, z)
	var post := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.07
	cm.height = 1.3
	post.mesh = cm
	post.material_override = P._post_mat()
	root.add_child(post)
	post.global_position = Vector3(x, g + 0.65, z)
	var bar := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.025
	bm.bottom_radius = 0.025
	bm.height = 1.1
	bar.mesh = bm
	bar.material_override = P._post_mat()
	root.add_child(bar)
	bar.global_position = Vector3(x, g + 1.3, z)
	bar.rotation.z = PI * 0.5
	var vs: Array = UserClipRig.variants(&"parrot")
	for i in vs.size():
		var m := UserClipRig.build_variant(&"parrot", i)
		var cyc := PerchCycle.new()
		cyc.model = m
		root.add_child(cyc)
		root.add_child(m)
		m.global_position = Vector3(x - 0.25 + i * 0.5, g + 1.325, z)
		m.rotation.y = PI   # клювом к зрителю (точка обзора — с −Z)

## Покой на жёрдочке: idle_perch, вставки (чистит перья, кричит, клюёт, прыжок), изредка взмах крыльями.
class PerchCycle extends Node:
	var model: Node3D
	var _t := 0.0
	var _next := 2.0
	func _process(dt: float) -> void:
		if model == null or not is_instance_valid(model):
			return
		var c: UserClipRig = model.get_meta(&"anim")
		if c == null or c.player == null:
			return
		_t += dt
		if c._oneshot != "" and c.player.is_playing():
			c.player.advance(dt)
			return
		c._oneshot = ""
		if _t >= _next:
			_t = 0.0
			_next = randf_range(2.5, 6.0)
			var pool := ["preen", "call", "peck", "hop", "takeoff"]
			c._shot(pool[randi() % pool.size()], 0.2)
		elif c._cur != "idle_perch" or not c.player.is_playing():
			c._play("idle_perch", 0.25)
		c.player.advance(dt)
