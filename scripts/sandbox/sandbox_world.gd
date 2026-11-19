class_name SandboxWorld
extends World
## Мир «Полигона»: тот же World (API, рельеф, океан, небо), но своя раскладка
## островов (SandboxArch) вместо архипелага матча.

## На полигоне уровень моря держим у номинала: точки, витрины, пирс и камеры
## расставлены относительно него. Прилива нет; нагон в шторм — лишь до 0.35 м,
## чтобы гроза (F5) не затапливала зоны, но волны у берега были видны.
const SANDBOX_SURGE_MAX := 0.35

func _update_surge(dt: float) -> void:
	var target := SANDBOX_SURGE_MAX * smoothstep(0.25, 1.0, storm_intensity())
	_surge = lerpf(_surge, target, 1.0 - exp(-dt / 60.0))

func _ready() -> void:
	tide_amplitude = 0.0
	add_to_group(&"world")
	var t0 := Time.get_ticks_msec()
	arch = SandboxArch.new(seed_value)
	terrain_material = TerrainMaterial.make_tropic(0.0)
	terrain = TerrainChunks.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.build(arch, terrain_material)
	_make_deep_floor()
	ocean = Ocean.new()
	add_child(ocean)
	ocean.build(terrain.height_at, arch.bounds.grow(60.0))
	_make_lakes()
	_make_wrecks()
	sky = SkyWeather.new()
	sky.name = "SkyWeather"
	add_child(sky)
	sky.setup(start_hour)
	build_ms = Time.get_ticks_msec() - t0
	build_stats = {"total_ms": build_ms, "islands": arch.islands.size()}
	print("[sandbox] мир построен за %d мс, островов %d" % [build_ms, arch.islands.size()])
	is_ready = true
	world_ready.emit()
