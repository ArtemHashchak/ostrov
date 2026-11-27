class_name NatureDetails
extends Node3D
## v5.2: мелочи живой природы вокруг камеры (план 23.11, п. 93–136). Тик из SkyWeather.update.
##  · летучие рыбы — днём над открытой водой у камеры изредка выпрыгивает и планирует стайка;
##  · кокосы падают сами — с пальм в радиусе 45 м, в ветер чаще (ChoppableTree._drop_coconut);
##  · песок взмучивается — шаги персонажей и зверей на мелководье (0,15–1,3 м) поднимают облачко мути;
##  · следы улиток — на сыром песке на рассвете и после дождя появляются тонкие петляющие дорожки;
##  · туша → кости — павший крупный зверь со временем темнеет и оседает, на его месте остаются кости;
##  · брошенную еду растаскивают — еда на земле (ItemPickup) за минуты исчезает, к ней тянется
##    муравьиная дорожка (тёмные точки), на пляже — уносят крабы;
##  · скорлупа в разрытой кладке — у опустевшего гнезда черепахи (TurtleNest) остаются осколки.

const FISH_AMOUNT := [0, 10, 16, 24]

var fish: GPUParticles3D
var _fish_pm: ParticleProcessMaterial
var silt: GPUParticles3D
var ants: GPUParticles3D
var _fish_t := 8.0
var _coco_t := 20.0
var _snail_t := 10.0
var _scan_t := 0.0
var _walkers := {}        # id -> {t}
var _corpses := {}        # animal id -> {node, t, base_y}
var _food := {}           # pickup id -> {t, node}
var _nest_done := {}      # nest id -> true
var stats := {"fish_jumps": 0, "coconuts": 0, "silt": 0, "snail": 0, "bones": 0, "food_taken": 0, "shells": 0}

func _ready() -> void:
	name = "NatureDetails"
	_ensure_bone_item()
	fish = GPUParticles3D.new()
	fish.name = "FlyingFish"
	fish.local_coords = false
	fish.one_shot = true
	fish.explosiveness = 0.85
	fish.lifetime = 2.4
	fish.visibility_aabb = AABB(Vector3(-40, -10, -40), Vector3(80, 30, 80))
	_fish_pm = ParticleProcessMaterial.new()
	_fish_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_fish_pm.emission_box_extents = Vector3(3.0, 0.05, 3.0)
	_fish_pm.spread = 12.0
	_fish_pm.initial_velocity_min = 8.0
	_fish_pm.initial_velocity_max = 11.0
	_fish_pm.gravity = Vector3(0, -3.2, 0)   # планируют на «крыльях» — падают медленнее
	_fish_pm.particle_flag_align_y = false
	_fish_pm.scale_min = 0.8
	_fish_pm.scale_max = 1.2
	fish.process_material = _fish_pm
	var fq := QuadMesh.new()
	fq.size = Vector2(0.32, 0.12)
	var fm := StandardMaterial3D.new()
	fm.albedo_texture = _fish_tex()
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	fm.alpha_scissor_threshold = 0.4
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.metallic_specular = 0.8
	fm.roughness = 0.25
	fq.material = fm
	fish.draw_pass_1 = fq
	fish.emitting = false
	add_child(fish)

	silt = GPUParticles3D.new()
	silt.name = "ShallowSilt"
	silt.local_coords = false
	silt.one_shot = false
	silt.amount = 40
	silt.lifetime = 4.0
	silt.emitting = false
	silt.visibility_aabb = AABB(Vector3(-20, -10, -20), Vector3(40, 20, 40))
	var spm := ParticleProcessMaterial.new()
	spm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	spm.emission_sphere_radius = 0.25
	spm.gravity = Vector3(0, -0.05, 0)
	spm.spread = 180.0
	spm.initial_velocity_min = 0.05
	spm.initial_velocity_max = 0.25
	spm.scale_min = 0.6
	spm.scale_max = 1.6
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	spm.color_ramp = gt
	silt.process_material = spm
	var sq := QuadMesh.new()
	sq.size = Vector2(0.7, 0.5)
	var sm := StandardMaterial3D.new()
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sm.vertex_color_use_as_albedo = true
	sm.albedo_color = Color(0.72, 0.66, 0.52, 0.35)
	sm.albedo_texture = RainFx._soft_dot()
	sq.material = sm
	silt.draw_pass_1 = sq
	add_child(silt)

func _ensure_bone_item() -> void:
	var it := get_node_or_null(^"/root/Items")
	if it and it.has_method(&"register_item") and it.get(&"items") is Dictionary and not (it.get(&"items") as Dictionary).has(&"bone"):
		it.call(&"register_item", &"bone", "Кости", &"resource", 20, 0.4)

## Тик из SkyWeather: cam — камера, sky — SkyWeather (время/ветер/сырость).
func tick(dt: float, cam: Camera3D, sky: SkyWeather) -> void:
	if cam == null or sky == null:
		return
	var cp := cam.global_position
	var w := BuildEnv.world()
	_tick_fish(dt, cp, sky, w)
	_tick_coconuts(dt, cp, sky)
	_tick_silt(dt)
	_tick_snails(dt, cp, sky, w)
	_scan_t -= dt
	if _scan_t <= 0.0:
		_scan_t = 0.5
		_tick_corpses(0.5)
		_tick_food(0.5, cp)
		_tick_nests(cp)

# ---------------------------------------------------------------- летучие рыбы
func _tick_fish(dt: float, cp: Vector3, sky: SkyWeather, w: Node) -> void:
	_fish_t -= dt
	if _fish_t > 0.0:
		return
	_fish_t = randf_range(25.0, 70.0)
	var q := clampi(Settings.graphics_quality, 0, 3)
	if FISH_AMOUNT[q] == 0 or sky.daylight() < 0.4 or sky.storm_intensity() > 0.5 or w == null:
		return
	var wl := BuildEnv.water_level()
	if cp.y > wl + 40.0 or cp.y < wl - 0.5:
		return
	# точка над глубокой водой в 15–45 м, перед камерой
	for i in 6:
		var a := randf() * TAU
		var r := randf_range(15.0, 45.0)
		var p := Vector3(cp.x + cos(a) * r, wl, cp.z + sin(a) * r)
		if w.has_method(&"height_at") and float(w.call(&"height_at", p.x, p.z)) > wl - 4.0:
			continue
		fish.amount = FISH_AMOUNT[q]
		var dir := Vector3(randf() - 0.5, 0.0, randf() - 0.5).normalized()
		_fish_pm.direction = (dir + Vector3(0, 0.22, 0)).normalized()
		fish.global_position = p + Vector3(0, 0.05, 0)
		fish.restart()
		fish.emitting = true
		stats.fish_jumps += 1
		return

## Силуэт летучей рыбы: веретено + распахнутые грудные плавники, серебристо-синий.
static var _fish_tex_c: Texture2D
static func _fish_tex() -> Texture2D:
	if _fish_tex_c:
		return _fish_tex_c
	var img := Image.create(64, 24, false, Image.FORMAT_RGBA8)
	for y in 24:
		for x in 64:
			var u := (x + 0.5) / 64.0 * 2.0 - 1.0
			var v := (y + 0.5) / 24.0 * 2.0 - 1.0
			var body := pow(u / 0.95, 2.0) + pow(v / (0.28 * (1.0 - absf(u) * 0.5)), 2.0) < 1.0
			var fin := absf(u - 0.15) < 0.35 - absf(v) * 0.25 and absf(v) < 0.95 and absf(v) > 0.15
			var tail := u < -0.75 and absf(v) < (-0.75 - u) * 2.2 + 0.1
			if body or fin or tail:
				var c := Color(0.35, 0.5, 0.7) if v < 0.0 else Color(0.75, 0.8, 0.85)
				if fin:
					c = Color(0.55, 0.65, 0.75, 0.85)
				img.set_pixel(x, y, c)
	_fish_tex_c = ImageTexture.create_from_image(img)
	return _fish_tex_c

# ---------------------------------------------------------------- кокосы падают сами
func _tick_coconuts(dt: float, cp: Vector3, sky: SkyWeather) -> void:
	_coco_t -= dt * (1.0 + clampf((sky.wind_speed() - 4.0) / 4.0, 0.0, 4.0))
	if _coco_t > 0.0:
		return
	_coco_t = randf_range(60.0, 140.0)
	var cands: Array = []
	for t in get_tree().get_nodes_in_group(&"choppable"):
		if t is Node3D and int(t.get(&"coconuts")) > 0 and (t as Node3D).global_position.distance_to(cp) < 45.0:
			cands.append(t)
	if cands.is_empty():
		return
	var t: Node = cands[randi() % cands.size()]
	if t.has_method(&"_drop_coconut"):
		t.call(&"_drop_coconut", null)
		stats.coconuts += 1

# ---------------------------------------------------------------- муть на мелководье
func _tick_silt(_dt: float) -> void:
	var now := Time.get_ticks_msec() * 0.001
	var nodes: Array = get_tree().get_nodes_in_group(&"characters")
	nodes.append_array(get_tree().get_nodes_in_group(&"animals"))
	var any := false
	for n in nodes:
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var p := (n as Node3D).global_position
		var ws := BuildEnv.water_surface(p.x, p.z)
		if ws < -1e5:
			continue
		var w := BuildEnv.world()
		var gh := float(w.call(&"height_at", p.x, p.z)) if w and w.has_method(&"height_at") else p.y
		var depth := ws - gh
		if depth < 0.15 or depth > 1.3 or p.y - gh > 0.6:
			continue
		var vel := Vector3.ZERO
		var vv = n.get(&"velocity")
		if vv is Vector3:
			vel = vv
		var id: int = n.get_instance_id()
		var last: Vector3 = _walkers.get(id, {}).get("p", p)
		var spd := maxf(Vector2(vel.x, vel.z).length(), Vector2(p.x - last.x, p.z - last.z).length() * 2.0)
		_walkers[id] = {"p": p, "t": now}
		if spd < 0.6:
			continue
		silt.global_position = Vector3(p.x, gh + 0.12, p.z)
		silt.emitting = true
		silt.amount_ratio = clampf(spd / 4.0, 0.3, 1.0)
		any = true
		stats.silt += 1
		break
	if not any:
		silt.emitting = false

# ---------------------------------------------------------------- следы улиток
func _tick_snails(dt: float, cp: Vector3, sky: SkyWeather, w: Node) -> void:
	_snail_t -= dt
	if _snail_t > 0.0:
		return
	_snail_t = randf_range(12.0, 25.0)
	var h := sky.time_of_day()
	var dawn := h > 4.5 and h < 9.0
	if not (dawn or sky.wetness() > 0.4) or w == null:
		return
	var st := get_node_or_null(^"/root/SandTracks")
	if st == null or not st.has_method(&"drag_mark"):
		return
	for i in 4:
		var a := randf() * TAU
		var r := randf_range(3.0, 10.0)
		var p := Vector3(cp.x + cos(a) * r, 0.0, cp.z + sin(a) * r)
		var g := float(w.call(&"height_at", p.x, p.z)) if w.has_method(&"height_at") else 0.0
		var wl := BuildEnv.water_level()
		if g < wl + 0.2 or g > wl + 4.0:
			continue   # сырой песок у воды, но не в прибое
		var dir := Vector2(cos(randf() * TAU), sin(randf() * TAU))
		var cur := Vector3(p.x, g, p.z)
		for k in 10:
			dir = dir.rotated(randf_range(-0.6, 0.6))
			var nx := cur + Vector3(dir.x, 0, dir.y) * 0.12
			st.call(&"drag_mark", cur, nx, 0.012, 0.35)
			cur = nx
		stats.snail += 1
		return

# ---------------------------------------------------------------- туша → кости
func _tick_corpses(dt: float) -> void:
	var fauna := Fauna.instance()
	if fauna == null:
		return
	for a in fauna.animals:
		if not is_instance_valid(a) or not a.dead or a.max_health < 15.0:
			continue
		var id := a.get_instance_id()
		if not _corpses.has(id):
			_corpses[id] = {"node": a, "t": 0.0, "pos": a.global_position, "done": false}
			a.tree_exiting.connect(_on_corpse_gone.bind(id))
		var c: Dictionary = _corpses[id]
		c.t = float(c.t) + dt
		c.pos = a.global_position
		# темнеет и оседает: модель чуть опускается и сплющивается к ~90 с
		var k := clampf(float(c.t) / 85.0, 0.0, 1.0)
		var m := a.get(&"_model") as Node3D
		if m:
			m.scale = Vector3(1.0, lerpf(1.0, 0.72, k), 1.0)
			m.position.y = lerpf(0.0, -0.08, k)
		_darken(a, k)

func _darken(n: Node, k: float) -> void:
	if k < 0.02:
		return
	for gi in n.find_children("*", "GeometryInstance3D", true, false):
		var g := gi as GeometryInstance3D
		if g.material_overlay == null:
			g.material_overlay = _decay_overlay()
		if g.material_overlay == _overlay:
			g.set_instance_shader_parameter(&"decay", k)

static var _overlay: ShaderMaterial
static func _decay_overlay() -> ShaderMaterial:
	if _overlay:
		return _overlay
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode blend_mul, unshaded, depth_draw_never, cull_back, shadows_disabled;
instance uniform float decay = 0.0;
void fragment() {
	// тушa со временем темнеет, теряет цвет и становится бурой
	ALBEDO = mix(vec3(1.0), vec3(0.42, 0.36, 0.3), decay);
}
"""
	_overlay = ShaderMaterial.new()
	_overlay.shader = sh
	return _overlay

func _on_corpse_gone(id: int) -> void:
	var c: Dictionary = _corpses.get(id, {})
	_corpses.erase(id)
	if c.is_empty() or float(c.t) < 30.0:
		return
	var host := BuildEnv.world()
	if host == null or not host.is_inside_tree():
		return
	var p: Vector3 = c.pos
	var pk := ItemPickup.spawn(host, p + Vector3(0, 0.2, 0), [{"id": &"bone", "n": randi_range(2, 5)}])
	if pk:
		pk.add_to_group(&"bones_pile")
		stats.bones += 1

# ---------------------------------------------------------------- брошенную еду растаскивают
func _tick_food(dt: float, cp: Vector3) -> void:
	var seen := {}
	for pk in get_tree().get_nodes_in_group(&"pickups"):
		if not (pk is ItemPickup) or not is_instance_valid(pk):
			continue
		var st: Array = (pk as ItemPickup).stacks
		if st.is_empty() or not _is_food(StringName(st[0].id)):
			continue
		var id := (pk as Node).get_instance_id()
		seen[id] = true
		if not _food.has(id):
			_food[id] = {"t": 0.0}
		var f: Dictionary = _food[id]
		f.t = float(f.t) + dt
		var p := (pk as Node3D).global_position
		# муравьиная дорожка к еде, когда игрок рядом (видно); через ~3 мин еды нет
		if f.t > 25.0 and p.distance_to(cp) < 25.0:
			_ant_trail(p)
		if f.t > 180.0:
			(pk as Node).queue_free()
			_food.erase(id)
			stats.food_taken += 1
	for id in _food.keys():
		if not seen.has(id):
			_food.erase(id)

func _is_food(id: StringName) -> bool:
	var s := String(id)
	for k in ["meat", "fish", "coconut", "berr", "banana", "egg", "fruit", "taro", "food", "yakitori"]:
		if s.contains(k):
			return true
	return false

func _ant_trail(p: Vector3) -> void:
	if ants == null:
		ants = GPUParticles3D.new()
		ants.name = "AntTrail"
		ants.local_coords = false
		ants.amount = 60
		ants.lifetime = 6.0
		ants.visibility_aabb = AABB(Vector3(-10, -2, -10), Vector3(20, 4, 20))
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
		pm.direction = Vector3(1, 0, 0)
		pm.spread = 3.0
		pm.initial_velocity_min = 0.45
		pm.initial_velocity_max = 0.55
		pm.gravity = Vector3.ZERO
		ants.process_material = pm
		var q := QuadMesh.new()
		q.size = Vector2(0.012, 0.006)
		q.orientation = PlaneMesh.FACE_Y
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.08, 0.05, 0.04)
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		q.material = m
		ants.draw_pass_1 = q
		add_child(ants)
	if ants.emitting and ants.global_position.distance_to(p) < 3.0:
		return
	# муравьи идут к еде с травы/опушки: старт в 2,8 м, путь к еде
	var a := randf() * TAU
	var start := p + Vector3(cos(a), 0, sin(a)) * 2.8
	var w := BuildEnv.world()
	if w and w.has_method(&"height_at"):
		start.y = float(w.call(&"height_at", start.x, start.z)) + 0.01
	ants.global_position = start
	(ants.process_material as ParticleProcessMaterial).direction = (p - start).normalized() * Vector3(1, 0, 1)
	ants.emitting = true

# ---------------------------------------------------------------- скорлупа в разрытой кладке
func _tick_nests(cp: Vector3) -> void:
	for n in get_tree().get_nodes_in_group(&"turtle_nests"):
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var id := (n as Node).get_instance_id()
		if _nest_done.has(id) or int(n.get(&"eggs")) > 0 or (n as Node3D).global_position.distance_to(cp) > 80.0:
			continue
		_nest_done[id] = true
		_shells(n as Node3D)

func _shells(nest: Node3D) -> void:
	var root := Node3D.new()
	root.name = "EggShells"
	nest.add_child(root)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.93, 0.9, 0.84)
	mat.roughness = 0.6
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in 9:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		var r := randf_range(0.012, 0.025)
		sm.radius = r
		sm.height = r * 2.0
		sm.is_hemisphere = true
		sm.radial_segments = 8
		sm.rings = 3
		mi.mesh = sm
		mi.material_override = mat
		var a := randf() * TAU
		var d := randf_range(0.05, 0.32)
		mi.position = Vector3(cos(a) * d, 0.01, sin(a) * d)
		mi.rotation = Vector3(randf_range(0, PI), randf() * TAU, randf_range(-0.5, 0.5))
		mi.scale = Vector3(1.0, randf_range(0.3, 0.7), 1.0)
		root.add_child(mi)
	stats.shells += 1
