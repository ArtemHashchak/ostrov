class_name SeasonEvent
extends Node3D
## Базовое событие сезона (v5.2). Управляет SeasonEvents: begin() — один раз при старте,
## step(dt) — каждый кадр (dt уже умножен на SeasonEvents.time_scale), finish() — конец.
## hud_line() — строка в списке активных событий (правый верх). Параметры — assets/data/events.json.

var id: StringName = &""
var director: Node = null
var cfg: Dictionary = {}
var t := 0.0
var duration := 300.0
var done := false
var rng := RandomNumberGenerator.new()

func setup(p_id: StringName, p_director: Node, opts: Dictionary) -> void:
	id = p_id
	director = p_director
	cfg = (DataTables.table("events").get(String(p_id), {}) as Dictionary).duplicate(true)
	for k in opts.keys():
		cfg[k] = opts[k]
	duration = float(cfg.get("duration_s", duration))
	rng.seed = int(opts.get("seed", Time.get_ticks_usec()))
	name = "Ev_" + String(p_id)

func begin() -> void:
	pass

func step(_dt: float) -> void:
	pass

func finish() -> void:
	done = true

func hud_line() -> String:
	return ""

## Остаток времени «м:сс».
func left_text() -> String:
	var s := int(maxf(duration - t, 0.0))
	return "%d:%02d" % [s / 60, s % 60]

# ------------------------------------------------------------ общее

func world() -> Node:
	return get_tree().get_first_node_in_group(&"world") if is_inside_tree() else null

func player() -> Node3D:
	return get_tree().get_first_node_in_group(&"player") as Node3D

func host_line(key: String, args: Array = []) -> String:
	var lines: Array = (DataTables.table("events").get("host", {}) as Dictionary).get(key, [])
	if lines.is_empty():
		return ""
	var s := String(lines[rng.randi_range(0, lines.size() - 1)])
	if args.is_empty():
		return s
	var n := s.count("%s")
	var a := args.slice(0, n)
	while a.size() < n:
		a.append("")
	return s % a

func say(text: String, prio: bool = false) -> void:
	if director and director.has_method(&"say"):
		director.call(&"say", text, prio)

## «северо-восток, ≈ 420 м» относительно игрока.
func where(pos: Vector3) -> String:
	var p := player()
	var from := p.global_position if p else Vector3.ZERO
	var d := Vector2(pos.x - from.x, pos.z - from.z)
	return "%s, ≈ %d м" % [Supply.compass(d), int(round(d.length() / 10.0) * 10.0)]

func characters() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for c in get_tree().get_nodes_in_group(&"characters"):
		if c is Node3D and alive(c):
			out.append(c as Node3D)
	return out

static func alive(c: Node) -> bool:
	if c == null or not is_instance_valid(c):
		return false
	var a: Variant = c.get(&"alive")
	if a != null:
		return bool(a)
	var h: Variant = c.get(&"health")
	return h == null or float(h) > 0.0
