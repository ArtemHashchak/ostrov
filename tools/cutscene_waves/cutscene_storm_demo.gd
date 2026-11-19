extends Node3D
## Демо-сцена снимка волн для кат-сцен: камера высоко над штормовым морем,
## ливень, молнии. Самостоятельная: не зависит от World/Sky3D/погоды игры —
## только CutsceneOcean из этой папки. Запуск: открыть cutscene_storm_demo.tscn и F6.
##
## Параметры (инспектор): шторм, ветер, высота и скорость облёта камеры.

@export_range(0.0, 1.0) var storm := 1.0
@export var wind_speed := 26.0              # м/с: штиль 3 … шторм 18–28
@export var wind_dir := Vector2(1.0, 0.35)
@export var cam_height := 85.0
@export var cam_radius := 140.0
@export var orbit_speed := 0.025            # рад/с
@export var night := false
@export var lightning := true

const AREA := Rect2(-700.0, -700.0, 1400.0, 1400.0)

var ocean: CutsceneOcean
var cam: Camera3D
var sun: DirectionalLight3D
var env: Environment
var _flash_light: DirectionalLight3D
var _t := 0.0
var _next_flash := 3.0
var _flash := 0.0
var _rng := RandomNumberGenerator.new()
var _rain: GPUParticles3D

## Простой рельеф: дно ~−18 м и несколько островов (для пены у берега и мелководья).
static func height_at(x: float, z: float) -> float:
	var h := -18.0
	var isl: Array[Vector3] = [Vector3(40.0, -30.0, 70.0), Vector3(-220.0, 160.0, 45.0), Vector3(260.0, 210.0, 55.0), Vector3(-150.0, -260.0, 35.0)]
	for c: Vector3 in isl:
		var d: float = Vector2(x - c.x, z - c.y).length() / c.z
		# купол острова + пологий шельф (пляж и отмель для прибоя)
		h = maxf(h, 9.0 * exp(-d * d * 1.3) + 6.0 * exp(-d * d * 0.35) - 6.5)
	return h

func _ready() -> void:
	_rng.seed = 7
	_make_env()
	_make_islands()
	ocean = CutsceneOcean.new()
	add_child(ocean)
	ocean.build(height_at, AREA)
	cam = Camera3D.new()
	cam.far = 6000.0
	cam.fov = 60.0
	add_child(cam)
	cam.make_current()
	_make_rain()

func _make_env() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var ps := ProceduralSkyMaterial.new()
	sky.sky_material = ps
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, 40.0, 0.0)
	sun.shadow_enabled = false
	add_child(sun)
	_flash_light = DirectionalLight3D.new()
	_flash_light.rotation_degrees = Vector3(-80.0, 0.0, 0.0)
	_flash_light.light_color = Color(0.8, 0.85, 1.0)
	_flash_light.light_energy = 0.0
	add_child(_flash_light)
	_apply_look()

func _apply_look() -> void:
	var ps := env.sky.sky_material as ProceduralSkyMaterial
	var day := Color(0.36, 0.40, 0.44).lerp(Color(0.45, 0.62, 0.85), 1.0 - storm)
	var horizon := Color(0.42, 0.46, 0.5).lerp(Color(0.7, 0.8, 0.9), 1.0 - storm)
	var k := 0.18 if night else 1.0
	ps.sky_top_color = day * k
	ps.sky_horizon_color = horizon * k
	ps.ground_horizon_color = horizon * k * 0.9
	ps.ground_bottom_color = Color(0.1, 0.12, 0.14) * k
	ps.sun_angle_max = 0.0 if storm > 0.5 else 30.0
	env.fog_light_color = horizon * k
	env.fog_density = lerpf(0.0004, 0.0022, storm)
	sun.light_energy = lerpf(1.2, 0.35, storm) * (0.12 if night else 1.0)
	sun.light_color = Color(1.0, 0.96, 0.9).lerp(Color(0.75, 0.8, 0.88), storm)
	if ocean:
		var tint := Color(0.5, 0.56, 0.72) if night else Color.WHITE
		ocean.set_night_tint(tint)

func _make_islands() -> void:
	var n := 220
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := AREA.size.x / n
	for j in n:
		for i in n:
			var x0 := AREA.position.x + i * step
			var z0 := AREA.position.y + j * step
			var q: Array[Vector2] = [Vector2(x0, z0), Vector2(x0 + step, z0), Vector2(x0 + step, z0 + step), Vector2(x0, z0 + step)]
			for t in [[0, 1, 2], [0, 2, 3]]:
				for k in t:
					var v: Vector2 = q[k]
					var h: float = height_at(v.x, v.y)
					st.set_color(Color(0.72, 0.66, 0.5).lerp(Color(0.2, 0.3, 0.15), smoothstep(1.2, 3.0, h)))
					st.add_vertex(Vector3(v.x, h, v.y))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.95
	mi.material_override = m
	add_child(mi)

func _make_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.amount = 6000
	_rain.lifetime = 1.6
	_rain.visibility_aabb = AABB(Vector3(-120, -120, -120), Vector3(240, 240, 240))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(110.0, 2.0, 110.0)
	pm.direction = Vector3(0.35, -1.0, 0.12)
	pm.spread = 3.0
	pm.initial_velocity_min = 55.0
	pm.initial_velocity_max = 70.0
	pm.gravity = Vector3.ZERO
	_rain.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.04, 1.6)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.albedo_color = Color(0.55, 0.6, 0.66, 0.35)
	q.material = m
	_rain.draw_pass_1 = q
	add_child(_rain)

func _process(dt: float) -> void:
	_t += dt
	var a := _t * orbit_speed
	cam.global_position = Vector3(cos(a) * cam_radius, cam_height, sin(a) * cam_radius)
	cam.look_at(Vector3(cos(a + 0.6) * cam_radius * 0.2, 0.0, sin(a + 0.6) * cam_radius * 0.2))
	_rain.global_position = cam.global_position + Vector3(0, 40.0, 0)
	_rain.emitting = storm > 0.3
	ocean.set_weather_drive(wind_dir, wind_speed, storm, 1.0 if storm > 0.3 else 0.0)
	ocean.update(dt, cam.global_position, 0.0, lerpf(1.0, 3.0, storm))
	_update_lightning(dt)

func _update_lightning(dt: float) -> void:
	if not lightning or storm < 0.5:
		_flash_light.light_energy = 0.0
		return
	_next_flash -= dt
	if _next_flash <= 0.0:
		_next_flash = _rng.randf_range(4.0, 11.0)
		_flash = 1.0
	if _flash > 0.0:
		# двойная вспышка: яркий пик и короткое мерцание
		var f := _flash
		var flick := 1.0 if f > 0.85 or (f > 0.55 and f < 0.68) else 0.35
		_flash_light.light_energy = 3.5 * f * flick
		env.background_energy_multiplier = 1.0 + 2.5 * f * flick
		_flash = maxf(0.0, _flash - dt * 2.6)
	else:
		_flash_light.light_energy = 0.0
		env.background_energy_multiplier = 1.0
