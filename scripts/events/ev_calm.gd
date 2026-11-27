extends SeasonEvent
## Полный штиль: погода «calm» без автосмены (почти нет ветра, низкая зыбь), зной — добавка
## к температуре тела (BodyState читает SeasonEvents.heat()), жажда растёт быстрее через жару.
## По окончании — погода снова сменяется сама.

var _prev: StringName = &""

func begin() -> void:
	var w := world()
	if w == null:
		done = true
		return
	_prev = StringName(w.call(&"weather"))
	var sky: Variant = w.get(&"sky")
	if sky is Object and (sky as Object).has_method(&"set_weather"):
		(sky as Object).call(&"set_weather", &"calm", false, false)
	else:
		w.call(&"set_weather", &"calm", false)
	say(host_line("calm"))

func heat_now() -> float:
	# зной нарастает первые 90 с и спадает в последние 60 с
	var k := smoothstep(0.0, 90.0, t) * (1.0 - smoothstep(duration - 60.0, duration, t))
	var w := world()
	var day := 1.0
	if w and w.has_method(&"is_night") and bool(w.call(&"is_night")):
		day = 0.2
	return float(cfg.get("heat", 0.35)) * k * day

func finish() -> void:
	var w := world()
	if w:
		var sky: Variant = w.get(&"sky")
		if sky is Object and (sky as Object).has_method(&"set_weather"):
			(sky as Object).call(&"set_weather", &"clear", false, true)
	super.finish()

func hud_line() -> String:
	return "Штиль и зной — пей больше (%s)" % left_text()
