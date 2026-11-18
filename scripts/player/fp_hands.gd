class_name FPHands
extends Node3D
## Руки от первого лица. Меш — цельная скиннинговая модель кисти и предплечья
## (tools/gen_fp_hands.py → assets/models/fp_hands/fp_arm.json): гладкая кожа с
## сухожилиями, венами, костяшками и ногтями, рукав с закатанным краем, часы на
## левой руке. Пальцы — кости Skeleton3D, позы хвата задаются процедурно.
## Шейдер кожи — fp_skin.gdshader (поры, SSS в Forward+).
##
## Анимации в коде: покой/шаг/бег/усталость (синусоида с затуханием), инерция от
## поворота камеры, перехват предмета при смене слота, замах/удар (топор), выпад
## (копьё), удар кулаком, «съесть/выпить», несение бревна, гребки при плавании.
## COMBAT задаёт позы оружия через pose_* (положение и поворот рук в осях Hands).

signal swing_impact
signal swing_finished
signal use_finished

const SWING_TIME := 0.62
const THRUST_TIME := 0.5
const PUNCH_TIME := 0.42
const USE_TIME := 0.9
const IMPACT_AT := 0.45 # доля длительности, когда наносится удар
const SWAP_DOWN := 0.15
const SWAP_UP := 0.2

const MODEL := "res://assets/models/fp_hands/fp_arm.json"
## Где в осях кисти (запястье в 0) лежит ось кулака — сюда ставится рукоять.
const GRIP := Vector3(0.0, -0.029, -0.08)
## Положение запястья в осях руки: ось кулака попадает в (0, 0.025, -0.115) — там,
## где её ждут позы COMBAT.
const WRIST := Vector3(0.0, 0.054, -0.035)
const SLEEVE_TINT := Color(0.43, 0.42, 0.33)
const SKIN_TINT := Color(1.0, 1.0, 1.0)

enum Swing { ARC, THRUST, PUNCH }

## Позы пальцев: [б.палец: поворот к ладони (противопоставление), сгиб пясти, сгиб 1, сгиб 2; затем
## указательный, средний, безымянный, мизинец: разведение, сгиб 1, 2, 3] —
## градусы, добавка к позе покоя меша.
const GRIPS := {
	&"relax": [15, 8, 10, 8, 4, 12, 18, 10, 1, 14, 20, 12, -2, 17, 23, 13, -5, 21, 27, 15],
	&"fist": [60, 45, 45, 35, 5, 84, 100, 58, 1, 86, 102, 60, -3, 88, 102, 62, -7, 90, 100, 60],
	&"handle": [60, 40, 40, 30, 4, 46, 58, 30, 0, 48, 60, 30, -3, 50, 60, 32, -7, 54, 62, 32],
	&"round": [40, 20, 12, 10, 0, 26, 30, 16, 0, 28, 32, 18, 0, 30, 34, 18, 0, 32, 36, 20],
	&"flat": [-5, -4, 0, 0, 2, -6, 2, 2, 0, -6, 2, 2, -1, -6, 2, 2, -3, -4, 4, 4],
	&"pinch": [50, 30, 30, 24, 3, 26, 62, 28, 0, 30, 66, 32, -3, 80, 98, 56, -7, 84, 96, 56],
	&"forend": [30, 14, 8, 6, 3, 36, 40, 22, 0, 38, 42, 24, -2, 42, 46, 26, -5, 46, 50, 28],
}
const FINGER_BONES := [
	[&"thumb1", &"thumb2", &"thumb3"],
	[&"index1", &"index2", &"index3"],
	[&"middle1", &"middle2", &"middle3"],
	[&"ring1", &"ring2", &"ring3"],
	[&"pinky1", &"pinky2", &"pinky3"],
]

static var _model: Dictionary = {}     # разобранный JSON + готовые меши (общие для всех рук)

var right_arm: Node3D
var left_arm: Node3D
var held_root: Node3D   # модель предмета в правой руке
var log_mesh: MeshInstance3D
var held_id: StringName = &"__none__"

var _swinging: bool = false
var _swing_kind: Swing = Swing.ARC
var _swing_t: float = 0.0
var _swing_len: float = SWING_TIME
var _impact_sent: bool = false
var _using: bool = false
var _use_t: float = 0.0
var _carry: float = 0.0
var _carry_on: bool = false
var _t: float = 0.0
var _hidden_items: bool = false
var _skin_mat: ShaderMaterial
var _sleeve_mat: StandardMaterial3D
var _skel_r: Skeleton3D
var _skel_l: Skeleton3D
var _grip_r: PackedFloat32Array
var _grip_l: PackedFloat32Array
var _hold: StringName = &"empty"
# перехват при смене предмета
var _swap_t: float = -1.0
var _old_held: Node3D
# инерция/покачивание
var _prev_cam: Basis = Basis.IDENTITY
var _cam_init := false
var _sway_p := Vector3.ZERO
var _sway_pv := Vector3.ZERO
var _sway_r := Vector3.ZERO
var _sway_rv := Vector3.ZERO
var _phase := 0.0
var _walk_amp := 0.0
var _run_amp := 0.0
var _was_floor := true
var _first_frame := true
# COMBAT: поза оружия (CombatController задаёт каждый кадр; pose_w=0 — обычные руки).
var pose_w := 0.0
var pose_bob := 1.0
var pose_r := Vector3.ZERO
var pose_l := Vector3.ZERO
var pose_rr := Vector3.ZERO
var pose_lr := Vector3.ZERO

func _ready() -> void:
	_load_model()
	_skin_mat = ShaderMaterial.new()
	_skin_mat.shader = load("res://scripts/player/fp_skin.gdshader") as Shader
	_skin_mat.set_shader_parameter(&"tint", SKIN_TINT)
	# Рубашка из плотного хлопка: цвет свой, от Fabric004 — только переплетение (нормали).
	_sleeve_mat = StandardMaterial3D.new()
	_sleeve_mat.albedo_color = SLEEVE_TINT
	_sleeve_mat.vertex_color_use_as_albedo = true
	_sleeve_mat.roughness = 0.92
	var weave := HeldModels._t("Fabric004", "normal")
	if weave:
		_sleeve_mat.normal_enabled = true
		_sleeve_mat.normal_texture = weave
		_sleeve_mat.normal_scale = 0.7
	_sleeve_mat.uv1_scale = Vector3(6.0, 6.0, 1.0)
	_sleeve_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	right_arm = _make_arm(true)
	left_arm = _make_arm(false)
	add_child(right_arm)
	add_child(left_arm)
	right_arm.position = Vector3(0.22, -0.3, -0.42)
	left_arm.position = Vector3(-0.22, -0.32, -0.44)
	held_root = Node3D.new()
	held_root.name = "Held"
	right_arm.get_node(^"Hand").add_child(held_root)
	_grip_r = _grip_array(&"relax")
	_grip_l = _grip_array(&"relax")
	set_held(&"")
	log_mesh = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.13
	cyl.bottom_radius = 0.15
	cyl.height = 1.9
	cyl.radial_segments = 14
	log_mesh.mesh = cyl
	log_mesh.material_override = HeldModels.pbr("bark_brown_02", Vector3(1.0, 3.0, 1.0))
	log_mesh.rotation = Vector3(PI / 2.0, 0.0, 0.0)
	log_mesh.position = Vector3(0.46, -0.2, -0.22)
	log_mesh.visible = false
	add_child(log_mesh)
	_disable_shadows(self)
	_apply_grip(_skel_r, _grip_r, false)
	_apply_grip(_skel_l, _grip_l, true)

# ======================= модель =======================

static func _arr_f(s: String) -> PackedFloat32Array:
	return Marshalls.base64_to_raw(s).to_float32_array()

static func _arr_i(s: String) -> PackedInt32Array:
	return Marshalls.base64_to_raw(s).to_int32_array()

static func _v3(a: PackedFloat32Array, mirror: bool) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(a.size() / 3)
	var sx := -1.0 if mirror else 1.0
	for i in out.size():
		out[i] = Vector3(a[i * 3] * sx, a[i * 3 + 1], a[i * 3 + 2])
	return out

static func _v2(a: PackedFloat32Array, mirror_x: bool) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(a.size() / 2)
	var sx := -1.0 if mirror_x else 1.0
	for i in out.size():
		out[i] = Vector2(a[i * 2] * sx, a[i * 2 + 1])
	return out

static func _colors(a: PackedFloat32Array) -> PackedColorArray:
	var out := PackedColorArray()
	out.resize(a.size() / 4)
	for i in out.size():
		out[i] = Color(a[i * 4], a[i * 4 + 1], a[i * 4 + 2], a[i * 4 + 3])
	return out

## Индексы: в файле — против часовой снаружи; Godot ждёт по часовой. У зеркальной
## (левой) руки обход и так меняется.
static func _indices(a: PackedInt32Array, mirror: bool) -> PackedInt32Array:
	if mirror:
		return a
	var out := a.duplicate()
	for i in range(0, out.size(), 3):
		out[i + 1] = a[i + 2]
		out[i + 2] = a[i + 1]
	return out

static func _surface(s: Dictionary, mirror: bool, skinned: bool) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = _v3(_arr_f(s.pos), mirror)
	arr[Mesh.ARRAY_NORMAL] = _v3(_arr_f(s.nrm), mirror)
	if s.has("col"):
		arr[Mesh.ARRAY_COLOR] = _colors(_arr_f(s.col))
	if s.has("uv"):
		arr[Mesh.ARRAY_TEX_UV] = _v2(_arr_f(s.uv), mirror and skinned)
	if s.has("uv2"):
		arr[Mesh.ARRAY_TEX_UV2] = _v2(_arr_f(s.uv2), false)
	if skinned:
		arr[Mesh.ARRAY_BONES] = _arr_i(s.bones)
		arr[Mesh.ARRAY_WEIGHTS] = _arr_f(s.weights)
	arr[Mesh.ARRAY_INDEX] = _indices(_arr_i(s.idx), mirror)
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

static func _load_model() -> void:
	if not _model.is_empty():
		return
	var f := FileAccess.open(MODEL, FileAccess.READ)
	if f == null:
		push_error("FPHands: нет модели рук " + MODEL)
		return
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	_model["bones"] = d.bones
	var surf: Dictionary = d.surfaces
	for mirror: bool in [false, true]:
		var sfx := "_l" if mirror else "_r"
		_model["skin" + sfx] = _surface(surf.skin, mirror, true)
		# рукав и часы привязаны к предплечью — тоже скиннинг (вес 1 на кость 0)
		_model["sleeve" + sfx] = _rigid_skinned(surf.sleeve, mirror)
		_model["watch" + sfx] = _rigid_skinned(surf.watch, mirror)
	var w: Dictionary = surf.watch
	_model["watch_face"] = Vector3(w.face_pos[0], w.face_pos[1], w.face_pos[2])
	_model["watch_up"] = Vector3(w.face_up[0], w.face_up[1], w.face_up[2])

static func _rigid_skinned(s: Dictionary, mirror: bool) -> ArrayMesh:
	return _surface(s, mirror, false)

static func _mirror_xf(t: Transform3D) -> Transform3D:
	var m := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
	return Transform3D(m * t.basis * m, Vector3(-t.origin.x, t.origin.y, t.origin.z))

func _make_arm(right: bool) -> Node3D:
	var arm := Node3D.new()
	arm.name = "RightArm" if right else "LeftArm"
	var skel := Skeleton3D.new()
	skel.name = "Skeleton"
	skel.position = Vector3(-WRIST.x if not right else WRIST.x, WRIST.y, WRIST.z)
	arm.add_child(skel)
	var bones: Array = _model.get("bones", [])
	var globals: Array[Transform3D] = []
	for b: Dictionary in bones:
		var bs: Array = b.basis
		var g := Transform3D(Basis(Vector3(bs[0][0], bs[0][1], bs[0][2]), Vector3(bs[1][0], bs[1][1], bs[1][2]),
				Vector3(bs[2][0], bs[2][1], bs[2][2])), Vector3(b.origin[0], b.origin[1], b.origin[2]))
		if not right:
			g = _mirror_xf(g)
		globals.append(g)
		var idx := skel.add_bone(String(b.name))
		var par := int(b.parent)
		if par >= 0:
			skel.set_bone_parent(idx, par)
			skel.set_bone_rest(idx, globals[par].affine_inverse() * g)
		else:
			skel.set_bone_rest(idx, g)
	skel.reset_bone_poses()
	if right:
		_skel_r = skel
	else:
		_skel_l = skel
	var sfx := "_r" if right else "_l"
	if _model.has("skin" + sfx):
		var skin := MeshInstance3D.new()
		skin.name = "Skin"
		skin.mesh = _model["skin" + sfx]
		skin.material_override = _skin_mat
		skel.add_child(skin)
		skin.skeleton = NodePath("..")
		skin.skin = skel.create_skin_from_rest_transforms()
		# Рукав и часы неподвижны относительно предплечья — обычные меши.
		var sleeve := MeshInstance3D.new()
		sleeve.name = "Sleeve"
		sleeve.mesh = _model["sleeve" + sfx]
		sleeve.material_override = _sleeve_mat
		skel.add_child(sleeve)
		if not right:
			var strap := MeshInstance3D.new()
			strap.name = "WatchStrap"
			strap.mesh = _model["watch" + sfx]
			strap.material_override = HeldModels.color_mat(Color(0.13, 0.1, 0.08), 0.75)
			skel.add_child(strap)
			var fp: Vector3 = _model["watch_face"]
			var up: Vector3 = _model["watch_up"]
			fp.x = -fp.x
			up.x = -up.x
			var case_mi := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.0155
			cm.bottom_radius = 0.0165
			cm.height = 0.008
			cm.radial_segments = 24
			case_mi.mesh = cm
			case_mi.material_override = HeldModels.color_mat(Color(0.55, 0.56, 0.58), 0.3, 0.9)
			skel.add_child(case_mi)
			case_mi.position = fp
			case_mi.basis = _basis_y(up)
			var glass := MeshInstance3D.new()
			var gm := CylinderMesh.new()
			gm.top_radius = 0.0128
			gm.bottom_radius = 0.0128
			gm.height = 0.002
			gm.radial_segments = 24
			glass.mesh = gm
			glass.material_override = HeldModels.color_mat(Color(0.07, 0.08, 0.09), 0.08, 0.2)
			glass.position = Vector3(0, 0.0045, 0)
			case_mi.add_child(glass)
	# Кисть: точка хвата (ось кулака), к ней крепятся предметы.
	var hand := Node3D.new()
	hand.name = "Hand"
	hand.position = skel.position + Vector3(GRIP.x * (1.0 if right else -1.0), GRIP.y, GRIP.z)
	arm.add_child(hand)
	return arm

static func _basis_y(up: Vector3) -> Basis:
	var y := up.normalized()
	var x := Vector3(0, 0, -1).cross(y).normalized()
	if x.length() < 0.5:
		x = Vector3.RIGHT
	var z := x.cross(y).normalized()
	return Basis(x, y, z)

func _disable_shadows(n: Node) -> void:
	for c in n.get_children():
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_disable_shadows(c)

# ======================= пальцы =======================

static func _grip_array(name: StringName) -> PackedFloat32Array:
	var src: Array = GRIPS.get(name, GRIPS[&"relax"])
	var out := PackedFloat32Array()
	for v in src:
		out.append(deg_to_rad(float(v)))
	return out

func _apply_grip(skel: Skeleton3D, g: PackedFloat32Array, mirror: bool) -> void:
	if skel == null or skel.get_bone_count() < 17:
		return
	var sgn := -1.0 if mirror else 1.0
	for f in 5:
		var names: Array = FINGER_BONES[f]
		for j in 3:
			var bi := skel.find_bone(String(names[j]))
			if bi < 0:
				continue
			var rest := skel.get_bone_rest(bi).basis.get_rotation_quaternion()
			var q := Quaternion(Vector3.RIGHT, -g[f * 4 + 1 + j])
			if j == 0 and f > 0:
				q = Quaternion(Vector3.UP, g[f * 4] * sgn) * q
			elif j == 0:
				q = Quaternion(Vector3.BACK, g[0] * sgn) * q
			skel.set_bone_pose_rotation(bi, rest * q)

func _grip_for(id: StringName) -> StringName:
	if id == &"":
		return &"relax"
	if id == &"water_bottle":
		return &"handle"
	if id in [&"coconut", &"rock", &"stone", &"meat_raw", &"meat_cooked", &"fish_raw", &"rope", &"fiber",
			&"cloth", &"bandage"]:
		return &"round"
	if id == &"leaf":
		return &"pinch"
	if id == &"bow":
		return &"pinch"
	return &"handle"

func _left_grip_for(id: StringName) -> StringName:
	if id == &"bow":
		return &"handle"
	if Combat.is_weapon(id):
		var t: StringName = Combat.weapon(id).get("type", &"")
		if t in [&"gun", &"crossbow"] and id != &"pistol":
			return &"forend"
	return &"relax"

# ======================= предмет в руке =======================

## Модель предмета в правой руке (id из Items; "" — пустая рука).
func set_held(id: StringName) -> void:
	if id == held_id:
		return
	var first := held_id == &"__none__"
	held_id = id
	# Перехват: старый предмет уходит вниз вместе с рукой, новый появляется снизу.
	if _old_held:
		_old_held.queue_free()
		_old_held = null
	if not first and held_root.get_child_count() > 0:
		_old_held = Node3D.new()
		_old_held.name = "HeldOld"
		held_root.get_parent().add_child(_old_held)
		_old_held.transform = held_root.transform
		for c in held_root.get_children():
			c.reparent(_old_held, false)
	for c in held_root.get_children():
		c.queue_free()
	if id != &"":
		var m := HeldModels.build(id)
		held_root.add_child(m)
		_place_item(m, id)
	_hold = _hold_for(id)
	_swap_t = -1.0 if first else 0.0
	_update_held_visible()

func _place_item(m: Node3D, id: StringName) -> void:
	# Ось кулака — X кисти; большой палец у правой руки в сторону -X. Рукоять
	# проходит сквозь кулак: навершие к большому пальцу и чуть вперёд.
	if id in [&"axe_crude", &"axe_modern", &"stick", &"club", &"flag"]:
		m.basis = _grip_basis(Vector3(-0.94, 0.0, -0.34), Vector3(-0.34, 0.0, 0.94))
		m.position = Vector3(0.0, 0.0, 0.0)
	elif id == &"spear":
		# копьё лежит в кулаке, древко вперёд к цели, держим ближе к середине
		m.basis = _grip_basis(Vector3(-0.5, 0.05, -0.86), Vector3(0.0, 1.0, 0.0))
		m.position = Vector3(0.38, -0.02, 0.62) * 0.55
	elif id == &"water_bottle":
		# бутылка стоймя в кулаке (кулак ребром — горлышко вверх)
		m.basis = _grip_basis(Vector3(-1.0, 0.0, -0.12), Vector3(0.0, 1.0, 0.0))
		m.position = Vector3(0.05, 0.0, 0.0)
	elif _hold_for(id) == &"item":
		# на ладони: центр предмета под ладонью (ладонь — сторона -Y кисти)
		m.position = Vector3(0.0, -0.1, 0.03)

## Базис предмета: ось Y (рукоять) по up, -Z (лезвие) — от back.
static func _grip_basis(up: Vector3, back: Vector3) -> Basis:
	var y := up.normalized()
	var x := y.cross(back.normalized()).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)

func _hold_for(id: StringName) -> StringName:
	if id == &"":
		return &"empty"
	if id in [&"axe_crude", &"axe_modern", &"stick", &"club", &"flag"]:
		return &"tool"
	if id == &"spear":
		return &"spear"
	if Combat.is_weapon(id):
		return &"weapon"
	if id == &"water_bottle":
		return &"tool_item"
	return &"item"

func _update_held_visible() -> void:
	var show := not _hidden_items and not _carry_on
	held_root.visible = show and (_swap_t < 0.0 or _swap_t >= SWAP_DOWN)
	if _old_held:
		_old_held.visible = show

func swing_kind_for(id: StringName) -> Swing:
	if id == &"spear":
		return Swing.THRUST
	if id == &"":
		return Swing.PUNCH
	return Swing.ARC

func play_swing(kind: Swing = Swing.ARC) -> void:
	if _swinging or _using:
		return
	_finish_swap()
	_swinging = true
	_swing_kind = kind
	_swing_len = SWING_TIME if kind == Swing.ARC else (THRUST_TIME if kind == Swing.THRUST else PUNCH_TIME)
	_swing_t = 0.0
	_impact_sent = false

func is_swinging() -> bool:
	return _swinging

func is_busy() -> bool:
	return _swinging or _using

## «Использовать» — поднести ко рту (еда/питьё).
func play_use() -> void:
	if _swinging or _using:
		return
	_finish_swap()
	_using = true
	_use_t = 0.0

func set_carry(on: bool) -> void:
	_carry_on = on
	log_mesh.visible = on
	_update_held_visible()

func set_items_hidden(on: bool) -> void:
	if on == _hidden_items:
		return
	_hidden_items = on
	_update_held_visible()

func _finish_swap() -> void:
	if _swap_t >= 0.0:
		_swap_t = -1.0
		if _old_held:
			_old_held.queue_free()
			_old_held = null
		_update_held_visible()

# ======================= анимация =======================

static func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

## Импульс 0→1→0 на отрезке [a, b] с плавными краями.
static func _bump(p: float, a: float, peak: float, b: float) -> float:
	if p <= a or p >= b:
		return 0.0
	if p < peak:
		return _ease((p - a) / (peak - a))
	return 1.0 - _ease((p - peak) / (b - peak))

func _spring(x: Vector3, v: Vector3, target: Vector3, omega: float, zeta: float, dt: float) -> Array:
	var acc := (target - x) * omega * omega - v * 2.0 * zeta * omega
	v += acc * dt
	x += v * dt
	return [x, v]

## Вызывается игроком каждый кадр.
func animate(delta: float, speed01: float, sprinting: bool, tired: float, on_floor: bool, _carrying: bool, swimming: bool = false) -> void:
	delta = minf(delta, 0.05)
	_t += delta
	_carry = move_toward(_carry, 1.0 if _carry_on else 0.0, delta * 3.5)
	var run := 1.0 if sprinting and speed01 > 0.3 else 0.0
	_run_amp = move_toward(_run_amp, run, delta * 4.0)
	# Шаг: фаза идёт со скоростью, амплитуда затухает плавно (не замирает посреди шага).
	var moving := speed01 if on_floor and not swimming else 0.0
	_walk_amp = lerpf(_walk_amp, moving, clampf(delta * 5.0, 0.0, 1.0))
	_phase += delta * lerpf(7.2, 10.4, _run_amp) * (0.35 + 0.65 * clampf(speed01 * 1.5, 0.0, 1.0))
	var sx := sin(_phase) * _walk_amp
	var sy := cos(_phase * 2.0) * _walk_amp
	var bob := Vector3(sx * (0.011 + 0.01 * _run_amp), -absf(sin(_phase)) * _walk_amp * (0.012 + 0.016 * _run_amp) + sy * 0.003, 0.0)
	var bob_rot := Vector3(sy * 0.012, sx * 0.02, sx * (0.025 + 0.03 * _run_amp))
	var breath_f := 1.5 + 2.6 * tired
	var breath := sin(_t * breath_f) * (0.0025 + 0.006 * tired)
	# FOV: при широком угле руки ближе к центру, чтобы не обрезались по краям.
	var fov_k := tan(deg_to_rad(clampf(Settings.fov, 50.0, 110.0)) * 0.5) / tan(deg_to_rad(75.0) * 0.5)
	var spread := lerpf(1.0, 1.0 / fov_k, 0.55)
	var g_r: StringName = _grip_for(held_id)
	var g_l: StringName = _left_grip_for(held_id)
	var base_r: Vector3
	var base_l: Vector3
	var rr: Vector3
	var lr: Vector3
	match _hold:
		&"empty":
			base_r = Vector3(0.2, -0.29, -0.4)
			base_l = Vector3(-0.21, -0.3, -0.41)
			rr = Vector3(deg_to_rad(10.0), deg_to_rad(16.0), deg_to_rad(-22.0))
			lr = Vector3(deg_to_rad(10.0), deg_to_rad(-16.0), deg_to_rad(22.0))
		&"tool":
			base_r = Vector3(0.2, -0.26, -0.38)
			base_l = Vector3(-0.26, -0.36, -0.40)
			rr = Vector3(deg_to_rad(16.0), deg_to_rad(14.0), deg_to_rad(-62.0))
			lr = Vector3(deg_to_rad(4.0), deg_to_rad(-10.0), deg_to_rad(30.0))
		&"spear":
			base_r = Vector3(0.19, -0.27, -0.36)
			base_l = Vector3(-0.26, -0.36, -0.40)
			rr = Vector3(deg_to_rad(10.0), deg_to_rad(18.0), deg_to_rad(-80.0))
			lr = Vector3(deg_to_rad(4.0), deg_to_rad(-10.0), deg_to_rad(30.0))
		&"weapon":
			base_r = Vector3(0.19, -0.27, -0.38)
			base_l = Vector3(-0.24, -0.34, -0.42)
			rr = Vector3(deg_to_rad(14.0), deg_to_rad(14.0), deg_to_rad(-55.0))
			lr = Vector3(deg_to_rad(4.0), deg_to_rad(-10.0), deg_to_rad(30.0))
		&"tool_item":
			base_r = Vector3(0.18, -0.26, -0.38)
			base_l = Vector3(-0.24, -0.34, -0.42)
			rr = Vector3(deg_to_rad(12.0), deg_to_rad(14.0), deg_to_rad(-75.0))
			lr = Vector3(deg_to_rad(4.0), deg_to_rad(-10.0), deg_to_rad(30.0))
		_:
			# еда, камень, кокос — на ладони, кисть повёрнута ладонью вверх
			base_r = Vector3(0.17, -0.25, -0.4)
			base_l = Vector3(-0.24, -0.34, -0.42)
			rr = Vector3(deg_to_rad(18.0), deg_to_rad(18.0), deg_to_rad(-140.0))
			lr = Vector3(deg_to_rad(4.0), deg_to_rad(-10.0), deg_to_rad(30.0))
	base_r.x *= spread
	base_l.x *= spread
	# бег: руки ниже и ближе, отмашка противофазой
	base_r += Vector3(-0.01, -0.03, 0.02) * _run_amp + Vector3(0.0, 0.0, sin(_phase) * 0.035 * _run_amp * _walk_amp)
	base_l += Vector3(0.01, -0.03, 0.02) * _run_amp - Vector3(0.0, 0.0, sin(_phase) * 0.035 * _run_amp * _walk_amp)
	base_r.y += -0.02 * tired + breath
	base_l.y += -0.02 * tired + breath * 0.9
	rr += Vector3(breath * 0.6, 0.0, 0.0)
	lr += Vector3(breath * 0.6, 0.0, 0.0)
	if swimming:
		# Гребки брассом: ладони плоские, разводим и подтягиваем.
		var st := sin(_t * 2.6)
		var ct := cos(_t * 2.6)
		base_r = Vector3(0.14 + st * 0.13, -0.22 + ct * 0.02, -0.46 + ct * 0.1)
		base_l = Vector3(-0.14 - st * 0.13, -0.22 + ct * 0.02, -0.46 + ct * 0.1)
		rr = Vector3(deg_to_rad(-8.0), deg_to_rad(-25.0) * st, deg_to_rad(-30.0 - 25.0 * st))
		lr = Vector3(deg_to_rad(-8.0), deg_to_rad(25.0) * st, deg_to_rad(30.0 + 25.0 * st))
		g_r = &"flat"
		g_l = &"flat"
	# Перехват предмета: рука опускается и возвращается уже с новым.
	if _swap_t >= 0.0:
		_swap_t += delta
		var dn := _ease(_swap_t / SWAP_DOWN) if _swap_t < SWAP_DOWN else 1.0 - _ease((_swap_t - SWAP_DOWN) / SWAP_UP)
		if _swap_t >= SWAP_DOWN and _old_held:
			_old_held.queue_free()
			_old_held = null
			_update_held_visible()
		base_r += Vector3(0.03, -0.2, 0.06) * dn
		rr += Vector3(deg_to_rad(-30.0), 0.0, deg_to_rad(10.0)) * dn
		if _swap_t >= SWAP_DOWN + SWAP_UP:
			_finish_swap()
	if _swinging:
		_swing_t += delta
		var p := _swing_t / _swing_len
		match _swing_kind:
			Swing.ARC:
				# замах за плечо (с упреждением) → резкий удар вниз-влево → проводка → возврат
				var wind := _bump(p, 0.0, 0.36, 0.47)
				var strike := _bump(p, 0.36, 0.5, 1.0)
				var follow := _bump(p, 0.44, 0.58, 1.0)
				base_r += Vector3(0.07, 0.12, 0.05) * wind + Vector3(-0.12, -0.06, -0.12) * strike + Vector3(-0.03, -0.06, 0.0) * follow
				rr += Vector3(deg_to_rad(55.0), deg_to_rad(-8.0), deg_to_rad(-20.0)) * wind
				rr += Vector3(deg_to_rad(-22.0), deg_to_rad(22.0), deg_to_rad(18.0)) * strike + Vector3(deg_to_rad(-12.0), 0.0, 0.0) * follow
				base_l += Vector3(0.02, 0.04, 0.0) * wind
			Swing.THRUST:
				var back := _bump(p, 0.0, 0.3, 0.42)
				var fwd := _bump(p, 0.3, 0.45, 1.0)
				base_r += Vector3(0.01, 0.025, 0.12) * back + Vector3(-0.05, 0.03, -0.3) * fwd
				base_l += Vector3(0.03, 0.0, 0.08) * back + Vector3(0.05, 0.02, -0.18) * fwd
				rr += Vector3(deg_to_rad(-6.0), 0.0, 0.0) * back + Vector3(deg_to_rad(4.0), deg_to_rad(-6.0), 0.0) * fwd
			Swing.PUNCH:
				var back2 := _bump(p, 0.0, 0.28, 0.4)
				var hit := _bump(p, 0.28, 0.45, 1.0)
				base_r += Vector3(0.02, -0.01, 0.06) * back2 + Vector3(-0.13, 0.09, -0.26) * hit
				rr += Vector3(deg_to_rad(-8.0), deg_to_rad(10.0), deg_to_rad(-20.0)) * back2
				rr += Vector3(deg_to_rad(8.0), deg_to_rad(-6.0), deg_to_rad(-40.0)) * hit
				base_l += Vector3(0.02, 0.03, 0.02) * hit
				g_r = &"fist"
		if p >= IMPACT_AT and not _impact_sent:
			_impact_sent = true
			swing_impact.emit()
		if p >= 1.0:
			_swinging = false
			swing_finished.emit()
	if _using:
		_use_t += delta
		var q := _use_t / USE_TIME
		var lift := _ease(q / 0.35) * (1.0 - _ease((q - 0.7) / 0.3))
		var sip := sin(clampf((q - 0.35) / 0.35, 0.0, 1.0) * PI) * lift
		base_r = base_r.lerp(Vector3(0.05, -0.13, -0.25), lift)
		rr = rr.lerp(Vector3(deg_to_rad(30.0), deg_to_rad(35.0), deg_to_rad(-60.0)), lift) + Vector3(deg_to_rad(20.0) * sip, 0.0, 0.0)
		if q >= 1.0:
			_using = false
			use_finished.emit()
	if _carry > 0.0:
		var c := _ease(_carry)
		# ладонь лежит на бревне сверху, пальцы обхватывают его
		base_r = base_r.lerp(Vector3(0.39, -0.115 + bob.y * 1.2, -0.42), c)
		base_l = base_l.lerp(Vector3(-0.26, -0.38, -0.42), c)
		rr = rr.lerp(Vector3(deg_to_rad(4.0), deg_to_rad(-30.0), deg_to_rad(-14.0)), c)
		lr = lr.lerp(Vector3(deg_to_rad(4.0), deg_to_rad(-10.0), deg_to_rad(30.0)), c)
		g_r = &"round"
		log_mesh.position = Vector3(0.46, -0.2 + bob.y * 1.2 - 0.03 * tired, -0.22)
		log_mesh.rotation = Vector3(PI / 2.0 + bob_rot.x * 0.5, 0.0, deg_to_rad(-4.0) + bob_rot.z * 0.3)
	# Покачивание при ходьбе добавляем к позе (в позах оружия — по pose_bob).
	var bob_k := lerpf(1.0, pose_bob, pose_w)
	base_r += bob * bob_k
	base_l += Vector3(-bob.x, bob.y, bob.z) * bob_k
	rr += bob_rot * bob_k
	lr += Vector3(bob_rot.x, -bob_rot.y, -bob_rot.z) * bob_k
	if pose_w > 0.0: # COMBAT: позы оружия
		var pb := Vector3(0.0, bob.y * 0.6 + breath, 0.0) * pose_bob
		base_r = base_r.lerp(pose_r + pb, pose_w)
		base_l = base_l.lerp(pose_l + pb, pose_w)
		rr = rr.lerp(pose_rr, pose_w)
		lr = lr.lerp(pose_lr, pose_w)
	# Плавное следование за целью (быстро — чтобы удары оставались резкими).
	if _first_frame:
		right_arm.position = base_r
		left_arm.position = base_l
		right_arm.rotation = rr
		left_arm.rotation = lr
		_first_frame = false
	var k := clampf(delta * 16.0, 0.0, 1.0)
	right_arm.position = right_arm.position.lerp(base_r, k)
	left_arm.position = left_arm.position.lerp(base_l, k)
	right_arm.rotation = right_arm.rotation.lerp(rr, k)
	left_arm.rotation = left_arm.rotation.lerp(lr, k)
	# Пальцы плавно перетекают в нужный хват.
	var gk := clampf(delta * 14.0, 0.0, 1.0)
	_blend_grip(_grip_r, _grip_array(g_r), gk)
	_blend_grip(_grip_l, _grip_array(g_l), gk)
	_apply_grip(_skel_r, _grip_r, false)
	_apply_grip(_skel_l, _grip_l, true)
	_update_sway(delta, on_floor)

func _blend_grip(cur: PackedFloat32Array, target: PackedFloat32Array, k: float) -> void:
	for i in cur.size():
		cur[i] = lerpf(cur[i], target[i], k)

## Инерция рук: отстают от поворота камеры и пружинят; при приземлении — проседают.
func _update_sway(delta: float, on_floor: bool) -> void:
	var cam := get_parent() as Node3D
	var gb := cam.global_basis.orthonormalized() if cam and cam.is_inside_tree() else Basis.IDENTITY
	var ang := Vector3.ZERO
	if _cam_init and delta > 0.0:
		var rel := (_prev_cam.inverse() * gb).get_euler()
		ang = Vector3(rel.x, rel.y, 0.0) / delta
		ang = ang.clamp(Vector3(-6.0, -6.0, 0.0), Vector3(6.0, 6.0, 0.0))
	_prev_cam = gb
	_cam_init = true
	var amt := lerpf(1.0, pose_bob, pose_w)
	var tgt_p := Vector3(ang.y * 0.012, -ang.x * 0.01, 0.0) * amt
	var tgt_r := Vector3(-ang.x * 0.035, -ang.y * 0.045, -ang.y * 0.03) * amt
	if on_floor and not _was_floor:
		_sway_pv += Vector3(0.0, -0.35, 0.0) * amt
	elif not on_floor and _was_floor:
		_sway_pv += Vector3(0.0, 0.12, 0.0) * amt
	_was_floor = on_floor
	var s := _spring(_sway_p, _sway_pv, tgt_p, 13.0, 0.62, delta)
	_sway_p = s[0]
	_sway_pv = s[1]
	var s2 := _spring(_sway_r, _sway_rv, tgt_r, 12.0, 0.6, delta)
	_sway_r = s2[0]
	_sway_rv = s2[1]
	position = _sway_p.clamp(Vector3(-0.05, -0.06, -0.03), Vector3(0.05, 0.05, 0.03))
	rotation = _sway_r.clamp(Vector3(-0.15, -0.15, -0.12), Vector3(0.15, 0.15, 0.12))
