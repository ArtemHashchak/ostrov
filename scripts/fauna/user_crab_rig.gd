class_name UserCrabRig
extends ArthropodRig
## Краб из пака пользователя (assets/user_pack/animals/crab): скин-меш со скелетом (Blender → GLB),
## анимация — та же процедурная логика ArthropodRig (походка, угроза, щипок, кормёжка, закапывание,
## смерть), но вместо отдельных узлов-сегментов двигаются кости Skeleton3D:
##  • ноги (3 пары × 4 кости) — FABRIK-IK от тазобедренного сустава к стопе; цепь сначала
##    поворачивается вокруг вертикали к цели (колени остаются вверх-наружу, как у авторской позы);
##  • клешни (4 кости + подвижный палец R/L.Finger) — запястье ведётся IK к целевой точке,
##    кисть разворачивается к направлению щипка, палец открывается вокруг шарнира;
##  • при ходьбе клешни покачиваются в такт шагу и пощёлкивают.
## Процедурная модель ArthropodRig.build_crab остаётся запасной: UserCrabRig.use_pack = false.

const SCENE := "res://assets/user_pack/animals/crab/crab_user.glb"
const TEX := "res://assets/user_pack/animals/crab/crab_"
const LEGS := [["Bone.005", "Bone.007", "Bone.008", "Bone.009"],
	["Bone.010", "Bone.011", "Bone.012", "Bone.013"],
	["Bone.014", "Bone.015", "Bone.016", "Bone.017"]]
const CLAW := ["Bone.001", "Bone.002", "Bone.003", "Bone.004"]

static var use_pack := true
static var _mat: StandardMaterial3D
static var _scene: PackedScene

var skel: Skeleton3D
var _skel_xf := Transform3D.IDENTITY     # пространство скелета → пространство Rig
var _skel_inv := Transform3D.IDENTITY
var _claw_walk: float = 0.0

## Знак/сила наклона стебелька при «прятании» (кость: ось X — поперёк, Y — вдоль стебелька).
const EYE_TILT := 1.15

static func available() -> bool:
	return use_pack and ResourceLoader.exists(SCENE)

static func material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.albedo_texture = load(TEX + "albedo.png")
		_mat.normal_enabled = true
		_mat.normal_texture = load(TEX + "normal.png")
		_mat.normal_scale = 0.8
		var orm := load(TEX + "orm.png") as Texture2D
		_mat.ao_enabled = true
		_mat.ao_texture = orm
		_mat.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		_mat.roughness_texture = orm
		_mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		_mat.roughness = 1.0
		_mat.metallic = 0.0
		_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return _mat

static func clear_cache() -> void:
	_mat = null
	_scene = null

## Модель краба (корень с метой "anim" = UserCrabRig), как AnimalModels._crab().
static func make_model(root: Node3D) -> UserCrabRig:
	var r := UserCrabRig.new()
	r.kind = &"crab"
	r.scale_k = 2.0      # краб пака вдвое выше процедурного: амплитуды шага/закапывания крупнее
	r.rest_h = 0.0
	r.rig = _node(root, "Rig", Vector3.ZERO)
	if _scene == null:
		_scene = load(SCENE) as PackedScene
	var inst := _scene.instantiate() as Node3D
	inst.name = "Body"
	r.rig.add_child(inst)
	root.set_meta(&"body", inst)
	r.skel = _find_skeleton(inst)
	for mi: MeshInstance3D in _meshes(inst):
		mi.material_override = material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# скелет → Rig
	var xf := r.skel.transform
	var p := r.skel.get_parent()
	while p != null and p != r.rig:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	r._skel_xf = xf
	r._skel_inv = xf.affine_inverse()
	var B: Dictionary = UserCrabData.BONES
	# ноги: тройки (L0 R1 L2) / (R0 L1 R2) в противофазе
	for i in LEGS.size():
		for sx: float in [-1.0, 1.0]:
			var pre := "L." if sx > 0.0 else "R."
			var bones: Array[int] = []
			var pts: Array[Vector3] = []
			for nm: String in LEGS[i]:
				bones.append(r.skel.find_bone(pre + nm))
				pts.append(B[pre + nm][0])
			pts.append(B[pre + LEGS[i][3]][1])
			var lens: Array[float] = []
			for k in 4:
				lens.append(pts[k].distance_to(pts[k + 1]))
			var tip: Vector3 = xf * pts[4]
			var rest := Vector3(tip.x * 0.97, 0.0, tip.z)
			var grp := 0.0 if ((i % 2 == 0) == (sx < 0.0)) else 0.5
			var dummy_f := _node(r.rig, "LegF", Vector3.ZERO)
			var dummy_t := _node(r.rig, "LegT", Vector3.ZERO)
			r.legs.append({"hip": xf * pts[0], "rest": rest, "a": lens[1], "b": lens[2] + lens[3],
				"fem": dummy_f, "tib": dummy_t, "side": sx, "ph": grp + i * 0.07, "lift": 0.05,
				"cur": rest, "bones": bones, "pts": pts, "lens": lens})
	# клешни
	for sx: float in [-1.0, 1.0]:
		var pre := "L." if sx > 0.0 else "R."
		var bones: Array[int] = []
		var pts: Array[Vector3] = []
		for nm: String in CLAW:
			bones.append(r.skel.find_bone(pre + nm))
			pts.append(B[pre + nm][0])
		pts.append(B[pre + CLAW[3]][1])
		var lens: Array[float] = []
		for k in 4:
			lens.append(pts[k].distance_to(pts[k + 1]))
		var f_head: Vector3 = B[pre + "Finger"][0]
		var f_tail: Vector3 = B[pre + "Finger"][1]
		var fix_tip: Vector3 = B[pre + "FixTip"][0]
		var fdir := (f_tail - f_head).normalized()
		var axis := fdir.cross((fix_tip - f_head).normalized()).normalized()
		var sh := _node(r.rig, "Claw", xf * pts[0])
		r.claws.append({"sh": sh, "el": sh, "fing": sh, "side": sx, "cur": Vector4.ZERO,
			"bones": bones, "pts": pts, "lens": lens, "finger": r.skel.find_bone(pre + "Finger"),
			"f_axis": axis, "wrist": pts[2], "palm": (pts[4] - pts[2]).normalized(),
			"w": pts[2], "d": (pts[4] - pts[2]).normalized(), "open": 0.0})
	# глаза на стебельках (кости R.Eye / L.Eye из stageD_eyes.py): подёргиваются, прячутся
	for sx: float in [-1.0, 1.0]:
		var eb := r.skel.find_bone(("L." if sx > 0.0 else "R.") + "Eye")
		if eb >= 0:
			var piv := _node(r.rig, "EyeStalk", Vector3.ZERO)
			r.eyes.append({"piv": piv, "side": sx, "cur": Vector2(1.15, 0.0), "tgt": Vector2(1.15, 0.0),
				"bone": eb, "rest": r.skel.get_bone_rest(eb).basis.get_rotation_quaternion()})
	r._finish(root)
	return r

static func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var s := _find_skeleton(c)
		if s:
			return s
	return null

static func _meshes(n: Node, out: Array[MeshInstance3D] = []) -> Array[MeshInstance3D]:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_meshes(c, out)
	return out

# ============================ IK ============================

## FABRIK по цепи точек (корень закреплён). Начальная форма — цепь покоя, повёрнутая вокруг
## вертикали к цели, поэтому «колени» сохраняют авторский изгиб.
static func _fabrik(rest: Array[Vector3], lens: Array[float], target: Vector3, iters: int) -> Array[Vector3]:
	var n := rest.size()
	var root := rest[0]
	var rd := rest[n - 1] - root
	rd.y = 0.0
	var td := target - root
	td.y = 0.0
	var yaw := 0.0
	if rd.length() > 0.001 and td.length() > 0.001:
		yaw = rd.signed_angle_to(td, Vector3.UP)
	var q := Basis(Vector3.UP, yaw)
	var p: Array[Vector3] = []
	for i in n:
		p.append(root + q * (rest[i] - root))
	var total := 0.0
	for l in lens:
		total += l
	if root.distance_to(target) >= total * 0.999:
		var dir := (target - root).normalized()
		for i in range(1, n):
			p[i] = p[i - 1] + dir * lens[i - 1]
		return p
	for _it in iters:
		p[n - 1] = target
		for i in range(n - 2, -1, -1):
			p[i] = p[i + 1] + (p[i] - p[i + 1]).normalized() * lens[i]
		p[0] = root
		for i in range(1, n):
			p[i] = p[i - 1] + (p[i] - p[i - 1]).normalized() * lens[i - 1]
		if p[n - 1].distance_squared_to(target) < 0.000001:
			break
	return p

## Повернуть кости цепи так, чтобы суставы встали в точки p (пространство скелета).
## yaw — общий разворот цепи вокруг вертикали (сохраняет «скрутку» костей), остаток — кратчайшей дугой.
func _apply_chain(bones: Array[int], rest: Array[Vector3], p: Array[Vector3], count: int) -> Transform3D:
	var root := rest[0]
	var rd := rest[rest.size() - 1] - root
	rd.y = 0.0
	var pd := p[p.size() - 1] - p[0]
	pd.y = 0.0
	var yaw := rd.signed_angle_to(pd, Vector3.UP) if rd.length() > 0.001 and pd.length() > 0.001 else 0.0
	var qy := Quaternion(Vector3.UP, yaw)
	var par := skel.get_bone_parent(bones[0])
	var parent_g := skel.get_bone_global_pose(par) if par >= 0 else Transform3D.IDENTITY
	var g := Transform3D.IDENTITY
	for i in count:
		var bi := bones[i]
		var rest_g := skel.get_bone_global_rest(bi)
		var d0 := qy * (rest[i + 1] - rest[i]).normalized()
		var d1 := (p[i + 1] - p[i]).normalized()
		var arc := Quaternion(d0, d1) if d0.dot(d1) > -0.999 else Quaternion(Vector3.UP, PI)
		var gb := Basis(arc * qy) * rest_g.basis
		g = Transform3D(gb, p[i])
		var local := parent_g.affine_inverse() * g
		skel.set_bone_pose_rotation(bi, local.basis.get_rotation_quaternion())
		parent_g = g
	return g

# ============================ переопределения ArthropodRig ============================

func _solve_leg(l: Dictionary, foot: Vector3, simple: bool) -> void:
	var target := _skel_inv * foot
	var rest: Array[Vector3] = l["pts"]
	var p := _fabrik(rest, l["lens"], target, 3 if simple else 8)
	_apply_chain(l["bones"], rest, p, 4)

func _pose(speed: float, dt: float, simple: bool) -> void:
	_claw_walk = clampf(speed / 0.12, 0.0, 1.0)
	super._pose(speed, dt, simple)
	_pose_eyes()

## Кости глаз по состоянию стебельков из ArthropodRig (cur.x ≈ 1.15 — торчат, 0.12 — спрятаны):
## наклон вперёд-вниз в гнездо и поворот вбок.
func _pose_eyes() -> void:
	for e: Dictionary in eyes:
		if not e.has("bone"):
			continue
		var cur: Vector2 = e["cur"]
		var tilt := (cur.x - 1.15) * EYE_TILT
		var turn := cur.y * float(e["side"]) * 0.8
		var q: Quaternion = e["rest"]
		skel.set_bone_pose_rotation(int(e["bone"]), q * Quaternion(Vector3.RIGHT, tilt) * Quaternion(Vector3.UP, turn))

## Клешня: цель запястья (w), направление кисти (d), раскрытие пальца — по состоянию; сглаживание.
func _pose_claw(c: Dictionary, dt: float) -> void:
	var s: float = c["side"]
	var m := _claw_walk
	# покой: клешни сложены перед «лицом», кисти смотрят внутрь-вперёд
	var w := Vector3(s * 0.135, 0.15, -0.15)
	var d := Vector3(-s * 0.45, -0.25, -0.86)
	var op := 0.08 + maxf(0.0, sin(_t * (2.3 + s * 0.4) + s)) * 0.14
	# ходьба: клешни покачиваются в такт шагу, пальцы пощёлкивают
	if m > 0.01:
		var ph := _gait * TAU + (0.0 if s > 0.0 else PI)
		w += Vector3(s * 0.008 * sin(ph), 0.022 * sin(ph), 0.02 * cos(ph)) * m
		d = d.rotated(Vector3.UP, 0.16 * sin(ph) * m)
		op = lerpf(op, 0.1 + 0.32 * maxf(0.0, sin(_t * 5.5 + s * 1.3)), m)
	# угроза: подняты и разведены, пальцы раскрыты и дрожат
	var tw := Vector3(s * 0.17, 0.30, -0.14) + Vector3(0, sin(_t * 17.0 + s) * 0.004, 0)
	var td := Vector3(s * 0.35, 0.8, -0.5)
	var top := 0.62 + sin(_t * 9.0 + s) * 0.08
	w = w.lerp(tw, _threat)
	d = d.lerp(td, _threat)
	op = lerpf(op, top, _threat)
	# замах
	var wk := _windup * (1.0 if s == _strike_side else 0.5)
	w = w.lerp(Vector3(s * 0.2, 0.31, -0.09), wk)
	d = d.lerp(Vector3(s * 0.45, 0.85, -0.25), wk)
	op = lerpf(op, 0.8, wk)
	# щипок: выброс вперёд, резкое смыкание
	if _strike >= 0.0 and s == _strike_side:
		var k := _strike / 0.45
		var thrust := sin(minf(k * 2.2, 1.0) * PI * 0.5) * (1.0 - smoothstep(0.55, 1.0, k))
		w = w.lerp(Vector3(s * 0.07, 0.17, -0.21), thrust)
		d = d.lerp(Vector3(-s * 0.15, -0.3, -1.0), thrust)
		op = lerpf(0.8, -0.05, minf(k / 0.22, 1.0)) if k < 0.6 else lerpf(-0.05, 0.1, (k - 0.6) / 0.4)
	# кормёжка: к песку → щипок → ко рту
	if _eat >= 0.0 and s == _eat_side:
		var e := _eat
		var down_w := Vector3(s * 0.12, 0.1, -0.15)
		var down_d := Vector3(-s * 0.2, -0.9, -0.4)
		var mouth_w := Vector3(s * 0.14, 0.2, -0.18)
		var mouth_d := Vector3(-s * 0.95, 0.1, 0.15)
		if e < 0.5:
			var k1 := smoothstep(0.0, 0.5, e)
			w = w.lerp(down_w, k1)
			d = d.lerp(down_d, k1)
			op = lerpf(op, 0.55, k1)
		elif e < 0.8:
			w = down_w
			d = down_d
			op = lerpf(0.55, 0.0, smoothstep(0.5, 0.62, e))
		else:
			var k2 := smoothstep(0.8, 1.3, e) * (1.0 - smoothstep(2.0, 2.4, e))
			w = down_w.lerp(mouth_w, k2)
			d = down_d.lerp(mouth_d, k2)
			op = 0.0 + (maxf(0.0, sin(_t * 30.0)) * 0.12 if e > 1.3 and e < 2.0 else 0.0)
	# ранен — прикрывается
	var hu := _hurt_amount() * 0.7
	w = w.lerp(Vector3(s * 0.1, 0.2, -0.12), hu)
	d = d.lerp(Vector3(-s * 0.5, 0.6, -0.4), hu)
	# смерть — поджаты
	if _curl > 0.0:
		w = w.lerp(Vector3(s * 0.1, 0.15, -0.1), _curl)
		d = d.lerp(Vector3(-s * 0.85, -0.3, 0.2), _curl)
		op = lerpf(op, 0.0, _curl)
	# закопан — прижаты к телу
	w = w.lerp(Vector3(s * 0.14, 0.1, -0.12), _burrow)
	d = d.lerp(Vector3(-s * 0.4, -0.6, -0.5), _burrow)
	# сглаживание
	var rate := 26.0 if _strike >= 0.0 else (9.0 + 7.0 * m)
	var kk := clampf(dt * rate, 0.0, 1.0) if dt > 0.0 else 1.0
	var cw: Vector3 = (c["w"] as Vector3).lerp(w, kk)
	var cd: Vector3 = (c["d"] as Vector3).lerp(d.normalized(), kk).normalized()
	var co: float = lerpf(float(c["open"]), op, kk)
	c["w"] = cw
	c["d"] = cd
	c["open"] = co
	_solve_claw(c, cw, cd, co)

func _solve_claw(c: Dictionary, w: Vector3, d: Vector3, op: float) -> void:
	var bones: Array[int] = c["bones"]
	var rest: Array[Vector3] = c["pts"]
	var lens: Array[float] = c["lens"]
	# плечо + мерус: IK к запястью
	var arm_rest: Array[Vector3] = [rest[0], rest[1], rest[2]]
	var arm_lens: Array[float] = [lens[0], lens[1]]
	var p := _fabrik(arm_rest, arm_lens, w, 8)
	var g := _apply_chain(bones, arm_rest, p, 2)
	# кисть (.003) — к направлению d; .004 (неподвижный палец) — как в покое относительно кисти
	var rest_g := skel.get_bone_global_rest(bones[2])
	var d0: Vector3 = c["palm"]
	var arc := Quaternion(d0, d) if d0.dot(d) > -0.999 else Quaternion(Vector3.UP, PI)
	var palm_g := Transform3D(Basis(arc) * rest_g.basis, p[2])
	skel.set_bone_pose_rotation(bones[2], (g.affine_inverse() * palm_g).basis.get_rotation_quaternion())
	skel.set_bone_pose_rotation(bones[3], skel.get_bone_rest(bones[3]).basis.get_rotation_quaternion())
	# подвижный палец: поворот вокруг шарнира (ось — в пространстве покоя пальца); open > 0 — раскрыт
	var fi: int = c["finger"]
	if fi >= 0:
		var frest := skel.get_bone_global_rest(fi)
		var ax_local := (frest.basis.inverse() * (c["f_axis"] as Vector3)).normalized()
		var q := skel.get_bone_rest(fi).basis.get_rotation_quaternion() * Quaternion(ax_local, -op)
		skel.set_bone_pose_rotation(fi, q)

func animate_dead(a: Node, dt: float) -> void:
	super.animate_dead(a, dt)
	var flip := (1.0 - cos(model.rotation.z)) * 0.5
	model.position.y = flip * 0.3
