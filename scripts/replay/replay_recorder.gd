class_name ReplayRecorder
extends Node
## Запись последних секунд игры на полигоне для реплея в максимальной графике.
## Кольцевой буфер (MAX_SEC с, REC_HZ кадров/с): камера и игрок (позиция, взгляд,
## зум, предмет в руках), существа рядом (позиция, поворот, скорость, анимация),
## физические предметы, выстрелы (Combat.last_shot), погода/время/ветер/уровень моря.
## ReplayRecorder.request(tree, сек) сохраняет клип в user://replays/<id>/clip.json и
## запускает рендер (ReplayRender). Воспроизведение — по записи, не пересимуляцией.

const REC_HZ := 30.0
const MAX_SEC := 60.0
const ACTOR_R := 80.0            # существа дальше от камеры не пишем
const MAX_ACTORS := 160

var host: Node                    # Polygon или PolygonIslandStage
var meta: Dictionary = {}
var frames: Array = []            # [{t, cam, pl, held, zoom, env, act: {key: [...]}}]
var events: Array = []            # [{t, type, ...}]
var actors: Dictionary = {}       # key → описание создания {type, ...}
var _t := 0.0
var _acc := 0.0
var _last_shot_ref: Variant = null
var _keys := {}                   # instance_id → key

func setup(h: Node, m: Dictionary) -> void:
	host = h
	meta = m

func _physics_process(delta: float) -> void:
	if host == null or not is_instance_valid(host):
		return
	_t += delta
	_shots()
	_acc += delta
	if _acc < 1.0 / REC_HZ:
		return
	_acc = 0.0
	var f := sample()
	if not f.is_empty():
		frames.append(f)
	# кольцо: старше MAX_SEC — выбросить
	while not frames.is_empty() and _t - float(frames[0].t) > MAX_SEC:
		frames.pop_front()
	while not events.is_empty() and _t - float(events[0].t) > MAX_SEC:
		events.pop_front()

## Один кадр записи (тестам — тоже).
func sample() -> Dictionary:
	var pl := host.get(&"player") as Player
	var cam := get_viewport().get_camera_3d()
	if pl == null or cam == null:
		return {}
	var w := host.get(&"world") as World
	var f := {"t": _t, "cam": _xf(cam.global_transform), "fov": cam.fov,
		"pl": [pl.global_position.x, pl.global_position.y, pl.global_position.z, float(pl.get(&"_yaw")), float(pl.get(&"_pitch"))],
		"held": String(pl.held_item()), "zoom": pl.fov_zoom, "act": {}}
	if w:
		f["env"] = [w.time_of_day(), String(w.weather()), w.wind_speed(), w.wind_dir().x, w.wind_dir().y,
			float(w.get(&"tide_offset")) if w.get(&"tide_offset") != null else w.water_level()]
	var cp := cam.global_position
	var n := 0
	for a in _candidates():
		var a3 := a as Node3D
		if a3 == null or not a3.is_inside_tree() or a3.global_position.distance_to(cp) > ACTOR_R:
			continue
		var key := _key(a3)
		if key == "":
			continue
		var rec: Array = _xf(a3.global_transform)
		var v := Vector3.ZERO
		if a3 is CharacterBody3D:
			v = (a3 as CharacterBody3D).velocity
		elif a3 is RigidBody3D:
			v = (a3 as RigidBody3D).linear_velocity
		rec.append_array([v.x, v.y, v.z])
		var ap := _anim(a3)
		if ap and ap.current_animation != "":
			rec.append_array([String(ap.current_animation), ap.current_animation_position])
		(f.act as Dictionary)[key] = rec
		n += 1
		if n >= MAX_ACTORS:
			break
	return f

func _candidates() -> Array:
	var tr := get_tree()
	var out: Array = []
	out.append_array(tr.get_nodes_in_group(&"wild_animals"))
	out.append_array(tr.get_nodes_in_group(&"sharks"))
	out.append_array(tr.get_nodes_in_group(&"replay_actor"))
	for p in tr.get_nodes_in_group(&"pickups"):
		if p is RigidBody3D and not (p as RigidBody3D).freeze:
			out.append(p)
	return out

## Ключ актёра и описание его создания (один раз на актёра).
func _key(a: Node3D) -> String:
	var iid := a.get_instance_id()
	if _keys.has(iid):
		return _keys[iid]
	var desc := {}
	if a.has_meta(&"replay_spawn"):
		desc = a.get_meta(&"replay_spawn")
	elif a is Animal:
		desc = {"type": "fauna", "species": String((a as Animal).species)}
	elif a.is_in_group(&"sharks") and a.get(&"species") != null:
		desc = {"type": "shark", "species": String(a.get(&"species"))}
	elif a is ItemPickup:
		desc = {"type": "pickup", "items": (a as ItemPickup).stacks.duplicate(true)}
	if desc.is_empty():
		return ""
	var key := "a%d" % _keys.size()
	_keys[iid] = key
	actors[key] = desc
	return key

static func _anim(a: Node) -> AnimationPlayer:
	if a.has_meta(&"_rp_ap"):
		var c: Variant = a.get_meta(&"_rp_ap")
		return c as AnimationPlayer if c is AnimationPlayer and is_instance_valid(c) else null
	var aps := a.find_children("*", "AnimationPlayer", true, false)
	var ap: AnimationPlayer = aps[0] if not aps.is_empty() else null
	a.set_meta(&"_rp_ap", ap)
	return ap

static func _xf(x: Transform3D) -> Array:
	var q := x.basis.get_rotation_quaternion()
	var s := x.basis.get_scale()
	return [x.origin.x, x.origin.y, x.origin.z, q.x, q.y, q.z, q.w, s.x]

static func xf_of(a: Array) -> Transform3D:
	var q := Quaternion(float(a[3]), float(a[4]), float(a[5]), float(a[6])).normalized()
	var s := float(a[7]) if a.size() > 7 else 1.0
	return Transform3D(Basis(q).scaled(Vector3.ONE * s), Vector3(float(a[0]), float(a[1]), float(a[2])))

func _shots() -> void:
	var ls: Dictionary = Combat.last_shot
	if ls.is_empty():
		return
	if is_same(ls, _last_shot_ref):
		return
	_last_shot_ref = ls
	var d: Dictionary = ls
	var pl := host.get(&"player") as Node
	if d.get("shooter") != pl:
		return
	var o: Vector3 = d.get("origin", Vector3.ZERO)
	var dir: Vector3 = d.get("aim", d.get("dir", Vector3.FORWARD))
	events.append({"t": _t, "type": "shot", "weapon": String(d.get("weapon", "")), "o": [o.x, o.y, o.z], "d": [dir.x, dir.y, dir.z]})

## Клип последних sec секунд: время с нуля.
func clip(sec: float) -> Dictionary:
	var t0 := _t - sec
	var fr: Array = []
	for f: Dictionary in frames:
		if float(f.t) >= t0:
			var c := f.duplicate()
			c.t = float(f.t) - t0
			fr.append(c)
	if not fr.is_empty():
		var shift := float(fr[0].t)
		for f: Dictionary in fr:
			f.t = float(f.t) - shift
		t0 += shift
	var ev: Array = []
	for e: Dictionary in events:
		if float(e.t) >= t0:
			var c := e.duplicate()
			c.t = float(e.t) - t0
			ev.append(c)
	var used := {}
	for f: Dictionary in fr:
		for k: String in (f.act as Dictionary):
			used[k] = actors.get(k, {})
	var m := meta.duplicate()
	if host is Polygon:
		m["section"] = String((host as Polygon).current_section())
	var dur := float(fr[-1].t) if not fr.is_empty() else 0.0
	return {"version": 1, "meta": m, "hz": REC_HZ, "duration": dur, "frames": fr, "events": ev, "actors": used}

## Сохранить клип и запустить рендер в максимальной графике.
static func request(tree: SceneTree, sec: float = 30.0) -> String:
	var rec := tree.get_first_node_in_group(&"replay_recorder") as ReplayRecorder
	if rec == null:
		for n in tree.root.find_children("ReplayRecorder", "ReplayRecorder", true, false):
			rec = n as ReplayRecorder
	if rec == null:
		Events.toast.emit("Реплей доступен на полигоне")
		return ""
	var c := rec.clip(clampf(sec, 3.0, MAX_SEC))
	if (c.frames as Array).size() < 10:
		Events.toast.emit("Запись слишком короткая — поиграйте ещё несколько секунд")
		return ""
	var path := ReplayRender.save_clip(c)
	ReplayRender.begin(tree, path)
	return path

func _ready() -> void:
	add_to_group(&"replay_recorder")
	process_physics_priority = 900
