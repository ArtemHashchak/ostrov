class_name RainFx
extends Node3D
## Дождь вокруг камеры (CONTRACT_WEATHER): ближние капли-штрихи (GPU-частицы, наклон по
## ветру), два дальних слоя-цилиндра с процедурными штрихами, брызги на земле/воде,
## листья и брызги моря в шторм. Под крышей ближние капли/брызги не идут.
## Всё ограничено пресетом графики; аллокаций в кадре нет.

const FALL_SPEED := 11.0

## [ближние капли, брызги, листья, морские брызги] по пресету Низкое..Ультра
const AMOUNTS := [[1300, 50, 20, 40], [2700, 110, 40, 80], [4800, 200, 70, 140], [7600, 300, 100, 200]]

var drops: GPUParticles3D
var splashes: GPUParticles3D
var leaves: GPUParticles3D
var spray: GPUParticles3D
const SEA_SPRAY_ENABLED := false
var sheets: Array[MeshInstance3D] = []
## Дальняя завеса ливня (шторм): цилиндр ~110 м, полосы плывут по ветру.
var curtain: MeshInstance3D
var _curtain_mat: ShaderMaterial
var _curtain_drift := 0.0
var _drop_pm: ParticleProcessMaterial
var _leaf_pm: ParticleProcessMaterial
var _spray_pm: ParticleProcessMaterial
var _drop_mat: ShaderMaterial
var _splash_mat: StandardMaterial3D
var _leaf_mat: StandardMaterial3D
var _sheet_mats: Array[ShaderMaterial] = []
var _rain := 0.0
var covered := false
var _cover_t := 0.0
var _space: PhysicsDirectSpaceState3D
var _ray := PhysicsRayQueryParameters3D.new()

func _ready() -> void:
	name = "RainFx"
	_make_drops()
	_make_sheets()
	_make_curtain()
	_make_splashes()
	_make_leaves()
	_make_spray()
	_apply_quality()
	if not Settings.graphics_changed.is_connected(_apply_quality):
		Settings.graphics_changed.connect(_apply_quality)

func _exit_tree() -> void:
	if Settings.graphics_changed.is_connected(_apply_quality):
		Settings.graphics_changed.disconnect(_apply_quality)

func _apply_quality() -> void:
	var a: Array = AMOUNTS[clampi(Settings.graphics_quality, 0, 3)]
	drops.amount = int(a[0])
	splashes.amount = int(a[1])
	leaves.amount = int(a[2])
	spray.amount = int(a[3])
	# дальний слой на «Низком» не нужен
	if sheets.size() > 1:
		sheets[1].visible = Settings.graphics_quality > 0 and _rain > 0.02

func _big_aabb() -> AABB:
	return AABB(Vector3(-60, -60, -60), Vector3(120, 120, 120))

func _make_drops() -> void:
	drops = GPUParticles3D.new()
	drops.name = "Drops"
	drops.local_coords = false
	drops.lifetime = 1.25
	drops.preprocess = 1.25
	drops.fixed_fps = 0
	drops.visibility_aabb = _big_aabb()
	drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_drop_pm = ParticleProcessMaterial.new()
	_drop_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_drop_pm.emission_box_extents = Vector3(15.0, 1.5, 15.0)
	_drop_pm.direction = Vector3(0, -1, 0)
	_drop_pm.spread = 2.5
	_drop_pm.initial_velocity_min = FALL_SPEED * 0.9
	_drop_pm.initial_velocity_max = FALL_SPEED * 1.1
	_drop_pm.gravity = Vector3.ZERO
	_drop_pm.particle_flag_align_y = true
	drops.process_material = _drop_pm
	var qm := QuadMesh.new()
	qm.size = Vector2(1.0, 1.0)
	_drop_mat = ShaderMaterial.new()
	_drop_mat.shader = load("res://scripts/world/weather/rain_streak.gdshader") as Shader
	qm.material = _drop_mat
	drops.draw_pass_1 = qm
	drops.emitting = false
	add_child(drops)

func _make_sheets() -> void:
	var sh := load("res://scripts/world/weather/rain_sheet.gdshader") as Shader
	# [радиус, высота, колонок, прозрачность, скорость]
	for cfg in [[8.0, 26.0, 900.0, 0.15, 2.6], [22.0, 46.0, 1800.0, 0.11, 2.0]]:
		var mi := MeshInstance3D.new()
		mi.name = "RainSheet%d" % sheets.size()
		var cm := CylinderMesh.new()
		cm.top_radius = cfg[0]
		cm.bottom_radius = cfg[0]
		cm.height = cfg[1]
		cm.radial_segments = 32
		cm.rings = 1
		cm.cap_top = false
		cm.cap_bottom = false
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter(&"columns", cfg[2])
		m.set_shader_parameter(&"rows", cfg[1] / 3.2)
		m.set_shader_parameter(&"speed", -float(cfg[4]))
		m.set_shader_parameter(&"color", Color(0.82, 0.86, 0.92, cfg[3]))
		m.set_shader_parameter(&"streak_len", 0.13)
		m.set_shader_parameter(&"thickness", 0.12)
		m.set_shader_parameter(&"soft_dist", 3.0 if cfg[0] < 10.0 else 8.0)
		cm.material = m
		mi.mesh = cm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 40.0
		mi.visible = false
		add_child(mi)
		sheets.append(mi)
		_sheet_mats.append(m)

func _make_curtain() -> void:
	curtain = MeshInstance3D.new()
	curtain.name = "RainCurtain"
	var cm := CylinderMesh.new()
	cm.top_radius = 110.0
	cm.bottom_radius = 110.0
	cm.height = 90.0
	cm.radial_segments = 48
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	_curtain_mat = ShaderMaterial.new()
	_curtain_mat.shader = load("res://scripts/world/weather/rain_curtain.gdshader") as Shader
	# пелена плавно «набирается» за 45 м за стеной цилиндра — без видимой границы на воде/суше
	_curtain_mat.set_shader_parameter(&"soft_dist", 45.0)
	cm.material = _curtain_mat
	curtain.mesh = cm
	curtain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	curtain.extra_cull_margin = 200.0
	curtain.visible = false
	add_child(curtain)

func _make_splashes() -> void:
	# Брызги капель: маленькие «коронки» (дуга из капелек), освещённые как вода, а не
	# светящиеся точки. Короткая жизнь, мало штук, гаснут с расстоянием (не видны дальше ~7 м).
	splashes = GPUParticles3D.new()
	splashes.name = "Splashes"
	splashes.local_coords = false
	splashes.lifetime = 0.22
	splashes.visibility_aabb = _big_aabb()
	splashes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(7.0, 0.01, 7.0)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 0.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.6
	pm.scale_max = 1.1
	var sc := CurveTexture.new()
	var cv := Curve.new()
	cv.add_point(Vector2(0, 0.35))
	cv.add_point(Vector2(0.35, 1.0))
	cv.add_point(Vector2(1, 1.15))
	cv.max_value = 1.2
	sc.curve = cv
	pm.scale_curve = sc
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 0.0))
	gr.add_point(0.15, Color(1, 1, 1, 1.0))
	gr.set_color(gr.get_point_count() - 1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = gr
	pm.color_ramp = gt
	splashes.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.09, 0.055)
	qm.center_offset = Vector3(0, 0.0275, 0)
	_splash_mat = StandardMaterial3D.new()
	# освещается сценой (ночью тёмное, днём — как вода), без собственной яркости
	_splash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_splash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_splash_mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	_splash_mat.billboard_keep_scale = true
	_splash_mat.vertex_color_use_as_albedo = true
	_splash_mat.albedo_color = Color(0.62, 0.68, 0.72, 0.38)
	_splash_mat.albedo_texture = _crown_tex()
	_splash_mat.roughness = 0.15
	_splash_mat.specular = 0.6
	_splash_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_splash_mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	_splash_mat.distance_fade_min_distance = 7.0
	_splash_mat.distance_fade_max_distance = 2.5
	qm.material = _splash_mat
	splashes.draw_pass_1 = qm
	splashes.emitting = false
	add_child(splashes)

## Коронка брызг: дуга из 7 тонких «капелек-штрихов», расходящихся вверх-в-стороны, и
## тонкая основа (без круглого ядра — не читается как точка).
static var _crown_c: Texture2D
static func _crown_tex() -> Texture2D:
	if _crown_c:
		return _crown_c
	var w := 64
	var h := 40
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	for k in 7:
		var t := (k - 3) / 3.0                       # -1..1
		var ang := t * 1.0                           # наклон штриха наружу
		var base := Vector2(32.0 + t * 9.0, h - 3.0)
		var tip := base + Vector2(sin(ang), -cos(ang)) * (20.0 - absf(t) * 7.0)
		for s in 40:
			var q := s / 39.0
			var pt := base.lerp(tip, q)
			var rad := lerpf(1.1, 1.6, q)            # капля на кончике чуть толще
			for yy in range(int(pt.y - 2), int(pt.y + 3)):
				for xx in range(int(pt.x - 2), int(pt.x + 3)):
					if xx < 0 or yy < 0 or xx >= w or yy >= h:
						continue
					var dd := Vector2(xx + 0.5, yy + 0.5).distance_to(pt)
					var a := clampf(1.0 - dd / rad, 0.0, 1.0) * lerpf(0.55, 0.9, q)
					var c := img.get_pixel(xx, yy)
					if a > c.a:
						img.set_pixel(xx, yy, Color(1, 1, 1, a))
	# тонкая основа-«кольцо» сбоку
	for xx in range(18, 47):
		var a := 0.35 * (1.0 - absf(xx - 32.0) / 14.0)
		for yy in [h - 3, h - 2]:
			var c := img.get_pixel(xx, yy)
			img.set_pixel(xx, yy, Color(1, 1, 1, maxf(c.a, a)))
	img.generate_mipmaps()
	_crown_c = ImageTexture.create_from_image(img)
	return _crown_c

func _make_leaves() -> void:
	leaves = GPUParticles3D.new()
	leaves.name = "StormLeaves"
	leaves.local_coords = false
	leaves.lifetime = 3.0
	leaves.visibility_aabb = _big_aabb()
	leaves.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_leaf_pm = ParticleProcessMaterial.new()
	_leaf_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_leaf_pm.emission_box_extents = Vector3(16.0, 1.4, 16.0)
	_leaf_pm.spread = 25.0
	_leaf_pm.gravity = Vector3(0, -1.2, 0)
	_leaf_pm.angular_velocity_min = -360.0
	_leaf_pm.angular_velocity_max = 360.0
	_leaf_pm.turbulence_enabled = true
	_leaf_pm.turbulence_noise_strength = 2.5
	_leaf_pm.turbulence_noise_scale = 3.0
	_leaf_pm.turbulence_influence_min = 0.05
	_leaf_pm.turbulence_influence_max = 0.2
	_leaf_pm.scale_min = 0.6
	_leaf_pm.scale_max = 1.4
	_leaf_pm.color = Color(1, 1, 1)
	var gr := Gradient.new()
	gr.set_color(0, Color(0.42, 0.55, 0.22))
	gr.set_color(1, Color(0.55, 0.42, 0.2))
	var gt := GradientTexture1D.new()
	gt.gradient = gr
	_leaf_pm.color_initial_ramp = gt
	leaves.process_material = _leaf_pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.11, 0.07)
	# лист: силуэт-эллипс с прожилкой (альфа), без освещения — цвет из рампы × свет сцены
	_leaf_mat = StandardMaterial3D.new()
	_leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_leaf_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_leaf_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_leaf_mat.alpha_scissor_threshold = 0.5
	_leaf_mat.vertex_color_use_as_albedo = true
	_leaf_mat.albedo_texture = _leaf_tex()
	qm.material = _leaf_mat
	leaves.draw_pass_1 = qm
	leaves.emitting = false
	add_child(leaves)

func _make_spray() -> void:
	spray = GPUParticles3D.new()
	spray.name = "SeaSpray"
	spray.local_coords = false
	spray.lifetime = 2.2
	spray.visibility_aabb = _big_aabb()
	spray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spray_pm = ParticleProcessMaterial.new()
	_spray_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_spray_pm.emission_box_extents = Vector3(22.0, 0.3, 22.0)
	_spray_pm.spread = 30.0
	_spray_pm.gravity = Vector3(0, -0.6, 0)
	_spray_pm.scale_min = 1.0
	_spray_pm.scale_max = 2.6
	var sc := CurveTexture.new()
	var cv := Curve.new()
	cv.add_point(Vector2(0, 0.3))
	cv.add_point(Vector2(0.4, 1.0))
	cv.add_point(Vector2(1, 1.3))
	cv.max_value = 1.5
	sc.curve = cv
	_spray_pm.scale_curve = sc
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 0.0))
	gr.add_point(0.2, Color(1, 1, 1, 0.22))
	gr.set_color(gr.get_point_count() - 1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = gr
	_spray_pm.color_ramp = gt
	spray.process_material = _spray_pm
	var qm := QuadMesh.new()
	qm.size = Vector2(1.2, 0.7)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.9, 0.93, 0.95)
	m.albedo_texture = _soft_dot()
	qm.material = m
	spray.draw_pass_1 = qm
	spray.emitting = false
	add_child(spray)

static var _leaf_tex_c: Texture2D
static func _leaf_tex() -> Texture2D:
	if _leaf_tex_c:
		return _leaf_tex_c
	var img := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 32:
			var u := (x - 15.5) / 15.5
			var v := (y - 7.5) / 7.5
			var half := (1.0 - u * u) * 0.95
			var inside := absf(v) < half
			var vein := absf(v) < 0.12
			var c := 0.82 if vein else 1.0
			img.set_pixel(x, y, Color(c, c, c, 1.0 if inside else 0.0))
	_leaf_tex_c = ImageTexture.create_from_image(img)
	return _leaf_tex_c

static var _dot_tex: Texture2D
static func _soft_dot() -> Texture2D:
	if _dot_tex:
		return _dot_tex
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5).length() / 15.5
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	_dot_tex = ImageTexture.create_from_image(img)
	return _dot_tex

## Крыша над камерой? Луч вверх раз в 0.25 с (дёшево).
func _check_cover(cam_pos: Vector3, dt: float) -> void:
	_cover_t -= dt
	if _cover_t > 0.0:
		return
	_cover_t = 0.25
	if _space == null:
		var w := get_world_3d()
		if w:
			_space = w.direct_space_state
	if _space == null:
		return
	_ray.from = cam_pos + Vector3(0, 0.3, 0)
	_ray.to = cam_pos + Vector3(0, 14.0, 0)
	_ray.collide_with_areas = false
	var hit := _space.intersect_ray(_ray)
	covered = not hit.is_empty()

## Каждый кадр из SkyWeather.update.
## ground_h — высота земли/воды под камерой; sea_h — уровень моря у камеры (для морских брызг).
func update(dt: float, cam: Camera3D, rain: float, storm: float, wdir: Vector2, wspeed: float,
		light: float, underwater: bool, ground_h: float, sea_h: float, near_shore: bool) -> void:
	_rain = rain
	if cam == null:
		return
	var cp := cam.global_position
	_check_cover(cp, dt)
	var raining := rain > 0.02 and not underwater
	# горизонтальный снос капель ветром (капли падают ~11 м/с, ветер даёт до ~7 м/с сноса)
	var drift := wdir * minf(wspeed * 0.32, 7.5)
	var vel := Vector3(drift.x, -FALL_SPEED, drift.y)
	var vlen := vel.length()
	_drop_pm.direction = vel / vlen
	_drop_pm.initial_velocity_min = vlen * 0.92
	_drop_pm.initial_velocity_max = vlen * 1.08
	# излучатель выше камеры и против ветра — капли «приносит» в кадр
	var up := 10.5
	var t_fall := up / FALL_SPEED
	drops.global_position = cp + Vector3(-drift.x * t_fall, up, -drift.y * t_fall)
	drops.emitting = raining and not covered
	drops.amount_ratio = clampf(rain * 1.1, 0.05, 1.0)
	_drop_mat.set_shader_parameter(&"light", light)
	_drop_mat.set_shader_parameter(&"length", 0.55 + 0.35 * rain)
	# дальние слои: наклон по ветру
	var tilt := atan2(drift.length(), FALL_SPEED)
	var axis := Vector3(drift.y, 0.0, -drift.x)
	for i in sheets.size():
		var mi := sheets[i]
		var vis := raining and (i == 0 or Settings.graphics_quality > 0)
		mi.visible = vis
		if not vis:
			continue
		mi.global_position = cp + Vector3(0.0, 4.0 + 6.0 * i, 0.0)
		if axis.length_squared() > 1e-4:
			mi.global_basis = Basis(axis.normalized(), -tilt)
		else:
			mi.global_basis = Basis.IDENTITY
		var m := _sheet_mats[i]
		m.set_shader_parameter(&"amount", rain)
		m.set_shader_parameter(&"light", light)
		# под крышей ближний цилиндр дал бы штрихи прямо по стенам навеса — гасим
		m.set_shader_parameter(&"sheet_fade", 0.0 if (covered and i == 0) else 1.0)
	# дальняя завеса ливня: только в сильный дождь/шторм, не на «Низком»
	var ca := clampf(smoothstep(0.55, 1.0, rain) * 0.6 + smoothstep(0.3, 1.0, storm) * 0.6, 0.0, 1.0)
	curtain.visible = ca > 0.02 and not underwater and Settings.graphics_quality > 0
	if curtain.visible:
		curtain.global_position = Vector3(cp.x, sea_h + 44.0, cp.z)
		curtain.global_basis = Basis.IDENTITY
		_curtain_drift += dt * wspeed * 0.012
		_curtain_mat.set_shader_parameter(&"amount", ca)
		_curtain_mat.set_shader_parameter(&"light", light)
		_curtain_mat.set_shader_parameter(&"drift", _curtain_drift)
	# брызги у земли/воды под камерой
	splashes.global_position = Vector3(cp.x, ground_h + 0.02, cp.z)
	splashes.emitting = raining and not covered and cp.y - ground_h < 12.0
	splashes.amount_ratio = clampf(rain, 0.05, 1.0)
	# сцена уже освещает коронки; лишь чуть приглушаем в слабый дождь
	_splash_mat.albedo_color = Color(0.62, 0.68, 0.72, lerpf(0.22, 0.38, clampf(rain, 0.0, 1.0)))
	# листья и мусор в шторм
	var st := smoothstep(0.45, 0.9, storm)
	var on_land := ground_h > sea_h + 0.5
	leaves.emitting = st > 0.05 and not underwater and on_land
	leaves.amount_ratio = clampf(st, 0.05, 1.0)
	var ll := clampf(light, 0.3, 1.2)
	_leaf_mat.albedo_color = Color(ll, ll, ll)
	var lv := Vector3(wdir.x, 0.15, wdir.y)
	_leaf_pm.direction = lv.normalized()
	_leaf_pm.initial_velocity_min = wspeed * 0.45
	_leaf_pm.initial_velocity_max = wspeed * 0.8
	leaves.global_position = Vector3(cp.x - wdir.x * 12.0, ground_h + 1.6, cp.z - wdir.y * 12.0)
	# морские брызги у берега/над водой в шторм
	# морская пыль частицами выключена: на экране читалась как летающие белые точки
	# (отзыв пользователя); у берега шторм передают пена и прибой в шейдере океана
	spray.emitting = SEA_SPRAY_ENABLED and st > 0.1 and near_shore and not underwater
	spray.amount_ratio = clampf(st, 0.05, 1.0)
	_spray_pm.direction = Vector3(wdir.x, 0.35, wdir.y).normalized()
	_spray_pm.initial_velocity_min = wspeed * 0.25
	_spray_pm.initial_velocity_max = wspeed * 0.5
	spray.global_position = Vector3(cp.x - wdir.x * 10.0, sea_h + 0.4, cp.z - wdir.y * 10.0)

## Для тестов/оверлея: сколько частиц в работе.
func counts() -> Dictionary:
	return {
		"drops": drops.amount if drops.emitting else 0,
		"splashes": splashes.amount if splashes.emitting else 0,
		"leaves": leaves.amount if leaves.emitting else 0,
		"spray": spray.amount if spray.emitting else 0,
		"curtain": curtain.visible,
		"sheets": sheets.filter(func(s: MeshInstance3D) -> bool: return s.visible).size(),
		"covered": covered,
	}
