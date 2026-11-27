class_name AfterRainFx
extends Node3D
## v5.2: мелкая погодная жизнь вокруг камеры (CONTRACT_WEATHER), всё — GPU-частицы без аллокаций
## в кадре, количество по пресету графики:
##  · капли с листьев — под пологом джунглей в дождь и ещё ~минуты после (пока листва мокрая);
##  · пар от земли — солнце после дождя, тёплая сырая земля (днём, без дождя);
##  · утренний туман над джунглями — низкий слой мягких клубов на рассвете (5–9 ч), гуще после
##    дождливой ночи; в Forward+ на «Высоком»+ ещё и объёмный туман (FogVolume) у земли;
##  · листья падают сами — в лесу в тихую погоду изредка кружат одиночные листья;
##  · пепел по ветру — от горящих костров (группа campfire) уносит хлопья пепла;
##  · роса — глобальный uniform dew_amount (0..1) для шейдеров листвы на рассвете.
## Вызов: SkyWeather.update → update_fx(...).

## [капли, пар, туман, листья, пепел] по пресету Низкое..Ультра
const AMOUNTS := [[60, 10, 6, 4, 20], [140, 18, 10, 6, 40], [240, 28, 16, 10, 60], [360, 40, 22, 14, 90]]

var drips: GPUParticles3D
var steam: GPUParticles3D
var mist: GPUParticles3D
var leaves: GPUParticles3D
var ash: GPUParticles3D
var fog_volume: FogVolume
var _drip_pm: ParticleProcessMaterial
var _steam_mat: StandardMaterial3D
var _mist_mat: StandardMaterial3D
var _ash_pm: ParticleProcessMaterial
var _leaf_pm: ParticleProcessMaterial
var _leaf_mat: StandardMaterial3D
var _wet_leaves := 0.0       # 0..1 — листва ещё мокрая после дождя (капает)
var _ground_warm_wet := 0.0  # 0..1 — тёплая сырая земля (пар)
var dew := 0.0
var mist_k := 0.0
var _fire_t := 0.0
var _fire_pos := Vector3.INF
var state := {}               # для тестов: что сейчас включено

func _ready() -> void:
	name = "AfterRainFx"
	drips = _particles("LeafDrips", 0.9, Vector3(9.0, 1.0, 9.0))
	_drip_pm = drips.process_material as ParticleProcessMaterial
	_drip_pm.gravity = Vector3(0, -9.8, 0)
	_drip_pm.initial_velocity_min = 0.0
	_drip_pm.initial_velocity_max = 0.3
	_drip_pm.particle_flag_align_y = true
	_drip_pm.scale_min = 0.8
	_drip_pm.scale_max = 1.3
	var dq := QuadMesh.new()
	dq.size = Vector2(0.012, 0.07)
	var dm := StandardMaterial3D.new()
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.albedo_color = Color(0.8, 0.88, 0.95, 0.55)
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	dq.material = dm
	drips.draw_pass_1 = dq

	steam = _particles("GroundSteam", 6.0, Vector3(14.0, 0.2, 14.0))
	var spm := steam.process_material as ParticleProcessMaterial
	spm.gravity = Vector3(0, 0.12, 0)
	spm.direction = Vector3(0, 1, 0)
	spm.spread = 20.0
	spm.initial_velocity_min = 0.05
	spm.initial_velocity_max = 0.2
	spm.scale_min = 0.8
	spm.scale_max = 1.8
	spm.color_ramp = _fade_ramp(0.0, 0.5, 0.0)
	var sq := QuadMesh.new()
	sq.size = Vector2(1.6, 1.0)
	_steam_mat = _soft_mat(Color(0.92, 0.94, 0.96, 0.16))
	sq.material = _steam_mat
	steam.draw_pass_1 = sq

	mist = _particles("JungleMist", 14.0, Vector3(30.0, 1.2, 30.0))
	var mpm := mist.process_material as ParticleProcessMaterial
	mpm.gravity = Vector3.ZERO
	mpm.direction = Vector3(1, 0, 0)
	mpm.spread = 180.0
	mpm.initial_velocity_min = 0.05
	mpm.initial_velocity_max = 0.25
	mpm.scale_min = 1.0
	mpm.scale_max = 2.0
	mpm.color_ramp = _fade_ramp(0.0, 1.0, 0.0)
	var mq := QuadMesh.new()
	mq.size = Vector2(9.0, 3.2)
	_mist_mat = _soft_mat(Color(0.88, 0.91, 0.93, 0.13))
	mq.material = _mist_mat
	mist.draw_pass_1 = mq

	leaves = _particles("CalmLeaves", 7.0, Vector3(12.0, 0.5, 12.0))
	_leaf_pm = leaves.process_material as ParticleProcessMaterial
	_leaf_pm.gravity = Vector3(0, -0.45, 0)
	_leaf_pm.initial_velocity_min = 0.0
	_leaf_pm.initial_velocity_max = 0.2
	_leaf_pm.angular_velocity_min = -160.0
	_leaf_pm.angular_velocity_max = 160.0
	_leaf_pm.turbulence_enabled = true
	_leaf_pm.turbulence_noise_strength = 0.8
	_leaf_pm.turbulence_noise_scale = 2.0
	_leaf_pm.turbulence_influence_min = 0.05
	_leaf_pm.turbulence_influence_max = 0.15
	var gr := Gradient.new()
	gr.set_color(0, Color(0.5, 0.6, 0.25))
	gr.set_color(1, Color(0.62, 0.45, 0.2))
	var gt := GradientTexture1D.new()
	gt.gradient = gr
	_leaf_pm.color_initial_ramp = gt
	var lq := QuadMesh.new()
	lq.size = Vector2(0.12, 0.08)
	_leaf_mat = StandardMaterial3D.new()
	_leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_leaf_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_leaf_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_leaf_mat.alpha_scissor_threshold = 0.5
	_leaf_mat.vertex_color_use_as_albedo = true
	_leaf_mat.albedo_texture = RainFx._leaf_tex()
	lq.material = _leaf_mat
	leaves.draw_pass_1 = lq

	ash = _particles("CampfireAsh", 5.0, Vector3(0.4, 0.2, 0.4))
	_ash_pm = ash.process_material as ParticleProcessMaterial
	_ash_pm.gravity = Vector3(0, -0.15, 0)
	_ash_pm.spread = 35.0
	_ash_pm.turbulence_enabled = true
	_ash_pm.turbulence_noise_strength = 1.2
	_ash_pm.turbulence_influence_min = 0.05
	_ash_pm.turbulence_influence_max = 0.2
	_ash_pm.angular_velocity_min = -200.0
	_ash_pm.angular_velocity_max = 200.0
	_ash_pm.scale_min = 0.5
	_ash_pm.scale_max = 1.2
	_ash_pm.color_ramp = _fade_ramp(1.0, 1.0, 0.0)
	var aq := QuadMesh.new()
	aq.size = Vector2(0.035, 0.035)
	var am := StandardMaterial3D.new()
	am.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	am.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	am.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	am.vertex_color_use_as_albedo = true
	am.albedo_color = Color(0.32, 0.3, 0.28, 0.85)
	aq.material = am
	ash.draw_pass_1 = aq

	if not GraphicsQuality.is_compat():
		fog_volume = FogVolume.new()
		fog_volume.name = "MorningFogVolume"
		fog_volume.size = Vector3(90.0, 7.0, 90.0)
		fog_volume.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
		var fm := FogMaterial.new()
		fm.density = 0.0
		fm.albedo = Color(0.9, 0.92, 0.94)
		fm.edge_fade = 0.35
		fog_volume.material = fm
		fog_volume.visible = false
		add_child(fog_volume)
	_apply_quality()
	if not Settings.graphics_changed.is_connected(_apply_quality):
		Settings.graphics_changed.connect(_apply_quality)

func _exit_tree() -> void:
	if Settings.graphics_changed.is_connected(_apply_quality):
		Settings.graphics_changed.disconnect(_apply_quality)
	RenderingServer.global_shader_parameter_set(&"dew_amount", 0.0)
	RenderingServer.global_shader_parameter_set(&"fire_glow", Vector4(0, -1000, 0, 0))

func _apply_quality() -> void:
	var a: Array = AMOUNTS[clampi(Settings.graphics_quality, 0, 3)]
	drips.amount = int(a[0])
	steam.amount = int(a[1])
	mist.amount = int(a[2])
	leaves.amount = int(a[3])
	ash.amount = int(a[4])

func _particles(nm: String, life: float, box: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = nm
	p.local_coords = false
	p.lifetime = life
	p.visibility_aabb = AABB(Vector3(-40, -20, -40), Vector3(80, 40, 80))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = box
	pm.direction = Vector3(0, -1, 0)
	p.process_material = pm
	p.emitting = false
	add_child(p)
	return p

func _fade_ramp(a0: float, a1: float, a2: float) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, a0), Color(1, 1, 1, a1), Color(1, 1, 1, a2)])
	var t := GradientTexture1D.new()
	t.gradient = g
	return t

func _soft_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = c
	m.albedo_texture = RainFx._soft_dot()
	m.disable_receive_shadows = true
	return m

## Каждый кадр из SkyWeather.update.
## canopy 0..1 — полог над камерой; hour — время суток; sun 0..1 — прямое солнце (день и без туч);
## ground_h — земля под камерой; covered — крыша над камерой (капли не идут).
func update_fx(dt: float, cam: Camera3D, rain: float, wetness: float, storm: float, canopy: float,
		hour: float, sun: float, light: float, wdir: Vector2, wspeed: float, ground_h: float,
		underwater: bool, covered: bool, forest: float) -> void:
	if cam == null:
		return
	var cp := cam.global_position
	var above := cp.y - ground_h
	var on_ground := above < 14.0 and not underwater
	# --- капли с листьев: идёт дождь или листва ещё мокрая (сохнет ~3 мин; на солнце быстрее)
	if rain > 0.08:
		_wet_leaves = minf(1.0, _wet_leaves + dt * 0.5)
	else:
		_wet_leaves = maxf(0.0, _wet_leaves - dt / (180.0 - 100.0 * sun))
	var drip_k := canopy * maxf(_wet_leaves, clampf(rain * 1.2, 0.0, 1.0)) * (0.35 if covered else 1.0)
	drips.emitting = drip_k > 0.05 and on_ground
	if drips.emitting:
		drips.amount_ratio = clampf(drip_k, 0.05, 1.0)
		drips.global_position = Vector3(cp.x, ground_h + 5.5, cp.z)
		(drips.draw_pass_1.surface_get_material(0) as StandardMaterial3D).albedo_color = Color(0.8, 0.88, 0.95, 0.35 + 0.3 * light)
	# --- пар: после дождя на тёплой сырой земле под солнцем (не в дождь, не в лесу под пологом)
	var target_steam := 0.0
	if rain < 0.04 and wetness > 0.25 and sun > 0.45 and hour > 8.0 and hour < 17.0:
		target_steam = smoothstep(0.25, 0.75, wetness) * smoothstep(0.45, 0.9, sun) * (1.0 - canopy * 0.6)
	_ground_warm_wet = move_toward(_ground_warm_wet, target_steam, dt / 8.0)
	steam.emitting = _ground_warm_wet > 0.05 and on_ground
	if steam.emitting:
		steam.amount_ratio = clampf(_ground_warm_wet, 0.05, 1.0)
		steam.global_position = Vector3(cp.x, ground_h + 0.25, cp.z)
		_steam_mat.albedo_color = Color(0.93, 0.95, 0.97, 0.18 * light)
	# --- утренний туман над джунглями: 5–9 ч, тихо, в лесных зонах; гуще после дождя/сырости
	var morning := smoothstep(4.6, 5.6, hour) * (1.0 - smoothstep(8.0, 9.5, hour))
	var calm := 1.0 - smoothstep(4.0, 9.0, wspeed)
	var tgt_mist := morning * calm * forest * (0.55 + 0.45 * clampf(wetness * 1.5, 0.0, 1.0)) * (1.0 - storm)
	mist_k = move_toward(mist_k, tgt_mist, dt / 20.0)
	mist.emitting = mist_k > 0.04 and not underwater and above < 60.0
	if mist.emitting:
		mist.amount_ratio = clampf(mist_k, 0.1, 1.0)
		mist.global_position = Vector3(cp.x, ground_h + 2.2, cp.z)
		_mist_mat.albedo_color = Color(0.9, 0.92, 0.94, 0.16 * clampf(light, 0.35, 1.0))
	if fog_volume:
		fog_volume.visible = mist_k > 0.04 and bool(GraphicsQuality.preset().get("vol_fog", false))
		if fog_volume.visible:
			fog_volume.global_position = Vector3(cp.x, ground_h + 2.5, cp.z)
			(fog_volume.material as FogMaterial).density = 0.06 * mist_k
	# --- листья падают сами: лес, тихо (в шторм листья — RainFx), днём и ночью
	var lk := forest * calm * (1.0 - clampf(rain * 2.0, 0.0, 1.0))
	leaves.emitting = lk > 0.15 and on_ground
	if leaves.emitting:
		leaves.amount_ratio = clampf(lk, 0.1, 1.0)
		leaves.global_position = Vector3(cp.x, ground_h + 7.0, cp.z)
		_leaf_pm.direction = Vector3(wdir.x * 0.3, -1.0, wdir.y * 0.3).normalized()
		var ll := clampf(light, 0.3, 1.1)
		_leaf_mat.albedo_color = Color(ll, ll, ll)
	# --- пепел от ближайшего горящего костра уносит ветром
	_fire_t -= dt
	if _fire_t <= 0.0:
		_fire_t = 0.5
		_fire_pos = _nearest_fire(cp, 80.0)
	# отражение костра на воде (ocean.gdshader: fire_glow); ярче в темноте
	if _fire_pos != Vector3.INF:
		RenderingServer.global_shader_parameter_set(&"fire_glow", Vector4(_fire_pos.x, _fire_pos.y + 0.5, _fire_pos.z,
				clampf(1.15 - light, 0.15, 1.0)))
	else:
		RenderingServer.global_shader_parameter_set(&"fire_glow", Vector4(0, -1000, 0, 0))
	state["fire_glow"] = _fire_pos != Vector3.INF
	ash.emitting = _fire_pos != Vector3.INF and wspeed > 1.5 and rain < 0.5
	if ash.emitting:
		ash.global_position = _fire_pos + Vector3(0, 0.7, 0)
		_ash_pm.direction = Vector3(wdir.x, 0.35, wdir.y).normalized()
		_ash_pm.initial_velocity_min = wspeed * 0.25
		_ash_pm.initial_velocity_max = wspeed * 0.55
		ash.amount_ratio = clampf(wspeed / 10.0, 0.2, 1.0)
	# --- роса: рассвет после ясной ночи (4,5–9 ч), высыхает к 9–10 ч; дождь смывает
	var dew_t := smoothstep(4.0, 5.5, hour) * (1.0 - smoothstep(8.5, 10.0, hour)) * calm * (1.0 - clampf(rain * 3.0, 0.0, 1.0))
	dew = move_toward(dew, dew_t, dt / 30.0)
	RenderingServer.global_shader_parameter_set(&"dew_amount", dew)
	state.merge({"drips": drips.emitting, "steam": steam.emitting, "mist": mist.emitting,
		"leaves": leaves.emitting, "ash": ash.emitting, "dew": dew, "mist_k": mist_k,
		"wet_leaves": _wet_leaves, "steam_k": _ground_warm_wet}, true)

func _nearest_fire(p: Vector3, r: float) -> Vector3:
	var best := Vector3.INF
	var bd := r * r
	for f in get_tree().get_nodes_in_group(&"campfire"):
		if f is Node3D and bool(f.get(&"lit")):
			var d := (f as Node3D).global_position.distance_squared_to(p)
			if d < bd:
				bd = d
				best = (f as Node3D).global_position
	return best
