class_name Polygon
extends Node3D
## Новый «Полигон» (версия 5, с нуля): ровная площадка-музей со ВСЕМИ моделями игры
## (PolygonExhibits — каталог ассетов + реестры), рядами по разделам: стенды (модель
## неподвижна, подпись) и «живые» участки. Разделы подгружаются по одному — только тот,
## у которого стоит игрок (и соседний, если он у границы). Острова и архипелаг —
## отдельные сцены (PolygonIslandStage), тоже по одному. Меню — F1 или M.
## Реплей в максимальной графике — кнопка в меню или команда консоли `replay`.

const SCENE := "res://scenes/polygon/polygon.tscn"
const LOAD_MARGIN := 55.0        # раздел строится, когда игрок ближе к его полосе
const UNLOAD_MARGIN := 110.0     # и удаляется, когда дальше
const MAX_SECTIONS := 2

const MODULES: Array[Dictionary] = [
	{"slot": "Build", "scene": "res://scenes/build/build_module.tscn"},
	{"slot": "Sea", "scene": "res://scenes/sea/sea.tscn"},
	{"slot": "Fauna", "scene": "res://scenes/fauna/fauna.tscn", "set": {"auto_populate": false}},
	{"slot": "Survival", "scene": "res://scenes/survival/survival.tscn", "set": {"spawn_debris": false, "spawn_wild": false}},
	{"slot": "Combat", "scene": "res://scenes/combat/combat.tscn"},
	{"slot": "Supply", "script": "res://scripts/supply/supply.gd"},
]

signal ready_to_play
signal section_built(id: StringName)

## Параметры запуска (ставит start()/реплей): {section, replay_mode, pos, look}
static var launch: Dictionary = {}

var world: PolygonWorld
var player: Player
var cheats: SandboxCheats
var panel: PolygonPanel
var recorder: ReplayRecorder
var sections: Dictionary = {}     # id → PolygonSection (построенные)
var is_built := false
var observer := false
var replay_mode := false
var _stream_t := 0.0
var _building := false
var _building_id: StringName = &""
var _hint: Label

static func start(tree: SceneTree, opts: Dictionary = {}) -> void:
	launch = opts
	Game.end_session()
	tree.paused = false
	tree.change_scene_to_file(SCENE)

func _ready() -> void:
	add_to_group(&"polygon")
	add_to_group(&"sandbox")
	replay_mode = bool(launch.get("replay_mode", false))
	world = $World as PolygonWorld
	if not world.is_ready:
		await world.world_ready
	for m in MODULES:
		var slot := get_node_or_null(String(m.slot))
		if slot == null:
			slot = Node3D.new()
			slot.name = String(m.slot)
			add_child(slot)
		var n: Node = null
		if m.has("scene") and ResourceLoader.exists(m.scene):
			n = (load(m.scene) as PackedScene).instantiate()
		elif m.has("script") and ResourceLoader.exists(m.script):
			n = (load(m.script) as Script).new() as Node
		if n == null:
			continue
		var props: Dictionary = m.get("set", {})
		for k: String in props:
			n.set(k, props[k])
		slot.add_child(n)
	Game.pending_config = {}
	Game.start_match({"mode": "ffa", "teams": 4, "bots_enemy": 0, "bots_ally": 0, "minutes": 0, "auto_flags": false})
	for i in 3:
		await get_tree().process_frame
	_hub()
	var lay := PolygonLayout.get_layout()
	var hub: Vector2 = lay.hub
	var start_pos := Vector3(hub.x, world.height_at(hub.x, hub.y) + 0.3, hub.y)
	var look: Variant = Vector3(hub.x, start_pos.y + 1.5, hub.y + 30.0)
	if launch.has("section"):
		var s := PolygonLayout.section(StringName(launch.section))
		if not s.is_empty():
			start_pos = stand_point(s)
			look = start_pos + Vector3(0, 0, 12)
	if launch.has("pos"):
		start_pos = launch.pos
		look = launch.get("look", null)
	var ps := load("res://scenes/player/player.tscn") as PackedScene
	player = ps.instantiate() as Player
	player.set(&"team", 0)
	player.set(&"starter_items", {&"axe_crude": 1, &"spear": 1})
	player.position = start_pos
	add_child(player)
	player.inventory.select(Inventory.HOTBAR - 1)
	cheats = SandboxCheats.new()
	cheats.name = "Cheats"
	add_child(cheats)
	cheats.player = player
	cheats.world = world
	cheats.set_infinite(true, true)
	cheats.teleport(start_pos, look)
	var sk: Object = world.get(&"sky")
	if sk and sk.has_method(&"set_weather"):
		sk.call(&"set_weather", world.weather(), true, false)
	# первый раздел — сразу (ждём, чтобы игрок не стоял в пустоте)
	await _stream(true)
	if not replay_mode:
		var layer := CanvasLayer.new()
		layer.layer = 12
		add_child(layer)
		panel = PolygonPanel.new()
		layer.add_child(panel)
		panel.setup(self)
		_hint = Label.new()
		_hint.text = "F1 или M — меню полигона · F5 — погода · F6 — время · V — полёт · ` — консоль"
		_hint.add_theme_font_size_override(&"font_size", 15)
		_hint.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.75))
		_hint.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.8))
		_hint.add_theme_constant_override(&"outline_size", 4)
		_hint.position = Vector2(16, 12)
		_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(_hint)
		recorder = ReplayRecorder.new()
		recorder.name = "ReplayRecorder"
		add_child(recorder)
		recorder.setup(self, {"scene": "polygon", "seed": world.seed_value})
	is_built = true
	if replay_mode:
		ReplayPlayback.attach(self)
	ready_to_play.emit()
	print("[polygon] готов: экспонатов %d, разделов %d" % [PolygonExhibits.all().size(), (lay.sections as Array).size()])
	if not replay_mode:
		Events.toast.emit("Полигон: F1 или M — меню (разделы, острова, погода, реплей) · предметы бесконечные")

## Точка обзора раздела: перед первым рядом стендов.
static func stand_point(s: Dictionary) -> Vector3:
	var t: Vector2 = s.get("title", Vector2(0, float(s.z0)))
	var x := t.x + 8.0
	var z := t.y + 2.0
	if s.id == &"sea":
		var ps: Vector2 = s.pier_start
		x = ps.x
		z = ps.y + 2.0
		return Vector3(x, 1.5, z)
	return Vector3(x, P_ground(x, z) + 0.3, z)

static func P_ground(x: float, z: float) -> float:
	return SandboxProps.ground(x, z)

func _hub() -> void:
	var lay := PolygonLayout.get_layout()
	var hub: Vector2 = lay.hub
	var root := Node3D.new()
	root.name = "Hub"
	add_child(root)
	var lines := PackedStringArray()
	for s: Dictionary in lay.sections:
		lines.append("%s — %d" % [s.name, int(s.count)])
	SandboxProps.signpost(root, hub.x - 6.0, hub.y, "ПОЛИГОН", "Все модели и механики игры\nF1 или M — меню · быстрые переходы")
	SandboxProps.label(root, Vector3(hub.x + 6.0, P_ground(hub.x + 6.0, hub.y) + 3.4, hub.y), "\n".join(lines), 30,
		SandboxProps.SIGN_COLOR, 80.0)

# ------------------------------------------------------------ подгрузка разделов

func _process(delta: float) -> void:
	if not is_built or player == null:
		return
	_stream_t -= delta
	if _stream_t <= 0.0:
		_stream_t = 0.5
		_stream(false)

## Нужные разделы — по положению игрока; лишние — удалить.
func _stream(wait: bool) -> void:
	if _building or player == null:
		return
	var z := player.global_position.z
	var want: Array[StringName] = []
	for s: Dictionary in PolygonLayout.get_layout().sections:
		if z >= float(s.z0) - LOAD_MARGIN and z <= float(s.z1) + LOAD_MARGIN:
			want.append(s.id)
	# ближайший — первым
	want.sort_custom(func(a: StringName, b: StringName) -> bool:
		return _dist(PolygonLayout.section(a), z) < _dist(PolygonLayout.section(b), z))
	want = want.slice(0, MAX_SECTIONS)
	for id: StringName in sections.keys():
		var s := PolygonLayout.section(id)
		if not want.has(id) and (z < float(s.z0) - UNLOAD_MARGIN or z > float(s.z1) + UNLOAD_MARGIN or sections.size() > MAX_SECTIONS):
			unload_section(id)
	for id in want:
		if not sections.has(id):
			if wait:
				await build_section(id)
			else:
				build_section(id)
			return

static func _dist(s: Dictionary, z: float) -> float:
	if z < float(s.z0):
		return float(s.z0) - z
	if z > float(s.z1):
		return z - float(s.z1)
	return 0.0

func build_section(id: StringName) -> PolygonSection:
	var s := PolygonLayout.section(id)
	if s.is_empty() or sections.has(id):
		return sections.get(id)
	_building = true
	_building_id = id
	var ps := PolygonSection.new().setup(s)
	ps.replay_mode = replay_mode
	add_child(ps)
	sections[id] = ps
	await ps.build()
	if _building_id == id:
		_building = false
		_building_id = &""
	if not is_instance_valid(ps) or ps.is_queued_for_deletion():
		return null
	print("[polygon] раздел «%s»: стендов %d, участков %d, узлов %d, %d мс" % [s.name, ps.stats.stands, ps.stats.plots,
		ps.stats.nodes, ps.stats.ms])
	section_built.emit(id)
	return ps

func unload_section(id: StringName) -> void:
	var ps: PolygonSection = sections.get(id)
	sections.erase(id)
	if _building_id == id:
		_building = false
		_building_id = &""
	if ps and is_instance_valid(ps):
		ps.unload()
	# кэш сцен каталога держит модели в памяти — сбросить (список записей перечитается)
	var cs := PolygonExhibits.catalog_script()
	if cs and cs.has_method(&"reload"):
		cs.call(&"reload")

## Перейти к разделу (быстрое перемещение).
func goto_section(id: StringName) -> void:
	var s := PolygonLayout.section(id)
	if s.is_empty():
		return
	var p := stand_point(s)
	cheats.teleport(p, p + Vector3(0, 0, 12))
	_stream_t = 0.0

func goto_hub() -> void:
	var hub: Vector2 = PolygonLayout.get_layout().hub
	var p := Vector3(hub.x, P_ground(hub.x, hub.y) + 0.3, hub.y)
	cheats.teleport(p, p + Vector3(0, 0, 30))

# ------------------------------------------------------------ режим наблюдателя

## Звери, акулы и рыбы не замечают игрока (он не в группе «characters»).
func set_observer(on: bool) -> void:
	observer = on
	if player == null:
		return
	if on and player.is_in_group(&"characters"):
		player.remove_from_group(&"characters")
	elif not on and not player.is_in_group(&"characters"):
		player.add_to_group(&"characters")

## Точка у прицела (для призыва из каталога и консоли).
func aim_point() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return player.global_position if player else Vector3.ZERO
	var from := cam.global_position
	var to := from - cam.global_basis.z * 40.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	if player:
		q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		return hit.position
	var p := from - cam.global_basis.z * 8.0
	return Vector3(p.x, world.height_at(p.x, p.z), p.z)

func current_section() -> StringName:
	if player == null:
		return &""
	var s := PolygonLayout.section_at(player.global_position.z)
	return s.get("id", &"")
