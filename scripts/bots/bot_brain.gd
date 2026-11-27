class_name BotBrain
extends RefCounted
## «Мозг» бота: выбирает задачу (срочное → задание команды) и ведёт её по шагам.
## Срочное: уплыть от акул, бой, яд, жажда, голод, защита флага, чужой мост к нашему
## острову. Задания команды: брёвна (рубка → распил → перенос), палки/верёвки/камни,
## постройка базы и моста, набег на чужой флаг. think() — несколько раз в секунду.

const SWING_CD := 0.8
const PICK_R := 2.0
const SEG_REACH_H := 1.8     # выше над землёй сегмент ствола не достать топором
const CUT_STALL_S := 25.0    # столько без удара по стволу — бросить его
const TASK_TIMEOUT := {"logs": 150.0, "deliver": 90.0, "collect": 80.0, "fill": 60.0, "fight": 40.0,
	"flee": 25.0, "drink": 80.0, "eat": 80.0, "herb": 60.0, "raid": 420.0, "defend": 30.0,
	"cut_bridge": 90.0, "goto": 240.0, "wander": 20.0, "retreat": 40.0, "prep": 120.0, "supply": 150.0}
## Упрощённые рецепты ботов (боты не ходят по верстакам): то же оружие из базовых ресурсов.
const BOT_RECIPES := {
	&"spear": {&"stick": 2, &"rock": 1},
	&"molotov": {&"coconut": 2, &"fiber": 1},
	&"dynamite": {&"rock": 4, &"stick": 2, &"fiber": 2},
	&"arrow": {&"stick": 1, &"rock": 1},
}

var bot: Bot
var team: BotTeam
## &"auto" — обычный бот; &"raid" — только набеги (цель raid_team или ближайшая); &"build" — только стройка.
var mode: StringName = &"auto"
var raid_team: int = -1
var task: Dictionary = {}
var enemy: Node3D = null
var clock: float = 0.0
var status: String = ""
var stats: Dictionary = {"logs": 0, "delivered": 0, "felled": 0, "parts": 0, "hits": 0, "kills": 0, "raids": 0}
var _black: Dictionary = {}       # instance_id -> до какого clock не трогать
var _swing_cd: float = 0.0
var _throw_cd: float = 0.0
var _seen_t: float = 0.0
var _react: float = 0.0
var _scan_t: float = 0.0
var _flora: Flora = null

func _init(b: Bot, t: BotTeam) -> void:
	bot = b
	team = t

func on_died() -> void:
	_end_task()
	enemy = null

func on_respawned() -> void:
	_end_task()

func act(delta: float) -> void:
	clock += delta
	_swing_cd -= delta * Bots.speed
	_throw_cd -= delta
	if is_instance_valid(enemy) and task.get("type", "") == "fight":
		bot.aim_target = _chest(enemy)

# ============================================================ выбор задачи

func think(_dt: float) -> void:
	if not bot.alive or not bot.is_inside_tree():
		return
	if _flora == null or not is_instance_valid(_flora):
		_flora = Flora.instance()
	_scan()
	var want := _urgent()
	if not want.is_empty() and String(want.type) != String(task.get("type", "")):
		_set_task(want)
	if task.is_empty():
		_set_task(_job())
	if task.is_empty():
		_set_task({"type": "wander"})
	var tt := String(task.type)
	if clock - float(task.t0) > float(TASK_TIMEOUT.get(tt, 120.0)):
		_fail("таймаут")
		return
	if bot.stuck >= 5 and bot.has_path():
		_fail("застрял")
		return
	match tt:
		"logs": _do_logs()
		"deliver": _do_deliver()
		"collect": _do_collect()
		"fill": _do_fill()
		"fight": _do_fight()
		"flee": _do_flee()
		"drink": _do_drink()
		"eat": _do_eat()
		"herb": _do_herb()
		"raid": _do_raid()
		"defend": _do_defend()
		"cut_bridge": _do_cut_bridge()
		"goto": _do_goto()
		"wander": _do_wander()
		"retreat": _do_retreat()
		"prep": _do_prep()
		"supply": _do_supply()
		"evade": _do_goto()

## v5.2: бот низко у моря во время цунами (отступ воды / волна).
func _tsunami_danger() -> bool:
	var se := SeasonEvents.instance()
	var ev := se.get_active(&"tsunami") if se else null
	return ev != null and bool(ev.call(&"bot_should_evade", bot))

## Задание «уйти наверх»: ближайшая точка того же острова выше 7 м.
func _tsunami_evade() -> Dictionary:
	if not _tsunami_danger():
		return {}
	var p := bot.global_position
	var best := Vector3.INF
	for r: float in [15.0, 30.0, 50.0, 75.0, 110.0]:
		for k in 12:
			var a := TAU * k / 12.0
			var q := p + Vector3(cos(a), 0, sin(a)) * r
			var h := bot.nav.ground(q).y
			if h > 7.0 and _same_side(q):
				best = Vector3(q.x, h, q.z)
				break
		if best != Vector3.INF:
			break
	if best == Vector3.INF:
		return {}
	return {"type": "evade", "p": best, "arrive": 3.0}

func _set_task(t: Dictionary) -> void:
	_end_task()
	task = t
	if task.is_empty():
		return
	task.t0 = clock
	if not task.has("phase"):
		task.phase = ""
	status = String(task.type)
	bot.running = String(task.type) in ["fight", "flee", "raid", "defend", "retreat", "cut_bridge"]
	bot.aiming = false

func _end_task() -> void:
	if task.has("res"):
		var r: Variant = task.res
		if is_instance_valid(r):
			team.release(r as Object)
	task = {}
	bot.aiming = false
	if bot.is_inside_tree():
		bot.stop()

func _done() -> void:
	_end_task()

func _fail(why: String) -> void:
	for k in ["node", "target", "bp", "tree", "trunk"]:
		var n: Variant = task.get(k)
		if is_instance_valid(n) and n is Object:
			_black[(n as Object).get_instance_id()] = clock + 90.0
	status = "%s: %s" % [task.get("type", ""), why]
	_black["task_" + String(task.get("type", ""))] = clock + 20.0
	_end_task()

## Строка состояния для отладки/тестов.
func debug() -> String:
	var g: Variant = task.get("goal")
	var gd := -1.0
	if g is Vector3:
		gd = (g as Vector3).distance_to(bot.global_position)
	var en := "-"
	if is_instance_valid(enemy):
		en = String(enemy.get(&"species")) if enemy.get(&"species") != null else String(enemy.name)
	return "%s/%s goal=%.1f path=%d stuck=%d pos=%s enemy=%s held=%s" % [task.get("type", "-"), task.get("phase", ""), gd,
		bot.path.size(), bot.stuck, str(bot.global_position.snapped(Vector3.ONE * 0.1)), en, bot.held_id]

## Узел из задачи (null, если удалён).
func _tn(key: String) -> Object:
	var v: Variant = task.get(key)
	if v == null or not is_instance_valid(v):
		return null
	return v as Object

func _recent_fail(tt: String) -> bool:
	return float(_black.get("task_" + tt, -1.0)) > clock

func _banned(o: Object) -> bool:
	return o == null or float(_black.get(o.get_instance_id(), -1.0)) > clock

# ============================================================ восприятие

func _scan() -> void:
	_scan_t -= 1.0
	var aggro := bot.cfg("aggro")
	var best: Node3D = null
	var bd := aggro
	var eye := bot.get_eye_position()
	for n in bot.get_tree().get_nodes_in_group(&"characters"):
		var c := n as Node3D
		if c == null or c == bot or not Game.is_alive(c):
			continue
		var ct: Variant = c.get(&"team")
		if ct != null and int(ct) == bot.team:
			continue
		var d := c.global_position.distance_to(bot.global_position)
		if d >= bd:
			continue
		if d > 6.0 and not _can_see(eye, _chest(c), c):
			continue
		best = c
		bd = d
	# кто напал (в т.ч. зверь) — отвечаем. Кроме морских (акула укусила на мосту, медуза):
	# в погоне за ними бот сходил с настила в воду. От акул бот уходит (flee), а не дерётся.
	if best == null and is_instance_valid(bot.last_attacker) and Game.match_time - bot.last_attacked_t < 8.0:
		var la := bot.last_attacker as Node3D
		if la and (la.is_in_group(&"sharks") or la.is_in_group(&"sea_life")):
			la = null
		if la and Game.is_alive(la) and la.global_position.distance_to(bot.global_position) < aggro * 1.5:
			best = la
	if not is_instance_valid(enemy):
		enemy = null
	if best != enemy:
		if best and enemy == null:
			_react = bot.cfg("reaction")
		enemy = best
	if enemy:
		_seen_t = clock

func _can_see(from: Vector3, to: Vector3, who: Node) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [bot.get_rid()]
	var hit := bot.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return true
	var c := hit.collider as Node
	for i in 4:
		if c == null:
			return false
		if c == who:
			return true
		c = c.get_parent()
	return false

static func _chest(n: Node3D) -> Vector3:
	if n is Bot or n.is_in_group(&"player"):
		return n.global_position + Vector3.UP * 1.25
	var sp: Variant = n.get(&"species")
	if sp != null and StringName(sp) in [&"snake", &"scorpion", &"spider", &"crab", &"iguana", &"turtle"]:
		return n.global_position + Vector3.UP * 0.12
	return n.global_position + Vector3.UP * 0.5

func _threat() -> float:
	var s := bot.get_tree().get_first_node_in_group(&"sea")
	if s == null:
		for n in bot.get_tree().get_nodes_in_group(&"sharks"):
			s = (n as Node).get_parent()
			break
	if s and s.has_method(&"threat_at"):
		return float(s.call(&"threat_at", bot.global_position))
	return 0.0

# ============================================================ срочное

func _urgent() -> Dictionary:
	var tt := String(task.get("type", ""))
	if bot.swimming and tt != "flee" and (_threat() > 0.3 or bot.health < 40.0) and not (tt in ["goto", "raid"] and _threat() < 0.5):
		return {"type": "flee"}
	if is_instance_valid(enemy):
		if tt == "fight" or tt == "retreat":
			return {}
		if bot.health < 25.0 and _enemy_hp(enemy) > bot.health * 1.5:
			return {"type": "retreat"}
		return {"type": "fight", "target": enemy}
	# SUPPLY: аптечка из посылки — сразу, если плохо или отравлен
	if bot.inv_count(&"medkit") > 0 and (bot.health < 45.0 or (bot.poison > 0.0 and bot.poison_time > 4.0)):
		var svm := Survival.instance()
		if svm:
			svm.consume_item(bot, &"medkit")
	if tt in ["fight", "flee", "retreat"]:
		return {}
	# v5.2: цунами — уйти наверх; награда за лидера — охота
	if tt == "evade":
		return {}
	var ev := _tsunami_evade()
	if not ev.is_empty():
		return ev
	var bt := SeasonEvents.bounty_target()
	if bt and bt != bot and int(bt.get(&"team")) != bot.team and bot.global_position.distance_to(bt.global_position) < 140.0 \
			and bot.health > 50.0 and not is_instance_valid(enemy):
		enemy = bt
		return {"type": "fight", "target": bt}
	if bot.poison > 0.0 and bot.poison_time > 2.0 and tt != "herb":
		var sv := Survival.instance()
		if sv and not sv.herb_sources(bot.global_position, 90.0).is_empty():
			return {"type": "herb"}
	if bot.thirst < 28.0 and tt != "drink":
		return {"type": "drink"}
	if bot.hunger < 25.0 and tt != "eat":
		return {"type": "eat"}
	if team.flag_alive() and Game.is_flag_under_attack(bot.team) and tt != "defend":
		if bot.global_position.distance_to(team.flag_pos()) < 160.0:
			return {"type": "defend"}
	if tt != "cut_bridge" and tt != "raid":
		var eb := team.enemy_bridge_to_home()
		if eb and not _banned(eb) and _owns_weapon_for_bridge():
			return {"type": "cut_bridge", "target": eb}
	return {}

static func _enemy_hp(e: Node) -> float:
	var h: Variant = e.get(&"health")
	return float(h) if h != null else 50.0

func _owns_weapon_for_bridge() -> bool:
	return bot.inv_count(&"molotov") > 0 or bot.inv_count(&"axe_crude") > 0 or bot.inv_count(&"axe_modern") > 0

# ============================================================ задания команды

func _job() -> Dictionary:
	_craft_upgrades()
	# руки заняты брёвнами — отнести
	if bot.logs_carried > 0:
		var bpl := _site_needing(&"log")
		if bpl:
			return {"type": "deliver", "bp": bpl}
		bot.take_logs(bot.logs_carried)
	var sup := _supply_job()
	if not sup.is_empty():
		return sup
	var raid := _raid_job()
	if not raid.is_empty():
		return raid
	var bp := team.current_build()
	if bp:
		var needs := bp.needs_left()
		if needs.has(&"log") and not _recent_fail("logs"):
			return {"type": "logs"}
		for t: StringName in [&"stick", &"rope", &"stone"]:
			if needs.has(t):
				if bot.inv_count(t) > 0:
					return {"type": "fill", "bp": bp, "item": t}
				if t == &"rope" and _craft(&"rope"):
					return {"type": "fill", "bp": bp, "item": t}
				return {"type": "collect", "item": t}
		if needs.has(&"log"):
			return {"type": "logs"}
	# строить нечего — запас для оружия, потом набег
	if bot.difficulty != &"easy" and bot.inv_count(&"molotov") == 0 and Game.match_time > 300.0:
		return {"type": "prep"}
	return {}

# ============================================================ посылки спонсоров (SUPPLY)

## Ящик спонсоров рядом (≤190 м, достижим): не каждый бот бежит — примерно половина,
## ближние (≤60 м) — всегда.
func _supply_job() -> Dictionary:
	if _recent_fail("supply"):
		return {}
	for n in bot.get_tree().get_nodes_in_group(&"supply_crates"):
		var c := n as SupplyCrate
		if c == null or not c.is_available() or _banned(c):
			continue
		var d := c.global_position.distance_to(bot.global_position)
		# v5.2: дрейфующий ящик (событие) — гонятся дальше и по воде
		var drift := c.has_meta(&"drift")
		if d > (float(c.get_meta(&"chase_r", 380.0)) if drift else 190.0):
			continue
		if d > 60.0 and (c.number + bot.index + bot.team) % 2 == 1:
			continue
		if not drift and not _same_side(c.global_position):
			continue
		return {"type": "supply", "node": c}
	return {}

func _do_supply() -> void:
	var c := _tn("node") as SupplyCrate
	if c == null or not c.is_available():
		_grab_pickups(bot.global_position, 4.0)
		_done()
		return
	if c.opener != null and is_instance_valid(c.opener) and c.opener != bot:
		_fail("ящик уже открывают")
		return
	if _go(c.global_position, 1.5):
		bot.face_to(c.global_position)
		bot.hold(&"")
		c.bot_open(bot)
	elif task.get("unreachable", false):
		_fail("не дойти до ящика")

func _site_needing(t: StringName) -> Blueprint:
	var bp := team.current_build()
	if bp and bp.needs_left().has(t):
		return bp
	var bm := BuildModule.instance()
	if bm == null:
		return null
	for b in bm.blueprints(bot.team):
		if not b.is_complete() and b.needs_left().has(t) and b.global_position.distance_to(bot.global_position) < 80.0:
			return b
	return null

## Набег: когда база готова (или прошло время) и до врага можно дойти.
func _raid_job() -> Dictionary:
	if mode == &"build":
		return {}
	var late := Game.match_time > 1500.0
	var ready := team.base_done or late or not team.flag_alive() or mode == &"raid"
	if not ready:
		return {}
	var many := team.living_bots().size() > 1
	if many and bot.index == 0 and team.flag_alive() and not late and mode != &"raid":
		return {}   # первый бот остаётся строителем, пока команда больше одного
	var tt := raid_team if raid_team >= 0 and raid_team < Game.teams.size() and Game.teams[raid_team].flag_alive else team.choose_target()
	if tt < 0:
		return {}
	var goal := Game.teams[tt].flag_pos
	var my_i := bot.nav.island_id(bot.global_position)
	if my_i < 0:
		my_i = team.home_id()
	var gi := bot.nav.island_id(goal)
	if not bot.nav.reachable(my_i, gi, bot.cfg("swim")):
		return {}
	if _best_weapon(false) == &"" and bot.inv_count(&"axe_crude") == 0:
		return {}
	return {"type": "raid", "team": tt}

# ============================================================ движение

## Идти к точке. true — пришли.
func _go(p: Vector3, arrive: float = 1.2) -> bool:
	var me := bot.global_position
	var flat := Vector2(p.x - me.x, p.z - me.z).length()
	if flat <= arrive + 0.15 and absf(p.y - me.y) < 3.0:
		bot.stop()
		return true
	var goal: Variant = task.get("goal")
	if not bot.has_path() or goal == null or (goal as Vector3).distance_to(p) > 1.5:
		var pth := bot.nav.path(me, p, bot.cfg("swim"))
		if pth.is_empty():
			task.unreachable = true
			return false
		task.goal = p
		bot.set_path(pth, arrive)
	return false

func _same_side(p: Vector3) -> bool:
	var a := bot.nav.island_id(bot.global_position)
	var b := bot.nav.island_id(p)
	if a < 0 or b < 0 or a == b:
		return true
	return bot.nav.reachable(a, b, bot.cfg("swim"))

# ============================================================ брёвна

func _do_logs() -> void:
	var ph := String(task.phase)
	if bot.logs_carried >= Bot.MAX_LOGS:
		var bp := _site_needing(&"log")
		_set_task({"type": "deliver", "bp": bp} if bp else {})
		return
	if ph == "" or ph == "find":
		# 1) брёвна на земле
		var lg := _free_log(14.0)
		if lg:
			task.phase = "pick"
			task.node = lg
			return
		# 2) поваленный ствол
		var tr := _trunk_near(bot.global_position, 18.0)
		if tr:
			task.phase = "cut"
			task.trunk = tr
			return
		# 3) дерево
		var tree := _find_tree()
		if tree == null:
			if bot.logs_carried > 0:
				var bp2 := _site_needing(&"log")
				_set_task({"type": "deliver", "bp": bp2} if bp2 else {})
			else:
				_fail("нет деревьев")
			return
		task.phase = "chop"
		task.tree = tree
		task.res = tree
		return
	match ph:
		"pick":
			var l := _tn("node") as FloraLog
			if l == null or not is_instance_valid(l) or l.carrier != null:
				task.phase = "find"
				return
			if l.global_position.y < bot.water_level() - 0.6:
				_black[l.get_instance_id()] = clock + 600.0
				task.phase = "find"
				return
			if _go(l.global_position, 1.3):
				bot.face_to(l.global_position)
				l.queue_free()
				bot.add_log()
				stats.logs = int(stats.logs) + 1
				task.phase = "find"
				task.t0 = clock
		"chop":
			var t := _tn("tree") as ChoppableTree
			if t == null or not is_instance_valid(t):
				task.phase = "find"
				return
			if t.felled:
				stats.felled = int(stats.felled) + 1
				var tr2 := _trunk_near(t.global_position, 14.0)
				task.phase = "wait_fall"
				task.trunk = tr2
				task.wait = clock + 2.5
				return
			if _go(t.global_position, 1.15):
				_hold_axe()
				bot.face_to(t.global_position)
				if _swing_cd <= 0.0:
					_swing_cd = SWING_CD / bot.cfg("work")
					bot.swing_anim()
					var to_bot := (bot.global_position - t.global_position)
					to_bot.y = 0.0
					to_bot = to_bot.normalized()
					t.on_hit(bot, {"position": t.global_position + Vector3.UP * 1.0 + to_bot * 0.25,
						"normal": to_bot, "tool": &"axe", "damage": _axe_damage()})
		"wait_fall":
			if clock < float(task.wait):
				return
			var tr3 := _tn("trunk") as FallenTrunk
			if tr3 == null or not is_instance_valid(tr3):
				tr3 = _trunk_near(bot.global_position, 20.0)
			if tr3 == null:
				task.phase = "find"
				return
			task.trunk = tr3
			task.phase = "cut"
		"cut":
			var tr4 := _tn("trunk") as FallenTrunk
			if tr4 == null or not is_instance_valid(tr4) or tr4.logs_left() <= 0:
				task.phase = "find"
				return
			var lg2 := _free_log(6.0)
			if lg2:
				task.phase = "pick"
				task.node = lg2
				return
			var sp := _segment_point(tr4)
			if sp.y < bot.water_level() - 0.8 or sp.x == INF:
				# под водой или все сегменты вне досягаемости (ствол лёг наклонно на склон/камни)
				_black[tr4.get_instance_id()] = clock + 600.0
				task.phase = "find"
				return
			# нет прогресса (не дойти / не достать) — бросить ствол, а не «пилить» до таймаута задачи
			# ключ — ствол + счётчик ударов; меняется — таймер заново (и после отлучки за бревном)
			var cut_key := "%d:%d" % [tr4.get_instance_id(), int(stats.get("hits", 0))]
			if String(task.get("cut_hits", "")) != cut_key or clock - float(task.get("cut_seen", -1e9)) > 2.0:
				task.cut_hits = cut_key
				task.cut_t = clock
			task.cut_seen = clock
			if clock - float(task.get("cut_t", clock)) > CUT_STALL_S:
				_black[tr4.get_instance_id()] = clock + 600.0
				task.erase("cut_hits")
				task.phase = "find"
				return
			if _go(sp, 1.3):
				_hold_axe()
				bot.face_to(sp)
				if _swing_cd <= 0.0:
					_swing_cd = SWING_CD / bot.cfg("work")
					bot.swing_anim()
					tr4.on_hit(bot, {"position": sp, "normal": Vector3.UP, "tool": &"axe", "damage": _axe_damage()})
					stats.hits = int(stats.hits) + 1

func _axe_damage() -> float:
	if bot.inv_count(&"axe_modern") > 0:
		return 22.0
	if bot.inv_count(&"axe_crude") > 0:
		return 14.0
	return 6.0

func _hold_axe() -> void:
	if bot.inv_count(&"axe_modern") > 0:
		bot.hold(&"axe_modern")
	elif bot.inv_count(&"axe_crude") > 0:
		bot.hold(&"axe_crude")
	else:
		bot.hold(&"")

func _free_log(r: float) -> FloraLog:
	var best: FloraLog = null
	var bd := r
	for n in bot.get_tree().get_nodes_in_group(&"log"):
		var l := n as FloraLog
		if l == null or l.carrier != null or not l.visible or _banned(l):
			continue
		var d := l.global_position.distance_to(bot.global_position)
		if d < bd:
			bd = d
			best = l
	return best

func _trunk_near(p: Vector3, r: float) -> FallenTrunk:
	var best: FallenTrunk = null
	var bd := r
	for n in bot.get_tree().get_nodes_in_group(&"fallen_trunks"):
		var t := n as FallenTrunk
		if t == null or t.logs_left() <= 0 or _banned(t):
			continue
		var d := t.global_position.distance_to(p)
		if d < bd:
			bd = d
			best = t
	return best

## Точка удара по стволу: середина ближайшего к боту сегмента (не у кроны), до которой
## можно дотянуться с земли (ствол бывает лёг наклонно — верхушкой на склон/камни).
## Ни одного досягаемого — Vector3(INF, …).
func _segment_point(t: FallenTrunk) -> Vector3:
	var best := Vector3(INF, INF, INF)
	var bd := INF
	var crown := t.crown_global_position() if t.has_crown() else Vector3(INF, INF, INF)
	var w: Node = bot.get_tree().get_first_node_in_group(&"world")
	for s: Dictionary in t.segments:
		var mid := t.global_transform * FloraLib.trunk_point(t.variant, (float(s.h0) + float(s.h1)) * 0.5)
		if crown.x < INF and mid.distance_to(crown) < 2.2:
			continue
		if w and w.has_method(&"height_at") and mid.y - float(w.call(&"height_at", mid.x, mid.z)) > SEG_REACH_H:
			continue
		var d := mid.distance_to(bot.global_position)
		if d < bd:
			bd = d
			best = mid
	return best

func _find_tree() -> ChoppableTree:
	if _flora == null:
		return null
	var base := team.flag_pos()
	var around := bot.global_position if bot.global_position.distance_to(base) > 90.0 else base
	var wl := bot.water_level()
	for r in [45.0, 90.0, 160.0]:
		# записи без создания узлов; узел дерева «будим» только у выбранного
		var tries := 0
		for e in _flora.nodes_near(around, float(r), &"tree"):
			var pos: Vector3 = e.position
			if pos.y < wl + 0.3:
				continue
			var n0: Variant = e.get("node")
			if n0 != null and (_banned(n0 as Object) or not team.reserve(n0 as Object, bot)):
				continue
			if not _same_side(pos):
				continue
			tries += 1
			if tries > 6:
				break
			var t := _flora.materialize(e) as ChoppableTree
			if t == null or t.felled or _banned(t) or not team.reserve(t, bot):
				continue
			return t
	return null

func _do_deliver() -> void:
	var bp := _tn("bp") as Blueprint
	if bp == null or not is_instance_valid(bp) or bp.is_complete() or not bp.needs_left().has(&"log"):
		bp = _site_needing(&"log")
		if bp == null:
			_done()
			return
		task.bp = bp
	if _go(team.work_point(bp), 2.2 if not bp.is_raft() else 1.4):
		bot.face_to(bp.global_position)
		bot.swing_anim()
		var n := bp.add_material(&"log", bot.logs_carried, bot)
		bot.take_logs(n)
		stats.delivered = int(stats.delivered) + n
		stats.parts = int(stats.parts) + n
		_done()

# ============================================================ материалы

func _do_fill() -> void:
	var bp := _tn("bp") as Blueprint
	var it: StringName = task.item
	if bp == null or not is_instance_valid(bp) or bp.is_complete():
		_done()
		return
	if _go(team.work_point(bp), 2.2 if not bp.is_raft() else 1.4):
		bot.face_to(bp.global_position)
		var placed := 0
		while bp.next_needed(it) >= 0 and bot.inv_count(it) > 0 and placed < 8:
			bot.inv_remove(it, 1)
			bp.fill_part(bp.next_needed(it), bot)
			placed += 1
		if placed > 0:
			bot.swing_anim()
		stats.parts = int(stats.parts) + placed
		_done()

const ITEM_KINDS := {&"stick": &"stick", &"rope": &"liana", &"stone": &"stone", &"rock": &"stone",
	&"coconut": &"coconut", &"fiber": &"liana", &"liana": &"liana", &"herb": &"herb"}

func _do_collect() -> void:
	var item: StringName = task.item
	var have0 := int(task.get("have0", -1))
	if have0 < 0:
		task.have0 = bot.inv_count(item) + (bot.inv_count(&"liana") if item == &"rope" else 0)
		have0 = int(task.have0)
	var have := bot.inv_count(item) + (bot.inv_count(&"liana") if item == &"rope" else 0)
	if item == &"rope" and bot.inv_count(&"liana") >= 2:
		_craft(&"rope")
	if have > have0 or (item == &"rope" and bot.inv_count(&"rope") > 0):
		_done()
		return
	var node := _tn("node") as Node3D
	if node == null or not is_instance_valid(node):
		node = _find_source(ITEM_KINDS.get(item, item))
		if node == null:
			_fail("нет источника %s" % item)
			return
		task.node = node
		task.res = node
		team.reserve(node, bot)
	var at := node.global_position
	if _go(at, 1.4):
		bot.face_to(at)
		_use_source(node)

## Найти и «материализовать» источник предмета (палка, лиана, камень, пальма с кокосами).
func _find_source(kind: StringName) -> Node3D:
	if _flora == null:
		return null
	for r in [50.0, 110.0, 180.0]:
		var tries := 0
		for e in _flora.nodes_near(bot.global_position, float(r), kind):
			var pos: Vector3 = e.position
			if pos.y < bot.water_level() - 0.3 or not _same_side(pos):
				continue
			var n0: Variant = e.get("node")
			if n0 != null and _banned(n0 as Object):
				continue
			tries += 1
			if tries > 6:
				break
			var n := _flora.materialize(e) as Node3D
			if n == null or _banned(n):
				continue
			if not team.reserve(n, bot):
				continue
			team.release(n)
			return n
	return null

func _use_source(node: Node3D) -> void:
	if _swing_cd > 0.0:
		return
	_swing_cd = 0.6 / bot.cfg("work")
	bot.swing_anim()
	if node is FloraPickup or node is ItemPickup:
		node.call(&"interact", bot)
	elif node is ResourceNode:
		(node as ResourceNode).harvest(bot)
		_black[node.get_instance_id()] = clock + 9999.0
		task.node = null
	elif node is ResourceRock:
		_hold_axe()
		(node as ResourceRock).on_hit(bot, {"position": node.global_position + Vector3.UP * 0.5, "tool": &"rock" if bot.inv_count(&"rock") > 0 else &"axe"})
		if (node as ResourceRock).depleted:
			task.node = null
	elif node is ChoppableTree:
		var t := node as ChoppableTree
		if t.coconuts <= 0 or t.felled:
			_black[t.get_instance_id()] = clock + 9999.0
			task.node = null
		else:
			t.interact(bot)
		_grab_pickups(node.global_position, 5.0)
	elif node.has_method(&"interact"):
		node.call(&"interact", bot)
	else:
		task.node = null

## Подобрать упавшие рядом предметы (кокосы и т.п.).
func _grab_pickups(at: Vector3, r: float) -> void:
	var sp := PhysicsShapeQueryParameters3D.new()
	var sh := SphereShape3D.new()
	sh.radius = r
	sp.shape = sh
	sp.transform = Transform3D(Basis(), at)
	for hit in bot.get_world_3d().direct_space_state.intersect_shape(sp, 16):
		var c := hit.collider as Node
		if c is FloraPickup or c is ItemPickup:
			c.call(&"interact", bot)

# ============================================================ крафт

func _craft(id: StringName) -> bool:
	# настоящий рецепт (без станции)
	for rid in Items.recipes:
		var r = Items.recipes[rid]
		if r.output != id:
			continue
		var ok := true
		for k in r.needs:
			if bot.inv_count(StringName(k)) < int(r.needs[k]):
				ok = false
				break
		if ok:
			for k in r.needs:
				bot.inv_remove(StringName(k), int(r.needs[k]))
			bot.inventory.add(id, int(r.count))
			return true
	if BOT_RECIPES.has(id):
		var need: Dictionary = BOT_RECIPES[id]
		for k in need:
			if bot.inv_count(k) < int(need[k]):
				return false
		for k in need:
			bot.inv_remove(k, int(need[k]))
		bot.inventory.add(id, 1 if id != &"arrow" else 3)
		return true
	return false

func _craft_upgrades() -> void:
	if bot.inv_count(&"spear") == 0 and bot.inv_count(&"stick") >= 4 and bot.inv_count(&"rock") >= 2:
		_craft(&"spear")
	if bot.inv_count(&"bow") == 0 and bot.inv_count(&"stick") >= 5 and bot.inv_count(&"rope") >= 3:
		_craft(&"bow")
	if bot.inv_count(&"bow") > 0 and bot.inv_count(&"arrow") < 6 and bot.inv_count(&"stick") >= 3 and bot.inv_count(&"rock") >= 2:
		_craft(&"arrow")
	if bot.inv_count(&"molotov") < 2:
		_craft(&"molotov")
	if bot.difficulty != &"easy" and Game.match_time > 1200.0 and bot.inv_count(&"dynamite") < 1:
		_craft(&"dynamite")

## Подготовка к набегу: кокосы и волокно на «молотов».
func _do_prep() -> void:
	if bot.inv_count(&"molotov") > 0:
		_done()
		return
	var need := &"coconut" if bot.inv_count(&"coconut") < 2 else (&"fiber" if bot.inv_count(&"fiber") < 1 else &"")
	if need == &"":
		_craft(&"molotov")
		_done()
		return
	_set_task({"type": "collect", "item": need})

# ============================================================ вода и еда

func _do_drink() -> void:
	if bot.thirst > 90.0:
		_done()
		return
	if bot.inv_count(&"coconut") > 0 or bot.inv_count(&"water_bottle_fresh") > 0:
		var sv := Survival.instance()
		var id := &"water_bottle_fresh" if bot.inv_count(&"water_bottle_fresh") > 0 else &"coconut"
		if sv:
			sv.consume_item(bot, id)
		else:
			bot.inv_remove(id, 1)
			bot.thirst = minf(100.0, bot.thirst + 15.0)
		if bot.thirst > 60.0:
			_done()
		return
	var node := _tn("node") as Node3D
	if node == null or not is_instance_valid(node):
		var sv2 := Survival.instance()
		if sv2:
			for s in sv2.drink_sources(bot.global_position, 160.0):
				if _same_side(s.pos) and not _banned(s.node) and not SeasonEvents.bot_avoids_water(s.pos, bot):
					node = s.node
					break
		if node == null:
			_set_task({"type": "collect", "item": &"coconut"})
			return
		task.node = node
	if _go(node.global_position, 1.8):
		bot.face_to(node.global_position)
		if not bool(node.call(&"drink", bot)):
			_black[node.get_instance_id()] = clock + 120.0
			task.node = null

func _food_in_inventory() -> StringName:
	for i in Inventory.SIZE:
		var s := bot.inventory.get_slot(i)
		if s.is_empty():
			continue
		var d := Items.get_item(s.id)
		if d == null:
			continue
		if float(d.data.get("hunger", 0.0)) > 0.0 and not String(s.id).ends_with("_raw"):
			return s.id
	return &""

func _do_eat() -> void:
	if bot.hunger > 85.0:
		_done()
		return
	var f := _food_in_inventory()
	if f != &"":
		var sv := Survival.instance()
		if sv:
			sv.consume_item(bot, f)
		else:
			bot.inv_remove(f, 1)
			bot.hunger = minf(100.0, bot.hunger + 20.0)
		return
	var node := _tn("node") as Node3D
	if node == null or not is_instance_valid(node):
		var sv2 := Survival.instance()
		if sv2:
			for s in sv2.food_sources(bot.global_position, 160.0):
				if s.action in ["pick", "harvest", "break"] and _same_side(s.pos) and not _banned(s.node):
					node = s.node
					task.act = s.action
					break
		if node == null:
			_set_task({"type": "collect", "item": &"coconut"})
			return
		task.node = node
	if _go(node.global_position, 1.6):
		bot.face_to(node.global_position)
		bot.swing_anim()
		match String(task.get("act", "pick")):
			"pick":
				if node.has_method(&"pick"):
					node.call(&"pick", bot)
			"harvest":
				node.call(&"interact", bot)
			"break":
				_hold_axe()
				node.call(&"on_hit", bot, {"position": node.global_position, "tool": &"axe", "damage": 20.0})
		_black[node.get_instance_id()] = clock + 30.0
		task.node = null

func _do_herb() -> void:
	if bot.poison <= 0.0 or bot.poison_time <= 0.0:
		_done()
		return
	var node := _tn("node") as Node3D
	if node == null or not is_instance_valid(node):
		var sv := Survival.instance()
		if sv:
			for s in sv.herb_sources(bot.global_position, 90.0):
				if _same_side(s.pos):
					node = s.node
					break
		if node == null:
			_fail("нет трав")
			return
		task.node = node
	if _go(node.global_position, 1.4):
		node.call(&"pick", bot)
		var sv2 := Survival.instance()
		if bot.inv_count(&"herb") > 0:
			bot.inv_remove(&"herb", 1)
		if sv2:
			sv2.cure_poison(bot)
		else:
			bot.poison = 0.0
			bot.poison_time = 0.0
		_done()

# ============================================================ бой

const RANGED_ORDER: Array[StringName] = [&"rifle", &"shotgun", &"musket", &"crossbow", &"bow", &"pistol", &"spear", &"machete", &"axe_modern", &"club", &"axe_crude"]
const MELEE_ORDER: Array[StringName] = [&"machete", &"axe_modern", &"spear", &"club", &"axe_crude", &"shotgun", &"rifle", &"musket", &"crossbow", &"pistol", &"bow"]

## Лучшее оружие из инвентаря (как Combat.best_weapon).
func _best_weapon(prefer_ranged: bool) -> StringName:
	var order := RANGED_ORDER if prefer_ranged else MELEE_ORDER
	for id in order:
		if bot.inventory.count(id) <= 0:
			continue
		var w := Combat.weapon(id)
		if w.is_empty():
			continue
		if String(w.type) in ["gun", "crossbow", "bow"] and not Combat.is_loaded(bot, id) and not Combat.has_ammo(bot, id):
			continue
		return id
	return &""

func _weapon_for(dist: float) -> StringName:
	var w := _best_weapon(dist > 7.0)
	if w == &"":
		return &""
	return w

func _do_fight() -> void:
	var e := _tn("target") as Node3D
	if e == null or not is_instance_valid(e) or not Game.is_alive(e):
		if e and is_instance_valid(e) and not Game.is_alive(e) and (e is Bot or e.is_in_group(&"player")):
			stats.kills = int(stats.kills) + 1
		enemy = null
		_done()
		return
	if is_instance_valid(enemy) and enemy != e:
		task.target = enemy
		e = enemy
	if clock - _seen_t > 6.0 or e.global_position.distance_to(bot.global_position) > bot.cfg("aggro") * 1.8:
		enemy = null
		_done()
		return
	if bot.health < 20.0 and _enemy_hp(e) > bot.health * 2.0:
		_set_task({"type": "retreat"})
		return
	var d := e.global_position.distance_to(bot.global_position)
	var w := _weapon_for(d)
	var wd := Combat.weapon(w) if w != &"" else {}
	var ranged := w != &"" and String(wd.get("type", "")) in ["bow", "crossbow", "gun"]
	var thrown := w == &"spear" and d > 6.0 and d < 18.0 and bot.inv_count(&"spear") > 1
	bot.hold(w)
	bot.aiming = true
	bot.aim_target = _chest(e)
	if _react > 0.0:
		_react -= bot.cfg("think")
		return
	if ranged:
		var rng := float(wd.get("range", 40.0))
		if d > rng * 0.8:
			_go(e.global_position, rng * 0.6)
			return
		bot.stop()
		if String(wd.type) in ["gun", "crossbow"] and not Combat.is_loaded(bot, w):
			if not Combat.is_reloading(bot):
				Combat.start_reload(bot, w)
			return
		if Combat.is_ready(bot, w):
			var eye := bot.get_eye_position()
			var tgt := _chest(e)
			if e is CharacterBody3D:
				tgt += (e as CharacterBody3D).velocity * clampf(d / float(wd.get("speed", 60.0)), 0.0, 1.0)
			var dir := _spread(Combat.aim_dir(eye, tgt, w), bot.cfg("spread"))
			bot.swing_anim()
			Combat.fire(bot, w, eye + dir * 0.4, dir, {"power": 1.0})
		return
	if thrown and _throw_cd <= 0.0:
		_throw_cd = 2.5
		var eye2 := bot.get_eye_position()
		var dir2 := _spread(Combat.aim_dir(eye2, _chest(e), &"spear"), bot.cfg("spread"))
		bot.swing_anim()
		Combat.throw_item(bot, &"spear", eye2 + dir2 * 0.4, dir2, 1.0)
		return
	# ближний бой
	var reach := float(wd.get("reach", 2.0)) if not wd.is_empty() else 1.8
	if d > reach * 0.85:
		_go(e.global_position, reach * 0.7)
		return
	bot.stop()
	bot.face_to(e.global_position)
	if Combat.is_ready(bot, w if w != &"" else &"club"):
		var eye3 := bot.get_eye_position()
		var dir3 := _spread((_chest(e) - eye3).normalized(), bot.cfg("spread") * 2.0)
		bot.swing_anim()
		var res := Combat.melee(bot, w, dir3)
		var landed := _hit_is(res, e)
		if not landed and d < reach + 0.4 and not res.is_empty():
			# невысокий зверь/узкая цель: луч прошёл мимо — засчитываем удар вплотную
			var wdmg := (float(wd.get("damage", 6.0)) if not wd.is_empty() else 6.0) * bot.cfg("dmg")
			if randf() > bot.cfg("spread") / 20.0:
				if e.has_method(&"on_hit"):
					e.call(&"on_hit", bot, {"position": _chest(e), "normal": -dir3, "tool": PlayerItems.tool_of(w) if w != &"" else &"hand", "damage": wdmg, "item": w})
				elif e.has_method(&"apply_damage"):
					e.call(&"apply_damage", wdmg, bot, &"melee")
				landed = true
		if landed:
			stats.hits = int(stats.hits) + 1

static func _hit_is(res: Dictionary, target: Node) -> bool:
	var c: Node = res.get("collider") as Node if is_instance_valid(res.get("collider")) else null
	for i in 6:
		if c == null:
			return false
		if c == target:
			return true
		c = c.get_parent()
	return false

static func _spread(dir: Vector3, deg: float) -> Vector3:
	var a := deg_to_rad(deg) * randf()
	var side := dir.cross(Vector3.UP)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized().rotated(dir, randf() * TAU)
	return dir.rotated(side, a).normalized()

func _do_retreat() -> void:
	var fp := team.flag_pos()
	if _go(fp, 3.0) or bot.health > 60.0:
		_done()

func _do_flee() -> void:
	if not bot.swimming:
		_done()
		return
	var tgt: Variant = task.get("land")
	if tgt == null:
		tgt = _nearest_land()
		task.land = tgt
	if tgt == null:
		return
	if not bot.has_path():
		var pth: Array[Dictionary] = [{"p": tgt as Vector3, "water": true, "deck": false}]
		bot.set_path(pth, 1.0)

func _nearest_land() -> Variant:
	var p := bot.global_position
	for r in [6.0, 12.0, 20.0, 32.0, 50.0, 75.0]:
		for k in 16:
			var a := TAU * k / 16.0
			var q := p + Vector3(cos(a), 0, sin(a)) * float(r)
			if bot.nav.land(q.x, q.z):
				return bot.nav.ground(q)
			var dk := bot.nav.deck_at(Vector3(q.x, bot.nav.wl(), q.z))
			if dk:
				return dk.global_position
	return null

# ============================================================ набег и оборона

func _do_raid() -> void:
	var tt := int(task.team)
	if tt >= Game.teams.size() or not Game.teams[tt].flag_alive:
		stats.raids = int(stats.raids) + 1
		_done()
		return
	var fp := Game.teams[tt].flag_pos
	var flag: Node3D = null
	var bm := BuildModule.instance()
	if bm:
		flag = bm.flag_of(tt)
	var d := bot.global_position.distance_to(fp)
	# взрывчатка и огонь — издалека
	if d < 16.0 and _throw_cd <= 0.0:
		var bomb := &"dynamite" if bot.inv_count(&"dynamite") > 0 else (&"molotov" if bot.inv_count(&"molotov") > 0 and _walls_near(fp, tt) else &"")
		if bomb != &"" and d > 5.0:
			_throw_cd = 4.0
			var eye := bot.get_eye_position()
			bot.stop()
			bot.face_to(fp)
			var dir := _spread(Combat.aim_dir(eye, fp + Vector3.UP * 0.6, bomb), bot.cfg("spread"))
			bot.hold(bomb)
			bot.swing_anim()
			Combat.throw_item(bot, bomb, eye + dir * 0.4, dir, 1.0)
			return
	# стена мешает — ломаем
	var wall := _tn("wall") as Blueprint
	if wall and is_instance_valid(wall) and not wall.is_queued_for_deletion() and wall.filled_count() > 0:
		if _go(wall.global_position, 1.9):
			_melee_struct(wall, wall.global_position + Vector3.UP * 1.0)
		return
	task.wall = null
	if d > 2.0:
		if _go(fp, 1.6):
			return
		if task.get("unreachable", false) or bot.stuck >= 2 or (d < 8.0 and bot.stuck >= 1):
			var w2 := _wall_between(fp, tt)
			if w2:
				task.wall = w2
				bot.stuck = 0
		return
	_melee_struct(flag, fp + Vector3.UP * 1.2)

func _walls_near(p: Vector3, t: int) -> bool:
	var bm := BuildModule.instance()
	if bm == null:
		return false
	for b in bm.blueprints(t):
		if not b.is_raft() and b.filled_count() > 0 and b.global_position.distance_to(p) < 4.5:
			return true
	return false

func _wall_between(fp: Vector3, t: int) -> Blueprint:
	var bm := BuildModule.instance()
	if bm == null:
		return null
	var best: Blueprint = null
	var bd := INF
	for b in bm.blueprints(t):
		if b.is_raft() or b.filled_count() <= 0 or b.global_position.distance_to(fp) > 6.0:
			continue
		var d := b.global_position.distance_to(bot.global_position)
		if d < bd:
			bd = d
			best = b
	return best

## Удар по постройке/флагу: через Combat.melee, при промахе вплотную — прямой on_hit.
func _melee_struct(target: Node3D, at: Vector3) -> void:
	if target == null or not is_instance_valid(target):
		return
	var w := _best_weapon(false)
	if w in [&"bow", &"crossbow", &"musket", &"pistol"]:
		w = &"axe_crude" if bot.inv_count(&"axe_crude") > 0 else &""
	bot.hold(w)
	bot.face_to(at)
	if not Combat.is_ready(bot, w if w != &"" else &"club") or _swing_cd > 0.0:
		return
	_swing_cd = 0.7
	bot.swing_anim()
	var eye := bot.get_eye_position()
	var res := Combat.melee(bot, w, (at - eye).normalized())
	var hit_node: Node = res.get("collider") as Node
	var hit_target := false
	var c := hit_node
	for i in 6:
		if c == null:
			break
		if c == target:
			hit_target = true
			break
		c = c.get_parent()
	if not hit_target and bot.global_position.distance_to(target.global_position) < 3.2:
		var dmg := float(Combat.weapon(w).get("damage", 6.0)) if w != &"" else 6.0
		target.call(&"on_hit", bot, {"position": at, "normal": Vector3.UP, "tool": PlayerItems.tool_of(w) if w != &"" else &"hand", "damage": dmg * bot.cfg("dmg"), "item": w})
	stats.hits = int(stats.hits) + 1

func _do_defend() -> void:
	var fp := team.flag_pos()
	if not team.flag_alive():
		_done()
		return
	if _go(fp, 4.0):
		if not Game.is_flag_under_attack(bot.team):
			_done()

func _do_cut_bridge() -> void:
	var deck := _tn("target") as Blueprint
	if deck == null or not is_instance_valid(deck) or deck.is_queued_for_deletion() or deck.is_drifting() or deck.burning:
		_done()
		return
	var p := deck.global_position
	var d := bot.global_position.distance_to(p)
	if bot.inv_count(&"molotov") > 0:
		if d < 15.0 and _throw_cd <= 0.0:
			_throw_cd = 3.0
			bot.stop()
			var eye := bot.get_eye_position()
			var dir := _spread(Combat.aim_dir(eye, p + Vector3.UP * 0.2, &"molotov"), bot.cfg("spread"))
			bot.hold(&"molotov")
			bot.swing_anim()
			Combat.throw_item(bot, &"molotov", eye + dir * 0.4, dir, 1.0)
			_black[deck.get_instance_id()] = clock + 25.0
			_done()
			return
		_go(team.work_point(deck), 8.0)
		return
	# рубим топором — встаём на берег у секции
	if _go(team.work_point(deck), 1.6):
		_melee_struct(deck, p)

# ============================================================ прочее

func _do_goto() -> void:
	if _go(task.p as Vector3, float(task.get("arrive", 1.5))):
		_done()
	elif task.get("unreachable", false):
		_fail("недостижимо")

func _do_wander() -> void:
	if not task.has("p"):
		var base := team.flag_pos()
		var a := randf() * TAU
		var p := base + Vector3(cos(a), 0, sin(a)) * randf_range(4.0, 14.0)
		task.p = bot.nav.ground(p)
	if _go(task.p as Vector3, 1.5):
		_done()

## Отладка/тесты: послать бота в точку.
func order_goto(p: Vector3, arrive: float = 1.5) -> void:
	_set_task({"type": "goto", "p": p, "arrive": arrive})
