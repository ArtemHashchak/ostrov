class_name TerrainChunks
extends Node3D
## Рельеф архипелага чанками 64×64 м.
## • Выборка высот и весов биомов идёт параллельно (WorkerThreadPool), меши
##   собираются в главном потоке.
## • Чанки у суши (что-то выше −9 м): отсчёты 1 м и три LOD по дальности
##   (1 м до LOD1, 2 м до LOD2, 4 м до LOD3, 8 м дальше) — все из одной выборки; у LOD
##   «юбки» по краям, чтобы не было щелей между уровнями.
## • Открытое море: один меш 4 м, без теней.
## • Коллизия — HeightMapShape3D на отсчёты того же чанка (1 м у суши, 4 м в
##   море). height_at() интерполирует ровно по треугольникам меша/коллизии.
## Дальность прорисовки ограничена visibility_range (за FAR чанк не рисуется —
## дальше туман и океан), отсечение по фрустуму — штатное по AABB чанка.

const CHUNK := 64.0
const FINE := 1.0
const MID := 2.0
const COARSE := 4.0
const LOD1 := 90.0       # дальше — меш 2 м
const LOD2 := 210.0      # дальше — меш 4 м
const LOD3 := 520.0      # дальше — меш 8 м
const FAR := 3500.0      # дальность по умолчанию; фактическую задаёт ViewDistance (настройка «Дальность видимости»)
## Без гистерезиса: с запасом (margin) и без плавного перехода LOD сохраняет
## прежнее состояние в полосе ±margin. После телепорта (возрождение, смена
## камеры) соседние уровни оба оставались скрытыми — «дыры» в рельефе, сквозь
## которые видна серая плоскость океана.
const MARGIN := 0.0
## Диагональ квадрата: true — (0,0)-(1,1), false — как у HeightMapShape3D в Godot.
const DIAG_MAIN := false

var arch: Archipelago
var _chunks: Dictionary = {}   # Vector2i → {step, n, origin: Vector2, h: PackedFloat32Array}
var material: Material
var water_mean := 0.0
var stats := {}                # время этапов, треугольники по LOD

var _keys: Array[Vector2i] = []
var _jobs: Array[Dictionary] = []

func build(a: Archipelago, mat: Material) -> void:
	arch = a
	material = mat
	var t0 := Time.get_ticks_usec()
	var b := arch.bounds
	var cx0 := int(floor(b.position.x / CHUNK))
	var cz0 := int(floor(b.position.y / CHUNK))
	var cx1 := int(ceil(b.end.x / CHUNK))
	var cz1 := int(ceil(b.end.y / CHUNK))
	_keys.clear()
	_jobs.clear()
	for cz in range(cz0, cz1):
		for cx in range(cx0, cx1):
			_keys.append(Vector2i(cx, cz))
			_jobs.append({})
	var cache_path := _cache_path()
	if not _load_cache(cache_path):
		var gid := WorkerThreadPool.add_group_task(_job, _keys.size(), -1, true, "terrain sample")
		WorkerThreadPool.wait_for_group_task_completion(gid)
		_save_cache(cache_path)
	var t1 := Time.get_ticks_usec()
	var tris := {"lod0": 0, "lod1": 0, "lod2": 0, "lod3": 0, "sea": 0}
	_sea_blocks.clear()
	_far_blocks.clear()
	for i in _keys.size():
		_build_chunk(_keys[i], _jobs[i], tris)
	_flush_sea_blocks()
	_flush_far_blocks()
	_jobs.clear()
	var t2 := Time.get_ticks_usec()
	stats = {"sample_ms": (t1 - t0) / 1000, "mesh_ms": (t2 - t1) / 1000, "chunks": _keys.size(),
			"tris": tris, "threads": OS.get_processor_count()}

func chunk_count() -> Dictionary:
	var fine := 0
	var coarse := 0
	for k in _chunks:
		if is_equal_approx(float(_chunks[k].step), FINE):
			fine += 1
		else:
			coarse += 1
	return {"fine": fine, "coarse": coarse, "total": _chunks.size()}

# ------------------------------------------------------------ кэш выборки (тесты)
## OSTROVA_TERRAIN_CACHE=1 (ставит tests/run.sh): выборка высот сохраняется в
## .godot/test_cache и при повторном запуске читается вместо 15–30 с расчёта.
## Ключ — сид, размер мира и md5 скриптов scripts/world/*.gd (любая правка генератора → новый кэш).

func _cache_path() -> String:
	if OS.get_environment("OSTROVA_TERRAIN_CACHE") != "1":
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(("%s|%d|%d" % [str(arch.bounds), arch.islands.size(), _keys.size()]).to_utf8_buffer())
	var files := DirAccess.get_files_at("res://scripts/world")
	files.sort()
	for f in files:
		if f.ends_with(".gd"):
			ctx.update(FileAccess.get_file_as_bytes("res://scripts/world/" + f))
	var key := ctx.finish().hex_encode().substr(0, 16)
	var dir := ProjectSettings.globalize_path("res://.godot/test_cache")
	DirAccess.make_dir_recursive_absolute(dir)
	return dir + "/terrain_" + key + ".bin"

func _load_cache(path: String) -> bool:
	if path == "" or not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return false
	var data: Variant = bytes_to_var(f.get_buffer(f.get_length()))
	f.close()
	if not (data is Array) or (data as Array).size() != _keys.size():
		return false
	for i in _keys.size():
		_jobs[i] = data[i]
	print("[terrain] выборка высот из кэша: ", path.get_file())
	return true

func _save_cache(path: String) -> void:
	if path == "":
		return
	var tmp := path + ".tmp%d" % OS.get_process_id()
	var f := FileAccess.open_compressed(tmp, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return
	f.store_buffer(var_to_bytes(_jobs))
	f.close()
	DirAccess.rename_absolute(tmp, path)

# ------------------------------------------------------------ выборка (потоки)

func _job(i: int) -> void:
	var key := _keys[i]
	var out: Dictionary = _jobs[i]
	var origin := Vector2(key.x * CHUNK, key.y * CHUNK)
	# классификация по пробам через 4 м: суша/мелководье → 1 м,
	# только подводный шельф (всё ниже −2.5 м) → 2 м, глубина → 4 м
	var hmax := -100.0
	var s := 0.0
	while s <= CHUNK:
		var t := 0.0
		while t <= CHUNK:
			hmax = maxf(hmax, arch.height(origin.x + s, origin.y + t))
			t += 4.0
		s += 4.0
	var shallow := hmax > -9.0
	var step := COARSE
	if hmax > -2.5:
		step = FINE
	elif shallow:
		step = MID
	var n := int(CHUNK / step) + 1
	var m := n + 2
	var hh := PackedFloat32Array()
	hh.resize(m * m)
	for j in m:
		var z := origin.y + (j - 1) * step
		for ii in m:
			hh[j * m + ii] = arch.height(origin.x + (ii - 1) * step, z)
	var inner := PackedFloat32Array()
	inner.resize(n * n)
	var norms := PackedVector3Array()
	norms.resize(n * n)
	var cols := PackedColorArray()
	cols.resize(n * n)
	for j in n:
		for ii in n:
			var h := hh[(j + 1) * m + (ii + 1)]
			var idx := j * n + ii
			inner[idx] = h
			norms[idx] = Vector3(hh[(j + 1) * m + ii] - hh[(j + 1) * m + ii + 2], 2.0 * step,
					hh[j * m + ii + 1] - hh[(j + 2) * m + ii + 1]).normalized()
			cols[idx] = arch.biome_weights(origin.x + ii * step, origin.y + j * step, h) if h > -2.5 else Color(0, 0, 0, 0)
	out["shallow"] = shallow
	out["step"] = step
	out["n"] = n
	out["origin"] = origin
	out["h"] = inner
	out["nrm"] = norms
	out["col"] = cols

# ------------------------------------------------------------ меши (главный поток)

func _build_chunk(key: Vector2i, data: Dictionary, tris: Dictionary) -> void:
	_chunks[key] = {"step": data.step, "n": data.n, "origin": data.origin, "h": data.h}
	var base := "T_%d_%d" % [key.x, key.y]
	if data.shallow:
		var levels := [[1, 0.0, LOD1, "lod0"], [2, LOD1, LOD2, "lod1"], [4, LOD2, LOD3, "lod2"], [8, LOD3, FAR, "lod3"]]
		var under := float(data.step) > FINE + 0.1   # подводный шельф (шаг 2 м)
		if under:
			levels = [[1, 0.0, LOD2, "lod1"], [2, LOD2, LOD3, "lod2"], [4, LOD3, FAR, "lod3"]]
		for L in levels:
			if String(L[3]) == "lod3":
				# дальний LOD (520–1500 м) — в общие блоки, см. _flush_far_blocks
				var fbk := Vector2i(floori(float(key.x) / SEA_BLOCK), floori(float(key.y) / SEA_BLOCK))
				if not _far_blocks.has(fbk):
					_far_blocks[fbk] = []
				(_far_blocks[fbk] as Array).append(_make_mesh(data, int(L[0])).surface_get_arrays(0))
				tris[L[3]] += _tri_count(int(data.n), int(L[0]))
				continue
			var mi := MeshInstance3D.new()
			mi.name = base + "_" + String(L[3])
			mi.mesh = _make_mesh(data, int(L[0]))
			mi.material_override = material
			mi.visibility_range_begin = float(L[1])
			mi.visibility_range_end = float(L[2])
			mi.visibility_range_begin_margin = MARGIN if float(L[1]) > 0.0 else 0.0
			mi.visibility_range_end_margin = MARGIN
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			# тени рельефа — от прокси 2 м (ниже), сам LOD0 их не отбрасывает:
			# тень рисуется в 4 каскадах, полная детализация там в 4 раза дороже
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			tris[L[3]] += _tri_count(int(data.n), int(L[0]))
			if not under and int(L[0]) == 2:
				var sh := MeshInstance3D.new()
				sh.name = base + "_shadow"
				sh.mesh = mi.mesh
				sh.material_override = material
				sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
				sh.visibility_range_end = LOD1
				sh.visibility_range_end_margin = MARGIN
				add_child(sh)
	else:
		# глубокое дно: копим в блоки SEA_BLOCK×SEA_BLOCK чанков и рисуем одним мешем
		# (вершины чанков уже в мировых координатах) — вместо ~250 вызовов отрисовки ~20
		var bk := Vector2i(floori(float(key.x) / SEA_BLOCK), floori(float(key.y) / SEA_BLOCK))
		if not _sea_blocks.has(bk):
			_sea_blocks[bk] = []
		(_sea_blocks[bk] as Array).append(_make_mesh(data, 1).surface_get_arrays(0))
		tris.sea += _tri_count(int(data.n), 1)
	_make_collision(data, key)

const SEA_BLOCK := 4
var _sea_blocks: Dictionary = {}   # Vector2i блока → [массивы поверхностей чанков]

var _far_blocks: Dictionary = {}   # Vector2i блока → [массивы LOD3 чанков]

## Склейка массивов поверхностей чанков в один меш (вершины уже мировые); dy — сдвиг по высоте.
static func _merge(parts: Array, dy: float = 0.0) -> ArrayMesh:
	var v := PackedVector3Array()
	var nr := PackedVector3Array()
	var c := PackedColorArray()
	var ix := PackedInt32Array()
	for a: Array in parts:
		var base := v.size()
		v.append_array(a[Mesh.ARRAY_VERTEX])
		nr.append_array(a[Mesh.ARRAY_NORMAL])
		c.append_array(a[Mesh.ARRAY_COLOR])
		var src: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var off := ix.size()
		ix.append_array(src)
		for i in range(off, ix.size()):
			ix[i] += base
	if dy != 0.0:
		for i in v.size():
			v[i].y += dy
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nr
	arr[Mesh.ARRAY_COLOR] = c
	arr[Mesh.ARRAY_INDEX] = ix
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh

func _flush_sea_blocks() -> void:
	for bk: Vector2i in _sea_blocks:
		var mi := MeshInstance3D.new()
		mi.name = "Tsea_%d_%d" % [bk.x, bk.y]
		mi.mesh = _merge(_sea_blocks[bk])
		mi.material_override = material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# дальность — по настройке «Дальность видимости» (ViewDistance; на «Максимуме» — 6 км)
		ViewDistance.cap(mi, ViewDistance.MAXIMUM, ViewDistance.G_TERRAIN)
		add_child(mi)
	_sea_blocks.clear()

## Дальний рельеф блоками 4×4 чанка. Блок включается раньше, чем гаснет LOD2 любого
## своего чанка (LOD3 − полудиагональ блока), поэтому дыр нет; там, где оба видны,
## блок на 0.8 м ниже и прячется под LOD2.
func _flush_far_blocks() -> void:
	var half_diag := CHUNK * SEA_BLOCK * 0.5 * sqrt(2.0)
	for bk: Vector2i in _far_blocks:
		var mi := MeshInstance3D.new()
		mi.name = "Tfar_%d_%d" % [bk.x, bk.y]
		mi.mesh = _merge(_far_blocks[bk], -0.8)
		mi.material_override = material
		mi.visibility_range_begin = maxf(LOD3 - half_diag, 0.0)
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# дальше выбранной дальности видимости блок не рисуется (туман густеет к этой границе)
		ViewDistance.cap(mi, ViewDistance.MAXIMUM, ViewDistance.G_TERRAIN)
		add_child(mi)
	_far_blocks.clear()

static func _tri_count(n: int, sub: int) -> int:
	var q := (n - 1) / sub
	return q * q * 2 + q * 4 * 4

## Меш из отсчётов чанка с прореживанием sub (1, 2, 4, 8) + юбки по краям.
func _make_mesh(data: Dictionary, sub: int) -> ArrayMesh:
	var n: int = data.n
	var step: float = data.step
	var origin: Vector2 = data.origin
	var hh: PackedFloat32Array = data.h
	var nn: PackedVector3Array = data.nrm
	var cc: PackedColorArray = data.col
	var q := (n - 1) / sub          # квадратов по стороне
	var k := q + 1                  # вершин по стороне
	var skirt := 0.6 + step * sub * 0.6
	var nv := k * k + 4 * k
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(nv)
	norms.resize(nv)
	cols.resize(nv)
	for j in k:
		for i in k:
			var src := (j * sub) * n + i * sub
			var idx := j * k + i
			verts[idx] = Vector3(origin.x + i * sub * step, hh[src], origin.y + j * sub * step)
			norms[idx] = nn[src]
			cols[idx] = cc[src]
	# юбки: копии краевых вершин, опущенные вниз
	var edges: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array(), PackedInt32Array(), PackedInt32Array()]
	for e in 4:
		for t in k:
			var src_i: int
			match e:
				0: src_i = t                    # z = 0
				1: src_i = (k - 1) * k + t      # z = max
				2: src_i = t * k                # x = 0
				_: src_i = t * k + k - 1        # x = max
			var dst := k * k + e * k + t
			verts[dst] = verts[src_i] - Vector3(0.0, skirt, 0.0)
			norms[dst] = norms[src_i]
			cols[dst] = cols[src_i]
			edges[e].append(src_i)
	var idxs := PackedInt32Array()
	idxs.resize(q * q * 6 + 4 * q * 12)
	var w := 0
	for j in q:
		for i in q:
			var a := j * k + i
			var b := a + 1
			var c := a + k
			var d := c + 1
			if DIAG_MAIN:
				idxs[w] = a; idxs[w + 1] = b; idxs[w + 2] = d
				idxs[w + 3] = a; idxs[w + 4] = d; idxs[w + 5] = c
			else:
				idxs[w] = a; idxs[w + 1] = b; idxs[w + 2] = c
				idxs[w + 3] = b; idxs[w + 4] = d; idxs[w + 5] = c
			w += 6
	for e in 4:
		for t in q:
			var t0 := edges[e][t]
			var t1 := edges[e][t + 1]
			var s0 := k * k + e * k + t
			var s1 := s0 + 1
			# обе стороны (юбка видна с любой стороны шва)
			idxs[w] = t0; idxs[w + 1] = s0; idxs[w + 2] = t1
			idxs[w + 3] = t1; idxs[w + 4] = s0; idxs[w + 5] = s1
			idxs[w + 6] = t0; idxs[w + 7] = t1; idxs[w + 8] = s0
			idxs[w + 9] = t1; idxs[w + 10] = s1; idxs[w + 11] = s0
			w += 12
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idxs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh

func _make_collision(data: Dictionary, key: Vector2i) -> void:
	var n: int = data.n
	var step: float = data.step
	var origin: Vector2 = data.origin
	var body := StaticBody3D.new()
	body.name = "C_%d_%d" % [key.x, key.y]
	body.add_to_group(&"terrain")
	var hm := HeightMapShape3D.new()
	hm.map_width = n
	hm.map_depth = n
	hm.map_data = data.h
	var cs := CollisionShape3D.new()
	cs.shape = hm
	cs.scale = Vector3(step, 1.0, step)
	body.add_child(cs)
	body.position = Vector3(origin.x + CHUNK * 0.5, 0.0, origin.y + CHUNK * 0.5)
	add_child(body)

## Высота точно по треугольникам меша/коллизии; вне карты — аналитическая.
func height_at(x: float, z: float) -> float:
	var key := Vector2i(int(floor(x / CHUNK)), int(floor(z / CHUNK)))
	if not _chunks.has(key):
		return arch.height(x, z)
	var data: Dictionary = _chunks[key]
	var step: float = data.step
	var n: int = data.n
	var origin: Vector2 = data.origin
	var fx := (x - origin.x) / step
	var fz := (z - origin.y) / step
	var i := clampi(int(floor(fx)), 0, n - 2)
	var j := clampi(int(floor(fz)), 0, n - 2)
	var u := clampf(fx - i, 0.0, 1.0)
	var v := clampf(fz - j, 0.0, 1.0)
	var hh: PackedFloat32Array = data.h
	var h00 := hh[j * n + i]
	var h10 := hh[j * n + i + 1]
	var h01 := hh[(j + 1) * n + i]
	var h11 := hh[(j + 1) * n + i + 1]
	if DIAG_MAIN:
		if u >= v:
			return h00 + (h10 - h00) * u + (h11 - h10) * v
		return h00 + (h11 - h01) * u + (h01 - h00) * v
	if u + v <= 1.0:
		return h00 + (h10 - h00) * u + (h01 - h00) * v
	return h11 + (h01 - h11) * (1.0 - u) + (h10 - h11) * (1.0 - v)

func normal_at(x: float, z: float) -> Vector3:
	var e := 0.5
	var hl := height_at(x - e, z)
	var hr := height_at(x + e, z)
	var hd := height_at(x, z - e)
	var hu := height_at(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()

## Оценка треугольников, видимых с точки (по дальности LOD, без фрустума).
func tris_in_range(cam: Vector3) -> int:
	var total := 0
	var p := Vector2(cam.x, cam.z)
	for key: Vector2i in _chunks:
		var data: Dictionary = _chunks[key]
		var c := (data.origin as Vector2) + Vector2(CHUNK, CHUNK) * 0.5
		var d := Vector3(c.x - p.x, -cam.y, c.y - p.y).length()
		if d > FAR:
			continue
		if float(data.step) < COARSE - 0.1:
			var n := int(data.n)
			var sub := 1 if d < LOD1 else (2 if d < LOD2 else (4 if d < LOD3 else 8))
			if n < 65:
				sub = maxi(1, sub / 2)
			total += _tri_count(n, sub)
		else:
			total += _tri_count(int(data.n), 1)
	return total
