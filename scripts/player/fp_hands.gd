class_name FPHands
extends Node3D
## Руки от первого лица (процедурные — заменим моделями из ассетов).
## Анимации в коде: покой/шаг/бег/усталость, удар-замах, несение бревна.

signal swing_impact
signal swing_finished

const SKIN := Color(0.78, 0.58, 0.45)
const SLEEVE := Color(0.32, 0.36, 0.30)
const SWING_TIME := 0.62
const IMPACT_AT := 0.45 # доля длительности, когда наносится удар

var right_arm: Node3D
var left_arm: Node3D
var held_root: Node3D   # сюда модули кладут модель предмета в руке
var log_mesh: MeshInstance3D

var _swinging: bool = false
var _swing_t: float = 0.0
var _impact_sent: bool = false
var _carry: float = 0.0
var _carry_on: bool = false
var _t: float = 0.0
var _sway: Vector2 = Vector2.ZERO

func _ready() -> void:
	right_arm = _make_arm(true)
	left_arm = _make_arm(false)
	add_child(right_arm)
	add_child(left_arm)
	held_root = Node3D.new()
	held_root.name = "Held"
	right_arm.get_node(^"Hand").add_child(held_root)
	held_root.position = Vector3(0.0, -0.02, -0.06)
	_add_placeholder_axe()
	log_mesh = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.13
	cyl.bottom_radius = 0.15
	cyl.height = 1.9
	cyl.radial_segments = 12
	log_mesh.mesh = cyl
	var bark := _mat(Color(1, 1, 1), 0.9)
	const BARK := "res://assets/textures/bark_brown_02/bark_brown_02_"
	if ResourceLoader.exists(BARK + "albedo.png"):
		bark.albedo_texture = load(BARK + "albedo.png") as Texture2D
		bark.normal_enabled = true
		bark.normal_texture = load(BARK + "normal.png") as Texture2D
		bark.uv1_scale = Vector3(1.0, 3.0, 1.0)
	else:
		bark.albedo_color = Color(0.42, 0.29, 0.19)
	log_mesh.material_override = bark
	log_mesh.rotation = Vector3(PI / 2.0, 0.0, 0.0)
	log_mesh.position = Vector3(0.46, -0.2, -0.22)
	log_mesh.visible = false
	add_child(log_mesh)
	_disable_shadows(self)

func _mat(c: Color, rough: float = 0.75) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m

func _make_arm(right: bool) -> Node3D:
	var s := 1.0 if right else -1.0
	var arm := Node3D.new()
	arm.name = "RightArm" if right else "LeftArm"
	arm.position = Vector3(0.24 * s, -0.27, -0.46)
	var forearm := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.042
	cap.height = 0.34
	forearm.mesh = cap
	forearm.material_override = _mat(SLEEVE, 0.95)
	forearm.rotation = Vector3(deg_to_rad(76.0), 0.0, 0.0)
	forearm.position = Vector3(0.0, -0.02, 0.15)
	arm.add_child(forearm)
	var cuff := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.045
	cm.bottom_radius = 0.045
	cm.height = 0.03
	cuff.mesh = cm
	cuff.material_override = _mat(SLEEVE.darkened(0.25), 0.95)
	cuff.rotation = Vector3(deg_to_rad(76.0), 0.0, 0.0)
	cuff.position = Vector3(0.0, 0.015, -0.005)
	arm.add_child(cuff)
	var hand := Node3D.new()
	hand.name = "Hand"
	hand.position = Vector3(0.0, 0.03, -0.06)
	arm.add_child(hand)
	var palm := MeshInstance3D.new()
	var bm := CapsuleMesh.new()
	bm.radius = 0.032
	bm.height = 0.1
	palm.mesh = bm
	palm.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
	palm.scale = Vector3(1.15, 1.0, 0.7)
	palm.material_override = _mat(SKIN, 0.6)
	hand.add_child(palm)
	var fingers := MeshInstance3D.new()
	var fm := CapsuleMesh.new()
	fm.radius = 0.026
	fm.height = 0.075
	fingers.mesh = fm
	fingers.material_override = _mat(SKIN, 0.6)
	fingers.position = Vector3(0.0, -0.018, -0.058)
	fingers.rotation = Vector3(deg_to_rad(55.0), 0.0, 0.0)
	fingers.scale = Vector3(1.25, 1.0, 0.75)
	hand.add_child(fingers)
	var thumb := MeshInstance3D.new()
	var tm := CapsuleMesh.new()
	tm.radius = 0.014
	tm.height = 0.07
	thumb.mesh = tm
	thumb.material_override = _mat(SKIN, 0.6)
	thumb.position = Vector3(-0.045 * s, 0.0, -0.02)
	thumb.rotation = Vector3(deg_to_rad(70.0), 0.0, deg_to_rad(30.0 * s))
	hand.add_child(thumb)
	return arm

func _add_placeholder_axe() -> void:
	var handle := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.016
	hm.bottom_radius = 0.02
	hm.height = 0.55
	handle.mesh = hm
	handle.material_override = _mat(Color(0.48, 0.33, 0.2), 0.85)
	handle.position = Vector3(0.0, 0.18, 0.0)
	held_root.add_child(handle)
	var head := MeshInstance3D.new()
	var am := BoxMesh.new()
	am.size = Vector3(0.025, 0.11, 0.16)
	head.mesh = am
	var steel := _mat(Color(0.55, 0.57, 0.6), 0.35)
	steel.metallic = 0.85
	head.material_override = steel
	head.position = Vector3(0.0, 0.42, -0.06)
	held_root.add_child(head)

func _disable_shadows(n: Node) -> void:
	for c in n.get_children():
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_disable_shadows(c)

func play_swing() -> void:
	if _swinging:
		return
	_swinging = true
	_swing_t = 0.0
	_impact_sent = false

func is_swinging() -> bool:
	return _swinging

func set_carry(on: bool) -> void:
	_carry_on = on
	log_mesh.visible = on
	held_root.visible = not on

## Вызывается игроком каждый кадр.
func animate(delta: float, speed01: float, sprinting: bool, tired: float, on_floor: bool, carrying: bool) -> void:
	_t += delta
	_carry = move_toward(_carry, 1.0 if _carry_on else 0.0, delta * 4.0)
	var step := sin(_t * (6.5 + 4.0 * speed01)) * speed01 * (1.0 if on_floor else 0.2)
	var breath := sin(_t * 1.6) * 0.004 + sin(_t * 4.2) * 0.01 * tired
	# Бег — руки ниже и ходят сильнее.
	var run := 1.0 if sprinting else 0.0
	var base_r := Vector3(0.24, -0.27 - 0.04 * run - 0.03 * tired, -0.46)
	var base_l := Vector3(-0.24, -0.29 - 0.04 * run - 0.03 * tired, -0.48)
	var rr := Vector3(0.0, 0.0, 0.0)
	var lr := Vector3(0.0, 0.0, 0.0)
	base_r.y += step * 0.025 + breath
	base_l.y -= step * 0.025 - breath
	base_r.z += step * 0.03 * run
	base_l.z -= step * 0.03 * run
	# Замах: отвод назад-вверх → удар вперёд-вниз → возврат.
	if _swinging:
		_swing_t += delta
		var p := _swing_t / SWING_TIME
		var wind := smoothstep(0.0, 0.35, p) * (1.0 - smoothstep(0.35, 0.5, p))
		var strike := smoothstep(0.35, 0.5, p) * (1.0 - smoothstep(0.55, 1.0, p))
		base_r += Vector3(0.05 * wind - 0.12 * strike, 0.16 * wind - 0.06 * strike, 0.12 * wind - 0.18 * strike)
		rr += Vector3(deg_to_rad(70.0) * wind - deg_to_rad(50.0) * strike, deg_to_rad(-15.0) * wind, deg_to_rad(-20.0) * wind)
		if p >= IMPACT_AT and not _impact_sent:
			_impact_sent = true
			swing_impact.emit()
		if p >= 1.0:
			_swinging = false
			swing_finished.emit()
	# Несение бревна на правом плече: правая рука придерживает сверху,
	# левая — свободна и опущена (как в The Forest).
	if _carry > 0.0:
		base_r = base_r.lerp(Vector3(0.36, -0.15 + step * 0.02, -0.40), _carry)
		base_l = base_l.lerp(Vector3(-0.24, -0.34 - step * 0.03, -0.44), _carry)
		rr = rr.lerp(Vector3(deg_to_rad(35.0), deg_to_rad(10.0), deg_to_rad(25.0)), _carry)
		log_mesh.position = Vector3(0.46, -0.2 + step * 0.025 - 0.03 * tired, -0.22)
		log_mesh.rotation = Vector3(PI / 2.0 + step * 0.02, 0.0, deg_to_rad(-4.0))
	# Без предмета в руках левая рука опускается чуть ниже.
	right_arm.position = right_arm.position.lerp(base_r, clampf(delta * 18.0, 0.0, 1.0))
	left_arm.position = left_arm.position.lerp(base_l, clampf(delta * 18.0, 0.0, 1.0))
	right_arm.rotation = right_arm.rotation.lerp(rr, clampf(delta * 18.0, 0.0, 1.0))
	left_arm.rotation = left_arm.rotation.lerp(lr, clampf(delta * 18.0, 0.0, 1.0))
