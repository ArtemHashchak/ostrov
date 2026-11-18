class_name SandboxArch
extends Archipelago
## Раскладка «Полигона»: большой пологий остров с зонами, домашние островки
## команд 1–3 (у острова команды 1 — пролив под мост) и атолл с рифом.

const MAIN_R := 150.0
const BRIDGE_GAP := 42.0

func _layout(_seed_value: int) -> void:
	islands.clear()
	bars.clear()
	islets.clear()
	lakes.clear()
	routes.clear()
	wreck_spots.clear()
	# 0: главный остров (команда 0 — игрок). Невысокий, без утёсов и лагуны.
	var main := _add_island(&"home", 0, 0.0, 0.0, MAIN_R, 2.2, -1.0, -1.0, 0.09)
	main.name = "Полигон"
	# 1: остров команды 1 на востоке — через узкий пролив (мост).
	var east := _add_island(&"home", 1, 0.0, MAIN_R + BRIDGE_GAP + 58.0, 58.0, 4.0, -1.0, -1.0, 0.12)
	_fit_gap(main, east, BRIDGE_GAP)
	# 2, 3: островки команд 2 и 3 (юг, север) — для ботов.
	var south := _add_island(&"home", 2, 90.0, MAIN_R + 85.0 + 48.0, 48.0, 5.0, -1.0, -1.0, 0.12)
	_fit_gap(main, south, 85.0)
	var north := _add_island(&"home", 3, 270.0, MAIN_R + 85.0 + 48.0, 48.0, 5.0, -1.0, -1.0, 0.12)
	_fit_gap(main, north, 85.0)
	# 4: атолл на западе — риф, черепахи.
	var atoll := _add_island(&"atoll", -1, 180.0, MAIN_R + 75.0 + 46.0, 46.0, 2.1, -1.0, -1.0, 0.3)
	_fit_gap(main, atoll, 75.0)
	for I in [east, south, north, atoll]:
		routes.append({"a": main.id, "b": I.id, "gap": strait_gap(main, I)})
	# пресный пруд в зоне выживания
	lakes.append({"center": Vector2(-62.0, 86.0), "radius": 7.0, "level": 0.0, "island": main.id, "kind": &"pond"})
	# остов корабля у западного берега
	var wp := beach_point(main, deg_to_rad(150.0))
	wreck_spots.append({"pos": wp + Vector2.from_angle(deg_to_rad(150.0)) * 14.0, "yaw": 0.4, "sink": 1.6, "island": main.id})
	var bb := Rect2(Vector2.ZERO, Vector2.ZERO)
	for I in islands:
		var r := float(I.radius) * 1.6
		bb = bb.merge(Rect2((I.center as Vector2) - Vector2(r, r), Vector2(r, r) * 2.0))
	bounds = bb.grow(30.0)

## Подвинуть остров b вдоль линии центров, чтобы пролив до a был gap метров.
func _fit_gap(a: Dictionary, b: Dictionary, gap: float) -> void:
	for it in 30:
		var g := strait_gap(a, b)
		if absf(g - gap) < 0.5:
			return
		var dir := ((b.center as Vector2) - (a.center as Vector2)).normalized()
		b.center = (b.center as Vector2) + dir * (gap - g)
