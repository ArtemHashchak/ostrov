class_name LandScene
extends Node3D
## Одна сценка режиссёра суши (LandDirector). kind — id из LandDirector.CATALOG.
## Актёры — Animal со «scripted» (мышление выключено): сценка задаёт им цель (move_to) и
## состояние, птицам — свой «словарь стаи» (flock), за центром которого они летят.
## Тикает актёров сама (они не в списке Fauna). Мёртвые актёры остаются тушками
## (передаются режиссёру — падальщики, мухи). Новых анимаций нет: клипы/процедурные.

var kind := ""
var director: LandDirector
var forced := false
var seed_value := 0
var done := false
var t := 0.0
var duration := 40.0
var actors: Array[Animal] = []
var props: Array[Node3D] = []
var flocks: Array[Dictionary] = []
var data := {}          # состояние конкретной сценки
var _rng := RandomNumberGenerator.new()

# ============================================================ общие помощники

func setup() -> bool:
	_rng.seed = seed_value
	name = "Scene_" + kind
	var f := Callable(self, "_setup_" + kind)
	if not f.is_valid():
		return false
	return bool(f.call())

func _process(dt: float) -> void:
	if done:
		return
	t += dt
	for av: Variant in actors:
		if is_instance_valid(av):
			var a := av as Animal
			if not a.has_meta(&"carried") and not a.is_queued_for_deletion():
				a.tick(dt)
	var f := Callable(self, "_tick_" + kind)
	if f.is_valid():
		f.call(dt)
	if t > duration:
		done = true

func cleanup() -> void:
	done = true
	for av: Variant in actors:
		if not is_instance_valid(av):
			continue
		var a := av as Animal
		if a.dead and director:
			director.keep_corpse(a)      # тушка остаётся: мухи, падальщики, варан
		else:
			a.queue_free()
	actors.clear()
	for pv: Variant in props:
		if is_instance_valid(pv) and not (pv as Node).has_meta(&"persist"):
			(pv as Node).queue_free()
	props.clear()
	if not is_queued_for_deletion():
		queue_free()

func _g(x: float, z: float) -> float:
	return director.ground(x, z) if director else 0.0

func _gp(p: Vector3) -> Vector3:
	return Vector3(p.x, _g(p.x, p.z), p.z)

func _wl() -> float:
	return director.water_y() if director else 0.0

func _origin() -> Vector3:
	return global_position

## Сухопутный актёр. walk — своя скорость шага (м/с), growth — размер (детёныши).
func animal(sp: StringName, pos: Vector3, growth: float = 1.0, walk: float = -1.0) -> Animal:
	var a := Animal.create(sp, _gp(pos), Fauna.instance())
	a.cfg = (Animal.SPECIES.get(sp, Animal.SPECIES[&"boar"]) as Dictionary).duplicate(true)
	if walk > 0.0:
		a.cfg["walk"] = walk
	a.scripted = true
	a.home = _gp(pos)
	a.home_r = 30.0
	var root := director.actors_root if director and director.actors_root else self
	root.add_child(a)
	a.global_position = _gp(pos)
	if growth != 1.0:
		a.set_growth(growth)   # масштаб модели (детёныш, мелкий краб в клюве)
	a.add_to_group(&"director_actors")
	actors.append(a)
	return a

## Птица (стая из одной/нескольких): летит за центром flock["pos"], который двигает сценка.
func flock_of(sp: StringName, pos: Vector3, n: int, spread: float = 2.0, night_ok := true) -> Dictionary:
	var fl := {"species": sp, "home": pos, "r": 20.0, "mode": &"fly", "pos": pos, "target": pos,
		"t": 0.0, "perch": Vector3.INF, "members": [], "scare_t": 0.0}
	for i in n:
		var off := Vector3(_rng.randf_range(-spread, spread), _rng.randf_range(-spread * 0.4, spread * 0.4), _rng.randf_range(-spread, spread))
		if n == 1:
			off = Vector3.ZERO
		var a := Animal.create(sp, pos + off, Fauna.instance())
		a.cfg = (Animal.SPECIES[sp] as Dictionary).duplicate(true)
		if night_ok:
			a.cfg["night"] = false          # летучие мыши видимы в сумерках сценки
		a.flock = fl
		a.flock_offset = off
		var root := director.actors_root if director and director.actors_root else self
		root.add_child(a)
		a.global_position = pos + off
		a.alt = maxf(0.5, pos.y - _g(pos.x, pos.z))
		a.add_to_group(&"director_actors")
		actors.append(a)
		(fl["members"] as Array).append(a)
	flocks.append(fl)
	return fl

func go(a: Animal, p: Vector3, speed: float = -1.0) -> void:
	if not is_instance_valid(a) or a.dead:
		return
	if speed > 0.0:
		a.cfg["walk"] = speed
	a.move_to = _gp(p)
	a.state = &"wander"

func stay(a: Animal, face: Vector3 = Vector3.INF) -> void:
	if not is_instance_valid(a) or a.dead:
		return
	a.state = &"idle"
	a.speed = 0.0
	if face != Vector3.INF:
		var to := face - a.global_position
		a.heading = atan2(-to.x, -to.z)

func arrived(a: Animal, r: float = 0.8) -> bool:
	if not is_instance_valid(a):
		return true
	var d := a.global_position - a.move_to
	d.y = 0.0
	return d.length() < r

## Убрать актёра без тушки (уплыл в море, съеден).
func vanish(a: Animal) -> void:
	if is_instance_valid(a):
		actors.erase(a)
		a.queue_free()

## Тушка без добычи (для сценок): мёртвое животное лежит на боку.
func corpse(sp: StringName, pos: Vector3, wounds := 3) -> Animal:
	var a := animal(sp, pos)
	a.cfg["drops"] = []
	a.rotation.y = _rng.randf() * TAU
	_wound(a, wounds)
	a.die(null)
	# клипы смерти пака (варан и др.) не кладут тушу на бок — для сценки кладём сами: модель на бок, без перекоса в грунт
	var m: Node3D = a.get(&"_model")
	if m:
		m.rotation.z = PI * 0.5
		m.position.y += 0.22 * a.growth
	return a

## Раны на туше (Wounds/DamageMask агента I): укусы/порезы по боку и шее — тушу видно издалека как добычу.
func _wound(a: Animal, n: int) -> void:
	var wn := get_node_or_null(^"/root/Wounds")
	if wn == null or n <= 0 or not wn.has_method(&"add_hit"):
		return
	var b := a.global_basis
	for i in n:
		var side := b.x * (1.0 if i % 2 == 0 else -1.0)
		var along := b.z * _rng.randf_range(-0.35, 0.45)
		var p := a.global_position + Vector3.UP * _rng.randf_range(0.35, 0.6) + side * 0.4 + along
		wn.call(&"add_hit", a, p, side, &"", &"bite" if i != 1 else &"melee")

## Убить актёра «по сценке» (добыча остаётся, как у обычной смерти).
func kill(a: Animal) -> void:
	if is_instance_valid(a) and not a.dead:
		a.die(null)

func prop(n: Node3D, pos: Vector3, persist := false) -> Node3D:
	var root := director.actors_root if director and director.actors_root else self
	root.add_child(n)
	n.global_position = pos
	if persist:
		n.set_meta(&"persist", true)
	props.append(n)
	return n

## Всплеск на воде (рыба, падение) — белые брызги, одноразово.
func splash(p: Vector3, size: float = 1.0) -> void:
	var ps := CPUParticles3D.new()
	ps.one_shot = true
	ps.explosiveness = 0.9
	ps.amount = int(18 * size) + 6
	ps.lifetime = 0.9
	ps.direction = Vector3.UP
	ps.spread = 35.0
	ps.initial_velocity_min = 1.5 * size
	ps.initial_velocity_max = 3.5 * size
	ps.gravity = Vector3(0, -9.8, 0)
	ps.scale_amount_min = 0.05 * size
	ps.scale_amount_max = 0.14 * size
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.radial_segments = 6
	m.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.92, 0.96, 1.0, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material = mat
	ps.mesh = m
	prop(ps, Vector3(p.x, _wl() + 0.05, p.z))
	ps.emitting = true

## Пыль/песок из-под лап (кабаны роют, черепаха копает).
func dust(p: Vector3, col := Color(0.55, 0.45, 0.3)) -> void:
	var ps := CPUParticles3D.new()
	ps.one_shot = true
	ps.explosiveness = 0.8
	ps.amount = 10
	ps.lifetime = 0.8
	ps.direction = Vector3.UP
	ps.spread = 60.0
	ps.initial_velocity_min = 0.6
	ps.initial_velocity_max = 1.6
	ps.gravity = Vector3(0, -6.0, 0)
	ps.scale_amount_min = 0.03
	ps.scale_amount_max = 0.07
	var m := BoxMesh.new()
	m.size = Vector3.ONE
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 1.0
	m.material = mat
	ps.mesh = m
	prop(ps, p + Vector3.UP * 0.05)
	ps.emitting = true
	var st := _sand()
	if st:
		st.call(&"dent", p, 0.18, 0.6)

func _sand() -> Node:
	return get_tree().get_first_node_in_group(&"sand_tracks") if is_inside_tree() else null

## Рыба (предмет) — модель из HeldModels (как в руке), для чаек.
func fish_model() -> Node3D:
	var m := HeldModels.build(&"fish_raw")
	if m == null:
		m = Node3D.new()
	return m

func _dir_to(a: Vector3, b: Vector3) -> Vector3:
	var d := b - a
	d.y = 0.0
	return d.normalized() if d.length() > 0.01 else Vector3.FORWARD

func _ring(c: Vector3, r: float, ang: float, h: float) -> Vector3:
	return Vector3(c.x + cos(ang) * r, h, c.z + sin(ang) * r)

func _player_near(r: float) -> bool:
	return director != null and director.player_pos().distance_to(_origin()) < r

## Игрок подошёл к «нормальным» животным — вернуть им обычное поведение (убегут/нападут).
func _release_if_close(r: float) -> void:
	if not director:
		return
	var pp := director.player_pos()
	for av: Variant in actors:
		if not is_instance_valid(av):
			continue
		var a := av as Animal
		if not a.dead and a.scripted and not a.cfg.get("fly", false):
			if a.global_position.distance_to(pp) < r:
				a.scripted = false

# ============================================================ 1. чайка роняет краба

func _setup_gull_crab_drop() -> bool:
	var R := _origin()
	var w := director.find_water(R, 60.0) if director else Vector3.INF
	var from := (w if w != Vector3.INF else R + Vector3(25, 0, 0))
	from = R + _dir_to(R, from) * minf(16.0, Vector2(from.x - R.x, from.z - R.z).length() + 6.0)   # с кромки воды, недалеко
	var start := Vector3(from.x, maxf(_g(from.x, from.z), _wl()) + 4.0, from.z)
	var fl := flock_of(&"gull", start, 1)
	var crab := animal(&"crab", start, 0.3)   # краб-призрак: панцирь ~5–8 см, с ногами ~20 см (чайка ~1,3 м в размахе)
	crab.set_meta(&"carried", true)
	data = {"rock": R, "fl": fl, "crab": crab, "phase": 0, "vy": 0.0, "gull": fl.members[0]}
	duration = 34.0
	return true

func _tick_gull_crab_drop(dt: float) -> void:
	var fl: Dictionary = data.fl
	var gull: Animal = data.gull
	var crab: Animal = data.crab
	var R: Vector3 = data.rock
	if not is_instance_valid(gull):
		done = true
		return
	match int(data.phase):
		0:      # набирает высоту над камнями с крабом в лапах
			var goal := R + Vector3(0, 11.0, 0)
			fl.pos = (fl.pos as Vector3).move_toward(goal, dt * 5.5)
			if is_instance_valid(crab):
				crab.global_position = gull.global_position + Vector3(0, -0.12, 0)
				crab.heading = gull.heading
				crab.rotation.y = gull.heading
			if gull.global_position.distance_to(goal) < 2.5 or t > 10.0:
				data.phase = 1     # отпустила: краб падает (тикаем вручную, пока не упал)
		1:      # краб падает на камни
			fl.pos = (fl.pos as Vector3) + Vector3(sin(t) * 2.0, 0, cos(t) * 2.0) * dt
			if is_instance_valid(crab):
				data.vy = float(data.vy) - 9.8 * dt
				crab.global_position.y += float(data.vy) * dt
				var g := _g(crab.global_position.x, crab.global_position.z)
				if crab.global_position.y <= g:
					crab.global_position.y = g
					crab.remove_meta(&"carried")
					kill(crab)
					dust(crab.global_position, Color(0.6, 0.55, 0.48))
					data.phase = 2
					data.t2 = t
			else:
				data.phase = 3
		2:      # садится рядом и клюёт
			var cp := crab.global_position if is_instance_valid(crab) else R
			fl.perch = Vector3(cp.x + 0.5, _g(cp.x + 0.5, cp.z) + 0.05, cp.z)
			fl.mode = &"perch"
			if fmod(t, 1.1) < dt * 1.5 and gull.state == &"perch":
				gull.anim_event(&"eat")
			if t - float(data.t2) > 16.0:
				data.phase = 3
		3:      # улетает
			fl.mode = &"fly"
			fl.pos = (fl.pos as Vector3) + Vector3(1, 0.25, 0.6).normalized() * 9.0 * dt
			if t > duration - 1.0:
				done = true

# ============================================================ 2. черепашата бегут к морю

func _setup_hatchlings() -> bool:
	var N := _origin()
	var W := director.find_water(N, 55.0)
	if W == Vector3.INF:
		if not forced:
			return false
		W = N + Vector3(0, 0, -14)
	W += _dir_to(N, W) * 3.0
	var mound := _mound(Color(0.8, 0.72, 0.55))
	prop(mound, N)
	var babies: Array[Animal] = []
	for i in 11:
		var p := N + Vector3(_rng.randf_range(-0.35, 0.35), 0, _rng.randf_range(-0.35, 0.35))
		var b := animal(&"turtle", p, 0.14, _rng.randf_range(0.22, 0.34))
		b.set_meta(&"start_delay", _rng.randf_range(0.0, 6.0))
		b.state = &"idle"
		babies.append(b)
	var crab := animal(&"crab", N + _dir_to(W, N).rotated(Vector3.UP, 1.4) * 7.0, 1.0, 1.3)
	stay(crab, N)
	data = {"W": W, "babies": babies, "crab": crab, "prey": null}
	duration = 75.0
	return true

func _tick_hatchlings(_dt: float) -> void:
	var W: Vector3 = data.W
	var left := 0
	for _b: Variant in data.babies:
		if not is_instance_valid(_b):
			continue
		var b := _b as Animal
		if not is_instance_valid(b) or b.dead:
			continue
		left += 1
		if t < float(b.get_meta(&"start_delay", 0.0)):
			continue
		if not b.has_meta(&"goal"):
			b.set_meta(&"goal", W + Vector3(_rng.randf_range(-3, 3), 0, _rng.randf_range(-3, 3)))
		if b.state != &"wander":
			go(b, b.get_meta(&"goal"))
		if _g(b.global_position.x, b.global_position.z) < _wl() - 0.08 or arrived(b, 0.5):
			vanish(b)      # уплыл
	# краб выбирает отставшего детёныша
	var crab: Animal = data.crab
	if is_instance_valid(crab) and not crab.dead and t > 9.0 and not data.get("crab_full", false):
		var prey: Variant = data.prey
		if prey == null or not is_instance_valid(prey) or (prey as Animal).dead:
			var best: Animal = null
			var bd := INF
			for _b: Variant in data.babies:
				if not is_instance_valid(_b):
					continue
				var b := _b as Animal
				if is_instance_valid(b) and not b.dead:
					var d := crab.global_position.distance_to(b.global_position)
					if d < bd:
						bd = d
						best = b
			data.prey = best
			prey = best
		if prey != null and is_instance_valid(prey):
			var pa := prey as Animal
			go(crab, pa.global_position, 1.4)
			if crab.global_position.distance_to(pa.global_position) < 0.35:
				crab.anim_event(&"attack")
				kill(pa)
				data.crab_full = true
				data.prey = null
				go(crab, crab.global_position + _dir_to(W, crab.global_position) * 6.0, 0.8)
	if is_instance_valid(crab) and data.get("crab_full", false) and crab.state != &"wander":
		go(crab, crab.global_position + Vector3(4, 0, 4), 0.6)
	if left == 0 or t > duration - 1.0:
		done = true

func _mound(col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 0.3
	sm.radial_segments = 14
	sm.rings = 6
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 1.0
	mi.material_override = m
	mi.scale = Vector3(1, 0.5, 1)
	return mi

# ============================================================ 3. варан у туши

func _setup_monitor_carcass() -> bool:
	var C := _origin()
	var body := corpse(&"monitor", C)   # туша варана (модель автора с текстурой; у комодских варанов каннибализм — реальный сюжет)
	var a := _rng.randf() * TAU
	var mon := animal(&"monitor", C + Vector3(cos(a), 0, sin(a)) * 16.0, 1.0, 0.7)
	var spot := C + Vector3(cos(a), 0, sin(a)) * 2.3
	go(mon, spot)
	data = {"C": C, "body": body, "mon": mon, "eat_t": 0.0, "spot": spot}
	duration = 70.0
	return true

func _tick_monitor_carcass(dt: float) -> void:
	var mon: Animal = data.mon
	var C: Vector3 = data.C
	if not is_instance_valid(mon) or mon.dead:
		return
	if not mon.scripted:
		return
	var spot: Vector3 = data.spot
	var dspot := Vector2(mon.global_position.x - spot.x, mon.global_position.z - spot.z).length()
	if dspot > 1.2 and mon.state != &"wander":
		go(mon, spot)
	elif dspot <= 1.2 and mon.state == &"wander":
		stay(mon, C)
	if mon.state == &"idle":
		stay(mon, C)
		data.eat_t = float(data.eat_t) - dt
		if float(data.eat_t) <= 0.0:
			data.eat_t = _rng.randf_range(1.2, 2.4)
			mon.anim_event(&"eat")
			# короткий рывок к туше — «рвёт» мясо
			mon.global_position += _dir_to(mon.global_position, C) * 0.08
	_release_if_close(6.0)

# ============================================================ 4. ход крабов

func _setup_crab_march() -> bool:
	var S := _origin()
	var W := director.find_water(S, 70.0)
	if W == Vector3.INF:
		if not forced:
			return false
		W = S + Vector3(0, 0, -25)
	var dir := _dir_to(S, W)
	W += dir * 3.0                      # цель — уже в воде, а не на кромке
	var side := dir.rotated(Vector3.UP, PI * 0.5)
	var crabs: Array[Animal] = []
	for i in 34:
		var back := _rng.randf_range(0.0, 14.0)
		var lat := _rng.randf_range(-3.0, 3.0)
		var p := S - dir * back + side * lat
		var c := animal(&"crab", p, _rng.randf_range(0.7, 1.05), _rng.randf_range(0.55, 0.9))
		c.set_meta(&"goal", W + side * lat * 1.3)
		go(c, c.get_meta(&"goal"))
		crabs.append(c)
	data = {"W": W, "crabs": crabs}
	duration = 70.0
	return true

func _tick_crab_march(_dt: float) -> void:
	var left := 0
	for _c: Variant in data.crabs:
		if not is_instance_valid(_c):
			continue
		var c := _c as Animal
		if not is_instance_valid(c) or c.dead:
			continue
		left += 1
		if not c.scripted:
			continue
		if _g(c.global_position.x, c.global_position.z) < _wl() - 0.1 or arrived(c, 0.4):
			vanish(c)
		elif c.state != &"wander":
			go(c, c.get_meta(&"goal"))      # испугались шума и замерли — идут дальше
	_release_if_close(2.5)
	if left == 0:
		done = true

# ============================================================ 5. летучие мыши вылетают

func _setup_bat_emergence() -> bool:
	var P := _origin() + Vector3(0, 1.5, 0)
	var fl := flock_of(&"bat", P, 26, 1.2)
	data = {"P": P, "fl": fl, "split": false}
	duration = 40.0
	return true

func _tick_bat_emergence(dt: float) -> void:
	var P: Vector3 = data.P
	if t < 14.0:
		# спираль вверх из расщелины
		var ang := t * 1.6
		var fl: Dictionary = data.fl
		fl.pos = _ring(P, 4.0 + t * 0.6, ang, P.y + 2.0 + t * 1.1)
	elif not data.split:
		data.split = true
		# стая расходится на три группы
		var members: Array = (data.fl as Dictionary).members
		var groups: Array[Dictionary] = []
		for k in 3:
			var g := {"species": &"bat", "home": P, "r": 40.0, "mode": &"fly", "pos": (data.fl as Dictionary).pos,
				"perch": Vector3.INF, "members": [], "dir": Vector3.FORWARD.rotated(Vector3.UP, TAU * k / 3.0 + _rng.randf())}
			groups.append(g)
		for i in members.size():
			var a := members[i] as Animal
			if is_instance_valid(a):
				var g: Dictionary = groups[i % 3]
				a.flock = g
				(g.members as Array).append(a)
		data.groups = groups
		flocks.append_array(groups)
	else:
		for g: Dictionary in data.groups:
			g.pos = (g.pos as Vector3) + (g.dir as Vector3) * 9.0 * dt + Vector3(0, 0.6 * dt, 0)

# ============================================================ 6. чайки дерутся за рыбу

func _setup_gulls_fight() -> bool:
	var F := _origin()
	var fish := fish_model()
	prop(fish, F + Vector3(0, 0.05, 0))
	fish.rotation = Vector3(0, _rng.randf() * TAU, PI * 0.5)
	var gulls: Array[Dictionary] = []
	for i in 3:
		var a := TAU * i / 3.0
		var p := F + Vector3(cos(a), 0, sin(a)) * 0.9
		var fl := flock_of(&"gull", p + Vector3(0, 3, 0), 1)
		fl.perch = Vector3(p.x, _g(p.x, p.z) + 0.05, p.z)
		fl.mode = &"perch"
		gulls.append(fl)
	data = {"F": F, "fish": fish, "gulls": gulls, "next": 1.0, "thief": -1}
	duration = 30.0
	return true

func _tick_gulls_fight(dt: float) -> void:
	var F: Vector3 = data.F
	var gulls: Array = data.gulls
	if int(data.thief) < 0:
		data.next = float(data.next) - dt
		if float(data.next) <= 0.0:
			data.next = _rng.randf_range(0.7, 1.6)
			# одна вспархивает и садится по другую сторону рыбы, оттесняя соседку
			var k := _rng.randi() % gulls.size()
			var fl: Dictionary = gulls[k]
			var a := _rng.randf() * TAU
			var p := F + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(0.5, 1.1)
			fl.mode = &"fly"
			fl.pos = Vector3(p.x, _g(p.x, p.z) + 1.4, p.z)
			fl.perch = Vector3(p.x, _g(p.x, p.z) + 0.05, p.z)
			fl.land_at = t + 0.6
		for fl: Dictionary in gulls:
			if fl.mode == &"fly" and t > float(fl.get("land_at", 0.0)):
				fl.mode = &"perch"
		if t > 15.0:
			data.thief = _rng.randi() % gulls.size()
			var thief: Dictionary = gulls[int(data.thief)]
			thief.mode = &"fly"
			data.away = _dir_to(director.player_pos(), F)
	else:
		var thief: Dictionary = gulls[int(data.thief)]
		thief.pos = (thief.pos as Vector3) + ((data.away as Vector3) + Vector3(0, 0.35, 0)) * 7.0 * dt
		var m: Animal = (thief.members as Array)[0]
		var fish: Node3D = data.fish
		if is_instance_valid(m) and is_instance_valid(fish):
			fish.global_position = m.global_position + Vector3(0, -0.12, 0)
		# остальные гонятся
		for i in gulls.size():
			if i == int(data.thief):
				continue
			var fl: Dictionary = gulls[i]
			fl.mode = &"fly"
			fl.pos = (fl.pos as Vector3).move_toward(thief.pos as Vector3 + Vector3(0, -0.5, 0), 8.0 * dt)

# ============================================================ 7. игуаны греются

func _setup_iguanas_bask() -> bool:
	var C := _origin()
	var sun := Vector3(1, 0, -0.3).normalized()
	for i in _rng.randi_range(3, 6):
		var p := C + Vector3(_rng.randf_range(-2.5, 2.5), 0, _rng.randf_range(-2.5, 2.5))
		var a := animal(&"iguana", p, _rng.randf_range(0.75, 1.1))
		stay(a, a.global_position + sun.rotated(Vector3.UP, _rng.randf_range(-0.5, 0.5)) * 5.0)
	duration = 80.0
	return true

func _tick_iguanas_bask(_dt: float) -> void:
	for av: Variant in actors:
		if is_instance_valid(av) and (av as Animal).scripted and _rng.randf() < 0.004:
			(av as Animal).anim_event(&"threat")      # кивок головой
	_release_if_close(5.0)

# ============================================================ 8. стая попугаев на крону

func _setup_parrots_flock() -> bool:
	var C := _origin()
	var crown := _tree_top_near(C, 25.0)
	data = {"C": C, "crown": crown}
	var start := C + Vector3(-30, 16, 10)
	data.fl = flock_of(&"parrot", start, 9, 2.5)
	duration = 48.0
	return true

func _tick_parrots_flock(dt: float) -> void:
	var fl: Dictionary = data.fl
	var C: Vector3 = data.C
	var crown: Vector3 = data.crown
	if t < 12.0:
		fl.pos = _ring(C, 10.0, t * 0.8, _g(C.x, C.z) + 14.0)
	elif t < 34.0:
		if crown != Vector3.INF:
			fl.perch = crown
			fl.mode = &"perch"
		else:
			fl.pos = _ring(C, 7.0, t * 0.6, _g(C.x, C.z) + 9.0)
	else:
		fl.mode = &"fly"
		fl.pos = (fl.pos as Vector3) + Vector3(1, 0.3, -0.4).normalized() * 10.0 * dt

func _tree_top_near(c: Vector3, r: float) -> Vector3:
	var best := Vector3.INF
	var bd := INF
	for tr in get_tree().get_nodes_in_group(&"trees"):
		if tr is Node3D:
			var p := (tr as Node3D).global_position
			var d := Vector2(p.x - c.x, p.z - c.z).length()
			if d < r and d < bd:
				bd = d
				best = Fauna._tree_top(tr as Node3D)
	return best

# ============================================================ 9. кабаны роют землю

func _setup_boar_family() -> bool:
	var C := _origin()
	var sow := animal(&"boar", C, 1.0, 0.8)
	var piglets: Array[Animal] = []
	for i in 3:
		piglets.append(animal(&"boar", C + Vector3(_rng.randf_range(-1.5, 1.5), 0, _rng.randf_range(-1.5, 1.5)), 0.45, 1.1))
	data = {"C": C, "sow": sow, "piglets": piglets, "next": 0.0, "root_t": 0.0}
	duration = 70.0
	return true

func _tick_boar_family(dt: float) -> void:
	var sow: Animal = data.sow
	var C: Vector3 = data.C
	if not is_instance_valid(sow) or sow.dead or not sow.scripted:
		_release_if_close(9.0)
		return
	data.next = float(data.next) - dt
	if float(data.next) <= 0.0:
		data.next = _rng.randf_range(4.0, 7.0)
		if _rng.randf() < 0.55:
			go(sow, C + Vector3(_rng.randf_range(-6, 6), 0, _rng.randf_range(-6, 6)))
		else:
			stay(sow)
			data.root_t = 3.0
	if sow.state == &"wander" and arrived(sow):
		stay(sow)
		data.root_t = 3.0
	if float(data.root_t) > 0.0:
		data.root_t = float(data.root_t) - dt
		if fmod(t, 0.7) < dt * 1.2:
			sow.anim_event(&"eat")
			dust(sow.global_position - Vector3(-sin(sow.heading), 0, -cos(sow.heading)) * -0.8, Color(0.35, 0.27, 0.18))
	for i in (data.piglets as Array).size():
		var p: Animal = data.piglets[i]
		if is_instance_valid(p) and not p.dead and p.scripted:
			var off := Vector3(cos(i * 2.1 + t * 0.3), 0, sin(i * 2.1 + t * 0.3)) * 1.4
			go(p, sow.global_position + off)
	_release_if_close(9.0)

# ============================================================ 10. раки-отшельники у пустой раковины

func _setup_hermit_shell() -> bool:
	var S := _origin()
	var shell := _shell_mesh()
	prop(shell, S + Vector3(0, 0.05, 0))
	var crabs: Array[Animal] = []
	for i in 6:
		var a := _rng.randf() * TAU
		var c := animal(&"hermit_crab", S + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(3.0, 6.0), 0.6 + i * 0.12, 0.1)
		crabs.append(c)
	# очередь по размеру — большие ближе к раковине
	crabs.sort_custom(func(a: Animal, b: Animal) -> bool: return a.growth > b.growth)
	var line_dir := Vector3(1, 0, 0).rotated(Vector3.UP, _rng.randf() * TAU)
	for i in crabs.size():
		go(crabs[i], S + line_dir * (0.35 + i * 0.32))
	data = {"S": S, "crabs": crabs, "shell": shell, "line": line_dir}
	duration = 60.0
	return true

func _tick_hermit_shell(_dt: float) -> void:
	var S: Vector3 = data.S
	var crabs: Array = data.crabs
	for _c: Variant in crabs:
		if not is_instance_valid(_c):
			continue
		var c := _c as Animal
		if is_instance_valid(c) and c.state == &"wander" and arrived(c, 0.12):
			stay(c, S)
	if t > 40.0 and not data.get("swapped", false):
		data.swapped = true
		# большой забирает раковину, остальные по цепочке подтягиваются
		var big: Animal = crabs[0]
		if is_instance_valid(big):
			go(big, S, 0.12)
			var sh: Node3D = data.shell
			if is_instance_valid(sh):
				sh.visible = false
				var old := _shell_mesh()
				prop(old, big.global_position + Vector3(0, 0.04, 0.2), true)
		for i in range(1, crabs.size()):
			var c: Animal = crabs[i]
			if is_instance_valid(c):
				go(c, S + (data.line as Vector3) * (0.35 + (i - 1) * 0.32), 0.12)
	_release_if_close(1.5)

func _shell_mesh() -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 0.07
	cm.height = 0.16
	cm.radial_segments = 12
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.86, 0.78, 0.66)
	m.roughness = 0.45
	mi.material_override = m
	mi.rotation = Vector3(PI * 0.5, 0.0, 0.3)
	root.add_child(mi)
	return root

# ============================================================ 11. змея и саламандра

func _setup_snake_hunt() -> bool:
	var C := _origin()
	var sal := animal(&"salamander", C, 1.0, 0.05)
	var a := _rng.randf() * TAU
	var sn := animal(&"snake", C + Vector3(cos(a), 0, sin(a)) * 4.5, 1.0, 0.3)
	go(sn, C)
	go(sal, C + Vector3(cos(a + PI), 0, sin(a + PI)) * 1.2)
	data = {"sal": sal, "sn": sn, "struck": false}
	duration = 45.0
	return true

func _tick_snake_hunt(_dt: float) -> void:
	var sal: Animal = data.sal
	var sn: Animal = data.sn
	if not is_instance_valid(sn) or sn.dead or not sn.scripted:
		return
	if is_instance_valid(sal) and not sal.dead:
		go(sn, sal.global_position, 0.3)
		if sn.global_position.distance_to(sal.global_position) < 0.55 and not data.struck:
			data.struck = true
			data.strike_t = t
			sn.anim_event(&"attack")
			sn.state = &"warn"
			kill(sal)
	if data.struck and t - float(data.get("strike_t", t)) > 2.5 and is_instance_valid(sal):
		vanish(sal)          # проглотила
		stay(sn)
	_release_if_close(3.0)

# ============================================================ 12. черепаха откладывает яйца

func _setup_turtle_nesting() -> bool:
	var N := _origin()
	var W := director.find_water(N, 60.0)
	if W == Vector3.INF:
		if not forced:
			return false
		W = N + Vector3(0, 0, -16)
	var start := W + _dir_to(N, W) * 3.0
	var tu := animal(&"turtle", start, 1.0, 0.18)
	go(tu, N)
	data = {"N": N, "W": W, "tu": tu, "phase": 0, "dig": 0.0}
	duration = 150.0
	return true

func _tick_turtle_nesting(dt: float) -> void:
	var tu: Animal = data.tu
	var N: Vector3 = data.N
	if not is_instance_valid(tu) or tu.dead:
		done = true
		return
	match int(data.phase):
		0:
			if arrived(tu, 0.6) or t > 90.0:
				stay(tu)
				data.phase = 1
		1:
			data.dig = float(data.dig) + dt
			if fmod(t, 0.9) < dt * 1.2:
				dust(tu.global_position - Vector3(-sin(tu.heading), 0, -cos(tu.heading)) * 0.5, Color(0.8, 0.72, 0.55))
			if float(data.dig) > 14.0:
				# гнездо остаётся в мире (следы к нему рисует WorldHints)
				var nest := TurtleNest.new()
				nest.eggs = _rng.randi_range(5, 9)
				nest.fauna = Fauna.instance()
				var root := get_tree().current_scene if get_tree().current_scene else director
				root.add_child(nest)
				nest.global_position = _gp(N)
				nest.set_meta(&"from_water", data.W)
				data.phase = 2
				go(tu, data.W)
		2:
			if _g(tu.global_position.x, tu.global_position.z) < _wl() - 0.2 or arrived(tu, 1.0):
				vanish(tu)
				done = true

# ============================================================ 13. чайки над косяком рыбы

func _setup_gulls_fish() -> bool:
	var C := _origin()
	var fl := flock_of(&"gull", Vector3(C.x, _wl() + 6.0, C.z), 7, 4.0)
	data = {"C": C, "fl": fl, "next_dive": 2.0, "boil": 0.0}
	duration = 45.0
	return true

func _tick_gulls_fish(dt: float) -> void:
	var C: Vector3 = data.C
	var fl: Dictionary = data.fl
	fl.pos = _ring(C, 5.0, t * 0.9, _wl() + 5.5)
	# «кипящая» вода: мелкие всплески косяка
	data.boil = float(data.boil) - dt
	if float(data.boil) <= 0.0:
		data.boil = _rng.randf_range(0.25, 0.6)
		splash(C + Vector3(_rng.randf_range(-3, 3), 0, _rng.randf_range(-3, 3)), 0.35)
	# пике за рыбой
	data.next_dive = float(data.next_dive) - dt
	var members: Array = fl.members
	if float(data.next_dive) <= 0.0 and not members.is_empty():
		data.next_dive = _rng.randf_range(1.5, 3.0)
		var g := members[_rng.randi() % members.size()] as Animal
		if is_instance_valid(g):
			g.flock_offset.y = -5.0
			g.set_meta(&"dive_t", t)
	for _g: Variant in members:
		if not is_instance_valid(_g):
			continue
		var g := _g as Animal
		if is_instance_valid(g) and g.has_meta(&"dive_t"):
			if g.global_position.y < _wl() + 0.6 and not g.has_meta(&"splashed"):
				g.set_meta(&"splashed", true)
				splash(g.global_position, 0.7)
			if t - float(g.get_meta(&"dive_t")) > 1.6:
				g.flock_offset.y = _rng.randf_range(-0.5, 1.0)
				g.remove_meta(&"dive_t")
				if g.has_meta(&"splashed"):
					g.remove_meta(&"splashed")

# ============================================================ 14. погоня в воздухе

func _setup_air_chase() -> bool:
	var C := _origin()
	var land := director.find_land(C, 140.0)
	var along := _dir_to(C, land).rotated(Vector3.UP, PI * 0.5) if land != Vector3.INF else Vector3(1, 0, 0)
	var y := _wl() + 9.0
	var lead := flock_of(&"gull", Vector3(C.x, y, C.z) - along * 25.0, 1)
	var chaser := flock_of(&"gull", Vector3(C.x, y + 1.5, C.z) - along * 32.0, 1)
	var fish := fish_model()
	prop(fish, (lead.pos as Vector3) + Vector3(0, -0.2, 0))
	data = {"lead": lead, "chaser": chaser, "along": along, "fish": fish, "dropped": false, "vy": 0.0}
	duration = 22.0
	return true

func _tick_air_chase(dt: float) -> void:
	var lead: Dictionary = data.lead
	var chaser: Dictionary = data.chaser
	var along: Vector3 = data.along
	var zig := along.rotated(Vector3.UP, PI * 0.5) * sin(t * 2.3) * 5.0
	lead.pos = (lead.pos as Vector3) + (along * 9.0 + zig) * dt
	chaser.pos = (chaser.pos as Vector3).move_toward(lead.pos as Vector3 + Vector3(0, 0.6, 0), 10.5 * dt)
	var fish: Node3D = data.fish
	var lm := (lead.members as Array)[0] as Animal
	if not is_instance_valid(fish):
		return
	if not data.dropped:
		if is_instance_valid(lm):
			fish.global_position = lm.global_position + Vector3(0, -0.15, 0)
		if t > 8.5:
			data.dropped = true
	else:
		data.vy = float(data.vy) - 9.8 * dt
		fish.global_position += Vector3(along.x * 3.0 * dt, float(data.vy) * dt, along.z * 3.0 * dt)
		if fish.global_position.y < _wl():
			splash(fish.global_position, 0.6)
			fish.queue_free()
			# обе разлетаются
			chaser.pos = (chaser.pos as Vector3) + Vector3(0, 3, 0)

# ============================================================ 15. варан патрулирует берег

func _setup_monitor_shore() -> bool:
	var C := _origin()
	var w := director.find_water(C, 40.0)
	var along := _dir_to(C, w).rotated(Vector3.UP, PI * 0.5) if w != Vector3.INF else Vector3(1, 0, 0)
	var mon := animal(&"monitor", C - along * 12.0, 1.0, 0.6)
	go(mon, C + along * 12.0)
	data = {"mon": mon, "C": C, "along": along, "tongue": 0.0, "leg": 0}
	duration = 55.0
	return true

func _tick_monitor_shore(dt: float) -> void:
	var mon: Animal = data.mon
	if not is_instance_valid(mon) or mon.dead or not mon.scripted:
		return
	if arrived(mon, 1.0):
		data.leg = int(data.leg) + 1
		var C: Vector3 = data.C
		var along: Vector3 = data.along
		if int(data.leg) == 1:
			stay(mon)
			data.pause = t
		else:
			go(mon, C - along * 14.0 if int(data.leg) % 2 == 0 else C + along * 14.0)
	if mon.state == &"idle" and t - float(data.get("pause", 0.0)) > 5.0:
		var C2: Vector3 = data.C
		go(mon, C2 - (data.along as Vector3) * 14.0)
	data.tongue = float(data.tongue) - dt
	if float(data.tongue) <= 0.0:
		data.tongue = _rng.randf_range(1.5, 3.5)
		mon.anim_event(&"threat")    # «пробует воздух»
	_release_if_close(6.0)

# ============================================================ 16. крабы на обнажившемся рифе

func _setup_crabs_low_tide() -> bool:
	var C := _origin()
	var W := director.find_water(C, 40.0)
	var to_sea := _dir_to(C, W) if W != Vector3.INF else Vector3(0, 0, -1)
	var crabs: Array[Animal] = []
	for i in 14:
		var p := C + to_sea * _rng.randf_range(0.0, 10.0) + to_sea.rotated(Vector3.UP, PI * 0.5) * _rng.randf_range(-8, 8)
		var c := animal(&"crab", p, _rng.randf_range(0.6, 1.0), 0.35)
		c.set_meta(&"next", _rng.randf_range(0.0, 3.0))
		crabs.append(c)
	data = {"C": C, "crabs": crabs, "to_sea": to_sea}
	duration = 70.0
	return true

func _tick_crabs_low_tide(dt: float) -> void:
	var C: Vector3 = data.C
	for _c: Variant in data.crabs:
		if not is_instance_valid(_c):
			continue
		var c := _c as Animal
		if not is_instance_valid(c) or c.dead or not c.scripted:
			continue
		var nx := float(c.get_meta(&"next", 0.0)) - dt
		if nx <= 0.0:
			nx = _rng.randf_range(2.0, 5.0)
			if _rng.randf() < 0.6:
				go(c, c.global_position + Vector3(_rng.randf_range(-1.5, 1.5), 0, _rng.randf_range(-1.5, 1.5)))
			else:
				stay(c)
				c.anim_event(&"eat")       # клешни к «рту» — кормятся на мокром песке
		c.set_meta(&"next", nx)
		if _g(c.global_position.x, c.global_position.z) < _wl() - 0.05:
			go(c, C)
	# прилив поднимается — уходят в воду
	if director and not director.low_tide() and t > 10.0 and not forced:
		for _c: Variant in data.crabs:
			if not is_instance_valid(_c):
				continue
			var c := _c as Animal
			if is_instance_valid(c) and c.scripted:
				go(c, c.global_position + (data.to_sea as Vector3) * 12.0, 0.6)
	_release_if_close(3.0)
