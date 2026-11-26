class_name AssetCatalog
extends RefCounted
## Каталог ассетов (A12, docs/V5_AGENTS.md «Контракты» п.1). Единый список «вид/предмет → модель»:
## все файлы assets/catalog/*.json (каждый агент пишет свой: flora.json, creatures.json, …).
## Формат файла: {"version": 1, "entries": [ {запись}, … ]}. Запись:
##   id, name, category (plant|tree|rock|ground|creature|sea|bird|insect|item|food|weapon|vehicle|character),
##   scene ("res://….glb|.tscn|.res" или "flora_pack:<id>" — меш FloraPack с материалами пака),
##   lod ([пути дальних LOD]), zones ([зоны карты зон]), size_m ([w,h,d], м), collision (none|soft|solid),
##   hitbox (capsule|box|mesh_simple) + shape ({type, radius, height, size, offset} — простая форма
##   для коллизии рядом с игроком; если нет — строится из size_m), density, cluster (0..1),
##   source (путь в KODAK/Остров/MODELS), license, climate_ok, tags.
## Для ground — tex: {albedo, normal, roughness, ao?, height?} (бесшовные, ≤2K).
##
## API: entries(), get_entry(id), by_category(cat), by_zone(zone, cat=""), instantiate(id, lod=0),
## shape(id) -> [Shape3D, Transform3D] | [], make_collider(id) -> CollisionObject3D | null.
## solid → StaticBody3D (слой 1, не пройти); soft → Area3D в группе "soft_plant" с мета "slow"
## (замедление игрока делает F, коллизии рядом с игроком создаёт C).

const DIR := "res://assets/catalog/"
const CATEGORIES := ["plant", "tree", "rock", "ground", "creature", "sea", "bird", "insect", "item", "food",
	"weapon", "vehicle", "character"]
const ZONES := ["jungle", "forest_edge", "beach", "dunes", "palm_belt", "lowland_forest", "rocks", "mangrove",
	"lagoon", "reef_crest", "reef_slope", "ocean", "cave"]
## Замедление в «мягких» растениях по умолчанию (множитель скорости игрока).
const SOFT_SLOW := 0.7

static var _entries: Dictionary = {}
static var _order: Array = []
static var _loaded := false
static var _scenes: Dictionary = {}

static func reload() -> void:
	_loaded = false
	_entries.clear()
	_order.clear()
	_scenes.clear()
	_load()

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var files := DirAccess.get_files_at(DIR) if DirAccess.dir_exists_absolute(DIR) else PackedStringArray()
	var names := Array(files)
	names.sort()
	for fn: String in names:
		if not fn.ends_with(".json"):
			continue
		var d = JSON.parse_string(FileAccess.get_file_as_string(DIR + fn))
		var arr: Array = []
		if d is Dictionary:
			arr = d.get("entries", [])
		elif d is Array:
			arr = d
		for e in arr:
			if e is Dictionary and e.has("id"):
				var id := String(e["id"])
				if not _entries.has(id):
					_order.append(id)
				var ee: Dictionary = e
				ee["_file"] = fn
				_entries[id] = ee

static func entries() -> Array:
	_load()
	var out: Array = []
	for id in _order:
		out.append(_entries[id])
	return out

static func get_entry(id: String) -> Dictionary:
	_load()
	return _entries.get(id, {})

static func has(id: String) -> bool:
	_load()
	return _entries.has(id)

static func by_category(cat: String) -> Array:
	var out: Array = []
	for e in entries():
		if String(e.get("category", "")) == cat:
			out.append(e)
	return out

static func by_zone(zone: String, cat: String = "") -> Array:
	var out: Array = []
	for e in entries():
		if (cat == "" or String(e.get("category", "")) == cat) and (e.get("zones", []) as Array).has(zone):
			out.append(e)
	return out

## Экземпляр модели (без коллизий). lod: 0 — ближний, 1+ — из списка "lod" (если есть).
static func instantiate(id: String, lod: int = 0) -> Node3D:
	var e := get_entry(id)
	if e.is_empty():
		return null
	var path := String(e.get("scene", ""))
	var lods: Array = e.get("lod", [])
	if lod > 0 and not lods.is_empty():
		path = String(lods[mini(lod - 1, lods.size() - 1)])
	if path.begins_with("flora_pack:"):
		var fid := path.substr(11)
		var m := FloraPack.mesh(fid, 2 if lod > 0 else 1)
		if m == null:
			return null
		var mi := MeshInstance3D.new()
		mi.name = id
		mi.mesh = m
		return mi
	if not ResourceLoader.exists(path):
		return null
	var res: Resource = _scenes.get(path)
	if res == null:
		res = load(path)
		_scenes[path] = res
	if res is PackedScene:
		var n := (res as PackedScene).instantiate() as Node3D
		if n:
			n.name = id
		return n
	if res is Mesh:
		var mi2 := MeshInstance3D.new()
		mi2.name = id
		mi2.mesh = res
		return mi2
	return null

## Простая форма коллизии: [Shape3D, Transform3D] (локально к модели) или [] для collision = none.
static func shape(id: String) -> Array:
	var e := get_entry(id)
	if e.is_empty() or String(e.get("collision", "none")) == "none":
		return []
	var sz: Array = e.get("size_m", [1.0, 1.0, 1.0])
	var s: Dictionary = e.get("shape", {})
	var typ := String(s.get("type", e.get("hitbox", "capsule")))
	var off: Array = s.get("offset", [0.0, 0.0, 0.0])
	var xf := Transform3D(Basis.IDENTITY, Vector3(float(off[0]), float(off[1]), float(off[2])))
	match typ:
		"box", "mesh_simple":
			var b := BoxShape3D.new()
			var bs: Array = s.get("size", sz)
			b.size = Vector3(float(bs[0]), float(bs[1]), float(bs[2]))
			if not s.has("offset"):
				xf.origin.y = b.size.y * 0.5
			return [b, xf]
		_:
			var c := CapsuleShape3D.new()
			var r := float(s.get("radius", clampf(minf(float(sz[0]), float(sz[2])) * 0.35, 0.06, 2.5)))
			var h := float(s.get("height", maxf(float(sz[1]), r * 2.0 + 0.01)))
			c.radius = r
			c.height = maxf(h, r * 2.0 + 0.01)
			if not s.has("offset"):
				xf.origin.y = c.height * 0.5
			return [c, xf]

## Коллайдер для экземпляра (позицию/поворот/масштаб ставит вызывающий).
static func make_collider(id: String) -> CollisionObject3D:
	var sh := shape(id)
	if sh.is_empty():
		return null
	var e := get_entry(id)
	var cs := CollisionShape3D.new()
	cs.shape = sh[0]
	cs.transform = sh[1]
	var obj: CollisionObject3D
	if String(e.get("collision")) == "solid":
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		obj = sb
	else:
		var ar := Area3D.new()
		ar.collision_layer = 0
		ar.collision_mask = 1
		ar.monitorable = false
		ar.add_to_group(&"soft_plant")
		ar.set_meta(&"slow", float(e.get("slow", SOFT_SLOW)))
		ar.set_meta(&"speed_mul", float(e.get("slow", SOFT_SLOW)))   # контракт F: BrushSensor читает speed_mul
		obj = ar
	obj.name = "Col_" + id
	obj.set_meta(&"catalog_id", id)
	obj.add_child(cs)
	return obj
