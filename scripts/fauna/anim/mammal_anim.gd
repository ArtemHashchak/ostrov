extends RefCounted
## Процедурная анимация четвероногих: кабан и обезьяна (риги CreatureRigs).
## Походки по фазам ног с долей опоры (стопа стоит на земле, пока нога в опоре — длина шага
## подобрана под скорость), смена шаг → рысь → галоп/прыжки с плавным перетеканием фаз,
## подгибание колена под рельеф (IK-lite), голова/хвост/поза по состоянию зверя.

const TAU_ := TAU

# фазы ног [ПЛ, ПП, ЗЛ, ЗП]
const WALK := [0.25, 0.75, 0.0, 0.5]      # боковая последовательность: ЗЛ → ПЛ → ЗП → ПП
const TROT := [0.0, 0.5, 0.5, 0.0]        # диагональные пары
const GALLOP := [0.55, 0.45, 0.05, 0.0]   # поперечный галоп: задние, потом передние
const BOUND := [0.5, 0.55, 0.0, 0.05]     # прыжки обезьяны

# ---------------------------------------------------------------------------
func animate(a: Animal, dt: float) -> void:
	var rig: Dictionary = a._model.get_meta(&"rig", {})
	if rig.is_empty():
		return
	var st := a.anim_state
	if st.is_empty():
		_init_state(a, st)
	var lod := FaunaAnim.lod_of(a)
	if lod == 2 and st.get("posed", false):
		return
	st["posed"] = true
	st["t"] = float(st["t"]) + dt
	if a.species == &"monkey":
		_monkey(a, rig, st, dt, lod)
	else:
		_boar(a, rig, st, dt, lod)

## События от Animal: attack — удар клыками; eat — жуёт (вздрог — по a._hurt_flash).
func on_event(a: Animal, ev: StringName) -> void:
	if a.anim_state.is_empty():
		_init_state(a, a.anim_state)
	match ev:
		&"attack":
			a.anim_state["toss"] = 0.45
		&"eat":
			a.anim_state["eat_t"] = 2.5

func animate_dead(a: Animal, dt: float) -> void:
	var rig: Dictionary = a._model.get_meta(&"rig", {})
	if rig.is_empty():
		return
	var body: Node3D = rig["body"]
	var t := a._dead_t
	# тело ложится на бок, а не проваливается: сдвиг на полуширину вдоль оси крена
	var side_w := 0.23 if a.species == &"boar" else 0.12
	body.position = Vector3(side_w * sin(a._model.rotation.z), 0.0, 0.0)
	var decay := clampf(1.0 - t / 2.5, 0.0, 1.0)
	var legs: Array = rig["legs"]
	var knees: Array = rig["knees"]
	for i in legs.size():
		var kick := sin(t * 15.0 + i * 1.7) * 0.45 * decay * decay
		(legs[i] as Node3D).rotation = Vector3(kick + (0.25 if i < 2 else -0.2), 0.0, 0.0)
		(knees[i] as Node3D).rotation.x = -0.25 - absf(kick) * 0.6
	var neck: Node3D = rig.get("neck")
	if neck:
		neck.rotation = Vector3(-0.15 - 0.2 * (1.0 - decay), 0.0, 0.25 * (1.0 - decay))
	if rig.has("hips"):
		(rig["hips"] as Node3D).rotation.x = 0.0
	if rig.has("hand"):
		_show_loot(a, rig, false)

# ---------------------------------------------------------------------------
func _init_state(a: Animal, st: Dictionary) -> void:
	st["t"] = 0.0
	st["cycle"] = randf()
	st["offs"] = WALK.duplicate()
	st["head_x"] = 0.0
	st["head_y"] = 0.0
	st["look_t"] = 0.0
	st["look_y"] = 0.0
	st["look_x"] = 0.0
	st["toss"] = 0.0
	st["eat_t"] = 0.0
	st["rest"] = 0.0      # 0..1 — лечь/сесть
	st["swim"] = 0.0
	st["climb"] = 0.0
	st["scratch"] = 0.0
	st["scratch_cd"] = randf_range(2.0, 6.0)
	st["throw"] = -1.0
	st["throw_cd"] = randf_range(3.0, 6.0)
	st["root_t"] = randf_range(0.0, 4.0)

## Фазы ног и их перетекание к нужной походке.
func _gait_offsets(st: Dictionary, target: Array, dt: float) -> Array:
	var offs: Array = st["offs"]
	for i in 4:
		var d := wrapf(float(target[i]) - float(offs[i]), -0.5, 0.5)
		offs[i] = wrapf(float(offs[i]) + d * (1.0 - exp(-4.0 * dt)), 0.0, 1.0)
	return offs

## Угол бедра и сгиб колена для фазы ph (0..1) при доле опоры duty.
static func _leg_pose(ph: float, duty: float, amp: float, lift: float) -> Vector2:
	if ph < duty:
		var s := ph / duty
		return Vector2(amp * (1.0 - 2.0 * s), 0.0)
	var s2 := (ph - duty) / (1.0 - duty)
	var e := s2 * s2 * (3.0 - 2.0 * s2)
	var raise := sin(PI * s2)
	return Vector2(-amp + 2.0 * amp * e + lift * 0.35 * raise, -lift * raise)

## Подгиб колена под рельеф: ступня не уходит в склон и не висит над ямой (только LOD 0).
func _ik_bend(a: Animal, hip: Node3D, l1: float, l2: float) -> float:
	var hp := hip.global_position
	var g := Fauna.ground_y_at(a, hp.x, hp.z)
	var need := hp.y - g
	var full := l1 + l2
	if need >= full - 0.005:
		return 0.0
	var Lt := clampf(need, full * 0.45, full)
	var c := (Lt * Lt - l1 * l1 - l2 * l2) / (2.0 * l1 * l2)
	return acos(clampf(c, -1.0, 1.0))

func _apply_legs(a: Animal, rig: Dictionary, st: Dictionary, offs: Array, duty: float, amp: float,
		lift: float, lod: int, skip: int = -1) -> void:
	var legs: Array = rig["legs"]
	var knees: Array = rig["knees"]
	var ll: Array = rig["leg_len"]
	var cycle := float(st["cycle"])
	for i in legs.size():
		if i == skip:
			continue
		var p := _leg_pose(wrapf(cycle + float(offs[i]), 0.0, 1.0), duty, amp, lift)
		var hip := legs[i] as Node3D
		var knee := knees[i] as Node3D
		var bend := 0.0
		if lod == 0 and float(st["swim"]) < 0.5:
			bend = _ik_bend(a, hip, float(ll[0]), float(ll[1]))
		hip.rotation.x = p.x + bend * 0.5
		knee.rotation.x = p.y - bend

# ============================== кабан ==============================
func _boar(a: Animal, rig: Dictionary, st: Dictionary, dt: float, lod: int) -> void:
	var body: Node3D = rig["body"]
	var neck: Node3D = rig["neck"]
	var legs: Array = rig["legs"]
	var knees: Array = rig["knees"]
	var t := float(st["t"])
	var sp := a.speed
	var state := a.state
	# --- плавание: спина у поверхности, лапы гребут
	var wl := Fauna.water_y(a)
	var depth := wl - a.global_position.y
	var swim_k := FaunaAnim.damp(float(st["swim"]), 1.0 if depth > 0.4 else 0.0, 4.0, dt)
	st["swim"] = swim_k
	# --- отдых (приручённый «ждать» или долгий простой): лечь
	var want_rest := (a.tamed and state == &"stay" and a.state_t > 1.5) or (state == &"idle" and a.state_t > 7.0)
	var rest := FaunaAnim.damp(float(st["rest"]), 1.0 if want_rest and swim_k < 0.1 else 0.0, 2.5, dt)
	st["rest"] = rest
	# --- походка
	var gait: Array
	var freq: float
	var duty: float
	if swim_k > 0.5:
		gait = TROT
		freq = 2.1
		duty = 0.5
	elif sp < 2.2:
		gait = WALK
		freq = 0.9 + sp * 0.45
		duty = 0.66
	elif sp < 4.3:
		gait = TROT
		freq = 1.9 + (sp - 2.2) * 0.18
		duty = 0.5
	else:
		gait = GALLOP
		freq = 2.6 + (sp - 4.3) * 0.08
		duty = 0.38
	var moving := clampf(sp / 0.35, 0.0, 1.0)
	if swim_k > 0.5:
		moving = 1.0
	st["cycle"] = wrapf(float(st["cycle"]) + freq * dt * maxf(moving, 0.0), 0.0, 1.0)
	var offs := _gait_offsets(st, gait, dt)
	var stride := sp * duty / maxf(freq, 0.1)
	var amp := clampf(atan2(stride * 0.5, 0.48), 0.0, 0.62) * moving
	var lift := (0.35 + minf(sp, 7.0) * 0.07) * moving
	if swim_k > 0.5:
		amp = 0.55
		lift = 0.9
	_apply_legs(a, rig, st, offs, duty, amp, lift, lod)
	# поза «лёжа»: ноги подогнуты, тело опущено
	if rest > 0.01:
		for i in 4:
			var hip := legs[i] as Node3D
			var knee := knees[i] as Node3D
			var front := i < 2
			hip.rotation.x = lerpf(hip.rotation.x, 0.35 if front else 1.1, rest)
			knee.rotation.x = lerpf(knee.rotation.x, -2.3 if front else -2.5, rest)
	# --- тело: покачивание по походке
	var c := float(st["cycle"]) * TAU_
	var bob := 0.0
	var pitch := 0.0
	if gait == GALLOP and swim_k < 0.5:
		bob = sin(c) * 0.035
		pitch = sin(c + 0.6) * 0.07
	elif gait == TROT:
		bob = absf(sin(c * 2.0)) * 0.018 * moving
	else:
		bob = sin(c * 4.0) * 0.008 * moving
	var y := bob - rest * 0.3
	if swim_k > 0.01:
		y = lerpf(y, (wl - a.global_position.y) - 0.62 + sin(t * 2.0) * 0.02, swim_k)
		pitch = lerpf(pitch, -0.08, swim_k)
	# --- атака: бросок с ударом клыками вверх (событие attack в момент укуса)
	var toss := maxf(0.0, float(st["toss"]) - dt)
	st["toss"] = toss
	var lunge := 0.0
	var head_x := 0.0
	var head_y := 0.0
	if toss > 0.0:
		var k := 1.0 - toss / 0.45
		if k < 0.3:
			head_x = -0.35 * (k / 0.3)
		elif k < 0.6:
			head_x = lerpf(-0.35, 0.5, (k - 0.3) / 0.3)
		else:
			head_x = 0.5 * (1.0 - (k - 0.6) / 0.4)
		lunge = -sin(k * PI) * 0.16
	else:
		match state:
			&"chase":
				head_x = -0.24
			&"attack":
				head_x = -0.3
			&"flee":
				head_x = 0.08
			&"idle", &"wander", &"follow", &"stay":
				# рыло в землю: копает с толчками
				var rooting := state == &"idle" and a.state_t > 1.2 and rest < 0.5
				if rooting:
					var rt := fposmod(t + float(st["root_t"]), 5.0)
					var nudge := maxf(0.0, sin(rt * 9.0)) * 0.08 if rt < 3.0 else 0.0
					head_x = -0.5 + nudge
				elif lod == 0:
					_look_around(st, dt, 0.45, 0.15)
					head_x = float(st["look_x"])
					head_y = float(st["look_y"])
	# ест с руки / только что покормили
	st["eat_t"] = maxf(0.0, float(st["eat_t"]) - dt)
	if a._now() - a.fed_t < 2.5 or float(st["eat_t"]) > 0.0:
		head_x = -0.45 + sin(t * 13.0) * 0.05
		head_y = 0.0
	if swim_k > 0.3:
		head_x = lerpf(head_x, 0.32, swim_k)
	# вздрог от удара
	var hurt := a._hurt_flash / 0.25
	head_x += hurt * 0.25
	head_x -= rest * 0.15
	st["head_x"] = FaunaAnim.damp(float(st["head_x"]), head_x, 14.0 if toss > 0.0 else 7.0, dt)
	st["head_y"] = FaunaAnim.damp(float(st["head_y"]), head_y, 6.0, dt)
	var bob_head := -bob * 1.5
	neck.rotation = Vector3(float(st["head_x"]) + bob_head, float(st["head_y"]), hurt * 0.12)
	body.position = Vector3(hurt * 0.03 * sin(t * 40.0), y, lunge + hurt * 0.05)
	body.rotation = Vector3(pitch + rest * 0.02, 0.0, hurt * 0.08)
	# хвост: при беге торчком (как у бородавочника), в покое — помахивает
	var tail: Node3D = (rig["tail"] as Array)[0]
	if lod == 0 or lod == 1:
		var up := clampf((sp - 3.0) / 2.0, 0.0, 1.0)
		var wag := sin(t * 9.0) * 0.35 * (1.0 - up)
		if fposmod(t, 4.0) > 1.6:
			wag *= 0.15
		tail.rotation = Vector3(lerpf(0.0, -2.2, up), 0.0, wag)

# ============================== обезьяна ==============================
func _monkey(a: Animal, rig: Dictionary, st: Dictionary, dt: float, lod: int) -> void:
	var body: Node3D = rig["body"]
	var hips: Node3D = rig["hips"]
	var neck: Node3D = rig["neck"]
	var legs: Array = rig["legs"]
	var knees: Array = rig["knees"]
	var t := float(st["t"])
	var sp := a.speed
	var state := a.state
	var has_loot := not a.stolen.is_empty()
	_show_loot(a, rig, has_loot)
	# --- лазанье на дерево (поведение поднимает зверя на 3.5 м в состоянии perch)
	var perch := state == &"perch"
	var climb := float(st["climb"])
	climb = move_toward(climb, 1.0 if perch else 0.0, dt / (2.2 if perch else 1.3))
	st["climb"] = climb
	var climbing := climb > 0.0 and climb < 1.0
	var base_lift := a.global_position.y - Fauna.ground_y_at(a, a.global_position.x, a.global_position.z)
	if not perch and climb <= 0.0:
		base_lift = 0.0
	var vis_lift := climb * 3.5
	# --- посадка: сидит в покое, на ветке, ест, «ждать»
	var fed := a._now() - a.fed_t < 2.5
	var want_sit := (state in [&"idle", &"stay"] and a.state_t > 0.8 and sp < 0.2) or (perch and climb >= 1.0) or fed
	var sit := FaunaAnim.damp(float(st["rest"]), 1.0 if want_sit else 0.0, 4.0, dt)
	st["rest"] = sit
	# --- походка: шаг или прыжки
	var gait: Array = WALK
	var freq := 1.1 + sp * 0.5
	var duty := 0.62
	if sp > 2.6:
		gait = BOUND
		freq = 2.2 + (sp - 2.6) * 0.15
		duty = 0.42
	var moving := clampf(sp / 0.3, 0.0, 1.0)
	if climbing:
		moving = 1.0
		freq = 2.0
	st["cycle"] = wrapf(float(st["cycle"]) + freq * dt * moving, 0.0, 1.0)
	var offs := _gait_offsets(st, gait, dt)
	var stride := sp * duty / maxf(freq, 0.1)
	var amp := clampf(atan2(stride * 0.5, 0.41), 0.0, 0.7) * moving
	var lift := (0.4 + minf(sp, 6.0) * 0.08) * moving
	# с добычей бежит на трёх лапах: правая рука прижимает добычу к груди
	var skip := 1 if has_loot and not climbing else -1
	_apply_legs(a, rig, st, offs, duty, amp, lift, lod if not climbing else 1, skip)
	var c := float(st["cycle"]) * TAU_
	var torso_x := 0.0
	var bob := 0.0
	if gait == BOUND:
		torso_x = sin(c) * 0.12
		bob = sin(c) * 0.03
	else:
		bob = absf(sin(c * 2.0)) * 0.012 * moving
	# поза сидя: туловище поднято вокруг таза, ноги подогнуты вперёд, руки на коленях
	if sit > 0.01:
		torso_x = lerpf(torso_x, 1.05, sit)
		for i in 4:
			var hip := legs[i] as Node3D
			var knee := knees[i] as Node3D
			if i < 2:
				hip.rotation.x = lerpf(hip.rotation.x, -0.75, sit)
				knee.rotation.x = lerpf(knee.rotation.x, -0.5, sit)
			else:
				hip.rotation.x = lerpf(hip.rotation.x, 1.35, sit)
				knee.rotation.x = lerpf(knee.rotation.x, -2.0, sit)
	# лазанье: тело вертикально у ствола, руки тянутся вверх по очереди
	if climbing:
		var k := 1.0 - absf(climb * 2.0 - 1.0)
		var ck := clampf(k * 3.0, 0.0, 1.0)
		torso_x = lerpf(torso_x, 1.45, ck)
		for i in 4:
			var hip := legs[i] as Node3D
			var knee := knees[i] as Node3D
			var ph := sin(c + (PI if i % 2 == 0 else 0.0) + (0.0 if i < 2 else PI * 0.5))
			if i < 2:
				hip.rotation.x = lerpf(hip.rotation.x, 1.7 + ph * 0.45, ck)
				knee.rotation.x = lerpf(knee.rotation.x, -0.4 - maxf(0.0, ph) * 0.6, ck)
			else:
				hip.rotation.x = lerpf(hip.rotation.x, 1.4 + ph * 0.35, ck)
				knee.rotation.x = lerpf(knee.rotation.x, -1.5 - maxf(0.0, -ph) * 0.4, ck)
	# --- правая рука: добыча, почёсывание, бросок, еда
	var arm_r := legs[1] as Node3D
	var elb_r := knees[1] as Node3D
	var arm_l := legs[0] as Node3D
	var elb_l := knees[0] as Node3D
	if has_loot and not climbing:
		var k2 := 1.0 if sit < 0.5 else 0.0
		arm_r.rotation = Vector3(lerpf(1.1, 1.9, sit), 0.0, -0.25 * k2)
		elb_r.rotation.x = -2.1 + (sin(t * 5.0) * 0.25 if sit > 0.5 else 0.0)
	# почёсывание в покое (сидя)
	var scratch := float(st["scratch"])
	var scd := float(st["scratch_cd"]) - dt
	if scratch <= 0.0 and scd <= 0.0 and sit > 0.9 and not has_loot and not fed and lod == 0:
		scratch = 1.6
		scd = randf_range(4.0, 9.0)
	st["scratch_cd"] = scd
	if scratch > 0.0:
		scratch -= dt
		var e := clampf(minf(1.6 - scratch, scratch) * 5.0, 0.0, 1.0)
		arm_r.rotation = arm_r.rotation.lerp(Vector3(2.55, -0.3, -0.5), e)
		elb_r.rotation.x = lerpf(elb_r.rotation.x, -2.3 + sin(t * 22.0) * 0.3, e)
	st["scratch"] = scratch
	# бросок с дерева в того, кто рядом
	_monkey_throw(a, rig, st, dt, lod, perch and climb >= 1.0, arm_r, elb_r)
	# ест с руки: обе руки ко рту, жуёт
	if fed:
		for pr in [[arm_l, elb_l], [arm_r, elb_r]]:
			(pr[0] as Node3D).rotation = Vector3(2.0, 0.0, 0.0)
			(pr[1] as Node3D).rotation.x = -2.3
	# --- голова
	var head_x := 0.0
	var head_y := 0.0
	if lod == 0 and not climbing:
		_look_around(st, dt, 0.9, 0.3)
		head_x = float(st["look_x"])
		head_y = float(st["look_y"])
	if state == &"flee" or (state == &"steal" and sp > 2.0):
		head_y = 0.0
		head_x = 0.15
	if fed:
		head_x = -0.25 + sin(t * 11.0) * 0.06
	head_x -= torso_x * 0.75   # голова держит горизонт, когда туловище поднято
	if climbing:
		head_x = -0.9
	var hurt := a._hurt_flash / 0.25
	head_x += hurt * 0.3
	st["head_x"] = FaunaAnim.damp(float(st["head_x"]), head_x, 9.0, dt)
	st["head_y"] = FaunaAnim.damp(float(st["head_y"]), head_y, 9.0, dt)
	neck.rotation = Vector3(float(st["head_x"]), float(st["head_y"]), 0.0)
	hips.rotation = Vector3(torso_x, 0.0, 0.0)
	var y := bob - sit * 0.24 + (vis_lift - base_lift)
	if climbing:
		y += 0.12
	body.position = Vector3(0.0, y, hurt * 0.05)
	body.rotation = Vector3(0.0, 0.0, hurt * 0.1)
	# --- хвост: S-дуга при ходьбе, висит с ветки, лежит сзади сидя
	if lod <= 1:
		var tail: Array = rig["tail"]
		var n := tail.size()
		var hang := clampf((climb - 0.6) / 0.4, 0.0, 1.0)
		for i in n:
			var f := float(i) / float(n - 1)
			var walk_x: float = [-0.95, -0.25, 0.2, 0.32, 0.32, 0.3, 0.3, 0.32][i]
			var sit_x: float = [0.55, 0.35, 0.15, 0.0, -0.1, -0.2, -0.3, -0.4][i]
			var hang_x: float = [1.25, 0.12, 0.06, 0.05, 0.05, 0.1, -0.35, -0.6][i]
			var rx := lerpf(walk_x, sit_x, sit * (1.0 - hang))
			rx = lerpf(rx, hang_x, hang)
			if gait == BOUND and sit < 0.5:
				rx += sin(c - f * 2.0) * 0.12
			var sway := sin(t * (1.6 + hang * 0.6) - f * 2.6) * (0.08 + f * 0.18) * (1.0 - sit * 0.5)
			(tail[i] as Node3D).rotation = Vector3(rx + sin(t * 2.1 - f * 3.0) * 0.06, sway, 0.0)

func _monkey_throw(a: Animal, rig: Dictionary, st: Dictionary, dt: float, lod: int, on_branch: bool,
		arm: Node3D, elb: Node3D) -> void:
	var th := float(st["throw"])
	var cd := float(st["throw_cd"]) - dt
	st["throw_cd"] = cd
	if th < 0.0:
		if on_branch and cd <= 0.0 and lod == 0 and a.stolen.is_empty():
			var tg := a._nearest_character(14.0)
			if tg:
				st["throw"] = 0.0
				st["throw_tg"] = tg
				st["thrown"] = false
				st["throw_cd"] = randf_range(6.0, 11.0)
		return
	th += dt
	st["throw"] = th
	var tg: Node3D = st.get("throw_tg", null)
	if tg != null and is_instance_valid(tg):
		# развернуться к цели
		var to := tg.global_position - a.global_position
		a.heading = FaunaAnim.damp_angle(a.heading, atan2(-to.x, -to.z), 8.0, dt)
		a.rotation.y = a.heading
	if th < 0.35:
		var e := th / 0.35
		arm.rotation = Vector3(lerpf(arm.rotation.x, 2.9, e), 0.0, -0.3 * e)
		elb.rotation.x = lerpf(elb.rotation.x, -1.9, e)
	elif th < 0.55:
		var e2 := (th - 0.35) / 0.2
		arm.rotation = Vector3(lerpf(2.9, 0.9, e2), 0.0, -0.3)
		elb.rotation.x = lerpf(-1.9, -0.2, e2)
		if not bool(st["thrown"]) and e2 > 0.5:
			st["thrown"] = true
			if tg != null and is_instance_valid(tg):
				_spawn_throw(a, (rig["hand"] as Node3D).global_position, tg.global_position + Vector3(0, 1.0, 0))
	elif th < 0.9:
		pass
	else:
		st["throw"] = -1.0

## Брошенный орех: дуга к цели, отскок и исчезновение (только визуально).
func _spawn_throw(a: Animal, from: Vector3, to: Vector3) -> void:
	var parent := a.get_parent()
	if parent == null or not parent.is_inside_tree():
		return
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.045
	sm.height = 0.085
	sm.radial_segments = 8
	sm.rings = 4
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.35, 0.24, 0.14)
	m.roughness = 0.9
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = from
	var dur := clampf(from.distance_to(to) / 12.0, 0.35, 1.1)
	var peak := 1.0 + from.distance_to(to) * 0.08
	var tw := mi.create_tween()
	tw.tween_method(func(k: float) -> void:
		if is_instance_valid(mi):
			mi.global_position = from.lerp(to, k) + Vector3(0, sin(k * PI) * peak, 0)
			mi.rotation = Vector3(k * 9.0, k * 5.0, 0.0), 0.0, 1.0, dur)
	tw.tween_callback(mi.queue_free).set_delay(0.6)
	FaunaSfx.play(a, &"monkey", 3.0, 5.0, 1.15)

func _show_loot(a: Animal, rig: Dictionary, on: bool) -> void:
	var hand: Node3D = rig["hand"]
	var it := hand.get_node_or_null(^"Loot") as MeshInstance3D
	if on and it == null:
		it = MeshInstance3D.new()
		it.name = "Loot"
		var bm := SphereMesh.new()
		bm.radius = 0.06
		bm.height = 0.1
		bm.radial_segments = 10
		bm.rings = 5
		it.mesh = bm
		var m := StandardMaterial3D.new()
		var id: StringName = a.stolen[0].get("id", &"") if not a.stolen.is_empty() else &""
		m.albedo_color = Color(0.9, 0.75, 0.2) if String(id) in ["banana", "mango", "papaya"] else Color(0.55, 0.42, 0.28)
		m.roughness = 0.8
		it.material_override = m
		it.position = Vector3(0, -0.02, -0.03)
		hand.add_child(it)
	if it:
		it.visible = on

## Осматривается: резкие повороты головы к новым случайным точкам.
func _look_around(st: Dictionary, dt: float, yaw: float, pitch: float) -> void:
	var lt := float(st["look_t"]) - dt
	if lt <= 0.0:
		lt = randf_range(0.8, 3.0)
		st["look_y"] = randf_range(-yaw, yaw) if randf() < 0.75 else 0.0
		st["look_x"] = randf_range(-pitch, pitch * 0.6)
	st["look_t"] = lt
