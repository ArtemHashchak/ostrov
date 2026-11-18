class_name ReptileAnim
extends RefCounted
## Процедурная анимация рептилий: змея, крокодил, игуана, варан, черепаха.
## Подключается через meta "anim" модели (см. Animal.anim_ctrl): setup/animate/animate_dead/on_event.
## Тело змеи, крокодила и ящериц гнётся по «позвоночнику» из 16 точек (шейдер reptile_skin):
## точки берутся со следа головы — тело ползёт ровно по пути головы (змея извивается, хвост
## повторяет повороты). Лапы и глаза переставляются вслед за позвоночником, походка — диагональная
## с неподвижной опорой стопы (амплитуда шага подобрана к скорости). Черепаха — ласты и голова.
## Детализация: lod 0–1 — полная, lod >= 2 — поза замирает.

const SKIN := preload("res://scripts/fauna/shaders/reptile_skin.gdshader")
const N := 16

var a: Animal
var model: Node3D
var mat: ShaderMaterial
var sp: StringName
var L := 1.0                 # длина модели (без роста)
var z0 := -0.5               # нос в покое
var z1 := 0.5                # кончик хвоста в покое
var ys := 0.0                # высота оси тела в покое
var spine := true
var reach := 0.12            # вынос стопы вбок (для амплитуды шага)
var stride := 0.3            # длина шага (ед. модели)
var amp_cap := 0.7           # предел размаха лапы (рад)

var pts := PackedVector3Array()        # текущий позвоночник (пространство модели)
var trail := PackedVector3Array()      # след головы (мир), [0] — голова
var travelled := 0.0
var gait := 0.0
var move_w := 0.0
var swim_ph := 0.0
var coil_w := 0.0
var idle_t := 0.0
var strike_t := -1.0
var roll_t := -1.0
var hurt_t := -1.0
var jaw := 0.0
var jaw_hold := 0.0
var tongue := 0.0
var tongue_t := -1.0
var tongue_next := 1.5
var bob_t := -1.0
var bob_next := 5.0
var _pitch := 0.0             # черепаха: добавка к тангажу модели
var head := Vector3.ZERO      # черепаха: (кивок, поворот, выдвижение)
var _kids: Array = []         # [Node3D, Transform3D покоя, is_leg, leg_index]
var _rng := RandomNumberGenerator.new()

# ============================== интерфейс ==============================

func setup(an: Animal) -> void:
	a = an
	model = an._model
	mat = an._mat
	sp = an.species
	_rng.seed = an.get_instance_id() ^ 0x5eed
	tongue_next = _rng.randf_range(0.5, 3.0)
	bob_next = _rng.randf_range(2.0, 7.0)
	L = float(model.get_meta(&"length", 1.0))
	match sp:
		&"snake":
			z0 = -L * 0.5; z1 = L * 0.5; ys = 0.03
		&"croc":
			z0 = -1.7; z1 = 1.7; ys = 0.22; reach = 0.26; stride = 0.6; amp_cap = 0.5
		&"iguana", &"monitor":
			var sc := L / 1.25
			z0 = -0.45 * L; z1 = 0.55 * L; ys = 0.08 * sc; reach = 0.125 * sc; stride = 0.36 * L
		_:
			spine = false
	_swap_shader()
	if mat:
		mat.set_shader_parameter(&"spine_on", 1.0 if spine else 0.0)
		mat.set_shader_parameter(&"spine_z0", z0)
		mat.set_shader_parameter(&"spine_z1", z1)
		mat.set_shader_parameter(&"spine_y", ys)
		mat.set_shader_parameter(&"bend_amp", 0.0)
		match sp:
			&"snake":
				mat.set_shader_parameter(&"tongue_z", z0 - 0.003)
			&"monitor":
				mat.set_shader_parameter(&"tongue_z", z0 - 0.003)
			&"croc":
				mat.set_shader_parameter(&"jaw_hinge", Vector2(0.215, -1.0))
				mat.set_shader_parameter(&"jaw_slope", 0.05)
				mat.set_shader_parameter(&"jaw_y_off", -0.004)
			&"turtle":
				mat.set_shader_parameter(&"head_on", 1.0)
				mat.set_shader_parameter(&"neck_pivot", Vector3(0.0, 0.15, -0.42))
	pts.resize(N)
	for j in N:
		pts[j] = Vector3(0.0, ys, lerpf(z0, z1, float(j) / (N - 1)))
	var legs: Array = model.get_meta(&"legs", [])
	for c in model.get_children():
		if c is Node3D and c.name != &"Body":
			var li := legs.find(c)
			_kids.append([c, (c as Node3D).transform, li >= 0, li])
	_push()

func animate(_an: Animal, dt: float) -> void:
	if a == null or dt <= 0.0:
		return
	if a.lod >= 2:
		_water_float()
		return
	var moving := a.speed > 0.06
	move_w = move_toward(move_w, clampf(a.speed / maxf(float(a.cfg["walk"]), 0.1), 0.0, 1.0) if moving else 0.0, dt * 4.0)
	idle_t = 0.0 if moving or a.state in [&"warn", &"attack", &"chase", &"flee"] else idle_t + dt
	if strike_t >= 0.0:
		strike_t += dt
		if strike_t > 0.45: strike_t = -1.0
	if hurt_t >= 0.0:
		hurt_t += dt
		if hurt_t > 0.4: hurt_t = -1.0
	match sp:
		&"snake": _snake(dt)
		&"croc": _croc(dt)
		&"iguana", &"monitor": _lizard(dt)
		&"turtle": _turtle(dt)
	_tongue(dt)
	_push()

func animate_dead(_an: Animal, _dt: float) -> bool:
	if mat:
		mat.set_shader_parameter(&"tongue_out", 0.0)
		if sp == &"croc":
			mat.set_shader_parameter(&"jaw_open", 0.18)
	return false

func on_event(_an: Animal, ev: StringName) -> void:
	match ev:
		&"attack":
			strike_t = 0.0
			if sp == &"croc":
				jaw = 0.0
				jaw_hold = 0.35
				if a and a._in_water():
					roll_t = 0.0
		&"hurt":
			hurt_t = 0.0
		&"threat":
			tongue_t = 0.0

# ============================== позвоночник ==============================

func _swap_shader() -> void:
	if mat == null:
		return
	var keep := {}
	for u: Dictionary in mat.shader.get_shader_uniform_list():
		var nm: StringName = u["name"]
		keep[nm] = mat.get_shader_parameter(nm)
	mat.shader = SKIN
	for nm: StringName in keep:
		if keep[nm] != null:
			mat.set_shader_parameter(nm, keep[nm])

## Голова в пространстве модели (для следа).
func _head_local(lat: float) -> Vector3:
	return Vector3(lat, ys, z0)

func _seg_world() -> float:
	return (z1 - z0) / float(N - 1) * maxf(a.growth, 0.05)

## Обновить след головы и получить из него позвоночник.
func _trail_follow(lat: float) -> void:
	var hw := model.to_global(_head_local(lat))
	var seg := _seg_world()
	if trail.size() < 2 or hw.distance_to(trail[0]) > (z1 - z0) * a.growth * 0.6:
		_trail_from_pts()
		hw = model.to_global(_head_local(lat))
	if hw.distance_to(trail[1]) >= seg * 0.5:
		trail.insert(0, hw)
	else:
		trail[0] = hw
	# выборка по длине дуги
	var need := 0.0
	var acc := 0.0
	var j := 0
	var out := PackedVector3Array()
	out.resize(N)
	var k := 1
	while k < trail.size() and j < N:
		var p0 := trail[k - 1]
		var p1 := trail[k]
		var l := p0.distance_to(p1)
		while j < N and acc + l >= need:
			out[j] = p0.lerp(p1, (need - acc) / maxf(l, 1e-5))
			j += 1
			need += seg
		acc += l
		k += 1
	if j < N:
		var last := trail[trail.size() - 1]
		var dir := (last - trail[trail.size() - 2]).normalized() if trail.size() > 1 else model.global_transform.basis.z.normalized()
		if dir.length() < 0.5:
			dir = model.global_transform.basis.z.normalized()
		while j < N:
			out[j] = last + dir * (need - acc)
			j += 1
			need += seg
	if k + 2 < trail.size():
		trail.resize(k + 2)
	for i in N:
		pts[i] = model.to_local(out[i])

func _trail_from_pts() -> void:
	trail.resize(N)
	for i in N:
		trail[i] = model.to_global(pts[i])

## Кадр позвоночника на оси покоя z (как в шейдере): [P, X, Y, T].
func _frame(z: float) -> Array:
	var u := clampf((z - z0) / (z1 - z0), 0.0, 1.0) * (N - 1)
	var i := mini(int(floor(u)), N - 2)
	var f := u - i
	var p0 := pts[i]
	var p1 := pts[i + 1]
	var t0 := p1 - p0
	var ta := (p0 - pts[i - 1]) if i > 0 else t0
	var tb := (pts[i + 2] - p1) if i < N - 2 else t0
	var T := ((ta + t0).normalized().lerp((t0 + tb).normalized(), f) + Vector3(0, 0, 1e-5)).normalized()
	var X := (Vector3.UP.cross(T) + Vector3(1e-5, 0, 0)).normalized()
	var Y := T.cross(X)
	return [p0.lerp(p1, f), X, Y, T]

## Лапы и глаза — вслед за позвоночником (+ поворот походки для лап).
func _place_kids(leg_rot: Array) -> void:
	for kd: Array in _kids:
		var n := kd[0] as Node3D
		if not is_instance_valid(n):
			continue
		var rt: Transform3D = kd[1]
		if spine:
			var fr := _frame(rt.origin.z)
			var X: Vector3 = fr[1]
			var Y: Vector3 = fr[2]
			var T: Vector3 = fr[3]
			var pos: Vector3 = fr[0] + X * rt.origin.x + Y * (rt.origin.y - ys)
			var b := Basis(X, Y, T) * rt.basis
			if kd[2] and int(kd[3]) < leg_rot.size():
				b = b * (leg_rot[int(kd[3])] as Basis)
			n.transform = Transform3D(b, pos)
		elif kd[2] and int(kd[3]) < leg_rot.size():
			n.transform = Transform3D(rt.basis * (leg_rot[int(kd[3])] as Basis), rt.origin)

func _push() -> void:
	if mat == null:
		return
	if spine:
		mat.set_shader_parameter(&"spine_pts", pts)
	mat.set_shader_parameter(&"tongue_out", tongue)
	if sp == &"croc":
		mat.set_shader_parameter(&"jaw_open", jaw)
	if sp == &"turtle":
		mat.set_shader_parameter(&"head_rot", Vector3(head.x, head.y, 0.0))
		mat.set_shader_parameter(&"head_ext", head.z)

# ============================== походка ==============================

## Повороты 4 лап: диагональная походка с опорой стопы. side: левая −1, правая +1.
func _gait_legs(dt: float, freq_cap: float, lift_amt: float) -> Array:
	var legs: Array = model.get_meta(&"legs", [])
	var res: Array = []
	var stride_w := stride * maxf(a.growth, 0.05)
	if a.speed > 0.05:
		gait += minf(a.speed / maxf(stride_w, 0.01), freq_cap) * dt
	var amp := clampf(stride * 0.5 / maxf(reach, 0.01), 0.25, amp_cap)
	for i in legs.size():
		var side := -1.0 if i % 2 == 0 else 1.0
		var off := 0.0 if (i == 0 or i == 3) else 0.5
		var p := fposmod(gait + off, 1.0)
		var s := 0.0
		var lift := 0.0
		if p < 0.6:
			s = 1.0 - 2.0 * p / 0.6
		else:
			var q := (p - 0.6) / 0.4
			s = -1.0 + 2.0 * smoothstep(0.0, 1.0, q)
			lift = sin(PI * q)
		var ry := side * s * amp * move_w
		var rz := side * lift * lift_amt * move_w
		res.append(Basis.from_euler(Vector3(0.0, ry, rz)))
	return res

# ============================== змея ==============================

func _coil_pts() -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(N)
	var span := z1 - z0
	for j in N:
		var s := float(j) / (N - 1)
		var r := (0.045 + 0.2 * s) * span / 1.6
		var th := 1.2 + s * 3.3 * PI
		var lift := 0.05 * span / 1.6 * pow(clampf(1.0 - s / 0.18, 0.0, 1.0), 1.5)
		out[j] = Vector3(cos(th) * r, ys + lift, 0.05 + sin(th) * r)
	return out

func _snake(dt: float) -> void:
	var water := _water_float()
	var moving := a.speed > 0.06
	# свернуться кольцом после долгого покоя, развернуться по своему же кольцу при старте
	if moving and coil_w > 0.4:
		var cp := _coil_pts()
		for j in N:
			pts[j] = pts[j].lerp(cp[j], coil_w)
		_trail_from_pts()
		coil_w = 0.0
	var want_coil := 1.0 if (idle_t > 2.5 and not water and a.state in [&"idle", &"wander", &"stay"]) else 0.0
	coil_w = move_toward(coil_w, want_coil, dt * 0.5)
	travelled += a.speed * dt
	var k := TAU / (0.42 * (z1 - z0) * maxf(a.growth, 0.05))
	var amp := (0.085 if not water else 0.12) * (z1 - z0) / 1.6
	var lat := sin(travelled * k) * amp * clampf(a.speed * 3.0, 0.0, 1.0)
	_trail_follow(lat)
	if coil_w > 0.001:
		var cp := _coil_pts()
		var e := smoothstep(0.0, 1.0, coil_w)
		for j in N:
			pts[j] = pts[j].lerp(cp[j], e)
	# стойка угрозы: передняя треть поднята S-образно, покачивается
	var raise := 1.0 if a.state in [&"warn", &"attack"] else 0.0
	var span := z1 - z0
	var t := a._anim_t
	for j in 7:
		var f := 1.0 - float(j) / 6.0
		var lift := raise * 0.16 * span * pow(f, 1.6)
		var p := pts[j]
		p.y += lift
		p.z += lift * 0.55
		p.x += raise * sin(t * 2.1) * 0.025 * span * f
		# бросок
		if strike_t >= 0.0:
			var th := sin(PI * clampf(strike_t / 0.3, 0.0, 1.0))
			p.z -= th * 0.28 * span * pow(f, 1.3)
			p.y -= th * lift * 0.5
		if hurt_t >= 0.0:
			p.x += sin(hurt_t * 40.0) * 0.03 * span * (1.0 - hurt_t / 0.4)
		pts[j] = p
	_place_kids([])

# ============================== крокодил ==============================

func _croc(dt: float) -> void:
	var water := _in_deep_water()
	travelled += a.speed * dt
	swim_ph += dt * (1.2 + a.speed * (1.1 if water else 0.6))
	var lat := 0.0
	if water:
		lat = sin(travelled * TAU / (0.9 * (z1 - z0) * a.growth)) * 0.04 * clampf(a.speed, 0.0, 1.0)
	_trail_follow(lat)
	# хвост: бегущая волна (в воде — главный движитель), на суше лёгкое покачивание
	var tail_a := (0.06 + 0.2 * clampf(a.speed / 3.0, 0.0, 1.0)) if water else (0.02 + 0.06 * move_w)
	for j in range(5, N):
		var s := float(j - 5) / float(N - 6)
		var p := pts[j]
		p.x += sin(swim_ph * 2.6 - s * 4.0) * tail_a * pow(s, 1.3)
		if not water:
			p.y -= s * s * 0.13          # хвост лежит на земле
		pts[j] = p
	if hurt_t >= 0.0:
		for j in N:
			pts[j].x += sin(hurt_t * 30.0) * 0.05 * (1.0 - hurt_t / 0.4)
	# высокий ход на суше: тело поднято, лапы под туловищем; в покое — лёжа на брюхе
	var high := 0.0 if water else move_w
	var legs := _gait_legs(dt, 2.2, 0.35)
	for i in legs.size():
		var side := -1.0 if i % 2 == 0 else 1.0
		var b: Basis = legs[i]
		if water:
			# лапы прижаты к бокам и назад
			b = Basis.from_euler(Vector3(0.0, -side * 1.05, -side * 0.15))
		else:
			# ход: лапы под туловищем; покой: раскинуты в стороны, лежит на брюхе
			b = Basis.from_euler(Vector3(0.0, side * 0.25 * (1.0 - high), -side * 0.36 * high + side * 0.32 * (1.0 - high))) * b
		legs[i] = b
	var y_off := 0.11 * high - 0.035 * (1.0 - high) * (0.0 if water else 1.0)
	if water and a.state == &"ambush":
		y_off = sin(a._anim_t * 0.7) * 0.015 - 0.02
	model.position.y = lerpf(model.position.y, y_off, clampf(dt * 5.0, 0.0, 1.0))
	# пасть: приоткрыта на солнце, раскрыта перед броском, захлопывается при укусе
	var want := 0.0
	if a.state in [&"attack", &"chase"] and a.target and a.global_position.distance_to(a.target.global_position) < 5.0:
		want = 0.5
	elif not water and idle_t > 4.0:
		want = 0.3    # греется с открытой пастью
	if jaw_hold > 0.0:
		jaw_hold -= dt
		jaw = move_toward(jaw, 0.0, dt * 12.0)
	else:
		jaw = move_toward(jaw, want, dt * (1.6 if want > jaw else 3.0))
	# смертельный кувырок в воде после укуса
	if roll_t >= 0.0:
		roll_t += dt
		var r := clampf(roll_t / 1.4, 0.0, 1.0)
		model.rotation.z = TAU * 2.0 * (r * r * (3.0 - 2.0 * r))
		if roll_t >= 1.4:
			roll_t = -1.0
			model.rotation.z = 0.0
	_place_kids(legs)

# ============================== ящерицы ==============================

func _lizard(dt: float) -> void:
	_trail_follow(0.0)
	var legs := _gait_legs(dt, 4.5, 0.5)
	# S-изгиб туловища в такт шагу + хвост бегущей волной, хвост волочится по земле
	var span := z1 - z0
	var ph := gait * TAU
	var s_hip := 0.5
	for j in N:
		var s := float(j) / (N - 1)
		var p := pts[j]
		p.x += sin(ph - s * TAU * 0.85) * 0.05 * span * (0.25 + s * 1.1) * move_w
		if s > s_hip:
			p.y -= (s - s_hip) / (1.0 - s_hip) * ys * 0.8
		if hurt_t >= 0.0:
			p.x += sin(hurt_t * 35.0) * 0.03 * span * (1.0 - hurt_t / 0.4)
		pts[j] = p
	# игуана — кивки головой; варан — покачивает головой на ходу
	if sp == &"iguana":
		bob_next -= dt
		if bob_next <= 0.0 and move_w < 0.2:
			bob_t = 0.0
			bob_next = _rng.randf_range(4.0, 9.0)
		if a.state == &"flee":
			bob_t = -1.0
	if bob_t >= 0.0:
		bob_t += dt
		var b := absf(sin(bob_t * TAU * 2.4)) * (1.0 - bob_t / 1.3)
		for j in 3:
			pts[j].y += b * 0.035 * span / 1.25 * (1.0 - j / 3.0)
		if bob_t > 1.3:
			bob_t = -1.0
	# приподнятая передняя часть в покое (опирается на передние лапы)
	var prop := (1.0 - move_w) * 0.018 * span
	for j in 6:
		pts[j].y += prop * (1.0 - j / 6.0)
	if sp == &"monitor":
		for j in 3:
			pts[j].x += sin(a._anim_t * 3.0) * 0.012 * span * move_w * (1.0 - j / 3.0)
	model.position.y = lerpf(model.position.y, 0.0, clampf(dt * 5.0, 0.0, 1.0))
	_place_kids(legs)

# ============================== черепаха ==============================

func _turtle(dt: float) -> void:
	var legs_n: Array = model.get_meta(&"legs", [])
	var res: Array = []
	var water := _in_deep_water()
	var t := a._anim_t
	var hx := 0.0
	var hy := sin(t * 0.37) * 0.25 * (1.0 if idle_t > 1.0 else 0.3)
	var hz := 0.0
	var body_z := 0.0
	var body_y := 0.0
	var pitch := 0.0
	if a.state == &"stay":
		# спряталась: голова втянута, ласты поджаты
		hz = -0.1; hx = 0.25; hy = 0.0
		for i in legs_n.size():
			var side := -1.0 if i % 2 == 0 else 1.0
			res.append(Basis.from_euler(Vector3(0.0, -side * (0.55 if i < 2 else 0.35), 0.0)))
	elif a.state == &"nest":
		# роет ямку задними ластами по очереди, нос приподнят
		swim_ph += dt * 3.2
		pitch = 0.09
		hx = -0.1
		for i in legs_n.size():
			var side := -1.0 if i % 2 == 0 else 1.0
			if i < 2:
				res.append(Basis.from_euler(Vector3(0.0, side * 0.2, -side * 0.05)))
			else:
				var o := swim_ph + (0.0 if side < 0 else PI)
				var sc := maxf(0.0, sin(o))
				res.append(Basis.from_euler(Vector3(0.0, -side * (0.2 + 0.6 * sc), side * (0.15 + 0.5 * sc))))
	elif water:
		# плывёт: передние ласты машут как крылья, задние рулят
		swim_ph += dt * (1.4 + a.speed * 1.6)
		var f := swim_ph
		hz = 0.03
		pitch = sin(f) * 0.03
		for i in legs_n.size():
			var side := -1.0 if i % 2 == 0 else 1.0
			if i < 2:
				var up := sin(f) * 0.8
				var sweep := cos(f) * 0.4
				res.append(Basis.from_euler(Vector3(cos(f) * 0.35, side * (0.15 + sweep), side * up)))
			else:
				res.append(Basis.from_euler(Vector3(0.0, -side * (0.45 + sin(f * 0.5) * 0.15), side * 0.1)))
	else:
		# ползёт по песку: передние ласты гребут вместе, задние толкают поочерёдно, тело рывками
		if a.speed > 0.03:
			swim_ph += dt * minf(a.speed / 0.16, 2.2)
		var p := fposmod(swim_ph, 1.0)
		var push := 0.0
		for i in legs_n.size():
			var side := -1.0 if i % 2 == 0 else 1.0
			if i < 2:
				var ry := 0.0
				var rz := 0.0
				if p < 0.6:
					var q := p / 0.6
					ry = lerpf(0.55, -0.35, q)
					push = sin(PI * q)
				else:
					var q2 := (p - 0.6) / 0.4
					ry = lerpf(-0.35, 0.55, smoothstep(0.0, 1.0, q2))
					rz = sin(PI * q2) * 0.35
				res.append(Basis.from_euler(Vector3(0.0, side * ry * move_w, side * rz * move_w)))
			else:
				var o := fposmod(p + (0.25 if side < 0 else 0.75), 1.0)
				res.append(Basis.from_euler(Vector3(0.0, -side * (0.25 + 0.2 * sin(o * TAU)) * move_w, side * 0.06)))
		body_z = -push * 0.035 * move_w
		body_y = push * 0.02 * move_w
		hx = -push * 0.12 * move_w
		hz = 0.02 * move_w
	head = Vector3(lerpf(head.x, hx, clampf(dt * 4.0, 0.0, 1.0)), lerpf(head.y, hy, clampf(dt * 3.0, 0.0, 1.0)),
		lerpf(head.z, hz, clampf(dt * (8.0 if hz < head.z else 3.0), 0.0, 1.0)))
	if hurt_t >= 0.0:
		head.z = -0.1
	model.position.z = lerpf(model.position.z, body_z, clampf(dt * 10.0, 0.0, 1.0))
	model.position.y = lerpf(model.position.y, body_y, clampf(dt * 10.0, 0.0, 1.0))
	var pp := lerpf(_pitch, pitch, clampf(dt * 4.0, 0.0, 1.0))
	model.rotation.x += pp - _pitch
	_pitch = pp
	# глаза — вслед за головой (та же формула, что в шейдере)
	var R := Basis(Vector3.UP, head.y) * Basis(Vector3.RIGHT, head.x)
	var piv := Vector3(0.0, 0.15, -0.42)
	for kd: Array in _kids:
		var n := kd[0] as Node3D
		if kd[2] or not is_instance_valid(n):
			continue
		var rt: Transform3D = kd[1]
		n.position = piv + R * (rt.origin - piv) + Vector3(0, 0, -head.z)
	_place_kids(res)

# ============================== язык, вода ==============================

func _tongue(dt: float) -> void:
	if sp != &"snake" and sp != &"monitor":
		return
	if tongue_t < 0.0:
		tongue_next -= dt * (2.5 if a.state in [&"warn", &"chase", &"attack"] else 1.0)
		if tongue_next <= 0.0:
			tongue_t = 0.0
			tongue_next = _rng.randf_range(1.2, 3.5)
	if tongue_t >= 0.0:
		tongue_t += dt
		tongue = absf(sin(tongue_t * TAU * 2.2)) if tongue_t < 0.7 else 0.0
		if tongue_t > 0.7:
			tongue_t = -1.0
	else:
		tongue = 0.0
	if a.lod >= 1:
		tongue = 0.0

func _in_deep_water() -> bool:
	var p := a.global_position
	return Fauna.ground_y_at(a, p.x, p.z) < Fauna.water_y(a) - 0.25

## Змея держится у поверхности воды. true — в воде.
func _water_float() -> bool:
	if sp != &"snake":
		return false
	var p := a.global_position
	var wl := Fauna.water_y(a)
	var g := Fauna.ground_y_at(a, p.x, p.z)
	if g < wl - 0.05:
		model.position.y = lerpf(model.position.y, (wl - ys * 0.6 * a.growth) - p.y, 0.3)
		return true
	model.position.y = lerpf(model.position.y, 0.0, 0.3)
	return false
