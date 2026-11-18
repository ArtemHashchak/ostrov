class_name FPHands
extends Node3D
## Руки от первого лица (процедурные, реалистичные материалы): кожа с
## подповерхностным рассеянием (Forward+), рукава из ткани, пальцы обхватывают
## предмет, часы на левом запястье. Анимации в коде: покой/шаг/бег/усталость,
## замах/удар (топор), выпад (копьё), удар кулаком, «съесть/выпить», несение бревна.

signal swing_impact
signal swing_finished
signal use_finished

const SKIN := Color(0.78, 0.56, 0.42)
const SLEEVE := Color(0.36, 0.38, 0.30)
const SWING_TIME := 0.62
const THRUST_TIME := 0.5
const PUNCH_TIME := 0.42
const USE_TIME := 0.9
const IMPACT_AT := 0.45 # доля длительности, когда наносится удар

enum Swing { ARC, THRUST, PUNCH }

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
var _skin_mat: StandardMaterial3D
var _sleeve_mat: StandardMaterial3D
var _fingers_r: Array[Node3D] = []
var _grip_roll := 0.0
# COMBAT: поза оружия (CombatController задаёт каждый кадр; pose_w=0 — обычные руки).
var pose_w := 0.0
var pose_bob := 1.0
var pose_r := Vector3.ZERO
var pose_l := Vector3.ZERO
var pose_rr := Vector3.ZERO
var pose_lr := Vector3.ZERO

func _ready() -> void:
	_skin_mat = _make_skin()
	_sleeve_mat = HeldModels.pbr("Fabric004", Vector3(2.0, 2.0, 2.0), SLEEVE)
	right_arm = _make_arm(true)
	left_arm = _make_arm(false)
	add_child(right_arm)
	add_child(left_arm)
	held_root = Node3D.new()
	held_root.name = "Held"
	right_arm.get_node(^"Hand").add_child(held_root)
	held_root.position = Vector3(0.0, -0.005, -0.055)
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

func _make_skin() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = SKIN
	m.roughness = 0.58
	m.metallic_specular = 0.35
	if not RenderProfile.is_compat():
		m.subsurf_scatter_enabled = true
		m.subsurf_scatter_strength = 0.35
		m.subsurf_scatter_skin_mode = true
	m.rim_enabled = true
	m.rim = 0.15
	m.rim_tint = 0.6
	return m

func _caps(parent: Node3D, r: float, h: float, mat: Material, pos: Vector3, rot: Vector3, scale: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = maxf(h, r * 2.0)
	cm.radial_segments = 14
	cm.rings = 6
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scale
	parent.add_child(mi)
	return mi

func _make_arm(right: bool) -> Node3D:
	var s := 1.0 if right else -1.0
	var arm := Node3D.new()
	arm.name = "RightArm" if right else "LeftArm"
	arm.position = Vector3(0.24 * s, -0.27, -0.46)
	# Предплечье: от рукава (за кадром) к запястью, чуть сужается.
	var fore := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.031
	cm.bottom_radius = 0.043
	cm.height = 0.34
	cm.radial_segments = 16
	fore.mesh = cm
	fore.material_override = _skin_mat
	fore.rotation = Vector3(deg_to_rad(-76.0), 0.0, 0.0)
	fore.position = Vector3(0.0, -0.035, 0.15)
	fore.scale = Vector3(1.0, 1.0, 0.82)
	arm.add_child(fore)
	# Рукав, закатанный до середины предплечья (как у героя The Forest).
	var sleeve := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.052
	sm.bottom_radius = 0.06
	sm.height = 0.2
	sm.radial_segments = 16
	sleeve.mesh = sm
	sleeve.material_override = _sleeve_mat
	sleeve.rotation = Vector3(deg_to_rad(-76.0), 0.0, 0.0)
	sleeve.position = Vector3(0.0, -0.062, 0.27)
	arm.add_child(sleeve)
	var roll := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.042
	tm.outer_radius = 0.062
	tm.rings = 18
	tm.ring_segments = 8
	roll.mesh = tm
	roll.material_override = _sleeve_mat
	roll.rotation = Vector3(deg_to_rad(-76.0), 0.0, 0.0)
	roll.position = Vector3(0.0, -0.04, 0.17)
	arm.add_child(roll)
	if not right:
		# Часы на левом запястье.
		var strap := MeshInstance3D.new()
		var sm2 := TorusMesh.new()
		sm2.inner_radius = 0.029
		sm2.outer_radius = 0.036
		sm2.rings = 16
		sm2.ring_segments = 6
		strap.mesh = sm2
		strap.material_override = HeldModels.color_mat(Color(0.12, 0.1, 0.09), 0.7)
		strap.rotation = Vector3(deg_to_rad(-76.0), 0.0, 0.0)
		strap.position = Vector3(0.0, -0.006, 0.035)
		arm.add_child(strap)
		var face := MeshInstance3D.new()
		var fm := CylinderMesh.new()
		fm.top_radius = 0.016
		fm.bottom_radius = 0.016
		fm.height = 0.008
		face.mesh = fm
		face.material_override = HeldModels.color_mat(Color(0.75, 0.76, 0.78), 0.25, 0.9)
		face.position = Vector3(0.0, 0.026, 0.04)
		face.rotation = Vector3(deg_to_rad(14.0), 0.0, 0.0)
		arm.add_child(face)
	# Кисть.
	var hand := Node3D.new()
	hand.name = "Hand"
	hand.position = Vector3(0.0, 0.03, -0.06)
	arm.add_child(hand)
	var palm := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.045
	bm.height = 0.09
	bm.radial_segments = 14
	bm.rings = 8
	palm.mesh = bm
	palm.scale = Vector3(1.0, 0.48, 1.2)
	palm.material_override = _skin_mat
	hand.add_child(palm)
	# Четыре пальца по две фаланги, согнуты в хват.
	for f in 4:
		var finger := Node3D.new()
		finger.position = Vector3((f - 1.5) * 0.019 * s, 0.002, -0.048 + absf(f - 1.5) * 0.004)
		finger.rotation = Vector3(deg_to_rad(-70.0), 0.0, 0.0)
		# Костяшка — видна сверху.
		_caps(hand, 0.0105, 0.012, _skin_mat, finger.position + Vector3(0, 0.004, 0.004), Vector3(0, 0, PI / 2.0))
		hand.add_child(finger)
		var len1 := 0.034 - absf(f - 1.5) * 0.003
		_caps(finger, 0.0095, len1, _skin_mat, Vector3(0, -len1 * 0.5, 0), Vector3.ZERO)
		var tip := Node3D.new()
		tip.position = Vector3(0, -len1, 0)
		tip.rotation = Vector3(deg_to_rad(-75.0), 0.0, 0.0)
		finger.add_child(tip)
		_caps(tip, 0.0085, len1 * 0.85, _skin_mat, Vector3(0, -len1 * 0.42, 0), Vector3.ZERO)
		if right:
			_fingers_r.append(finger)
	var thumb := Node3D.new()
	thumb.position = Vector3(-0.036 * s, 0.006, -0.012)
	thumb.rotation = Vector3(deg_to_rad(-40.0), deg_to_rad(-25.0 * s), deg_to_rad(40.0 * s))
	hand.add_child(thumb)
	_caps(thumb, 0.011, 0.045, _skin_mat, Vector3(0, -0.022, 0), Vector3.ZERO)
	return arm

func _disable_shadows(n: Node) -> void:
	for c in n.get_children():
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_disable_shadows(c)

## Модель предмета в правой руке (id из Items; "" — пустая рука).
func set_held(id: StringName) -> void:
	if id == held_id:
		return
	held_id = id
	for c in held_root.get_children():
		c.queue_free()
	if id != &"":
		var m := HeldModels.build(id)
		held_root.add_child(m)
		# Рукоять лежит поперёк кулака (ось X кисти), навершие — к большому
		# пальцу и вперёд; кисть повёрнута ребром — топор идёт по диагонали
		# вверх-влево, как в The Forest.
		if id in [&"axe_crude", &"axe_modern", &"stick"]:
			m.basis = _grip_basis(Vector3(-0.42, 0.88, -0.22), Vector3(0.25, 0.0, 1.0))
			m.position = Vector3(0.012, 0.0, 0.0)
		elif id == &"spear":
			m.rotation = Vector3(deg_to_rad(-80.0), 0.0, 0.0)
			m.position = Vector3(0.0, 0.0, 0.25)
	# Пустая рука — пальцы разжаты сильнее.
	_grip_roll = deg_to_rad(-18.0) if id in [&"axe_crude", &"axe_modern", &"stick"] else 0.0
	var curl := -70.0 if id != &"" else -35.0
	for f in _fingers_r:
		f.rotation.x = deg_to_rad(curl)

## Базис предмета: ось Y (рукоять) по up, -Z (лезвие) — от back.
static func _grip_basis(up: Vector3, back: Vector3) -> Basis:
	var y := up.normalized()
	var x := y.cross(back.normalized()).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)

func swing_kind_for(id: StringName) -> Swing:
	if id == &"spear":
		return Swing.THRUST
	if id == &"":
		return Swing.PUNCH
	return Swing.ARC

func play_swing(kind: Swing = Swing.ARC) -> void:
	if _swinging or _using:
		return
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
	_using = true
	_use_t = 0.0

func set_carry(on: bool) -> void:
	_carry_on = on
	log_mesh.visible = on
	held_root.visible = not on

func set_items_hidden(on: bool) -> void:
	_hidden_items = on
	held_root.visible = not on and not _carry_on

## Вызывается игроком каждый кадр.
func animate(delta: float, speed01: float, sprinting: bool, tired: float, on_floor: bool, _carrying: bool, swimming: bool = false) -> void:
	_t += delta
	_carry = move_toward(_carry, 1.0 if _carry_on else 0.0, delta * 4.0)
	var step := sin(_t * (6.5 + 4.0 * speed01)) * speed01 * (1.0 if on_floor else 0.2)
	var breath := sin(_t * 1.6) * 0.004 + sin(_t * 4.2) * 0.01 * tired
	var run := 1.0 if sprinting else 0.0
	var base_r := Vector3(0.24, -0.27 - 0.04 * run - 0.03 * tired, -0.46)
	var base_l := Vector3(-0.24, -0.29 - 0.04 * run - 0.03 * tired, -0.48)
	var rr := Vector3(0.0, 0.0, _grip_roll)
	var lr := Vector3.ZERO
	if _grip_roll != 0.0:
		# С инструментом правая рука ниже и правее, левая почти уходит из кадра.
		base_r += Vector3(0.04, -0.03, 0.02)
		base_l += Vector3(-0.04, -0.07, 0.04)
	base_r.y += step * 0.025 + breath
	base_l.y -= step * 0.025 - breath
	base_r.z += step * 0.03 * run
	base_l.z -= step * 0.03 * run
	if swimming:
		# Гребки брассом.
		var st := sin(_t * 2.6)
		base_r = Vector3(0.18 + st * 0.12, -0.24, -0.5 + cos(_t * 2.6) * 0.1)
		base_l = Vector3(-0.18 - st * 0.12, -0.24, -0.5 + cos(_t * 2.6) * 0.1)
		rr = Vector3(0.0, deg_to_rad(-20.0) * st, 0.0)
		lr = Vector3(0.0, deg_to_rad(20.0) * st, 0.0)
	if _swinging:
		_swing_t += delta
		var p := _swing_t / _swing_len
		match _swing_kind:
			Swing.ARC:
				var wind := smoothstep(0.0, 0.35, p) * (1.0 - smoothstep(0.35, 0.5, p))
				var strike := smoothstep(0.35, 0.5, p) * (1.0 - smoothstep(0.55, 1.0, p))
				base_r += Vector3(0.05 * wind - 0.12 * strike, 0.16 * wind - 0.06 * strike, 0.12 * wind - 0.18 * strike)
				rr += Vector3(deg_to_rad(70.0) * wind - deg_to_rad(50.0) * strike, deg_to_rad(-15.0) * wind, deg_to_rad(-20.0) * wind)
			Swing.THRUST:
				var back := smoothstep(0.0, 0.3, p) * (1.0 - smoothstep(0.3, 0.42, p))
				var fwd := smoothstep(0.3, 0.45, p) * (1.0 - smoothstep(0.55, 1.0, p))
				base_r += Vector3(-0.04 * fwd, 0.02 * back, 0.14 * back - 0.3 * fwd)
				base_l += Vector3(0.04 * fwd, 0.0, 0.1 * back - 0.22 * fwd)
			Swing.PUNCH:
				var back2 := smoothstep(0.0, 0.3, p) * (1.0 - smoothstep(0.3, 0.42, p))
				var hit := smoothstep(0.3, 0.45, p) * (1.0 - smoothstep(0.55, 1.0, p))
				base_r += Vector3(-0.1 * hit, 0.04 * hit, 0.06 * back2 - 0.24 * hit)
				rr += Vector3(deg_to_rad(10.0) * hit, 0.0, deg_to_rad(-30.0) * hit)
		if p >= IMPACT_AT and not _impact_sent:
			_impact_sent = true
			swing_impact.emit()
		if p >= 1.0:
			_swinging = false
			swing_finished.emit()
	if _using:
		_use_t += delta
		var q := _use_t / USE_TIME
		var lift := smoothstep(0.0, 0.35, q) * (1.0 - smoothstep(0.7, 1.0, q))
		base_r = base_r.lerp(Vector3(0.05, -0.12, -0.24), lift)
		rr = rr.lerp(Vector3(deg_to_rad(35.0), deg_to_rad(40.0), 0.0), lift)
		if q >= 1.0:
			_using = false
			use_finished.emit()
	if _carry > 0.0:
		base_r = base_r.lerp(Vector3(0.36, -0.15 + step * 0.02, -0.40), _carry)
		base_l = base_l.lerp(Vector3(-0.24, -0.34 - step * 0.03, -0.44), _carry)
		rr = rr.lerp(Vector3(deg_to_rad(35.0), deg_to_rad(10.0), deg_to_rad(25.0)), _carry)
		log_mesh.position = Vector3(0.46, -0.2 + step * 0.025 - 0.03 * tired, -0.22)
		log_mesh.rotation = Vector3(PI / 2.0 + step * 0.02, 0.0, deg_to_rad(-4.0))
	if pose_w > 0.0: # COMBAT: позы оружия
		var bob := Vector3(0.0, step * 0.012 + breath, step * 0.01 * run) * pose_bob
		base_r = base_r.lerp(pose_r + bob, pose_w)
		base_l = base_l.lerp(pose_l + bob, pose_w)
		rr = rr.lerp(pose_rr, pose_w)
		lr = lr.lerp(pose_lr, pose_w)
	var k := clampf(delta * 18.0, 0.0, 1.0)
	right_arm.position = right_arm.position.lerp(base_r, k)
	left_arm.position = left_arm.position.lerp(base_l, k)
	right_arm.rotation = right_arm.rotation.lerp(rr, k)
	left_arm.rotation = left_arm.rotation.lerp(lr, k)
