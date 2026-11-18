extends TestCase
## Масштаб интерфейса: canvas_items растягивает меню/настройки/лобби вместе с
## окном (запуск с XVFB_SCREEN=2560x1440 — снимки *_big), масштаб 3D от
## интерфейса не зависит, ползунок «Масштаб интерфейса» работает.

func _init() -> void:
	scene_path = "res://scenes/ui/main_menu.tscn"
	timeout_sec = 600.0

func run() -> void:
	await wait(2.0)
	var win := get_tree().root
	var tag := "big" if win.size.x > 1600 else "small"
	print("[uiscale] окно %s, логический размер %s, 3D ×%.2f" % [win.size, win.get_visible_rect().size, win.scaling_3d_scale])
	check(ProjectSettings.get_setting("display/window/stretch/mode") == "canvas_items", "растяжение canvas_items")
	var logical := win.get_visible_rect().size
	check(logical.y <= 721.0 and logical.y >= 719.0, "логическая высота 720 при любом окне (%s)" % logical)
	await shot("%s_01_menu" % tag)
	var menu := scene.get(&"_menu") as Control
	var settings := scene.get(&"settings") as Control
	menu.visible = false
	settings.visible = true
	await wait(0.3)
	var r := settings.get_global_rect()
	check(r.position.x >= 0.0 and r.position.y >= 0.0 and r.end.x <= logical.x + 1.0 and r.end.y <= logical.y + 1.0,
		"настройки влезают в экран (%s)" % r)
	await shot("%s_02_settings" % tag)
	(settings as SettingsPanel).close()
	scene.call(&"open_lobby")
	await wait(0.3)
	await shot("%s_03_lobby" % tag)
	var lobby := scene.get(&"lobby") as Control
	var lr := lobby.get_global_rect()
	check(lr.end.y <= logical.y + 1.0, "лобби влезает в экран (%s)" % lr)
	lobby.visible = false
	menu.visible = true
	# ползунок масштаба интерфейса
	Settings.ui_scale = 1.25
	Settings.apply_window()
	await wait(0.3)
	check(absf(win.content_scale_factor - 1.25) < 0.001, "масштаб интерфейса 125 %")
	await shot("%s_04_menu_ui125" % tag)
	Settings.ui_scale = 1.0
	Settings.apply_window()
	# 3D-разрешение не привязано к интерфейсу: масштаб 3D задаёт только пресет/ползунок
	var s3d := win.scaling_3d_scale
	Settings.ui_scale = 0.75
	Settings.apply_window()
	check(absf(win.scaling_3d_scale - s3d) < 0.001, "масштаб интерфейса не меняет разрешение 3D")
	Settings.ui_scale = 1.0
	Settings.apply_window()
