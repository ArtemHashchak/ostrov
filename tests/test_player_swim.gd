extends TestCase
## Плавание, ныряние, воздух, утопление, питьё воды.

func _init() -> void:
	timeout_sec = 400.0

func run() -> void:
	await wait(1.0)
	var p := get_tree().get_first_node_in_group(&"player") as Player
	check(p != null, "игрок есть")
	if p == null:
		return
	check(is_equal_approx(p.water_level(), 0.0), "уровень воды без группы world — 0")

	# Берег: питьё.
	var bx := 0.0
	for x in range(40, 80):
		if scene.call(&"height_at", float(x), 0.0) < 0.15:
			bx = float(x)
			break
	p.global_position = Vector3(bx - 1.5, float(scene.call(&"height_at", bx - 1.5, 0.0)) + 0.3, 0.0)
	p.set_look(-PI * 0.5, deg_to_rad(-55.0))
	p.thirst = 40.0
	await wait(0.8)
	check(p.can_drink_here(), "у воды можно попить")
	await tap(&"interact")
	await until(func() -> bool: return p.thirst > 40.0, 6.0)
	check(p.thirst > 40.0, "попил: жажда %.0f" % p.thirst)

	# В глубокую воду.
	p.global_position = Vector3(85.0, 0.5, 0.0)
	p.set_look(-PI * 0.5, 0.0)
	await until(func() -> bool: return p.swimming and absf(p.velocity.y) < 0.15 and not p.is_underwater(), 10.0)
	check(p.is_in_water() and p.swimming, "в глубокой воде — плывёт")
	check(not p.is_underwater(), "на плаву голова над водой (глаза %.2f)" % p.get_eye_position().y)
	check(absf(p.get_eye_position().y - Player.SWIM_FLOAT_EYE) < 0.35, "держится у поверхности")
	await shot("01_swim")
	var x0 := p.global_position.x
	await press(&"move_forward", 2.0)
	var swam := absf(p.global_position.x - x0)
	check(swam > 2.5 and swam < 7.5, "плывёт ~2 м/с: %.1f м за 2 с" % swam)

	# Ныряние (присед).
	Input.action_press(&"crouch")
	await until(func() -> bool: return p.get_eye_position().y < -1.5, 8.0)
	check(p.is_underwater(), "нырнул: глаза на %.2f" % p.get_eye_position().y)
	check(p.breath < Player.BREATH_MAX, "воздух тратится: %.0f" % p.breath)
	await shot("02_underwater")
	Input.action_release(&"crouch")
	# Всплытие (прыжок/вверх).
	Input.action_press(&"jump")
	await until(func() -> bool: return not p.is_underwater(), 10.0)
	Input.action_release(&"jump")
	check(not p.is_underwater(), "всплыл")
	var b1 := p.breath
	await wait(1.0)
	check(p.breath > b1 or p.breath >= Player.BREATH_MAX, "воздух восстанавливается")

	# Утопление: держим под водой.
	var hp0 := p.health
	var died := [false, &""]
	Events.character_died.connect(func(c: Node, _k: Node) -> void:
		if c == p:
			died[0] = true
			died[1] = p.last_damage_kind)
	p.breath = 3.0
	Input.action_press(&"crouch")
	await until(func() -> bool: return p.health < hp0, 10.0)
	check(p.breath <= 0.5, "воздух кончился")
	check(p.health < hp0, "урон от удушья: %.0f" % p.health)
	await shot("03_drowning")
	var t := 0.0
	while p.alive and t < 40.0:
		await wait(0.5)
		t += 0.5
	Input.action_release(&"crouch")
	check(died[0] and died[1] == &"drown", "утонул (причина %s)" % died[1])
	await wait(0.5)
	await shot("04_drowned")

## Ждать условие (игровое время под нагрузкой отстаёт от таймеров).
func until(cond: Callable, max_sec: float) -> void:
	var t := 0.0
	while not bool(cond.call()) and t < max_sec:
		await wait(0.1)
		t += 0.1
