class_name SeaBounds
extends RefCounted
## Где морской особи можно быть (v5.1, агент I): только в открытом море (маска моря ZoneMap —
## вода, что дотекает от края карты; отрезанные низины суши не годятся) и только там, где при
## самом низком отливе хватает глубины на её тело. Проверка тела — центр, морда, хвост и бока,
## чтобы крупные (групер, манта, кит) не залезали носом или хвостом на берег.
## Без карты зон (старые миры) — по глубине Sea.depth_at.

static func zones(sea: Object) -> ZoneMap:
	if sea == null:
		return null
	var w: Variant = sea.get(&"world")
	if w is Node and is_instance_valid(w):
		var z: Variant = (w as Node).get(&"zones")
		if z is ZoneMap:
			return z
	return null

## Глубина при самом низком отливе (с картой зон) или сейчас (без неё); вне моря — < 0.
static func depth(sea: Object, x: float, z: float) -> float:
	var zm := zones(sea)
	if zm != null:
		if not zm.is_sea(x, z):
			return -1.0
		var fl: float = float(sea.call(&"floor_at", x, z))
		return minf(ZoneMap.LOW_TIDE, float(sea.call(&"water_y"))) - fl
	return float(sea.call(&"depth_at", x, z)) if sea else 10.0

## Нужная глубина воды под особью длиной L (м).
static func need_depth(L: float) -> float:
	return clampf(L * 0.35 + 0.45, 0.6, 9.0)

static func water_ok(sea: Object, x: float, z: float, need: float) -> bool:
	return depth(sea, x, z) >= need

## Всё тело в воде: центр, морда, хвост и бока (fwd — направление морды).
static func body_ok(sea: Object, p: Vector3, fwd: Vector3, L: float, need: float = -1.0) -> bool:
	if need < 0.0:
		need = need_depth(L)
	var f := Vector3(fwd.x, 0.0, fwd.z)
	f = f.normalized() if f.length_squared() > 1e-6 else Vector3.FORWARD
	var s := f.cross(Vector3.UP) * L * 0.2
	var h := f * L * 0.55
	for q: Vector3 in [p, p + h, p - h, p + s, p - s]:
		if not water_ok(sea, q.x, q.z, need if q == p else need * 0.6):
			return false
	return true

## Петля маршрута группы (эллипс rx × rz вокруг c) целиком в воде нужной глубины.
static func ring_ok(sea: Object, c: Vector3, rx: float, rz: float, need: float, n: int = 12) -> bool:
	if not water_ok(sea, c.x, c.z, need):
		return false
	for i in n:
		var a := TAU * i / n
		if not water_ok(sea, c.x + cos(a) * rx, c.z + sin(a) * rz, need):
			return false
	return true

## Только открытый океан (для кита и пелагических гигантов).
static func deep_ocean(sea: Object, x: float, z: float) -> bool:
	var zm := zones(sea)
	if zm == null:
		return depth(sea, x, z) > 20.0
	return zm.is_sea(x, z) and zm.zone_at(x, z) == ZoneMap.Z_DEEP_OCEAN
