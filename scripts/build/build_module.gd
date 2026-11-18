class_name BuildModule
extends Node
## Корневой узел модуля BUILD. Добавь его в сцену матча (scenes/build/build_module.tscn).
## Регистрирует предметы и клавиши (B — книга стройки, R — поворот чертежа),
## вешает BuildMode на игроков, даёт API для ботов и других модулей.

const SOCKET_SNAP := 2.2
const RAFT_OFFSETS: Array[Vector3] = [Vector3(0, 0, -3.0), Vector3(0, 0, 3.0), Vector3(2.04, 0, 0), Vector3(-2.04, 0, 0)]

## Если UI делает свою «книгу» со стройкой — выключи (и вызывай open_menu()/start_place()).
var menu_hotkey_enabled: bool = true

static func instance() -> BuildModule:
	var t := BuildEnv.tree()
	return t.get_first_node_in_group(&"build_module") as BuildModule if t else null

func _ready() -> void:
	add_to_group(&"build_module")
	_ensure_items()
	_ensure_actions()
	for p in get_tree().get_nodes_in_group(&"player"):
		_attach(p)
	Events.character_spawned.connect(_on_spawned)

func _ensure_items() -> void:
	if Items.get_item(&"rope") == null:
		Items.register_item(&"rope", "Верёвка", &"resource", 20, 0.3)
	if Items.get_item(&"stick") == null:
		Items.register_item(&"stick", "Палка", &"resource", 20, 0.5)

func _ensure_actions() -> void:
	_add_key_action(&"build_menu", KEY_B)
	_add_key_action(&"build_rotate", KEY_R)

static func _add_key_action(action: StringName, key: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)

func _on_spawned(ch: Node) -> void:
	if ch.is_in_group(&"player"):
		_attach(ch)

func _attach(p: Node) -> void:
	if p.get_node_or_null(^"BuildMode") == null:
		var bm := BuildMode.new()
		bm.name = "BuildMode"
		p.add_child(bm)

func structures_root() -> Node:
	return get_parent() if get_parent() else get_tree().current_scene

# ================= API (игрок, боты, другие модули) =================

## Поставить чертёж. anchor — только для мостов (см. raft_socket/shore_raft).
func place_blueprint(def_id: StringName, xform: Transform3D, team: int,
		anchor: Dictionary = {}, context: Dictionary = {}) -> Blueprint:
	if def_id == &"platform" and context.is_empty():
		context = platform_ctx(xform)
	var bp := Blueprint.new().setup(def_id, team, context)
	bp.name = "%s_%d" % [def_id, Time.get_ticks_msec() % 100000]
	bp.base_xform = xform
	if BuildDefs.kind_of(def_id) == &"raft":
		bp.anchor = anchor if not anchor.is_empty() else {"type": &"shore"}
		var par: Blueprint = anchor.get("parent") as Blueprint
		if par and is_instance_valid(par):
			par.raft_children.append(bp)
	structures_root().add_child(bp)
	bp.global_transform = xform
	Events.blueprint_placed.emit(bp, def_id)
	return bp

## Контекст платформы: сваи до земли.
func platform_ctx(xform: Transform3D) -> Dictionary:
	var xf := xform
	var ground := func(lx: float, lz: float) -> float:
		var w: Vector3 = xf * Vector3(lx, 0.0, lz)
		return BuildEnv.height_at(w.x, w.z) - xf.origin.y
	return {"ground": ground}

func place_flag(team: int, pos: Vector3, yaw: float = 0.0) -> TeamFlag:
	var f := TeamFlag.new().setup(team)
	f.name = "Flag_%d" % team
	structures_root().add_child(f)
	f.global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	Game.set_flag_placed(team, pos)
	return f

func flag_of(team: int) -> TeamFlag:
	for n in get_tree().get_nodes_in_group(&"flag"):
		var f := n as TeamFlag
		if f and f.team == team:
			return f
	return null

func blueprints(team: int = -1) -> Array[Blueprint]:
	var out: Array[Blueprint] = []
	for n in get_tree().get_nodes_in_group(&"buildable"):
		var b := n as Blueprint
		if b and (team < 0 or b.team == team):
			out.append(b)
	return out

## Свободный сокет для привязки (стена к стене/платформе, крыша, дверь...).
## Возвращает {xform, host} или {}.
func find_socket(tag: StringName, near: Vector3, max_d: float = SOCKET_SNAP) -> Dictionary:
	var best: Dictionary = {}
	var best_d := max_d
	for b in blueprints():
		if b.is_raft() or b.global_position.distance_to(near) > 12.0:
			continue
		for s: Dictionary in BuildDefs.sockets(b.def_id):
			if not (s.tags as Array).has(tag):
				continue
			var wx: Transform3D = b.base_xform * (s.xform as Transform3D)
			var d := wx.origin.distance_to(near)
			if d < best_d and _socket_free(tag, wx.origin):
				best_d = d
				best = {"xform": wx, "host": b, "ctx": s.get("ctx", {})}
	if tag == &"stairs" and not best.is_empty() and (best.host as Blueprint).def_id == &"platform":
		best = _fit_stairs(best.host as Blueprint)
	return best

## Лестница к платформе: от настила до земли (рельеф под лестницей может быть ниже/выше).
func _fit_stairs(plat: Blueprint) -> Dictionary:
	var deck_y := plat.base_xform.origin.y + BuildDefs.DECK_H
	var rise := BuildDefs.DECK_H
	var xf := Transform3D()
	for i in 4:
		var run := BuildDefs.stairs_dims({"rise": rise}).y
		xf = plat.base_xform * Transform3D(Basis(), Vector3(0, 0, 1.5 + run * 0.5 + 0.1))
		var foot: Vector3 = xf * Vector3(0, 0, run * 0.5)
		var g := BuildEnv.height_at(foot.x, foot.z)
		rise = clampf(deck_y - g, 0.4, 4.0)
	xf.origin.y = deck_y - rise
	return {"xform": xf, "host": plat, "ctx": {"rise": rise}}

func _socket_free(tag: StringName, at: Vector3) -> bool:
	for b in blueprints():
		if StringName(BuildDefs.INFO.get(b.def_id, {}).get("snap", &"")) == tag and b.base_xform.origin.distance_to(at) < 0.45:
			return false
	return true

## Сокет для новой секции моста у существующей секции: {xform, parent, offset} или {}.
func raft_socket(near: Vector3, max_d: float = 3.0) -> Dictionary:
	var best: Dictionary = {}
	var best_d := max_d
	for n in get_tree().get_nodes_in_group(&"raft_deck"):
		var b := n as Blueprint
		if b == null or b.is_drifting():
			continue
		var base := b.base_now()
		for off in RAFT_OFFSETS:
			var o := Transform3D(Basis(), off)
			var wx := base * o
			var d := Vector2(wx.origin.x - near.x, wx.origin.z - near.z).length()
			if d < best_d and _raft_slot_free(wx.origin):
				best_d = d
				best = {"xform": wx, "parent": b, "offset": o}
	return best

func _raft_slot_free(at: Vector3) -> bool:
	for n in get_tree().get_nodes_in_group(&"raft_deck"):
		var b := n as Blueprint
		if b and Vector2(b.base_now().origin.x - at.x, b.base_now().origin.z - at.z).length() < 1.2:
			return false
	return true

## Первая секция моста у берега: «корма» (+Z) должна касаться суши.
## Возвращает {ok, xform, reason}.
func shore_raft(pos: Vector3, yaw: float) -> Dictionary:
	var wl := BuildEnv.water_level()
	var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, wl, pos.z))
	if BuildEnv.height_at(pos.x, pos.z) > wl - 0.3:
		return {"ok": false, "xform": xf, "reason": "Слишком мелко — ставь на воду"}
	var touches := false
	for t in [1.0, 1.5, 2.0, 2.6]:
		for lx in [-0.8, 0.0, 0.8]:
			var w: Vector3 = xf * Vector3(lx, 0.0, t)
			if BuildEnv.height_at(w.x, w.z) > wl - 0.15:
				touches = true
	if not touches:
		return {"ok": false, "xform": xf, "reason": "Мост начинается у берега или у другой секции"}
	if not _raft_slot_free(xf.origin):
		return {"ok": false, "xform": xf, "reason": "Место занято"}
	return {"ok": true, "xform": xf, "reason": ""}

## Проверка постановки на землю. Пусто — можно, иначе причина.
func check_ground(def_id: StringName, xform: Transform3D) -> String:
	var info: Dictionary = BuildDefs.INFO.get(def_id, {})
	if bool(info.get("socket_only", false)):
		return "Ставится только на постройку"
	var wl := BuildEnv.water_level()
	var o := xform.origin
	if BuildEnv.height_at(o.x, o.z) < wl + 0.1:
		return "Нельзя строить в воде — для воды есть мост"
	var pts: Array[Vector3] = []
	match def_id:
		&"wall", &"wall_window", &"wall_door":
			pts = [xform * Vector3(-1.5, 0, 0), xform * Vector3(1.5, 0, 0)]
		&"platform", &"stairs":
			pts = [xform * Vector3(-1.4, 0, -1.4), xform * Vector3(1.4, 0, -1.4), xform * Vector3(-1.4, 0, 1.4), xform * Vector3(1.4, 0, 1.4)]
		_:
			pts = [xform * Vector3(-0.8, 0, 0), xform * Vector3(0.8, 0, 0)]
	var lo := 1e9
	var hi := -1e9
	for p in pts:
		var h := BuildEnv.height_at(p.x, p.z)
		lo = minf(lo, h)
		hi = maxf(hi, h)
	var max_diff := 1.9 if def_id == &"platform" else 0.9
	if hi - lo > max_diff:
		return "Слишком крутой склон"
	var r := float(info.get("radius", 1.5))
	for b in blueprints():
		var rb := float(BuildDefs.INFO.get(b.def_id, {}).get("radius", 1.5))
		var dv := b.base_xform.origin - o
		if Vector2(dv.x, dv.z).length() < (r + rb) * 0.55 and absf(dv.y) < 1.5:
			return "Мешает другая постройка"
	return ""
