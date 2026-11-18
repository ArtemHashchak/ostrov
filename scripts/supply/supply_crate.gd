class_name SupplyCrate
extends StaticBody3D
## Ящик спонсоров: падает на парашюте, приземляется (на воде — плавает и дрейфует к
## берегу), пускает столб цветного дыма (цвет = редкость). Открыть — удерживать E ~3 с
## (урон прерывает); содержимое — в инвентарь открывшего (лишнее падает рядом).
## Группы: supply_crates, interactable. Боты: bot_open(bot) — открывают, стоя рядом.

signal landed(crate: SupplyCrate)
signal opened(crate: SupplyCrate, by: Node)

const OPEN_TIME := 3.0
const FALL_SPEED := 5.5
const W := 1.1
const H := 0.5
const D := 0.62
const SMOKE_AFTER_OPEN := 45.0
const SMOKE_MAX := 420.0
const DESPAWN_AFTER_OPEN := 300.0

enum State { FALLING, LANDED, FLOATING, OPENED }

var tier := 0
var number := 1
var island_name := ""
var loot: Array[Dictionary] = []
var wind := Vector3.ZERO
var state: State = State.FALLING
var opener: Node = null
var open_t := 0.0
var opened_by: Node = null

var _model: Node3D
var _chute: Node3D
var _smoke: Node3D
var _smoke_can: Node3D
var _t := 0.0
var _state_t := 0.0
var _shore := Vector3.ZERO
var _yaw := 0.0

func _ready() -> void:
	add_to_group(&"supply_crates")
	add_to_group(&"interactable")
	collision_layer = 1
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(W, H, D)
	cs.shape = bs
	cs.position = Vector3(0, H * 0.5, 0)
	add_child(cs)
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	SupplyModels.crate(_model, tier, number)
	_chute = Node3D.new()
	_chute.name = "Parachute"
	_chute.position = Vector3(0, H + 4.7, 0)
	add_child(_chute)
	SupplyModels.parachute(_chute, tier)
	_yaw = randf() * TAU
	rotation.y = _yaw
	Events.character_damaged.connect(_on_damaged)

func color() -> Color:
	return SupplyModels.TIER_COLORS[clampi(tier, 0, 2)]

func tier_name() -> String:
	return SupplyModels.TIER_NAMES[clampi(tier, 0, 2)]

func is_available() -> bool:
	return state == State.LANDED or state == State.FLOATING

func is_falling() -> bool:
	return state == State.FALLING

# ------------------------------------------------------------ падение и вода

func _physics_process(delta: float) -> void:
	_t += delta
	_state_t += delta
	match state:
		State.FALLING:
			_fall(delta)
		State.FLOATING:
			_float(delta)
		State.OPENED:
			if _on_water():
				_float(delta)
	_tick_open(delta)
	if _smoke and is_instance_valid(_smoke) and _smoke_can:
		for c in _smoke.get_children():
			if c is CPUParticles3D:
				(c as CPUParticles3D).global_position = _smoke_can.global_position + (c.get_meta(&"off", Vector3.ZERO) as Vector3)
	if state == State.OPENED and _state_t > DESPAWN_AFTER_OPEN:
		queue_free()
	elif state != State.FALLING and state != State.OPENED and _state_t > SMOKE_MAX and _smoke:
		SupplyFx.stop_smoke(_smoke)
		_smoke = null

func _fall(delta: float) -> void:
	var p := global_position
	p.y -= FALL_SPEED * delta
	p += wind * delta
	global_position = p
	# раскачивание под куполом
	_model.rotation = Vector3(sin(_t * 1.3) * 0.08, 0.0, sin(_t * 0.9 + 1.0) * 0.1)
	_chute.rotation = Vector3(sin(_t * 0.7) * 0.05, _t * 0.15, sin(_t * 0.6 + 2.0) * 0.05)
	var gy := BuildEnv.height_at(p.x, p.z)
	var ws := BuildEnv.water_surface(p.x, p.z)
	if gy > ws - 0.35:
		if p.y <= gy + 0.02:
			global_position.y = gy
			_land(false)
	elif p.y <= ws - 0.2:
		_land(true)

func _on_water() -> bool:
	var p := global_position
	return BuildEnv.height_at(p.x, p.z) < BuildEnv.water_surface(p.x, p.z) - 0.35

func _land(water: bool) -> void:
	state = State.FLOATING if water else State.LANDED
	_state_t = 0.0
	_model.rotation = Vector3.ZERO
	if water:
		_shore = _find_shore()
		CombatFx.impact(self, global_position + Vector3.UP * 0.2, Vector3.UP, &"water")
	else:
		CombatFx.particles(get_parent(), global_position + Vector3.UP * 0.1, 18, 1.4, "smoke", false,
			CombatFx._ramp([Color(0.7, 0.62, 0.48, 0.8), Color(0.7, 0.65, 0.55, 0.0)]), 0.6, 2.5, 80.0, Vector3.UP, Vector3(0, -1.0, 0))
		CombatFx.sound_at(self, "hit_wood_big", global_position, 2.0, 80.0)
	_collapse_chute(water)
	# дымовая шашка рядом с ящиком
	_smoke_can = Node3D.new()
	_smoke_can.name = "SmokeCan"
	_smoke_can.position = Vector3(W * 0.5 + 0.9, 0.0 if not water else 0.25, 0.3)
	add_child(_smoke_can)
	if not water:
		var sp := _smoke_can.global_position
		_smoke_can.global_position.y = BuildEnv.height_at(sp.x, sp.z)
	SupplyModels.smoke_can(_smoke_can, tier)
	_smoke = SupplyFx.smoke_column(_smoke_can, color(), wind)
	landed.emit(self)

## Купол оседает и ложится рядом по ветру, через 40 с исчезает.
func _collapse_chute(_water: bool) -> void:
	if _chute == null:
		return
	var side := wind.normalized() if wind.length() > 0.05 else Vector3.RIGHT
	# купол ложится на землю/воду по ветру, смятым «языком» ткани
	var gp := global_position + side * 3.0
	var gy := maxf(BuildEnv.height_at(gp.x, gp.z), BuildEnv.water_surface(gp.x, gp.z)) + 0.06
	var end := global_basis.inverse() * (Vector3(gp.x, gy, gp.z) - global_position)
	var yaw := atan2(side.x, side.z) - rotation.y
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_chute, "position", end, 2.8).set_ease(Tween.EASE_IN)
	tw.tween_property(_chute, "scale", Vector3(0.45, 0.1, 0.8), 2.8).set_ease(Tween.EASE_IN)
	tw.tween_property(_chute, "rotation", Vector3(0.0, yaw, 0.0), 1.5)
	var lines := _chute.get_node_or_null(^"Lines")
	if lines:
		tw.tween_callback(lines.queue_free).set_delay(1.2)
	tw.chain().tween_interval(40.0)
	tw.chain().tween_callback(_chute.queue_free)

## Куда дрейфовать на воде: ближайшая суша (16 направлений, до 70 м).
func _find_shore() -> Vector3:
	var p := global_position
	for r: float in [8.0, 16.0, 26.0, 40.0, 55.0, 70.0]:
		for k in 16:
			var a := TAU * k / 16.0
			var q := p + Vector3(cos(a), 0, sin(a)) * r
			if BuildEnv.height_at(q.x, q.z) > BuildEnv.water_surface(q.x, q.z) - 0.3:
				return q
	return Vector3.INF

func _float(delta: float) -> void:
	var p := global_position
	var ws := BuildEnv.water_surface(p.x, p.z)
	var gy := BuildEnv.height_at(p.x, p.z)
	if _shore != Vector3.INF and gy < ws - 1.1 and state != State.OPENED:
		var d := Vector3(_shore.x - p.x, 0, _shore.z - p.z)
		if d.length() > 0.5:
			p += d.normalized() * 0.35 * delta
	var y := ws - 0.24 + sin(_t * 1.4) * 0.05
	if gy > y - 0.05:
		y = gy + 0.02 # село на мель
	p.y = lerpf(p.y, y, clampf(delta * 3.0, 0.0, 1.0))
	global_position = p
	_model.rotation = Vector3(sin(_t * 1.1) * 0.06, 0.0, sin(_t * 0.8 + 1.0) * 0.07)

# ------------------------------------------------------------ открытие

func get_interact_text(ch: Node) -> String:
	match state:
		State.FALLING:
			return ""
		State.OPENED:
			return "Ящик спонсоров — пусто"
	var nm := "Ящик спонсоров (%s)" % tier_name()
	if opener == ch:
		return "%s — открываю… %d%%  (держи E)" % [nm, int(open_t / OPEN_TIME * 100.0)]
	if opener != null and is_instance_valid(opener):
		return "%s — его открывает %s" % [nm, Game.display_name(opener)]
	return "%s — удерживай E (%d с): вскрыть" % [nm, int(OPEN_TIME)]

func interact(ch: Node) -> void:
	if not is_available():
		return
	if opener != null and is_instance_valid(opener) and opener != ch:
		return
	opener = ch
	open_t = 0.0
	CombatFx.sound_at(self, "hit_metal", global_position + Vector3.UP * 0.4, -12.0)

## Бот начинает/продолжает вскрывать (зовёт каждый «тик» мозга, стоя рядом).
func bot_open(bot: Node) -> void:
	if opener == null or not is_instance_valid(opener):
		interact(bot)

func progress() -> float:
	return clampf(open_t / OPEN_TIME, 0.0, 1.0) if opener else 0.0

func cancel_open(why: String = "") -> void:
	if opener and why != "" and opener.is_in_group(&"player"):
		Events.toast.emit(why)
	opener = null
	open_t = 0.0

func _tick_open(delta: float) -> void:
	if opener == null:
		return
	if not is_instance_valid(opener) or not is_available() or not Game.is_alive(opener):
		cancel_open()
		return
	var o3 := opener as Node3D
	var reach := 3.4 if opener.is_in_group(&"player") else 2.8
	var c := global_position + Vector3.UP * H * 0.5
	if o3.global_position.distance_to(c) > reach + 0.9:
		cancel_open("Слишком далеко от ящика")
		return
	if opener.is_in_group(&"player") and not Input.is_action_pressed(&"interact"):
		cancel_open()
		return
	open_t += delta
	if open_t >= OPEN_TIME:
		_open(opener)

func _on_damaged(ch: Node, amount: float, _src: Node) -> void:
	if ch == opener and amount > 0.5:
		cancel_open("Ранен — вскрытие прервано")

func _open(by: Node) -> void:
	state = State.OPENED
	_state_t = 0.0
	opened_by = by
	opener = null
	open_t = 0.0
	var lid := _model.get_node_or_null(^"Lid") as Node3D
	if lid:
		create_tween().tween_property(lid, "rotation:x", deg_to_rad(105.0), 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var straps := _model.get_node_or_null(^"Straps") as Node3D
	if straps:
		straps.visible = false
	CombatFx.sound_at(self, "hit_metal", global_position + Vector3.UP * 0.4, -4.0)
	var at := global_position + Vector3.UP * 0.9
	var names: PackedStringArray = []
	for s in loot:
		Survival.give(by, StringName(s.id), int(s.n), at)
		names.append("%s ×%d" % [Items.item_name(StringName(s.id)), int(s.n)] if int(s.n) > 1 else Items.item_name(StringName(s.id)))
	if by.is_in_group(&"player"):
		Events.toast.emit("Посылка: " + ", ".join(names))
	opened.emit(self, by)
	var col := _smoke
	_smoke = null
	if col:
		get_tree().create_timer(SMOKE_AFTER_OPEN).timeout.connect(SupplyFx.stop_smoke.bind(col))

## Метка на мини-карте (Supply.map_markers).
func marker() -> Dictionary:
	return {"pos": global_position, "color": color(), "kind": &"crate" if not is_falling() else &"falling", "label": "Посылка"}
