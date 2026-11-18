class_name ArthropodRig
extends RefCounted
## Членистоногие (краб, скорпион, паук): сочленённые лапы, клешни, глаза на стебельках, хвост —
## и их процедурная анимация. Экземпляр — контроллер анимации животного (meta "anim" модели,
## интерфейс Animal.anim_ctrl): setup / animate / animate_dead / on_event.
##
## Устройство: все части — дети узла Rig (тело). Ноги — IK из двух сегментов (бедро + голень):
## точка стопы задаётся в пространстве модели (на земле) и переводится в пространство Rig,
## поэтому, когда тело качается или встаёт на дыбы, стопы остаются на месте.
## Походка — чередующиеся тетраподы (L1 R2 L3 R4 / R1 L2 R3 L4): стопа в опоре идёт назад
## ровно со скоростью тела (не скользит), в переносе — поднимается по дуге.
## LOD анимации: < 25 м — полная, 25–60 м — упрощённая (без IK, раз в два тика), дальше — заморожена.

const FULL_R := 25.0
const SIMPLE_R := 60.0

# ---------------------------- экземпляр ----------------------------
var kind: StringName = &"crab"
var model: Node3D
var rig: Node3D
var legs: Array = []    # Dictionary: hip, rest, a, b, fem, tib, side, ph, lift
var claws: Array = []   # Dictionary: sh, el, fing, side, cur(Vector4: pitch,yaw,elbow,finger)
var eyes: Array = []    # Dictionary: piv, side, cur, tgt
var mouth: Array = []   # Node3D
var tail: Array = []    # Node3D цепочка (скорпион)
var fangs: Array = []   # Node3D (паук: хелицеры)
var rest_h: float = 0.0       # подъём тела (Rig) над авторской высотой модели
var scale_k: float = 1.0      # масштаб амплитуд (размер вида)

var _t: float = 0.0
var _gait: float = 0.0
var _rng := RandomNumberGenerator.new()
var _threat: float = 0.0
var _windup: float = 0.0
var _strike: float = -1.0      # время с начала удара
var _strike_side: float = 1.0
var _eat: float = -1.0         # время с начала «поесть»
var _eat_side: float = 1.0
var _idle_next: float = 2.0
var _burrow: float = 0.0       # 0 — на поверхности, 1 — закопан
var _hurt: float = -1.0
var _curl: float = 0.0
var _dead_t: float = 0.0
var _side_turn: float = 0.0    # краб: разворот боком к движению
var _skip: bool = false
var _near_t: float = 0.0
var _near: bool = false
var _sand: CPUParticles3D
var _prev_burrow_state: bool = false
var _hidden: bool = false

static var _cam_frame: int = -1
static var _cam_pos: Vector3 = Vector3.ZERO

# ============================ сборка ============================

static func _seg_mesh(key: String, length: float, r0: float, r1: float, col: Color, tip_col: Color = Color(-1, 0, 0, 0)) -> ArrayMesh:
	return AnimalModels.cached(key, func() -> ArrayMesh:
		var st := AnimalModels.begin()
		if tip_col.r < 0.0:
			AnimalModels.tube(st, Vector3.ZERO, Vector3(0, 0, -length), r0, r1, 6, col, true)
		else:
			AnimalModels.tube(st, Vector3.ZERO, Vector3(0, 0, -length * 0.72), r0, lerpf(r0, r1, 0.72), 6, col, true)
			AnimalModels.tube(st, Vector3(0, 0, -length * 0.72), Vector3(0, 0, -length), lerpf(r0, r1, 0.72), r1, 6, tip_col, true)
		AnimalModels.ellipsoid(st, Vector3.ZERO, Vector3(r0, r0, r0) * 1.15, 6, col, false)
		return AnimalModels.commit(st))

static func _node(parent: Node3D, name_: String, pos: Vector3, mesh: Mesh = null, mat: Material = null) -> Node3D:
	var n: Node3D
	if mesh:
		n = AnimalModels.mesh_node(mesh, mat, name_)
	else:
		n = Node3D.new()
		n.name = name_
	n.position = pos
	parent.add_child(n)
	return n

func _add_leg(mat: Material, hip: Vector3, rest: Vector3, a: float, b: float, fem_m: Mesh, tib_m: Mesh, ph: float, lift: float) -> Node3D:
	var side := signf(hip.x)
	var fem := _node(rig, "Femur", hip, fem_m, mat)
	var tib := _node(rig, "Tibia", hip, tib_m, mat)
	legs.append({"hip": hip, "rest": rest, "a": a, "b": b, "fem": fem, "tib": tib, "side": side, "ph": ph, "lift": lift,
		"cur": rest})
	return fem

## Клешня: плечо (мерус) → локоть (кисть с неподвижным пальцем) → подвижный палец.
func _add_claw(mat: Material, shoulder: Vector3, k: float, key: String) -> Node3D:
	var side := signf(shoulder.x)
	var arm_m := _seg_mesh(key + "_arm", 0.075 * k, 0.017 * k, 0.014 * k, Color(0.9, 0, 0, 0))
	var hand_m := AnimalModels.cached(key + "_hand", func() -> ArrayMesh:
		var st := AnimalModels.begin()
		AnimalModels.ellipsoid(st, Vector3(0, 0, -0.012 * k), Vector3(0.016, 0.015, 0.018) * k, 7, Color(0.9, 0, 0, 0)) # запястье
		AnimalModels.ellipsoid(st, Vector3(0, 0.0, -0.05 * k), Vector3(0.028, 0.021, 0.042) * k, 10, Color(0.9, 0, 0, 0)) # ладонь
		AnimalModels.tube(st, Vector3(0, -0.006, -0.085) * k, Vector3(0, -0.009, -0.128) * k, 0.012 * k, 0.003 * k, 6, Color(0.55, 0.0, 0, 0), true)
		AnimalModels.tube(st, Vector3(0, -0.009, -0.118) * k, Vector3(0, -0.006, -0.13) * k, 0.005 * k, 0.0015 * k, 5, Color(0.3, 1.0, 0, 0), true)
		return AnimalModels.commit(st))
	var fing_m := AnimalModels.cached(key + "_finger", func() -> ArrayMesh:
		var st := AnimalModels.begin()
		AnimalModels.tube(st, Vector3.ZERO, Vector3(0, -0.002, -0.034) * k, 0.011 * k, 0.006 * k, 6, Color(0.75, 0.0, 0, 0), true)
		AnimalModels.tube(st, Vector3(0, -0.002, -0.034) * k, Vector3(0, -0.007, -0.05) * k, 0.006 * k, 0.0015 * k, 5, Color(0.4, 1.0, 0, 0), true)
		return AnimalModels.commit(st))
	var sh := _node(rig, "Claw", shoulder)
	_node(sh, "Arm", Vector3.ZERO, arm_m, mat)
	var el := _node(sh, "Elbow", Vector3(0, 0, -0.075 * k))
	_node(el, "Hand", Vector3.ZERO, hand_m, mat)
	var fing := _node(el, "Finger", Vector3(0, 0.013 * k, -0.082 * k))
	_node(fing, "FingerMesh", Vector3.ZERO, fing_m, mat)
	claws.append({"sh": sh, "el": el, "fing": fing, "side": side, "cur": Vector4(0, 0, 0, 0)})
	return sh

func _add_eye(mat: Material, pos: Vector3, stalk: float, r: float, key: String) -> void:
	var piv := _node(rig, "EyeStalk", pos)
	var st_m := _seg_mesh(key + "_stalk", stalk, r * 0.55, r * 0.45, Color(0.8, 0, 0, 0))
	_node(piv, "Stalk", Vector3.ZERO, st_m, mat)
	var em := SphereMesh.new()
	em.radius = r
	em.height = r * 2.0
	em.radial_segments = 8
	em.rings = 5
	var e := MeshInstance3D.new()
	e.name = "Eye"
	e.mesh = em
	e.material_override = AnimalModels.eye_material()
	e.position = Vector3(0, 0, -stalk)
	piv.add_child(e)
	eyes.append({"piv": piv, "side": signf(pos.x), "cur": Vector2(1.15, 0.0), "tgt": Vector2(1.15, 0.0)})

func _finish(root: Node3D) -> void:
	model = root
	var arr: Array = root.get_meta(&"legs")
	for c in claws:
		arr.append(c["sh"])
	for l in legs:
		arr.append(l["fem"])
	root.set_meta(&"anim", self)
	_pose(0.0, 0.0, false)

static func build_crab(root: Node3D, mat: Material) -> ArthropodRig:
	var r := ArthropodRig.new()
	r.kind = &"crab"
	r.rest_h = 0.0
	r.scale_k = 1.0
	r.rig = _node(root, "Rig", Vector3.ZERO)
	var body := AnimalModels.cached("crab_body2", func() -> ArrayMesh:
		var st := AnimalModels.begin()
		var rings: Array = []
		var prof := [[-0.1, 0.0, 0.01], [-0.085, 0.09, 0.03], [-0.04, 0.15, 0.045], [0.02, 0.16, 0.045], [0.07, 0.12, 0.035], [0.1, 0.03, 0.015]]
		for p in prof:
			rings.append({"z": p[0], "y": 0.07, "w": p[1], "h": p[2], "flat": 0.9})
		AnimalModels.loft(st, rings, 14, 1.0, 2.0)
		# брюшко (подвёрнутый «фартук») и ротовая рамка
		AnimalModels.ellipsoid(st, Vector3(0, 0.045, 0.03), Vector3(0.06, 0.012, 0.05), 8, Color(0.0, 0.0, 0, 0), false)
		return AnimalModels.commit(st))
	r.rig.add_child(AnimalModels.mesh_node(body, mat, "Body"))
	root.set_meta(&"body", r.rig.get_child(0))
	# клешни
	for sx: float in [-1.0, 1.0]:
		r._add_claw(mat, Vector3(sx * 0.085, 0.07, -0.085), 1.0, "crab_claw2")
	# глаза на стебельках
	for sx: float in [-1.0, 1.0]:
		r._add_eye(mat, Vector3(sx * 0.03, 0.1, -0.093), 0.045, 0.011, "crab_eye")
	# ротовые придатки (ногочелюсти) — мелькают, когда ест
	var mp := AnimalModels.cached("crab_mouth", func() -> ArrayMesh:
		var st := AnimalModels.begin()
		AnimalModels.ellipsoid(st, Vector3(0, -0.012, -0.004), Vector3(0.008, 0.014, 0.004), 6, Color(0.2, 0.0, 0, 0), false)
		return AnimalModels.commit(st))
	for sx: float in [-1.0, 1.0]:
		r.mouth.append(_node(r.rig, "Mouth", Vector3(sx * 0.009, 0.068, -0.099), mp, mat))
	# ходильные ноги: 4 пары, бедро вверх-наружу, голень вниз с тёмным коготком
	var fem := _seg_mesh("crab_femur3", 0.12, 0.0145, 0.012, Color(0.9, 0, 0, 0))
	var tib := _seg_mesh("crab_tibia3", 0.125, 0.011, 0.002, Color(0.75, 0, 0, 0), Color(0.35, 0.6, 0, 0))
	var splay := [-0.075, -0.025, 0.03, 0.075]
	var reach := [0.16, 0.175, 0.175, 0.155]
	for i in 4:
		for sx: float in [-1.0, 1.0]:
			var hip := Vector3(sx * 0.115, 0.062, -0.035 + i * 0.033)
			var rest := Vector3(sx * (0.115 + reach[i]), 0.0, hip.z + float(splay[i]) * 1.15)
			# тетраподы: L0 R1 L2 R3 — группа A, остальные — B
			var grp := 0.0 if ((i % 2 == 0) == (sx < 0.0)) else 0.5
			r._add_leg(mat, hip, rest, 0.12, 0.125, fem, tib, grp + i * 0.06, 0.035)
	r._finish(root)
	return r

static func build_scorpion(root: Node3D, mat: Material) -> ArthropodRig:
	var r := ArthropodRig.new()
	r.kind = &"scorpion"
	r.scale_k = 0.35
	r.rig = _node(root, "Rig", Vector3.ZERO)
	var body := AnimalModels.cached("scorpion_body2", func() -> ArrayMesh:
		var st := AnimalModels.begin()
		var rings: Array = []
		var prof := [[-0.06, 0.008], [-0.05, 0.022], [-0.02, 0.028], [0.02, 0.03], [0.05, 0.022], [0.065, 0.01]]
		for p in prof:
			rings.append({"z": p[0], "y": 0.022, "w": p[1], "h": p[1] * 0.45, "flat": 0.9})
		AnimalModels.loft(st, rings, 10, 0.0, 0.1)
		return AnimalModels.commit(st))
	r.rig.add_child(AnimalModels.mesh_node(body, mat, "Body"))
	root.set_meta(&"body", r.rig.get_child(0))
	# хвост: 5 сегментов + жало, каждый — шарнир (дуга над спиной)
	var seg := AnimalModels.cached("scorpion_tailseg", func() -> ArrayMesh:
		var st := AnimalModels.begin()
		AnimalModels.ellipsoid(st, Vector3(0, 0, -0.008), Vector3(0.0105, 0.0095, 0.0115), 7, Color(0.9, 0, 0, 0), false)
		return AnimalModels.commit(st))
	var sting := AnimalModels.cached("scorpion_sting", func() -> ArrayMesh:
		var st := AnimalModels.begin()
		AnimalModels.ellipsoid(st, Vector3(0, 0, -0.01), Vector3(0.0095, 0.0105, 0.0125), 7, Color(0.9, 0.7, 0, 0), false)
		AnimalModels.tube(st, Vector3(0, -0.006, -0.019), Vector3(0, -0.021, -0.028), 0.0042, 0.0008, 5, Color(0.3, 1.0, 0, 0), true)
		return AnimalModels.commit(st))
	var parent: Node3D = r.rig
	var pos := Vector3(0, 0.024, 0.062)
	for i in 6:
		var n := _node(parent, "Tail%d" % i, pos, sting if i == 5 else seg, mat)
		n.rotation.y = PI    # сегмент смотрит назад (+Z модели)
		r.tail.append(n)
		parent = n
		pos = Vector3(0, 0, -0.016)
	# педипальпы (клешни)
	for sx: float in [-1.0, 1.0]:
		r._add_claw(mat, Vector3(sx * 0.02, 0.022, -0.058), 0.42, "scorpion_claw2")
	var fem := _seg_mesh("scorpion_femur", 0.034, 0.0035, 0.003, Color(0.7, 0, 0, 0))
	var tib := _seg_mesh("scorpion_tibia", 0.042, 0.003, 0.0009, Color(0.6, 0, 0, 0), Color(0.5, 0.6, 0, 0))
	var splay := [-0.03, -0.01, 0.012, 0.032]
	for i in 4:
		for sx: float in [-1.0, 1.0]:
			var hip := Vector3(sx * 0.024, 0.02, -0.03 + i * 0.02)
			var rest := Vector3(sx * 0.072, 0.0, hip.z + float(splay[i]))
			var grp := 0.0 if ((i % 2 == 0) == (sx < 0.0)) else 0.5
			r._add_leg(mat, hip, rest, 0.034, 0.042, fem, tib, grp + i * 0.05, 0.012)
	r._add_eye_dots(root, [Vector3(-0.005, 0.034, -0.05), Vector3(0.005, 0.034, -0.05)], 0.0028)
	r._finish(root)
	return r

static func build_spider(root: Node3D, mat: Material) -> ArthropodRig:
	var r := ArthropodRig.new()
	r.kind = &"spider"
	r.scale_k = 0.45
	r.rig = _node(root, "Rig", Vector3.ZERO)
	var body := AnimalModels.cached("spider_body2", func() -> ArrayMesh:
		var st := AnimalModels.begin()
		AnimalModels.ellipsoid(st, Vector3(0, 0.04, -0.025), Vector3(0.026, 0.017, 0.03), 10, Color(0.7, 0, 0, 0))   # головогрудь
		AnimalModels.ellipsoid(st, Vector3(0, 0.05, 0.04), Vector3(0.036, 0.03, 0.045), 12, Color(0.7, 0, 0, 0))       # брюшко
		return AnimalModels.commit(st))
	r.rig.add_child(AnimalModels.mesh_node(body, mat, "Body"))
	root.set_meta(&"body", r.rig.get_child(0))
	# хелицеры с клыками
	var fang := AnimalModels.cached("spider_fang", func() -> ArrayMesh:
		var st := AnimalModels.begin()
		AnimalModels.tube(st, Vector3.ZERO, Vector3(0, -0.012, -0.008), 0.0062, 0.0045, 6, Color(0.3, 0, 0, 0), true)
		AnimalModels.tube(st, Vector3(0, -0.012, -0.008), Vector3(0, -0.02, 0.0), 0.0025, 0.0006, 5, Color(0.1, 1.0, 0, 0), true)
		return AnimalModels.commit(st))
	for sx: float in [-1.0, 1.0]:
		r.fangs.append(_node(r.rig, "Fang", Vector3(sx * 0.008, 0.036, -0.052), fang, mat))
	# педипальпы — короткие «ножки» у рта: как ноги, но короче
	var fem := _seg_mesh("spider_femur", 0.058, 0.0047, 0.004, Color(0.6, 0, 0, 0))
	var tib := _seg_mesh("spider_tibia", 0.07, 0.004, 0.0016, Color(0.6, 0.2, 0, 0), Color(0.5, 0.4, 0, 0))
	var yaw := [-0.75, -0.25, 0.25, 0.7]
	for i in 4:
		for sx: float in [-1.0, 1.0]:
			var hip := Vector3(sx * 0.018, 0.042, -0.042 + i * 0.012)
			var out := Vector3(sx * cos(float(yaw[i])), 0.0, sin(float(yaw[i])))
			var rest := hip + out * 0.095
			rest.y = 0.0
			var grp := 0.0 if ((i % 2 == 0) == (sx < 0.0)) else 0.5
			r._add_leg(mat, hip, rest, 0.058, 0.07, fem, tib, grp + i * 0.07, 0.022)
	r._add_eye_dots(root, [Vector3(-0.006, 0.055, -0.05), Vector3(0.006, 0.055, -0.05), Vector3(-0.003, 0.058, -0.048), Vector3(0.003, 0.058, -0.048)], 0.0028)
	r._finish(root)
	return r

func _add_eye_dots(_root: Node3D, pts: Array, rad: float) -> void:
	var em := SphereMesh.new()
	em.radius = rad
	em.height = rad * 2.0
	em.radial_segments = 8
	em.rings = 4
	var m := AnimalModels.eye_material()
	for p: Vector3 in pts:
		var e := MeshInstance3D.new()
		e.mesh = em
		e.material_override = m
		e.position = p
		rig.add_child(e)

# ============================ контроллер ============================

func setup(a: Node) -> void:
	_rng.seed = a.get_instance_id()
	_idle_next = _rng.randf_range(1.0, 4.0)
	_t = _rng.randf() * 10.0

static func _camera_pos(n: Node) -> Vector3:
	var f := Engine.get_process_frames()
	if f != _cam_frame:
		_cam_frame = f
		var cam := n.get_viewport().get_camera_3d() if n.is_inside_tree() else null
		_cam_pos = cam.global_position if cam else Vector3(1e9, 0, 0)
	return _cam_pos

func on_event(_a: Node, ev: StringName) -> void:
	match ev:
		&"attack":
			_strike = 0.0
			_strike_side = 1.0 if _rng.randf() < 0.5 else -1.0
		&"hurt":
			_hurt = 0.0
		&"die":
			_dead_t = 0.0
			_eat = -1.0
			_strike = -1.0
		&"eat":
			_start_eat()

func _start_eat() -> void:
	_eat = 0.0
	_eat_side = 1.0 if _rng.randf() < 0.5 else -1.0

func animate(a: Node, dt: float) -> void:
	var an := a as Animal
	var d := an.global_position.distance_to(_camera_pos(an))
	if d > SIMPLE_R:
		return
	_t += dt
	var simple := d > FULL_R
	if simple:
		_skip = not _skip
		if _skip:
			return
		dt *= 2.0
	var st: StringName = an.state
	var speed := an.speed
	# — угроза: поднятые клешни/хвост, паук встаёт на дыбы —
	_near_t -= dt
	if _near_t <= 0.0:
		_near_t = 0.35
		_near = an._nearest_character(3.0) != null if not simple else false
	var threat_want := 1.0 if st in [&"warn", &"attack", &"chase"] else (0.55 if _near and st in [&"idle", &"wander"] and kind != &"crab" else 0.0)
	if kind == &"crab" and _near and st in [&"idle", &"wander", &"flee"]:
		threat_want = maxf(threat_want, 0.45)
	_threat = move_toward(_threat, threat_want, dt * 4.0)
	# — удар: замах в начале атаки, щелчок/укол по событию attack —
	if st == &"attack" and _strike < 0.0:
		_windup = move_toward(_windup, 1.0, dt * 7.0)
	else:
		_windup = move_toward(_windup, 0.0, dt * 5.0)
	if _strike >= 0.0:
		_strike += dt
		if _strike > 0.45:
			_strike = -1.0
	if _hurt >= 0.0:
		_hurt += dt
		if _hurt > 0.4:
			_hurt = -1.0
	# — закапывание (краб) —
	var bur_want := 1.0 if st == &"burrow" else 0.0
	if (bur_want > 0.5) != _prev_burrow_state:
		_prev_burrow_state = bur_want > 0.5
		_sand_puff(an)
	_burrow = move_toward(_burrow, bur_want, dt * (0.85 if bur_want > 0.5 else 1.6))
	# — кормёжка: в покое время от времени щиплет песок и подносит ко рту —
	if st == &"idle" and _eat < 0.0 and _threat < 0.1 and _burrow < 0.05:
		_idle_next -= dt
		if _idle_next <= 0.0:
			_idle_next = _rng.randf_range(2.5, 6.0)
			if kind != &"spider" or _rng.randf() < 0.3:
				_start_eat()
	if _eat >= 0.0:
		_eat += dt
		if _eat > 2.4 or st != &"idle":
			_eat = -1.0
	# — краб бегает боком —
	if kind == &"crab":
		var want_side := PI * 0.5 if speed > 0.25 and st != &"attack" else 0.0
		_side_turn = lerp_angle(_side_turn, want_side, clampf(dt * 6.0, 0.0, 1.0))
		model.rotation.y = _side_turn
	_pose(speed, dt, simple)

## Направление движения в пространстве модели (тело идёт вперёд по -Z узла животного).
func _move_dir_local() -> Vector3:
	var fwd := model.transform.basis.inverse() * Vector3(0, 0, -1)
	fwd.y = 0.0
	return fwd.normalized() if fwd.length() > 0.01 else Vector3(0, 0, -1)

func _pose(speed: float, dt: float, simple: bool) -> void:
	var m := clampf(speed / 0.12, 0.0, 1.0)
	var duty := 0.62
	# длина шага ограничена досягаемостью ноги: быстрее — чаще шаги (до 14 Гц), а не длиннее
	var stride_max := 0.075 * scale_k * (1.0 if kind == &"crab" else 2.0)
	var freq := clampf(maxf(1.4, speed * duty / stride_max), 1.4, 14.0)
	if dt > 0.0:
		_gait = fmod(_gait + dt * freq * m, 1.0)
	var stride := minf(speed * duty / freq, stride_max * 1.6)
	var mv := _move_dir_local()
	# --- тело ---
	var bob := 0.0
	var roll := 0.0
	var pitch := 0.0
	var lift_y := rest_h
	if m > 0.01:
		bob = -absf(sin(_gait * TAU * 2.0)) * 0.006 * scale_k * m
		roll = sin(_gait * TAU) * 0.035 * m
	else:
		bob = sin(_t * 1.7) * 0.0015 * scale_k   # дыхание
	if _hurt >= 0.0:
		bob += sin(minf(_hurt / 0.4, 1.0) * PI) * 0.012 * scale_k
		roll += sin(_hurt * 40.0) * 0.06 * (1.0 - _hurt / 0.4)
	if kind == &"spider":
		# дыбы: перёд поднимается, задние ноги стоят
		pitch = _threat * 0.55 + _windup * 0.15
		lift_y += _threat * 0.01
		if _strike >= 0.0:
			pitch -= sin(minf(_strike / 0.3, 1.0) * PI) * 0.5
	elif kind == &"scorpion":
		pitch = -_threat * 0.08
		lift_y += _threat * 0.004
	elif kind == &"crab":
		lift_y += _threat * 0.012           # приподнимается на ногах
		pitch = _threat * 0.12
	# закопан: тело уходит в песок, покачиваясь
	var sink := _burrow * 0.115 * scale_k
	if _burrow > 0.01 and _burrow < 0.99:
		roll += sin(_t * 31.0) * 0.08
	var rb := Basis.from_euler(Vector3(pitch, 0.0, roll))
	rig.transform = Transform3D(rb, Vector3(0, lift_y + bob - sink, 0))
	if kind == &"spider":
		# поворот вокруг задней части: перёд вверх
		var pivot := Vector3(0, 0.045, 0.06)
		rig.transform = Transform3D(rb, pivot - rb * pivot + Vector3(0, lift_y + bob - sink, 0))
	var rig_inv := rig.transform.affine_inverse()
	# --- ноги ---
	var li := 0
	for l: Dictionary in legs:
		var rest: Vector3 = l["rest"]
		var ph: float = fmod(_gait + float(l["ph"]), 1.0)
		var foot := rest
		if m > 0.001:
			var off := 0.0
			var up := 0.0
			if ph < duty:
				off = stride * (0.5 - ph / duty)
			else:
				var s := (ph - duty) / (1.0 - duty)
				off = stride * (-0.5 + s)
				up = sin(s * PI) * float(l["lift"]) * (0.6 + 0.4 * m)
			foot += mv * off * m
			foot.y += up * m
			foot.x -= float(l["side"]) * up * 0.3   # в переносе нога чуть подтягивается
		# закапывание: ноги быстро гребут в стороны
		if _burrow > 0.01 and _burrow < 0.99:
			foot.z += sin(_t * 26.0 + li * 1.7) * 0.025 * scale_k
			foot.x += float(l["side"]) * absf(sin(_t * 26.0 + li)) * 0.015 * scale_k
		if _burrow > 0.0:
			foot = foot.lerp(Vector3(float(l["hip"].x) * 1.3, -0.05 * scale_k, float(l["hip"].z)), _burrow * 0.6)
		# паук на дыбах: передние две пары поднимаются вверх-вперёд
		if kind == &"spider" and li < 4 and _threat > 0.01:
			var raised := (l["hip"] as Vector3) + Vector3(float(l["side"]) * 0.03, 0.09, -0.07)
			foot = foot.lerp(rig.transform * raised, _threat * (1.0 if li < 2 else 0.5))
		# краб в угрозе: широкая стойка
		if kind == &"crab" and _threat > 0.01:
			foot.x += float(l["side"]) * 0.02 * _threat
		# смерть: ноги поджимаются к брюху
		if _curl > 0.0:
			var hip_m: Vector3 = rig.transform * (l["hip"] as Vector3)
			var curled := hip_m + Vector3(float(l["side"]) * 0.04, -0.02, 0.0) * (1.0 if kind == &"crab" else scale_k * 1.6)
			var tw := sin(_t * 23.0 + li * 2.1) * 0.012 * maxf(0.0, 1.0 - _dead_t / 1.6) * scale_k
			foot = foot.lerp(curled, _curl) + Vector3(0, tw, tw)
		l["cur"] = foot
		_solve_leg(l, rig_inv * foot, simple)
		li += 1
	# закопан полностью — ноги и клешни под песком (не торчат палками)
	var hide := _burrow > 0.8
	if hide != _hidden:
		_hidden = hide
		for l: Dictionary in legs:
			(l["fem"] as Node3D).visible = not hide
			(l["tib"] as Node3D).visible = not hide
		for c: Dictionary in claws:
			(c["sh"] as Node3D).visible = not hide
	# --- клешни ---
	for c: Dictionary in claws:
		_pose_claw(c, dt)
	# --- глаза на стебельках: подёргиваются, прячутся при испуге ---
	for e: Dictionary in eyes:
		if _rng.randf() < dt * 1.5:
			e["tgt"] = Vector2(1.15 + _rng.randf_range(-0.3, 0.25), _rng.randf_range(-0.35, 0.35))
		var tgt: Vector2 = e["tgt"]
		var retract := maxf(maxf(_hurt_amount(), _threat * 0.0), 1.0 if _curl > 0.0 else 0.0)
		if _burrow > 0.6:
			tgt = Vector2(1.45, 0.0)     # закопан — глаза торчат из песка
		tgt = tgt.lerp(Vector2(0.12, 0.0), retract)
		var cur: Vector2 = e["cur"]
		cur = cur.lerp(tgt, clampf(dt * 10.0, 0.0, 1.0)) if dt > 0.0 else tgt
		e["cur"] = cur
		var piv: Node3D = e["piv"]
		piv.rotation = Vector3(cur.x, float(e["side"]) * (-0.25) + cur.y * float(e["side"]), 0.0)
		if _burrow > 0.6:
			piv.position.y = 0.1 + _burrow * 0.06
		else:
			piv.position.y = move_toward(piv.position.y, 0.1, dt * 0.3)
	# --- рот ---
	var flick := 0.0
	if _eat > 0.9 or (kind == &"crab" and _rng.randf() < 0.02):
		flick = sin(_t * 38.0) * 0.5
	for i in mouth.size():
		(mouth[i] as Node3D).rotation = Vector3(0.0, (flick if i == 0 else -flick), 0.0)
	# --- хвост скорпиона ---
	if not tail.is_empty():
		_pose_tail(dt)
	# --- клыки паука ---
	for i in fangs.size():
		var f := fangs[i] as Node3D
		var open := _threat * 0.6 + (sin(minf(_strike / 0.25, 1.0) * PI) * 0.8 if _strike >= 0.0 else 0.0)
		f.rotation = Vector3(-open, (1.0 if i == 0 else -1.0) * open * 0.4, 0.0)

func _hurt_amount() -> float:
	return sin(clampf(_hurt / 0.4, 0.0, 1.0) * PI) if _hurt >= 0.0 else 0.0

## Двухзвенная IK: бедро от тазобедренного шарнира к колену (колено вверх-наружу), голень — к стопе.
func _solve_leg(l: Dictionary, foot: Vector3, simple: bool) -> void:
	var hip: Vector3 = l["hip"]
	var a: float = l["a"]
	var b: float = l["b"]
	var fem: Node3D = l["fem"]
	var tib: Node3D = l["tib"]
	var D := foot - hip
	var dist := clampf(D.length(), absf(a - b) + 0.001, a + b - 0.0005)
	var dir := D.normalized() if D.length() > 0.0001 else Vector3(float(l["side"]), -0.3, 0).normalized()
	var knee: Vector3
	if simple:
		# упрощённо: колено — над серединой
		knee = hip + dir * (a * 0.7) + Vector3(0, a * 0.55, 0)
	else:
		var cos_a := clampf((a * a + dist * dist - b * b) / (2.0 * a * dist), -1.0, 1.0)
		var ang := acos(cos_a)
		var axis := dir.cross(Vector3.UP)
		if axis.length() < 0.001:
			axis = Vector3(0, 0, 1)
		axis = axis.normalized()
		knee = hip + dir.rotated(axis, ang) * a
	fem.transform = Transform3D(_look_basis(knee - hip, float(l["side"])), hip)
	tib.transform = Transform3D(_look_basis(foot - knee, float(l["side"])), knee)

static func _look_basis(dir: Vector3, side: float) -> Basis:
	if dir.length() < 0.00001:
		return Basis.IDENTITY
	var n := dir.normalized()
	var up := Vector3.UP if absf(n.y) < 0.92 else Vector3(side, 0, 0)
	return Basis.looking_at(n, up)

## Клешня: целевые углы по состоянию, сглаживание. cur = (подъём плеча, разворот плеча, сгиб локтя, раскрытие пальца).
func _pose_claw(c: Dictionary, dt: float) -> void:
	var s: float = c["side"]
	var crab := kind == &"crab"
	# покой: клешни сложены перед «лицом»
	var tgt := Vector4(-0.12, -s * 0.55, s * 1.55, 0.06) if crab else Vector4(0.05, -s * 0.25, s * 1.0, 0.08)
	# пощёлкивание в покое
	tgt.w += maxf(0.0, sin(_t * (2.3 + s * 0.4) + s)) * 0.12
	# угроза: подняты и разведены, пальцы раскрыты, дрожат
	var thr := Vector4(0.95, -s * 1.05, s * 0.85, 0.75) if crab else Vector4(0.35, -s * 0.7, s * 0.6, 0.6)
	thr += Vector4(sin(_t * 17.0 + s) * 0.04, 0.0, 0.0, sin(_t * 9.0 + s) * 0.08)
	tgt = tgt.lerp(thr, _threat)
	# замах перед ударом: шире, выше
	tgt = tgt.lerp(Vector4(1.15, -s * 1.2, s * 1.0, 0.95), _windup * (1.0 if s == _strike_side or not crab else 0.5))
	# удар: выброс вперёд и резкое смыкание (обе — у скорпиона, одна — у краба)
	if _strike >= 0.0 and (s == _strike_side or not crab):
		var k := _strike / 0.45
		var thrust := sin(minf(k * 2.2, 1.0) * PI * 0.5) * (1.0 - smoothstep(0.55, 1.0, k))
		tgt = tgt.lerp(Vector4(0.25, -s * 0.3, s * 0.2, 0.0), thrust)
		if k < 0.25:
			tgt.w = lerpf(0.95, 0.0, k / 0.25)
	# кормёжка: щипок песка → ко рту
	if _eat >= 0.0 and s == _eat_side:
		var e := _eat
		if e < 0.5:
			tgt = tgt.lerp(Vector4(-0.55, -s * 0.35, s * 0.9, 0.5), smoothstep(0.0, 0.5, e))   # вниз к песку, пальцы раскрыты
		elif e < 0.8:
			tgt = Vector4(-0.55, -s * 0.35, s * 0.9, 0.0)                                     # щипок
		else:
			var k2 := smoothstep(0.8, 1.3, e) * (1.0 - smoothstep(2.0, 2.4, e))
			tgt = Vector4(-0.55, -s * 0.35, s * 0.9, 0.0).lerp(Vector4(-0.05, -s * 0.15, s * 2.15, 0.05), k2)  # ко рту
	# ранен — прикрывается
	tgt = tgt.lerp(Vector4(0.3, -s * 0.3, s * 1.9, 0.0), _hurt_amount() * 0.7)
	# смерть — сложены
	if _curl > 0.0:
		tgt = tgt.lerp(Vector4(-0.4, -s * 0.2, s * 2.0, 0.0), _curl)
	# закопан — прижаты
	tgt = tgt.lerp(Vector4(-0.25, -s * 0.4, s * 1.9, 0.0), _burrow)
	var cur: Vector4 = c["cur"]
	var rate := 26.0 if _strike >= 0.0 else 9.0
	cur = cur.lerp(tgt, clampf(dt * rate, 0.0, 1.0)) if dt > 0.0 else tgt
	c["cur"] = cur
	(c["sh"] as Node3D).rotation = Vector3(cur.x, cur.y, 0.0)
	(c["el"] as Node3D).rotation = Vector3(-cur.x * 0.35, cur.z, 0.0)
	(c["fing"] as Node3D).rotation = Vector3(cur.w, 0.0, 0.0)

## Хвост скорпиона: дуга над спиной; угроза — выше и напряжённее; удар — жало резко вперёд.
func _pose_tail(dt: float) -> void:
	var curl := 0.6 + _threat * 0.08 + sin(_t * 1.3) * 0.02
	var sway := sin(_t * 0.9) * 0.08 * (1.0 - _threat)
	if _threat > 0.0:
		sway += sin(_t * 11.0) * 0.03 * _threat
	var strike := 0.0
	if _strike >= 0.0:
		var k := _strike / 0.45
		strike = sin(minf(k * 2.5, 1.0) * PI * 0.5) * (1.0 - smoothstep(0.5, 1.0, k))
	var wind := _windup
	for i in tail.size():
		var n := tail[i] as Node3D
		var base := curl + wind * 0.08 + strike * 0.22
		if i == 0:
			base = 0.75 + _threat * 0.2 + wind * 0.15 - strike * 0.1
		if i == tail.size() - 1:
			base = 0.5 + strike * 0.9 - wind * 0.3
		if _curl > 0.0:
			base = lerpf(base, 0.3, _curl)
		var tgt := Vector3(base, PI if i == 0 else 0.0, sway if i > 0 else 0.0)
		n.rotation = n.rotation.lerp(tgt, clampf(dt * (30.0 if _strike >= 0.0 else 8.0), 0.0, 1.0)) if dt > 0.0 else tgt

func animate_dead(a: Node, dt: float) -> void:
	_t += dt
	_dead_t += dt
	_burrow = 0.0
	_threat = move_toward(_threat, 0.0, dt * 3.0)
	_curl = clampf(_dead_t / 1.4, 0.0, 1.0)
	if kind == &"crab":
		model.rotation.y = lerp_angle(model.rotation.y, 0.0, clampf(dt * 3.0, 0.0, 1.0))
	# перевёрнутое тело лежит на земле, а не уходит под неё
	var flip := (1.0 - cos(model.rotation.z)) * 0.5
	model.position.y = flip * (0.12 if kind == &"crab" else 0.06)
	var an := a as Animal
	if an and an.global_position.distance_to(_camera_pos(an)) > SIMPLE_R:
		return
	if _dead_t < 3.0:
		_pose(0.0, dt, false)

func _sand_puff(an: Node3D) -> void:
	if kind != &"crab" or not an.is_inside_tree():
		return
	if _sand == null:
		_sand = CPUParticles3D.new()
		_sand.name = "SandPuff"
		_sand.emitting = false
		_sand.one_shot = true
		_sand.amount = 18
		_sand.lifetime = 0.9
		_sand.explosiveness = 0.8
		_sand.direction = Vector3(0, 1, 0)
		_sand.spread = 70.0
		_sand.initial_velocity_min = 0.25
		_sand.initial_velocity_max = 0.6
		_sand.gravity = Vector3(0, -1.6, 0)
		_sand.scale_amount_min = 0.5
		_sand.scale_amount_max = 1.2
		var qm := QuadMesh.new()
		qm.size = Vector2(0.025, 0.025)
		var mt := StandardMaterial3D.new()
		mt.albedo_color = Color(0.82, 0.74, 0.56, 0.85)
		mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mt.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		qm.material = mt
		_sand.mesh = qm
		_sand.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		_sand.emission_sphere_radius = 0.1
		an.add_child(_sand)
		_sand.position = Vector3(0, 0.03, 0)
	_sand.restart()
