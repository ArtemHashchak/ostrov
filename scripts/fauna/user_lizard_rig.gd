class_name UserLizardRig
extends ReptileAnim
## Ящерица из пака пользователя (assets/user_pack/animals/lizard): скин-меш со скелетом автора
## (95 деформирующих костей: позвоночник, хвост, шея/голова, 4 лапы с кистями и пальцами).
## Одна модель на игуану и варана — разная окраска (сдвиг оттенка), размер и повадки.
## Анимация — логика ReptileAnim (позвоночник по следу головы, S-изгиб туловища в такт шагу,
## хвост бегущей волной и волочится, диагональная походка, кивки игуаны, покачивание головы варана),
## но вместо шейдерного изгиба процедурной сетки двигаются кости:
##  • позвоночник/хвост/шея/голова — каждая кость переносится кадром позвоночника в своей точке оси;
##  • лапы — двухкостная IK (плечо/бедро → локоть/колено → запястье/лодыжка): стопа ставится на землю
##    по фазе диагональной походки (опора 60 % цикла — стопа неподвижна относительно земли, перенос —
##    дугой вверх), локти и колени развёрнуты наружу и вверх (распластанная стойка рептилии),
##    запястье держит ладонь плоско; обе стороны — к земле (поза автора несимметрична, она не используется).
##  • туловище опущено: брюхо почти на земле, хвост волочится.
## Процедурная модель остаётся запасной: UserLizardRig.use_pack = false.

const SCENE := "res://assets/user_pack/animals/lizard/lizard_user.glb"
const TEX := "res://assets/user_pack/animals/lizard/lizard_"
const SHADER := preload("res://scripts/fauna/shaders/user_lizard.gdshader")
## Длина исходника в его единицах (нос — кончик хвоста, по оси Z после разворота).
const LEG_ROOTS := ["leg_front01.l", "leg_front01.r", "leg_back01.l", "leg_back01.r"]   # FL, FR, BL, BR
const LEG_KNEES := ["leg_front02.l", "leg_front02.r", "leg_back02.l", "leg_back02.r"]

## Окраска по виду: палитра (тёмный → светлый по яркости исходника) и цвет крапа.
const LOOK := {
	&"iguana": {"dark": Color(0.2, 0.26, 0.13), "light": Color(0.66, 0.72, 0.48), "spot": Color(0.48, 0.42, 0.22), "contrast": 1.05},
	&"monitor": {"dark": Color(0.13, 0.12, 0.09), "light": Color(0.52, 0.48, 0.39), "spot": Color(0.8, 0.68, 0.36), "contrast": 1.2},
}

static var use_pack := true
static var _scene: PackedScene
static var _mats: Dictionary = {}

var skel: Skeleton3D
var _xf := Transform3D.IDENTITY          # скелет → модель
var _xf_inv := Transform3D.IDENTITY
var _spine_bones: Array = []            # [idx, rest_global_model: Transform3D, z]
var _leg_bones: Array = []              # [idx, rest_global_model, hip: Vector3, knee_idx, knee_rest_local]
var _ik: Array = []                     # лапы для IK: словари (кости 01..04, покой, длины, сторона)
var _nose_z := -0.5
var _tail_z := 0.5
var _axis_y := 0.1
var _ready_rig := false

static func available() -> bool:
	return use_pack and ResourceLoader.exists(SCENE)

static func clear_cache() -> void:
	_scene = null
	_mats.clear()

static func material(species: StringName) -> ShaderMaterial:
	if _mats.has(species):
		return _mats[species]
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter(&"albedo_tex", load(TEX + "albedo.png"))
	m.set_shader_parameter(&"normal_tex", load(TEX + "normal.png"))
	m.set_shader_parameter(&"rough_tex", load(TEX + "roughness.png"))
	var lk: Dictionary = LOOK.get(species, {})
	m.set_shader_parameter(&"use_palette", 1.0 if lk.has("dark") else 0.0)
	m.set_shader_parameter(&"col_dark", lk.get("dark", Color(0.1, 0.1, 0.1)))
	m.set_shader_parameter(&"col_light", lk.get("light", Color(0.6, 0.6, 0.6)))
	m.set_shader_parameter(&"col_spot", lk.get("spot", Color(0.5, 0.4, 0.2)))
	m.set_shader_parameter(&"contrast", float(lk.get("contrast", 1.0)))
	_mats[species] = m
	return m

## Модель (корень как у AnimalModels._root, meta "anim" = UserLizardRig на этот экземпляр).
static func make_model(species: StringName, L: float) -> Node3D:
	var root: Node3D = AnimalModels._root(species, L)
	var r := UserLizardRig.new()
	if _scene == null:
		_scene = load(SCENE) as PackedScene
	var turn := Node3D.new()
	turn.name = "Body"      # «Body» — ReptileAnim не двигает этот узел как «ребёнка»
	root.add_child(turn)
	var inst := _scene.instantiate() as Node3D
	inst.name = "UserLizard"
	turn.add_child(inst)
	r.skel = _find_skeleton(inst)
	var mat := material(species)
	for mi in _meshes(inst):
		if String(mi.name).begins_with("eye"):
			# глаза — тёмные, влажные (собственный материал автора — однотонный)
			var em := StandardMaterial3D.new()
			em.albedo_color = Color(0.05, 0.04, 0.03)
			em.roughness = 0.08
			em.metallic_specular = 0.8
			mi.material_override = em
		else:
			mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# размер: длина исходника → L; разворот носом в −Z
	var aabb := _skin_aabb(inst)
	var src_len := maxf(aabb.size.z, 1e-4)
	var k := L / src_len
	turn.rotation = Vector3(0.0, PI, 0.0)
	turn.scale = Vector3(k, k, k)
	# стопы на земле: по костям кистей/пальцев в покое (AABB скин-сетки не совпадает с позой скелета)
	r.rig_root = root
	if r.skel:
		var feet_y := INF
		var to_root := r.skel.transform
		var pp: Node = r.skel.get_parent()
		while pp != null and pp != root:
			to_root = (pp as Node3D).transform * to_root
			pp = pp.get_parent()
		for bi in r.skel.get_bone_count():
			var bn := r.skel.get_bone_name(bi)
			if bn.begins_with("hand") or bn.begins_with("finger") or bn.begins_with("finge"):
				feet_y = minf(feet_y, (to_root * r.skel.get_bone_global_rest(bi)).origin.y)
		if feet_y < INF:
			turn.position.y = -feet_y + 0.012 * L
	else:
		turn.position.y = -aabb.position.y * k
	r._prepare(root, turn)
	root.set_meta(&"anim", r)
	root.set_meta(&"body", inst)
	root.set_meta(&"length", L)
	return root

var rig_root: Node3D

static func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var s := _find_skeleton(c)
		if s:
			return s
	return null

static func _meshes(n: Node, out: Array = []) -> Array:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_meshes(c, out)
	return out

static func _skin_aabb(inst: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in _meshes(inst):
		var xf := Transform3D.IDENTITY
		var p: Node = mi
		while p != null and p != inst:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		var b := xf * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box

## Кости в пространстве модели (корня) в покое, ось позвоночника, точки тазобедренных суставов.
func _prepare(root: Node3D, turn: Node3D) -> void:
	if skel == null:
		return
	var xf := skel.transform
	var p := skel.get_parent()
	while p != null and p != root:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	_xf = xf
	_xf_inv = xf.affine_inverse()
	# нос/хвост по оси Z модели: берём крайние кости позвоночника
	var zs: Array = []
	var nb := skel.get_bone_count()
	var depth := {}
	for i in nb:
		var d := 0
		var q := skel.get_bone_parent(i)
		while q >= 0:
			d += 1
			q = skel.get_bone_parent(q)
		depth[i] = d
	var order: Array = range(nb)
	order.sort_custom(func(x, y) -> bool: return int(depth[x]) < int(depth[y]))
	var ys_acc := 0.0
	var ys_n := 0
	for i in order:
		var nm := skel.get_bone_name(i)
		var rest_g := _xf * skel.get_bone_global_rest(i)
		if nm.begins_with("Body_control") or nm.begins_with("body01") or nm.begins_with("Tail_control") \
				or nm.begins_with("neck") or nm.begins_with("head"):
			_spine_bones.append([i, rest_g, rest_g.origin.z])
			zs.append(rest_g.origin.z)
			if nm.begins_with("Body_control"):
				ys_acc += rest_g.origin.y
				ys_n += 1
	for li in LEG_ROOTS.size():
		var bi := skel.find_bone(LEG_ROOTS[li])
		var ki := skel.find_bone(LEG_KNEES[li])
		if bi < 0:
			continue
		var rg := _xf * skel.get_bone_global_rest(bi)
		_leg_bones.append([bi, rg, rg.origin, ki, skel.get_bone_rest(ki) if ki >= 0 else Transform3D.IDENTITY])
	# IK: цепочка leg_X01 (ключица/таз) → 02 (плечо/бедро) → 03 (предплечье/голень) → 04 (запястье)
	for li in LEG_ROOTS.size():
		var r1n: String = LEG_ROOTS[li]
		var pre := r1n.substr(0, r1n.length() - 4)       # "leg_front" / "leg_back"
		var suf := r1n.substr(r1n.length() - 2)          # ".l" / ".r"
		var ids: Array = []
		for k in ["01", "02", "03", "04"]:
			ids.append(skel.find_bone(pre + k + suf))
		if ids.has(-1):
			continue
		var R: Array = []
		for bi in ids:
			R.append(_xf * skel.get_bone_global_rest(int(bi)))
		# высота лодыжки над подошвой (самая низкая кость кисти/пальцев этой лапы)
		var low := INF
		for bi in nb:
			var q := skel.get_bone_parent(bi)
			while q >= 0 and q != int(ids[3]):
				q = skel.get_bone_parent(q)
			if q == int(ids[3]):
				low = minf(low, (_xf * skel.get_bone_global_rest(bi)).origin.y)
		var r2: Transform3D = R[1]
		var r3: Transform3D = R[2]
		var r4: Transform3D = R[3]
		_ik.append({
			"i": li, "ids": ids, "R": R,
			"L2": (R[0] as Transform3D).affine_inverse() * r2,
			"L3": r2.affine_inverse() * r3,
			"L4": r3.affine_inverse() * r4,
			"l1": r2.origin.distance_to(r3.origin), "l2": r3.origin.distance_to(r4.origin),
			"ankle": clampf(r4.origin.y - low, 0.0, r2.origin.distance_to(r3.origin)) if low < INF else 0.0,
			"side": signf(r2.origin.x) if absf(r2.origin.x) > 1e-5 else (-1.0 if suf == ".l" else 1.0),
			"front": li < 2,
		})
	# пары лап симметричны по длинам и высоте лодыжки (поза автора несимметрична)
	for a_ in 2:
		if _ik.size() == 4:
			var A: Dictionary = _ik[a_ * 2]
			var B: Dictionary = _ik[a_ * 2 + 1]
			for key in ["l1", "l2", "ankle"]:
				var m := (float(A[key]) + float(B[key])) * 0.5
				A[key] = m
				B[key] = m
	# ось: от кончика морды до кончика хвоста (по сетке), высота — средняя высота костей туловища
	var skin_root := skel.get_parent() as Node3D
	var mb := _skin_aabb(skin_root)
	var to_model := Transform3D.IDENTITY
	var pp: Node = skin_root
	while pp != null and pp != root:
		to_model = (pp as Node3D).transform * to_model
		pp = pp.get_parent()
	var mbm := to_model * mb
	_nose_z = mbm.position.z
	_tail_z = mbm.end.z
	_axis_y = ys_acc / maxf(1.0, ys_n)
	# маркеры лап для ReptileAnim (нужно 4 — по ним считается походка)
	var legs: Array = []
	for lb in _leg_bones:
		var mk := Node3D.new()
		mk.name = "LegMark"
		mk.position = lb[2]
		root.add_child(mk)
		legs.append(mk)
	root.set_meta(&"legs", legs)
	_ready_rig = true

func setup(an: Animal) -> void:
	super.setup(an)
	if not _ready_rig:
		return
	# ось позвоночника — по настоящей модели
	z0 = _nose_z
	z1 = _tail_z
	ys = _axis_y
	var Lm := z1 - z0
	reach = 0.11 * Lm
	stride = 0.3 * Lm
	# распластанная стойка: ось туловища низко (брюхо в паре сантиметров от земли)
	ys = minf(_axis_y, 0.068 * Lm)
	pts.resize(N)
	for j in N:
		pts[j] = Vector3(0.0, ys, lerpf(z0, z1, float(j) / (N - 1)))
	trail.clear()
	_push()

var _last_growth := -1.0

## След головы (мир) сбрасывается в прямую линию, если зверь резко вырос (set_growth) или его
## переставили по высоте (появление, телепорт): иначе позвоночник тянется к старым точкам следа —
## хвост «в земле», нос задран.
func _trail_follow(lat: float) -> void:
	var reset := absf(a.growth - _last_growth) > 0.01
	if not reset and trail.size() > 0:
		var hw := model.to_global(_head_local(lat))
		reset = absf(hw.y - trail[0].y) > (z1 - z0) * maxf(a.growth, 0.05) * 0.12
	if reset:
		_last_growth = a.growth
		for j in N:
			pts[j] = Vector3(0.0, ys, lerpf(z0, z1, float(j) / (N - 1)))
		trail.clear()
	# След «ложится» на рельеф: каждая точка следа держит ту же высоту над землёй, что и голова.
	# Иначе после появления/падения на землю старые точки следа остаются выше или ниже головы,
	# и ящерица «встаёт на дыбы» (нос вверх, хвост в земле) — особенно в покое, когда след не обновляется.
	if trail.size() > 1 and model != null and model.is_inside_tree():
		var hw := model.to_global(_head_local(lat))
		var h_head := hw.y - Fauna.ground_y_at(a, hw.x, hw.z)
		for i in range(1, trail.size()):
			var tp := trail[i]
			trail[i].y = Fauna.ground_y_at(a, tp.x, tp.z) + h_head
	super._trail_follow(lat)

## Вместо шейдера: кости по кадрам позвоночника.
func _push() -> void:
	if not _ready_rig or skel == null:
		return
	var rest_line := func(z: float) -> Transform3D:
		return Transform3D(Basis.IDENTITY, Vector3(0.0, _axis_y, z))
	var D := func(z: float) -> Transform3D:
		var fr := _frame(z)
		var cur := Transform3D(Basis(fr[1], fr[2], fr[3]), fr[0])
		return cur * (rest_line.call(z) as Transform3D).affine_inverse()
	for sb in _spine_bones:
		var g: Transform3D = (D.call(float(sb[2])) as Transform3D) * (sb[1] as Transform3D)
		skel.set_bone_global_pose(int(sb[0]), _xf_inv * g)
	# лапы: IK по фазе походки (та же схема фаз, что ReptileAnim._gait_legs)
	var Lm := z1 - z0
	var amp_z := 0.3 * stride * move_w
	var gx_ok := a != null and rig_root != null and rig_root.is_inside_tree() and a.lod == 0
	var gxf := rig_root.global_transform if gx_ok else Transform3D.IDENTITY
	var gxf_inv := gxf.affine_inverse()          # полуразмах стопы без проскальзывания (опора 60 % цикла)
	for lg: Dictionary in _ik:
		var ids: Array = lg.ids
		var R: Array = lg.R
		var hipz: float = (R[1] as Transform3D).origin.z
		var Dh: Transform3D = D.call(hipz)
		var G1: Transform3D = Dh * (R[0] as Transform3D)
		var G2: Transform3D = G1 * (lg.L2 as Transform3D)
		var S := G2.origin
		var fr := _frame(hipz)
		var X: Vector3 = fr[1]
		var T: Vector3 = fr[3]
		var i: int = lg.i
		var off := 0.0 if (i == 0 or i == 3) else 0.5
		var ph := fposmod(gait + off, 1.0)
		var sw := 0.0
		var lift := 0.0
		if ph < 0.6:
			sw = 1.0 - 2.0 * ph / 0.6
		else:
			var q := (ph - 0.6) / 0.4
			sw = -1.0 + 2.0 * smoothstep(0.0, 1.0, q)
			lift = sin(PI * q)
		var l1: float = lg.l1
		var l2: float = lg.l2
		var ank: float = lg.ankle
		var side: float = lg.side
		var front: bool = lg.front
		# стопа: в сторону (почти распрямлённая лапа по горизонтали), чуть вперёд от плеча/бедра
		var dy := maxf(S.y - ank, 0.0)
		var span := 0.84 * (l1 + l2)
		var reach_h := sqrt(maxf(span * span - dy * dy, pow(0.35 * (l1 + l2), 2.0)))
		var tgt := S + X * side * reach_h - T * ((0.02 if front else 0.06) * Lm) - T * (sw * amp_z)
		tgt.y = ank + lift * 0.05 * Lm * move_w
		# рельеф под этой лапой (склон пляжа, кочка): высота земли в точке стопы относительно земли под
		# центром зверя — в кадр модели (модель может быть наклонена по склону — переводим через мир)
		if gx_ok:
			# точка «земли модели» под стопой → по вертикали на настоящий рельеф → обратно в модель
			var wt := gxf * Vector3(tgt.x, 0.0, tgt.z)
			var lt := gxf_inv * Vector3(wt.x, Fauna.ground_y_at(a, wt.x, wt.z), wt.z)
			tgt.y += clampf(lt.y, -0.2 * Lm, 0.2 * Lm)
		# полюс: локоть — наружу, вверх и назад; колено — наружу, вверх и вперёд
		var pole := S + X * side * 1.0 + Vector3.UP * 0.8 + T * (0.35 if front else -0.35)
		var K := _ik_knee(S, tgt, l1, l2, pole)
		var G2n := Transform3D(_aim(G2.basis, (G2 * (lg.L3 as Transform3D)).origin - S, K - S), S)
		var G3: Transform3D = G2n * (lg.L3 as Transform3D)
		var G3n := Transform3D(_aim(G3.basis, (G3 * (lg.L4 as Transform3D)).origin - G3.origin, tgt - K), K)
		# запястье: ладонь плоско (ориентация покоя в кадре туловища), пальцы чуть наружу
		var flat := Basis(Vector3.UP, -side * 0.35) * Dh.basis.orthonormalized() * (R[3] as Transform3D).basis
		var G4 := Transform3D(flat, (G3n * (lg.L4 as Transform3D)).origin)
		skel.set_bone_global_pose(int(ids[0]), _xf_inv * G1)
		skel.set_bone_global_pose(int(ids[1]), _xf_inv * G2n)
		skel.set_bone_global_pose(int(ids[2]), _xf_inv * G3n)
		skel.set_bone_global_pose(int(ids[3]), _xf_inv * G4)

## Повернуть базис так, чтобы направление from перешло в to (кратчайший поворот; масштаб сохраняется).
static func _aim(b: Basis, from: Vector3, to: Vector3) -> Basis:
	if from.length_squared() < 1e-12 or to.length_squared() < 1e-12:
		return b
	var f := from.normalized()
	var t := to.normalized()
	var ax := f.cross(t)
	var d := clampf(f.dot(t), -1.0, 1.0)
	if ax.length_squared() < 1e-12:
		return b
	return Basis(ax.normalized(), acos(d)) * b

## Двухкостная IK: точка колена/локтя K при плече S, цели T, длинах l1, l2 и полюсе P.
static func _ik_knee(S: Vector3, T: Vector3, l1: float, l2: float, P: Vector3) -> Vector3:
	var v := T - S
	var d := clampf(v.length(), absf(l1 - l2) + 1e-5, (l1 + l2) * 0.999)
	var dir := v.normalized() if v.length_squared() > 1e-12 else Vector3.DOWN
	var aa := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - aa * aa, 0.0))
	var pv := (P - S) - dir * (P - S).dot(dir)
	pv = pv.normalized() if pv.length_squared() > 1e-12 else Vector3.UP
	return S + dir * aa + pv * h
