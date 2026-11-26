class_name ZoneMap
extends RefCounted
## Карта зон мира (A11) — строится ОДИН раз генератором, всё, что ставится в мир
## (растения, животные, рыбы, кораллы, ресурсы, сценки), спрашивает только её.
## Растр с шагом STEP м по границам архипелага. В каждой ячейке:
##   h       — высота рельефа;
##   sea     — 1, если сюда дотекает открытое море (заливка от края карты по
##             ячейкам ниже высокой воды) — маска моря (A9); ямы ниже уровня моря,
##             отрезанные от моря сушей, — «сухие котловины» (не вода);
##   dist    — расстояние до берега, м (на суше — до моря, в море — до суши);
##   expo    — открытость волнам 0..1 (разгон ветра над водой с наветренной стороны);
##   wet     — влажность суши 0..1 (близость воды, болото, наветренность, джунгли);
##   jungle  — густота джунглей 0..1 (в центре острова — почти сплошная стена);
##   reef    — 0..1 риф (кораллы растут), только ниже самого низкого отлива;
##   zone    — тип зоны (константы Z_*).
## Глубина при самом низком отливе: depth_low = LOW_TIDE − h.

const STEP := 8.0
const LOW_TIDE := -0.8
const HIGH_TIDE := 0.8
const VERSION := 3

enum {
	Z_DEEP_OCEAN, Z_OCEAN, Z_LAGOON, Z_REEF_FLAT, Z_REEF_CREST, Z_REEF_SLOPE, Z_SHALLOWS, Z_MANGROVE_WATER,
	Z_BEACH, Z_DUNES, Z_PALM_BELT, Z_LOWLAND_FOREST, Z_JUNGLE, Z_ROCKS, Z_MANGROVE, Z_MEADOW,
	Z_FRESHWATER, Z_DRY_HOLLOW, Z_VOLCANIC,
}

## Имена зон — те же строки, что в каталоге ассетов (assets/catalog, поле zones).
const NAMES := [
	&"deep_ocean", &"ocean", &"lagoon", &"reef_flat", &"reef_crest", &"reef_slope", &"shallows", &"mangrove_water",
	&"beach", &"dunes", &"palm_belt", &"lowland_forest", &"jungle", &"rocks", &"mangrove", &"meadow",
	&"freshwater", &"dry_hollow", &"volcanic",
]

var origin := Vector2.ZERO
var nx := 0
var nz := 0
var h := PackedFloat32Array()
var dist := PackedFloat32Array()
var sea := PackedByteArray()
var zone := PackedByteArray()
var expo := PackedByteArray()
var wet := PackedByteArray()
var jungle := PackedByteArray()
var reef := PackedByteArray()
var _bw := PackedColorArray()     # веса биомов суши (временно, при построении)
var stats := {}
var wind_from := Vector2(1, 0)
var ring_center := Vector2.ZERO
var ring_r := 1e9

var _arch: Archipelago
var _hfn: Callable

## Построить по генератору. height_fn(x, z) -> float (потокобезопасная); по
## умолчанию — arch.height. cache_key — "" (без кэша) или ключ файла.
func build(arch: Archipelago, height_fn: Callable = Callable(), cache_key: String = "") -> void:
	_arch = arch
	_hfn = height_fn if height_fn.is_valid() else arch.height
	var t0 := Time.get_ticks_msec()
	var b := arch.bounds
	# сетка кратна STEP от нуля — совпадает с узлами чанков рельефа (64 м)
	origin = (b.position / STEP).floor() * STEP
	nx = int(ceil((b.end.x - origin.x) / STEP)) + 1
	nz = int(ceil((b.end.y - origin.y) / STEP)) + 1
	if arch.get(&"reef_r") != null:
		ring_r = float(arch.get(&"reef_r"))
	if arch.has_method(&"_windward"):
		wind_from = IslandGen.WIND_FROM
	if cache_key != "" and _load(cache_key):
		stats["ms"] = Time.get_ticks_msec() - t0
		stats["cached"] = true
		_arch = null
		return
	var n := nx * nz
	_rows.clear()
	for j in nz:
		_rows.append({})
	var gid := WorkerThreadPool.add_group_task(_sample_row, nz, -1, true, "zone map")
	WorkerThreadPool.wait_for_group_task_completion(gid)
	h.resize(n)
	_bw.resize(n)
	reef.resize(n)
	for j in nz:
		var r: Dictionary = _rows[j]
		var hr: PackedFloat32Array = r.h
		var br: PackedColorArray = r.bw
		var rr: PackedByteArray = r.reef
		for i in nx:
			var k := j * nx + i
			h[k] = hr[i]
			_bw[k] = br[i]
			reef[k] = rr[i]
	_rows.clear()
	var t1 := Time.get_ticks_msec()
	_flood_sea()
	_distance()
	_exposure()
	_classify()
	_bw = PackedColorArray()
	stats = {"cells": n, "sample_ms": t1 - t0, "ms": Time.get_ticks_msec() - t0, "nx": nx, "nz": nz}
	stats.merge(zone_histogram())
	if cache_key != "":
		_save(cache_key)
	_arch = null

var _rows: Array = []

func _sample_row(j: int) -> void:
	var z := origin.y + j * STEP
	var has_reef := _arch.has_method(&"reef_factor")
	var hr := PackedFloat32Array()
	hr.resize(nx)
	var br := PackedColorArray()
	br.resize(nx)
	var rr := PackedByteArray()
	rr.resize(nx)
	for i in nx:
		var x := origin.x + i * STEP
		var hh: float = _hfn.call(x, z)
		hr[i] = hh
		if hh > LOW_TIDE - 1.0:
			br[i] = _arch.biome_weights(x, z, hh)
		if has_reef and hh < LOW_TIDE:
			rr[i] = int(clampf(float(_arch.call(&"reef_factor", Vector2(x, z), hh)), 0.0, 1.0) * 255.0)
	var row: Dictionary = _rows[j]
	row["h"] = hr
	row["bw"] = br
	row["reef"] = rr

# ------------------------------------------------------------ маска моря

## Заливка от края карты по ячейкам ниже высокой воды (4-связность).
func _flood_sea() -> void:
	var n := nx * nz
	sea.resize(n)
	sea.fill(0)
	var q := PackedInt32Array()
	q.resize(n)
	var qh := 0
	var qt := 0
	for i in nx:
		for k in [i, (nz - 1) * nx + i]:
			if h[k] < HIGH_TIDE and sea[k] == 0:
				sea[k] = 1
				q[qt] = k
				qt += 1
	for j in nz:
		for k in [j * nx, j * nx + nx - 1]:
			if h[k] < HIGH_TIDE and sea[k] == 0:
				sea[k] = 1
				q[qt] = k
				qt += 1
	while qh < qt:
		var k := q[qh]
		qh += 1
		var i := k % nx
		var j := k / nx
		if i > 0 and sea[k - 1] == 0 and h[k - 1] < HIGH_TIDE:
			sea[k - 1] = 1
			q[qt] = k - 1
			qt += 1
		if i < nx - 1 and sea[k + 1] == 0 and h[k + 1] < HIGH_TIDE:
			sea[k + 1] = 1
			q[qt] = k + 1
			qt += 1
		if j > 0 and sea[k - nx] == 0 and h[k - nx] < HIGH_TIDE:
			sea[k - nx] = 1
			q[qt] = k - nx
			qt += 1
		if j < nz - 1 and sea[k + nx] == 0 and h[k + nx] < HIGH_TIDE:
			sea[k + nx] = 1
			q[qt] = k + nx
			qt += 1

# ------------------------------------------------------------ расстояния

## Расстояние до берега (chamfer 3-4, два прохода): на суше — до моря, в море — до суши.
func _distance() -> void:
	var n := nx * nz
	dist.resize(n)
	var INF := 1e9
	for k in n:
		dist[k] = 0.0 if _is_boundary(k) else INF
	var d1 := STEP
	var d2 := STEP * 1.41421
	for j in nz:
		for i in nx:
			var k := j * nx + i
			var v := dist[k]
			if v == 0.0:
				continue
			var s := sea[k]
			if i > 0 and sea[k - 1] == s:
				v = minf(v, dist[k - 1] + d1)
			if j > 0:
				if sea[k - nx] == s:
					v = minf(v, dist[k - nx] + d1)
				if i > 0 and sea[k - nx - 1] == s:
					v = minf(v, dist[k - nx - 1] + d2)
				if i < nx - 1 and sea[k - nx + 1] == s:
					v = minf(v, dist[k - nx + 1] + d2)
			dist[k] = v
	for j in range(nz - 1, -1, -1):
		for i in range(nx - 1, -1, -1):
			var k := j * nx + i
			var v := dist[k]
			if v == 0.0:
				continue
			var s := sea[k]
			if i < nx - 1 and sea[k + 1] == s:
				v = minf(v, dist[k + 1] + d1)
			if j < nz - 1:
				if sea[k + nx] == s:
					v = minf(v, dist[k + nx] + d1)
				if i < nx - 1 and sea[k + nx + 1] == s:
					v = minf(v, dist[k + nx + 1] + d2)
				if i > 0 and sea[k + nx - 1] == s:
					v = minf(v, dist[k + nx - 1] + d2)
			dist[k] = v
	for k in n:
		if dist[k] >= INF:
			dist[k] = 5000.0

func _is_boundary(k: int) -> bool:
	var s := sea[k]
	var i := k % nx
	var j := k / nx
	return (i > 0 and sea[k - 1] != s) or (i < nx - 1 and sea[k + 1] != s) \
		or (j > 0 and sea[k - nx] != s) or (j < nz - 1 and sea[k + nx] != s)

# ------------------------------------------------------------ волны

## Открытость волнам: разгон (fetch) — сколько метров открытой воды с
## наветренной стороны, по трём направлениям (ветер ±40°). 0 — тихо, 1 — ≥1.2 км.
func _exposure() -> void:
	var n := nx * nz
	var acc := PackedFloat32Array()
	acc.resize(n)
	acc.fill(0.0)
	var w := wind_from.normalized()
	var dirs: Array[Vector2] = [w, w.rotated(0.7), w.rotated(-0.7)]
	var wts := [0.5, 0.25, 0.25]
	for di in dirs.size():
		var d := dirs[di]
		var step := Vector2i(int(signf(roundf(d.x * 1.4))), int(signf(roundf(d.y * 1.4))))
		var len := STEP * Vector2(step).length()
		var fetch := PackedFloat32Array()
		fetch.resize(n)
		# проход так, чтобы наветренный сосед (k + step) был уже посчитан
		var jr := range(nz) if step.y <= 0 else range(nz - 1, -1, -1)
		var ir := range(nx) if step.x <= 0 else range(nx - 1, -1, -1)
		for j in jr:
			for i in ir:
				var k: int = j * nx + i
				if sea[k] != 1:
					fetch[k] = 0.0
					continue
				var ui: int = i + step.x
				var uj: int = j + step.y
				if ui < 0 or uj < 0 or ui >= nx or uj >= nz:
					fetch[k] = 2000.0
				else:
					fetch[k] = minf(fetch[uj * nx + ui] + len, 2000.0)
		for k in n:
			acc[k] += fetch[k] * float(wts[di])
	expo.resize(n)
	for k in n:
		expo[k] = int(clampf(acc[k] / 1200.0, 0.0, 1.0) * 255.0)
	# берег получает открытость ближайшей воды (2 прохода расширения)
	for it in 3:
		var nxt := expo.duplicate()
		for j in range(1, nz - 1):
			for i in range(1, nx - 1):
				var k := j * nx + i
				if sea[k] == 1 or dist[k] > 24.0:
					continue
				nxt[k] = maxi(maxi(expo[k - 1], expo[k + 1]), maxi(expo[k - nx], expo[k + nx]))
		expo = nxt

# ------------------------------------------------------------ зоны

func _classify() -> void:
	var n := nx * nz
	zone.resize(n)
	wet.resize(n)
	jungle.resize(n)
	jungle.fill(0)
	for j in nz:
		for i in nx:
			var k := j * nx + i
			var hh := h[k]
			var x := origin.x + i * STEP
			var z := origin.y + j * STEP
			if sea[k] == 1:
				wet[k] = 255
				zone[k] = _sea_zone(k, hh, x, z)
				continue
			if hh < 0.0 and sea[k] != 1:
				# отрезанная от моря яма: пресное озеро (если есть) или сухая котловина
				var lv := _lake_level(x, z, hh)
				zone[k] = Z_FRESHWATER if lv > hh else Z_DRY_HOLLOW
				wet[k] = 255 if lv > hh else 200
				continue
			zone[k] = _land_zone(k, hh, x, z, i, j)

func _lake_level(x: float, z: float, hh: float) -> float:
	return -INF if _arch == null else _arch.lake_level_at(x, z, hh)

func _sea_zone(k: int, hh: float, x: float, z: float) -> int:
	var depth := LOW_TIDE - hh
	var rf := float(reef[k]) / 255.0
	var ex := float(expo[k]) / 255.0
	var dl := dist[k]
	if rf > 0.3:
		if depth < 1.0:
			return Z_REEF_CREST
		if depth < 4.0:
			return Z_REEF_FLAT
		return Z_REEF_SLOPE
	# мангровая вода: у болотистого берега
	if depth < 3.0 and dl < 36.0:
		var bw := _near_land_bw(k)
		if bw.g > 0.4:
			return Z_MANGROVE_WATER
	if depth < 6.0:
		return Z_LAGOON if ex < 0.38 else Z_SHALLOWS
	var r := (Vector2(x, z) - ring_center).length()
	if depth > 24.0 or r > ring_r + 60.0:
		return Z_DEEP_OCEAN
	return Z_OCEAN

## Веса биомов ближайшей суши (в пределах 3 ячеек).
func _near_land_bw(k: int) -> Color:
	var i0 := k % nx
	var j0 := k / nx
	var best := Color(0, 0, 0, 0)
	for dj in range(-3, 4):
		for di in range(-3, 4):
			if di * di + dj * dj > 9:
				continue
			var i := i0 + di
			var j := j0 + dj
			if i < 0 or j < 0 or i >= nx or j >= nz:
				continue
			var kk := j * nx + i
			if sea[kk] != 1 and h[kk] > LOW_TIDE - 1.0:
				var c: Color = _bw[kk]
				if c.g > best.g:
					best = c
	return best

func _land_zone(k: int, hh: float, x: float, z: float, i: int, j: int) -> int:
	var bw: Color = _bw[k]
	var ds := dist[k]
	# уклон по соседям
	var hx := h[k + 1] - h[k - 1] if i > 0 and i < nx - 1 else 0.0
	var hz := h[k + nx] - h[k - nx] if j > 0 and j < nz - 1 else 0.0
	var slope := Vector2(hx, hz).length() / (2.0 * STEP)
	var ex := float(expo[k]) / 255.0
	# влажность: у воды и в болоте выше, на наветренной стороне выше (дождь), на высоте ниже
	var w := 0.35 + 0.35 * (1.0 - smoothstep(0.0, 90.0, ds)) + 0.4 * bw.g + 0.25 * bw.r - 0.15 * smoothstep(20.0, 70.0, hh)
	wet[k] = int(clampf(w, 0.0, 1.0) * 255.0)
	if _lake_level(x, z, hh) > hh:
		return Z_FRESHWATER
	if bw.b > 0.5 or slope > 0.85:
		return Z_ROCKS
	if bw.a > 0.5 and hh > 2.5:
		return Z_VOLCANIC
	if bw.g > 0.45:
		return Z_MANGROVE
	if hh < 1.6:
		return Z_BEACH
	if hh < 3.4 and ds < 46.0 and slope < 0.22 and ex > 0.15:
		return Z_DUNES
	# джунгли: густота растёт вглубь острова (стена в центре, реже к краям)
	var jg := bw.r * smoothstep(30.0, 130.0, ds) * (1.0 - smoothstep(0.55, 0.9, slope))
	jungle[k] = int(clampf(jg * 1.15, 0.0, 1.0) * 255.0)
	if ds < 55.0:
		return Z_PALM_BELT
	if bw.r > 0.45:
		return Z_JUNGLE
	if bw.r < 0.18 and w < 0.55:
		return Z_MEADOW
	return Z_LOWLAND_FOREST

# ------------------------------------------------------------ запросы

func _idx(x: float, z: float) -> int:
	var i := clampi(int(roundf((x - origin.x) / STEP)), 0, nx - 1)
	var j := clampi(int(roundf((z - origin.y) / STEP)), 0, nz - 1)
	return j * nx + i

func inside(x: float, z: float) -> bool:
	return x >= origin.x and z >= origin.y and x <= origin.x + (nx - 1) * STEP and z <= origin.y + (nz - 1) * STEP

func zone_at(x: float, z: float) -> int:
	return zone[_idx(x, z)] if nx > 0 else Z_OCEAN

func zone_name_at(x: float, z: float) -> StringName:
	return NAMES[zone_at(x, z)]

static func zone_name(z: int) -> StringName:
	return NAMES[z] if z >= 0 and z < NAMES.size() else &""

static func zone_id(name: StringName) -> int:
	return NAMES.find(name)

func height_at(x: float, z: float) -> float:
	return h[_idx(x, z)]

## Высота с билинейной интерполяцией между узлами (шаг STEP).
func height_lerp(x: float, z: float) -> float:
	var fx := clampf((x - origin.x) / STEP, 0.0, nx - 1.001)
	var fz := clampf((z - origin.y) / STEP, 0.0, nz - 1.001)
	var i := int(fx)
	var j := int(fz)
	var u := fx - i
	var v := fz - j
	var k := j * nx + i
	return lerpf(lerpf(h[k], h[k + 1], u), lerpf(h[k + nx], h[k + nx + 1], u), v)

## Открытое море (дотекает от края карты).
func is_sea(x: float, z: float) -> bool:
	return sea[_idx(x, z)] == 1

## Глубина воды при самом низком отливе (<0 — суша при отливе).
func depth_low(x: float, z: float) -> float:
	return LOW_TIDE - h[_idx(x, z)]

func dist_to_coast(x: float, z: float) -> float:
	return dist[_idx(x, z)]

func exposure(x: float, z: float) -> float:
	return float(expo[_idx(x, z)]) / 255.0

func wetness(x: float, z: float) -> float:
	return float(wet[_idx(x, z)]) / 255.0

func jungle_density(x: float, z: float) -> float:
	return float(jungle[_idx(x, z)]) / 255.0

func reef_at(x: float, z: float) -> float:
	return float(reef[_idx(x, z)]) / 255.0

## Можно ли ставить морскую жизнь/кораллы: открытое море, глубже min_depth при отливе.
func water_ok(x: float, z: float, min_depth: float = 0.4) -> bool:
	var k := _idx(x, z)
	return sea[k] == 1 and LOW_TIDE - h[k] >= min_depth

## Сухая суша (не море, не озеро, не котловина ниже нуля).
func land_ok(x: float, z: float) -> bool:
	var k := _idx(x, z)
	var zz := zone[k]
	return sea[k] != 1 and zz != Z_FRESHWATER and zz != Z_DRY_HOLLOW and h[k] > HIGH_TIDE

func zone_histogram() -> Dictionary:
	var cnt := {}
	for k in zone.size():
		var nm: StringName = NAMES[zone[k]]
		cnt[nm] = int(cnt.get(nm, 0)) + 1
	return {"zones": cnt}

## Текстура маски моря (R: 1 — открытое море) для шейдеров океана (агент D):
## по ней можно не рисовать воду в отрезанных ямах. Пиксель = STEP м, начало — origin.
func sea_mask_image() -> Image:
	var img := Image.create(nx, nz, false, Image.FORMAT_L8)
	var data := PackedByteArray()
	data.resize(nx * nz)
	for k in nx * nz:
		data[k] = 255 if sea[k] == 1 else 0
	img.set_data(nx, nz, false, Image.FORMAT_L8, data)
	return img

# ------------------------------------------------------------ кэш

static func cache_dir() -> String:
	var dir := "user://cache/zonemap" if OS.get_environment("OSTROVA_TERRAIN_CACHE") != "1" \
			else ProjectSettings.globalize_path("res://.godot/test_cache")
	DirAccess.make_dir_recursive_absolute(dir if dir.begins_with("/") else ProjectSettings.globalize_path(dir))
	return dir

func _path(key: String) -> String:
	return cache_dir() + "/zonemap_v%d_%s.bin" % [VERSION, key]

func _load(key: String) -> bool:
	var p := _path(key)
	if not FileAccess.file_exists(p):
		return false
	var f := FileAccess.open_compressed(p, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return false
	var d: Variant = bytes_to_var(f.get_buffer(f.get_length()))
	f.close()
	if not (d is Dictionary) or int(d.get("nx", -1)) != nx or int(d.get("nz", -1)) != nz:
		return false
	h = d.h
	dist = d.dist
	sea = d.sea
	zone = d.zone
	expo = d.expo
	wet = d.wet
	jungle = d.jungle
	reef = d.reef
	stats = d.get("stats", {})
	return true

func _save(key: String) -> void:
	var p := _path(key)
	var tmp := p + ".tmp%d" % OS.get_process_id()
	var f := FileAccess.open_compressed(tmp, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return
	f.store_buffer(var_to_bytes({"nx": nx, "nz": nz, "h": h, "dist": dist, "sea": sea, "zone": zone, "expo": expo,
		"wet": wet, "jungle": jungle, "reef": reef, "stats": stats}))
	f.close()
	DirAccess.rename_absolute(tmp, p)

## Ключ кэша: зерно + все скрипты генератора.
static func make_key(seed_value: int, extra: String = "") -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(("%d|%s" % [seed_value, extra]).to_utf8_buffer())
	for d in ["res://scripts/world", "res://scripts/world/gen", "res://scripts/world/islands"]:
		var files := DirAccess.get_files_at(d)
		files.sort()
		for f in files:
			if f.ends_with(".gd"):
				ctx.update(FileAccess.get_file_as_bytes(d + "/" + f))
	return ctx.finish().hex_encode().substr(0, 16)
