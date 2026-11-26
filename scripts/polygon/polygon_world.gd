class_name PolygonWorld
extends World
## Мир нового полигона: тот же World (рельеф, океан, небо, погода, API), раскладка —
## PolygonArch (ровный «музей» + полка под пирс). Прилив — только вручную из меню
## (tide_offset, м); штормовой нагон ограничен, чтобы музей не заливало.

const SURGE_MAX_POLY := 0.35
var tide_offset := 0.0

func _ready() -> void:
	tide_amplitude = 0.0
	add_to_group(&"world")
	var t0 := Time.get_ticks_msec()
	arch = PolygonArch.new(seed_value)
	terrain_material = TerrainMaterial.make_tropic(0.0)
	terrain = TerrainChunks.new()
	terrain.name = "Terrain"
	add_child(terrain)
	# карта зон и тропы — как у мира игры (модули спрашивают zone_at/sea_ok/trail_at)
	zones = ZoneMap.new()
	zones.build(arch, Callable(), ZoneMap.make_key(seed_value, "polygon|%s" % str(arch.bounds)))
	trails = TrailNet.new()
	trails.build(zones, arch, seed_value)
	terrain.build(arch, terrain_material, zones)
	_make_deep_floor()
	ocean = Ocean.new()
	add_child(ocean)
	ocean.build(terrain.height_at, arch.bounds.grow(60.0))
	sky = SkyWeather.new()
	sky.name = "SkyWeather"
	add_child(sky)
	sky.setup(start_hour, seed_value)
	sky.weather_changed.connect(func(w: StringName) -> void: weather_changed.emit(w))
	build_ms = Time.get_ticks_msec() - t0
	build_stats = {"total_ms": build_ms, "islands": 1}
	print("[polygon] мир построен за %d мс, музей %s" % [build_ms, str((arch as PolygonArch).bounds)])
	is_ready = true
	world_ready.emit()

func _update_surge(dt: float) -> void:
	var target := SURGE_MAX_POLY * smoothstep(0.25, 1.0, storm_intensity())
	_surge = lerpf(_surge, target, 1.0 - exp(-dt / 60.0))

func water_level() -> float:
	return tide_offset + _surge

func set_tide(m: float) -> void:
	tide_offset = clampf(m, -1.2, 1.2)
