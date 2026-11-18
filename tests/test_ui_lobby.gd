extends TestCase
## Главное меню → лобби: выбор режима/ботов/длительности, конфиг уходит в
## Game.pending_config; экраны «Управление» и «Настройки» (качество графики).

func _init() -> void:
	scene_path = "res://scenes/ui/main_menu.tscn"
	timeout_sec = 300.0

func run() -> void:
	await wait(2.0)
	var lobby := scene.get(&"lobby") as LobbyPanel
	check(lobby != null, "лобби создано")
	scene.call(&"open_lobby")
	await wait(0.3)
	check(lobby.visible and not (scene.get(&"_menu") as Control).visible, "«Играть» открывает лобби")
	lobby.set_option("mode", "2x2")
	lobby.set_option("bots_enemy", 2)
	lobby.set_option("bots_ally", 1)
	lobby.set_option("difficulty", "hard")
	lobby.set_option("minutes", 0)
	lobby.set_option("map_size", "large")
	await wait(0.2)
	await shot("01_lobby")
	lobby.launch = false
	var got: Array = []
	lobby.started.connect(func(c: Dictionary) -> void: got.append(c))
	lobby.start_match()
	check(got.size() == 1, "«Начать» отдаёт конфиг")
	var c: Dictionary = Game.pending_config
	check(String(c.get("mode")) == "2x2" and int(c.get("teams")) == 2, "режим 2×2, 2 команды")
	check(int(c.get("bots_enemy")) == 2 and int(c.get("bots_ally")) == 1 and String(c.get("difficulty")) == "hard", "боты и сложность")
	check(int(c.get("minutes")) == 0 and String(c.get("map_size")) == "large", "до последнего флага, большая карта")
	# Сохранение лобби между запусками.
	GameLauncher.save_lobby(c)
	var back := GameLauncher.load_lobby()
	check(String(back.get("mode")) == "2x2" and int(back.get("bots_enemy")) == 2, "настройки лобби сохраняются")
	# Game.start_match подхватывает конфиг лобби.
	Game.start_match({"minutes": 180, "teams": 4})
	check(Game.teams.size() == 2 and not Game.has_time_limit(), "матч стартует с конфигом лобби")
	Game.end_session()
	lobby.close()
	check((scene.get(&"_menu") as Control).visible, "назад из лобби")
	# Управление.
	var ctr := scene.get(&"controls") as ControlsHelp
	(scene.get(&"_menu") as Control).visible = false
	ctr.visible = true
	await wait(0.3)
	await shot("02_controls")
	check(UITheme.key_name(&"craft") == "C", "крафт — C (есть %s)" % UITheme.key_name(&"craft"))
	check(ControlsHelp.key_text(&"build_menu") == "B", "стройка — B")
	check(UITheme.key_name(&"crouch") != "C", "C не занята приседанием")
	ctr.close()
	# Настройки с качеством графики.
	(scene.get(&"_menu") as Control).visible = false
	var st := scene.get(&"settings") as SettingsPanel
	st.visible = true
	Settings.graphics_quality = 0
	Settings.apply_graphics()
	check(is_equal_approx(get_tree().root.scaling_3d_scale, 0.67), "низкое качество — масштаб 3D 0.67")
	Settings.graphics_quality = 2
	Settings.apply_graphics()
	await wait(0.3)
	await shot("03_settings")
	st.close()
