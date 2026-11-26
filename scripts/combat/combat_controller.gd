class_name CombatController
extends Node
## Оружие игрока (вешается модулем Combat ребёнком игрока; ввод получает раньше игрока).
##  Огнестрел/арбалет: ЛКМ — выстрел (пусто — перезарядка), ПКМ — прицел (целик по центру, FOV↓),
##    R — перезарядка: порох + пуля (мушкет ~5.5 с, шомпол), арбалет — болт (ворот ~3.2 с).
##  Лук: держать ЛКМ — натянуть (сила от натяжения), отпустить — выстрел; ПКМ — прицел; R — тип стрел.
##  Молотов/динамит: держать ЛКМ — замах (сила), отпустить — бросок.
##  Копьё: ЛКМ — выпад (анимация игрока); держать ПКМ — замах над плечом, ЛКМ — бросок.
##  Дубина/топоры — удары игрока (урон из Items).
##  Современный огнестрел (WeaponDef: пистолет, автомат): ЛКМ — выстрел (авто — держать),
##    V — режим огня, ПКМ — прицел (ads_anchor в центр экрана, FOV↓, разброс↓), R — перезарядка
##    (тактическая/полная). Отдача по паттерну с возвратом (Gunplay), пружина камеры, гильзы,
##    вспышка, дымок нагретого ствола, HUD «в магазине / в запасе», динамический прицел.

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
# --- современный огнестрел (WeaponDef) ---
var wdef: WeaponDef
var gp: Gunplay
var _prev_mode := false
var _barrel_smoke: CPUParticles3D
var _slide := 0.0
var _reload_stage := 0
## Подвижные детали (WeaponDef: BoltCarrier/Slide, Trigger, Selector, Magazine): спуск 0..1,
## угол переводчика (плавно к углу режима), исходные позиции/повороты деталей модели.
var _trig := 0.0
var _trig_held := false
var _sel_deg := 0.0
var _sel_init := false
var _rest: Dictionary = {}
## Прицеливание в режиме «переключать» (Settings.aim_toggle): защёлка.
var _aim_latched := false
## Износ (GearWear): ствол заклинило — до перезарядки (R) не стреляет; пауза после осечки.
var _jammed := false
var _wear_block_until := 0.0
var _mag_label: Label
var _cross: Control
## Текущий разброс (град) — для HUD и тестов.
var spread_now := 0.0

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
	elif wdef and InputMap.has_action(&"fire_mode") and event.is_action(&"fire_mode"):
		get_viewport().set_input_as_handled()

# ======================= кадр =======================

func _process(delta: float) -> void:
	if p == null:
		return
	_t += delta
	_sync_weapon()
	var active := _active() and wid != &""
	var atk := Input.is_action_pressed(&"attack") and active
	var aim_raw := Input.is_action_pressed(&"aim") and active
	var aim := aim_raw
	if Settings.aim_toggle:
		# «переключать»: одно нажатие — в прицел, ещё одно — из прицела (тачпад MacBook:
		# нельзя одновременно держать нажатие двумя пальцами и кликать)
		if aim_raw and not _prev_aim:
			_aim_latched = not _aim_latched
		if not active:
			_aim_latched = false
		aim = _aim_latched and active
	var rel := InputMap.has_action(&"reload") and Input.is_action_pressed(&"reload") and active
	var atk_down := atk and not _prev_atk
	var atk_up := not atk and _prev_atk
	var rel_down := rel and not _prev_reload
	var mode := InputMap.has_action(&"fire_mode") and Input.is_action_pressed(&"fire_mode") and active
	var mode_down := mode and not _prev_mode
	_prev_mode = mode
	_prev_atk = atk
	_prev_aim = aim_raw
	_trig_held = atk and wdef != null
	_prev_reload = rel
	var want_ads := false
	if active:
		match &"modern" if wdef else StringName(w.type):
			&"modern":
				want_ads = aim and not Combat.is_reloading(p) and not p.sprinting
				var auto := Combat.fire_mode(p, wid) == &"auto"
				if atk_down or (atk and auto and Combat.rounds(p, wid) > 0):
					# очередь: при низком FPS — несколько выстрелов за кадр (темп по часам Combat)
					var n := 0
					while _trigger_modern(atk_down and n == 0) and auto and n < 3:
						n += 1
				if rel_down:
					_start_reload()
				if mode_down:
					_cycle_mode()
			&"gun", &"crossbow":
				want_ads = aim and not Combat.is_reloading(p) and not p.sprinting
				# SUPPLY: автомат — очередь, пока зажата ЛКМ
				if atk_down or (atk and w.get("auto", false) and Combat.is_loaded(p, wid)):
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
	if wdef:
		ads = move_toward(ads, 1.0 if want_ads else 0.0, delta / maxf(wdef.ads_time, 0.05) * (1.0 if want_ads else 1.3))
	else:
		ads = move_toward(ads, 1.0 if want_ads else 0.0, delta * (6.0 if want_ads else 8.0))
	if gp:
		spread_now = gp.spread(smoothstep(0.0, 1.0, ads), Vector2(p.velocity.x, p.velocity.z).length() / Player.RUN_SPEED,
			p.is_on_floor(), p.crouching)
		var dl := gp.update(delta)
		if dl != Vector2.ZERO:
			var yaw: float = p.get(&"_yaw")
			var pitch: float = p.get(&"_pitch")
			p.set_look(yaw + dl.y, clampf(pitch + dl.x, deg_to_rad(-88.0), deg_to_rad(88.0)))
	var zoom := float(w.get("zoom", 0.0)) if wid != &"" else 0.0
	p.fov_zoom = zoom * smoothstep(0.0, 1.0, ads)
	_hunger_sway(delta)
	_glint(delta, zoom)
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
		wdef = WeaponDef.of(id)
		gp = Gunplay.new(wdef) if wdef else null
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
	if is_instance_valid(_barrel_smoke):
		_barrel_smoke.queue_free()
	_barrel_smoke = null
	gp = null
	wdef = null
	_aim_latched = false
	_jammed = false
	_rest.clear()
	_sel_init = false
	_trig = 0.0
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
	_rest.clear()
	_sel_init = false
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
	var m := WeaponDef.socket(_model, &"muzzle")
	return m.global_position if m else _eye() + _aim_dir() * 0.8

## Сокет модели в руке: muzzle / ejection_port / ads_anchor / mag / forend.
func socket(socket_name: StringName) -> Node3D:
	return WeaponDef.socket(_model, socket_name)

# ---------- современный огнестрел ----------

func _trigger_modern(pressed: bool) -> bool:
	if Combat.fire_mode(p, wid) == &"safe":
		# на предохранителе спуск не идёт: глухой щелчок пальца по спуску
		if pressed:
			CombatFx.sound_at(p, wdef.sound_dry, _eye() + Vector3.DOWN * 0.3, -18.0)
		return false
	if not Combat.is_ready(p, wid) or Combat.is_reloading(p):
		return false
	if Combat.rounds(p, wid) <= 0:
		if pressed:
			CombatFx.sound_at(p, wdef.sound_dry, _eye(), -6.0)
			_start_reload()
		return false
	if not _wear_ok(pressed, wdef.ammo_id):
		return false
	var mz := socket(&"muzzle")
	var ok := Combat.fire(p, wid, _eye(), _aim_dir(), {"ads": ads > 0.7, "spread": spread_now,
		"muzzle": mz.global_position if mz else _eye() + _aim_dir() * 0.8, "muzzle_node": mz})
	if not ok:
		return false
	gp.on_shot(smoothstep(0.0, 1.0, ads))
	_fire_anim = 1.0
	_slide = 1.0
	_eject()
	return true

## Гильза и газы из окна выброса.
func _eject() -> void:
	var port := socket(&"ejection_port")
	var b := cam.global_basis
	var xf := port.global_transform if port else Transform3D(b, _eye() + b * Vector3(0.12, -0.1, -0.35))
	GunFx.eject_casing(p, xf, b.x, b.y, b.z, p.velocity, wdef)
	GunFx.port_gas(p, xf.origin, b.x, wdef.smoke)

## Голод — прицел «плавает» (сильнее в прицеле): медленный шум взгляда, когда сытость < 40.
var _sway_t := 0.0
var _sway_prev := Vector2.ZERO
func _hunger_sway(delta: float) -> void:
	if wid == &"" or p.hunger >= 40.0:
		_sway_prev = Vector2.ZERO
		return
	_sway_t += delta
	var k := (1.0 - p.hunger / 40.0) * deg_to_rad(DataTables.f("balance", "weapons/hunger_sway_deg", 1.6)) * lerpf(0.5, 1.0, ads)
	var cur := Vector2(sin(_sway_t * 1.3) + 0.5 * sin(_sway_t * 2.9), cos(_sway_t * 1.1) + 0.4 * sin(_sway_t * 3.7)) * k * 0.5
	var d := cur - _sway_prev
	_sway_prev = cur
	p.set_look(float(p.get(&"_yaw")) + d.x, clampf(float(p.get(&"_pitch")) + d.y, deg_to_rad(-88.0), deg_to_rad(88.0)))

## Блик оптики: в прицеле с увеличением при солнце над горизонтом — раздражитель «glint»
## для соперников (видят издалека), раз в секунду. Сила — свойство glint предмета.
var _glint_t := 0.0
func _glint(delta: float, zoom: float) -> void:
	if ads < 0.8 or zoom < 15.0:
		return
	_glint_t += delta
	if _glint_t < 1.0:
		return
	_glint_t = 0.0
	var wn := BuildEnv.world()
	var sun := float(wn.call(&"sun_elevation")) if wn and wn.has_method(&"sun_elevation") else 0.0
	if rad_to_deg(asin(clampf(sun, -1.0, 1.0))) < DataTables.f("balance", "weapons/glint_min_sun_elev", 8.0):
		return
	var g := maxf(float(Materials.prop(wid, "glint", 0.0)), 0.5 if zoom >= 20.0 else 0.0)
	var pc := get_node_or_null(^"/root/Perception")
	if pc and g > 0.0:
		pc.call(&"emit", &"glint", _eye(), DataTables.f("balance", "weapons/glint_radius", 600.0) * g, g, p)

## Износ и отсыревший порох (GearWear): осечка, заклинивание, поломка. false — выстрела нет.
func _wear_ok(pressed: bool, ammo_id: StringName) -> bool:
	if _jammed:
		if pressed:
			CombatFx.sound_at(p, "dry_click", _eye(), -10.0)
			Events.toast.emit("Заклинило — перезарядка (R)")
		return false
	if Combat._now() < _wear_block_until:
		return false
	match GearWear.fire_check(p, wid, ammo_id):
		&"broken":
			if pressed:
				CombatFx.sound_at(p, "dry_click", _eye(), -10.0)
				Events.toast.emit("Оружие сломано — ржавчина и соль")
			return false
		&"jam":
			_jammed = true
			CombatFx.sound_at(p, "dry_click", _eye(), -6.0)
			Events.toast.emit("Заклинило — перезарядка (R)")
			return false
		&"misfire":
			_wear_block_until = Combat._now() + 0.35
			CombatFx.sound_at(p, "dry_click", _eye(), -6.0)
			Events.toast.emit("Осечка")
			return false
	return true

func _cycle_mode() -> void:
	if wdef.fire_modes.size() < 2:
		return
	var m := Combat.cycle_fire_mode(p, wid)
	CombatFx.sound_at(p, wdef.sound_mode, _eye() + Vector3.DOWN * 0.3, -10.0)
	Events.toast.emit("Режим огня: %s" % mode_name(m))

static func mode_name(m: StringName) -> String:
	match m:
		&"auto":
			return "автоматический"
		&"safe":
			return "предохранитель"
	return "одиночный"

func _trigger() -> void:
	if not Combat.is_ready(p, wid):
		return
	if Combat.is_loaded(p, wid) and w.type == &"gun" and not _wear_ok(true, &"gunpowder"):
		return
	if Combat.is_loaded(p, wid):
		var ok := Combat.fire(p, wid, _eye(), _aim_dir(), {"ads": ads > 0.7, "muzzle": _muzzle_pos()})
		if ok:
			_recoil(float(w.get("recoil", 2.0)))
			_set_cock(false)
	else:
		_start_reload()

func _start_reload() -> void:
	if Combat.is_reloading(p):
		return
	if _jammed:
		# перезарядка устраняет заклинивание (снять магазин, передёрнуть затвор)
		_jammed = false
	if w.has("mag"):
		if Combat.rounds(p, wid) >= Combat.capacity(p, wid):
			return
	elif Combat.is_loaded(p, wid):
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
	_reload_stage = 0
	if wdef:
		CombatFx.sound_at(p, wdef.sound_reload, _eye() + Vector3.DOWN * 0.4, -16.0) # магазин из шахты
		return
	if w.has("mag"):
		CombatFx.sound_at(p, "hit_metal", _eye() + Vector3.DOWN * 0.4, -14.0)
		return
	CombatFx.sound_at(p, "crossbow_crank" if w.type == &"crossbow" else "ramrod", _eye() + Vector3.DOWN * 0.4, -6.0)

func _reload_progress() -> float:
	if not Combat.is_reloading(p) or _reload_len <= 0.0:
		return 1.0
	var st := Combat.state(p)
	return clampf(1.0 - (float(st.reload_end) - Combat._now()) / _reload_len, 0.0, 1.0)

func _recoil(deg: float) -> void:
	deg *= Gunplay.RECOIL_MULT
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
	var m := WeaponDef.socket(_model, StringName(marker_name.to_snake_case()))
	if m == null and _model:
		m = _model.find_child(marker_name, true, false) as Node3D
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

## Кривая входа в прицел: smootherstep (нулевые скорость и ускорение на концах).
static func _ease_ads(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * x * (x * (x * 6.0 - 15.0) + 10.0)

func _pose_gun() -> void:
	var roll := deg_to_rad(-80.0)
	var pistol := wid == &"pistol" or bool(w.get("pistol", false))
	var mag: bool = w.has("mag") # SUPPLY: магазинное оружие
	# В прицеле предплечье уходит вниз-вправо (а не в камеру); модель повёрнута обратно,
	# чтобы ствол смотрел ровно вперёд.
	var ads_rr := Vector3(deg_to_rad(14.0), deg_to_rad(22.0), roll) if pistol else Vector3(deg_to_rad(10.0), deg_to_rad(24.0), roll)
	var hip_rr := ads_rr + Vector3(deg_to_rad(3.0), deg_to_rad(4.0), 0.0)
	if _model:
		_model.basis = Basis.from_euler(ads_rr).inverse()
	var hip_r := Vector3(0.2, -0.2, -0.4) if pistol else Vector3(0.16, -0.2, -0.28)
	# ПКМ: целик точно по центру экрана (WeaponDef — сокет ads_anchor на ads_distance перед камерой)
	var sight_rel := _rel_to_arm(hands.right_arm, "ads_anchor" if wdef else "Sight")
	# мушкет/арбалет: целик на ~0.48 м — правая кисть у шейки приклада не лезет в центр
	# кадра (было 0.33: кисть в 15 см от глаза закрывала пол-экрана)
	var target := Vector3(0.0, -0.004, -0.5) if pistol else Vector3(0.0, -0.01, -0.48)
	if wdef:
		target = Vector3(0.0, 0.0, -wdef.ads_distance)
	var ads_r := target - Basis.from_euler(ads_rr) * sight_rel
	# плавный вход в прицел: «smootherstep» без рывка на концах + лёгкий провал/крен оружия в середине пути
	var ae := _ease_ads(ads)
	var r := hip_r.lerp(ads_r, ae)
	var rr := hip_rr.lerp(ads_rr, ae)
	var mid := sin(ae * PI)
	r += Vector3(0.006, -0.012, 0.0) * mid
	rr.z += deg_to_rad(-4.0) * mid
	# перезарядка
	var rp := _reload_progress()
	if rp < 1.0:
		var lift := smoothstep(0.0, 0.18, rp) * (1.0 - smoothstep(0.8, 1.0, rp))
		if mag:
			# магазин: оружие наклонено к себе боком, левая рука меняет магазин
			r = r.lerp(Vector3(0.08, -0.3, -0.36) if not pistol else Vector3(0.06, -0.26, -0.36), lift)
			rr = rr.lerp(Vector3(deg_to_rad(18.0), deg_to_rad(-25.0), roll + deg_to_rad(35.0)), lift)
			if not _reload_snd and rp > 0.7 and not wdef:
				_reload_snd = true
				CombatFx.sound_at(p, "dry_click", _eye() + Vector3.DOWN * 0.3, -4.0)
		elif w.type == &"gun":
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
	if gp:
		# откат и подброс оружия — пружина Gunplay (в прицеле слабее)
		var kk := gp.gun_kick * lerpf(1.0, 0.6, ads)
		r += Vector3(0.0, 0.004, wdef.kick_back) * kk
		rr.x += deg_to_rad(wdef.kick_rot) * kk
	elif _fire_anim > 0.0:
		rr.x += deg_to_rad(float(w.get("recoil", 2.0)) * 1.2) * _fire_anim * _fire_anim
	hands.pose_r = r
	hands.pose_rr = rr
	# левая рука — под цевьё (у пистоля — внизу, вне кадра)
	if pistol:
		hands.pose_l = Vector3(-0.3, -0.5, -0.35)
		hands.pose_lr = Vector3.ZERO
		if rp < 1.0 and not mag:
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
		var lift2 := smoothstep(0.0, 0.18, rp) * (1.0 - smoothstep(0.8, 1.0, rp))
		if mag:
			# рука к магазину → вниз (новый из подсумка) → обратно
			var mg := _rel_to_arm(hands.right_arm, "Mag")
			var mgh := r + Basis.from_euler(rr) * mg
			var away := smoothstep(0.25, 0.4, rp) * (1.0 - smoothstep(0.55, 0.7, rp))
			var at_mag := mgh + Vector3(-0.02, -0.03, 0.02) + Vector3(-0.08, -0.22, 0.08) * away
			l = l.lerp(at_mag, lift2)
			lr = lr.lerp(Vector3(deg_to_rad(10.0), 0.0, deg_to_rad(60.0)), lift2)
		elif w.type == &"gun":
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
	elif wdef and _model:
		_update_modern_parts()
	elif wid in [&"musket", &"pistol"]:
		var rp2 := _reload_progress()
		if Combat.is_loaded(p, wid) and rp2 > 0.92:
			_set_cock(true)
		var ramrod := _model.get_node_or_null(^"Ramrod") as Node3D if _model else null
		if ramrod:
			ramrod.visible = rp2 < 0.3 or rp2 > 0.85

## Затвор/кожух, магазин при перезарядке, дымок ствола, звуки перезарядки по стадиям.
func _update_modern_parts() -> void:
	var dt := get_process_delta_time()
	var empty := Combat.rounds(p, wid) <= 0 and not Combat.is_reloading(p)
	_slide = move_toward(_slide, 0.0, dt / maxf(wdef.bolt_cycle, 0.01))
	var rp := _reload_progress()
	var full := bool(Combat.state(p).get("reload_full", false))
	var reloading := Combat.is_reloading(p)
	# затвор: откат на выстреле; пустым — на задержке (если она есть у этого ствола);
	# при полной перезарядке (charge_on_empty) — отвести и отпустить в конце
	var back := sin(_slide * PI) * wdef.bolt_travel
	if wdef.bolt_hold_open and (empty or (reloading and full and rp < 0.85)):
		back = wdef.bolt_travel * 0.85
	elif wdef.charge_on_empty and reloading and full:
		back = maxf(back, wdef.bolt_travel * smoothstep(0.72, 0.82, rp) * (1.0 - smoothstep(0.88, 0.91, rp)))
	for nm: String in [wdef.bolt_node, wdef.charging_node]:
		var bn := _part(nm)
		if bn:
			bn.position = _rest_xf(bn).origin + Vector3(0.0, 0.0, back)
	# спуск: тянется, пока зажата атака (на предохранителе — упирается)
	var safe := Combat.fire_mode(p, wid) == &"safe"
	_trig = move_toward(_trig, (0.25 if safe else 1.0) if _trig_held else 0.0, dt / 0.05)
	var tg := _part(wdef.trigger_node)
	if tg:
		tg.basis = _rest_xf(tg).basis * Basis(Vector3.RIGHT, deg_to_rad(wdef.trigger_pull_deg) * _trig)
	# переводчик: к углу режима
	var sel := _part(wdef.selector_node)
	if sel and not wdef.selector_deg.is_empty():
		var target := float(wdef.selector_deg.get(Combat.fire_mode(p, wid), 0.0))
		if not _sel_init:
			_sel_deg = target
			_sel_init = true
		_sel_deg = move_toward(_sel_deg, target, dt * 400.0)
		sel.basis = _rest_xf(sel).basis * Basis(Vector3.RIGHT, deg_to_rad(_sel_deg))
	# магазин: качнуть вперёд и вынуть, новый — тем же путём обратно
	var mg := _part(wdef.mag_node)
	if mg:
		var rock := 0.0
		var away := 0.0
		if reloading and rp < 1.0:
			if rp < 0.4:
				rock = smoothstep(0.1, 0.2, rp)
				away = smoothstep(0.18, 0.32, rp)
			else:
				away = 1.0 - smoothstep(0.42, 0.54, rp)
				rock = 1.0 - smoothstep(0.54, 0.62, rp)
		var r0 := _rest_xf(mg)
		mg.transform = Transform3D(r0.basis * Basis(Vector3.RIGHT, deg_to_rad(wdef.mag_rock_deg) * rock),
			r0.origin + wdef.mag_drop * away)
		mg.visible = away < 0.95
	if Combat.is_reloading(p):
		if _reload_stage == 0 and rp > 0.62:
			_reload_stage = 1
			CombatFx.sound_at(p, "dry_click", _eye() + Vector3.DOWN * 0.3, -4.0) # магазин встал
		elif _reload_stage == 1 and rp > 0.86 and full:
			_reload_stage = 2
			CombatFx.sound_at(p, wdef.sound_reload, _eye() + Vector3.DOWN * 0.3, -12.0) # затвор
	# дымок нагретого ствола после очереди
	if gp:
		var mz := socket(&"muzzle")
		if not is_instance_valid(_barrel_smoke) and mz:
			_barrel_smoke = GunFx.barrel_smoke(mz)
		if is_instance_valid(_barrel_smoke):
			var since := gp.t - gp.last_shot_t
			_barrel_smoke.emitting = gp.heat > 0.25 and since > 0.15
			_barrel_smoke.color = Color(1, 1, 1, clampf(gp.heat, 0.0, 1.0))

## Подвижная деталь модели по имени (WeaponDef: bolt_node и т. п.), null — нет такой.
func _part(nm: String) -> Node3D:
	if nm == "" or _model == null:
		return null
	return _model.find_child(nm, true, false) as Node3D

## Исходный transform детали (запоминается при первом обращении к модели).
func _rest_xf(n: Node3D) -> Transform3D:
	var id := n.get_instance_id()
	if not _rest.has(id):
		_rest[id] = n.transform
	return _rest[id]

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
	var gk := gp.kick if gp else Vector3.ZERO
	cam.rotation = Vector3(_kick.x + gk.x + _noise.get_noise_1d(_t * 90.0) * 0.03 * s,
		_kick.y + gk.y + _noise.get_noise_1d(_t * 90.0 + 50.0) * 0.03 * s, gk.z)
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
	# GUNPLAY: «в магазине / в запасе» крупно и динамический прицел по разбросу
	_mag_label = Label.new()
	_mag_label.anchor_left = 1.0
	_mag_label.anchor_right = 1.0
	_mag_label.anchor_top = 1.0
	_mag_label.anchor_bottom = 1.0
	_mag_label.offset_left = -360.0
	_mag_label.offset_right = -24.0
	_mag_label.offset_top = -176.0
	_mag_label.offset_bottom = -122.0
	_mag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mag_label.add_theme_color_override(&"font_color", Color(0.97, 0.95, 0.88))
	_mag_label.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.85))
	_mag_label.add_theme_font_size_override(&"font_size", 40)
	_ui.add_child(_mag_label)
	_cross = SpreadCross.new()
	_cross.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_cross)
	_marker = HitMarker.new()
	_marker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_marker)

func hit_marker(info: Dictionary) -> void:
	if info.get("target") == null:
		return
	var t: Variant = info.get("target")
	var killed := false
	if t is Object and is_instance_valid(t):
		var o := t as Object
		if &"alive" in o:
			killed = not bool(o.get(&"alive"))
		elif &"hp" in o:
			killed = float(o.get(&"hp")) <= 0.0
		elif &"health" in o:
			killed = float(o.get(&"health")) <= 0.0
	(_marker as HitMarker).show_hit(info.get("zone", &"") == &"head", killed, info.get("zone", &"") == &"structure")

func _update_ui(_delta: float) -> void:
	if _ammo_label == null:
		return
	_ui.visible = p.alive and not p.ui_open
	_mag_label.text = ""
	var sc := _cross as SpreadCross
	sc.px = -1.0
	sc.queue_redraw()
	if wid == &"" or w.type == &"melee":
		_ammo_label.text = ""
		return
	if wdef:
		var mag := Combat.rounds(p, wid)
		var reserve := BuildEnv.inv_count(p, wdef.ammo_id)
		_mag_label.text = "%d / %d" % [mag, reserve]
		_mag_label.modulate = Color(1.0, 0.45, 0.35) if mag == 0 else (Color(1.0, 0.85, 0.5) if mag <= int(wdef.mag_size * 0.25) else Color.WHITE)
		var st2 := "перезарядка…" if Combat.is_reloading(p) else ("пусто — R" if mag == 0 and reserve > 0 else ("нет патронов" if mag == 0 else ""))
		var modes := "" if wdef.fire_modes.size() < 2 else "  [%s — V]" % {&"auto": "АВТО", &"safe": "ПРЕДОХР."}.get(Combat.fire_mode(p, wid), "ОДИН.")
		_ammo_label.text = "%s%s\nв магазине / в запасе (%s)%s" % [w.name, modes, Items.item_name(wdef.ammo_id), ("  · " + st2) if st2 != "" else ""]
		# прицел: зазор по разбросу (в прицеле — не нужен)
		if cam and ads < 0.5:
			var half_h := get_viewport().get_visible_rect().size.y * 0.5
			sc.px = tan(deg_to_rad(spread_now)) / tan(deg_to_rad(cam.fov * 0.5)) * half_h
		return
	var txt := String(w.name)
	match w.type:
		&"gun", &"crossbow":
			var st := "перезарядка…" if Combat.is_reloading(p) else ("заряжен" if Combat.is_loaded(p, wid) else "не заряжен (R)")
			if w.has("mag") and not Combat.is_reloading(p):
				st = "%d / %d%s" % [Combat.rounds(p, wid), int(w.mag), "  (R — перезарядить)" if Combat.rounds(p, wid) == 0 else ""]
			var parts := []
			for a: Dictionary in w.ammo:
				parts.append("%s: %d" % [Items.item_name(a.id), BuildEnv.inv_count(p, a.id)])
			txt += " — %s\n%s" % [st, ", ".join(parts)]
		&"bow":
			txt += " — %s: %d  (R — сменить)" % [Items.item_name(_pick_arrow()), max(0, Combat.ammo_count(p, &"bow", _pick_arrow()))]
		&"throw":
			txt += " — %d шт.  %s" % [BuildEnv.inv_count(p, wid), "ПКМ — замах, ЛКМ — бросок" if wid == &"spear" else "держи ЛКМ — замах"]
	_ammo_label.text = txt


## Четыре чёрточки вокруг центра — зазор = текущий разброс (px < 0 — скрыт).
class SpreadCross:
	extends Control
	var px := -1.0
	func _draw() -> void:
		if px < 0.0:
			return
		var c := size * 0.5
		var g := clampf(px, 4.0, 160.0)
		for d: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			draw_line(c + d * (g + 1.0), c + d * (g + 9.0), Color(0, 0, 0, 0.5), 3.0, true)
			draw_line(c + d * g, c + d * (g + 8.0), Color(1, 0.98, 0.92, 0.85), 1.5, true)


class HitMarker:
	## Отметка попадания: чёткий «X» из 4 штрихов с тёмной обводкой у центра экрана.
	## Обычное попадание — белый, короткий (0,16 с); в голову — жёлто-оранжевый, крупнее;
	## убийство — красный, крупнее и дольше (0,4 с); по постройке — маленький серый.
	## Появляется с «толчком» (шире → на место) и быстро гаснет.
	extends Control
	var _t := 0.0
	var _dur := 0.16
	var _kind := 0 # 0 тело, 1 голова, 2 убийство, 3 постройка
	func show_hit(head: bool, killed: bool = false, structure: bool = false) -> void:
		_kind = 2 if killed else (1 if head else (3 if structure else 0))
		_dur = [0.16, 0.22, 0.4, 0.12][_kind]
		_t = _dur
		queue_redraw()
	func _process(delta: float) -> void:
		if _t > 0.0:
			_t -= delta
			queue_redraw()
	func _draw() -> void:
		if _t <= 0.0:
			return
		var k := clampf(_t / _dur, 0.0, 1.0)          # 1 → 0
		var age := 1.0 - k
		var pop := 1.0 + 0.35 * maxf(0.0, 1.0 - age * 6.0) # толчок первые ~15% времени
		var a := clampf(k * 2.5, 0.0, 1.0)              # держится, потом гаснет
		var col: Color = [Color(1, 1, 1), Color(1.0, 0.78, 0.25), Color(1.0, 0.22, 0.18), Color(0.75, 0.75, 0.75)][_kind]
		col.a = a
		var r0: float = [7.0, 8.0, 8.0, 6.0][_kind] * pop
		var r1: float = [15.0, 18.0, 21.0, 11.0][_kind] * pop
		var w: float = [2.0, 2.4, 3.0, 1.6][_kind]
		var c := size * 0.5
		for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var dn := d.normalized()
			draw_line(c + dn * (r0 - 1.0), c + dn * (r1 + 1.0), Color(0, 0, 0, 0.55 * a), w + 2.0, true)
			draw_line(c + dn * r0, c + dn * r1, col, w, true)
