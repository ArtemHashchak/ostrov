extends Node
## Поверхности, этап 1 (A3) — автозагрузка Surfaces. Материал под ногами → скорость,
## громкость шагов (для Perception), глубина следа (для SandTracks агента D).
##   Surfaces.at(pos) -> StringName (sand, wet_sand, dirt, mud, grass, forest, jungle, stone,
##                                    pebbles, coral, shallow_water, wood, metal, leaves_dry)
##   Surfaces.props(id) -> {speed, loud, track}
##   Surfaces.speed_mul_at(pos), loud_at(pos), track_at(pos)
## Источник: коллайдер под ногой (meta "surface" / группы, как GunFx.surface_of) или зона
## мира (World.zone_at / biome_at) → таблица assets/data/surfaces.json.

var _cache_pos := Vector3(INF, INF, INF)
var _cache_id: StringName = &"dirt"
var _cache_t := -1.0

func props(id: StringName) -> Dictionary:
	return (DataTables.get_value("surfaces", "surfaces", {}) as Dictionary).get(String(id), {"speed": 1.0, "loud": 0.4, "track": 0.5})

func at(pos: Vector3) -> StringName:
	var now := Time.get_ticks_msec() * 0.001
	if pos.distance_squared_to(_cache_pos) < 0.09 and now - _cache_t < 0.3:
		return _cache_id
	_cache_pos = pos
	_cache_t = now
	_cache_id = _compute(pos)
	return _cache_id

func _compute(pos: Vector3) -> StringName:
	var wl := BuildEnv.water_level()
	if pos.y < wl - 0.05:
		return &"shallow_water"
	var tree := get_tree()
	var vp := tree.root if tree else null
	if vp and vp.world_3d:
		var space := vp.world_3d.direct_space_state
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.3, pos + Vector3.DOWN * 0.6)
		var pl := tree.get_first_node_in_group(&"player")
		if pl is CollisionObject3D:
			q.exclude = [(pl as CollisionObject3D).get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and hit.collider is Node:
			var c := hit.collider as Node
			if not _is_terrain(c):
				var s := GunFx.surface_of(c, hit.position, hit.normal)
				match s:
					&"wood", &"metal", &"stone":
						return s
	var w := BuildEnv.world()
	var zone: StringName = &""
	if w and w.has_method(&"zone_at"):
		zone = w.call(&"zone_at", pos.x, pos.z)
	elif w and w.has_method(&"biome_at"):
		zone = w.call(&"biome_at", pos.x, pos.z)
	var map: Dictionary = DataTables.get_value("surfaces", "zone_to_surface", {})
	var sid := StringName(map.get(String(zone), "dirt"))
	if sid == &"sand" and pos.y < wl + 0.55:
		sid = &"wet_sand"
	if sid == &"sand" and w and w.has_method(&"wetness") and float(w.call(&"wetness")) > 0.6:
		sid = &"wet_sand"
	return sid

static func _is_terrain(c: Node) -> bool:
	var cur := c
	for i in 4:
		if cur == null:
			return false
		if cur.is_in_group(&"terrain"):
			return true
		cur = cur.get_parent()
	return false

## Множитель скорости ходьбы (мелководье не считаем — у игрока свой WADE_MUL).
func speed_mul_at(pos: Vector3) -> float:
	var s := at(pos)
	if s == &"shallow_water":
		return 1.0
	return float(props(s).get("speed", 1.0))

func loud_at(pos: Vector3) -> float:
	return float(props(at(pos)).get("loud", 0.4))

func track_at(pos: Vector3) -> float:
	return float(props(at(pos)).get("track", 0.5))
