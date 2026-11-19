class_name IslandsShowcase
extends Node3D
## «Полигон островов»: по острову каждого типа генератора (IslandGen) в ряд —
## для оценки будущего архипелага 3×3 км. Мир — ShowcaseWorld, модули те же,
## что в матче (флора, море с рифами и живностью, птицы). Быстрое перемещение
## (вид с пляжа / сверху), обзор всего ряда, погода и время — меню F1 или M.

const SCENE := "res://scenes/sandbox/islands_showcase.tscn"

const MODULES: Array[Dictionary] = [
	{"slot": "Sea", "scene": "res://scenes/sea/sea.tscn"},
	{"slot": "Fauna", "scene": "res://scenes/fauna/fauna.tscn", "set": {"auto_populate": false}},
]

signal ready_to_play

var world: ShowcaseWorld
var player: Player
var cheats: SandboxCheats
var panel: IslandsPanel
var flora: Flora
var overview_cam: Camera3D
var labels: Array[Label3D] = []
var is_built := false

static func start(tree: SceneTree) -> void:
	Game.end_session()
	tree.paused = false
	tree.change_scene_to_file(SCENE)

func _ready() -> void:
	world = $World as ShowcaseWorld
	if not world.is_ready:
		await world.world_ready
	flora = Flora.new()
	$Flora.add_child(flora)
	for m in MODULES:
		var slot := get_node_or_null(String(m.slot))
		if slot == null:
			slot = Node3D.new()
			slot.name = String(m.slot)
			add_child(slot)
		if not ResourceLoader.exists(m.scene):
			continue
		var n := (load(m.scene) as PackedScene).instantiate()
		var props: Dictionary = m.get("set", {})
		for k: String in props:
			n.set(k, props[k])
		slot.add_child(n)
	Game.pending_config = {}
	Game.start_match({"mode": "ffa", "teams": 4, "bots_enemy": 0, "bots_ally": 0, "minutes": 0, "auto_flags": false})
	if not flora.populated:
		await flora.flora_ready
	for i in 3:
		await get_tree().process_frame
	_birds()
	_labels()
	var first: Dictionary = world.showcase()[0]
	var ps := load("res://scenes/player/player.tscn") as PackedScene
	player = ps.instantiate() as Player
	player.set(&"team", 0)
	player.set(&"starter_items", {})
	player.position = beach_pos(first)
	add_child(player)
	player.inventory.select(Inventory.HOTBAR - 1)
	cheats = SandboxCheats.new()
	cheats.name = "Cheats"
	add_child(cheats)
	cheats.player = player
	cheats.world = world
	cheats.god = true
	cheats.infinite = false
	cheats.teleport(beach_pos(first), _v3(first.beach_look, 8.0))
	var sk: Object = world.get(&"sky")
	if sk and sk.has_method(&"set_weather"):
		sk.call(&"set_weather", &"clear", true, false)
	overview_cam = Camera3D.new()
	overview_cam.name = "OverviewCam"
	overview_cam.fov = 55.0
	overview_cam.far = 12000.0
	add_child(overview_cam)
	var layer := CanvasLayer.new()
	layer.layer = 12
	add_child(layer)
	panel = IslandsPanel.new()
	layer.add_child(panel)
	panel.setup(self)
	var hint := Label.new()
	hint.text = "F1 или M — острова, обзор, погода · F5 — погода · F6 — время · V — полёт · O — обзор ряда"
	hint.add_theme_font_size_override(&"font_size", 15)
	hint.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.75))
	hint.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.8))
	hint.add_theme_constant_override(&"outline_size", 4)
	hint.position = Vector2(16, 12)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hint)
	is_built = true
	ready_to_play.emit()
	print("[islands] готов: островов %d, декор %s, флора %s" % [world.showcase().size(), str(world.decor.stats), str(flora.stats)])
	Events.toast.emit("Полигон островов: F1 или M — меню, O — обзор всего ряда, V — полёт")

func _v3(p: Vector2, dy: float = 0.0) -> Vector3:
	return Vector3(p.x, maxf(world.height_at(p.x, p.y), world.water_level()) + dy, p.y)

## Точка на пляже (или у кромки воды) для вида на остров.
func beach_pos(e: Dictionary) -> Vector3:
	var b: Vector2 = e.beach
	var h := world.height_at(b.x, b.y)
	return Vector3(b.x, maxf(h, world.water_level() + 0.1) + 0.2, b.y)

## Позиция «сверху»: наискосок с юга, на высоте ~ размер острова.
func aerial_pos(e: Dictionary) -> Vector3:
	var c: Vector2 = e.center
	var ext: float = e.extent
	return Vector3(c.x - ext * 0.15, ext * 0.85 + 60.0, c.y + ext * 1.45)

func go_beach(i: int) -> void:
	var e: Dictionary = world.showcase()[i]
	set_overview(false)
	if cheats.fly:
		cheats.set_fly(false)
	cheats.teleport(beach_pos(e), _v3(e.beach_look, 10.0))
	Events.toast.emit(String(e.name))

func go_air(i: int) -> void:
	var e: Dictionary = world.showcase()[i]
	set_overview(false)
	if not cheats.fly:
		cheats.set_fly(true)
	cheats.teleport(aerial_pos(e), _v3(e.center))
	Events.toast.emit(String(e.name) + " — сверху")

## Обзор всего ряда (отдельная камера высоко над рядом).
func set_overview(on: bool) -> void:
	if overview_cam == null:
		return
	world.set_overview(on)
	if on:
		var b := world.arch.bounds
		var c := b.get_center()
		overview_cam.global_position = Vector3(c.x, b.size.x * 0.36, b.end.y + b.size.x * 0.33)
		overview_cam.look_at(Vector3(c.x, 0.0, c.y))
		overview_cam.current = true
		for l in labels:
			l.pixel_size = 0.9
	else:
		overview_cam.current = false
		if player:
			player.camera.current = true
		for l in labels:
			l.pixel_size = 0.12

func overview_on() -> bool:
	return overview_cam != null and overview_cam.current

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		if (event as InputEventKey).physical_keycode == KEY_O and player and not player.ui_open:
			set_overview(not overview_on())
			get_viewport().set_input_as_handled()

## Подписи над островами (видно издалека).
func _labels() -> void:
	for e: Dictionary in world.showcase():
		var c: Vector2 = e.center
		var top := 0.0
		for id: int in e.island_ids:
			top = maxf(top, float(world.arch.islands[id].max_h))
		var l := Label3D.new()
		l.text = String(e.name)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.font_size = 96
		l.outline_size = 24
		l.pixel_size = 0.12
		l.modulate = Color(1, 1, 1, 0.95)
		l.outline_modulate = Color(0, 0, 0, 0.8)
		l.position = Vector3(c.x, top + 38.0, c.y)
		l.visibility_range_end = 4000.0
		add_child(l)
		labels.append(l)

## Птицы: колония на скалистом островке, чайки над кеем и атоллом, попугаи
## над вулканом и карстом (из модуля фауны).
func _birds() -> void:
	var fauna: Node = get_node_or_null(^"Fauna")
	var f: Node = fauna.get_child(0) if fauna and fauna.get_child_count() > 0 else null
	if f == null or not f.has_method(&"spawn_flock"):
		return
	for e: Dictionary in world.showcase():
		var c: Vector2 = e.center
		var p := Vector3(c.x, 0.0, c.y)
		match StringName(e.type):
			&"islet":
				f.call(&"spawn_flock", &"gull", p, 9, 40.0)
				f.call(&"spawn_flock", &"gull", p + Vector3(15, 0, -10), 7, 35.0)
			&"cay", &"atoll", &"coral":
				f.call(&"spawn_flock", &"gull", p, 5, 70.0)
			&"volcanic", &"karst":
				f.call(&"spawn_flock", &"parrot", p, 7, 80.0)
