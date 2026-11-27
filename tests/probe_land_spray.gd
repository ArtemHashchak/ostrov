## test-timeout: 300
extends TestCase
## v5.1 (агент H): что видно на песке в момент приземления после прыжка (выброс песка SandTracks._spray).
## Снимки через 0,05 / 0,2 / 0,5 с после приземления.

func _init() -> void:
	scene_path = "res://tests/empty_stage.tscn"
	timeout_sec = 280.0

class FakeWorld extends Node3D:
	func height_at(_x: float, _z: float) -> float:
		return 0.0

func run() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.72, 0.9)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.8, 0.8)
	env.environment = e
	scene.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	scene.add_child(sun)
	var fw := FakeWorld.new()
	scene.add_child(fw)
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	g.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.86, 0.78, 0.6)
	g.material_override = gm
	scene.add_child(g)
	var cam := Camera3D.new()
	scene.add_child(cam)
	cam.current = true
	cam.global_position = Vector3(0, 1.6, 1.6)
	cam.look_at(Vector3(0, 0, -0.3), Vector3.UP)
	var st: Node = SandTracks
	st.set(&"_world", fw)
	await wait(0.3)
	st.call(&"_spray", Vector2(0, -0.3), Vector2(0, -1), 1.0)
	await wait(0.05)
	await shot("t005")
	await wait(0.15)
	await shot("t020")
	await wait(0.3)
	await shot("t050")
	check(true, "снимки")
