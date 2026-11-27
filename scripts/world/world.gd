class_name World
extends Node3D
## Мир архипелага (группа `world`): рельеф, океан с приливом, небо и погода.
## API для других модулей — см. CONTRACT_G1.md («Мир»).

signal world_ready
## Смена погоды (плавный переход начинается сейчас). См. CONTRACT_WEATHER.md.
signal weather_changed(w: StringName)

@export var seed_value: int = 2026
## Генератор мира: 4 — прежний архипелаг (25 островов), 5 — новый (ArchipelagoV5,
## ≈3×3 км, граф островов, барьерный риф). Переменная окружения OSTROVA_GEN
## переопределяет (тесты). Карта зон (ZoneMap) строится для обоих.
@export var gen_version: int = 5
@export var start_hour: float = 8.5
@export var tide_amplitude: float = 0.8
@export var tide_period: float = 480.0     # секунд на цикл прилив→отлив→прилив

const SAND_TOP := 1.6

var arch: Archipelago
## Карта зон (A11): все, кто ставит что-то в мир, спрашивают её (zone_at и др.).
var zones: ZoneMap
## Декор особенностей островов v5 (ручьи, водопады, гроты) — IslandDecor.
var island_decor: Node3D
## Звериные тропы и прорубленные проходы (TrailNet).
var trails: TrailNet
var terrain: TerrainChunks
var ocean: Ocean
var sky: SkyWeather
var terrain_material: ShaderMaterial
var is_ready := false
var time_s := 0.0
var build_ms := 0
var build_stats := {}
var _lake_mat: StandardMaterial3D

func _ready() -> void:
	add_to_group(&"world")
	var t0 := Time.get_ticks_msec()
	var gv := gen_version
	if OS.get_environment("OSTROVA_GEN") != "":
		gv = int(OS.get_environment("OSTROVA_GEN"))
	gen_version = gv
	arch = ArchipelagoV5.new(seed_value) if gv >= 5 else Archipelago.new(seed_value)
	terrain_material = TerrainMaterial.make_tropic(0.0)
	terrain = TerrainChunks.new()
	terrain.name = "Terrain"
	add_child(terrain)
	var t_arch := Time.get_ticks_msec()
	zones = ZoneMap.new()
	zones.build(arch, Callable(), ZoneMap.make_key(seed_value, "g%d|%s" % [gen_version, str(arch.bounds)]))
	trails = TrailNet.new()
	trails.build(zones, arch, seed_value)
	if gen_version >= 5:
		var canopy := TrailCanopy.new()
		canopy.setup(self, trails)
		add_child(canopy)
	var t_zone := Time.get_ticks_msec()
	# мир v5 (≈3×3 км): подробный рельеф подгружается вокруг игрока/ботов/камеры
	terrain.streaming = gen_version >= 5
	terrain.build(arch, terrain_material, zones)
	var t_terr := Time.get_ticks_msec()
	_make_deep_floor()
	ocean = Ocean.new()
	add_child(ocean)
	ocean.build(_ocean_height if gen_version >= 5 else terrain.height_at, arch.bounds.grow(60.0))
	var t_ocean := Time.get_ticks_msec()
	_make_lakes()
	_make_wrecks()
	if gen_version >= 5 and arch is IslandGen:
		# ручьи, водопады, гроты, птичьи карнизы островов-рецептов
		island_decor = IslandDecor.new()
		island_decor.name = "IslandDecor"
		add_child(island_decor)
		island_decor.build(self, arch as IslandGen)
	sky = SkyWeather.new()
	sky.name = "SkyWeather"
	add_child(sky)
	sky.setup(start_hour, seed_value)
	sky.weather_changed.connect(func(w: StringName) -> void: weather_changed.emit(w))
	if gen_version >= 5:
		# v5.2: сценки живой природы на суше и подсказки через мир (агент L); в тестах — выключены
		var live := not LandDirector.is_test_run()
		var dir := LandDirector.new()
		dir.world = self
		dir.auto = live
		add_child(dir)
		var hints := WorldHints.new()
		hints.world = self
		hints.active = live
		add_child(hints)
	build_ms = Time.get_ticks_msec() - t0
	build_stats = {"total_ms": build_ms, "layout_ms": t_arch - t0, "zones_ms": t_zone - t_arch, "trails": trails.stats,
			"terrain_ms": t_terr - t_zone, "ocean_ms": t_ocean - t_terr, "terrain": terrain.stats, "islands": arch.islands.size(),
			"gen": gen_version}
	print("[world] построен за %d мс: %s, чанки %s" % [build_ms, str(build_stats), str(terrain.chunk_count())])
	is_ready = true
	world_ready.emit()

## Дно океана за пределами чанков (чтобы под водой не было видно края мира).
func _make_deep_floor() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "DeepFloor"
	var pm := PlaneMesh.new()
	pm.size = Vector2(9000.0, 9000.0)
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.36, 0.40, 0.36)
	m.roughness = 1.0
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(arch.bounds.get_center().x, Archipelago.SEA_FLOOR - 2.5, arch.bounds.get_center().y)
	add_child(mi)

## Пресные озёра: прозрачная гладь на уровне озера (берег рельефа выше уровня).
func _make_lakes() -> void:
	var root := Node3D.new()
	root.name = "Lakes"
	add_child(root)
	_lake_mat = StandardMaterial3D.new()
	_lake_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_lake_mat.albedo_color = Color(0.10, 0.20, 0.17, 0.78)
	_lake_mat.roughness = 0.04
	_lake_mat.metallic_specular = 0.8
	var nrm := "res://addons/ostrova_water/lesusx_gerstner/textures/Water 0339normal.jpg"
	if ResourceLoader.exists(nrm):
		_lake_mat.normal_enabled = true
		_lake_mat.normal_texture = load(nrm)
		_lake_mat.normal_scale = 0.25
		_lake_mat.uv1_scale = Vector3(0.12, 0.12, 0.12)
		_lake_mat.uv1_world_triplanar = true
	_lake_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for L in arch.lakes:
		var c: Vector2 = L.center
		var mi := MeshInstance3D.new()
		mi.name = "Lake_%d" % int(L.island)
		mi.mesh = _lake_mesh(L)
		mi.material_override = _lake_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(c.x, float(L.level), c.y)
		mi.visibility_range_end = 900.0
		mi.add_to_group(&"fresh_water")
		root.add_child(mi)

## Плоскость воды озера только над его маской (+1 отсчёт каймы, которую
## прячет рельеф выше уровня) — без «висящей» воды над низким берегом.
func _lake_mesh(L: Dictionary) -> ArrayMesh:
	var n: int = L.get("mask_n", 0)
	var st := Archipelago.LAKE_STEP
	var org: Vector2 = L.get("mask_origin", L.center)
	var c: Vector2 = L.center
	var verts := PackedVector3Array()
	for j in n - 1:
		for i in n - 1:
			if not (Archipelago.lake_wet(L, i, j) or Archipelago.lake_wet(L, i + 1, j) \
					or Archipelago.lake_wet(L, i, j + 1) or Archipelago.lake_wet(L, i + 1, j + 1)):
				continue
			var x0 := org.x + i * st - c.x
			var z0 := org.y + j * st - c.y
			var a := Vector3(x0, 0, z0)
			var b := Vector3(x0 + st, 0, z0)
			var d := Vector3(x0, 0, z0 + st)
			var e := Vector3(x0 + st, 0, z0 + st)
			verts.append_array([a, b, e, a, e, d])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	var nrm := PackedVector3Array()
	nrm.resize(verts.size())
	nrm.fill(Vector3.UP)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = nrm
	var m := ArrayMesh.new()
	if verts.size() > 0:
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

## Кладбища кораблей: корпуса парусников (без парусов), накренённые и
## наполовину затопленные, плюс обломки на берегу. Коллизия — упрощённая.
func _make_wrecks() -> void:
	var root := Node3D.new()
	root.name = "Wrecks"
	add_child(root)
	var ship_scene := load("res://assets/models/ships/dutch_ship_medium_2k.glb") as PackedScene
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 404
	var planks := TerrainMaterial.pbr("weathered_planks", 1.0)
	var wood := TerrainMaterial.pbr("rough_wood", 1.0)
	for w in arch.wreck_spots:
		var p: Vector2 = w.pos
		var g := height_at(p.x, p.y)
		var body := StaticBody3D.new()
		body.name = "Wreck_%d" % root.get_child_count()
		body.add_to_group(&"wrecks")
		root.add_child(body)
		var roll := rng.randf_range(0.35, 0.6) * (1.0 if rng.randf() < 0.5 else -1.0)
		var pitch := rng.randf_range(-0.12, 0.12)
		body.position = Vector3(p.x, maxf(g, -6.0) + 0.6 - float(w.sink) * 0.35, p.y)
		body.rotation = Vector3(roll, float(w.yaw), pitch)
		if ship_scene:
			var ship := ship_scene.instantiate()
			for n in ship.find_children("*", "MeshInstance3D", true, false):
				var mi := n as MeshInstance3D
				if not String(mi.name).to_lower().contains("hull") and not String(mi.mesh.resource_name if mi.mesh else "").to_lower().contains("base"):
					mi.queue_free()
					continue
				mi.visibility_range_end = 380.0
			body.add_child(ship)
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(20.0, 6.0, 5.0)
		cs.shape = box
		cs.position = Vector3(0.6, 1.0, 0.0)
		body.add_child(cs)
	# обломки на мусорных берегах кладбищ
	for I in arch.islands:
		if I.kind != &"wreck":
			continue
		var c: Vector2 = I.center
		for k in 14:
			var a := rng.randf() * TAU
			var bp := arch.beach_point(I, a)
			bp += Vector2.from_angle(a) * rng.randf_range(-6.0, 2.0)
			var h := height_at(bp.x, bp.y)
			if h < -0.6:
				continue
			var mi := MeshInstance3D.new()
			if k % 3 == 0:
				var cy := CylinderMesh.new()
				cy.top_radius = 0.32
				cy.bottom_radius = 0.36
				cy.height = 0.95
				mi.mesh = cy
				mi.material_override = wood
				mi.rotation = Vector3(PI * 0.5 * float(rng.randf() < 0.6), rng.randf() * TAU, 0.0)
				mi.position = Vector3(bp.x, h + 0.3, bp.y)
			else:
				var bx := BoxMesh.new()
				bx.size = Vector3(rng.randf_range(1.5, 4.0), 0.12, rng.randf_range(0.22, 0.35))
				mi.mesh = bx
				mi.material_override = planks
				mi.rotation = Vector3(rng.randf_range(-0.15, 0.15), rng.randf() * TAU, rng.randf_range(-0.15, 0.15))
				mi.position = Vector3(bp.x, h + 0.06, bp.y)
			mi.visibility_range_end = 220.0
			root.add_child(mi)

## Остановить/запустить ход времени (тесты, катсцены).
func set_time_paused(p: bool) -> void:
	if sky and sky.sky3d:
		sky.sky3d.game_time_enabled = not p

func _process(delta: float) -> void:
	var __pt := PerfStats.begin()
	_perf_process(delta)
	PerfStats.end(&"world", __pt)

func _perf_process(delta: float) -> void:
	time_s += delta
	_update_surge(delta)
	var level := water_level()
	var cam := get_viewport().get_camera_3d()
	var cp := cam.global_position if cam else Vector3.ZERO
	ocean.set_weather_drive(wind_dir(), wind_speed(), storm_intensity(), rain_factor())
	ocean.update(delta, cp, level, sky.wave_scale())
	terrain_material.set_shader_parameter(&"water_level", level)
	terrain_material.set_shader_parameter(&"time_s", time_s)
	var surf := ocean.wave_height(cp.x, cp.z) if cam else level
	sky.update(delta, cam, surf)
	var dl := sky.daylight()
	ocean.set_night_tint(Color(0.5, 0.56, 0.72).lerp(Color.WHITE, sqrt(dl)))

# ------------------------------------------------------------ API «Мир»

func height_at(x: float, z: float) -> float:
	return terrain.height_at(x, z)

func normal_at(x: float, z: float) -> Vector3:
	return terrain.normal_at(x, z)

func is_land(x: float, z: float) -> bool:
	var h := height_at(x, z)
	return h > water_level() and h >= arch.lake_level_at(x, z, h)

## Уровень воды озера/пруда над точкой или −INF (не под пресной водой).
func lake_level_at(x: float, z: float) -> float:
	return arch.lake_level_at(x, z, height_at(x, z))

## 'beach' | 'jungle' | 'meadow' | 'rocky' | 'swamp' | 'water'
func biome_at(x: float, z: float) -> StringName:
	var h := height_at(x, z)
	if h < water_level() or h < arch.lake_level_at(x, z, h):
		return &"water"
	var w := arch.biome_weights(x, z, h)
	var n := normal_at(x, z)
	if w.b > 0.5 or n.y < 0.74 or (w.a > 0.5 and h > 2.5):
		return &"rocky"
	if w.g > 0.5:
		return &"swamp"
	if h < SAND_TOP:
		return &"beach"
	if w.r > 0.5:
		return &"jungle"
	return &"meadow"

## Высота для карты глубин океана (v5): у берега — точная, в море — из карты зон
## (точная выборка 3×3 км заняла бы ~20 с).
func _ocean_height(x: float, z: float) -> float:
	var hz := zones.height_lerp(x, z)
	if hz > -5.0 and hz < 4.0:
		return arch.height(x, z)
	return hz

## Зона в точке (ZoneMap.NAMES: beach, jungle, reef_crest, lagoon, …).
func zone_at(x: float, z: float) -> StringName:
	return zones.zone_name_at(x, z) if zones else biome_at(x, z)

## Густота джунглей 0..1 (стена в центре острова).
func jungle_density(x: float, z: float) -> float:
	return zones.jungle_density(x, z) if zones else 0.0

## Расстояние до ближайшей тропы/прохода, м (далеко — INF).
func trail_dist(x: float, z: float) -> float:
	return trails.dist(x, z) if trails else INF

## Тропа под ногами: 0 — нет, &"animal" — звериная (полог ~1,2 м, идти
## пригнувшись ≈70 % скорости), &"cut" — прорубленный проход (100 %).
func trail_at(x: float, z: float) -> StringName:
	if trails == null or trails.dist(x, z) > TrailNet.WIDTH * 0.5 + 0.35:
		return &""
	for seg in trails.segments_near(Vector2(x, z), 1.2):
		if seg[2] == &"cut":
			return &"cut"
	return &"animal"

## Насколько растительность мешает идти в точке, 0..1 (агент F: скорость игрока
## × (1 − 0.75·drag)): густые джунгли вне троп — почти стена; на тропе — 0.
func vegetation_drag(x: float, z: float) -> float:
	if zones == null:
		return 0.0
	if trail_at(x, z) != &"":
		return 0.0
	return zones.jungle_density(x, z)

## Прорубить проход (навсегда): ломаная точек XZ. Растения на нём уже срублены
## игроком; новые там не появятся.
func add_cut_path(pts: PackedVector2Array) -> void:
	if trails:
		trails.add_cut(pts)

## Удар мачете по подлеску (игрок/бот): срубает кусты в радиусе ~1,1 м у точки удара и
## продолжает прорубленный проход от прошлого удара этого же рубящего (≤ 4 м) — тропа &"cut".
var _cut_last: Dictionary = {}   # instance_id → Vector2
func cut_vegetation(cutter: Node, at: Vector3) -> int:
	var fl := get_tree().get_first_node_in_group(&"flora")
	var n := 0
	if fl and fl.has_method(&"clear_brush"):
		n = int(fl.call(&"clear_brush", at, 1.1))
	var here := Vector2(at.x, at.z)
	var id := cutter.get_instance_id() if cutter else 0
	var prev: Variant = _cut_last.get(id)
	# проход — только в зарослях (где мешает растительность) или если срублено что-то
	if n > 0 or (zones and zones.jungle_density(at.x, at.z) > 0.15):
		if prev != null and (prev as Vector2).distance_to(here) <= 4.0 and (prev as Vector2).distance_to(here) > 0.3:
			add_cut_path(PackedVector2Array([prev, here]))
			_cut_last[id] = here
		elif prev == null or (prev as Vector2).distance_to(here) > 4.0:
			_cut_last[id] = here
	return n

## Можно ли ставить морскую жизнь: открытое море (не отрезанная яма),
## глубже min_depth даже в самый низкий отлив.
func sea_ok(x: float, z: float, min_depth: float = 0.4) -> bool:
	if zones:
		return zones.water_ok(x, z, min_depth)
	return height_at(x, z) < -tide_amplitude - min_depth

## Самый низкий уровень воды (отлив без нагона).
func low_tide_level() -> float:
	return -tide_amplitude

## Памятники генератора v5: [{type, pos: Vector3, island, yaw}].
func monuments() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if arch is ArchipelagoV5:
		for m in (arch as ArchipelagoV5).monuments:
			var p: Vector2 = m.pos
			out.append({"type": m.type, "pos": Vector3(p.x, height_at(p.x, p.y), p.y), "island": m.island, "yaw": m.yaw})
	return out

## Текущий уровень воды (среднее 0 + прилив).
func water_level() -> float:
	return sin(time_s / tide_period * TAU) * tide_amplitude + _surge

## Штормовой нагон: море поднимается до ~0.6 м (v5: было 1.8 — заливало полуострова) и плавно
## (минуты) уходит обратно. Волны в шторм на вид выше (SkyWeather.WEATHERS.storm.waves).
var _surge := 0.0
const SURGE_MAX := 0.6

func storm_surge() -> float:
	return _surge

func _update_surge(dt: float) -> void:
	var target := SURGE_MAX * smoothstep(0.25, 1.0, storm_intensity())
	# поднимается ~за 2 мин, спадает ~за 4 мин
	var tau := 120.0 if target > _surge else 240.0
	_surge = lerpf(_surge, target, 1.0 - exp(-dt / tau))

func tide_rising() -> bool:
	return cos(time_s / tide_period * TAU) > 0.0

## Высота поверхности воды с волнами (совпадает с шейдером вблизи камеры).
func wave_height(x: float, z: float) -> float:
	return ocean.wave_height(x, z) if ocean else water_level()

## [{id, kind, team, center: Vector2, radius, max_h, name}]
## kind: 'home' (team 0–3) | 'center' (вулкан) | 'shared' | 'spring' | 'swamp' |
##       'rocky' | 'atoll' | 'wreck'; у не-домашних team = −1.
func islands() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var v5 := arch as ArchipelagoV5
	for I in arch.islands:
		var e := {"id": I.id, "kind": I.kind, "team": I.team, "center": I.center, "radius": I.radius,
				"max_h": I.max_h, "name": I.name}
		if v5:
			e["cls"] = v5.class_of(I)
			e["type"] = I.get("type", &"")
			e["flora_profile"] = I.get("flora_profile", {})
		out.append(e)
	return out

## Остров в точке (или ближайший в пределах 1.3 радиуса), иначе {}.
func island_at(x: float, z: float) -> Dictionary:
	var ia := arch.island_at(Vector2(x, z))
	if ia.island.is_empty() or float(ia.d) > 1.3:
		return {}
	var I: Dictionary = ia.island
	return {"id": I.id, "kind": I.kind, "team": I.team, "center": I.center, "radius": I.radius, "name": I.name}

# ------------------------------------------------------------ пресная вода и места

## Пресная вода в точке: озёра родниковых островов и редкие родники-пруды на скалах.
func fresh_water_at(pos: Vector3) -> bool:
	return arch.fresh_water_at(pos)

## Центры пресных водоёмов (на поверхности воды).
func springs() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for L in arch.lakes:
		var c: Vector2 = L.center
		out.append(Vector3(c.x, float(L.level), c.y))
	return out

## [{pos: Vector3 (поверхность), radius, level, kind: 'lake'|'pond', island}]
func lakes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for L in arch.lakes:
		var c: Vector2 = L.center
		out.append({"pos": Vector3(c.x, float(L.level), c.y), "radius": L.radius, "level": L.level,
				"kind": L.kind, "island": L.island})
	return out

## Мусорные берега (выброс обломков после штормов): кладбища кораблей и
## наветренные пляжи домашних/общих островов. [{pos: Vector3, radius, island}]
func trash_beaches() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for I in arch.islands:
		var a0: float = I.angle
		match I.kind:
			&"wreck":
				for k in 3:
					out.append(_beach_spot(I, a0 + PI + (k - 1) * 1.2, 14.0))
			&"home":
				out.append(_beach_spot(I, a0 + 2.3, 11.0))
			&"shared":
				out.append(_beach_spot(I, a0, 10.0))
	return out

## Черепашьи пляжи (кладки яиц): атоллы и пологие песчаные берега общих островов.
func turtle_beaches() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for I in arch.islands:
		var a0: float = I.angle
		match I.kind:
			&"atoll":
				out.append(_beach_spot(I, a0 + 0.9, 12.0))
				out.append(_beach_spot(I, a0 + PI + 0.4, 12.0))
			&"shared":
				out.append(_beach_spot(I, a0 + PI * 0.75, 9.0))
	return out

## Болота и мангры: мангровые острова и лагуны домашних островов.
func swamps() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for I in arch.islands:
		var c: Vector2 = I.center
		if I.kind == &"swamp":
			out.append({"pos": Vector3(c.x, height_at(c.x, c.y), c.y), "radius": float(I.radius) * 0.85, "island": I.id})
		elif float(I.lagoon_dir) >= 0.0:
			var ld := float(I.lagoon_dir)
			var lc := c + Vector2(cos(ld), sin(ld)) * arch._coast_r(I, ld) * 0.7
			out.append({"pos": Vector3(lc.x, height_at(lc.x, lc.y), lc.y), "radius": float(I.radius) * 0.3, "island": I.id})
	return out

func _beach_spot(I: Dictionary, a: float, r: float) -> Dictionary:
	# ищем по дуге и поперёк берега точку, где действительно сухой песок
	var best := arch.beach_point(I, a)
	var found := false
	for k in 15:
		var aa := a + floorf(k * 0.5) * 0.09 * (1.0 if k % 2 == 0 else -1.0)
		for dd in [0.0, -3.0, 3.0, -6.0]:
			var p := arch.beach_point(I, aa) + Vector2.from_angle(aa) * float(dd)
			var h := height_at(p.x, p.y)
			if h > 0.3 and h < SAND_TOP and biome_at(p.x, p.y) == &"beach":
				best = p
				found = true
				break
		if found:
			break
	return {"pos": Vector3(best.x, height_at(best.x, best.y), best.y), "radius": r, "island": I.id}

## Остовы кораблей (кладбища кораблей и один у атолла).
func wrecks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for w in arch.wreck_spots:
		var p: Vector2 = w.pos
		out.append({"pos": Vector3(p.x, height_at(p.x, p.y), p.y), "yaw": w.yaw, "island": w.island})
	return out

## Островки и косы между островами (опоры мостов).
func islets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for il in arch.islets:
		out.append({"center": il.center, "radius": il.radius, "top": il.top})
	return out

func sandbars() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for b in arch.bars:
		out.append({"points": b.pts, "width": b.width, "top": b.top})
	return out

## Ровное место ближе к центру домашнего острова команды.
func spawn_point(team: int) -> Vector3:
	var c := Vector2.ZERO
	for I in arch.islands:
		if int(I.team) == team:
			c = I.center
	var best := Vector3(c.x, height_at(c.x, c.y) + 0.3, c.y)
	var best_score := -1e9
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + team
	for k in 160:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.0, 45.0)
		var x := c.x + cos(a) * r
		var z := c.y + sin(a) * r
		var h := height_at(x, z)
		var n := normal_at(x, z)
		if h < 2.2:
			continue
		var score := n.y * 10.0 - r * 0.05 - absf(h - 6.0) * 0.1
		if score > best_score:
			best_score = score
			best = Vector3(x, h + 0.3, z)
	return best

func time_of_day() -> float:
	return sky.time_of_day()

func set_time_of_day(h: float) -> void:
	sky.set_time_of_day(h)

func is_night() -> bool:
	return sky.is_night()

func weather() -> StringName:
	return sky.weather

func set_weather(w: StringName, instant: bool = false) -> void:
	sky.set_weather(w, instant)

func rain_factor() -> float:
	return sky.rain_factor()

# ---- ветер и погода (CONTRACT_WEATHER.md)
func wind_dir() -> Vector2:
	return sky.wind_dir()

func wind_speed() -> float:
	return sky.wind_speed()

func gust() -> float:
	return sky.gust()

func storm_intensity() -> float:
	return sky.storm_intensity()

func rain_intensity() -> float:
	return sky.rain_intensity()

func wetness() -> float:
	return sky.wetness()
