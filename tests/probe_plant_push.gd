## test-timeout: 600
extends TestCase
## Снимки касания кустов (v5.1, агент H): вид игрока, идущего сквозь алоказию/колоказию.
## Глобальные plant_push_a/plant_trail_a задаются напрямую (без SkyWeather) — проверяется шейдер.
## PUSH_TAG=before|after — в имени файла. Снимки: tests/shots/probe_plant_push_<tag>_*.png

func _init() -> void:
	scene_path = "res://tests/empty_stage.tscn"
	timeout_sec = 600.0

var cam: Camera3D

func _plant(id: String, pos: Vector3, rot: float) -> void:
	var n := AssetCatalog.instantiate(id)
	if n == null:
		check(false, "растение %s" % id)
		return
	scene.add_child(n)
	n.global_position = pos
	n.rotation.y = rot

func _set_push(pa: Vector4, tr: Vector4) -> void:
	RenderingServer.global_shader_parameter_set(&"plant_push_a", pa)
	RenderingServer.global_shader_parameter_set(&"plant_trail_a", tr)
	RenderingServer.global_shader_parameter_set(&"plant_push_b", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"plant_push_c", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"plant_trail_b", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"plant_trail_c", Vector4.ZERO)

func run() -> void:
	var tag := OS.get_environment("PUSH_TAG") if OS.get_environment("PUSH_TAG") != "" else "after"
	var r := 0.75 if tag == "before" else 0.35   # прежний шейдер брал радиус 0,75 у персонажа
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.72, 0.9)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.8, 0.85)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	scene.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	scene.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.32, 0.27, 0.18)
	ground.material_override = gm
	scene.add_child(ground)
	# ряд кустов: игрок идёт по оси −Z сквозь средний
	_plant("flora_alocasia_big_01", Vector3(0, 0, -3.0), 0.3)
	_plant("flora_colocasia1_01", Vector3(-2.4, 0, -6.0), 1.1)
	_plant("flora_alocasia_big_03", Vector3(2.3, 0, -3.2), 2.0)
	_plant("flora_alocasia_var_01", Vector3(0.4, 0, -6.0), 0.7)
	cam = Camera3D.new()
	scene.add_child(cam)
	cam.current = true
	cam.fov = 75.0
	cam.global_position = Vector3(0.2, 1.62, -0.6)
	cam.look_at(Vector3(0.0, 0.7, -4.0), Vector3.UP)
	# 1) никто не касается
	_set_push(Vector4.ZERO, Vector4.ZERO)
	await wait(0.8)
	await shot("%s_1_idle" % tag)
	# 2) игрок вошёл в средний куст (ноги у края, идёт в −Z)
	_set_push(Vector4(0.15, 0.0, -2.35, r), Vector4(0.15, 0.0, -1.6, 0.9))
	await wait(0.4)
	await shot("%s_2_push" % tag)
	# тот же момент сбоку
	cam.global_position = Vector3(-3.0, 1.4, -2.7)
	cam.look_at(Vector3(0.0, 0.6, -3.0), Vector3.UP)
	await wait(0.3)
	await shot("%s_2b_push_side" % tag)
	_set_push(Vector4.ZERO, Vector4.ZERO)
	await wait(0.3)
	await shot("%s_2c_idle_side" % tag)
	# 3) игрок прошёл куст насквозь — куст качается
	_set_push(Vector4(0.1, 0.0, -4.4, r), Vector4(0.1, 0.0, -3.1, 0.8))
	cam.global_position = Vector3(1.6, 1.62, -1.0)
	cam.look_at(Vector3(0.0, 0.7, -3.0), Vector3.UP)
	await wait(0.15)
	await shot("%s_3_shake" % tag)
	check(true, "снимки сделаны")
