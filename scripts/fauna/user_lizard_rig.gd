class_name UserLizardRig
extends ReptileAnim
## Ящерица из пака пользователя (assets/user_pack/animals/lizard): скин-меш со скелетом автора
## (95 деформирующих костей: позвоночник, хвост, шея/голова, 4 лапы с кистями и пальцами).
## Одна модель на игуану и варана — разная окраска (сдвиг оттенка), размер и повадки.
## Анимация — логика ReptileAnim (позвоночник по следу головы, S-изгиб туловища в такт шагу,
## хвост бегущей волной и волочится, диагональная походка, кивки игуаны, покачивание головы варана),
## но вместо шейдерного изгиба процедурной сетки двигаются кости:
##  • позвоночник/хвост/шея/голова — каждая кость переносится кадром позвоночника в своей точке оси;
##  • лапы — корневая кость лапы поворачивается в «тазобедренном» суставе (размах и подъём шага),
##    колено и запястье чуть сгибаются на подъёме; кисти и пальцы следуют.
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
	pts.resize(N)
	for j in N:
		pts[j] = Vector3(0.0, ys, lerpf(z0, z1, float(j) / (N - 1)))
	trail.clear()
	_push()

## Вместо шейдера: кости по кадрам позвоночника.
func _push() -> void:
	if not _ready_rig or skel == null:
		return
	var rest_line := func(z: float) -> Transform3D:
		return Transform3D(Basis.IDENTITY, Vector3(0.0, ys, z))
	var D := func(z: float) -> Transform3D:
		var fr := _frame(z)
		var cur := Transform3D(Basis(fr[1], fr[2], fr[3]), fr[0])
		return cur * (rest_line.call(z) as Transform3D).affine_inverse()
	for sb in _spine_bones:
		var g: Transform3D = (D.call(float(sb[2])) as Transform3D) * (sb[1] as Transform3D)
		skel.set_bone_global_pose(int(sb[0]), _xf_inv * g)
	# лапы: поворот в тазобедренном суставе (из маркеров ReptileAnim) + сгиб колена на подъёме
	var legs: Array = rig_root.get_meta(&"legs", []) if rig_root else []
	for li in _leg_bones.size():
		var lb: Array = _leg_bones[li]
		var hip: Vector3 = lb[2]
		var rest: Transform3D = lb[1]
		var g: Transform3D = (D.call(hip.z) as Transform3D)
		var rot := Basis.IDENTITY
		if li < legs.size() and is_instance_valid(legs[li]):
			# маркер: поворот лапы относительно кадра позвоночника
			var fr := _frame(hip.z)
			var frame_b := Basis(fr[1], fr[2], fr[3])
			rot = frame_b.inverse() * (legs[li] as Node3D).transform.basis
		var about_hip := Transform3D(Basis.IDENTITY, hip) * Transform3D(rot, Vector3.ZERO) * Transform3D(Basis.IDENTITY, -hip)
		skel.set_bone_global_pose(int(lb[0]), _xf_inv * (g * about_hip * rest))
		# колено: подъём лапы (крен вокруг продольной оси) → лёгкий сгиб
		var ki := int(lb[3])
		if ki >= 0:
			var lift := absf(rot.get_euler().z)
			var kr: Transform3D = lb[4]
			skel.set_bone_pose_rotation(ki, kr.basis.get_rotation_quaternion() * Quaternion(Vector3.RIGHT, -lift * 0.9))
