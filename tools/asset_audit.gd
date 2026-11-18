extends SceneTree
## Аудит ассетов под бюджеты производительности (см. ASSETS.md, «Бюджеты для
## своих моделей»). Проверяет модели (.glb/.gltf/.fbx/.obj/.blend) и
## текстуры в папке (по умолчанию res://assets):
##   - треугольники модели против бюджета категории (по имени папки/файла);
##   - число поверхностей (= вызовов отрисовки) и материалов;
##   - наличие LOD (импорт «Generate LODs») и теневых мешей;
##   - текстуры: размер > 2048, не степень двойки, без mipmaps, без VRAM-сжатия.
## Запуск:
##   godot --headless --path <проект> -s res://tools/asset_audit.gd -- [res://assets/mypack]
## Итог печатается и пишется в user://asset_audit.txt (OK / ВНИМАНИЕ / ПРЕВЫШЕНО).

## Бюджеты: категория → [треугольники LOD0, поверхностей, макс. текстура].
const BUDGETS := {
	"tree": [12000, 3, 2048],
	"palm": [12000, 3, 2048],
	"bush": [3000, 2, 1024],
	"plant": [1500, 2, 1024],
	"grass": [400, 1, 512],
	"rock": [4000, 1, 2048],
	"animal": [10000, 3, 2048],
	"character": [25000, 4, 2048],
	"structure": [3000, 2, 2048],
	"building": [20000, 4, 2048],
	"item": [2500, 2, 1024],
	"weapon": [6000, 2, 1024],
	"prop": [5000, 2, 1024],
	"ship": [40000, 6, 2048],
	"default": [8000, 3, 2048],
}
## Ключевые слова пути → категория.
const KEYWORDS := [
	["palm", "palm"], ["tree", "tree"], ["stump", "prop"], ["shrub", "bush"], ["bush", "bush"],
	["fern", "plant"], ["plant", "plant"], ["flower", "plant"], ["herb", "plant"], ["grass", "grass"],
	["rock", "rock"], ["boulder", "rock"], ["stone", "rock"], ["cliff", "rock"],
	["animal", "animal"], ["fauna", "animal"], ["shark", "animal"], ["fish", "animal"], ["boar", "animal"],
	["croc", "animal"], ["monkey", "animal"], ["crab", "animal"], ["turtle", "animal"], ["snake", "animal"],
	["character", "character"], ["player", "character"], ["bot", "character"], ["hand", "character"], ["arm", "character"],
	["wall", "structure"], ["log", "structure"], ["plank", "structure"], ["roof", "structure"], ["bridge", "structure"],
	["raft", "structure"], ["build", "structure"], ["hut", "building"], ["house", "building"], ["tower", "building"],
	["weapon", "weapon"], ["bow", "weapon"], ["spear", "weapon"], ["axe", "weapon"], ["gun", "weapon"], ["rifle", "weapon"],
	["item", "item"], ["food", "item"], ["bottle", "item"], ["tool", "item"],
	["ship", "ship"], ["boat", "ship"], ["wreck", "ship"],
	["barrel", "prop"], ["crate", "prop"], ["chest", "prop"], ["prop", "prop"],
]
const MODEL_EXT := ["glb", "gltf", "fbx", "obj", "blend"]
const TEX_EXT := ["png", "jpg", "jpeg", "webp", "tga", "exr", "hdr", "ktx", "dds"]

var _lines: PackedStringArray = []
var _warn := 0
var _over := 0

func _init() -> void:
	var root := "res://assets"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("res://"):
			root = a
	_out("Аудит ассетов: %s" % root)
	_out("Формат: [статус] путь — треугольники/бюджет, поверхности, LOD, текстуры")
	var files: PackedStringArray = []
	_walk(root, files)
	var models := 0
	var texs := 0
	for f in files:
		var ext := f.get_extension().to_lower()
		if ext in MODEL_EXT:
			_audit_model(f)
			models += 1
		elif ext in TEX_EXT:
			_audit_texture(f)
			texs += 1
	_out("")
	_out("Итого: моделей %d, текстур %d, предупреждений %d, превышений %d" % [models, texs, _warn, _over])
	var fa := FileAccess.open("user://asset_audit.txt", FileAccess.WRITE)
	if fa:
		fa.store_string("\n".join(_lines) + "\n")
	quit(1 if _over > 0 else 0)

func _out(s: String) -> void:
	print(s)
	_lines.append(s)

func _walk(dir: String, out: PackedStringArray) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if not f.ends_with(".import"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		if not sub.begins_with("."):
			_walk(dir.path_join(sub), out)

func _category(path: String) -> String:
	var p := path.to_lower()
	for kw: Array in KEYWORDS:
		if p.get_file().contains(kw[0]):
			return kw[1]
	for kw: Array in KEYWORDS:
		if p.contains(kw[0]):
			return kw[1]
	return "default"

func _import_params(path: String) -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(path + ".import") != OK:
		return {}
	var out := {}
	if cfg.has_section("params"):
		for k in cfg.get_section_keys("params"):
			out[k] = cfg.get_value("params", k)
	return out

func _audit_model(path: String) -> void:
	var res := load(path)
	var inst: Node = null
	if res is PackedScene:
		inst = (res as PackedScene).instantiate()
	elif res is Mesh:
		# OBJ импортируется как Mesh
		var mi := MeshInstance3D.new()
		mi.mesh = res as Mesh
		inst = mi
	else:
		_out("[ОШИБКА] %s — не загружается (нет импорта?)" % path)
		_warn += 1
		return
	var tris := 0
	var surfaces := 0
	var mats := {}
	var max_tex := 0
	var stack: Array[Node] = [inst]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D and (n as MeshInstance3D).mesh:
			var m := (n as MeshInstance3D).mesh
			for s in m.get_surface_count():
				surfaces += 1
				tris += _surface_tris(m, s)
				var mat := (n as MeshInstance3D).get_active_material(s)
				if mat:
					mats[mat] = true
					max_tex = maxi(max_tex, _material_tex_size(mat))
	inst.free()
	var cat := _category(path)
	var b: Array = BUDGETS[cat]
	var params := _import_params(path)
	var lods := bool(params.get("meshes/generate_lods", true))
	var shadow := bool(params.get("meshes/create_shadow_meshes", true))
	var status := "OK"
	var notes: PackedStringArray = []
	if tris > int(b[0]) * 2:
		status = "ПРЕВЫШЕНО"
	elif tris > int(b[0]):
		status = "ВНИМАНИЕ"
	if surfaces > int(b[1]):
		notes.append("поверхностей %d > %d (объедините материалы/атлас)" % [surfaces, b[1]])
		if status == "OK": status = "ВНИМАНИЕ"
	if max_tex > int(b[2]):
		notes.append("текстура %d > %d" % [max_tex, b[2]])
		if status == "OK": status = "ВНИМАНИЕ"
	if not lods:
		notes.append("LOD выключены в импорте")
		if status == "OK": status = "ВНИМАНИЕ"
	if not shadow:
		notes.append("нет теневых мешей")
	if status == "ВНИМАНИЕ": _warn += 1
	if status == "ПРЕВЫШЕНО": _over += 1
	_out("[%s] %s — %s: %d/%d треуг., поверхностей %d, материалов %d, текстуры до %d px%s" % [
		status, path, cat, tris, b[0], surfaces, mats.size(), max_tex,
		("; " + "; ".join(notes)) if not notes.is_empty() else ""])

func _surface_tris(m: Mesh, s: int) -> int:
	if m is ArrayMesh:
		var am := m as ArrayMesh
		var fmt := am.surface_get_format(s)
		if fmt & Mesh.ARRAY_FORMAT_INDEX:
			return am.surface_get_array_index_len(s) / 3
		return am.surface_get_array_len(s) / 3
	var arr := m.surface_get_arrays(s)
	var idx: Variant = arr[Mesh.ARRAY_INDEX]
	if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
		return (idx as PackedInt32Array).size() / 3
	return (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3

func _material_tex_size(mat: Material) -> int:
	var mx := 0
	if mat is BaseMaterial3D:
		var bm := mat as BaseMaterial3D
		for slot in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_ORM,
				BaseMaterial3D.TEXTURE_ROUGHNESS, BaseMaterial3D.TEXTURE_METALLIC, BaseMaterial3D.TEXTURE_EMISSION]:
			var t := bm.get_texture(slot)
			if t:
				mx = maxi(mx, maxi(t.get_width(), t.get_height()))
	return mx

func _audit_texture(path: String) -> void:
	var t := load(path) as Texture2D
	if t == null:
		return
	var w := t.get_width()
	var h := t.get_height()
	var params := _import_params(path)
	var notes: PackedStringArray = []
	var status := "OK"
	if maxi(w, h) > 4096:
		status = "ПРЕВЫШЕНО"
		notes.append("больше 4096")
	elif maxi(w, h) > 2048:
		status = "ВНИМАНИЕ"
		notes.append("больше 2048 — только для крупных объектов")
	if not (_pow2(w) and _pow2(h)) and not path.contains("/ui/") and not path.get_extension() in ["hdr", "exr"]:
		notes.append("не степень двойки")
		if status == "OK": status = "ВНИМАНИЕ"
	var mode := int(params.get("compress/mode", -1))
	var detect := int(params.get("detect_3d/compress_to", 0))
	if mode == 0 and detect == 0 and not path.contains("/ui/"):
		notes.append("без VRAM-сжатия (Lossless): в 3D включите VRAM Compressed")
		if status == "OK": status = "ВНИМАНИЕ"
	if params.has("mipmaps/generate") and not bool(params["mipmaps/generate"]) and mode == 2:
		notes.append("без mipmaps")
		if status == "OK": status = "ВНИМАНИЕ"
	if status == "OK":
		return # текстуры без замечаний не печатаем
	if status == "ВНИМАНИЕ": _warn += 1
	if status == "ПРЕВЫШЕНО": _over += 1
	_out("[%s] %s — %dx%d; %s" % [status, path, w, h, "; ".join(notes)])

func _pow2(x: int) -> bool:
	return x > 0 and (x & (x - 1)) == 0
