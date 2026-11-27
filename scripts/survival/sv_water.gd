class_name SvWater
extends SvStation
## Источник пресной воды:
##   spring      — родник (бесконечный, только на части островов);
##   still       — солнечный опреснитель (днём, на солнце; медленно);
##   rain_barrel — бочка (дождь; ёмкость 8 порций);
##   tarp        — тент (дождь собирается быстрее, ёмкость 4).
## Порция = 1 бутылка / плошка / глоток (+25 жажды).
## E: с пустой тарой в руке — набрать; иначе — попить.

const SIP := 25.0
const CFG := {
	&"spring": {"name": "Родник", "cap": 999.0, "hp": 9999.0},
	&"still": {"name": "Солнечный опреснитель", "cap": 2.0, "hp": 30.0, "sun_rate": 1.0 / 240.0},
	&"rain_barrel": {"name": "Дождевая бочка", "cap": 8.0, "hp": 60.0, "rain_rate": 1.0 / 40.0},
	&"tarp": {"name": "Дождевой тент", "cap": 4.0, "hp": 40.0, "rain_rate": 1.0 / 14.0},
}

var amount := 0.0
var cap := 1.0
var _level: MeshInstance3D
var _level_y := Vector2.ZERO # (пусто, полно)
var _shown := -1.0

func _ready() -> void:
	name = "SvWater_" + String(kind)
	var c: Dictionary = CFG.get(kind, CFG[&"rain_barrel"])
	cap = float(c.cap)
	max_hp = float(c.hp)
	hp = max_hp
	model = Node3D.new()
	add_child(model)
	match kind:
		&"spring":
			add_to_group(&"sv_fresh")
			remove_from_group(&"buildable")
			amount = cap
			SurvivalModels.spring(model)
			add_shape(Vector3(2.4, 0.35, 2.2), Vector3(0, -0.1, 0), true)
		&"still":
			salvage = {&"plastic_sheet": 1, &"bottle_empty": 1, &"stick": 1}
			var d := SurvivalModels.still(model)
			_level = d.level as MeshInstance3D
			_level_y = Vector2(0.012, 0.09)
			add_shape(Vector3(1.3, 0.35, 1.3), Vector3.ZERO, true)
		&"rain_barrel":
			salvage = {&"barrel": 1}
			_level = SurvivalModels.rain_barrel(model)
			_level_y = Vector2(0.1, 0.86)
			add_shape(Vector3(0.65, 1.0, 0.65), Vector3.ZERO, true)
		&"tarp":
			salvage = {&"cloth": 2, &"rope": 1, &"stick": 3}
			_level = SurvivalModels.tarp(model)
			_level_y = Vector2(0.04, 0.34)
			add_shape(Vector3(2.0, 1.25, 1.7))
	_update_level()

func display_name() -> String:
	return String(CFG.get(kind, {}).get("name", "Вода"))

func is_fresh() -> bool:
	return true

func portions() -> int:
	return int(floor(amount + 0.001))

## Сколько солнца: день, облачность, дождь.
static func sun_factor() -> float:
	var w := Survival.world_node()
	var h := 12.0
	var weather := &"clear"
	if w:
		if w.has_method(&"time_of_day"):
			h = float(w.call(&"time_of_day"))
		if w.has_method(&"weather"):
			weather = StringName(w.call(&"weather"))
	var day := clampf(sin((h - 6.0) / 12.0 * PI), 0.0, 1.0)
	var cloud := 1.0
	match weather:
		&"cloudy": cloud = 0.45
		&"rain": cloud = 0.15
		&"storm": cloud = 0.0
		&"fog": cloud = 0.5
	return day * cloud * (1.0 - Survival.rain())

func tick(dt: float) -> void:
	if kind == &"spring":
		return
	var c: Dictionary = CFG[kind]
	var add := 0.0
	if c.has("sun_rate"):
		add += float(c.sun_rate) * sun_factor() * dt
	if c.has("rain_rate"):
		add += float(c.rain_rate) * Survival.rain() * dt
	if add > 0.0:
		amount = minf(cap, amount + add)
		_update_level()

func _update_level() -> void:
	if _level == null:
		return
	var f := clampf(amount / cap, 0.0, 1.0)
	if absf(f - _shown) < 0.02:
		return
	_shown = f
	_level.visible = f > 0.01
	_level.position.y = lerpf(_level_y.x, _level_y.y, f)

func get_interact_text(ch: Node) -> String:
	var h := held(ch)
	var hdr := display_name()
	if kind != &"spring":
		hdr += " (вода %d/%d)" % [portions(), int(cap)]
		if kind == &"still" and portions() == 0:
			hdr += ", капает %d%%" % int(fmod(amount, 1.0) * 100.0)
	if portions() <= 0:
		return hdr + (" — ждёт солнца" if kind == &"still" else " — ждёт дождя")
	if Survival.data(h).has("fill_fresh"):
		return "%s — E: набрать в «%s»" % [hdr, iname(h)]
	if h == &"water_salt" or h == &"shell_salt":
		return "%s — E: вылить морскую и набрать пресной" % hdr
	return "%s — E: попить" % hdr

func interact(ch: Node) -> void:
	if portions() <= 0:
		toast(ch, "Воды пока нет")
		return
	var h := held(ch)
	if h == &"water_salt" or h == &"shell_salt":
		# вылить морскую — тара станет пустой
		var empty_id := StringName(Survival.data(h).get("returns"))
		var n := Survival.count(ch, h)
		Survival.take(ch, h, n)
		Survival.give(ch, empty_id, n)
		h = empty_id
	if Survival.data(h).has("fill_fresh"):
		fill(ch, h)
		return
	drink(ch)

## Набрать в тару id (всё, что есть в инвентаре, пока хватает воды).
func fill(ch: Node, id: StringName) -> int:
	if SeasonEvents.is_poisoned(global_position):
		toast(ch, "Вода пахнет тухлым — набирать не стал")
		return 0
	var to := StringName(Survival.data(id).get("fill_fresh", &""))
	if to == &"":
		return 0
	var n := mini(Survival.count(ch, id), portions())
	if n <= 0 or not Survival.take(ch, id, n):
		return 0
	Survival.give(ch, to, n)
	if kind != &"spring":
		amount -= n
		_update_level()
	Survival.sfx(global_position, "res://assets/sounds/sfx-kit/props-splash.wav")
	toast(ch, "Набрал пресной воды ×%d" % n)
	return n

func drink(ch: Node) -> bool:
	if portions() <= 0:
		return false
	# v5.2: отравленный родник (событие)
	if SeasonEvents.is_poisoned(global_position):
		var se := SeasonEvents.instance()
		var ev := se.get_active(&"poison_spring") if se else null
		if ev:
			ev.call(&"poison", ch)
		return true
	var t := float(ch.get(&"thirst")) if ch.get(&"thirst") != null else 0.0
	if t >= 99.0:
		toast(ch, "Не хочется пить")
		return false
	ch.set(&"thirst", minf(100.0, t + SIP))
	if kind != &"spring":
		amount -= 1.0
		_update_level()
	var hands: Variant = ch.get(&"hands")
	if hands is Object and (hands as Object).has_method(&"play_use"):
		(hands as Object).call(&"play_use")
	Survival.sfx(global_position, "res://assets/sounds/sfx-kit/props-splash.wav")
	toast(ch, "Ты попил пресной воды")
	return true

func on_broken(by: Node) -> void:
	if kind == &"spring":
		return

func on_hit(by: Node, hit: Dictionary) -> void:
	if kind == &"spring":
		return
	super.on_hit(by, hit)
