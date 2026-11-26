class_name BodyState
extends Node
## Состояние тела игрока (V5): мокрость (A5) и ощущение температуры.
## Мокрость 0..1: плавание — быстро до 1, дождь — постепенно, волна у берега — брызги;
## сохнет со временем, быстрее на солнце, на ветру и у костра.
## Температура (ощущение) −1 (холодно) .. +1 (жарко) плавно идёт к цели:
##   ночь холоднее, полдень на солнце жарко (в тени и в воде — прохладнее), дождь и ветер
##   холодят, мокрая одежда холодит сильно, костёр рядом греет; одежда (свойство предмета
##   clothing.warmth в items_props.json, без визуала) смягчает холод.
## Последствия: холод — силы восстанавливаются медленнее (Player.stamina_regen_mul), сильный
## холод — урон; жара — жажда быстрее (Player.thirst_mul), сильная жара — урон.
## Значения — assets/data/balance.json (wetness, temperature). Ставит индикатор в HUD.

var wetness: float = 0.0
var temp: float = 0.0
var target_temp: float = 0.0
## Разложение цели по причинам (для HUD/отладки/тестов).
var causes: Dictionary = {}
## Тесты: зафиксировать время суток/погоду, не спрашивая мир.
var force: Dictionary = {}
var _acc := 0.0
var _hurt_acc := 0.0
var _label: Label
var _blur: ColorRect

func pl() -> Player:
	return get_parent() as Player

func b(key: String, d: float) -> float:
	return DataTables.f("balance", key, d)

func _ready() -> void:
	if pl() and pl().create_hud and DisplayServer.get_name() != "headless":
		var cl := CanvasLayer.new()
		cl.layer = 5
		add_child(cl)
		_label = Label.new()
		_label.add_theme_font_size_override(&"font_size", 15)
		_label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.7))
		_label.add_theme_constant_override(&"outline_size", 4)
		_label.anchor_left = 0.0
		_label.anchor_top = 1.0
		_label.offset_left = 18
		_label.offset_top = -150
		cl.add_child(_label)
		# жажда — экран мутнеет
		_blur = ColorRect.new()
		_blur.set_anchors_preset(Control.PRESET_FULL_RECT)
		_blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sm := ShaderMaterial.new()
		sm.shader = load("res://scripts/mech/thirst_blur.gdshader") as Shader
		_blur.material = sm
		_blur.visible = false
		cl.add_child(_blur)
		cl.move_child(_blur, 0)

func _physics_process(delta: float) -> void:
	var p := pl()
	if p == null or not p.alive:
		return
	_update_wetness(delta)
	GearWear.tick(p, delta)
	WaterContainers.tick(p, delta)
	_acc += delta
	if _acc >= 0.5:
		_acc = 0.0
		target_temp = _target()
	temp = move_toward(temp, target_temp, b("temperature/adapt_per_s", 0.02) * delta)
	_apply(delta)
	if _label:
		_label.text = hud_text()
	if _blur:
		var a := thirst_blur()
		_blur.visible = a > 0.01
		(_blur.material as ShaderMaterial).set_shader_parameter(&"amount", a)

func _world() -> Node:
	return BuildEnv.world()

func _w(method: StringName, d: float) -> float:
	if force.has(String(method)):
		return float(force[String(method)])
	var w := _world()
	return float(w.call(method)) if w and w.has_method(method) else d

func _update_wetness(delta: float) -> void:
	var p := pl()
	var wl := p.water_level()
	if p.swimming or p.global_position.y < wl - 0.6:
		wetness = move_toward(wetness, 1.0, b("wetness/swim_rate", 3.0) * delta)
		return
	var rain := _w(&"rain_intensity", 0.0)
	if rain > 0.05 and not _sheltered():
		wetness = minf(1.0, wetness + b("wetness/rain_rate", 0.25) * rain * delta / 6.0)
		return
	if p.global_position.y < wl + 0.2:
		wetness = maxf(wetness, minf(1.0, wetness + b("wetness/wave_splash", 0.3) * delta))
		return
	# сохнем: база за «игровой час» ≈ 60 с, солнце, ветер, костёр
	var sun := clampf(_w(&"sun_elevation", 0.5), 0.0, 1.0)
	var k := b("wetness/dry_base_per_h", 0.6) / 60.0
	k *= 1.0 + sun * b("wetness/dry_sun_mul", 2.0) * (0.0 if _shade() else 1.0)
	k *= 1.0 + _w(&"wind_speed", 3.0) * b("wetness/dry_wind_mul", 0.15)
	if _fire_near(b("wetness/fire_radius", 3.5)) > 0.0:
		k *= b("wetness/dry_fire_mul", 6.0)
	wetness = maxf(0.0, wetness - k * delta)

func _target() -> float:
	var p := pl()
	causes.clear()
	var t := b("temperature/comfort", 0.0)
	var sun := _w(&"sun_elevation", 0.5)
	if sun < -0.05:
		causes["ночь"] = b("temperature/night_cold", -0.55) * clampf(-sun * 4.0, 0.3, 1.0)
	else:
		causes["день"] = b("temperature/day_warm", 0.1)
		if sun > 0.75 and not _shade() and not p.swimming:
			causes["полуденное солнце"] = b("temperature/noon_heat", 0.55) * smoothstep(0.75, 0.95, sun)
		elif _shade() and sun > 0.5:
			causes["тень"] = b("temperature/shade_cool", -0.25) * 0.5
	var rain := _w(&"rain_intensity", 0.0)
	if rain > 0.05:
		causes["дождь"] = b("temperature/rain_cold", -0.25) * rain
	var wind := _w(&"wind_speed", 3.0)
	if wind > 4.0:
		causes["ветер"] = b("temperature/wind_cold_per_ms", -0.03) * (wind - 4.0) * (1.0 + wetness)
	if wetness > 0.05:
		causes["мокрая одежда"] = b("temperature/wet_cold", -0.45) * wetness
	if p.swimming:
		causes["вода"] = b("temperature/water_cool", -0.35)
	var fire := _fire_near(b("temperature/fire_radius", 4.0))
	if fire > 0.0:
		causes["костёр"] = b("temperature/fire_warm", 0.9) * fire
	var warm := clothing_warmth()
	for k in causes.keys():
		var v := float(causes[k])
		t += v * (1.0 - warm) if v < 0.0 else v
	if warm > 0.0:
		causes["одежда"] = warm
	return clampf(t, -1.0, 1.0)

## Тепло одежды 0..0,8: лучший предмет на каждую часть тела (свойство clothing, без визуала).
func clothing_warmth() -> float:
	var p := pl()
	if p.inventory == null:
		return 0.0
	var best := {}
	for id in _inventory_ids():
		var cl: Dictionary = Materials.prop(id, "clothing", {})
		if cl.is_empty():
			continue
		var slot := String(cl.get("slot", "torso"))
		best[slot] = maxf(float(best.get(slot, 0.0)), float(cl.get("warmth", 0.0)) * (1.0 - 0.6 * wetness * (1.0 - float(cl.get("waterproof", 0.0)))))
	var sum := 0.0
	for v in best.values():
		sum += float(v)
	return clampf(sum, 0.0, 0.8)

func _inventory_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	var inv := pl().inventory
	if inv == null:
		return out
	for s: Dictionary in inv.slots:
		if not s.is_empty() and int(s.get("n", 0)) > 0:
			out.append(StringName(s.get("id", &"")))
	return out

func _apply(delta: float) -> void:
	var p := pl()
	p.stamina_regen_mul = lerpf(1.0, b("temperature/cold_stamina_mul", 0.6), smoothstep(-0.4, -0.8, temp))
	p.thirst_mul = lerpf(1.0, b("temperature/heat_thirst_mul", 2.2), smoothstep(0.35, 0.8, temp))
	_hurt_acc += delta
	if _hurt_acc >= 1.0:
		_hurt_acc -= 1.0
		if temp < b("temperature/cold_damage_below", -0.85):
			p.apply_damage(b("temperature/cold_dps", 0.15), null, &"cold")
		elif temp > b("temperature/heat_damage_above", 0.9):
			p.apply_damage(b("temperature/heat_dps", 0.1), null, &"heat")

## Сила ближайшего горящего костра 0..1 в радиусе r.
func _fire_near(r: float) -> float:
	if force.has("fire"):
		return float(force["fire"])
	var best := 0.0
	var pp := pl().global_position
	for f in get_tree().get_nodes_in_group(&"campfire"):
		if f is Node3D and bool(f.get(&"lit")):
			var d := (f as Node3D).global_position.distance_to(pp)
			if d < r:
				best = maxf(best, 1.0 - d / r)
	return best

## Над головой что-то есть (крона, крыша, тент) — тень и укрытие от дождя.
func _shade() -> bool:
	if force.has("shade"):
		return bool(force["shade"])
	return _ray_up(18.0)

func _sheltered() -> bool:
	if force.has("shelter"):
		return bool(force["shelter"])
	return _ray_up(6.0)

func _ray_up(h: float) -> bool:
	var p := pl()
	var space := p.get_world_3d().direct_space_state
	var o := p.global_position + Vector3.UP * 1.9
	var q := PhysicsRayQueryParameters3D.create(o, o + Vector3.UP * h)
	q.exclude = [p.get_rid()]
	return not space.intersect_ray(q).is_empty()

## Сила помутнения от жажды 0..1 (жажда < 25).
func thirst_blur() -> float:
	var t := float(pl().thirst)
	return DataTables.f("balance", "weapons/thirst_blur", 0.7) * clampf(1.0 - t / 25.0, 0.0, 1.0)

func temp_word() -> String:
	if temp < -0.7:
		return "очень холодно"
	if temp < -0.35:
		return "холодно"
	if temp < -0.15:
		return "прохладно"
	if temp > 0.7:
		return "жара"
	if temp > 0.35:
		return "жарко"
	return ""

func hud_text() -> String:
	var parts: Array[String] = []
	if wetness > 0.6:
		parts.append("мокрый")
	elif wetness > 0.2:
		parts.append("влажный")
	var tw := temp_word()
	if tw != "":
		parts.append(tw)
	return " · ".join(parts)
