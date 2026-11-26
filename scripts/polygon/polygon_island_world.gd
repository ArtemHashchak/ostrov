class_name PolygonIslandWorld
extends World
## Мир «остров полигона»: один остров рецепта, новый архипелаг v5 или карта матча —
## раскладка от PolygonIslands.make_arch(PolygonIslandStage.island_id). Рельеф, океан,
## небо — общий World; декор рек/водопадов/гротов (IslandDecor) — у раскладок IslandGen.

var decor: IslandDecor

func _ready() -> void:
	# архипелаги — тем же путём, что мир игры (v5: потоковый рельеф, карта зон, тропы)
	match PolygonIslandStage.island_id:
		"archipelago_v5":
			gen_version = 5
			super._ready()
			return
		"archipelago_match":
			gen_version = 4
			super._ready()
			return
	add_to_group(&"world")
	var t0 := Time.get_ticks_msec()
	arch = PolygonIslands.make_arch(PolygonIslandStage.island_id, seed_value)
	terrain_material = TerrainMaterial.make_tropic(0.0)
	terrain = TerrainChunks.new()
	terrain.name = "Terrain"
	add_child(terrain)
	zones = ZoneMap.new()
	zones.build(arch, Callable(), ZoneMap.make_key(seed_value, "polygon_island|%s|%s" % [PolygonIslandStage.island_id, str(arch.bounds)]))
	trails = TrailNet.new()
	trails.build(zones, arch, seed_value)
	terrain.build(arch, terrain_material, zones)
	_make_deep_floor()
	ocean = Ocean.new()
	add_child(ocean)
	ocean.build(terrain.height_at, arch.bounds.grow(60.0))
	_make_lakes()
	_make_wrecks()
	if arch is IslandGen:
		decor = IslandDecor.new()
		decor.name = "IslandDecor"
		add_child(decor)
		decor.build(self, arch as IslandGen)
	sky = SkyWeather.new()
	sky.name = "SkyWeather"
	add_child(sky)
	sky.setup(start_hour, seed_value)
	sky.weather_changed.connect(func(w: StringName) -> void: weather_changed.emit(w))
	build_ms = Time.get_ticks_msec() - t0
	build_stats = {"total_ms": build_ms, "islands": arch.islands.size(), "terrain": terrain.stats}
	print("[polygon-island] «%s»: построен за %d мс, островов %d" % [PolygonIslandStage.island_id, build_ms, arch.islands.size()])
	is_ready = true
	world_ready.emit()

## Острова + тип рецепта и профиль флоры (Flora берёт flora_profile, если есть).
func islands() -> Array[Dictionary]:
	if PolygonIslandStage.island_id in ["archipelago_v5", "archipelago_match"]:
		return super.islands()
	var out: Array[Dictionary] = []
	for I in arch.islands:
		var e := {"id": I.id, "kind": I.kind, "team": I.team, "center": I.center, "radius": I.radius,
				"max_h": I.max_h, "name": I.name}
		if I.has("type"):
			e["type"] = I.type
			e["flora_profile"] = I.flora_profile
		out.append(e)
	return out

func set_tide(m: float) -> void:
	tide_amplitude = absf(m)
