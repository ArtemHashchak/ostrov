class_name BuildModule
extends Node
## Корневой узел модуля BUILD. Добавь его в сцену матча (scenes/build/build_module.tscn).
## Регистрирует предметы и клавиши (B — книга стройки, R — поворот чертежа),
## вешает BuildMode на игроков, даёт API для ботов и других модулей.

const SOCKET_SNAP := 2.2
const TERRITORY_R := 40.0          # территория флага: чужим строить нельзя, своим — быстрее
const PILE_MAX_DEPTH := 6.0        # сваи достают до дна не глубже 6 м
const RAFT_OFFSETS: Array[Vector3] = [Vector3(0, 0, -3.0), Vector3(0, 0, 3.0), Vector3(2.04, 0, 0), Vector3(-2.04, 0, 0)]

## Если UI делает свою «книгу» со стройкой — выключи (и вызывай open_menu()/start_place()).
var menu_hotkey_enabled: bool = true

## Каталог чертежей для ботов/UI: {id: {name, kind, cost, radius, size, snap, socket_only}}.
var defs: Dictionary:
	get:
		return BuildDefs.catalog()

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

func _exit_tree() -> void:
	# статические кэши материалов/мешей — иначе утечки RID при выходе
	BuildMats.clear_cache()
	BuildDefs._catalog.clear()

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

## Узел постройки нужного класса (ворота, сундук, поленница, колья — со своим поведением).
static func new_blueprint(def_id: StringName) -> Blueprint:
	match def_id:
		&"gate", &"raft_gate":
			return BuildGate.new()
		&"chest":
			return BuildChest.new()
		&"log_holder":
			return BuildLogHolder.new()
		&"spikes":
			return BuildSpikes.new()
	return Blueprint.new()

## Чертежи, которым нужен рельеф под ними (сваи, ноги).
static func needs_ground_ctx(def_id: StringName) -> bool:
	return def_id in [&"platform", &"watchtower", &"raft_pile"]

## Поставить чертёж. anchor — только для мостов (см. raft_socket/shore_raft).
## null — на чужой территории (у чужого флага) строить нельзя.
func place_blueprint(def_id: StringName, xform: Transform3D, team: int,
		anchor: Dictionary = {}, context: Dictionary = {}) -> Blueprint:
	if territory_blocks(team, xform.origin):
		BuildEnv.toast("Чужая территория — строить нельзя")
		return null
	if needs_ground_ctx(def_id) and context.is_empty():
		context = platform_ctx(xform)
	var bp := new_blueprint(def_id).setup(def_id, team, context)
	bp.name = "%s_%d" % [def_id, Time.get_ticks_msec() % 100000]
	bp.base_xform = xform
	if def_id == &"raft_pile":
		bp.anchor = {"type": &"pile"}   # стоит на сваях сам по себе
	elif BuildDefs.kind_of(def_id) == &"raft":
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

# ================= территория флага =================

## Чья территория в точке: команда, чей стоящий флаг ближе TERRITORY_R, иначе -1.
func territory_of(pos: Vector3) -> int:
	var best := -1
	var best_d := TERRITORY_R
	for n in get_tree().get_nodes_in_group(&"flag"):
		var f := n as TeamFlag
		if f == null or f.preview or f.fallen:
			continue
		var d := Vector2(f.global_position.x - pos.x, f.global_position.z - pos.z).length()
		if d <= best_d:
			best_d = d
			best = f.team
	return best

## Команде team здесь строить нельзя (чужая территория).
func territory_blocks(team: int, pos: Vector3) -> bool:
	var t := territory_of(pos)
	return t >= 0 and team >= 0 and t != team

## Стоящие флаги: [{team, pos, radius}] — для рамки территории и ботов.
func territories() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for n in get_tree().get_nodes_in_group(&"flag"):
		var f := n as TeamFlag
		if f and not f.preview and not f.fallen:
			out.append({"team": f.team, "pos": f.global_position, "radius": TERRITORY_R})
	return out

func flag_of(team: int) -> TeamFlag:
	for n in get_tree().get_nodes_in_group(&"flag"):
		var f := n as TeamFlag
		if f and f.team == team:
			return f
	return null

## Все постройки команды (для ботов): стены, ворота, мосты, сундуки...
func structures_of(team: int) -> Array[Blueprint]:
	return blueprints(team)

## Постройки команды по чертежу (например, сундуки или поленницы).
func structures_by_def(team: int, def_id: StringName) -> Array[Blueprint]:
	var out: Array[Blueprint] = []
	for b in blueprints(team):
		if b.def_id == def_id:
			out.append(b)
	return out

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
		if b.is_raft() or b.base_xform.origin.distance_to(near) > 12.0:
			continue
		for s: Dictionary in BuildDefs.sockets(b.def_id):
			if not (s.tags as Array).has(tag):
				continue
			var wx: Transform3D = b.base_xform * (s.xform as Transform3D)
			var d := wx.origin.distance_to(near)
			if d < best_d and _socket_free(tag, wx.origin):
				best_d = d
				best = {"xform": wx, "host": b, "ctx": s.get("ctx", {})}
	if tag == &"stairs" and not best.is_empty() and (best.host as Blueprint).def_id in [&"platform", &"watchtower"]:
		best = _fit_stairs(best.host as Blueprint)
	return best

## Лестница к платформе: от настила до земли (рельеф под лестницей может быть ниже/выше).
func _fit_stairs(plat: Blueprint) -> Dictionary:
	var dh := BuildDefs.deck_h(plat.def_id)
	var deck_y := plat.base_xform.origin.y + dh
	var rise := dh
	var edge := 1.4 if plat.def_id == &"watchtower" else 1.6
	var xf := Transform3D()
	for i in 4:
		var run := BuildDefs.stairs_dims({"rise": rise}).y
		xf = plat.base_xform * Transform3D(Basis(), Vector3(0, 0, edge + run * 0.5))
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

## Секция на сваях посреди воды (без берега и соседей): {ok, xform, reason}.
func pile_raft(pos: Vector3, yaw: float) -> Dictionary:
	var wl := BuildEnv.water_level()
	var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, wl, pos.z))
	var deepest := 0.0
	var shallowest := 99.0
	for c in [Vector2(-0.85, -1.2), Vector2(0.85, -1.2), Vector2(-0.85, 1.2), Vector2(0.85, 1.2)]:
		var w: Vector3 = xf * Vector3(c.x, 0.0, c.y)
		var depth := wl - BuildEnv.height_at(w.x, w.z)
		deepest = maxf(deepest, depth)
		shallowest = minf(shallowest, depth)
	if shallowest < 0.3:
		return {"ok": false, "xform": xf, "reason": "Слишком мелко — ставь на воду"}
	if deepest > PILE_MAX_DEPTH:
		return {"ok": false, "xform": xf, "reason": "Слишком глубоко для свай (до %d м)" % int(PILE_MAX_DEPTH)}
	if not _raft_slot_free(xf.origin):
		return {"ok": false, "xform": xf, "reason": "Место занято"}
	return {"ok": true, "xform": xf, "reason": ""}

## Мост между островами для бота: где ставить первую секцию и сколько секций нужно.
## from/to — индекс в world.islands() или словарь острова ({center: Vector2, radius}).
## Возвращает {ok, xform (первая секция у берега from), yaw, dir: Vector3, sections: int,
##   length: float (метров воды), start: Vector3 (берег from), end: Vector3 (берег to), piles: int}
## Сваи (piles) — сколько секций по пути можно поставить на сваях (глубина ≤ 6 м).
func find_bridge_target(from_island: Variant, to_island: Variant) -> Dictionary:
	var a := _island_dict(from_island)
	var b := _island_dict(to_island)
	if a.is_empty() or b.is_empty():
		return {"ok": false, "reason": "нет островов"}
	var ca: Vector2 = a.get("center", Vector2.ZERO)
	var cb: Vector2 = b.get("center", Vector2.ZERO)
	var base_dir := (cb - ca).normalized()
	var best: Dictionary = {}
	# перебираем несколько параллельных линий — ищем самый короткий пролив
	for side: float in [0.0, -12.0, 12.0, -24.0, 24.0, -36.0, 36.0]:
		var perp := Vector2(-base_dir.y, base_dir.x) * side
		var r := _bridge_line(ca + perp, cb + perp, base_dir)
		if r.ok and (best.is_empty() or float(r.length) < float(best.length)):
			best = r
	if best.is_empty():
		return {"ok": false, "reason": "не нашёл берег"}
	return best

func _island_dict(v: Variant) -> Dictionary:
	if v is Dictionary:
		return v
	var w := BuildEnv.world()
	if w and w.has_method(&"islands") and (v is int):
		var arr: Array = w.call(&"islands")
		if int(v) >= 0 and int(v) < arr.size():
			return arr[int(v)]
	return {}

func _bridge_line(ca: Vector2, cb: Vector2, d2: Vector2) -> Dictionary:
	var total := ca.distance_to(cb)
	var step := 0.5
	# последняя суша острова A по пути
	var t := 0.0
	var shore_a := -1.0
	var in_land := BuildEnv.is_land(ca.x, ca.y)
	while t < total:
		var p := ca + d2 * t
		var land := BuildEnv.is_land(p.x, p.y)
		if land:
			in_land = true
		elif in_land:
			shore_a = t
			break
		t += step
	if shore_a < 0.0:
		return {"ok": false}
	# первая суша острова B по пути
	var shore_b := -1.0
	t = shore_a + 1.0
	while t < total + 30.0:
		var p2 := ca + d2 * t
		if BuildEnv.is_land(p2.x, p2.y):
			shore_b = t
			break
		t += step
	if shore_b < 0.0:
		return {"ok": false}
	var dir := Vector3(d2.x, 0.0, d2.y)
	var yaw := atan2(-dir.x, -dir.z)     # -Z секции смотрит на остров B, корма (+Z) — к берегу A
	var wl := BuildEnv.water_level()
	# первая секция: сдвигаемся от берега, пока shore_raft не согласится
	var first: Dictionary = {}
	var k := 0.0
	while k < 4.0:
		var s := ca + d2 * (shore_a + 0.6 + k)
		var r := shore_raft(Vector3(s.x, wl, s.y), yaw)
		if r.ok:
			first = r
			first["at"] = shore_a + 0.6 + k
			break
		k += 0.25
	if first.is_empty():
		return {"ok": false}
	var water := shore_b - float(first.at) + BuildDefs.RAFT_L * 0.5
	var n := maxi(1, int(ceil(water / BuildDefs.RAFT_L)))
	var piles := 0
	for i in n:
		var q := ca + d2 * (float(first.at) + i * BuildDefs.RAFT_L)
		if wl - BuildEnv.height_at(q.x, q.y) <= PILE_MAX_DEPTH:
			piles += 1
	var sa := ca + d2 * shore_a
	var sb := ca + d2 * shore_b
	return {"ok": true, "xform": first.xform, "yaw": yaw, "dir": dir, "sections": n, "length": water,
		"start": Vector3(sa.x, BuildEnv.height_at(sa.x, sa.y), sa.y),
		"end": Vector3(sb.x, BuildEnv.height_at(sb.x, sb.y), sb.y), "piles": piles}

## Следующая секция моста вперёд (-Z) от данной: {xform, parent, offset} или {}.
func next_raft_slot(section: Blueprint) -> Dictionary:
	if section == null or not is_instance_valid(section):
		return {}
	return raft_socket(section.base_now() * Vector3(0, 0, -BuildDefs.RAFT_L), 1.0)

## Проверка постановки на землю. Пусто — можно, иначе причина.
func check_ground(def_id: StringName, xform: Transform3D, team: int = -1) -> String:
	var info: Dictionary = BuildDefs.INFO.get(def_id, {})
	if bool(info.get("socket_only", false)):
		return "Ставится только на постройку"
	if territory_blocks(team, xform.origin):
		return "Чужая территория — у чужого флага строить нельзя"
	var wl := BuildEnv.water_level()
	var o := xform.origin
	if BuildEnv.height_at(o.x, o.z) < wl + 0.1:
		return "Нельзя строить в воде — для воды есть мост"
	var pts: Array[Vector3] = []
	match def_id:
		&"wall", &"wall_window", &"wall_door":
			pts = [xform * Vector3(-1.5, 0, 0), xform * Vector3(1.5, 0, 0)]
		&"platform", &"stairs", &"watchtower", &"foundation":
			pts = [xform * Vector3(-1.4, 0, -1.4), xform * Vector3(1.4, 0, -1.4), xform * Vector3(-1.4, 0, 1.4), xform * Vector3(1.4, 0, 1.4)]
		&"palisade", &"gate", &"spikes":
			pts = [xform * Vector3(-1.5, 0, 0), xform * Vector3(1.5, 0, 0)]
		_:
			pts = [xform * Vector3(-0.8, 0, 0), xform * Vector3(0.8, 0, 0)]
	var lo := 1e9
	var hi := -1e9
	for p in pts:
		var h := BuildEnv.height_at(p.x, p.z)
		lo = minf(lo, h)
		hi = maxf(hi, h)
	var max_diff := 0.9
	match def_id:
		&"platform", &"watchtower": max_diff = 1.9
		&"palisade", &"spikes", &"foundation": max_diff = 1.2
	if hi - lo > max_diff:
		return "Слишком крутой склон"
	var r := float(info.get("radius", 1.5))
	for b in blueprints():
		var rb := float(BuildDefs.INFO.get(b.def_id, {}).get("radius", 1.5))
		var dv := b.base_xform.origin - o
		if Vector2(dv.x, dv.z).length() < (r + rb) * 0.55 and absf(dv.y) < 1.5:
			return "Мешает другая постройка"
	return ""
