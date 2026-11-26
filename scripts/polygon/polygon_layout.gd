class_name PolygonLayout
extends RefCounted
## Раскладка нового полигона: ровный «музей» — прямоугольник одной высоты,
## разделы — полосы с севера на юг (z растёт к югу), «Море» — у южного берега:
## пирс с подводными аквариумами и сетчатые вольеры в воде.
## В каждой полосе: табличка раздела → ряды стендов (модель неподвижна, подпись) →
## «живые» участки (вольеры, вольеры-птичники, террариумы, грядки, рощи).
## Всё считается из списка экспонатов (PolygonExhibits), поэтому размер музея растёт сам.

const HW := 140.0               # полуширина музея по X
const MARGIN := 14.0            # от края музея до первых стендов
const GROUND_H := 2.2           # высота ровной площадки над уровнем моря
const HUB_DEPTH := 34.0
const BAND_GAP := 12.0
const TITLE_D := 9.0
const RANGE_D := 118.0          # стрельбище: мишени до 100 м
const SHELF_DEPTH := -4.6       # глубина мелководья у пирса и вольеров
const PIER_TANK_STEP := 5.0
const SEA_PEN_R := 8.0

## Размер «живого» участка раздела (сторона квадрата, м).
const PLOT := {&"animals": 20.0, &"birds": 17.0, &"small": 8.0, &"plants": 8.0, &"trees": 16.0, &"rocks": 7.0}

static var _cache: Dictionary = {}

static func reset() -> void:
	_cache = {}

static func get_layout() -> Dictionary:
	if _cache.is_empty():
		_cache = compute(PolygonExhibits.all())
	return _cache

static func compute(exhibits: Array) -> Dictionary:
	var by_sec := {}
	for s: Dictionary in PolygonExhibits.SECTIONS:
		by_sec[s.id] = []
	for e: Dictionary in exhibits:
		if by_sec.has(e.section):
			(by_sec[e.section] as Array).append(e)
	var z := 0.0
	var hub := Vector2(0.0, HUB_DEPTH * 0.5)
	z += HUB_DEPTH
	var sections: Array = []
	for s: Dictionary in PolygonExhibits.SECTIONS:
		if s.id == &"sea":
			continue
		var list: Array = by_sec[s.id]
		var sec := {"id": s.id, "name": s.name, "z0": z, "stands": [], "plots": [], "tables": [], "count": list.size()}
		var cz := z + TITLE_D
		sec["title"] = Vector2(-HW + MARGIN, z + 4.0)
		match s.id:
			&"items", &"weapons":
				# предметы — на столах (8 на стол 4 м), модели каталога — на стендах
				var on_tables := list.filter(func(e: Dictionary) -> bool: return e.src == "item")
				var stands := list.filter(func(e: Dictionary) -> bool: return e.src != "item")
				cz = _stand_rows(sec, stands, cz)
				cz = _tables(sec, on_tables, cz)
				if s.id == &"weapons":
					sec["range"] = Vector2(0.0, cz + 3.0)
					cz += RANGE_D
			&"buildings":
				cz = _plots(sec, list, cz, 10.0)
				sec["house"] = Vector2(-HW + MARGIN + 8.0, cz + 8.0)
				cz += 18.0
			_:
				cz = _stand_rows(sec, list, cz)
				if PLOT.has(s.id):
					var live := list.filter(func(e: Dictionary) -> bool: return bool(e.get("live", false)) and not bool(e.get("ground", false)))
					cz = _plots(sec, live, cz + 4.0, float(PLOT[s.id]))
		sec["z1"] = cz + 4.0
		z = cz + BAND_GAP
		sections.append(sec)
	# море: берег, пирс с аквариумами по обе стороны, вольеры-сетки за концом пирса
	var zc := z + 6.0
	var sea_list: Array = by_sec[&"sea"]
	var per_side := ceili(sea_list.size() / 2.0)
	var pier_len := maxf(30.0, per_side * PIER_TANK_STEP + 12.0)
	var sea := {"id": &"sea", "name": "Море", "z0": z, "stands": [], "plots": [], "tables": [], "count": sea_list.size(),
		"title": Vector2(-12.0, zc - 8.0), "pier_start": Vector2(0.0, zc - 3.0), "pier_len": pier_len}
	for i in sea_list.size():
		var side := -1.0 if i % 2 == 0 else 1.0
		var k := i / 2
		(sea.stands as Array).append({"ex": sea_list[i], "pos": Vector2(side * 4.6, zc + 6.0 + k * PIER_TANK_STEP)})
	var live_sea := sea_list.filter(func(e: Dictionary) -> bool: return bool(e.get("live", false)))
	var cols := 9
	for i in live_sea.size():
		var c := i % cols
		var r := i / cols
		var px := (c - (cols - 1) * 0.5) * (SEA_PEN_R * 2.0 + 3.0)
		var pz := zc + pier_len + 14.0 + r * (SEA_PEN_R * 2.0 + 3.0)
		(sea.plots as Array).append({"ex": live_sea[i], "pos": Vector2(px, pz), "size": SEA_PEN_R * 2.0})
	var rows := ceili(live_sea.size() / float(cols))
	var shelf_end := zc + pier_len + 14.0 + rows * (SEA_PEN_R * 2.0 + 3.0) + 10.0
	sea["z1"] = shelf_end
	sea["coast"] = zc
	sections.append(sea)
	return {"hw": HW, "z0": 0.0, "coast": zc, "shelf_end": shelf_end, "hub": hub, "sections": sections,
		"ground_h": GROUND_H}

## Ряды стендов: шаг по X — по ширине модели, глубина ряда — по самой глубокой.
static func _stand_rows(sec: Dictionary, list: Array, cz: float) -> float:
	var x := -HW + MARGIN
	var row_d := 0.0
	var row: Array = []
	for e: Dictionary in list:
		var sz: Vector3 = e.size
		var w := clampf(maxf(sz.x, sz.z) + 2.2, 3.0, 14.0)
		if x + w > HW - MARGIN and not row.is_empty():
			cz += row_d + 2.5
			x = -HW + MARGIN
			row_d = 0.0
			row.clear()
		var d := clampf(maxf(sz.x, sz.z) + 2.0, 3.0, 14.0)
		row_d = maxf(row_d, d)
		var st := {"ex": e, "pos": Vector2(x + w * 0.5, cz + d * 0.5), "w": w}
		(sec.stands as Array).append(st)
		row.append(st)
		x += w
	# выровнять ряд по глубине (центры на одной линии)
	if not list.is_empty():
		cz += row_d + 2.5
	return cz

static func _plots(sec: Dictionary, list: Array, cz: float, size: float) -> float:
	if list.is_empty():
		return cz
	var step := size + 3.0
	var cols := maxi(1, int((HW * 2.0 - MARGIN * 2.0) / step))
	for i in list.size():
		var c := i % cols
		var r := i / cols
		var px := -HW + MARGIN + step * 0.5 + c * step
		var pz := cz + step * 0.5 + r * step
		var e: Dictionary = list[i]
		var s := size
		if sec.id == &"trees":
			var sz: Vector3 = e.size
			s = clampf(maxf(sz.x, sz.z) * 1.6, 10.0, size)
		(sec.plots as Array).append({"ex": e, "pos": Vector2(px, pz), "size": s})
	return cz + ceili(list.size() / float(cols)) * step

static func _tables(sec: Dictionary, list: Array, cz: float) -> float:
	if list.is_empty():
		return cz
	const PER := 8
	const TW := 4.0
	var step_x := TW + 2.5
	var cols := maxi(1, int((HW * 2.0 - MARGIN * 2.0) / step_x))
	var n := ceili(list.size() / float(PER))
	for ti in n:
		var c := ti % cols
		var r := ti / cols
		var px := -HW + MARGIN + step_x * 0.5 + c * step_x
		var pz := cz + 2.0 + r * 4.0
		(sec.tables as Array).append({"pos": Vector2(px, pz), "items": list.slice(ti * PER, mini(list.size(), (ti + 1) * PER))})
	return cz + 2.0 + ceili(n / float(cols)) * 4.0 + 2.0

## Раздел по точке (для подгрузки и меню); {} — вне разделов (центр).
static func section_at(z: float) -> Dictionary:
	for s: Dictionary in get_layout().sections:
		if z >= float(s.z0) - 2.0 and z <= float(s.z1) + 2.0:
			return s
	return {}

static func section(id: StringName) -> Dictionary:
	for s: Dictionary in get_layout().sections:
		if s.id == id:
			return s
	return {}
