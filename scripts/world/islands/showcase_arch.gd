class_name ShowcaseArch
extends IslandGen
## «Полигон островов»: по одному острову каждого типа в ряд вдоль оси X,
## между берегами ~GAP м открытого моря. Для оценки генератора островов
## будущего архипелага 3×3 км (раскладка матча не меняется).

const GAP := 330.0

## Порядок и параметры: [тип, радиус, высота, параметры, смещение по Z].
var ORDER: Array = [
	[&"volcanic", 230.0, 92.0, {"beach_w": 0.055, "coast_amp": 0.13, "stream_ang": deg_to_rad(95.0), "fall_r": 0.5}, 0.0],
	[&"atoll", 200.0, 2.0, {"coast_amp": 0.07, "ring_in": 0.62, "passes": [deg_to_rad(215.0), deg_to_rad(30.0)]}, 40.0],
	[&"karst", 140.0, 48.0, {"coast_amp": 0.22, "coves": [Vector3(deg_to_rad(250.0), 0.3, 0.3), Vector3(deg_to_rad(40.0), 0.22, 0.24)]}, -30.0],
	[&"mangrove", 180.0, 1.9, {"coast_amp": 0.26, "beach_w": 0.0}, 30.0],
	[&"cay", 70.0, 1.9, {"coast_amp": 0.06, "aspect": 2.6, "aspect_dir": 0.35}, -20.0],
	[&"islet", 48.0, 24.0, {"coast_amp": 0.2}, 25.0],
	[&"savanna", 170.0, 26.0, {"beach_w": 0.12, "windward_cliffs": 0.7}, -40.0],
	[&"coral", 110.0, 3.2, {"beach_w": 0.22, "reef_out": 1.6, "coast_amp": 0.1}, 20.0],
	[&"tombolo", 0.0, 0.0, {}, 0.0],
	[&"plateau", 160.0, 58.0, {"coast_amp": 0.12, "edge": 0.1}, -10.0],
]

## Витрины: {type, name, island_ids, center: Vector2, beach: Vector2, beach_look: Vector2, extent}
var showcase: Array[Dictionary] = []

func _layout(seed_value: int) -> void:
	islands.clear()
	bars.clear()
	islets.clear()
	lakes.clear()
	routes.clear()
	wreck_spots.clear()
	features.clear()
	showcase.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 17 + 3
	var cursor := 0.0
	for e: Array in ORDER:
		var type: StringName = e[0]
		if type == &"tombolo":
			cursor = _add_tombolo(cursor, rng)
			continue
		var R: float = e[1]
		var params: Dictionary = (e[3] as Dictionary).duplicate(true)
		var ext := R * (1.0 + float(params.get("coast_amp", 0.15)))
		if params.has("aspect"):
			ext *= float(params.aspect) * absf(cos(float(params.get("aspect_dir", 0.0)))) + 0.3
		var c := Vector2(cursor + ext, float(e[4]))
		var I := add_typed(type, c, R, float(e[2]), params)
		match type:
			&"volcanic":
				_volcanic_features(I, rng)
			&"karst":
				_karst_features(I)
			&"islet":
				_islet_features(I, rng)
			&"plateau":
				_plateau_features(I)
			&"coral":
				# остов судна на краю рифа
				wreck_spots.append({"pos": c + Vector2.from_angle(deg_to_rad(110.0)) * R * 1.5, "yaw": 0.8, "sink": 2.6, "island": I.id})
		var extent := ext
		if type == &"atoll" or type == &"coral":
			extent = R * 1.6
		showcase.append(_entry(type, [I], c, extent))
		cursor = c.x + ext + GAP
	var bb := Rect2((islands[0].center as Vector2), Vector2.ZERO)
	for I in islands:
		var r := float(I.radius) * maxf(float(I.get("aspect", 1.0)), 1.0) * 1.9
		bb = bb.merge(Rect2((I.center as Vector2) - Vector2(r, r), Vector2(r, r) * 2.0))
	bounds = bb.grow(40.0)

func _entry(type: StringName, isl: Array, c: Vector2, extent: float) -> Dictionary:
	var I0: Dictionary = isl[0]
	# вид с пляжа — с южной стороны (+Z), смотрим к центру острова
	var a := deg_to_rad(90.0)
	var beach := beach_point(I0, a)
	if type == &"karst":
		beach = beach_point(I0, ((I0.p as Dictionary).coves[0] as Vector3).x)
	elif type == &"plateau" or type == &"islet":
		beach = (I0.center as Vector2) + Vector2.from_angle(a) * float(I0.radius) * 1.45
	var ids: Array[int] = []
	for I: Dictionary in isl:
		ids.append(int(I.id))
	return {"type": type, "name": IslandGen.type_name(type), "island_ids": ids, "center": c,
		"beach": beach, "beach_look": c, "extent": extent}

# ------------------------------------------------------------ особенности

func _volcanic_features(I: Dictionary, rng: RandomNumberGenerator) -> void:
	var c: Vector2 = I.center
	var R: float = I.radius
	var P: Dictionary = I.p
	P["summit"] = Vector2(rng.randf_range(-12.0, 12.0), rng.randf_range(-12.0, 12.0))
	var sa: float = P.stream_ang
	var fall_r: float = P.fall_r
	var dir := Vector2.from_angle(sa)
	var side := Vector2(-dir.y, dir.x)
	# русло: от чаши под водопадом до моря, с меандрами
	var pts := PackedVector2Array()
	var n := 14
	for k in n + 1:
		var t := float(k) / float(n)
		var rr := lerpf(fall_r + 0.035, 1.03, t)
		var mea := sin(t * 9.0 + 1.3) * 9.0 * smoothstep(0.05, 0.3, t)
		pts.append(c + dir * _coast_r(I, sa) * rr + side * mea)
	P["stream_pts"] = pts
	# верхнее русло над уступом (питает водопад)
	var up := PackedVector2Array()
	for k in 6:
		var t := float(k) / 5.0
		up.append(c + dir * _coast_r(I, sa) * lerpf(fall_r - 0.2, fall_r - 0.005, t) + side * sin(t * 5.0) * 5.0)
	var top := c + dir * _coast_r(I, sa) * (fall_r - 0.005)
	var bottom := c + dir * _coast_r(I, sa) * (fall_r + 0.03)
	features.append({"type": &"stream", "island": I.id, "pts": up, "width": 3.5})
	features.append({"type": &"waterfall", "island": I.id, "top": top, "bottom": bottom, "width": 7.0, "sea": false})
	features.append({"type": &"stream", "island": I.id, "pts": pts, "width": 5.0})
	# озерцо под водопадом
	lakes.append({"center": bottom + dir * 9.0, "radius": 9.0, "level": 0.0, "island": I.id, "kind": &"pond"})

func _karst_features(I: Dictionary) -> void:
	var c: Vector2 = I.center
	for ga: float in [deg_to_rad(320.0), deg_to_rad(150.0)]:
		var R := _coast_r(I, ga)
		var dir := Vector2.from_angle(ga)
		features.append({"type": &"grotto", "island": I.id, "mouth": c + dir * R * 1.0, "inner": c + dir * R * 0.8,
			"width": 7.5, "height": 10.0})
	# кекуры (отдельные столбы) у берега
	for k in 4:
		var a := deg_to_rad(20.0 + k * 85.0)
		islets.append({"center": c + Vector2.from_angle(a) * _coast_r(I, a) * 1.18, "radius": 6.0 + k, "top": 14.0 + k * 4.0})

func _islet_features(I: Dictionary, rng: RandomNumberGenerator) -> void:
	var c: Vector2 = I.center
	features.append({"type": &"ledges", "island": I.id, "center": c, "radius": float(I.radius), "top": float(I.max_h)})
	for k in 3:
		var a := rng.randf() * TAU
		islets.append({"center": c + Vector2.from_angle(a) * float(I.radius) * rng.randf_range(1.45, 1.9),
			"radius": rng.randf_range(3.5, 6.0), "top": rng.randf_range(6.0, 13.0)})

func _plateau_features(I: Dictionary) -> void:
	var c: Vector2 = I.center
	var a := deg_to_rad(80.0)
	var dir := Vector2.from_angle(a)
	var side := Vector2(-dir.y, dir.x)
	var R := _coast_r(I, a)
	var pts := PackedVector2Array()
	for k in 9:
		var t := float(k) / 8.0
		pts.append(c + dir * R * lerpf(0.35, 0.99, t) + side * sin(t * 6.0) * 10.0)
	features.append({"type": &"stream", "island": I.id, "pts": pts, "width": 4.0})
	features.append({"type": &"waterfall", "island": I.id, "top": c + dir * R * 0.99 + side * sin(6.0) * 10.0,
		"bottom": c + dir * R * 1.05 + side * sin(6.0) * 10.0, "width": 6.0, "sea": true})

## Близнецы: два холмистых острова, соединённые песчаной косой (томболо).
func _add_tombolo(cursor: float, _rng: RandomNumberGenerator) -> float:
	var ra := 92.0
	var rb := 72.0
	var ca := Vector2(cursor + ra * 1.15, -25.0)
	var cb := ca + Vector2(ra + rb + 85.0, 45.0)
	var A := add_typed(&"tombolo", ca, ra, 30.0, {"beach_w": 0.1, "windward_cliffs": 0.4})
	var B := add_typed(&"tombolo", cb, rb, 21.0, {"beach_w": 0.12, "windward_cliffs": 0.5})
	var dir := (cb - ca).normalized()
	var side := Vector2(-dir.y, dir.x)
	var p0 := ca + dir * ra * 0.85
	var p1 := cb - dir * rb * 0.85
	var pts := PackedVector2Array()
	for k in 9:
		var t := float(k) / 8.0
		pts.append(p0.lerp(p1, t) + side * sin(t * PI) * 16.0)
	_add_bar(pts, 13.0, 1.05)
	var mid := (ca + cb) * 0.5
	var ext := (cb.x + rb * 1.15) - cursor
	showcase.append(_entry(&"tombolo", [A, B], mid, ext * 0.5))
	showcase[showcase.size() - 1]["beach"] = p0.lerp(p1, 0.5) + side * 16.0 + side * 10.0
	showcase[showcase.size() - 1]["beach_look"] = ca
	return cb.x + rb * 1.15 + GAP
