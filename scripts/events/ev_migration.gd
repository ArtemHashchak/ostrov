extends SeasonEvent
## Миграция мант (иногда с горбатым китом) вдоль архипелага: невидимый «вожак» идёт по дуге
## кольца у внешних островов (видно с берега и с лодок), только по открытому морю глубже
## min_depth. Манты держат строй (follow), изредка выпрыгивают; кит идёт у поверхности.
## Существа — критеры моря (OceanRoster «manta»/«whale») в сцене консоли CreatureSpawner.

var route: Array[Vector3] = []
var _seg := 0
var _pod: Node3D
var _crit: Array = []
var _leap_t := 0.0
var _whale := false
var _whale_node: Node = null
var _announced := false

func begin() -> void:
	var w := world()
	if w == null:
		done = true
		return
	route = _build_route(w)
	if route.size() < 2:
		push_warning("[events] миграция: не нашлось морского маршрута")
		done = true
		return
	_pod = Node3D.new()
	_pod.name = "MigrationPod"
	add_child(_pod)
	_pod.global_position = route[0]
	var cs := CreatureSpawner.instance()
	var st: Variant = cs.call(&"_stage") if cs else null
	if st == null:
		done = true
		return
	var mr: Array = cfg.get("mantas", [5, 8])
	var n := rng.randi_range(int(mr[0]), int(mr[1]))
	for i in n:
		var off := Vector3(rng.randf_range(-9.0, 9.0), rng.randf_range(-1.5, 0.5), float(i) * 3.2 + rng.randf_range(-1.0, 1.0))
		var c: Node = st.call(&"critter", "manta", route[0] + off)
		if c:
			c.call(&"follow", _pod, off, 1.7)
			_crit.append(c)
	if rng.randf() < float(cfg.get("whale_chance", 0.55)):
		var off2 := Vector3(-22.0, 0.0, 14.0)
		var wc: Node = st.call(&"critter", "whale", route[0] + off2)
		if wc:
			wc.call(&"follow", _pod, off2, 1.4)
			_crit.append(wc)
			_whale = true
			_whale_node = wc
	_leap_t = rng.randf_range(8.0, 16.0)
	# длительность — по длине маршрута
	var L := 0.0
	for i in range(1, route.size()):
		L += route[i].distance_to(route[i - 1])
	duration = minf(float(cfg.get("duration_s", 600)), L / float(cfg.get("speed", 1.8)) + 10.0)
	var mid := route[route.size() / 2]
	say(host_line("migration", [where(mid)]) + (" С ними — горбатый кит." if _whale else ""))

func _build_route(w: Node) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var R := float(cfg.get("ring_r", 1430.0))
	var arc := deg_to_rad(float(cfg.get("arc_deg", 150.0)))
	var md := float(cfg.get("min_depth", 8.0))
	var a0 := rng.randf() * TAU
	var dir := 1.0 if rng.randf() < 0.5 else -1.0
	var steps := int(arc * R / 50.0)
	var wl := float(w.call(&"water_level"))
	for i in steps + 1:
		var a := a0 + dir * arc * float(i) / float(steps)
		var ok := false
		for dr: float in [0.0, 40.0, -40.0, 80.0, 120.0, -80.0, 160.0]:
			var r := clampf(R + dr, 300.0, ArchipelagoV5.HALF - 25.0)
			var x := cos(a) * r
			var z := sin(a) * r
			if bool(w.call(&"sea_ok", x, z, md)):
				out.append(Vector3(x, wl - 2.2, z))
				ok = true
				break
		if not ok and not out.is_empty():
			continue
	return out

func step(dt: float) -> void:
	if _pod == null:
		return
	var spd := float(cfg.get("speed", 1.8))
	# вожак ждёт стаю: идёт, только пока манты держатся рядом (не обгоняет их)
	var gc := group_center()
	if gc != Vector3.INF and Vector2(gc.x - _pod.global_position.x, gc.z - _pod.global_position.z).length() > 14.0:
		spd *= 0.15
	var left := spd * dt
	while left > 0.0 and _seg < route.size() - 1:
		var a := _pod.global_position
		var b := route[_seg + 1]
		var d := a.distance_to(b)
		if d <= left:
			_pod.global_position = b
			left -= d
			_seg += 1
		else:
			_pod.global_position = a + (b - a) / d * left
			left = 0.0
	if _seg < route.size() - 1:
		_pod.look_at(route[_seg + 1], Vector3.UP)
	else:
		done = true
	_leap_t -= dt
	if _leap_t <= 0.0:
		var lr: Array = cfg.get("leap_every_s", [18, 40])
		_leap_t = rng.randf_range(float(lr[0]), float(lr[1]))
		var mantas := _crit.filter(func(c: Variant) -> bool: return is_instance_valid(c) and c != _whale_node)
		if not mantas.is_empty():
			var c: Node = mantas[rng.randi_range(0, mantas.size() - 1)]
			var fwd := -_pod.global_basis.z
			c.call(&"leap", fwd * 4.0 + Vector3.UP * 7.5)
			# через 3 с — снова в строй
			get_tree().create_timer(3.0).timeout.connect(func() -> void:
				if is_instance_valid(c) and is_instance_valid(_pod):
					c.call(&"follow", _pod, Vector3(rng.randf_range(-9, 9), -0.5, rng.randf_range(0, 20)), 1.7))

func finish() -> void:
	for c in _crit:
		if is_instance_valid(c):
			(c as Node).queue_free()
	_crit.clear()
	super.finish()

## Центр стаи (без кита) — для камеры и метки.
func group_center() -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for k in _crit:
		if is_instance_valid(k) and k != _whale_node:
			c += (k as Node3D).global_position
			n += 1
	return c / float(n) if n > 0 else Vector3.INF

func pod_pos() -> Vector3:
	return _pod.global_position if _pod else Vector3.INF

func hud_line() -> String:
	return "Миграция мант%s — %s (%s)" % [" и кита" if _whale else "", where(pod_pos()), left_text()]

func markers(_viewer: Node) -> Array[Dictionary]:
	return [{"pos": pod_pos(), "color": Color(0.45, 0.8, 1.0), "kind": &"event", "label": "Манты"}]
