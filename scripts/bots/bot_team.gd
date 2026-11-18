class_name BotTeam
extends RefCounted
## Общий план команды ботов: база у флага (стены вокруг флага, шалаш), мост
## из связок брёвен к следующему острову на пути к врагу, выбор цели для набега,
## оборона (сжечь/срубить чужой мост к нашему острову). Боты берут задания у команды.

const BASE_PLAN: Array[Dictionary] = [
	{"def": &"wall", "off": Vector3(0, 0, -1.5), "yaw": 0.0},
	{"def": &"wall_door", "off": Vector3(0, 0, 1.5), "yaw": 0.0},
	{"def": &"wall", "off": Vector3(-1.5, 0, 0), "yaw": PI * 0.5},
	{"def": &"wall", "off": Vector3(1.5, 0, 0), "yaw": PI * 0.5},
	{"def": &"shelter", "off": Vector3(5.5, 0, 3.0), "yaw": 0.0},
]
const MAX_SECTIONS := 70

var team: int = 1
var bots: Array = []                 # Array[Bot]
var nav: BotNav
var module: Node                     # Bots
var home: Dictionary = {}            # остров команды
var plan_i: int = 0
var base_done: bool = false
var active: Blueprint = null         # что строим сейчас
var bridge: Dictionary = {}          # {pair, from, to, dir, root, tip, sections, done}
var bridges_built: int = 0
var target_team: int = -1
var reserved: Dictionary = {}        # instance_id цели -> bot (деревья, камни)
var _replan_t: float = 0.0
var _failed_spots: Dictionary = {}

func _init(t: int, n: BotNav, m: Node) -> void:
	team = t
	nav = n
	module = m
	home = nav.home_island(team)

func flag_pos() -> Vector3:
	if team < Game.teams.size() and Game.teams[team].flag_placed:
		return Game.teams[team].flag_pos
	var w := nav.world
	return w.call(&"spawn_point", team) as Vector3 if w else Vector3.ZERO

func flag_alive() -> bool:
	return team < Game.teams.size() and Game.teams[team].flag_alive

func home_id() -> int:
	return int(home.get("id", -1))

## Флаг ставит MatchDirector (GAME); если его нет (тесты) — сами.
func ensure_flag() -> void:
	if team >= Game.teams.size() or Game.teams[team].flag_placed:
		return
	var bm := BuildModule.instance()
	var p := flag_pos()
	if bm:
		bm.place_flag(team, Vector3(p.x, nav.h(p.x, p.z), p.z), 0.0)
	else:
		Game.set_flag_placed(team, p)

func living_bots() -> Array:
	var out: Array = []
	for b in bots:
		if is_instance_valid(b) and not (b as Bot).is_dead():
			out.append(b)
	return out

# ------------------------------------------------------------------ стройка

func _bm() -> BuildModule:
	return BuildModule.instance()

## Текущая недостроенная постройка команды (или новая по плану). null — строить нечего.
func current_build() -> Blueprint:
	if is_instance_valid(active) and not active.is_complete() and not active.is_queued_for_deletion():
		return active
	active = null
	var bm := _bm()
	if bm == null:
		return null
	# недостроенные чертежи команды (в т.ч. начатые игроком-союзником) — сначала они
	var fp := flag_pos()
	var best: Blueprint = null
	var bd := 60.0
	for b in bm.blueprints(team):
		if b.is_complete() or b.is_drifting() or b.is_raft():
			continue
		var d := b.global_position.distance_to(fp)
		if d < bd:
			bd = d
			best = b
	if best:
		active = best
		return active
	if not base_done:
		active = _place_next_base()
		if active:
			return active
	if bridge.get("done", false) or bridge.is_empty():
		_choose_bridge()
	if not bridge.is_empty() and not bridge.get("done", false):
		active = _next_section()
	return active

func _place_next_base() -> Blueprint:
	var bm := _bm()
	var fp := flag_pos()
	while plan_i < BASE_PLAN.size():
		var it: Dictionary = BASE_PLAN[plan_i]
		plan_i += 1
		var off: Vector3 = it.off
		var p := fp + off
		p.y = nav.h(p.x, p.z)
		var xf := Transform3D(Basis(Vector3.UP, float(it.yaw)), p)
		var why := bm.check_ground(it.def, xf, team)
		if why != "":
			continue
		var bp := bm.place_blueprint(it.def, xf, team)
		if bp:
			return bp
	base_done = true
	return null

## Ближайшая цель — команда с живым флагом, маршрут до острова которой самый короткий.
func choose_target() -> int:
	var best := -1
	var best_c := INF
	var hid := home_id()
	for t in Game.teams:
		if t.id == team or not t.flag_alive or t.eliminated:
			continue
		var I := nav.home_island(t.id)
		if I.is_empty():
			continue
		var c := (I.center as Vector2).distance_to(home.get("center", Vector2.ZERO) as Vector2)
		if nav.reachable(hid, int(I.id), 0.0):
			c *= 0.5
		if c < best_c:
			best_c = c
			best = t.id
	target_team = best
	return best

## Следующий недостающий мост по пути к цели: идём по графу «все соседи», ребро без
## готового моста — то, что строим. Мосты строятся от уже доступного острова.
func _choose_bridge() -> void:
	bridge = {}
	var tt := choose_target()
	if tt < 0:
		return
	var goal := int(nav.home_island(tt).get("id", -1))
	var hid := home_id()
	if hid < 0 or goal < 0:
		return
	# Дейкстра по парам: готовое ребро — дёшево, неготовое — по длине воды
	var dist: Dictionary = {hid: 0.0}
	var prev: Dictionary = {}
	var open: Array[int] = [hid]
	var done: Dictionary = {}
	while not open.is_empty():
		var bi := 0
		for i in open.size():
			if float(dist[open[i]]) < float(dist[open[bi]]):
				bi = i
		var u: int = open[bi]
		open.remove_at(bi)
		if done.has(u):
			continue
		done[u] = true
		if u == goal:
			break
		for k in nav.pairs:
			var P: Dictionary = nav.pairs[k]
			var v := -1
			if int(P.a) == u:
				v = int(P.b)
			elif int(P.b) == u:
				v = int(P.a)
			if v < 0 or _failed_spots.has(k):
				continue
			var c := 5.0 if nav.reachable(u, v, 0.0) else float(P.water_len) + 10.0
			var nd := float(dist[u]) + c
			if not dist.has(v) or nd < float(dist[v]):
				dist[v] = nd
				prev[v] = u
				open.append(v)
	if not prev.has(goal):
		return
	var seq: Array[int] = [goal]
	var cur := goal
	while cur != hid:
		cur = int(prev[cur])
		seq.push_front(cur)
	for i in seq.size() - 1:
		var a := seq[i]
		var b := seq[i + 1]
		if nav.reachable(a, b, 0.0):
			continue
		var P2 := nav.pair(a, b)
		if P2.is_empty():
			return
		var rev := int(P2.a) != a
		var from: Vector3 = P2.sb if rev else P2.sa
		var to: Vector3 = P2.sa if rev else P2.sb
		var dir: Vector3 = -(P2.dir as Vector3) if rev else (P2.dir as Vector3)
		bridge = {"key": BotNav._key(a, b), "a": a, "b": b, "from": from, "to": to, "dir": dir,
			"root": null, "tip": null, "sections": 0, "done": false}
		return

## Поставить следующую секцию моста. null — пока нельзя/готово.
func _next_section() -> Blueprint:
	var bm := _bm()
	var dir: Vector3 = bridge.dir
	var tipv: Variant = bridge.tip
	if tipv != null and (not is_instance_valid(tipv) or (tipv as Blueprint).is_drifting()):
		# секцию сожгли — начинаем заново
		bridge.root = null
		bridge.tip = null
		bridge.sections = 0
		tipv = null
	var tip: Blueprint = tipv as Blueprint
	if tip != null and not tip.is_complete():
		return tip
	if tip == null:
		# BUILD подсказывает самый узкий пролив между островами
		if bm.has_method(&"find_bridge_target"):
			var ft: Dictionary = bm.call(&"find_bridge_target", nav.by_id.get(int(bridge.a), {}), nav.by_id.get(int(bridge.b), {}))
			if bool(ft.get("ok", false)):
				var bp0 := bm.place_blueprint(&"raft", ft.xform as Transform3D, team, {"type": &"shore"})
				if bp0:
					bridge.dir = ft.get("dir", dir)
					bridge.root = bp0
					bridge.tip = bp0
					bridge.sections = 1
					return bp0
		var from: Vector3 = bridge.from
		var yaw := atan2(-dir.x, -dir.z)
		var side := Vector3(dir.z, 0, -dir.x)
		for k in 160:
			var s := float(k) * 0.25
			for lat in [0.0, 1.5, -1.5, 3.0, -3.0]:
				var p: Vector3 = from + dir * s + side * float(lat)
				var r := bm.shore_raft(p, yaw)
				if r.ok:
					var bp := bm.place_blueprint(&"raft", r.xform, team, {"type": &"shore"})
					if bp == null:
						continue
					bridge.root = bp
					bridge.tip = bp
					bridge.sections = 1
					return bp
		_failed_spots[bridge.key] = true
		bridge = {}
		return null
	# суша впереди — мост готов
	var ahead := tip.base_now() * Vector3(0, 0, -2.4)
	if nav.h(ahead.x, ahead.z) > nav.wl() - 0.15 or int(bridge.sections) >= MAX_SECTIONS:
		bridge.done = true
		bridges_built += 1
		nav.refresh_links(module.get_tree())
		return null
	var near := tip.base_now() * Vector3(0, 0, -3.0)
	var sock := bm.raft_socket(near, 1.5)
	if sock.is_empty():
		return null
	var bp2 := bm.place_blueprint(&"raft", sock.xform, team, {"type": &"raft", "parent": sock.parent, "offset": sock.offset})
	if bp2 == null:
		# дальше чужая территория — мост до сюда
		bridge.done = true
		return null
	bridge.tip = bp2
	bridge.sections = int(bridge.sections) + 1
	return bp2

## Точка, откуда работать над постройкой (у моста — с предыдущей секции/берега).
func work_point(bp: Blueprint) -> Vector3:
	if bp.is_raft():
		return bp.base_now() * Vector3(0, 0, 2.6)
	return bp.global_position

# ------------------------------------------------------------------ оборона

## Чужой мост, который пристал к нашему острову: вернуть его первую секцию у нашего берега.
func enemy_bridge_to_home() -> Blueprint:
	var hid := home_id()
	for L in nav.links:
		if int(L.team) == team:
			continue
		var decks: Array = L.decks
		if decks.is_empty():
			continue
		if int(L.b) == hid:
			return decks[decks.size() - 1] as Blueprint
		if int(L.a) == hid:
			return decks[0] as Blueprint
	# недостроенные чужие цепочки, подошедшие близко к нам
	var hc: Vector2 = home.get("center", Vector2.ZERO)
	var hr := float(home.get("radius", 100.0))
	for k in nav.chains:
		var ch: Dictionary = nav.chains[k]
		if int(ch.team) == team or not is_instance_valid(ch.tip):
			continue
		var tp: Vector3 = (ch.tip as Blueprint).global_position
		if Vector2(tp.x, tp.z).distance_to(hc) < hr + 25.0:
			return ch.tip as Blueprint
	return null

# ------------------------------------------------------------------ резервы целей

func reserve(target: Object, bot: Object) -> bool:
	var k := target.get_instance_id()
	var cur: Variant = reserved.get(k)
	if cur != null and is_instance_valid(cur) and cur != bot and not (cur as Bot).is_dead():
		return false
	reserved[k] = bot
	return true

func release(target: Object) -> void:
	if target:
		reserved.erase(target.get_instance_id())
