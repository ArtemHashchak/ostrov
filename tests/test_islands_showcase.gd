## test-timeout: 1200
extends TestCase
## «Полигон островов»: 10 типов островов генератора в ряд. Проверяет, что каждый
## тип узнаётся по рельефу (вулкан высокий, у атолла лагуна под водой и кольцо,
## у карста отвесные стены, мангры низкие с протоками, кей заливает прилив и т. д.),
## расстояния между островами, декор (ручьи, водопады, гроты, птичий базар),
## флору; снимает каждый остров с пляжа и сверху, обзор всего ряда, шторм.

var sc: IslandsShowcase

func _init() -> void:
	scene_path = "res://scenes/sandbox/islands_showcase.tscn"
	timeout_sec = 3500.0

func _entry(type: StringName) -> Dictionary:
	for e: Dictionary in sc.world.showcase():
		if StringName(e.type) == type:
			return e
	return {}

func _isl(type: StringName) -> Dictionary:
	var e := _entry(type)
	return sc.world.arch.islands[int(e.island_ids[0])] if not e.is_empty() else {}

func _H(p: Vector2) -> float:
	return sc.world.arch.height(p.x, p.y)

func run() -> void:
	Engine.max_physics_steps_per_frame = 30
	sc = scene as IslandsShowcase
	var t0 := Time.get_ticks_msec()
	while not sc.is_built and Time.get_ticks_msec() - t0 < 1500000:
		await wait(0.5)
	check(sc.is_built, "полигон островов собран за %d с" % int((Time.get_ticks_msec() - t0) / 1000.0))
	if not sc.is_built:
		return
	var w := sc.world
	var arch := w.arch as IslandGen
	var list := w.showcase()
	check(list.size() == 10, "островов-витрин 10 (%d)" % list.size())
	var types := {}
	for e: Dictionary in list:
		types[e.type] = true
	check(types.size() == 10, "все 10 типов разные (%s)" % str(types.keys()))
	print("[test] постройка мира: ", w.build_stats)
	# ---- расстояния между берегами соседей (по оси ряда)
	var prev_east := -INF
	for e: Dictionary in list:
		var west := INF
		var east := -INF
		for id: int in e.island_ids:
			var I: Dictionary = arch.islands[id]
			var c: Vector2 = I.center
			west = minf(west, c.x - arch._coast_r(I, PI))
			east = maxf(east, c.x + arch._coast_r(I, 0.0))
		if prev_east > -INF:
			check(west - prev_east >= 250.0, "между берегами «%s» и соседом %.0f м (≥ 250)" % [e.name, west - prev_east])
		prev_east = east
	# ---- рельеф по типам
	var V := _isl(&"volcanic")
	var vmax := -100.0
	for k in 400:
		var p: Vector2 = (V.center as Vector2) + Vector2.from_angle(k * 0.7) * float(V.radius) * (k / 400.0) * 0.5
		vmax = maxf(vmax, _H(p))
	check(vmax > 65.0, "вулкан высокий: вершина %.0f м" % vmax)
	var A := _isl(&"atoll")
	var ac: Vector2 = A.center
	check(_H(ac) < -1.5, "атолл: центр лагуны под водой (%.1f м)" % _H(ac))
	var ring_land := 0
	var ring_n := 0
	for k in 72:
		var a := k * TAU / 72.0
		var p := ac + Vector2.from_angle(a) * arch._coast_r(A, a) * 0.87
		ring_n += 1
		if _H(p) > 1.0:
			ring_land += 1
	check(ring_land >= 10 and ring_land < ring_n, "атолл: моту на кольце %d/%d, между ними риф-флэт" % [ring_land, ring_n])
	var K := _isl(&"karst")
	var kc: Vector2 = K.center
	var steep := 0
	for k in 24:
		var a := k * TAU / 24.0
		var R := arch._coast_r(K, a)
		var h_in := _H(kc + Vector2.from_angle(a) * R * 0.94)
		var h_edge := _H(kc + Vector2.from_angle(a) * R * 1.01)
		if h_in - h_edge > 20.0:
			steep += 1
	check(steep >= 12, "карст: отвесные стены у воды (%d/24 направлений, перепад > 20 м на ~8 м)" % steep)
	var M := _isl(&"mangrove")
	var low := 0
	var chan := 0
	for k in 300:
		var p: Vector2 = (M.center as Vector2) + Vector2.from_angle(k * 2.39996) * float(M.radius) * sqrt((k + 0.5) / 300.0) * 0.9
		var h := _H(p)
		if h < 2.7:
			low += 1
		if h < 0.0:
			chan += 1
	check(low >= 290 and chan >= 15, "мангры: низкие (%d/300 ниже 2.7 м), протоки ниже моря (%d)" % [low, chan])
	var C := _isl(&"cay")
	var axis := Vector2.from_angle(float(C.aspect_dir))
	var crest := _H((C.center as Vector2) - axis * float(C.radius) * 0.6)
	var tail := _H((C.center as Vector2) + axis * float(C.radius) * float(C.aspect) * 0.8)
	check(crest > 1.4 and tail < 0.8 and tail > -0.4, "кей: гребень %.1f м над приливом, хвост косы %.2f м (заливается)" % [crest, tail])
	var Il := _isl(&"islet")
	var ih := _H(Il.center)
	var ie := _H((Il.center as Vector2) + Vector2(float(Il.radius) * 1.05, 0))
	check(ih > 15.0 and ie < 1.5, "скалистый островок: верх %.0f м, у воды %.1f м" % [ih, ie])
	var Sv := _isl(&"savanna")
	var sc2: Vector2 = Sv.center
	var Rw := arch._coast_r(Sv, 0.0)
	var Rl := arch._coast_r(Sv, PI)
	var beach_w := 0.0
	var beach_l := 0.0
	for k in 40:
		var t := 1.0 - k * 0.006
		if _H(sc2 + Vector2(Rw * t, 0)) < 1.8:
			beach_w += 1
		if _H(sc2 - Vector2(Rl * t, 0)) < 1.8:
			beach_l += 1
	check(beach_l > beach_w, "саванна: пляж шире с подветренной стороны (%d > %d)" % [beach_l, beach_w])
	var Co := _isl(&"coral")
	var reef_h := _H((Co.center as Vector2) + Vector2(0, arch._coast_r(Co, PI * 0.5) * 1.3))
	var deep_h := _H((Co.center as Vector2) + Vector2(0, arch._coast_r(Co, PI * 0.5) * 2.1))
	check(reef_h > -1.5 and deep_h < -8.0, "коралловый остров: риф-флэт %.1f м, за рифом глубина %.0f м" % [reef_h, deep_h])
	var Te := _entry(&"tombolo")
	var ta: Dictionary = arch.islands[int(Te.island_ids[0])]
	var tb: Dictionary = arch.islands[int(Te.island_ids[1])]
	var bar_mid: Vector2 = (arch.bars[0].pts as PackedVector2Array)[4]
	check(_H(bar_mid) > 0.7, "томболо: коса между близнецами над водой (%.2f м)" % _H(bar_mid))
	check(_H(ta.center) > 12.0 and _H(tb.center) > 8.0, "близнецы: оба холмистые")
	var Pl := _isl(&"plateau")
	var pc: Vector2 = Pl.center
	var tops: Array[float] = []
	for k in 30:
		tops.append(_H(pc + Vector2.from_angle(k * 2.4) * float(Pl.radius) * 0.5 * sqrt(k / 30.0)))
	var tmin: float = tops.min()
	var tmax: float = tops.max()
	check(tmin > 45.0 and tmax - tmin < 14.0, "плато: плоский верх %.0f–%.0f м" % [tmin, tmax])
	# ---- декор
	var ds: Dictionary = w.decor.stats
	print("[test] декор: ", ds)
	check(int(ds.streams) >= 3, "ручьи: %d" % int(ds.streams))
	check(int(ds.waterfalls) == 2, "водопады: %d (вулкан, плато)" % int(ds.waterfalls))
	check(int(ds.grottos) == 2, "гроты в карсте: %d" % int(ds.grottos))
	check(int(ds.guano) >= 40, "потёки на карнизах птичьего базара: %d" % int(ds.guano))
	check(arch.lakes.size() >= 1 and w.lake_level_at((arch.lakes[0].center as Vector2).x, (arch.lakes[0].center as Vector2).y) > 1.0,
		"озерцо под водопадом вулкана (уровень %.1f м)" % float(arch.lakes[0].level) if arch.lakes.size() > 0 else "озерцо")
	# ---- флора: по профилям типов
	var fs: Dictionary = sc.flora.stats
	print("[test] флора: ", fs)
	check(int(fs.get("palm", 0)) > 150 and int(fs.get("broadleaf", 0)) > 150 and int(fs.get("mangrove", 0)) > 80,
		"флора: пальм %d, лиственных %d, мангров %d" % [int(fs.get("palm", 0)), int(fs.get("broadleaf", 0)), int(fs.get("mangrove", 0))])
	# ---- снимки: каждый остров с пляжа и сверху
	sc.world.set_time_of_day(10.0)
	sc.set_photo_mode(true)
	check(not sc.player.hands.visible and not (sc.player.hud as CanvasLayer).visible, "фоторежим прячет руки и HUD")
	for i in list.size():
		var e: Dictionary = list[i]
		sc.go_beach(i)
		await wait(3.0)
		await shot("%02d_%s_beach" % [i + 1, String(e.type)])
		sc.go_air(i)
		await wait(3.0)
		await shot("%02d_%s_air" % [i + 1, String(e.type)])
	check(absf(sc.world.time_of_day() - 10.0) < 0.3, "время на полигоне стоит (%.2f ч после всех снимков)" % sc.world.time_of_day())
	# ---- водопад вулкана вблизи и грот
	var vf: Dictionary = {}
	for f: Dictionary in arch.features:
		if f.type == &"waterfall" and int(f.island) == int(V.id):
			vf = f
	if not vf.is_empty():
		var bot: Vector2 = vf.bottom
		var top: Vector2 = vf.top
		var dir := (bot - top).normalized()
		var eye := bot + dir * 34.0 + Vector2(-dir.y, dir.x) * 8.0
		sc.cheats.teleport(Vector3(eye.x, w.height_at(eye.x, eye.y) + 4.0, eye.y), Vector3(top.x, w.height_at(top.x, top.y) - 6.0, top.y))
		await wait(3.0)
		await shot("21_waterfall")
	for f: Dictionary in arch.features:
		if f.type == &"grotto":
			var m: Vector2 = f.mouth
			var inn: Vector2 = f.inner
			var out := m + (m - inn).normalized() * 30.0
			if not sc.cheats.fly:
				sc.cheats.set_fly(true)
			sc.cheats.teleport(Vector3(out.x, 3.0, out.y), Vector3(m.x, 2.0, m.y))
			await wait(3.0)
			await shot("22_grotto")
			break
	# ---- шторм у карста, закат над атоллом
	sc.go_beach(2)
	sc.cheats.set_weather(&"storm")
	await wait(4.0)
	await shot("23_karst_storm")
	sc.cheats.set_weather(&"clear")
	sc.world.set_time_of_day(18.6)
	sc.go_air(1)
	await wait(3.0)
	await shot("24_atoll_sunset")
	# ---- обзор всего ряда
	sc.world.set_time_of_day(11.0)
	sc.set_overview(true)
	await wait(4.0)
	await shot("25_overview")
	check(sc.overview_on(), "обзор всего ряда включается")
	sc.set_overview(false)
	sc.set_photo_mode(false)
	await wait(0.5)
	check(sc.player.hands.visible and (sc.player.hud as CanvasLayer).visible, "фоторежим выключается")
	check(not sc.overview_on() and sc.player.camera.current, "обзор выключается, камера игрока снова главная")
