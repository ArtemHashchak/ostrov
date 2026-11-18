class_name CombatController
extends Node
## Оружие игрока (вешается модулем Combat ребёнком игрока; ввод получает раньше игрока).
##  Огнестрел/арбалет: ЛКМ — выстрел (пусто — перезарядка), ПКМ — прицел (целик по центру, FOV↓),
##    R — перезарядка: порох + пуля (мушкет ~5.5 с, шомпол), арбалет — болт (ворот ~3.2 с).
##  Лук: держать ЛКМ — натянуть (сила от натяжения), отпустить — выстрел; ПКМ — прицел; R — тип стрел.
##  Молотов/динамит: держать ЛКМ — замах (сила), отпустить — бросок.
##  Копьё: ЛКМ — выпад (анимация игрока); держать ПКМ — замах над плечом, ЛКМ — бросок.
##  Дубина/топоры — удары игрока (урон из Items).

var p: Player
var hands: FPHands
var cam: Camera3D

var wid: StringName = &""
var w: Dictionary = {}
var ads := 0.0
var draw := 0.0
var windup := 0.0
var bow_ammo: StringName = &"arrow"

var _model: Node3D
var _bow_fp: Node3D
var _arrow_fp: Node3D
var _flame: Node3D
var _prev_atk := false
var _prev_aim := false
var _prev_reload := false
var _drawing := false
var _winding := false
var _throw_anim := 0.0
var _fire_anim := 0.0
var _kick := Vector2.ZERO
var _shake := 0.0
var _draw_hold := 0.0
var _reload_len := 0.0
var _reload_snd := false
var _ui: CanvasLayer
var _ammo_label: Label
var _marker: Control
var _marker_t := 0.0
var _marker_head := false
var _draw_snd: AudioStreamPlayer3D
var _noise := FastNoiseLite.new()
var _t := 0.0

func _ready() -> void:
	p = get_parent() as Player
	if p == null:
		return
	hands = p.hands
	cam = p.camera
	_noise.frequency = 0.6
	_build_ui()

# ======================= ввод =======================

func _active() -> bool:
	return p != null and p.alive and p.input_enabled and not p.ui_open and not get_tree().paused \
		and not p.carrying_log and not p.swimming

func _unhandled_input(event: InputEvent) -> void:
	if wid == &"" or not _active():
		return
	var t: StringName = w.type
	if t == &"melee":
		return
	if event.is_action(&"aim"):
		get_viewport().set_input_as_handled()
	elif event.is_action(&"attack"):
		if wid == &"spear" and not Input.is_action_pressed(&"aim"):
			return # выпад копьём — анимация игрока
		get_viewport().set_input_as_handled()
	elif event.is_action(&"reload") and t in [&"gun", &"crossbow", &"bow"]:
		get_viewport().set_input_as_handled()

# ======================= кадр =======================

func _process(delta: float) -> void:
	if p == null:
		return
	_t += delta
	_sync_weapon()
	var active := _active() and wid != &""
	var atk := Input.is_action_pressed(&"attack") and active
	var aim := Input.is_action_pressed(&"aim") and active
	var rel := InputMap.has_action(&"reload") and Input.is_action_pressed(&"reload") and active
	var atk_down := atk and not _prev_atk
	var atk_up := not atk and _prev_atk
	var rel_down := rel and not _prev_reload
	_prev_atk = atk
	_prev_aim = aim
	_prev_reload = rel
	var want_ads := false
	if active:
		match w.type:
			&"gun", &"crossbow":
				want_ads = aim and not Combat.is_reloading(p) and not p.sprinting
				if atk_down:
					_trigger()
				if rel_down:
					_start_reload()
			&"bow":
				want_ads = aim and not p.sprinting
				_bow_input(delta, atk, atk_up)
				if rel_down:
					_toggle_arrows()
			&"throw":
				if wid == &"spear":
					_spear_input(delta, aim, atk_down)
				else:
					_throw_input(delta, atk, atk_up)
	else:
		_drawing = false
		_winding = false
		draw = move_toward(draw, 0.0, delta * 4.0)
		windup = 0.0
	ads = move_toward(ads, 1.0 if want_ads else 0.0, delta * (6.0 if want_ads else 8.0))
	var zoom := float(w.get("zoom", 0.0)) if wid != &"" else 0.0
	p.fov_zoom = zoom * smoothstep(0.0, 1.0, ads)
	_throw_anim = move_toward(_throw_anim, 0.0, delta / 0.45)
	_fire_anim = move_toward(_fire_anim, 0.0, delta * 3.0)
	_update_pose(delta)
	_update_parts()
	_update_camera_fx(delta)
	_update_ui(delta)

func _sync_weapon() -> void:
	var id := p.held_item()
	if not Combat.is_weapon(id):
		id = &""
	if id != wid:
		_unequip()
		wid = id
		w = Combat.weapon(id)
		_equip()
	if wid != &"" and (_model == null or not is_instance_valid(_model) or _model.is_queued_for_deletion()):
		_find_model()

func _equip() -> void:
	draw = 0.0
	windup = 0.0
	_find_model()
	if wid == &"bow":
		_bow_fp = Node3D.new()
		_bow_fp.name = "BowFP"
		CombatModels._bow(_bow_fp, true)
		HeldModels._no_shadows(_bow_fp)
		hands.left_arm.get_node(^"Hand").add_child(_bow_fp)
		# лук вертикально в кулаке (рука повёрнута ребром), слегка «завален» вправо
		_bow_fp.basis = Basis(Vector3.BACK, deg_to_rad(-80.0)) * Basis(Vector3.BACK, deg_to_rad(-10.0))
		_bow_fp.position = Vector3.ZERO # Hand — ось кулака (FPHands.GRIP)
		_arrow_fp = CombatModels.projectile(&"arrow")
		hands.add_child(_arrow_fp)
		_arrow_fp.visible = false

func _unequip() -> void:
	if Combat.is_reloading(p):
		Combat.cancel_reload(p)
	if _bow_fp:
		_bow_fp.queue_free()
		_bow_fp = null
	if _arrow_fp:
		_arrow_fp.queue_free()
		_arrow_fp = null
	_clear_flame()
	if _draw_snd:
		_draw_snd.queue_free()
		_draw_snd = null
	_drawing = false
	_winding = false
	_model = null
	if hands:
		hands.pose_w = 0.0
	if p:
		p.fov_zoom = 0.0

func _find_model() -> void:
	_model = null
	if hands == null:
		return
	var kids := hands.held_root.get_children()
	for i in range(kids.size() - 1, -1, -1):
		var c := kids[i] as Node3D
		if c and not c.is_queued_for_deletion():
			_model = c
			break
	if _model == null:
		return
	match w.get("type", &""):
		&"gun", &"crossbow":
			_model.position = Vector3.ZERO
		&"bow":
			_model.visible = false

# ======================= действия =======================

func _eye() -> Vector3:
	return cam.global_position

func _aim_dir() -> Vector3:
	return -cam.global_basis.z

func _muzzle_pos() -> Vector3:
	var m := _model.find_child("Muzzle", true, false) as Node3D if _model else null
	return m.global_position if m else _eye() + _aim_dir() * 0.8

func _trigger() -> void:
	if not Combat.is_ready(p, wid):
		return
	if Combat.is_loaded(p, wid):
		var ok := Combat.fire(p, wid, _eye(), _aim_dir(), {"ads": ads > 0.7, "muzzle": _muzzle_pos()})
		if ok:
			_recoil(float(w.get("recoil", 2.0)))
			_set_cock(false)
	else:
		_start_reload()

func _start_reload() -> void:
	if Combat.is_loaded(p, wid) or Combat.is_reloading(p):
		return
	var t := Combat.start_reload(p, wid)
	if t <= 0.0:
		CombatFx.sound_at(p, "dry_click", _eye(), -8.0)
		var need := []
		for a: Dictionary in w.ammo:
			need.append(Items.item_name(a.id))
		Events.toast.emit("Нечем зарядить: нужно — %s" % ", ".join(need))
		return
	_reload_len = t
	_reload_snd = false
	CombatFx.sound_at(p, "crossbow_crank" if w.type == &"crossbow" else "ramrod", _eye() + Vector3.DOWN * 0.4, -6.0)

func _reload_progress() -> float:
	if not Combat.is_reloading(p) or _reload_len <= 0.0:
		return 1.0
	var st := Combat.state(p)
	return clampf(1.0 - (float(st.reload_end) - Combat._now()) / _reload_len, 0.0, 1.0)

func _recoil(deg: float) -> void:
	var yaw: float = p.get(&"_yaw")
	var pitch: float = p.get(&"_pitch")
	p.set_look(yaw + deg_to_rad(randf_range(-0.25, 0.25) * deg), clampf(pitch + deg_to_rad(deg * 0.45), -1.5, 1.5))
	_kick += Vector2(deg_to_rad(deg * 0.9), deg_to_rad(randf_range(-0.3, 0.3) * deg))
	_fire_anim = 1.0
	_shake = maxf(_shake, deg * 0.05)
	if hands:
		hands.right_arm.position += Vector3(0.0, 0.01, 0.012) * deg
		hands.right_arm.rotation.x += deg_to_rad(deg * 1.6)
		hands.left_arm.position += Vector3(0.0, 0.006, 0.008) * deg

func _bow_input(delta: float, atk: bool, atk_up: bool) -> void:
	var have := Combat.has_ammo(p, &"bow")
	if atk and have and Combat.is_ready(p, wid):
		if not _drawing:
			_drawing = true
			_draw_hold = 0.0
			_draw_snd = CombatFx.sound_at(p, "bow_draw", _eye(), -10.0)
		draw = minf(draw + delta / float(w.draw), 1.0)
		if draw >= 1.0:
			_draw_hold += delta
	elif atk and not have and not _drawing and Input.is_action_just_pressed(&"attack"):
		Events.toast.emit("Нет стрел")
	if atk_up and _drawing:
		_drawing = false
		if draw > 0.2:
			var sway := _sway()
			var ok := Combat.fire(p, wid, _eye(), (_aim_dir() + sway).normalized(),
				{"ads": ads > 0.6, "power": draw, "ammo": _pick_arrow()})
			if ok:
				_recoil(0.6)
		draw = 0.0
	if not atk and not _drawing:
		draw = move_toward(draw, 0.0, delta * 5.0)

func _pick_arrow() -> StringName:
	if Combat.ammo_count(p, &"bow", bow_ammo) == 0:
		for a: StringName in [&"arrow", &"arrow_fire"]:
			if Combat.ammo_count(p, &"bow", a) != 0:
				return a
	return bow_ammo

func _toggle_arrows() -> void:
	bow_ammo = &"arrow_fire" if bow_ammo == &"arrow" else &"arrow"
	Events.toast.emit("Стрелы: %s" % Items.item_name(bow_ammo))

func _throw_input(delta: float, atk: bool, atk_up: bool) -> void:
	if atk and Combat.is_ready(p, wid):
		if not _winding:
			_winding = true
			if wid == &"molotov":
				_light_flame()
		windup = minf(windup + delta / 0.8, 1.0)
	if atk_up and _winding:
		_winding = false
		var dir := (_aim_dir() + Vector3.UP * 0.08).normalized()
		var n := Combat.throw_item(p, wid, _eye() + _aim_dir() * 0.2 + cam.global_basis.x * 0.2, dir, maxf(windup, 0.35))
		if n:
			_throw_anim = 1.0
		_clear_flame()
		windup = 0.0

func _spear_input(delta: float, aim: bool, atk_down: bool) -> void:
	if aim:
		windup = minf(windup + delta / 0.6, 1.0)
		if atk_down and windup > 0.3 and Combat.is_ready(p, wid):
			var dir := (_aim_dir() + Vector3.UP * 0.03).normalized()
			if Combat.throw_item(p, wid, _eye() + cam.global_basis.x * 0.25, dir, windup):
				_throw_anim = 1.0
			windup = 0.0
	else:
		windup = move_toward(windup, 0.0, delta * 4.0)

func _light_flame() -> void:
	_clear_flame()
	if _model == null:
		return
	var fm := _model.find_child("Flame", true, false) as Node3D
	if fm:
		_flame = CombatFx.flames(fm, 0.08)
		CombatFx.sound_at(p, "fire_whoosh", fm.global_position, -12.0)

func _clear_flame() -> void:
	if _flame and is_instance_valid(_flame):
		_flame.queue_free()
	_flame = null

func _sway() -> Vector3:
	var k := clampf(_draw_hold / 3.0, 0.0, 1.0)
	return Vector3(_noise.get_noise_1d(_t * 40.0), _noise.get_noise_1d(_t * 40.0 + 100.0), 0.0) * 0.03 * k

# ======================= позы рук =======================

## Положение маркера модели относительно правой руки (в её локальных осях).
func _rel_to_arm(arm: Node3D, marker_name: String) -> Vector3:
	var m := _model.find_child(marker_name, true, false) as Node3D if _model else null
	if m == null:
		return Vector3(0.0, 0.05, -0.2)
	return arm.transform.affine_inverse() * hands.to_local(m.global_position)

func _update_pose(delta: float) -> void:
	if hands == null:
		return
	if wid == &"" or w.type == &"melee" or (wid == &"spear" and windup <= 0.0 and _throw_anim <= 0.0):
		hands.pose_w = move_toward(hands.pose_w, 0.0, delta * 6.0)
		return
	if not _active():
		hands.pose_w = move_toward(hands.pose_w, 0.0, delta * 6.0)
		return
	hands.pose_w = move_toward(hands.pose_w, 1.0, delta * 8.0)
	hands.pose_bob = lerpf(1.0, 0.15, ads)
	var t: StringName = w.type
	match t:
		&"gun", &"crossbow":
			_pose_gun()
		&"bow":
			_pose_bow()
		&"throw":
			_pose_throw()

func _pose_gun() -> void:
	var roll := deg_to_rad(-80.0)
	var pistol := wid == &"pistol"
	# В прицеле предплечье уходит вниз-вправо (а не в камеру); модель повёрнута обратно,
	# чтобы ствол смотрел ровно вперёд.
	var ads_rr := Vector3(deg_to_rad(14.0), deg_to_rad(22.0), roll) if pistol else Vector3(deg_to_rad(10.0), deg_to_rad(24.0), roll)
	var hip_rr := ads_rr + Vector3(deg_to_rad(3.0), deg_to_rad(4.0), 0.0)
	if _model:
		_model.basis = Basis.from_euler(ads_rr).inverse()
	var hip_r := Vector3(0.2, -0.2, -0.4) if pistol else Vector3(0.16, -0.2, -0.28)
	# ПКМ: целик точно по центру экрана
	var sight_rel := _rel_to_arm(hands.right_arm, "Sight")
	var target := Vector3(0.0, -0.004, -0.5) if pistol else Vector3(0.0, -0.01, -0.33)
	var ads_r := target - Basis.from_euler(ads_rr) * sight_rel
	var r := hip_r.lerp(ads_r, smoothstep(0.0, 1.0, ads))
	var rr := hip_rr.lerp(ads_rr, smoothstep(0.0, 1.0, ads))
	# перезарядка
	var rp := _reload_progress()
	if rp < 1.0:
		var lift := smoothstep(0.0, 0.12, rp) * (1.0 - smoothstep(0.88, 1.0, rp))
		if w.type == &"gun":
			# ствол вертикально, дулом вверх — порох, пуля, шомпол
			r = r.lerp(Vector3(0.1, -0.5, -0.38) if not pistol else Vector3(0.08, -0.32, -0.36), lift)
			rr = rr.lerp(Vector3(deg_to_rad(75.0), deg_to_rad(-10.0), roll), lift)
			if not _reload_snd and rp > 0.45:
				_reload_snd = true
				CombatFx.sound_at(p, "ramrod", _eye() + Vector3.DOWN * 0.3, -8.0)
		else:
			# арбалет: носом вниз, крутим ворот
			# (приклад держим подальше от камеры — иначе он закрывает пол-экрана)
			r = r.lerp(Vector3(0.1, -0.42, -0.5), lift)
			rr = rr.lerp(Vector3(deg_to_rad(-22.0), deg_to_rad(-10.0), roll), lift)
	if _fire_anim > 0.0:
		rr.x += deg_to_rad(float(w.get("recoil", 2.0)) * 1.2) * _fire_anim * _fire_anim
	hands.pose_r = r
	hands.pose_rr = rr
	# левая рука — под цевьё (у пистоля — внизу, вне кадра)
	if pistol:
		hands.pose_l = Vector3(-0.3, -0.5, -0.35)
		hands.pose_lr = Vector3.ZERO
		if rp < 1.0:
			var mz := _rel_to_arm(hands.right_arm, "Muzzle")
			var mh := r + Basis.from_euler(rr) * mz
			var stroke := absf(sin(rp * TAU * 3.0)) * smoothstep(0.3, 0.4, rp) * (1.0 - smoothstep(0.75, 0.85, rp))
			hands.pose_l = mh + Vector3(-0.02, 0.05 + 0.08 * stroke, 0.03)
			hands.pose_lr = Vector3(deg_to_rad(-60.0), 0.0, deg_to_rad(60.0))
		return
	var lr := Vector3(deg_to_rad(15.0), deg_to_rad(-25.0), deg_to_rad(75.0))
	var fore := _rel_to_arm(hands.right_arm, "Forend")
	var fh := r + Basis.from_euler(rr) * fore
	var hand_off := Basis.from_euler(lr) * Vector3(0.0, 0.0, -0.075)
	var l := fh - hand_off + Vector3(0.0, -0.035, 0.0)
	if rp < 1.0:
		var lift2 := smoothstep(0.0, 0.12, rp) * (1.0 - smoothstep(0.88, 1.0, rp))
		if w.type == &"gun":
			var mz2 := _rel_to_arm(hands.right_arm, "Muzzle")
			var mh2 := r + Basis.from_euler(rr) * mz2
			var stroke2 := absf(sin(rp * TAU * 3.0)) * smoothstep(0.3, 0.4, rp) * (1.0 - smoothstep(0.78, 0.86, rp))
			var at_muzzle := mh2 + Vector3(-0.03, 0.04 + 0.16 * stroke2, 0.05)
			l = l.lerp(at_muzzle, lift2)
			lr = lr.lerp(Vector3(deg_to_rad(-70.0), 0.0, deg_to_rad(70.0)), lift2)
		else:
			# вращение ворота у приклада
			var ang := rp * TAU * 5.0
			var crank := r + Vector3(-0.12 + cos(ang) * 0.05, 0.02 + sin(ang) * 0.05, 0.06)
			l = l.lerp(crank, lift2)
			lr = lr.lerp(Vector3(0.0, 0.0, deg_to_rad(40.0)), lift2)
	hands.pose_l = l
	hands.pose_lr = lr

func _pose_bow() -> void:
	var k := smoothstep(0.0, 1.0, draw)
	var a := maxf(ads, k * 0.6)
	var sw := _sway()
	# левая — держит лук, вытягивается к центру при натяжении
	hands.pose_l = Vector3(-0.2, -0.22, -0.5).lerp(Vector3(-0.07, -0.085, -0.62), a) + sw
	hands.pose_lr = Vector3(deg_to_rad(4.0), deg_to_rad(8.0), deg_to_rad(80.0))
	# правая — у тетивы, при натяжении к щеке
	var rest := Vector3(0.06, -0.2, -0.46).lerp(Vector3(-0.02, -0.1, -0.5), a)
	hands.pose_r = rest.lerp(Vector3(0.035, -0.085, -0.19), k)
	hands.pose_rr = Vector3(deg_to_rad(10.0), deg_to_rad(-20.0), deg_to_rad(-70.0))

func _pose_throw() -> void:
	var k := smoothstep(0.0, 1.0, windup)
	var th := _throw_anim
	var spear := wid == &"spear"
	var rest_r := Vector3(0.24, -0.27, -0.46)
	var back_r := Vector3(0.3, 0.02, -0.12) if not spear else Vector3(0.3, 0.0, -0.22)
	var r := rest_r.lerp(back_r, k)
	var rr := Vector3(deg_to_rad(-55.0) * k, deg_to_rad(10.0) * k, deg_to_rad(15.0) * k) if not spear else Vector3(deg_to_rad(6.0), 0.0, 0.0) * k
	if th > 0.0:
		# бросок: рука резко вперёд-вниз, потом возвращается
		var f := sin(th * PI) if th < 1.0 else 0.0
		r = rest_r.lerp(Vector3(0.05, -0.15, -0.75), f)
		rr = Vector3(deg_to_rad(40.0) * f, 0.0, 0.0)
	hands.pose_r = r
	hands.pose_rr = rr
	# левая рука вытянута к цели, локоть уходит вниз (иначе рукав торчит в камеру)
	hands.pose_l = Vector3(-0.24, -0.29, -0.48).lerp(Vector3(-0.2, -0.2, -0.62), k)
	hands.pose_lr = Vector3(deg_to_rad(35.0) * k, deg_to_rad(-8.0) * k, deg_to_rad(20.0) * k)

# ======================= детали моделей =======================

func _update_parts() -> void:
	if wid == &"bow" and _bow_fp:
		var top := _bow_fp.get_node_or_null(^"TipTop") as Node3D
		var bot := _bow_fp.get_node_or_null(^"TipBot") as Node3D
		var st := _bow_fp.get_node_or_null(^"StringTop") as Node3D
		var sb := _bow_fp.get_node_or_null(^"StringBot") as Node3D
		var has_arrow := Combat.has_ammo(p, &"bow") and Combat.is_ready(p, wid) and _active()
		# точка натяжения — пальцы правой руки (в осях лука), без стрелы — тетива в покое
		var fingers := (hands.right_arm.get_node(^"Hand") as Node3D).global_transform * Vector3(0.0, -0.012, -0.04)
		var nock_l := _bow_fp.to_local(fingers)
		var brace := Vector3(0.0, 0.0, 0.09)
		var nock := brace.lerp(nock_l, clampf(draw * 1.5, 0.0, 1.0)) if has_arrow else brace
		if st and top:
			CombatModels.place_rod(st, top.position, nock)
		if sb and bot:
			CombatModels.place_rod(sb, bot.position, nock)
		if _arrow_fp:
			_arrow_fp.visible = has_arrow and hands.pose_w > 0.8
			if _arrow_fp.visible:
				var rest := (_bow_fp.get_node(^"Rest") as Node3D).global_position
				var nock_g := _bow_fp.to_global(nock)
				var dirv := (rest - nock_g)
				if dirv.length() > 0.01:
					var xf := Transform3D.IDENTITY
					xf.origin = nock_g
					xf = xf.looking_at(nock_g + dirv.normalized(), cam.global_basis.y)
					_arrow_fp.global_transform = xf
				var rag := _arrow_fp.find_child("Rag", true, false)
				if _pick_arrow() == &"arrow_fire" and _arrow_fp.get_node_or_null(^"Fire") == null:
					var fl := CombatFx.flames(_arrow_fp, 0.06)
					fl.name = "Fire"
					fl.position = Vector3(0, 0, -0.7)
				elif _pick_arrow() != &"arrow_fire" and _arrow_fp.get_node_or_null(^"Fire"):
					_arrow_fp.get_node(^"Fire").queue_free()
				if rag:
					(rag as Node3D).visible = _pick_arrow() == &"arrow_fire"
		if _model:
			_model.visible = false
	elif wid == &"crossbow" and _model:
		var loaded := Combat.is_loaded(p, wid)
		var rp := _reload_progress()
		var tl := _model.get_node_or_null(^"TipL") as Node3D
		var tr := _model.get_node_or_null(^"TipR") as Node3D
		var nut := _model.get_node_or_null(^"Nut") as Node3D
		var rest := _model.get_node_or_null(^"Rest") as Node3D
		if tl and tr and nut and rest:
			var spanned := 1.0 if loaded and rp >= 1.0 else (smoothstep(0.1, 0.85, rp) if Combat.is_reloading(p) else 0.0)
			var pt := rest.position.lerp(nut.position, spanned)
			CombatModels.place_rod(_model.get_node(^"StringL") as Node3D, tl.position, pt)
			CombatModels.place_rod(_model.get_node(^"StringR") as Node3D, tr.position, pt)
		var bolt := _model.get_node_or_null(^"Bolt") as Node3D
		if bolt:
			bolt.visible = loaded and rp > 0.9
	elif wid in [&"musket", &"pistol"]:
		var rp2 := _reload_progress()
		if Combat.is_loaded(p, wid) and rp2 > 0.92:
			_set_cock(true)
		var ramrod := _model.get_node_or_null(^"Ramrod") as Node3D if _model else null
		if ramrod:
			ramrod.visible = rp2 < 0.3 or rp2 > 0.85

func _set_cock(cocked: bool) -> void:
	var c := _model.find_child("Cock", true, false) as Node3D if _model else null
	if c:
		c.rotation.x = deg_to_rad(28.0) if cocked else deg_to_rad(-12.0)

# ======================= камера =======================

func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)

func _update_camera_fx(delta: float) -> void:
	if cam == null:
		return
	_kick = _kick.lerp(Vector2.ZERO, clampf(delta * 9.0, 0.0, 1.0))
	_shake = move_toward(_shake, 0.0, delta * 1.2)
	var s := _shake * _shake
	cam.rotation = Vector3(_kick.x + _noise.get_noise_1d(_t * 90.0) * 0.03 * s, _kick.y + _noise.get_noise_1d(_t * 90.0 + 50.0) * 0.03 * s, 0.0)
	cam.h_offset = _noise.get_noise_1d(_t * 70.0 + 20.0) * 0.05 * s
	cam.v_offset = _noise.get_noise_1d(_t * 70.0 + 80.0) * 0.05 * s

# ======================= интерфейс =======================

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 5
	add_child(_ui)
	_ammo_label = Label.new()
	_ammo_label.anchor_left = 1.0
	_ammo_label.anchor_right = 1.0
	_ammo_label.anchor_top = 1.0
	_ammo_label.anchor_bottom = 1.0
	_ammo_label.offset_left = -360.0
	_ammo_label.offset_right = -24.0
	_ammo_label.offset_top = -120.0
	_ammo_label.offset_bottom = -90.0
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ammo_label.add_theme_color_override(&"font_color", Color(0.95, 0.92, 0.85))
	_ammo_label.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.8))
	_ammo_label.add_theme_font_size_override(&"font_size", 18)
	_ui.add_child(_ammo_label)
	_marker = HitMarker.new()
	_marker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_marker)

func hit_marker(info: Dictionary) -> void:
	if info.get("target") == null:
		return
	(_marker as HitMarker).show_hit(info.get("zone", &"") == &"head")

func _update_ui(_delta: float) -> void:
	if _ammo_label == null:
		return
	_ui.visible = p.alive and not p.ui_open
	if wid == &"" or w.type == &"melee":
		_ammo_label.text = ""
		return
	var txt := String(w.name)
	match w.type:
		&"gun", &"crossbow":
			var st := "перезарядка…" if Combat.is_reloading(p) else ("заряжен" if Combat.is_loaded(p, wid) else "не заряжен (R)")
			var parts := []
			for a: Dictionary in w.ammo:
				parts.append("%s: %d" % [Items.item_name(a.id), BuildEnv.inv_count(p, a.id)])
			txt += " — %s\n%s" % [st, ", ".join(parts)]
		&"bow":
			txt += " — %s: %d  (R — сменить)" % [Items.item_name(_pick_arrow()), max(0, Combat.ammo_count(p, &"bow", _pick_arrow()))]
		&"throw":
			txt += " — %d шт.  %s" % [BuildEnv.inv_count(p, wid), "ПКМ — замах, ЛКМ — бросок" if wid == &"spear" else "держи ЛКМ — замах"]
	_ammo_label.text = txt


class HitMarker:
	extends Control
	var _t := 0.0
	var _head := false
	func show_hit(head: bool) -> void:
		_t = 0.25
		_head = head
		queue_redraw()
	func _process(delta: float) -> void:
		if _t > 0.0:
			_t -= delta
			queue_redraw()
	func _draw() -> void:
		if _t <= 0.0:
			return
		var c := size * 0.5
		var col := Color(1, 0.25, 0.2, _t * 4.0) if _head else Color(1, 1, 1, _t * 4.0)
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(c + d * 6.0, c + d * 14.0, col, 2.0, true)
