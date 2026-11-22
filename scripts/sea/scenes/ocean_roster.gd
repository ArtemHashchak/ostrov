class_name OceanRoster
extends RefCounted
## Океанский состав для сцен моря: все виды «богатого океана» как данные
## (assets/sea_scenes/ocean_roster.json) — размер, стая, среда, глубина, рацион, время
## активности, поведение и СЛОТ МОДЕЛИ. Пока у вида нет своей модели, его играет «дублёр»:
##   pack       — модель из пака пользователя (id вида пака) с подкраской tint и вытяжкой stretch;
##   proxy      — простой силуэт (SeaProxyMeshes) с цветами colors;
##   crab       — краб фауны (модель пользователя) в масштабе;
##   shark_ai   — настоящая акула моря (Sea.spawn_shark: ИИ, клипы большой белой);
##   school_mesh — стая на видеокарте (SeaSchool) из модели пака;
##   bird       — птицы фауны;
##   skel       — модель со скелетом и клипами автора (SeaSkel): слот "skel:<id>[,<id>…]" — варианты вида;
##   school_mesh с "vat" — стая из модели автора с запечёнными в текстуру клипами (слот "school:<id>").
## Слот «model»: id вида пака ("octopus_user"), путь к .res/.glb с разметкой вершин
## (tools/folder_anim/build_rig_mesh.gd), "shark_ai:white", "fauna:crab" — тогда дублёр не нужен.

const PATH := "res://assets/sea_scenes/ocean_roster.json"

static var _data: Dictionary = {}
static var _by_id: Dictionary = {}
static var _plants: Dictionary = {}

static func _load() -> void:
	if not _data.is_empty():
		return
	var txt := FileAccess.get_file_as_string(PATH) if FileAccess.file_exists(PATH) else ""
	var v: Variant = JSON.parse_string(txt) if txt != "" else null
	_data = v if v is Dictionary else {"species": [], "plants": []}
	for d: Variant in _data.get("species", []):
		_by_id[String((d as Dictionary).get("id", ""))] = d
	for d: Variant in _data.get("plants", []):
		_plants[String((d as Dictionary).get("id", ""))] = d

static func reload() -> void:
	_data = {}
	_by_id = {}
	_plants = {}
	_load()

static func species(id: String) -> Dictionary:
	_load()
	return _by_id.get(id, {})

static func plant(id: String) -> Dictionary:
	_load()
	return _plants.get(id, {})

static func all_species() -> Array:
	_load()
	return _data.get("species", [])

static func all_plants() -> Array:
	_load()
	return _data.get("plants", [])

## Запись вида пака пользователя по id ("discus_user").
static func pack_entry(pack_id: String) -> Dictionary:
	for d: Dictionary in UserSeaPack.species_list():
		if String(d.get("id", "")) == pack_id:
			return d
	return {}

## Чем вид представлен сейчас: {"kind": "pack"|"skel"|"proxy"|"crab"|"shark_ai"|"school_mesh"|"bird", ...}.
## Сначала — слот «model» (настоящая модель), иначе — дублёр.
static func visual(sp: Dictionary) -> Dictionary:
	var model := String(sp.get("model", ""))
	var si: Dictionary = sp.get("stand_in", {})
	if model != "":
		if model.begins_with("shark_ai:"):
			return {"kind": "shark_ai", "species": model.substr(9)}
		if model.begins_with("skel:"):
			var vs: Array = []
			for v in model.substr(5).split(",", false):
				if SeaSkel.has(v.strip_edges()):
					vs.append(v.strip_edges())
			if not vs.is_empty():
				return {"kind": "skel", "variants": vs, "len": float(sp.get("length", 0.4)), "real": true}
		if model.begins_with("school:"):
			var sid := model.substr(7)
			if SeaSchool.vat_available(sid):
				return {"kind": "school_mesh", "entry": {}, "vat": sid, "tint": String(si.get("vat_tint", "#ffffff")), "real": true}
		if model.begins_with("fauna:"):
			var f := model.substr(6)
			if f == "crab":
				return {"kind": "crab", "scale": float(si.get("crab", 1.0))}
			return {"kind": "bird", "species": f}
		var pe := pack_entry(model)
		if not pe.is_empty():
			return {"kind": "pack", "entry": pe, "real": true}
		if ResourceLoader.exists(model):
			var syn := {"id": String(sp.id) + "_model", "name": sp.get("name", ""), "mesh": model,
				"length": float(sp.get("length", 0.4)), "speed": float(sp.get("speed", 0.6)), "near": _near_kind(sp)}
			return {"kind": "pack", "entry": syn, "real": true}
	if si.has("pack"):
		var pe := pack_entry(String(si["pack"]))
		if not pe.is_empty():
			var e := pe.duplicate(true)
			e["id"] = "roster_" + String(sp.id)
			e["near"] = String(pe.get("near", UserSeaActor._kind_of(pe)))
			e["speed"] = float(sp.get("speed", pe.get("speed", 0.6)))
			var prm: Dictionary = (e.get("params", {}) as Dictionary).duplicate()
			if si.has("tint"):
				prm["tint"] = si["tint"]
			e["params"] = prm
			# модель остаётся своего размера (анимация считается в её единицах), узел масштабируется
			return {"kind": "pack", "entry": e, "stretch": float(si.get("stretch", 1.0)), "src_len": float(pe.get("length", 0.4)),
				"len": float(sp.get("length", pe.get("length", 0.4)))}
	if si.has("school_mesh"):
		var pe := pack_entry(String(si["school_mesh"]))
		return {"kind": "school_mesh", "entry": pe, "tint": String(si.get("tint", "#ffffff"))}
	if si.has("crab"):
		return {"kind": "crab", "scale": float(si["crab"]), "shell": bool(si.get("shell", false))}
	if si.has("shark_ai"):
		return {"kind": "shark_ai", "species": String(si["shark_ai"])}
	if si.has("bird"):
		return {"kind": "bird", "species": String(si["bird"])}
	return {"kind": "proxy", "proxy": String(si.get("proxy", "fish")), "colors": si.get("colors", ["#999999"])}

static func _near_kind(sp: Dictionary) -> String:
	return "octopus" if String(sp.get("group", "")) == "mollusc" else "fish"

## Подходит ли вид ко времени суток (day | night | dusk | any).
static func active_now(sp: Dictionary, night: bool, dusk: bool) -> bool:
	match String(sp.get("active", "any")):
		"day":
			return not night
		"night":
			return night or dusk
		"dusk":
			return dusk or night
	return true
