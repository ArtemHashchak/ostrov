class_name UserBatRig
extends Node
## Летучая мышь из пака пользователя (Птицы/Flying+Bat_FBX.zip, крылан): скан-модель без скелета →
## в Blender (tools/user_pack2/bat_prep.py, bat_rig.py) упрощена до ~3.6k треуг., выровнена и получила
## скелет: root, head, legs, wing1/wing2 с каждой стороны (гладкие веса по размаху крыла).
## Анимация — та же логика BirdAnim, что у процедурной мыши (рваные частые взмахи, кисть складывается
## на подъёме, висит вниз головой на дереве, изредка расправляет крылья): BirdAnim крутит пустые
## узлы-шарниры (как в CreatureRigs.bat), а этот узел каждый кадр переносит их повороты на кости.
## Запасной вариант — процедурная мышь: UserBatRig.use_pack = false.

const SCENE := "res://assets/user_pack/animals/bat/bat_user.glb"
const TEX := "res://assets/user_pack/animals/bat/bat_"
## Размер в игре: размах ~0.6 м (крылан средних размеров), как в исходнике.
const SCALE := 1.0

static var use_pack := true
static var _scene: PackedScene
static var _mat: StandardMaterial3D

var skel: Skeleton3D
var _pairs: Array = []        # [bone_idx, pivot: Node3D, head_body: Vector3, rest_body: Transform3D, parent_pair_idx]
var _sk_body := Transform3D.IDENTITY     # скелет → body
var _sk_body_inv := Transform3D.IDENTITY

static func available() -> bool:
	return use_pack and ResourceLoader.exists(SCENE)

static func clear_cache() -> void:
	_scene = null
	_mat = null

static func material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.albedo_texture = load(TEX + "material_0_baseColor.png")
		var nt := TEX + "material_0_normal.png"
		if ResourceLoader.exists(nt):
			_mat.normal_enabled = true
			_mat.normal_texture = load(nt)
			_mat.normal_scale = 0.7
		_mat.roughness = 0.82
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED     # перепонка видна с обеих сторон
		_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return _mat

## Модель для FaunaAnim.register_builder(&"bat", …): тот же «риг» (meta rig), что у CreatureRigs.bat.
static func build() -> Node3D:
	var r := CreatureRigs._rig_root(&"bat", 0.12)
	var root: Node3D = r[0]
	var body: Node3D = r[1]
	var rig: Dictionary = r[2]
	if _scene == null:
		_scene = load(SCENE) as PackedScene
	var turn := Node3D.new()
	turn.name = "Turn"
	turn.rotation = Vector3(0.0, PI, 0.0)
	turn.scale = Vector3.ONE * SCALE
	body.add_child(turn)
	var inst := _scene.instantiate() as Node3D
	inst.name = "UserBat"
	turn.add_child(inst)
	var f := UserBatRig.new()
	f.name = "BoneFollow"
	f.process_priority = 100
	f.skel = _find_skeleton(inst)
	for mi in _meshes(inst):
		mi.material_override = material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	root.add_child(f)
	f._build_pivots(body, turn, rig)
	rig["span"] = 0.3
	root.set_meta(&"length", 0.18)
	return root

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

func _bone_body(bi: int) -> Transform3D:
	return _sk_body * skel.get_bone_global_rest(bi)

## Шарниры как в CreatureRigs.bat (Neck, WingL/R → Hand, FootL/R), но в точках костей модели.
func _build_pivots(body: Node3D, turn: Node3D, rig: Dictionary) -> void:
	if skel == null:
		return
	var xf := skel.transform
	var p := skel.get_parent()
	while p != null and p != body:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	_sk_body = xf
	_sk_body_inv = xf.affine_inverse()
	var piv := func(parent: Node3D, nm: String, pos: Vector3) -> Node3D:
		var n := Node3D.new()
		n.name = nm
		n.position = pos
		parent.add_child(n)
		return n
	# голова
	var hb := skel.find_bone("head")
	var neck: Node3D = piv.call(body, "Neck", _bone_body(hb).origin if hb >= 0 else Vector3.ZERO)
	rig["neck"] = neck
	if hb >= 0:
		_pairs.append([hb, neck, _bone_body(hb).origin, _bone_body(hb), -1])
	# крылья: L — слева (−X после разворота), как у процедурной
	var wings: Array = []
	for side in ["L", "R"]:
		var sx := -1.0 if side == "L" else 1.0
		var b1 := skel.find_bone("wing1." + side)
		var b2 := skel.find_bone("wing2." + side)
		if b1 < 0 or b2 < 0:
			continue
		var h1 := _bone_body(b1).origin
		var h2 := _bone_body(b2).origin
		var sh: Node3D = piv.call(body, "Wing" + side, h1)
		sh.rotation_order = EULER_ORDER_ZXY
		var hand: Node3D = piv.call(sh, "Hand", h2 - h1)
		wings.append({"shoulder": sh, "hand": hand, "side": sx, "pos0": sh.position,
			"fold_pos": h1 + Vector3(-sx * 0.006, 0.0, 0.0)})
		var i1 := _pairs.size()
		_pairs.append([b1, sh, h1, _bone_body(b1), -1])
		_pairs.append([b2, hand, h2, _bone_body(b2), i1])
	rig["wings"] = wings
	# лапки (ими висит): одна кость legs — общий шарнир на обе
	var lb := skel.find_bone("legs")
	var feet: Array = []
	if lb >= 0:
		var fp: Node3D = piv.call(body, "Feet", _bone_body(lb).origin)
		feet.append(fp)
		_pairs.append([lb, fp, _bone_body(lb).origin, _bone_body(lb), -1])
	rig["feet"] = feet

func _process(_dt: float) -> void:
	if skel == null or _pairs.is_empty():
		return
	# поворот шарнира относительно body (у шарниров в покое поворот нулевой)
	var acc: Array = []
	acc.resize(_pairs.size())
	for i in _pairs.size():
		var pr: Array = _pairs[i]
		var pv := pr[1] as Node3D
		var head: Vector3 = pr[2]
		var rest: Transform3D = pr[3]
		var parent_i := int(pr[4])
		var b := pv.transform.basis
		var new_head := head
		if parent_i >= 0:
			var pa: Array = acc[parent_i]
			b = (pa[0] as Basis) * b
			# голова дочерней кости едет вместе с родительской
			new_head = (pa[1] as Vector3) + (pa[0] as Basis) * (head - (_pairs[parent_i][2] as Vector3))
		elif pv.get_parent() != null and pv.position != head:
			new_head = pv.position
		acc[i] = [b, new_head]
		var g := Transform3D(Basis.IDENTITY, new_head) * Transform3D(b, Vector3.ZERO) * Transform3D(Basis.IDENTITY, -head) * rest
		skel.set_bone_global_pose(int(pr[0]), _sk_body_inv * g)
