class_name PolygonArch
extends Archipelago
## Рельеф нового полигона: один «остров»-музей — ровный прямоугольник высотой
## GROUND_H (никаких холмов), по северу/западу/востоку — короткий пляж и обрыв в море,
## по югу — мелководная полка (≈4.6 м) под пирс с аквариумами и морские вольеры,
## дальше — обычная глубина. Размер берётся из PolygonLayout (растёт с числом моделей).

var lay: Dictionary
var hw := 140.0
var z0 := 0.0
var zc := 300.0
var shelf_end := 400.0
var gh := PolygonLayout.GROUND_H

func _layout(_seed_value: int) -> void:
	islands.clear()
	bars.clear()
	islets.clear()
	lakes.clear()
	routes.clear()
	wreck_spots.clear()
	lay = PolygonLayout.get_layout()
	hw = float(lay.hw)
	z0 = float(lay.z0)
	zc = float(lay.coast)
	shelf_end = float(lay.shelf_end)
	gh = float(lay.ground_h)
	var c := Vector2(0.0, (z0 + shelf_end) * 0.5)
	var half := Vector2(hw + 60.0, (shelf_end - z0) * 0.5 + 60.0)
	var I := {"id": 0, "kind": &"museum", "team": 0, "center": c, "radius": half.length() / 2.3 + 10.0,
		"max_h": gh, "cliff_dir": -1.0, "lagoon_dir": -1.0, "beach_w": 0.0, "name": "Полигон", "angle": 0.0}
	islands.append(I)
	bounds = Rect2(Vector2(-hw - 90.0, z0 - 90.0), Vector2(hw * 2.0 + 180.0, shelf_end - z0 + 180.0))

## Расстояние от точки до прямоугольника музея (0 внутри) и до берега внутрь.
func _rect_d(p: Vector2) -> Vector2:
	var dx := maxf(absf(p.x) - hw, 0.0)
	var dz := maxf(maxf(z0 - p.y, p.y - zc), 0.0)
	var outside := Vector2(dx, dz).length()
	var inside := minf(minf(hw - absf(p.x), p.y - z0), zc - p.y)
	return Vector2(outside, inside)

func _island_h(I: Dictionary, p: Vector2) -> float:
	if I.kind != &"museum":
		return super._island_h(I, p)
	var d := _rect_d(p)
	if d.x <= 0.0:
		# внутри: ровно; у края — полоса пляжа 8 м
		var edge := smoothstep(0.0, 8.0, d.y)
		return lerpf(1.0, gh, edge)
	# юг: мелководная полка под пирс и вольеры
	var on_shelf := absf(p.x) <= hw + 20.0 and p.y > zc and p.y < shelf_end + 40.0
	var beach := lerpf(1.0, -0.6, smoothstep(0.0, 6.0, d.x))
	var deep := lerpf(-0.6, SEA_FLOOR, smoothstep(6.0, 46.0, d.x))
	var h := beach if d.x < 6.0 else deep
	if on_shelf:
		var dz := p.y - zc
		var shelf := lerpf(1.0, PolygonLayout.SHELF_DEPTH, smoothstep(0.0, 14.0, dz))
		var off := maxf(p.y - shelf_end, 0.0) + maxf(absf(p.x) - hw, 0.0)
		shelf = lerpf(shelf, SEA_FLOOR, smoothstep(0.0, 40.0, off))
		h = maxf(h, shelf) if d.x < 6.0 else shelf
	return h

func island_at(p: Vector2) -> Dictionary:
	if islands.is_empty():
		return {"island": {}, "d": 1e9}
	var d := _rect_d(p)
	# «доля радиуса»: <1 — суша, >1 — море (как у круглых островов)
	var span := minf(hw, (zc - z0) * 0.5)
	var dd := 1.0 - d.y / span if d.x <= 0.0 else 1.0 + d.x / span
	return {"island": islands[0], "d": dd}

func biome_weights(x: float, z: float, h: float) -> Color:
	# ровная трава (r — джунгли, g — болото, b — скалы, a — тёмный камень): всё 0
	return Color(0, 0, 0, 0)

func beach_point(I: Dictionary, a: float) -> Vector2:
	return Vector2(cos(a), sin(a)) * hw
