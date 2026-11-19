class_name ShowcaseWorld
extends World
## Мир «Полигона островов»: тот же World (рельеф, океан, небо, погода), но
## раскладка — ShowcaseArch (по острову каждого типа в ряд) и декор IslandDecor
## (ручьи, водопады, гроты, карнизы птичьего базара).

var decor: IslandDecor
var overview := false

func _ready() -> void:
	add_to_group(&"world")
	var t0 := Time.get_ticks_msec()
	arch = ShowcaseArch.new(seed_value)
	terrain_material = TerrainMaterial.make_tropic(0.0)
	terrain = TerrainChunks.new()
	terrain.name = "Terrain"
	add_child(terrain)
	var t_arch := Time.get_ticks_msec()
	terrain.build(arch, terrain_material)
	var t_terr := Time.get_ticks_msec()
	_make_deep_floor()
	ocean = Ocean.new()
	add_child(ocean)
	ocean.build(terrain.height_at, arch.bounds.grow(60.0))
	var t_ocean := Time.get_ticks_msec()
	_make_lakes()
	_make_wrecks()
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
	build_stats = {"total_ms": build_ms, "layout_ms": t_arch - t0, "terrain_ms": t_terr - t_arch,
			"ocean_ms": t_ocean - t_terr, "terrain": terrain.stats, "islands": arch.islands.size()}
	print("[islands] мир построен за %d мс: %s" % [build_ms, str(build_stats)])
	is_ready = true
	world_ready.emit()

## Острова + тип рецепта и профиль флоры (Flora берёт flora_profile, если есть).
func islands() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for I in arch.islands:
		var e := {"id": I.id, "kind": I.kind, "team": I.team, "center": I.center, "radius": I.radius,
				"max_h": I.max_h, "name": I.name}
		if I.has("type"):
			e["type"] = I.type
			e["flora_profile"] = I.flora_profile
		out.append(e)
	return out

func showcase() -> Array[Dictionary]:
	return (arch as ShowcaseArch).showcase

## Обзор сверху: дальность прорисовки рельефа и декора увеличивается (иначе
## острова дальше FAR не рисуются), при выходе — возвращается.
func set_overview(on: bool) -> void:
	if on == overview:
		return
	overview = on
	# только последний уровень (дальше FAR не рисуется), иначе уровни LOD перекроются
	for n in _geoms(terrain) + _geoms(decor) + _geoms(get_node_or_null(^"Lakes")):
		var g := n as GeometryInstance3D
		if on and g.visibility_range_end >= 800.0:
			g.set_meta(&"_vr_end", g.visibility_range_end)
			g.visibility_range_end = 9000.0
		elif not on and g.has_meta(&"_vr_end"):
			g.visibility_range_end = float(g.get_meta(&"_vr_end"))
			g.remove_meta(&"_vr_end")

func _geoms(root: Node) -> Array:
	var out: Array = []
	if root == null:
		return out
	var st: Array[Node] = [root]
	while not st.is_empty():
		var n: Node = st.pop_back()
		if n is GeometryInstance3D:
			out.append(n)
		st.append_array(n.get_children())
	return out
