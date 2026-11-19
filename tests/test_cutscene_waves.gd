extends TestCase
## Снимок генератора волн для кат-сцен (tools/cutscene_waves): сцена грузится,
## волны идут, кадры сверху в грозу днём и ночью.

func _init() -> void:
	scene_path = "res://tools/cutscene_waves/cutscene_storm_demo.tscn"
	timeout_sec = 1500.0

func run() -> void:
	await wait(2.0)
	var demo := scene
	check(demo != null and demo.get(&"ocean") != null, "демо-сцена и CutsceneOcean созданы")
	if demo == null or demo.get(&"ocean") == null:
		return
	var oc: CutsceneOcean = demo.ocean
	var h0 := oc.wave_height(30.0, 40.0)
	await wait(1.5)
	var h1 := oc.wave_height(30.0, 40.0)
	check(absf(h1 - h0) > 0.001, "волны движутся (%.3f → %.3f)" % [h0, h1])
	# шторм уже устоялся? прогнать сглаживание погоды вперёд
	for i in 600:
		oc.set_weather_drive(Vector2(1.0, 0.35), 26.0, 1.0, 1.0)
		oc.update(0.2, demo.cam.global_position, 0.0, 3.0)
	await wait(1.0)
	await shot("top_storm_day")
	demo.cam_height = 45.0
	await wait(1.0)
	await shot("low_storm_day")
	demo.night = true
	demo.call(&"_apply_look")
	demo.cam_height = 85.0
	demo._next_flash = 0.0
	await wait(0.15)
	await shot("top_storm_night_flash")
	await wait(2.0)
	await shot("top_storm_night")
