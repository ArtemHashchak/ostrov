class_name MatchDirector
extends Node
## Ход матча в мире: на старте ставит флаги всех команд у точек старта
## (BuildModule.place_flag), забирает флаг из инвентаря игроков, шлёт
## предупреждения о времени и об атаке на флаг. Правила — в автозагрузке Game.

signal notice(text: String, color: Color)

const TIME_WARNINGS: Array[float] = [1800.0, 600.0, 300.0, 60.0]

var _warned: Dictionary = {}
var _attack_note_t: Dictionary = {} # team → match_time последнего сообщения

func _ready() -> void:
	add_to_group(&"match_director")
	Events.match_started.connect(_on_match_started)
	Events.flag_damaged.connect(_on_flag_damaged)
	Events.flag_destroyed.connect(_on_flag_destroyed)
	Events.team_eliminated.connect(_on_team_eliminated)
	Events.match_ended.connect(_on_match_ended)

static func instance() -> MatchDirector:
	var t := Engine.get_main_loop() as SceneTree
	return t.get_first_node_in_group(&"match_director") as MatchDirector if t else null

func _world() -> Node:
	return get_tree().get_first_node_in_group(&"world")

func _on_match_started(cfg: Dictionary) -> void:
	_warned.clear()
	_attack_note_t.clear()
	if bool(cfg.get("auto_flags", true)):
		place_all_flags()
	if bool(cfg.get("tutorial", false)):
		return
	var mins := float(cfg.get("minutes", 180))
	var mode := "Каждый за себя" if String(cfg.get("mode", "ffa")) == "ffa" else "2 × 2"
	notice.emit("%s · %s" % [mode, ("%d ч" % int(mins / 60.0)) if mins >= 60.0 else ("%d мин" % int(mins)) if mins > 0.0 else "до последнего флага"], UITheme.ACCENT)

## Поставить флаги всем командам, у кого его ещё нет.
func place_all_flags() -> void:
	var bm := BuildModule.instance()
	for t in Game.teams:
		if t.flag_placed:
			continue
		var pos := flag_spot(t.id)
		var yaw := 0.0
		var w := _world()
		if w and w.has_method(&"islands"):
			for I: Dictionary in w.call(&"islands"):
				if int(I.team) == t.id:
					var c: Vector2 = I.center
					yaw = atan2(pos.x - c.x, pos.z - c.y)
		if bm:
			bm.place_flag(t.id, pos, yaw)
		else:
			Game.set_flag_placed(t.id, pos)
	# Флаг уже стоит — предмет «флаг» у игроков не нужен.
	for t in Game.teams:
		for m in t.members:
			_take_flag_item(m)
	if not Events.character_spawned.is_connected(_take_flag_item):
		Events.character_spawned.connect(_take_flag_item, CONNECT_DEFERRED)

func _take_flag_item(ch: Node) -> void:
	if ch == null or not is_instance_valid(ch):
		return
	var inv: Variant = ch.get(&"inventory")
	if inv is Object and (inv as Object).has_method(&"count"):
		var n := int((inv as Object).call(&"count", &"flag"))
		if n > 0 and ch.get(&"team") != null and Game.teams.size() > int(ch.get(&"team")) \
				and Game.teams[int(ch.get(&"team"))].flag_placed:
			(inv as Object).call(&"remove", &"flag", n)

## Место для флага: ровная суша рядом с точкой старта, но не вплотную к ней.
func flag_spot(team: int) -> Vector3:
	var w := _world()
	if w == null:
		return Vector3(team * 30.0, 2.0, 0.0)
	var sp := w.call(&"spawn_point", team) as Vector3
	var wl := float(w.call(&"water_level")) if w.has_method(&"water_level") else 0.0
	var best := sp
	var best_s := -INF
	for ring: float in [5.0, 7.0, 9.0, 12.0]:
		for k in 12:
			var a := TAU * float(k) / 12.0
			var x := sp.x + cos(a) * ring
			var z := sp.z + sin(a) * ring
			if w.has_method(&"is_land") and not bool(w.call(&"is_land", x, z)):
				continue
			var h := float(w.call(&"height_at", x, z))
			var n := w.call(&"normal_at", x, z) as Vector3 if w.has_method(&"normal_at") else Vector3.UP
			var s := n.y * 4.0 - absf(ring - 7.0) * 0.1
			if h < wl + 1.2:
				s -= 5.0
			if s > best_s:
				best_s = s
				best = Vector3(x, h, z)
	return best

func _process(_delta: float) -> void:
	var __pt := PerfStats.begin()
	_perf_process(_delta)
	PerfStats.end(&"game", __pt)

func _perf_process(_delta: float) -> void:
	if not Game.is_playing() or not Game.has_time_limit():
		return
	var left := Game.time_left()
	for w in TIME_WARNINGS:
		if left <= w and left > w - 5.0 and not _warned.has(w) and Game.match_length > w + 1.0:
			_warned[w] = true
			var txt := ("Осталось %d мин" % int(w / 60.0)) if w >= 60.0 else "Осталась 1 минута"
			notice.emit(txt, UITheme.ACCENT)

func _player_team() -> int:
	var p := get_tree().get_first_node_in_group(&"player")
	return int(p.get(&"team")) if p and p.get(&"team") != null else 0

func _on_flag_damaged(team: int, hp: float, _mx: float) -> void:
	if team != _player_team() or hp <= 0.0:
		return
	var last := float(_attack_note_t.get(team, -100.0))
	if Game.match_time - last > 15.0:
		_attack_note_t[team] = Game.match_time
		notice.emit("Ваш флаг атакуют!", UITheme.DANGER)

func _on_flag_destroyed(team: int, _by: Node) -> void:
	if team == _player_team():
		notice.emit("Ваш флаг уничтожен — возрождения больше нет!", UITheme.DANGER)
	else:
		notice.emit("Флаг %s уничтожен" % Game.TEAM_NAMES_GEN[team % 4], Game.team_color(team))

func _on_team_eliminated(team: int) -> void:
	notice.emit("Команда %s выбыла" % Game.TEAM_NAMES_GEN[team % 4], Game.team_color(team).darkened(0.2))

func _on_match_ended(win: int) -> void:
	if win < 0:
		notice.emit("Ничья", UITheme.ACCENT)
	else:
		notice.emit("Победили %s" % Game.TEAM_NAMES[win % 4], Game.team_color(win))
