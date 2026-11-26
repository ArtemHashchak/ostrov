class_name ArchipelagoV5
extends ShowcaseArch
## Архипелаг версии 5 (≈3×3 км, новая карта на каждое зерно).
## Граф островов по размеру (4 сектора, по одному на команду):
##   пара крошечных равных стартовых островков → средний → большой → огромный центр.
## Соседи 250–700 м открытой воды (3–6 минут на плоту). Центр — высокий
## вулканический остров; вокруг центра — неполное кольцо барьерного рифа с
## проходами (снаружи дикий океан глубже), окаймляющие рифы — у подветренных
## берегов (пассат из IslandGen.WIND_FROM). Рифы всегда ниже самого низкого отлива.
## «Памятники» (корабль на мели, родник, лагуна, маяк/вышка) — в monuments.
## Всё детерминировано от зерна. Высоты — аналитические (потокобезопасно).

const HALF := 1500.0              # полуширина карты, м
const LOW_TIDE := -0.8            # самый низкий уровень воды (World.tide_amplitude)
const REEF_TOP := -1.15           # верх гребня рифа: всегда под водой при отливе
const OCEAN_FLOOR := -34.0        # дикий океан за барьерным рифом
const LAGOON_FLOOR := -13.0       # внутри кольца

## Радиусы колец (центр→край) и размеры классов островов.
const D_LARGE := 700.0
const D_MEDIUM := 1180.0
const D_START := 1335.0
const D_EXTRA := 1250.0
const START_DA := 17.0            # угол стартовых островков от среднего, °
const START_R := 52.0
const START_H := 9.0

## Барьерный риф: радиус кольца, ширина, проходы.
var reef_r := 985.0
var reef_passes: Array[Vector2] = []      # (угол центра, полуширина) рад
## Памятники: {type: &"shipwreck"|&"spring"|&"lagoon"|&"lighthouse", pos: Vector2, island, yaw}
var monuments: Array[Dictionary] = []
## Классы островов по id: &"huge"|&"large"|&"medium"|&"start"|&"extra"
var size_class: Dictionary = {}
## Сектор (команда) острова: id → 0..3, центр — −1.
var sector_of: Dictionary = {}
## Рёбра графа маршрутов: [{a, b, gap}] (то же, что routes, но без кос/островков).
var links: Array[Dictionary] = []
var rot0 := 0.0
var ring_ecc := 0.0
var ring_ecc_dir := 0.0

var _n_ring := FastNoiseLite.new()

var seed_used := 0

func _init(seed_value: int = 2026) -> void:
	seed_used = seed_value
	_n_ring.seed = seed_value + 4421
	_n_ring.frequency = 0.9
	_n_ring.fractal_octaves = 3
	super._init(seed_value)

# ------------------------------------------------------------ раскладка

func _layout(seed_value: int) -> void:
	islands.clear()
	bars.clear()
	islets.clear()
	lakes.clear()
	routes.clear()
	wreck_spots.clear()
	features.clear()
	showcase.clear()
	monuments.clear()
	size_class.clear()
	sector_of.clear()
	links.clear()
	reef_passes.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 92821 + 17
	rot0 = rng.randf_range(0.0, 90.0)
	reef_r = rng.randf_range(960.0, 1005.0)
	ring_ecc = rng.randf_range(0.0, 0.06)
	ring_ecc_dir = rng.randf() * TAU
	# --- центр: высокий вулканический остров
	var cR := rng.randf_range(235.0, 265.0)
	var center := add_typed(&"volcanic", Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30)), cR, rng.randf_range(85.0, 100.0),
			{"beach_w": 0.055, "coast_amp": 0.13, "stream_ang": rng.randf() * TAU, "fall_r": 0.5})
	_volcanic_features(center, rng)
	_set_class(center, &"huge", -1, &"center")
	# --- большие (по одному между секторами), средние, стартовые, дополнительные
	var large_types: Array = [&"karst", &"plateau", &"mangrove", &"savanna"]
	var extra_types: Array = [&"atoll", &"coral", &"cay", &"islet"]
	_shuffle(large_types, rng)
	_shuffle(extra_types, rng)
	var larges: Array[Dictionary] = []
	var mediums: Array[Dictionary] = []
	var starts: Array = []
	var extras: Array[Dictionary] = []
	for t in 4:
		var th := deg_to_rad(rot0 + t * 90.0)
		var thl := th + deg_to_rad(45.0 + rng.randf_range(-8.0, 8.0))
		larges.append(_add_large(large_types[t], _polar(thl, D_LARGE + rng.randf_range(-40.0, 40.0)), rng, t))
		var med := add_typed(&"tombolo", _polar(th, D_MEDIUM + rng.randf_range(-35.0, 35.0)), rng.randf_range(90.0, 105.0),
				rng.randf_range(20.0, 26.0), {"beach_w": 0.12, "windward_cliffs": 0.45, "coast_amp": 0.15})
		_set_class(med, &"medium", t, &"shared")
		mediums.append(med)
		var pair: Array[Dictionary] = []
		for s in 2:
			var ths := th + deg_to_rad((START_DA + rng.randf_range(-1.5, 1.5)) * (1.0 if s == 0 else -1.0))
			var st := add_typed(&"savanna", _polar(ths, D_START), START_R, START_H,
					{"beach_w": 0.16, "windward_cliffs": 0.0, "coast_amp": 0.08})
			st.type = &"starter"
			st.flora_profile = STARTER_FLORA
			_set_class(st, &"start", t, &"home" if s == 0 else &"start")
			if s == 0:
				st.team = t
				st.name = "Стартовый островок — %s" % Archipelago._team_name(t)
			else:
				st.name = "Стартовый островок (второй)"
			pair.append(st)
		starts.append(pair)
		extras.append(_add_extra(extra_types[t], _polar(th + deg_to_rad(45.0 + rng.randf_range(-6.0, 6.0)),
				D_EXTRA + rng.randf_range(-40.0, 40.0)), rng, t))
	_relax_v5()
	# особенности строятся по окончательным центрам
	for I in islands:
		match StringName(I.type):
			&"karst":
				_karst_features(I)
			&"plateau":
				_plateau_features(I)
			&"islet":
				_islet_features(I, rng)
			&"mangrove":
				_make_creeks(I)
	# --- граф: стартовые → средний → большой (два соседних) → центр; дополнительные — к среднему и большому
	for t in 4:
		for st: Dictionary in starts[t]:
			_link(st, mediums[t])
		_link(mediums[t], larges[t])
		_link(mediums[t], larges[(t + 3) % 4])
		_link(larges[t], center)
		_link(extras[t], larges[t])
		var mb := mediums[t]
		for M in mediums:
			if strait_gap(extras[t], M) < strait_gap(extras[t], mb):
				mb = M
		_link(extras[t], mb)
	# --- барьерный риф: проходы напротив маршрутов средний↔большой (их 8) — не все, 5–6
	var pass_angles: Array[float] = []
	for t in 4:
		var a_m := (mediums[t].center as Vector2).angle()
		for L: Dictionary in [larges[t], larges[(t + 3) % 4]]:
			pass_angles.append(_mid_angle(a_m, (L.center as Vector2).angle()))
	_shuffle(pass_angles, rng)
	for k in rng.randi_range(5, 6):
		reef_passes.append(Vector2(pass_angles[k], rng.randf_range(0.055, 0.085)))
	# --- памятники
	_place_monuments(rng, center, larges, mediums, extras)
	# --- границы
	bounds = Rect2(-HALF, -HALF, HALF * 2.0, HALF * 2.0)

const STARTER_FLORA := {"tree": 0.9, "palm": 1.4, "rock": 0.8, "res": 1.0, "ore": 0.0, "mangrove": 0.2, "bush": 1.0, "herb": 0.8, "stick": 1.3}

func _set_class(I: Dictionary, cls: StringName, sector: int, kind: StringName) -> void:
	I.kind = kind
	I.angle = (I.center as Vector2).angle()
	size_class[int(I.id)] = cls
	sector_of[int(I.id)] = sector

func _polar(a: float, r: float) -> Vector2:
	return Vector2(cos(a), sin(a)) * r

func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

static func _mid_angle(a: float, b: float) -> float:
	return a + angle_difference(a, b) * 0.5

func _add_large(type: StringName, c: Vector2, rng: RandomNumberGenerator, t: int) -> Dictionary:
	var I: Dictionary
	match type:
		&"karst":
			I = add_typed(&"karst", c, rng.randf_range(160.0, 180.0), rng.randf_range(44.0, 54.0),
					{"coast_amp": 0.2, "coves": [Vector3(rng.randf() * TAU, 0.3, 0.3), Vector3(rng.randf() * TAU, 0.22, 0.24)]})
			_set_class(I, &"large", t, &"rocky")
		&"plateau":
			I = add_typed(&"plateau", c, rng.randf_range(160.0, 175.0), rng.randf_range(50.0, 60.0), {"coast_amp": 0.12, "edge": 0.1})
			_set_class(I, &"large", t, &"rocky")
		&"mangrove":
			I = add_typed(&"mangrove", c, rng.randf_range(170.0, 190.0), 1.9, {"coast_amp": 0.24, "beach_w": 0.0})
			_set_class(I, &"large", t, &"swamp")
		_:
			I = add_typed(&"savanna", c, rng.randf_range(165.0, 180.0), rng.randf_range(24.0, 30.0), {"beach_w": 0.12, "windward_cliffs": 0.7})
			_set_class(I, &"large", t, &"shared")
	return I

func _add_extra(type: StringName, c: Vector2, rng: RandomNumberGenerator, t: int) -> Dictionary:
	var I: Dictionary
	match type:
		&"atoll":
			I = add_typed(&"atoll", c, rng.randf_range(125.0, 145.0), 2.0,
					{"coast_amp": 0.07, "ring_in": 0.62, "passes": [rng.randf() * TAU, rng.randf() * TAU]})
			_set_class(I, &"extra", t, &"atoll")
		&"coral":
			I = add_typed(&"coral", c, rng.randf_range(85.0, 100.0), 3.2, {"beach_w": 0.22, "reef_out": 1.6, "coast_amp": 0.1})
			_set_class(I, &"extra", t, &"atoll")
		&"cay":
			I = add_typed(&"cay", c, rng.randf_range(55.0, 65.0), 1.9, {"coast_amp": 0.06, "aspect": 2.4, "aspect_dir": c.angle() + PI * 0.5})
			_set_class(I, &"extra", t, &"atoll")
		_:
			I = add_typed(&"islet", c, rng.randf_range(44.0, 52.0), rng.randf_range(20.0, 26.0), {"coast_amp": 0.2})
			_set_class(I, &"extra", t, &"rocky")
	return I

func _link(a: Dictionary, b: Dictionary) -> void:
	var g := strait_gap(a, b)
	links.append({"a": a.id, "b": b.id, "gap": g})
	routes.append({"a": a.id, "b": b.id, "gap": g})

## Раздвигаем острова, чтобы между любыми двумя было ≥ MIN_GAP воды.
const MIN_GAP := 250.0
func _relax_v5() -> void:
	for it in 40:
		var moved := false
		for i in islands.size():
			for j in range(i + 1, islands.size()):
				var a: Dictionary = islands[i]
				var b: Dictionary = islands[j]
				var g := strait_gap(a, b)
				if g >= MIN_GAP:
					continue
				var dir := ((b.center as Vector2) - (a.center as Vector2)).normalized()
				var push := (MIN_GAP - g) + 4.0
				var ma: bool = size_class.get(int(a.id), &"") != &"huge"
				var mb: bool = size_class.get(int(b.id), &"") != &"huge"
				if ma and mb:
					a.center = (a.center as Vector2) - dir * push * 0.5
					b.center = (b.center as Vector2) + dir * push * 0.5
				elif mb:
					b.center = (b.center as Vector2) + dir * push
				elif ma:
					a.center = (a.center as Vector2) - dir * push
				moved = true
		# не выходим за карту
		for I in islands:
			var c: Vector2 = I.center
			var lim := HALF - float(I.radius) * 1.7
			if c.length() > lim and size_class.get(int(I.id), &"") != &"huge":
				I.center = c.normalized() * lim
		if not moved:
			break
	for I in islands:
		I.angle = (I.center as Vector2).angle()
	# параметры, зависящие от центра, пересчитать (стоки/водопады строились до сдвига — сдвигаем вместе)

func _place_monuments(rng: RandomNumberGenerator, center: Dictionary, larges: Array[Dictionary], mediums: Array[Dictionary], extras: Array[Dictionary]) -> void:
	# корабль на мели: у берега кораллового острова и кея (риф у пляжа) и на
	# подветренном пляже большого «саванного» острова — рядом с сушей (записки, разбор)
	var wreck_isl: Array[Dictionary] = []
	for E in extras:
		if E.type == &"coral" or E.type == &"cay":
			wreck_isl.append(E)
	for L in larges:
		if L.type == &"savanna":
			wreck_isl.append(L)
	for E in wreck_isl:
		var a := atan2(-IslandGen.WIND_FROM.y, -IslandGen.WIND_FROM.x) + rng.randf_range(-0.9, 0.9)
		var p := (E.center as Vector2) + Vector2.from_angle(a) * _coast_r(E, a) * 1.1
		wreck_spots.append({"pos": p, "yaw": a + PI * 0.5 + rng.randf_range(-0.4, 0.4), "sink": 1.6, "island": E.id})
		monuments.append({"type": &"shipwreck", "pos": p, "island": E.id, "yaw": a + PI * 0.5})
	# родники: пресное озеро на двух больших (не мангровых) островах + пруд на вулкане (есть у водопада)
	var n_spring := 0
	for L in larges:
		if L.type == &"mangrove" or n_spring >= 2:
			continue
		var c: Vector2 = L.center
		var lc := c + (-c).normalized().rotated(rng.randf_range(-0.6, 0.6)) * float(L.radius) * 0.18
		var lvl := 3.8 if L.type == &"savanna" else 6.0
		lakes.append({"center": lc, "radius": float(L.radius) * 0.17, "level": lvl, "island": L.id, "kind": &"lake"})
		monuments.append({"type": &"spring", "pos": lc, "island": L.id, "yaw": 0.0})
		n_spring += 1
	# лагуна: атолл и лагуна внутри барьерного рифа у центра
	for E in extras:
		if E.type == &"atoll":
			monuments.append({"type": &"lagoon", "pos": E.center, "island": E.id, "yaw": 0.0})
	# маяк / наблюдательная вышка: на скальном островке (или краю плато)
	for E in extras:
		if E.type == &"islet":
			monuments.append({"type": &"lighthouse", "pos": E.center, "island": E.id, "yaw": 0.0})
	var has_lh := false
	for m in monuments:
		if m.type == &"lighthouse":
			has_lh = true
	if not has_lh:
		for L in larges:
			if L.type == &"plateau" or L.type == &"karst":
				var a := (-(L.center as Vector2)).angle() + PI
				monuments.append({"type": &"lighthouse", "pos": (L.center as Vector2) + Vector2.from_angle(a) * float(L.radius) * 0.8,
						"island": L.id, "yaw": a})
				break

# ------------------------------------------------------------ высоты

## Высота: дно (лагуна внутри кольца / дикий океан снаружи), острова, косы,
## островки, барьерный риф, озёра.
func height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var h := floor_h(p)
	var cell := _cell(x, z)
	if not cell.is_empty():
		for idx in cell.i:
			h = maxf(h, _island_h(islands[idx], p))
		for idx in cell.b:
			h = maxf(h, _bar_h(bars[idx], p))
		for idx in cell.l:
			h = maxf(h, _islet_h(islets[idx], p))
	var rh := barrier_h(p)
	if rh > h:
		h = rh
	if not cell.is_empty():
		for idx in cell.k:
			h = _lake_h(lakes[idx], p, h)
	return h

## Дно без островов: внутри кольца рифа — песчаная лагуна, снаружи — дикий океан.
func floor_h(p: Vector2) -> float:
	var r := p.length()
	var inner := SEA_FLOOR + 2.0 + _n_floor.get_noise_2d(p.x, p.y) * 2.5
	var outer := OCEAN_FLOOR + _n_floor.get_noise_2d(p.x * 0.5, p.y * 0.5) * 4.0
	return lerpf(inner, outer, smoothstep(reef_r + 40.0, reef_r + 260.0, r))

## Радиус гребня кольца в направлении ang: шум, слабый эллипс, «лопасти».
func ring_r(ang: float) -> float:
	var e := 1.0 + ring_ecc * cos(2.0 * (ang - ring_ecc_dir))
	return reef_r * e + _n_ring.get_noise_2d(cos(ang) * 1.6, sin(ang) * 1.6) * 95.0 \
		+ _n_ring.get_noise_2d(cos(ang) * 6.0 + 40.0, sin(ang) * 6.0) * 22.0

## Ширина риф-плато со стороны лагуны (м) — меняется вдоль кольца.
func ring_flat_w(ang: float) -> float:
	return 26.0 + 70.0 * (_n_ring.get_noise_2d(cos(ang) * 3.0 + 90.0, sin(ang) * 3.0) * 0.5 + 0.5)

## 0..1 — насколько точка в проходе.
func pass_factor(ang: float) -> float:
	var k := 0.0
	for ps in reef_passes:
		var d := absf(angle_difference(ang, ps.x))
		k = maxf(k, 1.0 - smoothstep(ps.y * 0.6, ps.y, d))
	return k

## Высота барьерного рифа (или −100 вдали от кольца): риф-плато со стороны
## лагуны, гребень, крутой внешний склон в океан. В проходах — глубоко.
func barrier_h(p: Vector2) -> float:
	var r := p.length()
	var ang := atan2(p.y, p.x)
	var rr := ring_r(ang)
	var t := r - rr       # <0 — к лагуне
	if t < -150.0 or t > 120.0:
		return -100.0
	var fw := ring_flat_w(ang)
	var crest := REEF_TOP - 0.15 + _n_detail.get_noise_2d(p.x * 0.7, p.y * 0.7) * 0.22 - absf(_n_reef.get_noise_2d(p.x * 2.0, p.y * 2.0)) * 0.6
	crest = minf(crest, REEF_TOP)
	var h: float
	if t < 0.0:
		# риф-плато (≈−2…−3.5 м) с пятнами-головами к лагуне
		var flat := -2.6 + _n_reef.get_noise_2d(p.x, p.y) * 1.4
		h = lerpf(flat, crest, smoothstep(-22.0, -4.0, t))
		h = lerpf(h, floor_h(p), smoothstep(-fw, -fw - 40.0, t))
	else:
		h = lerpf(crest, OCEAN_FLOOR * 0.7, smoothstep(4.0, 75.0, t))
	h = minf(h, REEF_TOP)
	var pf := pass_factor(ang)
	if pf > 0.0:
		h = lerpf(h, minf(h, -9.0 + _n_detail.get_noise_2d(p.x, p.y) * 1.5), pf)
	return h

## 0..1 — риф (кораллы растут) в точке: барьер и окаймляющие рифы островов.
## h — высота в точке (если известна).
func reef_factor(p: Vector2, h: float) -> float:
	if h > LOW_TIDE - 0.25 or h < -18.0:
		return 0.0
	var r := p.length()
	var t := r - ring_r(atan2(p.y, p.x))
	var k := 0.0
	var fw := ring_flat_w(atan2(p.y, p.x))
	if t > -fw - 40.0 and t < 70.0:
		k = (1.0 - smoothstep(30.0, 70.0, t)) * smoothstep(-fw - 40.0, -fw, t) * (1.0 - pass_factor(atan2(p.y, p.x)))
	# окаймляющий риф: мелководье у берега с подветренной стороны
	var ia := island_at(p)
	var I: Dictionary = ia.island
	if not I.is_empty():
		var d: float = ia.d
		var lee := 1.0 - smoothstep(-0.2, 0.5, _windward(p - (I.center as Vector2)))
		var fr := _bump(d, 1.0, 1.45) * lee * smoothstep(-0.9, -1.4, h) * (1.0 - smoothstep(-8.0, -14.0, h))
		k = maxf(k, fr)
	return clampf(k, 0.0, 1.0)

## Окаймляющие рифы (_sub из IslandGen): гуще с подветренной стороны и
## всегда ниже самого низкого отлива.
func _sub(I: Dictionary, p: Vector2, d: float, steep: float = 0.0, shelf_w: float = 0.12, reef: float = 1.0) -> float:
	var lee := 1.0 - smoothstep(-0.2, 0.6, _windward(p - (I.center as Vector2)))
	var h := super._sub(I, p, d, steep, shelf_w, reef * (0.35 + 0.65 * lee))
	if h > LOW_TIDE - 0.3 and d > 1.02:
		h = minf(h, REEF_TOP)
	return h

## Мангровые острова: вся низкая суша — мангровый лес/болото (не пляж).
func biome_weights(x: float, z: float, h: float) -> Color:
	var w := super.biome_weights(x, z, h)
	var ia := island_at(Vector2(x, z))
	var I: Dictionary = ia.island
	if not I.is_empty() and StringName(I.get("type", &"")) == &"mangrove" and float(ia.d) < 1.15:
		w.g = maxf(w.g, 1.0 - smoothstep(1.9, 2.6, h))
	return w

# ------------------------------------------------------------ сводка

## Класс острова: huge/large/medium/start/extra.
func class_of(I: Dictionary) -> StringName:
	return size_class.get(int(I.id), &"")

## Ближайший берег-к-берегу между двумя островами (через strait_gap).
func gap_between(a: Dictionary, b: Dictionary) -> float:
	return strait_gap(a, b)

func summary() -> Dictionary:
	var by_class := {}
	for I in islands:
		var c: StringName = class_of(I)
		by_class[c] = int(by_class.get(c, 0)) + 1
	return {"islands": islands.size(), "classes": by_class, "links": links.size(), "passes": reef_passes.size(),
		"monuments": monuments.size(), "reef_r": reef_r}
