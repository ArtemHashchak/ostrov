extends TestCase
## Игрок от первого лица: ходьба, бег, усталость, прыжок, присед, удар,
## переноска бревна, подсказка взаимодействия, пауза.

var hint: String = ""

func run() -> void:
	Events.interact_hint_changed.connect(func(t: String) -> void: hint = t)
	await wait(1.0)
	var p := get_tree().get_first_node_in_group(&"player") as Player
	check(p != null, "игрок создан")
	if p == null:
		return
	check(p.is_on_floor(), "игрок стоит на земле")
	# Смотрим на бревно перед собой (оно в 2 м по -Z, у земли).
	p.set_look(0.0, deg_to_rad(-28.0))
	await wait(0.4)
	await shot("01_start")
	check(hint.contains("бревно"), "подсказка у бревна: '%s'" % hint)

	# Ходьба вбок (бревно впереди) 2 с.
	var start := p.global_position
	await press(&"move_left", 2.0)
	var walked := Vector2(p.global_position.x - start.x, p.global_position.z - start.z).length()
	check(walked > 5.0 and walked < 8.5, "ходьба ~3.4 м/с: прошёл %.2f м за 2 с" % walked)

	# Бег до усталости.
	p.set_look(PI, 0.0)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	var ran_from := p.global_position
	await wait(1.0)
	check(p.sprinting, "спринт включился")
	await shot("02_run")
	var t := 0.0
	while not p.tired and t < 9.0:
		await wait(0.25)
		t += 0.25
	var ran := Vector2(p.global_position.x - ran_from.x, p.global_position.z - ran_from.z).length()
	check(p.tired, "выдохся через %.1f с бега (пробежал %.1f м)" % [t + 1.0, ran])
	# Пока устал — спринт не включается, нет мигания вкл/выкл.
	# Пока устал — спринт не включается ни на кадр, пока не отдышится до 35.
	var bad := 0
	var frames := 0
	while p.tired and frames < 600:
		await get_tree().physics_frame
		frames += 1
		if p.sprinting and p.tired:
			bad += 1
	check(bad == 0 and frames > 10, "усталость без дёрганья: %d кадров усталости, спринт включался %d раз" % [frames, bad])
	check(not p.tired and p.stamina >= Player.TIRED_RECOVER_AT - 1.0, "отдышался на %.0f выносливости" % p.stamina)
	await shot("03_tired")
	Input.action_release(&"sprint")
	Input.action_release(&"move_forward")

	# Восстановление.
	await wait(3.5)
	check(p.stamina > 30.0, "выносливость восстанавливается: %.0f" % p.stamina)

	# Прыжок.
	var y0 := p.global_position.y
	var top := y0
	await tap(&"jump")
	for i in 30:
		await wait_frames(1)
		top = maxf(top, p.global_position.y)
	check(top - y0 > 0.6, "прыжок: высота %.2f м" % (top - y0))
	await wait(0.8)

	# Присед.
	Input.action_press(&"crouch")
	await wait(0.6)
	check(p.crouching and p.head.position.y < 1.3, "присед: глаза на %.2f м" % p.head.position.y)
	await shot("04_crouch")
	Input.action_release(&"crouch")
	await wait(0.6)
	check(not p.crouching, "встал")

	# Удар по мишени: подходим к ней.
	var target := scene.get_node(^"TestTarget") as TestProp
	p.global_position = target.global_position + Vector3(0.0, 0.3, 1.4)
	p.set_look(0.0, deg_to_rad(-12.0))
	await wait(0.6)
	await tap(&"attack")
	await wait(0.2)
	await shot("05_swing")
	await wait(0.6)
	check(target.hits == 1, "удар попал в мишень (попаданий %d)" % target.hits)

	# Бревно: взять и пронести.
	var log_prop := scene.get_node(^"TestLog") as TestProp
	p.global_position = log_prop.global_position + Vector3(0.0, 0.2, 1.6)
	await wait(0.5)
	aim_at(p, log_prop.global_position)
	await wait(0.2)
	await tap(&"interact")
	await wait(0.4)
	check(p.carrying_log, "поднял бревно")
	p.set_look(0.0, deg_to_rad(-5.0))
	await press(&"move_back", 1.0)
	await shot("06_carry")
	await tap(&"interact")
	await wait(0.3)
	check(not p.carrying_log and log_prop.visible, "положил бревно")

	# Пауза.
	await tap(&"pause")
	check(get_tree().paused, "пауза включилась")
	await tap(&"pause")
	check(not get_tree().paused, "пауза выключилась")

	# Вид на остров.
	p.global_position = Vector3(30.0, scene.call(&"height_at", 30.0, 10.0) + 0.2, 10.0)
	p.set_look(deg_to_rad(60.0), deg_to_rad(-6.0))
	await wait(0.8)
	await shot("07_view")

func aim_at(p: Player, pt: Vector3) -> void:
	var d := pt - p.get_eye_position()
	p.set_look(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))
