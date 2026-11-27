class_name StormOmens
extends Node
## v5.2: предвестники грозы. Когда по прогнозу SkyWeather до шторма остаётся LEAD_S секунд (или
## шторм уже начинается), один раз за шторм шлётся раздражитель Perception &"storm_coming"
## (радиус на весь остров) и сигнал storm_coming. Встроенные реакции по умолчанию (если поведение
## фауны их не перехватило): стаи птиц улетают с побережья вглубь острова и прячутся в кронах,
## крабы зарываются / уходят в норы. Сами животные могут реагировать через группу perceiver.

signal storm_coming(seconds_left: float)

const LEAD_S := 75.0
const RADIUS := 3000.0

var armed := true
var last_eta := -1.0
var fired_count := 0

func tick(_dt: float, sky: Node, cam: Camera3D) -> void:
	if sky == null or not sky.has_method(&"forecast"):
		return
	var eta := -1.0
	var kind: StringName = sky.call(&"weather_kind")
	if kind == &"storm":
		eta = 0.0
	else:
		for f: Dictionary in sky.call(&"forecast", 4):
			var fw := StringName(f.get("w", &""))
			if SkyWeather.WEATHER_KIND.get(fw, fw) == &"storm":
				eta = float(f.get("in_s", 0.0))
				break
	last_eta = eta
	if eta < 0.0:
		armed = true
		return
	if armed and eta <= LEAD_S:
		armed = false
		fire(eta, cam.global_position if cam else Vector3.ZERO)

## Сработать сейчас (тесты/консоль).
func fire(eta: float, pos: Vector3) -> void:
	fired_count += 1
	storm_coming.emit(eta)
	var per := get_node_or_null(^"/root/Perception")
	if per and per.has_method(&"emit"):
		per.call(&"emit", &"storm_coming", pos, RADIUS, 1.0, null)
	_default_reactions(pos)

func _default_reactions(_pos: Vector3) -> void:
	var fauna := Fauna.instance()
	if fauna == null:
		return
	var now := Time.get_ticks_msec() * 0.001
	var w := BuildEnv.world()
	for fl: Dictionary in fauna.flocks:
		if bool(fl.get("storm_handled", false)) and now < float(fl.get("spooked_until", 0.0)):
			continue
		var fp: Vector3 = fl.get("pos", Vector3.INF)
		if fp == Vector3.INF:
			continue
		# вглубь острова: к центру ближайшего острова (птицы прячутся в кронах), иначе просто от моря
		var tgt := fp
		if w and w.has_method(&"islands"):
			var best := INF
			for I in w.call(&"islands"):
				var c: Vector2 = I.center
				var d := Vector2(fp.x, fp.z).distance_to(c)
				if d < best:
					best = d
					tgt = Vector3(c.x, fp.y, c.y)
		var away := (tgt - fp)
		away.y = 0.0
		if away.length() < 5.0:
			away = Vector3(randf() - 0.5, 0.0, randf() - 0.5) * 20.0
		tgt = fp + away.normalized() * clampf(away.length(), 60.0, 220.0)
		tgt.y = maxf(fp.y, BuildEnv.water_level()) + randf_range(10.0, 18.0)
		fl["mode"] = &"fly"
		fl["target"] = tgt
		fl["t"] = 0.0
		fl["legs"] = 2
		fl["spooked_until"] = now + 240.0
		fl["spooked_by"] = &"storm_coming"
		fl["storm_handled"] = true
		for m in fl.get("members", []):
			if is_instance_valid(m) and m.has_method(&"_set_state") and not bool(m.get(&"dead")):
				m.call(&"_set_state", &"fly")
	for a in fauna.animals:
		if is_instance_valid(a) and not a.dead and a.species == &"crab":
			a.call(&"_set_state", &"burrow")
