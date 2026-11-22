class_name UserSpiderRig
extends UserCrabRig
## Паук-птицеед из пака пользователя (Насекомые/Паук-птицеед/Паук_птицеед.blend): скин-меш автора
## (тело 14.4k треуг. + 4.1k карточек волосков) со скелетом автора (64 деформирующие кости: тело,
## брюшко, хелицеры с клыками, 8 ног × 6 члеников, педипальпы). В GLB переведён без упрощения
## (tools/user_pack3/spider_export.py): процедурные материалы автора запечены в альбедо/нормали.
## Анимация — логика ArthropodRig для паука (чередующиеся тетраподы, дыбы с поднятыми передними
## ногами, укус с раскрытием хелицер, кормёжка, смерть с поджатыми ногами), кости — FABRIK-IK
## (как у краба пака): цепь бедро → колено → голень → плюсна → лапка, тазик закреплён.
## Лазанье по стволам и прыжок вниз — в Animal (состояния to_tree / climb / on_tree / jump);
## в прыжке ноги расставлены вперёд-в стороны (_air).

const SPIDER_SCENE := "res://assets/user_pack/animals/spider/spider_tarantula.glb"
const FUR_SHADER := preload("res://scripts/fauna/shaders/user_spider_fur.gdshader")
const K := 0.2            # модель автора (размах ног 1.1) → ≈ 0.22 м
const LEG_CHAIN := ["femur", "patella", "tibia", "metatarsus", "tarsus"]

static var use_spider := true
static var _sp_scene: PackedScene
static var _fur_mat: ShaderMaterial

var _air: float = 0.0           # 0 — на опоре, 1 — в прыжке
var _chel: Array = []           # [bone, rest_q, side]
var _fang_b: Array = []
var _palps: Array = []          # [bones, rest_q]

static func spider_available() -> bool:
	return use_spider and ResourceLoader.exists(SPIDER_SCENE)

static func fur_material(tex: Texture2D) -> ShaderMaterial:
	if _fur_mat == null:
		_fur_mat = ShaderMaterial.new()
		_fur_mat.shader = FUR_SHADER
		_fur_mat.set_shader_parameter(&"hair_tex", tex)
	return _fur_mat

static func make_spider(root: Node3D) -> UserSpiderRig:
	var r := UserSpiderRig.new()
	r.kind = &"spider"
	r.scale_k = 0.45
	r.rest_h = 0.0
	r.rig = _node(root, "Rig", Vector3.ZERO)
	if _sp_scene == null:
		_sp_scene = load(SPIDER_SCENE) as PackedScene
	var turn := _node(r.rig, "Body", Vector3.ZERO)   # «Rig/Body» — как у остальных моделей
	turn.rotation.y = PI          # у автора — головой в +Z
	turn.scale = Vector3.ONE * K
	var inst := _sp_scene.instantiate() as Node3D
	inst.name = "Tarantula"
	turn.add_child(inst)
	root.set_meta(&"body", inst)
	r.skel = _find_skeleton(inst)
	for mi: MeshInstance3D in _meshes(inst):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if String(mi.name).contains("Fur"):
			var sm := mi.mesh.surface_get_material(0) as StandardMaterial3D
			mi.material_override = fur_material(sm.albedo_texture if sm else null)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var xf := r.skel.transform
	var p := r.skel.get_parent()
	while p != null and p != r.rig:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	r._skel_xf = xf
	r._skel_inv = xf.affine_inverse()
	# ноги: порядок как у ArthropodRig.build_spider (пара 1 −x, +x, пара 2 …) — li < 4 поднимаются на дыбах
	for i in 4:
		for sx: float in [-1.0, 1.0]:
			# в пространстве Rig +x — это «.R» автора (модель развёрнута)
			var suf := ".R" if sx > 0.0 else ".L"
			var bones: Array[int] = []
			var pts: Array[Vector3] = []
			for seg: String in LEG_CHAIN:
				var bi := r.skel.find_bone("leg%d.%s%s" % [i + 1, seg, suf])
				bones.append(bi)
				pts.append(r.skel.get_bone_global_rest(bi).origin)
			var tg := r.skel.get_bone_global_rest(bones[4])
			var ty := tg.basis.y.normalized()
			pts.append(tg.origin + ty * (tg.origin.y / maxf(-ty.y, 0.05)))   # кончик лапки — на земле
			var lens: Array[float] = []
			for k in 5:
				lens.append(pts[k].distance_to(pts[k + 1]))
			var tip: Vector3 = xf * pts[5]
			var rest := Vector3(tip.x, 0.0, tip.z)
			var grp := 0.0 if ((i % 2 == 0) == (sx < 0.0)) else 0.5
			r.legs.append({"hip": xf * pts[0], "rest": rest, "a": lens[0], "b": lens[1] + lens[2] + lens[3] + lens[4],
				"fem": _node(r.rig, "LegF", Vector3.ZERO), "tib": _node(r.rig, "LegT", Vector3.ZERO),
				"side": signf((xf * pts[0]).x), "ph": grp + i * 0.07, "lift": 0.024,
				"cur": rest, "bones": bones, "pts": pts, "lens": lens, "idx": i})
	# хелицеры и клыки (раскрываются на дыбах и при укусе), педипальпы (пощупывают)
	for suf: String in [".L", ".R"]:
		var cb := r.skel.find_bone("chelicera" + suf)
		var fb := r.skel.find_bone("fang" + suf)
		r._chel.append([cb, r.skel.get_bone_rest(cb).basis.get_rotation_quaternion()])
		r._fang_b.append([fb, r.skel.get_bone_rest(fb).basis.get_rotation_quaternion(), 1.0 if suf == ".L" else -1.0])
		var pb: Array = []
		for seg: String in ["femur", "patella", "tibia"]:
			var bi := r.skel.find_bone("palp.%s%s" % [seg, suf])
			pb.append([bi, r.skel.get_bone_rest(bi).basis.get_rotation_quaternion()])
		r._palps.append(pb)
	r._finish(root)
	return r

func animate(a: Node, dt: float) -> void:
	var an := a as Animal
	_air = move_toward(_air, 1.0 if an.state == &"jump" else 0.0, dt * 6.0)
	super.animate(a, dt)

## Лапка: FABRIK по 5 члеников; в прыжке — расставлены вперёд-в стороны и чуть вниз.
func _solve_leg(l: Dictionary, foot: Vector3, simple: bool) -> void:
	# дыбы: передняя пара вверх-вперёд под ~45°, вторая — наполовину (цель ArthropodRig рассчитана на
	# короткие ноги процедурного паука — длинные лапы автора вытягивались свечкой)
	if _threat > 0.01 and int(l.get("idx", 9)) < 2:
		var hip: Vector3 = l["hip"]
		var rest_r: Vector3 = rig.transform.affine_inverse() * (l["rest"] as Vector3)   # стопа на земле
		var out := Vector3((l["rest"] as Vector3).x - hip.x, 0.0, (l["rest"] as Vector3).z - hip.z)
		var reach := out.length()
		var w := _threat * (1.0 if int(l["idx"]) == 0 else 0.45)
		var raised := hip + out.normalized() * reach * 0.62 + Vector3(0.0, reach * (0.55 if int(l["idx"]) == 0 else 0.3), 0.0)
		foot = rest_r.lerp(raised, w)
	if _air > 0.0:
		var hip: Vector3 = l["hip"]
		var rest: Vector3 = l["rest"]
		var spread := hip + (rest - hip) * Vector3(1.05, 0.0, 1.25) + Vector3(0.0, -0.012, 0.0)
		foot = foot.lerp(spread, _air)
	var target := _skel_inv * foot
	var pts: Array[Vector3] = l["pts"]
	var p := _fabrik(pts, l["lens"], target, 3 if simple else 8)
	_apply_chain(l["bones"], pts, p, 5)

func animate_dead(a: Node, dt: float) -> void:
	super.animate_dead(a, dt)
	var flip := (1.0 - cos(model.rotation.z)) * 0.5
	model.position.y = flip * 0.05     # перевёрнутый паук лежит на спине (у краба — выше)

func _pose(speed: float, dt: float, simple: bool) -> void:
	super._pose(speed, dt, simple)
	if simple:
		return
	# хелицеры: опускаются и раскрывают клыки (угроза, укус); педипальпы пощупывают землю
	var open := _threat * 0.6 + (sin(minf(_strike / 0.25, 1.0) * PI) * 0.8 if _strike >= 0.0 else 0.0)
	for c: Array in _chel:
		skel.set_bone_pose_rotation(int(c[0]), (c[1] as Quaternion) * Quaternion(Vector3.RIGHT, open * 0.45))
	for f: Array in _fang_b:
		skel.set_bone_pose_rotation(int(f[0]), (f[1] as Quaternion) * Quaternion(Vector3.RIGHT, -open * 1.1))
	for i in _palps.size():
		var pb: Array = _palps[i]
		var w := sin(_t * 5.0 + i * 1.9) * 0.18 * (1.0 - _threat) + _threat * 0.5
		for k in pb.size():
			var b: Array = pb[k]
			skel.set_bone_pose_rotation(int(b[0]), (b[1] as Quaternion) * Quaternion(Vector3.RIGHT, w * (1.0 if k == 0 else 0.5)))
