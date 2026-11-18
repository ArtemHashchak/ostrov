class_name SupplyController
extends Node
## Предметы «из внешнего мира» у игрока (вешает Supply ребёнком игрока; ввод получает
## раньше игрока, как CombatController):
##   Газовая горелка: ЛКМ (держать) — факел, поджигает постройки/мосты/костры, жжёт;
##     ПКМ — вскипятить морскую воду (нужен котелок) или пожарить еду без костра. Газ — баллоны.
##   Бензопила: ЛКМ (держать) — пилит деревья/стволы ~в 2,5 раза быстрее топора; бензин — канистры.
##   Бинокль: держать ПКМ — приближение ×6.  Фонарик: ПКМ — вкл/выкл.
##   Рация: ПКМ — эфир (когда и где следующий сброс); в инвентаре — метка сброса на карте.
##   Ласты (в инвентаре): плавание ×1.45.  Бронежилет (в инвентаре): Supply.filter_damage.

const TORCH_REACH := 1.9
const SAW_REACH := 2.3
const SAW_TICK := 0.2
const SAW_TREE_DMG := 18.0   # «урон топора» за тик пилы (ChoppableTree.tree_damage → ≈28 по стволу)
const SAW_FLESH_DMG := 7.0
const TORCH_TICK := 0.25
const TORCH_IGNITE := 1.0    # сек факела по дереву постройки до возгорания
const BOIL_TIME := 8.0
const COOK_TIME := 6.0
const ZOOM := 58.0
const SWIM_MUL := 1.45

var p: Player
var held: StringName = &""
var job: Dictionary = {}       # горелка: {kind: &"boil"|&"cook", t, total, id}

var _light: SpotLight3D
var _light_on := false
var _flame: Node3D
var _motor: SupplyFx.Motor
var _tick := 0.0
var _heat := 0.0
var _heat_target: Node = null
var _zoom := 0.0
var _hands_hidden := false
var _no_fuel_t := 0.0
var _ui: CanvasLayer
var _label: Label
var _bar: ProgressBar
var _bar_label: Label
var _scope: Control

func _ready() -> void:
	process_priority = 10 # после CombatController: бинокль перекрывает его fov_zoom
	p = get_parent() as Player
	if p == null:
		return
	_build_ui()

func _active() -> bool:
	return p != null and p.alive and p.input_enabled and not p.ui_open and not get_tree().paused \
		and not p.carrying_log and not p.swimming

func _unhandled_input(event: InputEvent) -> void:
	if p == null or not _active():
		return
	var id := p.held_item()
	match id:
		&"gas_torch":
			if event.is_action(&"attack"):
				get_viewport().set_input_as_handled()
			elif event.is_action_pressed(&"aim"):
				get_viewport().set_input_as_handled()
				torch_use()
		&"chainsaw":
			if event.is_action(&"attack"):
				get_viewport().set_input_as_handled()
			elif event.is_action_pressed(&"aim"):
				get_viewport().set_input_as_handled()
				Events.toast.emit("Бензопила: держи ЛКМ у ствола. Бензин: %s" % _fuel_text(&"fuel_can"))
		&"binoculars":
			if event.is_action(&"aim"):
				get_viewport().set_input_as_handled()
		&"flashlight":
			if event.is_action_pressed(&"aim"):
				get_viewport().set_input_as_handled()
				_light_on = not _light_on
				CombatFx.sound_at(p, "dry_click", p.get_eye_position(), -12.0)
		&"radio":
			if event.is_action_pressed(&"aim"):
				get_viewport().set_input_as_handled()
				var s := Supply.instance()
				Events.toast.emit(s.radio_text(p) if s else "Рация: помехи")
				CombatFx.sound_at(p, "dry_click", p.get_eye_position(), -14.0)
		&"fins", &"armor_vest":
			if event.is_action_pressed(&"aim"):
				get_viewport().set_input_as_handled()
				Events.toast.emit("%s работает, пока лежит в инвентаре" % Items.item_name(id))

# ======================= кадр =======================

func _process(delta: float) -> void:
	if p == null:
		return
	var id := p.held_item() if p.alive else &""
	if id != held:
		_on_switch(held, id)
		held = id
	var active := _active()
	var atk := active and Input.is_action_pressed(&"attack")
	var aim := active and Input.is_action_pressed(&"aim")
	# ласты
	p.set(&"swim_mul", SWIM_MUL if p.inventory and p.inventory.count(&"fins") > 0 else 1.0)
	# фонарик
	if _light:
		_light.visible = held == &"flashlight" and _light_on and p.alive
	# бинокль
	_zoom = move_toward(_zoom, 1.0 if (held == &"binoculars" and aim) else 0.0, delta * 5.0)
	if _zoom > 0.0:
		p.fov_zoom = maxf(p.fov_zoom, ZOOM * smoothstep(0.0, 1.0, _zoom))
	if _scope:
		_scope.visible = _zoom > 0.6
	# в бинокль руки убираем (только на смене состояния — видимость рук трогают и другие)
	var hid := _zoom > 0.6 and p.alive
	if p.hands and hid != _hands_hidden:
		_hands_hidden = hid
		p.hands.visible = not hid
	match held:
		&"gas_torch":
			_torch_process(delta, atk)
		&"chainsaw":
			_saw_process(delta, atk)
	_update_ui(delta)

func _on_switch(_from: StringName, _to: StringName) -> void:
	if not job.is_empty():
		job = {}
	_set_flame(false)
	if _motor and is_instance_valid(_motor):
		_motor.queue_free()
	_motor = null
	_heat = 0.0
	_heat_target = null

# ======================= топливо =======================

## Потратить sec секунд газа/бензина; пустой баллон — берём следующий. false — нечем.
func burn(can: StringName, sec: float) -> bool:
	var key := StringName("supply_" + String(can))
	var left := float(p.get_meta(key, 0.0))
	if left <= 0.0:
		if p.inventory == null or not p.inventory.remove(can, 1):
			return false
		left += SupplyItems.GAS_PER_CAN if can == &"gas_can" else SupplyItems.FUEL_PER_CAN
	left -= sec
	p.set_meta(key, maxf(left, 0.0))
	return true

func fuel_left(can: StringName) -> float:
	var per := SupplyItems.GAS_PER_CAN if can == &"gas_can" else SupplyItems.FUEL_PER_CAN
	return float(p.get_meta(StringName("supply_" + String(can)), 0.0)) + per * (p.inventory.count(can) if p.inventory else 0)

func _fuel_text(can: StringName) -> String:
	var s := fuel_left(can)
	return "%d с" % int(s) if s > 0.0 else "пусто"

# ======================= горелка =======================

func _set_flame(on: bool) -> void:
	if on and (_flame == null or not is_instance_valid(_flame)):
		var m := _held_marker("Flame")
		if m:
			_flame = SupplyFx.torch_flame(m)
		if _motor == null or not is_instance_valid(_motor):
			_motor = SupplyFx.Motor.new()
			_motor.kind = &"torch"
			p.camera.add_child(_motor)
	elif not on:
		if _flame and is_instance_valid(_flame):
			_flame.queue_free()
		_flame = null
		if held == &"gas_torch" and _motor and is_instance_valid(_motor):
			_motor.queue_free()
			_motor = null

func _held_marker(nm: String) -> Node3D:
	if p.hands == null:
		return null
	for c in p.hands.held_root.get_children():
		if c.is_queued_for_deletion():
			continue
		var m := c.find_child(nm, true, false) as Node3D
		if m:
			return m
	return null

func _torch_process(delta: float, atk: bool) -> void:
	var lit := false
	if atk:
		if burn(&"gas_can", delta):
			lit = true
			_tick -= delta
			if _tick <= 0.0:
				_tick = TORCH_TICK
				_torch_hit()
		else:
			_out_of(&"gas_can")
	if not job.is_empty():
		if burn(&"gas_can", delta):
			lit = true
			job.t = float(job.t) + delta
			if float(job.t) >= float(job.total):
				_finish_job()
		else:
			_out_of(&"gas_can")
			job = {}
	_set_flame(lit)
	if not atk:
		_heat = maxf(0.0, _heat - delta)

func _out_of(can: StringName) -> void:
	if Time.get_ticks_msec() * 0.001 - _no_fuel_t > 3.0:
		_no_fuel_t = Time.get_ticks_msec() * 0.001
		Events.toast.emit("Нет газа — нужен газовый баллон" if can == &"gas_can" else "Нет бензина — нужна канистра")
		CombatFx.sound_at(p, "dry_click", p.get_eye_position(), -8.0)

func _ray(reach: float) -> Dictionary:
	var from := p.camera.global_position
	var to := from + p.get_look_dir() * reach
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [p.get_rid()]
	q.collide_with_areas = false
	return p.get_world_3d().direct_space_state.intersect_ray(q)

## Факел: дерево построек загорается через ~1 с, живым — ожоги, костёр — разгорается.
func _torch_hit() -> void:
	var hit := _ray(TORCH_REACH)
	if hit.is_empty():
		_heat = 0.0
		return
	var col := hit.collider as Node
	var fire := Combat._find_with(col, &"light")
	if fire is SvFire and not (fire as SvFire).lit:
		(fire as SvFire).light(null)
		Events.toast.emit("Костёр разожжён горелкой")
		return
	var dmg := Combat._find_with(col, &"apply_damage")
	if dmg and dmg != p and (dmg.is_in_group(&"characters") or dmg.is_in_group(&"animals")):
		dmg.call(&"apply_damage", 3.0, p, &"fire")
		return
	var ign := Combat._find_with(col, &"ignite")
	if ign:
		if ign != _heat_target:
			_heat_target = ign
			_heat = 0.0
		_heat += TORCH_TICK
		if _heat >= TORCH_IGNITE:
			_heat = -4.0 # не поджигать каждый тик
			ign.call(&"ignite", p)
			Combat.ignite_area(hit.position as Vector3, 0.7, p, 5.0)
			Events.toast.emit("Подожжено!")

## ПКМ с горелкой: вскипятить (котелок + морская вода) или пожарить.
func torch_use() -> void:
	if not job.is_empty():
		job = {}
		Events.toast.emit("Горелка выключена")
		return
	if fuel_left(&"gas_can") <= 0.0:
		_out_of(&"gas_can")
		return
	var boil_id := _first_with("boil")
	if boil_id != &"" and p.inventory.count(&"pot") > 0:
		job = {"kind": &"boil", "t": 0.0, "total": BOIL_TIME, "id": boil_id}
		Events.toast.emit("Горелка: кипячу «%s» в котелке" % Items.item_name(boil_id))
		return
	var cook_id := _first_with("cook")
	if cook_id != &"":
		job = {"kind": &"cook", "t": 0.0, "total": COOK_TIME, "id": cook_id}
		Events.toast.emit("Горелка: жарю «%s»" % Items.item_name(cook_id))
		return
	if boil_id != &"":
		Events.toast.emit("Чтобы вскипятить воду, нужен котелок")
	else:
		Events.toast.emit("Нечего кипятить или жарить")

func _first_with(key: String) -> StringName:
	if p.inventory == null:
		return &""
	for s in p.inventory.slots:
		if not s.is_empty() and PlayerItems.data(StringName(s.id)).has(key):
			return StringName(s.id)
	return &""

func _finish_job() -> void:
	var id: StringName = job.id
	var kind: StringName = job.kind
	job = {}
	var dd := PlayerItems.data(id)
	if kind == &"boil":
		var n := mini(4, p.inventory.count(id))
		if n > 0 and p.inventory.remove(id, n):
			Survival.give(p, StringName(dd.get("boil", id)), n)
			Events.toast.emit("Вода вскипела — теперь пресная (×%d)" % n)
	else:
		if p.inventory.remove(id, 1):
			Survival.give(p, StringName(dd.get("cook", id)), 1)

# ======================= бензопила =======================

func _saw_process(delta: float, atk: bool) -> void:
	var has_fuel := fuel_left(&"fuel_can") > 0.0
	if _motor == null or not is_instance_valid(_motor):
		if has_fuel:
			_motor = SupplyFx.Motor.new()
			_motor.kind = &"saw"
			p.camera.add_child(_motor)
	if _motor and is_instance_valid(_motor):
		_motor.rpm = move_toward(_motor.rpm, 1.0 if atk else 0.15, delta * 3.0)
	if not atk:
		if has_fuel:
			burn(&"fuel_can", delta * 0.1)
		return
	if not burn(&"fuel_can", delta):
		_out_of(&"fuel_can")
		if _motor and is_instance_valid(_motor):
			_motor.queue_free()
		_motor = null
		return
	# вибрация рук
	if p.hands:
		p.hands.right_arm.position += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.004
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = SAW_TICK
	var hit := _ray(SAW_REACH)
	if hit.is_empty():
		return
	var col := hit.collider as Node
	var dmg := Combat._find_with(col, &"apply_damage")
	if dmg and dmg != p and (dmg.is_in_group(&"characters") or dmg.is_in_group(&"animals")):
		dmg.call(&"apply_damage", SAW_FLESH_DMG, p, &"melee")
		CombatFx.impact(p, hit.position as Vector3, hit.normal as Vector3, &"flesh")
		return
	var t := Combat._find_with(col, &"on_hit")
	var info := {"position": hit.position, "normal": hit.normal, "tool": &"axe", "damage": SAW_TREE_DMG, "item": &"chainsaw", "collider": col}
	if t:
		t.call(&"on_hit", p, info)
	elif dmg and dmg != p:
		dmg.call(&"apply_damage", SAW_TREE_DMG, p, &"axe")
	Events.player_swing.emit(p, info)

# ======================= интерфейс =======================

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 5
	add_child(_ui)
	_light = SpotLight3D.new()
	_light.name = "Flashlight"
	_light.light_color = Color(1.0, 0.96, 0.88)
	_light.light_energy = 4.0
	_light.spot_range = 34.0
	_light.spot_angle = 24.0
	_light.spot_attenuation = 0.8
	_light.shadow_enabled = false
	_light.position = Vector3(0.12, -0.08, -0.1)
	_light.visible = false
	p.camera.add_child(_light)
	_label = Label.new()
	_label.anchor_left = 1.0
	_label.anchor_right = 1.0
	_label.anchor_top = 1.0
	_label.anchor_bottom = 1.0
	_label.offset_left = -420.0
	_label.offset_right = -24.0
	_label.offset_top = -150.0
	_label.offset_bottom = -124.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.add_theme_color_override(&"font_color", Color(0.95, 0.92, 0.85))
	_label.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.8))
	_label.add_theme_font_size_override(&"font_size", 17)
	_ui.add_child(_label)
	_bar = ProgressBar.new()
	_bar.anchor_left = 0.5
	_bar.anchor_right = 0.5
	_bar.anchor_top = 0.62
	_bar.anchor_bottom = 0.62
	_bar.offset_left = -130.0
	_bar.offset_right = 130.0
	_bar.offset_bottom = 12.0
	_bar.show_percentage = false
	_bar.max_value = 1.0
	_bar.add_theme_stylebox_override(&"background", UITheme.box(Color(0, 0, 0, 0.55), 4))
	_bar.add_theme_stylebox_override(&"fill", UITheme.box(UITheme.ACCENT, 4))
	_bar.visible = false
	_ui.add_child(_bar)
	_bar_label = Label.new()
	_bar_label.anchor_left = 0.5
	_bar_label.anchor_right = 0.5
	_bar_label.anchor_top = 0.62
	_bar_label.anchor_bottom = 0.62
	_bar_label.offset_left = -200.0
	_bar_label.offset_right = 200.0
	_bar_label.offset_top = -26.0
	_bar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bar_label.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.8))
	_bar_label.visible = false
	_ui.add_child(_bar_label)
	_scope = Scope.new()
	_scope.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scope.visible = false
	_ui.add_child(_scope)

## Ящик, который сейчас вскрывает этот игрок.
func _opening_crate() -> SupplyCrate:
	for c in get_tree().get_nodes_in_group(&"supply_crates"):
		if (c as SupplyCrate).opener == p:
			return c as SupplyCrate
	return null

func _update_ui(_delta: float) -> void:
	_ui.visible = p.alive and not p.ui_open
	var txt := ""
	match held:
		&"gas_torch": txt = "Горелка — газ: %s   ЛКМ — факел, ПКМ — кипятить/жарить" % _fuel_text(&"gas_can")
		&"chainsaw": txt = "Бензопила — бензин: %s   держи ЛКМ" % _fuel_text(&"fuel_can")
		&"binoculars": txt = "Бинокль — держи ПКМ"
		&"flashlight": txt = "Фонарик — %s (ПКМ)" % ("вкл" if _light_on else "выкл")
		&"radio": txt = "Рация — ПКМ: слушать эфир"
		&"armor_vest": txt = "Бронежилет — пластины %d%%" % int(float(p.get_meta(&"supply_armor", SupplyItems.ARMOR_HP)) / SupplyItems.ARMOR_HP * 100.0)
	_label.text = txt
	var prog := -1.0
	var what := ""
	var cr := _opening_crate()
	if cr:
		prog = cr.progress()
		what = "Вскрываю ящик спонсоров…"
	elif not job.is_empty():
		prog = float(job.t) / float(job.total)
		what = "Кипячу воду…" if job.kind == &"boil" else "Жарю на горелке…"
	_bar.visible = prog >= 0.0
	_bar_label.visible = prog >= 0.0
	if prog >= 0.0:
		_bar.value = prog
		_bar_label.text = what


## Вид в бинокль: чёрная маска с двумя кругами.
class Scope:
	extends Control
	func _draw() -> void:
		var c := size * 0.5
		var r := size.y * 0.42
		var off := Vector2(r * 0.62, 0.0)
		# маска построчно: всё вне объединения двух кругов — чёрное
		var step := 3.0
		var y := 0.0
		while y < size.y:
			var dy := absf(y + step * 0.5 - c.y)
			if dy >= r:
				draw_rect(Rect2(0, y, size.x, step), Color.BLACK)
			else:
				var hw := sqrt(r * r - dy * dy)
				var x0 := c.x - off.x - hw
				var x1 := c.x + off.x + hw
				draw_rect(Rect2(0, y, x0, step), Color.BLACK)
				draw_rect(Rect2(x1, y, size.x - x1, step), Color.BLACK)
				if hw < off.x: # между кругами (у краёв по вертикали)
					draw_rect(Rect2(c.x - off.x + hw, y, (off.x - hw) * 2.0, step), Color.BLACK)
			y += step
		draw_line(c - Vector2(12, 0), c + Vector2(12, 0), Color(0, 0, 0, 0.5), 1.0)
		draw_line(c - Vector2(0, 12), c + Vector2(0, 12), Color(0, 0, 0, 0.5), 1.0)
