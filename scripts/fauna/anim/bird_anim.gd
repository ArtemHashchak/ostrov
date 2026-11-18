extends RefCounted
## Анимация птиц (попугай, чайка) и летучей мыши на ригах CreatureRigs.
## Крыло: плечо (взмах, отвод назад) → кисть (запаздывание, складывание на подъёме).
## Режимы: машет / планирует / взлёт / посадка / сидит (крылья сложены, голова вертится рывками,
## чистит перья) / летучая мышь висит вниз головой (днём на дереве).

func animate(a: Animal, dt: float) -> void:
	var rig: Dictionary = a._model.get_meta(&"rig", {})
	if rig.is_empty():
		return
	var st := a.anim_state
	if st.is_empty():
		_init_state(a, st)
	var lod := FaunaAnim.lod_of(a)
	var t := float(st["t"]) + dt
	st["t"] = t
	var y := a.global_position.y
	var vy := (y - float(st["py"])) / maxf(dt, 0.001)
	st["py"] = y
	st["vy"] = FaunaAnim.damp(float(st["vy"]), clampf(vy, -8.0, 8.0), 6.0, dt)
	var bat := a.species == &"bat"
	var mode := _mode(a, st)
	if lod == 2:
		# далеко: только взмах плечом (2 поворота на крыло)
		if mode == &"fly":
			var ph := float(st["ph"]) + dt * _freq(a) * TAU
			st["ph"] = ph
			for w: Dictionary in rig["wings"]:
				(w["shoulder"] as Node3D).rotation = Vector3(0, 0, float(w["side"]) * sin(ph) * 0.8)
		elif not st.get("posed_far", false):
			_fold(rig, 1.0, bat, st, 0.0)
			st["posed_far"] = true
		return
	st["posed_far"] = false
	if bat:
		_bat(a, rig, st, dt, lod, mode)
	else:
		_bird(a, rig, st, dt, lod, mode)

func animate_dead(a: Animal, _dt: float) -> void:
	var rig: Dictionary = a._model.get_meta(&"rig", {})
	if rig.is_empty():
		return
	for w: Dictionary in rig["wings"]:
		var s := float(w["side"])
		(w["shoulder"] as Node3D).rotation = Vector3(0.0, -s * 0.5, -s * 0.25)
		(w["hand"] as Node3D).rotation = Vector3(0.0, s * 0.4, 0.0)
	var body: Node3D = rig["body"]
	body.rotation = Vector3.ZERO
	body.position = Vector3.ZERO
	var neck: Node3D = rig.get("neck")
	if neck:
		neck.rotation = Vector3(-0.4, 0.6, 0.0)

func _init_state(a: Animal, st: Dictionary) -> void:
	st["t"] = randf() * 10.0
	st["ph"] = randf() * TAU
	st["py"] = a.global_position.y
	st["vy"] = 0.0
	st["fold"] = 1.0 if a.state != &"fly" else 0.0
	st["glide"] = 0.0
	st["look_t"] = 0.0
	st["look_y"] = 0.0
	st["look_x"] = 0.0
	st["preen"] = 0.0
	st["preen_cd"] = randf_range(5.0, 12.0)
	st["ruffle"] = 0.0
	st["pitch"] = 0.0
	st["land"] = 0.0
	st["take"] = 0.0

func _mode(a: Animal, st: Dictionary) -> StringName:
	if a.state == &"roost":
		return &"roost"
	if a.state == &"perch" or (a.tamed and a.species == &"parrot" and a.state != &"fly"):
		return &"perch"
	return &"fly"

func _freq(a: Animal) -> float:
	match a.species:
		&"bat":
			return 9.0
		&"gull":
			return 2.6
	return 7.0

## Поза крыла при взмахе: ph — фаза, amp — размах, fold_up — складывание кисти на подъёме.
func _flap_wing(w: Dictionary, ph: float, amp: float, dihedral: float, fold_up: float, sweep: float) -> void:
	var s := float(w["side"])
	# вниз быстрее, чем вверх: искажённая фаза
	var p := ph + 0.35 * sin(ph)
	var up := sin(p)
	var rising := maxf(0.0, cos(p))
	(w["shoulder"] as Node3D).rotation = Vector3(0.0, -s * (sweep + 0.18 * rising * fold_up), s * (amp * up + dihedral))
	(w["hand"] as Node3D).rotation = Vector3(0.0, -s * 0.65 * rising * fold_up, s * amp * 0.55 * sin(p - 0.8))

func _glide_wing(w: Dictionary, t: float, dihedral: float) -> void:
	var s := float(w["side"])
	(w["shoulder"] as Node3D).rotation = Vector3(0.0, -s * 0.05, s * (dihedral + sin(t * 2.7 + s) * 0.025))
	(w["hand"] as Node3D).rotation = Vector3(0.0, s * 0.04, -s * 0.06 + sin(t * 3.1) * 0.02)

## Сложенные крылья (fold 0..1 — смешивание с текущей позой): крыло отведено назад в своей
## плоскости, повёрнуто ребром вверх вдоль бока и укорочено (кисть под плечом, кончики над хвостом).
func _fold(rig: Dictionary, fold: float, bat: bool, st: Dictionary, ruffle: float) -> void:
	for w: Dictionary in rig["wings"]:
		var s := float(w["side"])
		var sh := w["shoulder"] as Node3D
		var hd := w["hand"] as Node3D
		var tsh := Vector3(0.0, -s * 1.5, s * 1.35)
		var thd := Vector3(0.0, s * 0.2, 0.0)
		var span_k := 0.55
		if bat:
			tsh = Vector3(0.0, -s * 1.45, s * 1.45)
			thd = Vector3(0.0, s * 0.35, 0.0)
			span_k = 0.6
		if ruffle > 0.0:
			# встряхнуть / расправить: крыло приоткрывается
			tsh = tsh.lerp(Vector3(0.0, -s * 0.5, s * 0.6), ruffle)
			span_k = lerpf(span_k, 1.0, ruffle)
		var f := clampf(fold, 0.0, 1.0)
		sh.rotation = sh.rotation.lerp(tsh, f)
		hd.rotation = hd.rotation.lerp(thd, f)
		sh.position = (w["pos0"] as Vector3).lerp(w["fold_pos"] as Vector3, f)
		var k := lerpf(1.0, span_k, f)
		sh.scale = Vector3(k, 1.0, lerpf(1.0, 0.7, f))
		hd.scale = Vector3(lerpf(1.0, 0.6, f), 1.0, 1.0)

func _bird(a: Animal, rig: Dictionary, st: Dictionary, dt: float, lod: int, mode: StringName) -> void:
	var body: Node3D = rig["body"]
	var neck: Node3D = rig["neck"]
	var tail: Node3D = (rig["tail"] as Array)[0]
	var feet: Array = rig["feet"]
	var t := float(st["t"])
	var vy := float(st["vy"])
	var gull := a.species == &"gull"
	var fold := FaunaAnim.damp(float(st["fold"]), 1.0 if mode == &"perch" else 0.0, 9.0, dt)
	st["fold"] = fold
	# взлёт / посадка по вертикальной скорости и высоте
	var near_ground := a.alt < 2.5
	var take := FaunaAnim.damp(float(st["take"]), 1.0 if mode == &"fly" and vy > 0.6 and a.alt < 4.0 else 0.0, 5.0, dt)
	var land := FaunaAnim.damp(float(st["land"]), 1.0 if mode == &"fly" and vy < -0.5 and near_ground else 0.0, 5.0, dt)
	st["take"] = take
	st["land"] = land
	# планирование: чайка — длинные глиссады, попугай — короткие паузы
	var glide_on := false
	if gull:
		glide_on = fposmod(t + float(a.flock_offset.z), 6.0) > 3.5 and vy > -1.5
	else:
		glide_on = fposmod(t * 0.9 + float(a.flock_offset.x), 3.2) > 2.85
	if take > 0.3 or land > 0.3:
		glide_on = false
	var glide := FaunaAnim.damp(float(st["glide"]), 1.0 if glide_on else 0.0, 6.0, dt)
	st["glide"] = glide
	var freq := _freq(a) * (1.0 + take * 0.35 - land * 0.25)
	var ph := float(st["ph"]) + dt * freq * TAU * (1.0 - glide * 0.95)
	st["ph"] = ph
	var amp := (0.55 if gull else 0.85) * (1.0 + take * 0.3 + land * 0.2)
	var dihedral := 0.08 + land * 0.35
	if fold < 0.999:
		for w: Dictionary in rig["wings"]:
			if glide > 0.5:
				_glide_wing(w, t, 0.1 if gull else 0.06)
			else:
				_flap_wing(w, ph, amp, dihedral, 1.0 if not gull else 0.6, 0.0)
	# сидит: изредка встряхивает крыльями
	var ruffle := float(st["ruffle"])
	if mode == &"perch" and lod == 0 and ruffle <= 0.0 and randf() < dt * 0.04:
		ruffle = 0.6
	ruffle = maxf(0.0, ruffle - dt)
	st["ruffle"] = ruffle
	if fold > 0.001:
		_fold(rig, fold, false, st, sin(clampf(ruffle / 0.6, 0.0, 1.0) * PI) * 0.8)
	# тело: тангаж по набору высоты, при взлёте/посадке — почти вертикально
	var pitch := clampf(vy * 0.06, -0.3, 0.3) * (1.0 - fold)
	pitch += take * 0.45 + land * 0.75
	pitch = lerpf(pitch, 0.18 if not gull else 0.05, fold)  # сидит: грудь чуть вверх
	st["pitch"] = FaunaAnim.damp(float(st["pitch"]), pitch, 6.0, dt)
	var flap_bob := -sin(ph) * 0.012 * (1.0 - glide) * (1.0 - fold)
	body.rotation = Vector3(float(st["pitch"]), 0.0, 0.0)
	body.position = Vector3(0.0, flap_bob, 0.0)
	# лапки: в полёте поджаты назад, при посадке — вперёд
	var foot_x := lerpf(-1.35, 0.55, land)
	foot_x = lerpf(foot_x, -float(st["pitch"]), fold)
	for f in feet:
		(f as Node3D).rotation = Vector3(foot_x, 0.0, 0.0)
	# голова
	var hx := -float(st["pitch"]) * 0.8
	var hy := 0.0
	var hz := 0.0
	if fold > 0.5 and lod == 0:
		# резкие повороты головы
		var lt := float(st["look_t"]) - dt
		if lt <= 0.0:
			lt = randf_range(0.35, 2.2)
			st["look_y"] = randf_range(-1.3, 1.3)
			st["look_x"] = randf_range(-0.35, 0.25)
		st["look_t"] = lt
		hy = float(st["look_y"])
		hx += float(st["look_x"])
		hz = float(st["look_y"]) * 0.15
		# чистит перья: голова к крылу
		var pr := float(st["preen"])
		var pcd := float(st["preen_cd"]) - dt
		if pr <= 0.0 and pcd <= 0.0:
			pr = 1.4
			pcd = randf_range(6.0, 14.0)
		st["preen_cd"] = pcd
		if pr > 0.0:
			pr -= dt
			var e := clampf(minf(1.4 - pr, pr) * 6.0, 0.0, 1.0)
			hy = lerpf(hy, 2.3, e)
			hx = lerpf(hx, -0.5 + sin(t * 16.0) * 0.08, e)
			hz = lerpf(hz, 0.4, e)
		st["preen"] = pr
	elif a.tamed and a.species == &"parrot" and a._now() - a.fed_t < 2.5:
		hx = -0.4 + sin(t * 14.0) * 0.1
	var snap := 26.0 if fold > 0.5 else 8.0
	var cur := neck.rotation
	neck.rotation = Vector3(FaunaAnim.damp(cur.x, hx, snap, dt), FaunaAnim.damp_angle(cur.y, hy, snap, dt), FaunaAnim.damp(cur.z, hz, snap, dt))
	# хвост: веер при посадке, покачивание сидя
	var tx := land * 0.45 - take * 0.15
	if fold > 0.5:
		tx = 0.12 + maxf(0.0, sin(t * 5.0)) * 0.12 * (1.0 if fposmod(t, 3.0) < 0.6 else 0.0)
	tail.rotation = Vector3(FaunaAnim.damp(tail.rotation.x, tx, 10.0, dt), sin(t * 1.3) * 0.05 * (1.0 - fold), 0.0)

func _bat(a: Animal, rig: Dictionary, st: Dictionary, dt: float, lod: int, mode: StringName) -> void:
	var body: Node3D = rig["body"]
	var neck: Node3D = rig["neck"]
	var feet: Array = rig["feet"]
	var t := float(st["t"])
	var hang := mode == &"roost"
	var fold := FaunaAnim.damp(float(st["fold"]), 1.0 if hang else 0.0, 7.0, dt)
	st["fold"] = fold
	var o := a.flock_offset.x * 3.0 + a.flock_offset.z
	if fold < 0.999:
		# быстрые глубокие взмахи, кисть сильно складывается на подъёме
		var ph := float(st["ph"]) + dt * (_freq(a) + sin(t * 1.7 + o) * 1.5) * TAU
		st["ph"] = ph
		for w: Dictionary in rig["wings"]:
			_flap_wing(w, ph, 1.05, 0.0, 1.6, 0.1)
	if fold > 0.001:
		# висит: крылья обёрнуты вокруг тела, изредка расправляет
		var stretch := 0.0
		if lod == 0 and fposmod(t + o, 11.0) < 0.9:
			stretch = sin(fposmod(t + o, 11.0) / 0.9 * PI) * 0.7
		_fold(rig, fold, true, st, stretch)
	# тело: в полёте — рывки по крену и тангажу; вися — вниз головой, покачивается
	var jitter := Vector3(sin(t * 6.3 + o) * 0.25, 0.0, sin(t * 7.9 + o * 1.3) * 0.45) * (1.0 - fold)
	var hang_rot := Vector3(-PI * 0.5 + sin(t * 0.9 + o) * 0.06, 0.0, sin(t * 0.7 + o) * 0.05)
	body.rotation = jitter.lerp(hang_rot, fold)
	# точка подвеса — лапки над телом: тело висит ниже ветки
	body.position = Vector3(0.0, -0.05 * fold, 0.0)
	for f in feet:
		(f as Node3D).rotation = Vector3(lerpf(-0.6, 0.25, fold), 0.0, 0.0)
	var hx := 0.0
	var hy := 0.0
	if hang and lod == 0:
		var lt := float(st["look_t"]) - dt
		if lt <= 0.0:
			lt = randf_range(1.0, 4.0)
			st["look_y"] = randf_range(-0.8, 0.8)
		st["look_t"] = lt
		hy = float(st["look_y"])
		hx = 0.5  # голова приподнята к земле (тело вниз головой)
	neck.rotation = Vector3(FaunaAnim.damp(neck.rotation.x, hx, 10.0, dt), FaunaAnim.damp_angle(neck.rotation.y, hy, 10.0, dt), 0.0)
