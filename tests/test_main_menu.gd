extends TestCase
## Главное меню: строится, фоновый пролёт, настройки, «Играть» грузит мир.

func _init() -> void:
	scene_path = "res://scenes/ui/main_menu.tscn"
	timeout_sec = 300.0

func run() -> void:
	await wait(2.0)
	check(scene != null and scene.get(&"settings") != null, "меню построено")
	await shot("01_menu")
	(scene.get(&"settings") as Control).visible = true
	(scene.get(&"_menu") as Control).visible = false
	await wait(0.3)
	await shot("02_settings")
	(scene.get(&"settings") as SettingsPanel).close()
	check((scene.get(&"_menu") as Control).visible, "назад из настроек")
	# play_game() меняет текущую сцену (это раннер тестов) — проверяем только цель.
	check(ResourceLoader.exists(scene.get(&"MATCH")) or ResourceLoader.exists(scene.get(&"FALLBACK")), "«Играть» — сцена мира существует")
	# «Авторы» — титры CC BY.
	var cr := scene.get(&"credits") as CreditsPanel
	check(cr != null, "экран «Авторы» есть")
	if cr:
		(scene.get(&"_menu") as Control).visible = false
		cr.visible = true
		await wait(0.3)
		await shot("03_credits")
		cr.visible = false
		cr.closed.emit()
		check((scene.get(&"_menu") as Control).visible, "назад из «Авторов»")
