class_name IslandGen
extends Archipelago
## Генератор островов по типам («рецептам») — основа будущего архипелага 3×3 км.
## Каждый остров — словарь Archipelago (id, kind, center, radius, max_h, …) плюс:
##   type     — тип рецепта (TYPES), по нему считаются высоты и биомы;
##   kind     — «старый» вид для модулей (Sea, Fauna, Survival), см. TYPES[type].kind;
##   p        — параметры рецепта (дополнительные к общим);
##   coast_amp, aspect, aspect_dir — изрезанность и вытянутость берега.
## Рецепты дают аналитическую высоту H(x, z) (потокобезопасно) и веса биомов
## для покраски рельефа (r — джунгли, g — болото/ил, b — скала, a — чёрный
## вулканический песок/порода). Особенности, которые рельефом не передать
## (водопады, ручьи, гроты, птичьи карнизы), пишутся в features — их строит
## IslandDecor.
##
## Наветренная сторона: пассат дует из WIND_FROM (восток); там влажнее (джунгли
## гуще), на подветренной суше (саванна, широкие пляжи).

const WIND_FROM := Vector2(1.0, 0.0)

## Описание типов: name — подпись, kind — вид для старых модулей,
## flora — профиль рассадки Flora (множители категорий, см. Flora.PROFILES).
const TYPES := {
	&"volcanic": {"name": "Высокий вулканический остров", "kind": &"center",
		"flora": {"tree": 1.35, "palm": 0.7, "rock": 1.0, "res": 1.4, "ore": 0.6, "mangrove": 0.3, "herb": 1.6, "bush": 1.3}},
	&"atoll": {"name": "Атолл с лагуной", "kind": &"atoll",
		"flora": {"tree": 0.15, "palm": 2.2, "rock": 0.1, "res": 0.4, "ore": 0.0, "mangrove": 0.5, "bush": 0.8}},
	&"karst": {"name": "Известняковый остров (карст)", "kind": &"rocky",
		"flora": {"tree": 1.1, "palm": 0.5, "rock": 1.2, "res": 0.8, "ore": 0.4, "mangrove": 0.0, "bush": 1.4, "herb": 0.8}},
	&"mangrove": {"name": "Мангровый остров", "kind": &"swamp",
		"flora": {"tree": 0.8, "palm": 0.3, "rock": 0.05, "res": 1.0, "ore": 0.0, "mangrove": 3.2, "herb": 1.4}},
	&"cay": {"name": "Песчаный кей и коса", "kind": &"atoll",
		"flora": {"tree": 0.0, "palm": 0.9, "rock": 0.0, "res": 0.2, "ore": 0.0, "mangrove": 0.0, "bush": 0.7, "stick": 1.5}},
	&"islet": {"name": "Скалистый островок с птичьим базаром", "kind": &"rocky",
		"flora": {"tree": 0.0, "palm": 0.0, "rock": 1.6, "res": 0.1, "ore": 0.4, "mangrove": 0.0, "bush": 0.25, "herb": 0.2}},
	&"savanna": {"name": "Сухой остров (саванна)", "kind": &"home",
		"flora": {"tree": 0.35, "palm": 1.3, "rock": 1.0, "res": 0.9, "ore": 0.3, "mangrove": 0.1, "bush": 0.6}},
	&"coral": {"name": "Низкий коралловый остров с рифом", "kind": &"atoll",
		"flora": {"tree": 0.25, "palm": 2.6, "rock": 0.1, "res": 0.6, "ore": 0.0, "mangrove": 0.2, "bush": 0.9}},
	&"tombolo": {"name": "Острова-близнецы с томболо", "kind": &"shared",
		"flora": {"tree": 1.0, "palm": 1.1, "rock": 0.9, "res": 1.0, "ore": 0.3, "mangrove": 0.3, "bush": 1.0}},
	&"plateau": {"name": "Столовый остров (плато)", "kind": &"rocky",
		"flora": {"tree": 0.7, "palm": 0.6, "rock": 1.3, "res": 0.9, "ore": 0.8, "mangrove": 0.0, "bush": 0.9, "herb": 0.9}},
}

## Особенности для IslandDecor:
##   {type: &"stream", island, pts: PackedVector2Array (от истока к устью), width}
##   {type: &"waterfall", island, top: Vector2, bottom: Vector2, width, sea: bool}
##   {type: &"grotto", island, mouth: Vector2, inner: Vector2, width, height}
##   {type: &"ledges", island, center: Vector2, radius, top}
var features: Array[Dictionary] = []

var _n_karst := FastNoiseLite.new()
var _n_terr := FastNoiseLite.new()

func _init(seed_value: int = 2026) -> void:
	_n_karst.seed = seed_value + 9001
	_n_karst.noise_type = FastNoiseLite.TYPE_CELLULAR
	_n_karst.frequency = 0.035
	_n_karst.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	_n_terr.seed = seed_value + 9101
	_n_terr.frequency = 0.05
	_n_terr.fractal_octaves = 3
	super._init(seed_value)

# ------------------------------------------------------------ добавление

## Остров типа type в точке center (мировые XZ). params переопределяют рецепт.
func add_typed(type: StringName, center: Vector2, radius: float, max_h: float, params: Dictionary = {}) -> Dictionary:
	var td: Dictionary = TYPES.get(type, TYPES[&"savanna"])
	var I := {
		"id": islands.size(), "kind": td.kind, "type": type, "team": -1, "center": center,
		"radius": radius, "max_h": max_h, "cliff_dir": -1.0, "lagoon_dir": -1.0,
		"beach_w": float(params.get("beach_w", BEACH_W)), "name": String(td.name), "angle": 0.0,
		"coast_amp": float(params.get("coast_amp", 0.15)), "aspect": float(params.get("aspect", 1.0)),
		"aspect_dir": float(params.get("aspect_dir", 0.0)), "p": params, "flora_profile": td.flora,
	}
	islands.append(I)
	if type == &"mangrove":
		_make_creeks(I)
	return I

## Приливные протоки мангров: от берега внутрь с меандрами и боковыми рукавами,
## ширина сужается к вершине. I.creeks = [{pts: PackedVector2Array, w0, w1, bmin, bmax}].
func _make_creeks(I: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(I.id) * 7919 + 11
	var c: Vector2 = I.center
	var R: float = I.radius
	var creeks: Array = []
	var n := int((I.p as Dictionary).get("creeks", 6))
	for k in n:
		var a := (float(k) + rng.randf_range(-0.3, 0.3)) * TAU / float(n)
		var depth := rng.randf_range(0.55, 0.85)
		var main := _creek_path(c + Vector2.from_angle(a) * R * 1.08, c + Vector2.from_angle(a + rng.randf_range(-0.5, 0.5)) * R * (1.0 - depth), rng, 7.0)
		creeks.append({"pts": main, "w0": rng.randf_range(9.0, 14.0), "w1": 2.5})
		for b in rng.randi_range(1, 2):
			var at := main[rng.randi_range(2, main.size() - 4)]
			var out := (at - c).normalized().rotated(rng.randf_range(0.7, 1.4) * (1.0 if rng.randf() < 0.5 else -1.0))
			var br := _creek_path(at, at + out * R * rng.randf_range(0.15, 0.3), rng, 4.0)
			creeks.append({"pts": br, "w0": rng.randf_range(4.0, 6.0), "w1": 1.5})
	for cr: Dictionary in creeks:
		var pts: PackedVector2Array = cr.pts
		var mn := pts[0]
		var mx := pts[0]
		for q in pts:
			mn = Vector2(minf(mn.x, q.x), minf(mn.y, q.y))
			mx = Vector2(maxf(mx.x, q.x), maxf(mx.y, q.y))
		cr["bmin"] = mn - Vector2(20, 20)
		cr["bmax"] = mx + Vector2(20, 20)
	I["creeks"] = creeks

func _creek_path(a: Vector2, b: Vector2, rng: RandomNumberGenerator, wiggle: float) -> PackedVector2Array:
	## Случайное блуждание к цели: курс поворачивает плавно (меандры), шаг ~6 м.
	var pts := PackedVector2Array([a])
	var p := a
	var heading := (b - a).angle()
	var turn := 0.0
	var total := a.distance_to(b)
	var stepl := 6.0
	var guard := 0
	while p.distance_to(b) > stepl and guard < 400:
		guard += 1
		var want := (b - p).angle()
		turn = clampf(turn + rng.randf_range(-0.25, 0.25) * wiggle / 7.0, -0.55, 0.55)
		var rem := clampf(p.distance_to(b) / maxf(total, 1.0), 0.0, 1.0)
		heading += angle_difference(heading, want) * lerpf(0.75, 0.16, rem) + turn * 0.35 * rem
		p += Vector2.from_angle(heading) * stepl
		pts.append(p)
		if pts.size() > int(total / stepl * 2.5):
			break
	pts.append(b)
	return pts

## Расстояние до ближайшей протоки и её ширина там: Vector2(dist, width).
func _creek_dist(I: Dictionary, p: Vector2) -> Vector2:
	var best := Vector2(1e9, 0.0)
	for cr: Dictionary in I.get("creeks", []):
		var mn: Vector2 = cr.bmin
		var mx: Vector2 = cr.bmax
		if p.x < mn.x or p.y < mn.y or p.x > mx.x or p.y > mx.y:
			continue
		var pts: PackedVector2Array = cr.pts
		for k in pts.size() - 1:
			var dd := _seg_dist(p, pts[k], pts[k + 1])
			if dd < best.x:
				var t := float(k) / float(pts.size() - 1)
				best = Vector2(dd, lerpf(float(cr.w0), float(cr.w1), t))
	return best

# ------------------------------------------------------------ берег

## Радиус берега по углу: шум изрезанности, вытянутость (эллипс), бухты.
func _coast_r(I: Dictionary, ang: float) -> float:
	if not I.has("type"):
		return super._coast_r(I, ang)
	var id := float(I.id)
	var cn := _n_coast.get_noise_2d(cos(ang) * 70.0 + id * 1000.0, sin(ang) * 70.0)
	var cn2 := _n_detail.get_noise_2d(cos(ang) * 40.0 + id * 333.0, sin(ang) * 40.0)
	var r := float(I.radius) * (1.0 + float(I.coast_amp) * cn + float(I.coast_amp) * 0.35 * cn2)
	var asp := float(I.aspect)
	if not is_equal_approx(asp, 1.0):
		var t := ang - float(I.aspect_dir)
		# эллипс с полуосями asp·R и R/asp^0.5
		var a := asp
		var b := 1.0 / sqrt(asp)
		r *= 1.0 / sqrt(pow(cos(t) / a, 2.0) + pow(sin(t) / b, 2.0))
	# бухты (карст, плато): узкие вырезы в береге
	var p: Dictionary = I.p
	for cv: Variant in p.get("coves", []):
		var cd: Vector3 = cv     # x — угол, y — полуширина (рад), z — глубина (доля R)
		# полукруглая бухта: профиль √(1 − x²) по углу, сглаженный у входа
		var x := absf(angle_difference(ang, cd.x)) / cd.y
		var k := sqrt(maxf(0.0, 1.0 - x * x)) * smoothstep(1.0, 0.85, x) if x < 1.0 else 0.0
		r *= 1.0 - cd.z * k
	return r

# ------------------------------------------------------------ высоты

func _island_h(I: Dictionary, p: Vector2) -> float:
	if not I.has("type"):
		return super._island_h(I, p)
	var c: Vector2 = I.center
	var v := p - c
	var dist := v.length()
	var reach := float(I.radius) * maxf(float(I.aspect), 1.0) * 2.3
	if dist > reach:
		return -100.0
	var ang := atan2(v.y, v.x)
	var R := _coast_r(I, ang)
	var d := dist / R
	var inland := 1.0 - d
	match StringName(I.type):
		&"volcanic":
			return _h_volcanic(I, p, v, ang, d, inland)
		&"atoll":
			return _h_atoll(I, p, ang, d)
		&"karst":
			return _h_karst(I, p, ang, d, inland)
		&"mangrove":
			return _h_mangrove(I, p, d, inland)
		&"cay":
			return _h_cay(I, p, d, inland)
		&"islet":
			return _h_islet(I, p, ang, d, inland)
		&"coral":
			return _h_coral(I, p, d, inland)
		&"plateau":
			return _h_plateau(I, p, ang, d, inland)
		_:
			return _h_hilly(I, p, v, ang, d, inland)

## Подводный склон: шельф с рифами, под утёсами — сразу глубоко.
func _sub(I: Dictionary, p: Vector2, d: float, steep: float = 0.0, shelf_w: float = 0.12, reef: float = 1.0) -> float:
	var shelf := lerpf(0.0, -2.4, smoothstep(1.0, 1.0 + shelf_w, d))
	var h := lerpf(shelf, SEA_FLOOR, smoothstep(1.0 + shelf_w, 1.0 + shelf_w + 0.7, d))
	h = lerpf(h, minf(h, lerpf(-3.0, SEA_FLOOR, smoothstep(1.0, 1.25, d))), steep * smoothstep(1.0, 1.03, d))
	var rf := smoothstep(0.18, 0.42, _n_reef.get_noise_2d(p.x, p.y)) * _bump(d, 1.02, 1.0 + shelf_w + 0.18) * (1.0 - steep) * reef
	if rf > 0.0:
		h = maxf(h, lerpf(h, -0.8 + _n_detail.get_noise_2d(p.x, p.y) * 0.35, rf))
	return h + _n_floor.get_noise_2d(p.x, p.y) * 0.8 * smoothstep(1.2, 1.6, d)

## Пляж: от уреза воды до бровки (BEACH_H), с дюнами.
func _beach(p: Vector2, inland: float, bw: float, top: float = BEACH_H) -> float:
	var hb := top * smoothstep(0.0, bw, inland)
	return hb + 0.5 * maxf(0.0, _n_dune.get_noise_2d(p.x, p.y)) * _bump(inland, 0.02, bw + 0.05)

## Наветренность точки острова: 1 — к ветру, −1 — под ветром.
func _windward(v: Vector2) -> float:
	return v.normalized().dot(WIND_FROM) if v.length_squared() > 1.0 else 0.0

# --- 1. Высокий вулканический остров: конус с радиальными гребнями и долинами,
# амфитеатр с водопадом и ручьём, чёрный песок.
func _h_volcanic(I: Dictionary, p: Vector2, _v: Vector2, ang: float, d: float, inland: float) -> float:
	if d >= 1.0:
		return _sub(I, p, d, 0.0, 0.1, 0.6)
	var mh := float(I.max_h)
	var P: Dictionary = I.p
	# вершина смещена к наветренной стороне не будет — к центру с шумом
	var off: Vector2 = P.get("summit", Vector2.ZERO)
	var q := p - (I.center as Vector2) - off
	var rq := q.length() / (float(I.radius) * 0.95)
	var cone := pow(clampf(1.0 - rq, 0.0, 1.0), 1.55)
	# радиальные гребни и долины (эрозия): угловая волна со сдвигом от шума
	var warp := _n_hills.get_noise_2d(p.x * 0.5, p.y * 0.5) * 3.2
	var ridges := lerpf(1.0, absf(sin(ang * 9.0 + warp + rq * 4.0)), smoothstep(0.12, 0.3, rq))
	var vdepth := (1.0 - pow(ridges, 0.6)) * (5.0 + 9.0 * smoothstep(0.1, 0.6, inland)) * smoothstep(0.08, 0.35, inland) * (1.0 - smoothstep(0.82, 0.95, inland))
	var h := BEACH_H + 0.4 + (mh - BEACH_H) * cone
	h -= vdepth
	h += _n_ridge.get_noise_2d(p.x, p.y) * 4.0 * smoothstep(0.15, 0.5, inland)
	h += _n_hills.get_noise_2d(p.x * 1.7, p.y * 1.7) * 2.5 * smoothstep(0.1, 0.4, inland)
	# амфитеатр: уступ (сброс) поперёк главной долины — водопад
	var sa := float(P.get("stream_ang", 0.0))
	var da := absf(angle_difference(ang, sa))
	var fall_r := float(P.get("fall_r", 0.48))    # где уступ (доля радиуса от центра)
	var amph := (1.0 - smoothstep(0.22, 0.42, da))
	if amph > 0.0:
		# ниже уступа — чаша амфитеатра (понижение), выше — плечо
		var below := smoothstep(fall_r - 0.01, fall_r + 0.015, d)
		var cut := below * (h - lerpf(9.0, BEACH_H + 1.5, smoothstep(fall_r, 0.97, d))) * amph
		h -= maxf(cut, 0.0)
	# русло ручья: от истока выше уступа до моря
	var pts: PackedVector2Array = P.get("stream_pts", PackedVector2Array())
	if pts.size() > 1:
		var best := 1e9
		for k in pts.size() - 1:
			best = minf(best, _seg_dist(p, pts[k], pts[k + 1]))
		var w := 6.0
		if best < w * 3.0:
			var bed := maxf(h - lerpf(3.2, 1.4, smoothstep(0.6, 0.98, d)), BEACH_H * 0.6)
			h = lerpf(bed, h, smoothstep(w * 0.4, w * 3.0, best))
	# чёрный пляж
	var hb := _beach(p, inland, float(I.beach_w), BEACH_H * 0.9)
	h = lerpf(hb, h, smoothstep(float(I.beach_w) - 0.01, float(I.beach_w) + 0.07, inland))
	return h + _n_detail.get_noise_2d(p.x, p.y) * 0.35

# --- 2. Атолл: кольцо рифа с моту (островками), мелкая лагуна с коралловыми
# пятнами, проходы в кольце, внешний гребень рифа и обрыв.
func _h_atoll(I: Dictionary, p: Vector2, ang: float, d: float) -> float:
	var P: Dictionary = I.p
	var ring_in := float(P.get("ring_in", 0.74))
	# проходы в кольце
	var pass_k := 0.0
	for pa: Variant in P.get("passes", []):
		pass_k = maxf(pass_k, 1.0 - smoothstep(0.04, 0.09, absf(angle_difference(ang, float(pa)))))
	if d >= 1.0:
		# гребень рифа и обрыв
		var crest := lerpf(-0.25, -1.4, smoothstep(1.0, 1.08, d))
		var h := lerpf(crest, SEA_FLOOR - 4.0, smoothstep(1.08, 1.35, d))
		h += _n_reef.get_noise_2d(p.x * 1.5, p.y * 1.5) * 0.4 * (1.0 - smoothstep(1.0, 1.15, d))
		return lerpf(h, minf(h, -3.0), pass_k * (1.0 - smoothstep(1.0, 1.2, d)))
	if d < ring_in:
		# лагуна: дно −3…−7, коралловые «башни» до −0.7
		var t := smoothstep(ring_in, ring_in - 0.18, d)
		var bed := lerpf(-0.9, -5.5 + _n_floor.get_noise_2d(p.x * 3.0, p.y * 3.0) * 1.5, t)
		var pin := smoothstep(0.55, 0.8, _n_karst.get_noise_2d(p.x * 0.7, p.y * 0.7) * 0.5 + 0.5)
		bed = maxf(bed, lerpf(bed, -0.7 + _n_detail.get_noise_2d(p.x, p.y) * 0.3, pin * t))
		return bed
	# кольцо: риф-флэт (заливается в прилив) и моту
	var u := (d - ring_in) / (1.0 - ring_in)    # 0 — к лагуне, 1 — к морю
	var flat := -0.35 + 0.25 * _n_detail.get_noise_2d(p.x * 0.8, p.y * 0.8)
	var motu_n := _n_coast.get_noise_2d(cos(ang) * 55.0 + 777.0, sin(ang) * 55.0)
	var motu := smoothstep(-0.1, 0.1, motu_n) * smoothstep(0.04, 0.28, u) * (1.0 - smoothstep(0.82, 0.97, u)) * (1.0 - pass_k)
	var h_motu := BEACH_H + 0.9 + 0.6 * maxf(0.0, _n_dune.get_noise_2d(p.x, p.y))
	var h := lerpf(flat, h_motu, motu)
	# к лагуне — песчаный склон, к морю — гребень
	h = minf(h, lerpf(-1.2, h, smoothstep(0.0, 0.18, u)))
	return lerpf(h, -2.6, pass_k)

# --- 3. Карст: башни известняка с отвесными стенами прямо из воды, волноприбойная
# ниша у воды, бухты с карманными пляжами, воронки и «зубцы» на вершине, гроты.
func _h_karst(I: Dictionary, p: Vector2, ang: float, d: float, inland: float) -> float:
	var mh := float(I.max_h)
	# бухта — карманный пляж
	var cove := 0.0
	for cv: Variant in (I.p as Dictionary).get("coves", []):
		var cd: Vector3 = cv
		cove = maxf(cove, 1.0 - smoothstep(cd.y * 0.6, cd.y * 1.15, absf(angle_difference(ang, cd.x))))
	if d >= 1.0:
		return lerpf(_sub(I, p, d, 1.0, 0.05, 0.3), _sub(I, p, d, 0.0, 0.1, 0.6), cove)
	# верх: ячеистый карст — башни и воронки
	var cell := _n_karst.get_noise_2d(p.x, p.y)       # 0..~1: края ячеек выше
	var towers := pow(smoothstep(-0.25, 0.55, cell), 1.6)
	var top := mh * (0.32 + 0.68 * towers) + _n_ridge.get_noise_2d(p.x * 1.5, p.y * 1.5) * 4.0
	# отвесная стена: почти сразу от воды
	var wall := smoothstep(0.0, 0.035, inland)
	var bench := 0.9 + 0.3 * _n_detail.get_noise_2d(p.x, p.y)        # волноприбойная терраса
	var h := lerpf(bench, top, smoothstep(0.012, 0.04, inland))
	h = lerpf(lerpf(-0.6, bench, smoothstep(0.0, 0.012, inland)), h, wall)
	# в бухте — пляж и пологий подъём к подножию стены дальше вглубь
	if cove > 0.0:
		var hb := _beach(p, inland, 0.16)
		var back := lerpf(hb, top, smoothstep(0.2, 0.3, inland))
		h = lerpf(h, minf(h, back), cove)
	# гроты: узкие протоки в стене
	for f in features:
		if f.type == &"grotto" and int(f.island) == int(I.id):
			var sd := _seg_dist(p, f.mouth, f.inner)
			var w: float = f.width
			if sd < w * 1.6:
				h = minf(h, lerpf(-1.6, h, smoothstep(w * 0.45, w * 1.6, sd)))
	return h + _n_detail.get_noise_2d(p.x * 1.4, p.y * 1.4) * 0.6 * smoothstep(0.03, 0.1, inland)

# --- 4. Мангры: низкие кочки, сеть приливных проток, илистые отмели по краю
# (обнажаются в отлив).
func _h_mangrove(I: Dictionary, p: Vector2, d: float, inland: float) -> float:
	var cd := _creek_dist(I, p)
	var creek := 1.0 - smoothstep(cd.y * 0.35, cd.y * 0.75, cd.x)
	if d >= 1.0:
		# широкая илистая отмель (обнажается в отлив), к ней выходят устья проток
		var mud := lerpf(-0.15, -1.3, smoothstep(1.0, 1.32, d)) + _n_floor.get_noise_2d(p.x * 2.0, p.y * 2.0) * 0.18
		mud = lerpf(mud, minf(mud, -1.3), creek)
		return lerpf(mud, SEA_FLOOR, smoothstep(1.32, 1.85, d))
	# почти плоская суша: у края ~0.3 (заливается в прилив), вглубь до ~1.5, редкие кочки
	var base := 0.3 + 1.0 * smoothstep(0.0, 0.55, inland) + _n_hills.get_noise_2d(p.x * 0.8, p.y * 0.8) * 0.22
	base += 0.45 * smoothstep(0.62, 0.8, _n_ridge.get_noise_2d(p.x * 0.6, p.y * 0.6) * 0.5 + 0.5) * smoothstep(0.25, 0.5, inland)
	# мелкие лужицы-«окна» с илом
	var pool := smoothstep(0.55, 0.75, _n_karst.get_noise_2d(p.x * 0.5, p.y * 0.5)) * smoothstep(0.15, 0.35, inland)
	base = lerpf(base, 0.05, pool * 0.8)
	# протока: дно −1.2 у устья → −0.3 в вершине, илистые бровки
	var floor_h := lerpf(-1.2, -0.3, clampf(inland * 1.6, 0.0, 1.0))
	var h := lerpf(base, floor_h, creek * creek * (3.0 - 2.0 * creek))
	var bank := (1.0 - smoothstep(cd.y * 0.75, cd.y * 1.6, cd.x)) * (1.0 - creek)
	h = lerpf(h, minf(h, 0.45), bank * 0.6)
	return h + _n_detail.get_noise_2d(p.x * 1.5, p.y * 1.5) * 0.08

# --- 5. Песчаный кей: невысокий гребень с редкой травой и длинная коса,
# которую заливает в прилив; вокруг — обширные бирюзовые отмели.
func _h_cay(I: Dictionary, p: Vector2, d: float, inland: float) -> float:
	if d >= 1.0:
		var flats := lerpf(-0.4, -1.6, smoothstep(1.0, 1.7, d))
		flats += _n_dune.get_noise_2d(p.x * 0.6, p.y * 0.6) * 0.35
		return lerpf(flats, SEA_FLOOR, smoothstep(1.9, 2.25, d))
	var crest := float(I.max_h)
	# гребень ближе к одному краю, к хвосту косы понижается до ~0.3 (заливает)
	var c: Vector2 = I.center
	var axis := Vector2.from_angle(float(I.aspect_dir))
	var along := (p - c).dot(axis) / (float(I.radius) * float(I.aspect))   # −1…1
	var spine := lerpf(crest, 0.35, smoothstep(-0.35, 0.95, along))
	var h := spine * smoothstep(0.0, 0.55, inland) + 0.15
	h += 0.35 * maxf(0.0, _n_dune.get_noise_2d(p.x * 1.3, p.y * 1.3)) * smoothstep(0.1, 0.5, inland)
	return h

# --- 6. Скалистый островок: отвесные бока, ступенчатые карнизы (птичий базар),
# столбы-кекуры вокруг.
func _h_islet(I: Dictionary, p: Vector2, _ang: float, d: float, inland: float) -> float:
	if d >= 1.0:
		return _sub(I, p, d, 0.85, 0.06, 0.2)
	var mh := float(I.max_h)
	var raw := mh * pow(smoothstep(0.0, 0.75, inland), 0.55) * (0.85 + 0.25 * _n_hills.get_noise_2d(p.x * 2.0, p.y * 2.0))
	raw += _n_ridge.get_noise_2d(p.x * 2.5, p.y * 2.5) * 1.5
	# карнизы: квантование высоты по 3.2 м, кромка ступени чуть закруглена
	var step := 3.2
	var k := raw / step
	var fr := k - floorf(k)
	var terr := (floorf(k) + smoothstep(0.72, 1.0, fr)) * step
	var h := lerpf(raw, terr, 0.85 * smoothstep(0.04, 0.12, inland))
	h = lerpf(lerpf(-0.8, 1.2, smoothstep(0.0, 0.015, inland)), h, smoothstep(0.0, 0.05, inland))
	return h + _n_detail.get_noise_2d(p.x * 3.0, p.y * 3.0) * 0.35

# --- 7/9. Холмистый остров (саванна, близнецы): пологие холмы, широкие пляжи на
# подветренной стороне, невысокие обрывы на наветренной.
func _h_hilly(I: Dictionary, p: Vector2, v: Vector2, _ang: float, d: float, inland: float) -> float:
	var ww := _windward(v)
	var cliff := smoothstep(0.55, 0.85, ww) * float((I.p as Dictionary).get("windward_cliffs", 0.6))
	if d >= 1.0:
		return _sub(I, p, d, cliff * 0.8, 0.12 + 0.08 * maxf(0.0, -ww), 0.5)
	var bw := float(I.beach_w) * (1.0 + 0.9 * maxf(0.0, -ww))
	var hb := _beach(p, inland, bw)
	var hn := _n_hills.get_noise_2d(p.x * 0.8, p.y * 0.8) * 0.5 + 0.5
	var rn := _n_ridge.get_noise_2d(p.x * 0.7, p.y * 0.7) * 0.5 + 0.5
	var core := pow(smoothstep(0.05, 0.9, inland), 1.1)
	var hi := BEACH_H + 0.3 + float(I.max_h) * core * (0.35 + 0.5 * hn + 0.3 * rn)
	var h := lerpf(hb, hi, smoothstep(bw - 0.02, bw + 0.12, inland))
	if cliff > 0.0:
		var hc := maxf(h, float(I.max_h) * 0.45 * smoothstep(0.0, 0.05, inland) + hi * 0.4)
		h = lerpf(h, hc, cliff)
	return h + _n_detail.get_noise_2d(p.x, p.y) * 0.25 * smoothstep(0.08, 0.3, inland)

# --- 8. Низкий коралловый остров: плоский, широкие белые пляжи, пальмовая роща,
# широкий окаймляющий риф (риф-флэт, гребень, лагуна между рифом и берегом).
func _h_coral(I: Dictionary, p: Vector2, d: float, inland: float) -> float:
	if d >= 1.0:
		var reef_out := float((I.p as Dictionary).get("reef_out", 1.55))
		var aa := atan2(p.y - (I.center as Vector2).y, p.x - (I.center as Vector2).x)
		reef_out += 0.22 * _n_coast.get_noise_2d(cos(aa) * 45.0 + 2222.0, sin(aa) * 45.0)
		# мелкая «бухточка» между берегом и рифом, плоский риф-флэт, гребень, обрыв
		var moat := lerpf(-0.5, -1.8, _bump(d, 1.0, lerpf(1.0, reef_out, 0.55)))
		var flat := -0.6 + _n_reef.get_noise_2d(p.x * 1.2, p.y * 1.2) * 0.35
		var t := smoothstep(lerpf(1.0, reef_out, 0.45), lerpf(1.0, reef_out, 0.6), d)
		var h := lerpf(moat, flat, t)
		h = lerpf(h, -0.35, _bump(d, reef_out - 0.06, reef_out + 0.02))
		return lerpf(h, SEA_FLOOR - 3.0, smoothstep(reef_out, reef_out + 0.3, d))
	var hb := _beach(p, inland, float(I.beach_w), BEACH_H * 1.05)
	var hi := BEACH_H + 0.35 + float(I.max_h) * smoothstep(0.1, 0.8, inland) * (0.6 + 0.4 * (_n_hills.get_noise_2d(p.x, p.y) * 0.5 + 0.5))
	return lerpf(hb, hi, smoothstep(float(I.beach_w) - 0.02, float(I.beach_w) + 0.12, inland)) + _n_detail.get_noise_2d(p.x, p.y) * 0.12

# --- 10. Плато: плоский верх (слоистый), обрывы по всему берегу, осыпи у подножия,
# узкий пляж у основания стен местами, водопад с края плато прямо в море.
func _h_plateau(I: Dictionary, p: Vector2, ang: float, d: float, inland: float) -> float:
	var mh := float(I.max_h)
	var talus_n := smoothstep(0.1, 0.5, _n_coast.get_noise_2d(cos(ang) * 60.0 + 4000.0, sin(ang) * 60.0))
	if d >= 1.0:
		return _sub(I, p, d, 1.0 - talus_n * 0.7, 0.07, 0.4)
	var top := mh + _n_hills.get_noise_2d(p.x * 0.6, p.y * 0.6) * 3.0 + _n_detail.get_noise_2d(p.x, p.y) * 0.5
	# слоистость стен: уступы по 7 м на стене
	var edge := float((I.p as Dictionary).get("edge", 0.1))
	var wall_t := smoothstep(0.0, edge, inland)
	var strata := wall_t * top
	var sk := strata / 7.0
	strata = lerpf(strata, (floorf(sk) + smoothstep(0.6, 1.0, sk - floorf(sk))) * 7.0, 0.55 * wall_t * (1.0 - wall_t) * 4.0)
	# осыпь у подножия (там, где есть узкий пляж)
	var talus := lerpf(_beach(p, inland, 0.025), mh * 0.35, smoothstep(0.02, 0.07, inland))
	var h := lerpf(strata, maxf(strata, talus), talus_n * (1.0 - smoothstep(0.06, 0.09, inland)))
	h = maxf(h, _beach(p, inland, 0.02) * talus_n)
	# водопад: ручей по плато к краю
	for f in features:
		if f.type == &"stream" and int(f.island) == int(I.id):
			var pts: PackedVector2Array = f.pts
			var best := 1e9
			for k in pts.size() - 1:
				best = minf(best, _seg_dist(p, pts[k], pts[k + 1]))
			if best < 14.0:
				h = minf(h, lerpf(h - 2.2, h, smoothstep(2.0, 14.0, best)))
	return h

# ------------------------------------------------------------ биомы

func biome_weights(x: float, z: float, h: float) -> Color:
	var p := Vector2(x, z)
	var ia := island_at(p)
	var I: Dictionary = ia.island
	if I.is_empty() or not I.has("type"):
		return super.biome_weights(x, z, h)
	var d: float = ia.d
	if d > 1.4:
		return Color(0, 0, 0, 0)
	var c: Vector2 = I.center
	var v := p - c
	var inland := 1.0 - d
	var ww := _windward(v)
	var moist := clampf(_n_moist.get_noise_2d(x, z) * 0.5 + 0.5 + ww * 0.18, 0.0, 1.0)
	var slope_rock := 0.0
	match StringName(I.type):
		&"volcanic":
			# чёрный песок и лава у берега, джунгли по склонам (гуще с наветра и в долинах),
			# скалы на крутых гребнях и у вершины
			var black := 1.0 - smoothstep(0.02, 0.08, inland)
			var lava := smoothstep(0.35, 0.6, _n_ridge.get_noise_2d(x * 1.5, z * 1.5)) * (1.0 - smoothstep(0.08, 0.25, inland))
			var high := smoothstep(float(I.max_h) * 0.72, float(I.max_h) * 0.92, h)
			var jl := smoothstep(0.25, 0.5, moist + 0.15) * smoothstep(0.05, 0.14, inland) * (1.0 - high * 0.8)
			return Color(jl, 0.0, high * 0.7, maxf(black, lava))
		&"atoll", &"cay", &"coral":
			var veg := smoothstep(BEACH_H + 0.3, BEACH_H + 1.2, h) * (0.3 if StringName(I.type) == &"cay" else 0.55)
			return Color(veg * smoothstep(0.4, 0.6, moist), 0.0, 0.0, 0.0)
		&"karst":
			var wall := (1.0 - smoothstep(0.03, 0.07, inland)) * smoothstep(2.5, 6.0, h)
			var top_rock := smoothstep(0.55, 0.8, _n_karst.get_noise_2d(x, z)) * 0.6
			return Color((1.0 - wall) * smoothstep(0.3, 0.5, moist) * smoothstep(0.06, 0.1, inland), 0.0, maxf(wall, top_rock), 0.0)
		&"mangrove":
			# ил у проток, в «окнах» и по низкому краю; выше — лес
			var cd := _creek_dist(I, p)
			var near := 1.0 - smoothstep(cd.y * 0.8, cd.y * 2.2, cd.x)
			var mud := maxf(maxf(near, 1.0 - smoothstep(0.55, 0.95, h)), 1.0 - smoothstep(0.02, 0.06, inland))
			return Color((1.0 - mud) * (0.55 + 0.4 * moist), mud, 0.0, 0.0)
		&"islet":
			return Color(0.0, 0.0, 1.0, 0.15)
		&"plateau":
			var wall2 := 1.0 - smoothstep(0.06, 0.11, inland)
			var topj := smoothstep(0.45, 0.65, moist) * smoothstep(0.1, 0.16, inland)
			return Color(topj, 0.0, maxf(wall2 * smoothstep(3.0, 6.0, h), 0.0), 0.0)
		_:
			# саванна / холмы: сухо под ветром, полоса леса с наветра
			var dry_bias := -0.2 if StringName(I.type) == &"savanna" else 0.0
			var jl2 := smoothstep(0.5, 0.7, moist + dry_bias + ww * 0.15) * smoothstep(0.12, 0.25, inland)
			slope_rock = smoothstep(0.6, 0.9, ww) * smoothstep(3.0, 6.0, h) * (1.0 - smoothstep(0.06, 0.12, inland))
			return Color(jl2 * (1.0 - slope_rock), 0.0, slope_rock, 0.0)

## Точка на пляже/у кромки острова под углом a.
func beach_point(I: Dictionary, a: float) -> Vector2:
	if not I.has("type"):
		return super.beach_point(I, a)
	var R := _coast_r(I, a)
	var c: Vector2 = I.center
	var d := 0.97
	if StringName(I.type) == &"atoll":
		d = 0.9
	return c + Vector2.from_angle(a) * R * d

## Подпись типа.
static func type_name(type: StringName) -> String:
	return String((TYPES.get(type, {}) as Dictionary).get("name", String(type)))
