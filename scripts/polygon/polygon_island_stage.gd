class_name PolygonIslandStage
extends Node3D
## Остров (или целый архипелаг) полигона — отдельная сцена: в памяти только он,
## музей выгружен. Модули как в матче (флора, море с рифами и живностью, фауна, бой,
## стройка), игрок, читы, то же меню (F1/M: «← В музей», другие острова, мир, реплей).

const SCENE := "res://scenes/polygon/polygon_island.tscn"

const MODULES: Array[Dictionary] = [
	{"slot": "Build", "scene": "res://scenes/build/build_module.tscn"},
	{"slot": "Sea", "scene": "res://scenes/sea/sea.tscn"},
	{"slot": "Fauna", "scene": "res://scenes/fauna/fauna.tscn", "set": {"auto_populate": true}},
	{"slot": "Combat", "scene": "res://scenes/combat/combat.tscn"},
]

signal ready_to_play

static var island_id := "volcanic"
static var launch: Dictionary = {}

var world: PolygonIslandWorld
var player: Player
var cheats: SandboxCheats
var panel: PolygonPanel
var flora: Flora
var recorder: ReplayRecorder
var is_built := false
var observer := false
var replay_mode := false

static func open(tree: SceneTree, id: String, opts: Dictionary = {}) -> void:
	island_id = id
	launch = opts
	Game.end_session()
	tree.paused = false
	tree.change_scene_to_file(SCENE)

static func back_to_museum(tree: SceneTree) -> void:
	Polygon.start(tree)

func _ready() -> void:
	add_to_group(&"polygon")
	add_to_group(&"sandbox")
	replay_mode = bool(launch.get("replay_mode", false))
	world = $World as PolygonIslandWorld
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
		if replay_mode and m.slot == "Fauna":
			n.set(&"auto_populate", false)
		slot.add_child(n)
	Game.pending_config = {}
	Game.start_match({"mode": "ffa", "teams": 4, "bots_enemy": 0, "bots_ally": 0, "minutes": 0, "auto_flags": false})
	if not flora.populated:
		await flora.flora_ready
	for i in 3:
		await get_tree().process_frame
	var sp := spawn_pos()
	var ps := load("res://scenes/player/player.tscn") as PackedScene
	player = ps.instantiate() as Player
	player.set(&"team", 0)
	player.set(&"starter_items", {})
	player.position = sp
	add_child(player)
	player.inventory.select(Inventory.HOTBAR - 1)
	cheats = SandboxCheats.new()
	cheats.name = "Cheats"
	add_child(cheats)
	cheats.player = player
	cheats.world = world
	cheats.god = true
	cheats.infinite = false
	var look: Variant = launch.get("look", null)
	cheats.teleport(launch.get("pos", sp), look if look != null else sp + (Vector3(-sp.x, 0, -sp.z).normalized() * 20.0 + Vector3.UP * 2.0))
	if not replay_mode:
		var layer := CanvasLayer.new()
		layer.layer = 12
		add_child(layer)
		panel = PolygonPanel.new()
		layer.add_child(panel)
		panel.setup(self)
		var hint := Label.new()
		hint.text = "%s · F1 или M — меню (← в музей, другие острова, погода, реплей) · V — полёт" % PolygonIslands.name_of(island_id)
		hint.add_theme_font_size_override(&"font_size", 15)
		hint.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.75))
		hint.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.8))
		hint.add_theme_constant_override(&"outline_size", 4)
		hint.position = Vector2(16, 12)
		layer.add_child(hint)
		recorder = ReplayRecorder.new()
		recorder.name = "ReplayRecorder"
		add_child(recorder)
		recorder.setup(self, {"scene": "island", "island": island_id, "seed": world.seed_value})
	is_built = true
	if replay_mode:
		ReplayPlayback.attach(self)
	ready_to_play.emit()
	print("[polygon-island] готов: %s, флора %s" % [island_id, str(flora.stats)])
	if not replay_mode:
		Events.toast.emit(PolygonIslands.name_of(island_id) + " · F1 — меню")

## Место появления: пляж первого (или домашнего) острова, лицом к суше.
func spawn_pos() -> Vector3:
	var a := world.arch
	if a is ShowcaseArch and not (a as ShowcaseArch).showcase.is_empty():
		var e: Dictionary = (a as ShowcaseArch).showcase[0]
		var b: Vector2 = e.beach
		return Vector3(b.x, maxf(world.height_at(b.x, b.y), world.water_level() + 0.1) + 0.3, b.y)
	for I in a.islands:
		if int(I.get("team", -1)) == 0:
			return world.spawn_point(0)
	if not a.islands.is_empty():
		var I0: Dictionary = a.islands[0]
		var bp := a.beach_point(I0, 0.0)
		return Vector3(bp.x, maxf(world.height_at(bp.x, bp.y), 0.1) + 0.3, bp.y)
	return Vector3(0, 5, 0)

func set_observer(on: bool) -> void:
	observer = on
	if player == null:
		return
	if on and player.is_in_group(&"characters"):
		player.remove_from_group(&"characters")
	elif not on and not player.is_in_group(&"characters"):
		player.add_to_group(&"characters")

func aim_point() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return player.global_position if player else Vector3.ZERO
	var from := cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from - cam.global_basis.z * 60.0)
	if player:
		q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		return hit.position
	var p := from - cam.global_basis.z * 8.0
	return Vector3(p.x, world.height_at(p.x, p.z), p.z)
