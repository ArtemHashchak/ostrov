## test-timeout: 1500
extends TestCase
## Остров полигона (сцена PolygonIslandStage, в памяти только он): новый архипелаг v5
## по умолчанию (POLY_ISLAND=<id> — любой из PolygonIslands.list(), напр. volcanic).
## Мир построен, игрок на суше у берега, меню с «← В музей» и списком островов,
## запись реплея идёт. Снимок: tests/shots/test_polygon_island_<id>.png.

var st: PolygonIslandStage
var id := "archipelago_v5"

func _init() -> void:
	if OS.get_environment("POLY_ISLAND") != "":
		id = OS.get_environment("POLY_ISLAND")
	PolygonIslandStage.island_id = id
	scene_path = "res://scenes/polygon/polygon_island.tscn"
	timeout_sec = 1400.0

func run() -> void:
	Engine.max_physics_steps_per_frame = 30
	st = scene as PolygonIslandStage
	var t0 := Time.get_ticks_msec()
	while not st.is_built and Time.get_ticks_msec() - t0 < 1200000:
		await wait(0.5)
	check(st.is_built, "«%s» собран за %d с" % [PolygonIslands.name_of(id), (Time.get_ticks_msec() - t0) / 1000])
	if not st.is_built:
		return
	var w := st.world
	check(w.arch.islands.size() >= 1, "островов: %d" % w.arch.islands.size())
	if id == "archipelago_v5":
		check(w.gen_version == 5 and w.arch is ArchipelagoV5, "архипелаг v5 (генератор мира)")
	await wait(2.0)
	var p := st.player.global_position
	check(w.height_at(p.x, p.z) > w.water_level() - 0.3, "игрок на суше/у кромки (h=%.1f)" % w.height_at(p.x, p.z))
	check(w.zones != null, "карта зон построена")
	st.panel.open()
	await wait_frames(2)
	var tabs := st.panel.tabs
	check(tabs.get_tab_count() >= 6, "меню острова: %d вкладок" % tabs.get_tab_count())
	var has_back := false
	for b in st.panel.find_children("*", "Button", true, false):
		if (b as Button).text.contains("В музей"):
			has_back = true
	check(has_back, "в меню есть «← В музей полигона»")
	st.panel.close()
	await wait(1.0)
	check(st.recorder != null and st.recorder.frames.size() > 5, "реплей пишет запись на острове")
	print("[test] память: %.0f МБ" % (Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0))
	shot(id)
