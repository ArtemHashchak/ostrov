class_name FaunaAnim
extends RefCounted
## Реестр и помощники процедурной анимации животных (общий файл агентов анимации).
##
## Как подключить анимацию к Animal:
##  1) meta "anim" у модели — объект с методами setup/animate/animate_dead/on_event(animal, …)
##     (основной путь; события attack/hurt/die/eat/threat шлёт Animal.anim_event). Контроллер может
##     быть общим на все модели вида: состояние конкретного зверя — в animal.anim_state.
##  2) register_builder(species, maker) — своя модель-риг вместо AnimalModels.build (maker() -> Node3D).
##  3) register/controller_for — реестр общих контроллеров вида (для совместимости).
## По умолчанию: кабан, обезьяна (MammalAnim), попугай, чайка, летучая мышь (BirdAnim) — риги CreatureRigs.
##
## LOD анимации по расстоянию до камеры: 0 — полная (<25 м), 1 — упрощённая (<60 м), 2 — заморожена.

const FULL_R := 25.0
const SIMPLE_R := 60.0

static var _controllers: Dictionary = {}   # species -> Object
static var _builders: Dictionary = {}      # species -> Callable() -> Node3D
static var _inited: bool = false
static var _cam_frame: int = -1
static var _cam_pos: Vector3 = Vector3.ZERO
static var _mammal: Object = null
static var _bird: Object = null

static func register(species: StringName, controller: Object) -> void:
	_ensure()
	_controllers[species] = controller

static func register_builder(species: StringName, maker: Callable) -> void:
	_ensure()
	_builders[species] = maker

## Общий контроллер вида или null.
static func controller_for(species: StringName) -> Object:
	_ensure()
	return _controllers.get(species, null)

## Особая модель вида (с ригом) или null — тогда AnimalModels строит процедурную.
static func build_model(species: StringName) -> Node3D:
	_ensure()
	var mk: Variant = _builders.get(species, null)
	if mk is Callable and (mk as Callable).is_valid():
		return (mk as Callable).call()
	return null

## Общие экземпляры контроллеров млекопитающих и птиц (без собственного состояния).
static func mammal() -> Object:
	if _mammal == null:
		_mammal = load("res://scripts/fauna/anim/mammal_anim.gd").new()
	return _mammal

static func bird() -> Object:
	if _bird == null:
		_bird = load("res://scripts/fauna/anim/bird_anim.gd").new()
	return _bird

static func _ensure() -> void:
	if _inited:
		return
	_inited = true
	# риги млекопитающих и птиц (агент анимации C); другие агенты — через register_builder
	if not _builders.has(&"boar"):
		_builders[&"boar"] = CreatureRigs.boar
	if not _builders.has(&"monkey"):
		_builders[&"monkey"] = CreatureRigs.monkey
	if not _builders.has(&"parrot"):
		_builders[&"parrot"] = CreatureRigs.bird.bind(&"parrot")
	if not _builders.has(&"gull"):
		_builders[&"gull"] = CreatureRigs.bird.bind(&"gull")
	if not _builders.has(&"bat"):
		# крылан из пака пользователя (скелет, те же шарниры BirdAnim); иначе — процедурная мышь
		_builders[&"bat"] = UserBatRig.build if UserBatRig.available() else CreatureRigs.bat

## Позиция активной камеры (кэш на кадр).
static func cam_pos(n: Node) -> Vector3:
	var f := Engine.get_process_frames()
	if f != _cam_frame and n.is_inside_tree():
		_cam_frame = f
		var cam := n.get_viewport().get_camera_3d()
		_cam_pos = cam.global_position if cam else Vector3(1e9, 1e9, 1e9)
	return _cam_pos

## 0 — полная анимация, 1 — упрощённая, 2 — заморожена.
static func lod_of(n: Node3D) -> int:
	var d2 := n.global_position.distance_squared_to(cam_pos(n))
	if d2 < FULL_R * FULL_R:
		return 0
	if d2 < SIMPLE_R * SIMPLE_R:
		return 1
	return 2

## Сглаживание к цели с частотой k (1/с), независимое от dt.
static func damp(cur: float, target: float, k: float, dt: float) -> float:
	return lerpf(cur, target, 1.0 - exp(-k * dt))

static func damp_angle(cur: float, target: float, k: float, dt: float) -> float:
	return lerp_angle(cur, target, 1.0 - exp(-k * dt))
