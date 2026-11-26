class_name BotModel
extends Node3D
## Внешний вид бота: скелетная модель «Mannequiny» (GDQuest, CC-BY 4.0) в одежде
## цвета команды, предмет в правой руке, брёвна на плече, анимации
## (стоит / идёт / бежит / плывёт / удар / смерть). Далеко от камеры анимация
## замирает, ещё дальше модель скрывается — бот почти ничего не стоит.

const MODEL_PATH := "res://scenes/bots/model/mannequiny.glb"
## v5: персонаж пользователя (Персонажи/«Мужчина (модель с анимациями)», Mixamo: idle/walk/run/jump/death,
## текстуры Fuse). Есть файл и use_user = true — боты (и тело игрока для тени/3-го лица) в нём; иначе манекен.
const USER_MODEL_PATH := "res://assets/user_pack/characters/character_male.glb"
const USER_HAND_BONE := "mixamorig_RightHand"
const USER_ARM_BONE := "mixamorig_LeftArm"
static var use_user := true
const ANIM_FAR := 70.0      # дальше — анимация не обновляется
const HIDE_FAR := 420.0     # дальше — модель не рисуется
const SKIN_TONES: Array[Color] = [Color(0.55, 0.38, 0.27), Color(0.71, 0.52, 0.39), Color(0.42, 0.29, 0.2), Color(0.8, 0.62, 0.48)]

static var _scene: PackedScene = null
static var _user_scene: PackedScene = null
static var _user_fixed := false
var user_model := false
static var _loops_set := false
static var _mat_cache: Dictionary = {}

var team: int = 0
var skin: Color = SKIN_TONES[0]
var anim: AnimationPlayer = null
var skeleton: Skeleton3D = null
var body_root: Node3D = null       # поворачивается при плавании/смерти
var hand_r: BoneAttachment3D = null
var _held_node: Node3D = null
var _held_id: StringName = &"-"
var _logs_node: Node3D = null
var _cur: StringName = &""
var _action_t: float = 0.0
var _dead: bool = false
var _swim: bool = false
var _swim_k: float = 0.0
var _anim_on: bool = true
var _anim_check_t: float = 0.0

func setup(team_id: int, seed_v: int) -> BotModel:
	team = team_id
	skin = SKIN_TONES[posmod(seed_v, SKIN_TONES.size())]
	return self

static func clear_cache() -> void:
	_mat_cache.clear()
	_mesh_cache.clear()
	_scene = null

func _ready() -> void:
	user_model = use_user and ResourceLoader.exists(USER_MODEL_PATH)
	if user_model:
		_ready_user()
		return
	if _scene == null:
		_scene = load(MODEL_PATH) as PackedScene
	body_root = Node3D.new()
	body_root.name = "Body"
	add_child(body_root)
	var inst := _scene.instantiate() as Node3D
	# glTF смотрит в +Z, бот — в −Z
	inst.rotation.y = PI
	body_root.add_child(inst)
	anim = inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	skeleton = inst.find_child("Skeleton3D", true, false) as Skeleton3D
	_set_loops()
	_apply_materials(inst)
	if skeleton:
		hand_r = BoneAttachment3D.new()
		hand_r.bone_name = "hand.r"
		skeleton.add_child(hand_r)
	play(&"idle")

## Персонаж пользователя: свои текстуры (без «раскраски» манекена), повязка цвета команды на левом плече,
## предмет в правой руке Mixamo, клипы idle/walk/run/jump/death (корень клипов не уезжает — ход делает бот).
func _ready_user() -> void:
	if _user_scene == null:
		_user_scene = load(USER_MODEL_PATH) as PackedScene
	body_root = Node3D.new()
	body_root.name = "Body"
	add_child(body_root)
	var inst := _user_scene.instantiate() as Node3D
	inst.rotation.y = PI   # Mixamo смотрит в +Z, бот — в −Z
	body_root.add_child(inst)
	anim = inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	skeleton = inst.find_child("Skeleton3D", true, false) as Skeleton3D
	if anim and not _user_fixed:
		_user_fixed = true
		for a: StringName in anim.get_animation_list():
			var an := anim.get_animation(a)
			an.loop_mode = Animation.LOOP_LINEAR if String(a) in ["idle", "walk", "run"] else Animation.LOOP_NONE
			_pin_root(an)
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visibility_range_end = HIDE_FAR
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if skeleton:
		hand_r = BoneAttachment3D.new()
		hand_r.bone_name = USER_HAND_BONE
		skeleton.add_child(hand_r)
		var arm := BoneAttachment3D.new()
		arm.bone_name = USER_ARM_BONE
		skeleton.add_child(arm)
		var band := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.058
		cm.bottom_radius = 0.058
		cm.height = 0.07
		cm.radial_segments = 12
		band.mesh = cm
		band.material_override = _mat("band%d" % team, Game.team_color(team), 0.8)
		band.position = Vector3(0.0, 0.12, 0.0)
		arm.add_child(band)
	play(&"idle")

## Ход корня (Hips) в клипах Mixamo по горизонтали — убрать: двигает тело код бота.
static func _pin_root(an: Animation) -> void:
	for t in an.get_track_count():
		if an.track_get_type(t) != Animation.TYPE_POSITION_3D:
			continue
		var path := String(an.track_get_path(t))
		if not path.ends_with("Hips"):
			continue
		if an.track_get_key_count(t) == 0:
			continue
		var p0: Vector3 = an.track_get_key_value(t, 0)
		for k in an.track_get_key_count(t):
			var v: Vector3 = an.track_get_key_value(t, k)
			an.track_set_key_value(t, k, Vector3(p0.x, v.y, p0.z))

func _set_loops() -> void:
	if anim == null or _loops_set:
		return
	_loops_set = true
	for a: StringName in [&"idle", &"run", &"fight_idle"]:
		if anim.has_animation(a):
			anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR

func _mat(key: String, c: Color, rough: float) -> StandardMaterial3D:
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if key.begins_with("skin"):
		m.rim_enabled = true
		m.rim = 0.25
		m.rim_tint = 0.6
	_mat_cache[key] = m
	return m

## Одежда «раскрашивается» по позе покоя: рубаха цвета команды, шорты, кожа,
## волосы и обувь — цвет вершин (меш кэшируется на команду и тон кожи).
static var _mesh_cache: Dictionary = {}

func _apply_materials(inst: Node) -> void:
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.visibility_range_end = HIDE_FAR
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var key := "%d|%s" % [team, skin.to_html(false)]
		if not _mesh_cache.has(key):
			_mesh_cache[key] = _dress(m.mesh as ArrayMesh, Game.team_color(team), skin)
		var dm: ArrayMesh = _mesh_cache[key]
		if dm == null:
			continue
		m.mesh = dm
		for s in dm.get_surface_count():
			m.set_surface_override_material(s, null)

static func _dress(src: ArrayMesh, team_c: Color, skin_c: Color) -> ArrayMesh:
	if src == null:
		return null
	var shirt := team_c.darkened(0.15)
	var shorts := Color(0.33, 0.29, 0.22)
	var hair := Color(0.1, 0.07, 0.05)
	var sandal := Color(0.24, 0.17, 0.11)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.75
	var out := ArrayMesh.new()
	for s in src.get_surface_count():
		var arr := src.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var cols := PackedColorArray()
		cols.resize(verts.size())
		for i in verts.size():
			var v := verts[i]
			var ax := absf(v.x)
			var c := skin_c
			if v.y < 0.09:
				c = sandal
			elif v.y > 1.70 and ax < 0.13 and v.z < 0.07:
				c = hair
			elif v.y > 1.70 and ax < 0.11:
				c = hair
			elif v.y > 0.98 and v.y < 1.50 and ax < 0.36:
				c = shirt
			elif v.y > 0.55 and v.y <= 1.02:
				c = shorts
			cols[i] = c
		arr[Mesh.ARRAY_COLOR] = cols
		var fmt := src.surface_get_format(s)
		var flags := fmt & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		out.add_surface_from_arrays(src.surface_get_primitive_type(s), arr, [], {}, flags)
		out.surface_set_material(s, mat)
	return out

func play(a: StringName, speed: float = 1.0, blend: float = 0.18) -> void:
	if anim == null or not anim.has_animation(a):
		return
	if _cur != a:
		_cur = a
		anim.play(a, blend, speed)
	else:
		anim.speed_scale = speed

## Удар/рубка/бросок — короткая анимация поверх движения.
func action(kind: StringName = &"swing") -> void:
	if _dead or anim == null:
		return
	_action_t = 0.45
	_cur = &""
	var a := &"fight_punch" if kind != &"kick" else &"fight_kick"
	if anim.has_animation(a):
		anim.play(a, 0.06, 1.5)

func set_held(id: StringName) -> void:
	if id == _held_id or hand_r == null:
		return
	_held_id = id
	if _held_node:
		_held_node.queue_free()
		_held_node = null
	if id == &"" or id == &"hand":
		return
	var n := HeldModels.build(id)
	if n == null:
		return
	_held_node = n
	# ручка в кулаке, лезвие вверх-вперёд
	n.rotation = Vector3(deg_to_rad(-90.0), 0.0, deg_to_rad(90.0))
	n.position = Vector3(0.0, 0.08, 0.02)
	hand_r.add_child(n)

func set_logs(n: int) -> void:
	if n <= 0:
		if _logs_node:
			_logs_node.queue_free()
			_logs_node = null
		return
	if _logs_node and _logs_node.get_child_count() == n:
		return
	if _logs_node:
		_logs_node.queue_free()
	_logs_node = Node3D.new()
	_logs_node.position = Vector3(0.22, 1.56, 0.0)
	body_root.add_child(_logs_node)
	var mat := BuildMats.mat(&"log")
	for i in n:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.16
		cm.bottom_radius = 0.17
		cm.height = 2.0
		cm.radial_segments = 10
		mi.mesh = cm
		mi.material_override = mat
		mi.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		mi.position = Vector3(0.0, i * 0.3, 0.1)
		_logs_node.add_child(mi)

func set_dead(on: bool) -> void:
	_dead = on
	if on and user_model and anim and anim.has_animation(&"death"):
		_cur = &"death"
		anim.play(&"death", 0.15)
		return
	if on:
		var tw := create_tween()
		_cur = &""
		if anim:
			anim.pause()
		tw.tween_property(body_root, ^"rotation:x", -PI * 0.5, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(body_root, ^"position:y", 0.25, 0.55)
	else:
		body_root.rotation = Vector3.ZERO
		body_root.position = Vector3.ZERO
		play(&"idle")

## Обновление позы: hspeed — горизонтальная скорость, swim — плывёт.
func update_pose(delta: float, hspeed: float, swim: bool, run: bool) -> void:
	if _dead:
		return
	_anim_check_t -= delta
	if _anim_check_t <= 0.0:
		_anim_check_t = 0.5
		var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
		var on := cam == null or cam.global_position.distance_to(global_position) < ANIM_FAR
		if on != _anim_on and anim:
			_anim_on = on
			anim.active = on
	_swim = swim
	_swim_k = move_toward(_swim_k, 1.0 if swim else 0.0, delta * 2.5)
	body_root.rotation.x = -_swim_k * 1.25
	body_root.position.y = -_swim_k * 0.15
	if _action_t > 0.0:
		_action_t -= delta
		return
	if swim:
		play(&"run", 0.45 + hspeed * 0.12)
	elif user_model and hspeed > 0.35 and hspeed < 2.4 and not run:
		play(&"walk", clampf(hspeed / 1.5, 0.6, 1.4))
	elif hspeed > 0.35:
		play(&"run", clampf(hspeed / (5.2 if run else 4.4), 0.45, 1.25))
	else:
		play(&"idle")
