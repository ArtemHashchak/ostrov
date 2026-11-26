extends Node
## Шина событий шоу (A1) — автозагрузка ShowBus. Любое значимое действие — событие с тегами:
##   ShowBus.emit_event(actor, &"kill", [&"knife", &"night", &"in_water"], {target = …})
## Одно событие сразу: начисляет очки по таблице assets/data/show_points.json
## (base[kind] × произведение tags[тег] × ранг популярности актёра), рассылает сигнал
## show_event (подписчики: ведущий, режиссёр сценок, рейтинг — подключаются постепенно).
## Сериализуемо (только данные) — задел под онлайн (A0b).
## Само подписывается на Events.character_died: убийства людей и животных с тегами
## оружия/ночи/воды.

signal show_event(ev: Dictionary)

## Очки по актёрам: instance_id → float; по командам: team → float.
var points: Dictionary = {}
var team_points: Dictionary = {}
## Ранг популярности (только множитель очков): instance_id → float (1 — обычный).
var popularity: Dictionary = {}
var events_log: Array[Dictionary] = []
var _first_blood := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Events.has_signal(&"character_died"):
		Events.character_died.connect(_on_died)
	if Events.has_signal(&"match_started"):
		Events.match_started.connect(func(_c: Dictionary) -> void: reset())

func reset() -> void:
	points.clear()
	team_points.clear()
	events_log.clear()
	_first_blood = false

## Очки за событие (без начисления).
func score_for(kind: StringName, tags: Array) -> float:
	var t := DataTables.table("show_points")
	var base := float((t.get("base", {}) as Dictionary).get(String(kind), 0.0))
	var mul := 1.0
	var tm: Dictionary = t.get("tags", {})
	for tg in tags:
		mul *= float(tm.get(String(tg), 1.0))
	return base * mul

func emit_event(actor: Node, kind: StringName, tags: Array = [], data: Dictionary = {}) -> float:
	var pts := score_for(kind, tags)
	var aid := actor.get_instance_id() if actor else 0
	pts *= float(popularity.get(aid, 1.0))
	var ev := {"kind": String(kind), "tags": tags.map(func(x: Variant) -> String: return String(x)),
		"actor": aid, "team": int(actor.get(&"team")) if actor and &"team" in actor else -1,
		"points": pts, "t": Time.get_ticks_msec() * 0.001}
	for k in data.keys():
		var v: Variant = data[k]
		ev[k] = v.get_instance_id() if v is Object else v
	if aid != 0:
		points[aid] = float(points.get(aid, 0.0)) + pts
	if int(ev.team) >= 0:
		team_points[ev.team] = float(team_points.get(ev.team, 0.0)) + pts
	events_log.append(ev)
	if events_log.size() > 200:
		events_log.pop_front()
	show_event.emit(ev)
	return pts

func points_of(actor: Node) -> float:
	return float(points.get(actor.get_instance_id(), 0.0)) if actor else 0.0

## Теги убийства: оружие (по last_damage_kind/текущему предмету), ночь, вода.
func _on_died(ch: Node, killer: Node) -> void:
	if killer == null or killer == ch or not is_instance_valid(killer):
		return
	var tags: Array = []
	var wid: StringName = killer.call(&"held_item") if killer.has_method(&"held_item") else &""
	if wid != &"":
		var w := Combat.weapon(wid) if Combat.is_weapon(wid) else {}
		match StringName(w.get("type", &"")):
			&"melee":
				tags.append(&"knife" if String(wid).contains("knife") or wid == &"machete" else &"melee")
			&"bow", &"crossbow":
				tags.append(&"bow")
			&"gun":
				tags.append(&"gun")
			&"throw":
				tags.append(&"spear" if wid == &"spear" else &"explosion")
	var w2 := BuildEnv.world()
	if w2 and w2.has_method(&"is_night") and bool(w2.call(&"is_night")):
		tags.append(&"night")
	if ch is Node3D and (ch as Node3D).global_position.y < BuildEnv.water_level() - 0.3:
		tags.append(&"in_water")
	var kind := &"kill"
	if ch.is_in_group(&"sharks"):
		kind = &"kill_shark"
	elif ch.is_in_group(&"animals"):
		kind = &"kill_animal"
	if kind == &"kill" and not _first_blood:
		_first_blood = true
		emit_event(killer, &"first_blood", tags)
	emit_event(killer, kind, tags, {"target": ch})
