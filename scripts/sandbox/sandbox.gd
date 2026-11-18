class_name Sandbox
extends Node3D
## «Полигон»: все модели и механики игры в одном месте, быстрое перемещение.
## Мир — SandboxWorld (свой небольшой архипелаг), модули те же, что в матче;
## случайной фауны и обломков нет — всё разложено по зонам (SandboxZones).

const SCENE := "res://scenes/sandbox/sandbox.tscn"

const MODULES: Array[Dictionary] = [
	{"slot": "Build", "scene": "res://scenes/build/build_module.tscn"},
	{"slot": "Sea", "scene": "res://scenes/sea/sea.tscn"},
	{"slot": "Fauna", "scene": "res://scenes/fauna/fauna.tscn", "set": {"auto_populate": false}},
	{"slot": "Survival", "scene": "res://scenes/survival/survival.tscn", "set": {"spawn_debris": false, "spawn_wild": false}},
	{"slot": "Combat", "scene": "res://scenes/combat/combat.tscn"},
	{"slot": "Bots", "scene": "res://scenes/bots/bots.tscn"},
]

signal ready_to_play

var world: World
var player: Player
var zones: SandboxZones
var cheats: SandboxCheats
var panel: SandboxPanel
var is_built := false

static func start(tree: SceneTree) -> void:
	Game.end_session()
	tree.paused = false
	tree.change_scene_to_file(SCENE)

func _ready() -> void:
	world = $World as World
	if not world.is_ready:
		await world.world_ready
	# Флора: случайная рассадка по острову, зоны чистые, ряды всех видов.
	SandboxFlora.showcase = SandboxZones.flora_layout()
	SandboxFlora.clear = SandboxZones.clear_zones()
	var flora := SandboxFlora.new()
	$Flora.add_child(flora)
	for m in MODULES:
		var slot := get_node_or_null(String(m.slot))
		if slot == null or not ResourceLoader.exists(m.scene):
			continue
		var n := (load(m.scene) as PackedScene).instantiate()
		var props: Dictionary = m.get("set", {})
		for k: String in props:
			n.set(k, props[k])
		slot.add_child(n)
	# Без ботов из лобби, без лимита времени, флаги не ставятся сами.
	Game.pending_config = {}
	Game.start_match({"mode": "ffa", "teams": 4, "bots_enemy": 0, "bots_ally": 0, "minutes": 0, "auto_flags": false})
	if not flora.populated:
		await flora.flora_ready
	for i in 3:
		await get_tree().process_frame
	zones = SandboxZones.new()
	zones.name = "Zones"
	add_child(zones)
	zones.setup(world)
	await zones.build_all()
	# игрок — в центре
	var ps := load("res://scenes/player/player.tscn") as PackedScene
	player = ps.instantiate() as Player
	player.set(&"team", 0)
	player.set(&"starter_items", {&"axe_crude": 1, &"spear": 1})
	var hub: Dictionary = zones.points[&"hub"]
	player.position = hub.pos
	add_child(player)
	zones.player = player
	player.inventory.select(Inventory.HOTBAR - 1) # руки свободны — ничего не заслоняет вид
	zones.tame_demo()
	cheats = SandboxCheats.new()
	cheats.name = "Cheats"
	add_child(cheats)
	cheats.player = player
	cheats.teleport(hub.pos, hub.look)
	var layer := CanvasLayer.new()
	layer.layer = 12
	add_child(layer)
	panel = SandboxPanel.new()
	layer.add_child(panel)
	panel.setup(zones, cheats, world, player)
	is_built = true
	ready_to_play.emit()
	print("[sandbox] готов: точек %d, предметов %d" % [zones.points.size(), Items.items.size()])
	Events.toast.emit("Полигон: F1 или M — меню и перемещение, V — полёт")
