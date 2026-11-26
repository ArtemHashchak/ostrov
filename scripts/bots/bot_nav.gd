class_name BotNav
extends RefCounted
## Навигация ботов по архипелагу без NavMesh.
## Уровни:
##  1) граф островов: рёбра — готовые мосты (цепочки плотов от берега до берега)
##     и, если позволяет сложность, заплывы через узкие проливы;
##  2) внутри острова — прямое движение с обходом препятствий (Bot.steer).
## Мосты пересчитываются раз в несколько секунд (строят и жгут все команды).
## Путь — массив точек {p: Vector3, water: bool, deck: bool}.

const PAIR_MAX_GAP := 140.0
const BOAT_MAX_GAP := 820.0          # мир v5: лодкой между островами (250–700 м воды)
const SAMPLE := 1.0
const REFRESH := 3.0

var world: Node = null
var islands: Array[Dictionary] = []
var islets: Array[Dictionary] = []
var by_id: Dictionary = {}           # id -> island
## Пары соседних островов: key "a|b" (a<b) -> {a, b, water_len, sa: Vector3, sb: Vector3, dir: Vector3 (a→b)}
var pairs: Dictionary = {}
## Готовые мосты: [{a, b, team, points: Array[Vector3] (от a к b), decks: Array}]
var links: Array[Dictionary] = []
## Недостроенные цепочки: root(instance_id) -> {root, tip, team, a}
var chains: Dictionary = {}
## Морские переправы (мир v5, лодки BotBoat): key "a|b" -> {a, b, gap, sa, sb, la, lb, dir}
## sa/sb — последняя суша у берегов, la/lb — точки спуска на воду (глубже 0,8 м).
var sea_routes: Dictionary = {}
var boats_ok := false
var _t := 0.0

func setup(w: Node) -> void:
	world = w
	islands = []
	by_id.clear()
	for I: Dictionary in w.call(&"islands"):
		islands.append(I)
		by_id[int(I.id)] = I
	islets = []
	if w.has_method(&"islets"):
		for il: Dictionary in w.call(&"islets"):
			islets.append(il)
	_build_pairs()
	boats_ok = int(w.get(&"gen_version")) >= 5 if w.get(&"gen_version") != null else false
	if boats_ok:
		_build_sea_routes()

func wl() -> float:
	return float(world.call(&"water_level")) if world else 0.0

func h(x: float, z: float) -> float:
	return float(world.call(&"height_at", x, z))

func ground(p: Vector3) -> Vector3:
	return Vector3(p.x, h(p.x, p.z), p.z)

func land(x: float, z: float) -> bool:
	return bool(world.call(&"is_land", x, z)) and h(x, z) > wl() + 0.05

## id острова в точке (−1 — море/не остров).
func island_id(p: Vector3) -> int:
	var I: Dictionary = world.call(&"island_at", p.x, p.z)
	return int(I.id) if not I.is_empty() else -1

## Скальный островок посреди пролива рядом с p (в пределах его радиуса × k): индекс, иначе −1.
func islet_at(p: Vector3, k: float = 1.7) -> int:
	for i in islets.size():
		var c: Vector2 = islets[i].center
		if Vector2(p.x, p.z).distance_to(c) < float(islets[i].radius) * k:
			return i
	return -1

func home_island(team: int) -> Dictionary:
	for I in islands:
		if String(I.kind) == "home" and int(I.team) == team:
			return I
	return {}

static func _key(a: int, b: int) -> String:
	return "%d|%d" % [mini(a, b), maxi(a, b)]

func pair(a: int, b: int) -> Dictionary:
	return pairs.get(_key(a, b), {})

## Соседи: для каждой пары близких островов — длина глубокой воды по линии центров
## и точки берегов (где кончается суша a и начинается суша b).
func _build_pairs() -> void:
	pairs.clear()
	var lvl := wl()
	for i in islands.size():
		for j in range(i + 1, islands.size()):
			var A := islands[i]
			var B := islands[j]
			var ca: Vector2 = A.center
			var cb: Vector2 = B.center
			var dist := ca.distance_to(cb)
			if dist - float(A.radius) - float(B.radius) > PAIR_MAX_GAP:
				continue
			var dir := (cb - ca) / maxf(dist, 0.01)
			var steps := int(dist / SAMPLE)
			var last_a := -1.0
			var first_b := -1.0
			var water := 0.0
			for k in steps + 1:
				var t := float(k) * SAMPLE
				var p := ca + dir * t
				var hh := h(p.x, p.y)
				var is_l := hh > lvl + 0.05
				if is_l:
					if first_b < 0.0 and water > 0.0:
						# суша чужого острова или островок посреди пролива
						var I2: Dictionary = world.call(&"island_at", p.x, p.y)
						if not I2.is_empty() and int(I2.id) == int(B.id):
							first_b = t
							break
					if water <= 0.0:
						last_a = t
				elif hh < lvl - 1.1:
					water += SAMPLE
			if last_a < 0.0 or first_b < 0.0:
				continue
			var pa := ca + dir * last_a
			var pb := ca + dir * first_b
			pairs[_key(int(A.id), int(B.id))] = {
				"a": int(A.id), "b": int(B.id), "water_len": water, "gap": first_b - last_a,
				"sa": Vector3(pa.x, h(pa.x, pa.y), pa.y), "sb": Vector3(pb.x, h(pb.x, pb.y), pb.y),
				"dir": Vector3(dir.x, 0.0, dir.y)}

## Морские переправы мира v5: пары островов с водой ≤ BOAT_MAX_GAP по линии центров,
## без чужой суши на пути. Точки: суша у берега (sa/sb) и спуск на воду (la/lb).
func _build_sea_routes() -> void:
	sea_routes.clear()
	var lvl := wl()
	for i in islands.size():
		for j in range(i + 1, islands.size()):
			var A := islands[i]
			var B := islands[j]
			var ca: Vector2 = A.center
			var cb: Vector2 = B.center
			var dist := ca.distance_to(cb)
			if dist - float(A.radius) - float(B.radius) > BOAT_MAX_GAP:
				continue
			var dir := (cb - ca) / maxf(dist, 0.01)
			var last_a := -1.0
			var first_b := -1.0
			var launch_a := -1.0
			var launch_b := -1.0
			var blocked := false
			var in_water := false
			var t := 0.0
			while t <= dist:
				var q := ca + dir * t
				var hh := h(q.x, q.y)
				if hh > lvl + 0.05:
					var I2: Dictionary = world.call(&"island_at", q.x, q.y)
					var iid := int(I2.id) if not I2.is_empty() else -1
					if in_water:
						if iid == int(B.id):
							first_b = t
							break
						if iid != int(A.id):
							blocked = true
							break
					else:
						last_a = t
				else:
					if last_a >= 0.0:
						in_water = true
						if launch_a < 0.0 and hh < lvl - 0.8:
							launch_a = t
						if hh < lvl - 0.8:
							launch_b = t
				t += 2.0
			if blocked or last_a < 0.0 or first_b < 0.0 or launch_a < 0.0 or launch_b < 0.0:
				continue
			var gap := first_b - last_a
			if gap > BOAT_MAX_GAP or gap <= PAIR_MAX_GAP * 0.5:
				continue
			var pa := ca + dir * last_a
			var pb := ca + dir * first_b
			var la := ca + dir * launch_a
			var lb := ca + dir * launch_b
			sea_routes[_key(int(A.id), int(B.id))] = {"a": int(A.id), "b": int(B.id), "gap": gap,
				"sa": ground(Vector3(pa.x, 0, pa.y)), "sb": ground(Vector3(pb.x, 0, pb.y)),
				"la": Vector3(la.x, lvl, la.y), "lb": Vector3(lb.x, lvl, lb.y), "dir": Vector3(dir.x, 0, dir.y)}

# ------------------------------------------------------------------ мосты

func update(delta: float, tree: SceneTree) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = REFRESH
	refresh_links(tree)

static func _root_of(b: Blueprint) -> Blueprint:
	var cur := b
	for i in 200:
		var par: Variant = cur.anchor.get("parent")
		if String(cur.anchor.get("type", "")) != "raft" or not is_instance_valid(par):
			return cur
		cur = par as Blueprint
	return cur

func refresh_links(tree: SceneTree) -> void:
	links.clear()
	chains.clear()
	var lvl := wl()
	var roots: Dictionary = {}
	for n in tree.get_nodes_in_group(&"raft_deck"):
		var b := n as Blueprint
		if b == null or b.is_drifting() or b.preview or not b.is_inside_tree():
			continue
		var r := _root_of(b)
		if r.is_drifting():
			continue
		roots[r.get_instance_id()] = r
	for rid in roots:
		var root: Blueprint = roots[rid]
		var start := _land_along(root, 1.0)
		var ia := island_id(start) if start.x < INF else -1
		var head: Array[Vector3] = []
		if ia < 0 and start.x < INF:
			var back := root.base_now().basis.z
			back.y = 0.0
			var hw := _walk_to_other(start, back.normalized(), -2)
			ia = int(hw.get("id", -1))
			if ia >= 0:
				head = hw.points as Array[Vector3]
				head.reverse()
		# обход дерева секций: путь от корня до каждой
		var stack: Array = [[root, [root]]]
		var tip: Blueprint = root
		var tip_len := 1
		while not stack.is_empty():
			var it: Array = stack.pop_back()
			var b: Blueprint = it[0]
			var path: Array = it[1]
			if path.size() > tip_len:
				tip = b
				tip_len = path.size()
			var ahead := _land_along(b, -1.0)
			if ahead.x < INF and ia >= 0 and _all_complete(path):
				# по косе дальше вперёд — до суши другого острова
				var fwd := -(b.base_now().basis.z)
				fwd.y = 0.0
				fwd = fwd.normalized()
				var tail := _walk_to_other(ahead, fwd, ia)
				var ib := int(tail.get("id", -1))
				if ib >= 0 and ib != ia:
					var pts: Array[Vector3] = head.duplicate()
					pts.append(start)
					for d: Blueprint in path:
						pts.append(d.base_now() * Vector3(0, 0, 1.0))
						pts.append(d.base_now() * Vector3(0, 0, -1.0))
					pts.append(ahead)
					pts.append_array(tail.points as Array[Vector3])
					links.append({"a": ia, "b": ib, "team": root.team, "points": pts, "decks": path.duplicate(), "root": root})
			for cv in b.raft_children:
				if not is_instance_valid(cv):
					continue
				var c := cv as Blueprint
				if c and not c.is_drifting() and not path.has(c):
					var np := path.duplicate()
					np.append(c)
					stack.append([c, np])
		chains[rid] = {"root": root, "tip": tip, "team": root.team, "a": ia, "len": tip_len}

## От точки p по направлению dir по суше/мели, пока не окажемся на другом острове (≠ not_id).
## {id, points} или {id: -1}.
func _walk_to_other(p: Vector3, dir: Vector3, not_id: int) -> Dictionary:
	var pts: Array[Vector3] = []
	var lvl := wl()
	var id0 := island_id(p)
	if id0 >= 0 and id0 != not_id:
		return {"id": id0, "points": pts}
	for k in range(1, 61):
		var q := p + dir * float(k) * 2.0
		var hh := h(q.x, q.z)
		if hh < lvl - 1.0:
			return {"id": -1}
		if k % 4 == 0:
			pts.append(Vector3(q.x, maxf(hh, lvl - 0.6), q.z))
		var id := island_id(q)
		if id >= 0 and id != not_id and hh > lvl + 0.05:
			pts.append(Vector3(q.x, hh, q.z))
			return {"id": id, "points": pts}
	return {"id": -1}

## Суша за кормой (sgn=+1) или перед носом (sgn=−1) секции в пределах 7 м; иначе (INF,…).
func _land_along(b: Blueprint, sgn: float) -> Vector3:
	var xf := b.base_now()
	for d in [1.8, 2.4, 3.2, 4.2, 5.4, 7.0]:
		var p := xf * Vector3(0, 0, sgn * float(d))
		if h(p.x, p.z) > wl() + 0.02:
			var q := xf * Vector3(0, 0, sgn * (float(d) + 1.2))
			return ground(q if h(q.x, q.z) > wl() + 0.02 else p)
	return Vector3(INF, INF, INF)

## Отладка: что видит навигация.
func describe() -> String:
	var bits: PackedStringArray = []
	for L in links:
		bits.append("link %d→%d t%d (%d точек)" % [int(L.a), int(L.b), int(L.team), (L.points as Array).size()])
	for k in chains:
		var c: Dictionary = chains[k]
		var tp: Vector3 = (c.tip as Blueprint).global_position if is_instance_valid(c.tip) else Vector3.ZERO
		bits.append("chain a=%d len=%d t%d tip=%s" % [int(c.a), int(c.len), int(c.team), str(tp.snapped(Vector3.ONE))])
	return "; ".join(bits)

static func _all_complete(path: Array) -> bool:
	for d in path:
		if not is_instance_valid(d) or not (d as Blueprint).is_complete():
			return false
	return true

## Готовая цепочка секций от берега до tip (для строителя).
func chain_points(root: Blueprint, tip: Blueprint) -> Array[Vector3]:
	var path: Array[Blueprint] = []
	var cur := tip
	for i in 200:
		path.push_front(cur)
		if cur == root:
			break
		var par: Variant = cur.anchor.get("parent")
		if not is_instance_valid(par):
			break
		cur = par as Blueprint
	var pts: Array[Vector3] = [ground(root.base_now() * Vector3(0, 0, 2.4))]
	for d in path:
		if not d.is_complete():
			break
		pts.append(d.base_now() * Vector3(0, 0, 1.0))
		pts.append(d.base_now() * Vector3(0, 0, -1.0))
	return pts

# ------------------------------------------------------------------ маршрут

## Рёбра графа островов из узла a: [{to, cost, kind: 'link'|'swim', link?}]
func _edges(a: int, swim_max: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for L in links:
		if int(L.a) == a:
			out.append({"to": int(L.b), "cost": float((L.points as Array).size()) * 1.5, "kind": "link", "link": L, "rev": false})
		elif int(L.b) == a:
			out.append({"to": int(L.a), "cost": float((L.points as Array).size()) * 1.5, "kind": "link", "link": L, "rev": true})
	if boats_ok and BotBoat.storm_ok(world):
		for k in sea_routes:
			var R: Dictionary = sea_routes[k]
			if int(R.a) == a:
				out.append({"to": int(R.b), "cost": float(R.gap) * 1.2 + 60.0, "kind": "boat", "route": R, "rev": false})
			elif int(R.b) == a:
				out.append({"to": int(R.a), "cost": float(R.gap) * 1.2 + 60.0, "kind": "boat", "route": R, "rev": true})
	if swim_max > 0.0:
		for k in pairs:
			var P: Dictionary = pairs[k]
			if float(P.water_len) > swim_max:
				continue
			if int(P.a) == a:
				out.append({"to": int(P.b), "cost": float(P.gap) * 3.0 + 20.0, "kind": "swim", "pair": P, "rev": false})
			elif int(P.b) == a:
				out.append({"to": int(P.a), "cost": float(P.gap) * 3.0 + 20.0, "kind": "swim", "pair": P, "rev": true})
	return out

## Последовательность рёбер от острова a к b (Дейкстра); [] — недостижимо; null-путь a==b — [].
func island_route(a: int, b: int, swim_max: float) -> Array:
	if a == b:
		return []
	var dist: Dictionary = {a: 0.0}
	var prev: Dictionary = {}
	var open: Array[int] = [a]
	var done: Dictionary = {}
	while not open.is_empty():
		var best_i := 0
		for i in open.size():
			if float(dist[open[i]]) < float(dist[open[best_i]]):
				best_i = i
		var u: int = open[best_i]
		open.remove_at(best_i)
		if done.has(u):
			continue
		done[u] = true
		if u == b:
			break
		for e in _edges(u, swim_max):
			var v: int = e.to
			var nd := float(dist[u]) + float(e.cost)
			if not dist.has(v) or nd < float(dist[v]):
				dist[v] = nd
				prev[v] = [u, e]
				open.append(v)
	if not prev.has(b):
		return [null]
	var seq: Array = []
	var cur := b
	while cur != a:
		var pr: Array = prev[cur]
		seq.push_front(pr[1])
		cur = int(pr[0])
	return seq

func reachable(a: int, b: int, swim_max: float) -> bool:
	if a == b:
		return true
	var r := island_route(a, b, swim_max)
	return not (r.size() == 1 and r[0] == null)

## Путь из from в to: массив {p, water, deck}. Пустой массив — недостижимо.
func path(from: Vector3, to: Vector3, swim_max: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ia := island_id(from)
	var ib := island_id(to)
	var on_deck := deck_at(from)
	if ia < 0 and on_deck:
		# стоим на мосту — сначала сойти на ближайший конец цепочки
		var L := _link_with_deck(on_deck)
		if not L.is_empty():
			var pts: Array = L.points
			var ib_side := island_id(pts[pts.size() - 1])
			var go_fwd := ib_side == ib or (ib < 0 and from.distance_to(pts[pts.size() - 1]) < from.distance_to(pts[0]))
			var idx := _nearest_idx(pts, from)
			if go_fwd:
				for i in range(idx, pts.size()):
					out.append({"p": pts[i], "water": true, "deck": true})
				ia = int(L.b)
			else:
				for i in range(idx, -1, -1):
					out.append({"p": pts[i], "water": true, "deck": true})
				ia = int(L.a)
		else:
			var ch := _chain_with_deck(on_deck)
			if not ch.is_empty():
				var pts2 := chain_points(ch.root, on_deck)
				for i in range(pts2.size() - 1, -1, -1):
					out.append({"p": pts2[i], "water": true, "deck": true})
				ia = int(ch.a)
	if ia < 0:
		# в воде: к ближайшему берегу по направлению к цели
		ia = ib if ib >= 0 else ia
	if ib < 0:
		var tdeck := deck_at(to)
		if tdeck:
			var ch2 := _chain_with_deck(tdeck)
			if not ch2.is_empty():
				ib = int(ch2.a)
				_append_route(out, ia, ib, swim_max)
				for p in chain_points(ch2.root, tdeck):
					out.append({"p": p, "water": true, "deck": true})
				out.append({"p": to, "water": true, "deck": true})
				return out
	if ia >= 0 and ib >= 0 and ia != ib:
		if not _append_route(out, ia, ib, swim_max):
			return []
	out.append({"p": to, "water": ib < 0, "deck": false})
	return out

func _append_route(out: Array[Dictionary], ia: int, ib: int, swim_max: float) -> bool:
	if ia == ib or ia < 0 or ib < 0:
		return true
	var r := island_route(ia, ib, swim_max)
	if r.size() == 1 and r[0] == null:
		return false
	for e: Dictionary in r:
		if e.kind == "link":
			var pts: Array = (e.link as Dictionary).points
			var seq: Array = pts.duplicate()
			if e.rev:
				seq.reverse()
			for i in seq.size():
				out.append({"p": seq[i], "water": i > 0 and i < seq.size() - 1, "deck": i > 0 and i < seq.size() - 1})
		elif e.kind == "boat":
			var R: Dictionary = e.route
			var s0: Vector3 = R.sb if e.rev else R.sa
			var l0: Vector3 = R.lb if e.rev else R.la
			var l1: Vector3 = R.la if e.rev else R.lb
			var s1: Vector3 = R.sa if e.rev else R.sb
			out.append({"p": s0, "water": false, "deck": false})
			out.append({"p": s1, "water": true, "deck": false, "boat": true, "launch": l0, "land": l1})
		else:
			var P: Dictionary = e.pair
			var s: Vector3 = P.sb if e.rev else P.sa
			var t: Vector3 = P.sa if e.rev else P.sb
			out.append({"p": s, "water": false, "deck": false})
			out.append({"p": t, "water": true, "deck": false})
	return true

static func _nearest_idx(pts: Array, p: Vector3) -> int:
	var bi := 0
	var bd := INF
	for i in pts.size():
		var d := (pts[i] as Vector3).distance_to(p)
		if d < bd:
			bd = d
			bi = i
	return bi

func _link_with_deck(d: Blueprint) -> Dictionary:
	for L in links:
		if (L.decks as Array).has(d):
			return L
	return {}

func _chain_with_deck(d: Blueprint) -> Dictionary:
	var r := _root_of(d)
	return chains.get(r.get_instance_id(), {})

## Секция моста под точкой (в пределах её настила), иначе null.
func deck_at(p: Vector3) -> Blueprint:
	var tree := world.get_tree() if world else null
	if tree == null:
		return null
	for n in tree.get_nodes_in_group(&"raft_deck"):
		var b := n as Blueprint
		if b == null or b.is_drifting():
			continue
		var loc := b.base_now().affine_inverse() * p
		if absf(loc.x) < 1.3 and absf(loc.z) < 1.8 and absf(loc.y) < 2.0:
			return b
	return null
