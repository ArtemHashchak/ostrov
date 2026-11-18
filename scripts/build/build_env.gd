class_name BuildEnv
extends RefCounted
## Доступ модуля BUILD к миру без жёстких ссылок: узел группы `world`
## (CONTRACT_G1), иначе — текущая сцена с height_at (тестовый остров),
## иначе — плоская земля. Плюс инвентарь персонажа.

static func tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

static var _world_cache: Node = null

static func world() -> Node:
	if _world_cache and is_instance_valid(_world_cache) and _world_cache.is_inside_tree():
		return _world_cache
	_world_cache = _find_world()
	return _world_cache

static func _find_world() -> Node:
	var t := tree()
	if t == null:
		return null
	var w := t.get_first_node_in_group(&"world")
	if w:
		return w
	var cs := t.current_scene
	if cs and cs.has_method(&"height_at"):
		return cs
	# тестовый раннер: сцена-остров — ребёнок корня
	for n in t.root.get_children():
		if n.has_method(&"height_at"):
			return n
		for c in n.get_children():
			if c.has_method(&"height_at"):
				return c
	return null

static func height_at(x: float, z: float) -> float:
	var w := world()
	if w and w.has_method(&"height_at"):
		return float(w.call(&"height_at", x, z))
	return 1.0

static func water_level() -> float:
	var w := world()
	if w and w.has_method(&"water_level"):
		return float(w.call(&"water_level"))
	return 0.0

static func now() -> float:
	return Time.get_ticks_msec() / 1000.0

## Высота волны над уровнем воды в точке (x,z).
static func wave_height(x: float, z: float) -> float:
	var w := world()
	if w and w.has_method(&"wave_height"):
		return float(w.call(&"wave_height", x, z))
	var t := now()
	return sin(t * 0.9 + x * 0.15) * 0.10 + sin(t * 1.3 + z * 0.21) * 0.07 + sin(t * 0.55 + (x + z) * 0.05) * 0.05

static func water_surface(x: float, z: float) -> float:
	return water_level() + wave_height(x, z)

static func is_land(x: float, z: float) -> bool:
	var w := world()
	if w and w.has_method(&"is_land"):
		return bool(w.call(&"is_land", x, z))
	return height_at(x, z) > water_level() + 0.05

static func weather() -> StringName:
	var w := world()
	if w and w.has_method(&"weather"):
		return StringName(w.call(&"weather"))
	return &"clear"

## Остров команды (или пусто, если мир не знает островов).
static func home_island(team: int) -> Dictionary:
	var w := world()
	if w == null or not w.has_method(&"islands"):
		return {}
	for isl: Dictionary in w.call(&"islands"):
		if String(isl.get("kind", "")) == "home" and int(isl.get("team", -1)) == team:
			return isl
	return {}

static func on_own_island(team: int, pos: Vector3) -> bool:
	var isl := home_island(team)
	if isl.is_empty():
		return true # мир без островов (тесты) — разрешаем
	var c: Vector2 = isl.get("center", Vector2.ZERO)
	return Vector2(pos.x, pos.z).distance_to(c) <= float(isl.get("radius", 1e9))

# --- инвентарь (класс Inventory от PLAYER/UI; утиная типизация) ---

static func inventory(ch: Node) -> Node:
	if ch == null:
		return null
	var v: Variant = ch.get(&"inventory")
	if v is Node:
		return v as Node
	return ch.get_node_or_null(^"Inventory")

static func inv_count(ch: Node, id: StringName) -> int:
	var inv := inventory(ch)
	if inv == null or not inv.has_method(&"count"):
		return 0
	var n := int(inv.call(&"count", id))
	# камень: в ядре это stone, в контракте — rock
	if id == &"stone":
		n += int(inv.call(&"count", &"rock"))
	return n

static func inv_remove(ch: Node, id: StringName, n: int) -> bool:
	var inv := inventory(ch)
	if inv == null or not inv.has_method(&"remove"):
		return false
	if bool(inv.call(&"remove", id, n)):
		return true
	if id == &"stone":
		return bool(inv.call(&"remove", &"rock", n))
	return false

static func toast(text: String) -> void:
	Events.toast.emit(text)
