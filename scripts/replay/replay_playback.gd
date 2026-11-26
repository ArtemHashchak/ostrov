class_name ReplayPlayback
extends Node
## Покадровое воспроизведение клипа (дочерний процесс рендера реплея).
## Запуск: игра с аргументами `-- --replay-render=<clip.json> --replay-quality=3` и
## `--fixed-fps 60`. main_menu вызывает maybe_start(): пресет графики (без сохранения
## настроек), сцена клипа (музей полигона или остров) в режиме реплея — без «живых»
## существ и без интерфейса; ReplayPlayback водит игрока, камеру, существ, предметы,
## выстрелы и погоду строго по записи и сохраняет каждый кадр в frames/*.jpg.
## Пишет прогресс в progress.json и закрывает игру в конце.

const WARMUP_FRAMES := 90        # прогрев: подгрузка, LOD, тени, флора (кадры не пишутся)
const JPG_Q := 0.92
## Кадр видео считается в отдельном окне-вьюпорте этого размера (не зависит от размера
## окна игры и экрана ноутбука); основное окно 3D не рисует — вся видеокарта на кадр.
const FRAME_SIZE := Vector2i(1920, 1080)

static var clip: Dictionary = {}
static var clip_dir := ""
static var quality := 3
static var capture := true        # тесты: без записи кадров и выхода
static var frame_size := FRAME_SIZE

var host: Node
var frame := -WARMUP_FRAMES
var total := 0
var _frames: Array = []
var _events: Array = []
var _ev_i := 0
var _actors: Dictionary = {}       # key → Node3D
var _t := 0.0
var _done := false
var applied: Array = []            # для тестов: [{t, key, pos}]
var _sub: SubViewport
var _cam: Camera3D

## Разбор аргументов; true — игра запущена как рендер реплея.
static func maybe_start(tree: SceneTree) -> bool:
	var path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--replay-render="):
			path = a.substr(16)
		elif a.begins_with("--replay-quality="):
			quality = clampi(int(a.substr(17)), 0, 3)
		elif a.begins_with("--replay-size="):
			var wh := a.substr(14).split("x")
			if wh.size() == 2:
				frame_size = Vector2i(maxi(64, int(wh[0])), maxi(64, int(wh[1])))
	if path == "":
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary):
		push_error("[replay] клип не читается: " + path)
		tree.quit(2)
		return true
	clip = d
	clip_dir = path.get_base_dir()
	_graphics()
	open_scene(tree)
	return true

## Пресет графики для рендера — только в памяти (настройки игрока не сохраняются).
static func _graphics() -> void:
	Settings.graphics_detected = true
	Settings.graphics_quality = quality
	Settings.render_scale = 1.0
	Settings.dynamic_resolution = false
	Settings.vsync = false
	Settings.fps_cap = 0
	Settings.fullscreen = false
	Settings.flora_distance = 2.0
	Settings.apply_graphics()

static func open_scene(tree: SceneTree) -> void:
	var m: Dictionary = clip.get("meta", {})
	var fr: Array = clip.get("frames", [])
	var opts := {"replay_mode": true}
	if not fr.is_empty():
		var p: Array = fr[0].pl
		opts["pos"] = Vector3(float(p[0]), float(p[1]), float(p[2]))
	if String(m.get("scene", "polygon")) == "island":
		PolygonIslandStage.open(tree, String(m.get("island", "volcanic")), opts)
	else:
		if String(m.get("section", "")) != "":
			opts["section"] = StringName(m.section)
		Polygon.start(tree, opts)

## Вызывает сцена (Polygon/PolygonIslandStage) в режиме реплея, когда готова.
static func attach(h: Node) -> ReplayPlayback:
	if clip.is_empty():
		return null
	var rp := ReplayPlayback.new()
	rp.name = "ReplayPlayback"
	rp.host = h
	h.add_child(rp)
	return rp

func _ready() -> void:
	process_physics_priority = 1000
	process_priority = 1000
	_frames = clip.get("frames", [])
	_events = clip.get("events", [])
	total = int(ceil(float(clip.get("duration", 0.0)) * ReplayRender.FPS)) + 1
	_hide_ui()
	var pl := host.get(&"player") as Player
	if pl:
		pl.input_enabled = false
		if host.get(&"cheats"):
			(host.get(&"cheats") as SandboxCheats).set_infinite(true, true)
			(host.get(&"cheats") as SandboxCheats).god = true
	if capture:
		_make_capture()
		RenderingServer.frame_post_draw.connect(_on_drawn)
		_progress("render")

## Вьюпорт кадра: тот же 3D-мир, своя камера — копия камеры игрока каждый кадр.
func _make_capture() -> void:
	var root := get_tree().root
	_sub = SubViewport.new()
	_sub.name = "ReplayFrame"
	_sub.size = frame_size
	_sub.world_3d = root.world_3d
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sub.own_world_3d = false
	add_child(_sub)
	GraphicsQuality.apply_viewport(_sub)
	_sub.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	_sub.scaling_3d_scale = 1.0
	if not GraphicsQuality.is_compat():
		_sub.use_taa = true
		_sub.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_cam = Camera3D.new()
	_sub.add_child(_cam)
	_cam.current = true
	root.disable_3d = true

func _process(_delta: float) -> void:
	if _cam == null:
		return
	var src := get_tree().root.get_camera_3d()
	if src == null or src == _cam:
		return
	_cam.global_transform = src.global_transform
	_cam.fov = src.fov
	_cam.near = src.near
	_cam.far = src.far
	_cam.environment = src.environment
	_cam.attributes = src.attributes
	_cam.cull_mask = src.cull_mask

func _hide_ui() -> void:
	var ui := MatchUI.instance()
	if ui:
		for c in ui.get_children():
			if c is CanvasLayer:
				(c as CanvasLayer).visible = false
	var pl := host.get(&"player") as Node
	if pl:
		for c in pl.get_children():
			if c is CanvasLayer:
				(c as CanvasLayer).visible = false

## Кадр записи на время t (линейно между соседними).
func frame_at(t: float) -> Array:
	if _frames.is_empty():
		return [{}, {}, 0.0]
	var i := 0
	var lo := 0
	var hi := _frames.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if float(_frames[mid].t) <= t:
			lo = mid
		else:
			hi = mid - 1
	i = lo
	var a: Dictionary = _frames[i]
	var b: Dictionary = _frames[mini(i + 1, _frames.size() - 1)]
	var span := float(b.t) - float(a.t)
	var k := clampf((t - float(a.t)) / span, 0.0, 1.0) if span > 0.0001 else 0.0
	return [a, b, k]

func _physics_process(_delta: float) -> void:
	if _done:
		return
	_t = maxf(0.0, frame) / float(ReplayRender.FPS)
	apply(_t)
	frame += 1
	if not capture and frame >= total:
		_done = true

## Применить состояние записи на время t (игрок, камера, мир, существа, события).
func apply(t: float) -> void:
	var fk := frame_at(t)
	var a: Dictionary = fk[0]
	var b: Dictionary = fk[1]
	var k: float = fk[2]
	if a.is_empty():
		return
	var pl := host.get(&"player") as Player
	if pl:
		var pa: Array = a.pl
		var pb: Array = b.pl
		var pos := Vector3(float(pa[0]), float(pa[1]), float(pa[2])).lerp(Vector3(float(pb[0]), float(pb[1]), float(pb[2])), k)
		pl.global_position = pos
		pl.velocity = Vector3.ZERO
		pl.set_look(lerp_angle(float(pa[3]), float(pb[3]), k), lerpf(float(pa[4]), float(pb[4]), k))
		pl.fov_zoom = lerpf(float(a.get("zoom", 0.0)), float(b.get("zoom", 0.0)), k)
		var held := StringName(a.get("held", ""))
		if held != pl.held_item():
			_hold(pl, held)
	_env(a)
	_actors_apply(a, b, k, t)
	while _ev_i < _events.size() and float(_events[_ev_i].t) <= t:
		_event(_events[_ev_i])
		_ev_i += 1

func _hold(pl: Player, id: StringName) -> void:
	var inv := pl.inventory
	if id == &"":
		inv.select(Inventory.HOTBAR - 1)
		return
	for i in Inventory.HOTBAR:
		if StringName(inv.get_slot(i).get("id", &"")) == id:
			inv.select(i)
			return
	# предмета нет в быстрых слотах — положить в первый
	inv.set_slot(0, {"id": id, "n": 1})
	inv.select(0)

var _env_key := ""

func _env(f: Dictionary) -> void:
	var e: Array = f.get("env", [])
	var w := host.get(&"world") as World
	if e.is_empty() or w == null:
		return
	var key := "%s|%.2f" % [e[1], float(e[0])]
	if key != _env_key:
		if String(e[1]) != String(w.weather()):
			var sk: Object = w.get(&"sky")
			if sk and sk.has_method(&"set_weather"):
				sk.call(&"set_weather", StringName(e[1]), true, false)
		_env_key = key
	if absf(w.time_of_day() - float(e[0])) > 0.01:
		w.set_time_of_day(float(e[0]))
	if w.has_method(&"set_tide") and e.size() > 5:
		w.call(&"set_tide", float(e[5]))

func _actors_apply(a: Dictionary, b: Dictionary, k: float, t: float) -> void:
	var aa: Dictionary = a.get("act", {})
	var bb: Dictionary = b.get("act", {})
	var seen := {}
	for key: String in aa:
		seen[key] = true
		var node := _actor(key, aa[key])
		if node == null:
			continue
		var ra: Array = aa[key]
		var xf := ReplayRecorder.xf_of(ra)
		if bb.has(key):
			xf = xf.interpolate_with(ReplayRecorder.xf_of(bb[key]), k)
		node.visible = true
		node.global_transform = xf
		if node is CharacterBody3D and ra.size() >= 11:
			(node as CharacterBody3D).velocity = Vector3(float(ra[8]), float(ra[9]), float(ra[10]))
		if ra.size() >= 13:
			var ap := ReplayRecorder._anim(node)
			if ap:
				var an := StringName(ra[11])
				if ap.has_animation(an):
					if ap.current_animation != an:
						ap.play(an)
					ap.seek(float(ra[12]), true)
		if not capture:
			applied.append({"t": t, "key": key, "pos": xf.origin})
	# не попавшие в кадр записи — спрятать (ушли далеко от камеры)
	for key: String in _actors:
		if not seen.has(key) and is_instance_valid(_actors[key]):
			(_actors[key] as Node3D).visible = false

func _actor(key: String, rec: Array) -> Node3D:
	if _actors.has(key):
		var n: Variant = _actors[key]
		return n as Node3D if is_instance_valid(n) else null
	var desc: Dictionary = (clip.get("actors", {}) as Dictionary).get(key, {})
	var pos := Vector3(float(rec[0]), float(rec[1]), float(rec[2]))
	var node: Node3D = null
	match String(desc.get("type", "")):
		"fauna":
			if Fauna.instance():
				node = Fauna.instance().spawn(StringName(desc.species), pos, 1.0)
		"shark":
			var sea := get_tree().get_first_node_in_group(&"sea")
			if sea and sea.has_method(&"spawn_shark"):
				node = sea.call(&"spawn_shark", StringName(desc.species), Vector2(pos.x, pos.z), maxf(0.5, -pos.y), 7) as Node3D
		"spawner":
			var cs := CreatureSpawner.instance()
			var info := CreatureSpawner.find(String(desc.id))
			if cs and not info.is_empty():
				node = cs.call(&"_spawn_one", info, pos, 0.0) as Node3D
		"catalog":
			var sc := PolygonExhibits.catalog_script()
			if sc:
				node = sc.call(&"instantiate", String(desc.id), 0) as Node3D
				if node:
					host.add_child(node)
		"pickup":
			var items: Array[Dictionary] = []
			for s in desc.get("items", []):
				items.append({"id": StringName(s.id), "n": int(s.n)})
			var pk := ItemPickup.spawn(host, pos, items)
			if pk:
				pk.freeze = true
				pk.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			node = pk
	_actors[key] = node
	return node

func _event(e: Dictionary) -> void:
	if String(e.get("type", "")) != "shot":
		return
	var pl := host.get(&"player") as Node
	var o: Array = e.o
	var d: Array = e.d
	var wid := StringName(e.weapon)
	Combat.fire(pl, wid, Vector3(float(o[0]), float(o[1]), float(o[2])), Vector3(float(d[0]), float(d[1]), float(d[2])),
		{"ads": true})

# ------------------------------------------------------------ кадры и прогресс

func _on_drawn() -> void:
	if _done or frame <= 0:
		return
	var idx := frame - 1
	if idx >= total:
		_finish()
		return
	var img := (_sub.get_texture() if _sub else get_viewport().get_texture()).get_image()
	if img:
		img.save_jpg(clip_dir + "/frames/f%05d.jpg" % idx, JPG_Q)
	if idx % 15 == 0:
		_progress("render", idx)

func _progress(stage: String, i: int = 0) -> void:
	var f := FileAccess.open(clip_dir + "/progress.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"stage": stage, "frame": i, "total": total, "frames": total, "quality": quality}))
		f.close()

func _finish() -> void:
	if _done:
		return
	_done = true
	_progress("done", total)
	get_tree().quit(0)
