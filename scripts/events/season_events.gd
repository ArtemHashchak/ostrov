class_name SeasonEvents
extends Node3D
## События сезона (v5.2, агент M). Директор: расписание по часам шоу (Game.match_time),
## запуск/шаг/конец событий, объявления ведущего (ShowHost) + баннер (MatchDirector.notice) +
## строка в правом верхнем углу (активные события и задание зрителей).
## События: migration · red_crabs · tsunami · bounty · poison_spring · drift_crate · viewer_task · calm.
## Параметры и реплики — assets/data/events.json. Консоль: event <id>|list|stop.
##
## API: SeasonEvents.instance() / ensure() — найти/создать (на полигоне создаётся консолью),
##   start(id, opts={}) -> SeasonEvent, stop_all(), active_ids(),
##   static is_poisoned(pos), bot_avoids_water(pos, bot), tsunami_info(), bounty_target(),
##   static heat() (зной штиля, BodyState), say(text, prio).

const IDS: Array[StringName] = [&"migration", &"red_crabs", &"tsunami", &"bounty", &"poison_spring",
	&"drift_crate", &"viewer_task", &"calm"]
const NAMES := {
	&"migration": "Миграция мант", &"red_crabs": "Нашествие красных крабов", &"tsunami": "Цунами",
	&"bounty": "Награда за лидера", &"poison_spring": "Отравленный родник", &"drift_crate": "Дрейфующий ящик",
	&"viewer_task": "Задание зрителей", &"calm": "Штиль",
}
const SCRIPTS := {
	&"migration": "res://scripts/events/ev_migration.gd",
	&"red_crabs": "res://scripts/events/ev_red_crabs.gd",
	&"tsunami": "res://scripts/events/ev_tsunami.gd",
	&"bounty": "res://scripts/events/ev_bounty.gd",
	&"poison_spring": "res://scripts/events/ev_poison_spring.gd",
	&"drift_crate": "res://scripts/events/ev_drift_crate.gd",
	&"viewer_task": "res://scripts/events/ev_viewer_task.gd",
	&"calm": "res://scripts/events/ev_calm.gd",
}

## Игровые факты событий для заданий зрителей: kind = crab_caught | fish_speared | …
signal game_fact(kind: StringName, by: Node, data: Dictionary)

## Ускорение времени событий (тесты): шаг события получает dt × time_scale.
static var time_scale := 1.0
## Автоматическое расписание (в матче). На полигоне — только консоль.
var auto := true
var active: Array[SeasonEvent] = []
var history: Array[StringName] = []
var next_t := -1.0
var _rng := RandomNumberGenerator.new()
var _hud: CanvasLayer
var _hud_label: Label
var _hud_t := 0.0

static func instance() -> SeasonEvents:
	var t := Engine.get_main_loop() as SceneTree
	return t.get_first_node_in_group(&"season_events") as SeasonEvents if t else null

## Найти или создать (рядом с миром). Без мира — null.
static func ensure() -> SeasonEvents:
	var se := instance()
	if se:
		return se
	var t := Engine.get_main_loop() as SceneTree
	if t == null:
		return null
	var w := t.get_first_node_in_group(&"world")
	var host: Node = w.get_parent() if w and w.get_parent() else t.current_scene
	if host == null:
		return null
	se = SeasonEvents.new()
	se.auto = false
	host.add_child(se)
	return se

func _ready() -> void:
	name = "SeasonEvents"
	add_to_group(&"season_events")
	add_to_group(&"map_markers")
	_rng.randomize()
	SeasonItems.register()
	_build_hud()
	if Events.has_signal(&"match_started"):
		Events.match_started.connect(func(_c: Dictionary) -> void: _reset())

func _exit_tree() -> void:
	var w := get_tree().get_first_node_in_group(&"world") if is_inside_tree() else null
	if w:
		w.set_meta(&"event_heat", 0.0)
		if &"event_sea_offset" in w:
			w.set(&"event_sea_offset", 0.0)

func _reset() -> void:
	stop_all()
	history.clear()
	next_t = -1.0

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 4
	add_child(_hud)
	_hud_label = Label.new()
	_hud_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_hud_label.offset_left = -420
	_hud_label.offset_right = -16
	_hud_label.offset_top = 96
	_hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hud_label.add_theme_font_size_override(&"font_size", 15)
	_hud_label.add_theme_color_override(&"font_color", Color(1.0, 0.86, 0.55))
	_hud_label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.85))
	_hud_label.add_theme_constant_override(&"outline_size", 4)
	_hud.add_child(_hud_label)

# ------------------------------------------------------------ расписание

func _process(delta: float) -> void:
	var dt := delta * time_scale
	for e in active.duplicate():
		if not is_instance_valid(e):
			active.erase(e)
			continue
		e.t += dt
		e.step(dt)
		if e.done or e.t >= e.duration:
			_end(e)
	if auto and Game.is_playing():
		_schedule_tick()
	_hud_t -= delta
	if _hud_t <= 0.0:
		_hud_t = 0.5
		_update_hud()

func _schedule_tick() -> void:
	var sch: Dictionary = DataTables.table("events").get("schedule", {})
	if next_t < 0.0:
		next_t = Game.match_time + _rng.randf_range(float(sch.get("first_min_s", 360)), float(sch.get("first_max_s", 540)))
		return
	if Game.match_time < next_t:
		return
	next_t = Game.match_time + _rng.randf_range(float(sch.get("gap_min_s", 480)), float(sch.get("gap_max_s", 900)))
	if active.size() >= int(sch.get("max_active", 2)):
		return
	var w: Dictionary = sch.get("weights", {})
	var once: Array = sch.get("once_per_match", [])
	var pool: Array[StringName] = []
	var weights: Array[float] = []
	for id in IDS:
		if is_active(id):
			continue
		if String(id) in once and history.has(id):
			continue
		pool.append(id)
		weights.append(float(w.get(String(id), 1.0)))
	if pool.is_empty():
		return
	var tot := 0.0
	for x in weights:
		tot += x
	var r := _rng.randf() * tot
	for i in pool.size():
		r -= weights[i]
		if r <= 0.0:
			start(pool[i])
			return

func is_active(id: StringName) -> bool:
	for e in active:
		if is_instance_valid(e) and e.id == id:
			return true
	return false

func get_active(id: StringName) -> SeasonEvent:
	for e in active:
		if is_instance_valid(e) and e.id == id:
			return e
	return null

func active_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for e in active:
		if is_instance_valid(e):
			out.append(e.id)
	return out

## Запустить событие (повторный запуск того же id — перезапуск).
func start(id: StringName, opts: Dictionary = {}) -> SeasonEvent:
	if not SCRIPTS.has(id):
		return null
	var old := get_active(id)
	if old:
		_end(old)
	var sc := load(String(SCRIPTS[id])) as GDScript
	if sc == null:
		return null
	var e := sc.new() as SeasonEvent
	e.setup(id, self, opts)
	add_child(e)
	active.append(e)
	history.append(id)
	print("[events] старт «%s» t=%d" % [NAMES.get(id, id), int(Game.match_time)])
	e.begin()
	if not e.done:
		banner("Событие: " + String(NAMES.get(id, id)))
	if e.done:
		_end(e)
		return null
	return e

func stop(id: StringName) -> bool:
	var e := get_active(id)
	if e:
		_end(e)
		return true
	return false

func stop_all() -> void:
	for e in active.duplicate():
		_end(e)

func _end(e: SeasonEvent) -> void:
	active.erase(e)
	if is_instance_valid(e):
		if not e.done:
			e.finish()
		e.done = true
		print("[events] конец «%s»" % NAMES.get(e.id, e.id))
		e.queue_free()

# ------------------------------------------------------------ объявления

func say(text: String, prio: bool = false) -> void:
	if text == "":
		return
	var h := ShowHost.instance()
	if h:
		h.say(text, prio)
	else:
		Events.toast.emit(text)

## Крупный баннер по центру сверху (заголовок события).
func banner(title: String) -> void:
	var md := MatchDirector.instance()
	if md:
		md.notice.emit(title, Color(1.0, 0.82, 0.45))
	else:
		Events.toast.emit(title)

func _update_hud() -> void:
	var lines: PackedStringArray = []
	for e in active:
		if is_instance_valid(e):
			var s := e.hud_line()
			if s != "":
				lines.append(s)
	_hud_label.text = "\n".join(lines)
	_hud_label.visible = not lines.is_empty()

func map_markers(viewer: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in active:
		if is_instance_valid(e) and e.has_method(&"markers"):
			out.append_array(e.call(&"markers", viewer))
	return out

## Очки шоу за событие: обычное событие ShowBus (теги, подписчики), точная сумма pts.
func award(actor: Node, kind: StringName, pts: float, tags: Array = [], data: Dictionary = {}) -> float:
	if actor == null or not is_instance_valid(actor):
		return 0.0
	var base := ShowBus.emit_event(actor, kind, tags, data)
	var extra := pts - base
	if absf(extra) > 0.001:
		var aid := actor.get_instance_id()
		ShowBus.points[aid] = float(ShowBus.points.get(aid, 0.0)) + extra
		var tm: Variant = actor.get(&"team")
		if tm != null and int(tm) >= 0:
			ShowBus.team_points[int(tm)] = float(ShowBus.team_points.get(int(tm), 0.0)) + extra
	return pts

# ------------------------------------------------------------ запросы систем

## Отравлен ли источник пресной воды в точке.
static func is_poisoned(pos: Vector3) -> bool:
	var se := instance()
	if se == null:
		return false
	var e := se.get_active(&"poison_spring")
	return e != null and bool(e.call(&"poisoned_at", pos))

## Бот обходит этот источник (предупреждён или видит признаки рядом).
static func bot_avoids_water(pos: Vector3, bot: Node) -> bool:
	var se := instance()
	if se == null:
		return false
	var e := se.get_active(&"poison_spring")
	return e != null and bool(e.call(&"bot_knows", pos, bot))

## {phase: "" | "withdraw" | "wave" | "surge" | "recede", dir: Vector2, front: float}
static func tsunami_info() -> Dictionary:
	var se := instance()
	if se == null:
		return {}
	var e := se.get_active(&"tsunami")
	return e.call(&"info") if e else {}

static func bounty_target() -> Node3D:
	var se := instance()
	if se == null:
		return null
	var e := se.get_active(&"bounty")
	return e.call(&"target_node") if e else null

## Зной штиля (0..1) — добавка к температуре тела (BodyState).
static func heat() -> float:
	var se := instance()
	if se == null:
		return 0.0
	var e := se.get_active(&"calm")
	return float(e.call(&"heat_now")) if e else 0.0
