extends SceneTree
## Нормализация одной модели под бюджет «Островов» (см. ASSETS.md → «Бюджеты для своих моделей»).
## Запускается во ВРЕМЕННОМ проекте (tools/asset_normalize.py готовит его сам):
##   godot --headless -s res://asset_normalize.gd -- <spec.json>
## spec.json:
##   name        — имя результата (категория_имя), напр. "animal_shark_great_white"
##   category    — tree | bush | plant | rock | fish_small | animal_medium | animal_large | animal | item | structure | seaweed | coral
##   src         — res:// путь исходника (FBX/OBJ/GLB/DAE)
##   out         — абсолютный путь .glb
##   report      — абсолютный путь отчёта .json
##   size        — целевой размер в метрах (0 — не масштабировать), size_axis: "y" | "max"
##   rotate_y    — поворот вокруг Y в градусах (лицо модели должно смотреть в −Z)
##   tris        — бюджет треугольников LOD0 (0 — по категории)
##   tex         — максимальная сторона текстуры (0 — по категории)
##   materials   — { "часть имени материала": {albedo, normal, orm, alpha_scissor, cull_disabled, color} }
##   keep_anims  — список анимаций, которые оставить (пусто — все); rename_anims — {старое: новое}
##   drop_meshes — части имён мешей, которые выбросить
## Упрощение: ImporterMesh.generate_lods (meshoptimizer, сохраняет UV/нормали/кости и веса),
## берётся LOD с числом треугольников не больше доли бюджета, затем неиспользуемые вершины выкидываются.

const BUDGET := {
	"tree": [12000, 2048], "bush": [3000, 1024], "plant": [1500, 1024], "grass": [400, 512],
	"rock": [4000, 2048], "fish_small": [1500, 512], "animal_medium": [5000, 1024],
	"animal_large": [12000, 2048], "animal": [10000, 2048], "item": [2500, 1024],
	"weapon": [6000, 1024], "structure": [3000, 2048], "seaweed": [2000, 1024], "coral": [2000, 1024],
}
const MIN_PART_TRIS := 48

var spec: Dictionary
var report := {}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: -- <spec.json>")
		quit(2)
		return
	spec = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if spec == null:
		push_error("bad spec")
		quit(2)
		return
	var code := _run()
	var f := FileAccess.open(String(spec.get("report", "/tmp/asset_report.json")), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	quit(code)


func _run() -> int:
	var cat := String(spec.get("category", "animal"))
	var b: Array = BUDGET.get(cat, [10000, 2048])
	var budget := int(spec.get("tris", 0)) if int(spec.get("tris", 0)) > 0 else int(b[0])
	var tex_max := int(spec.get("tex", 0)) if int(spec.get("tex", 0)) > 0 else int(b[1])
	report = {"name": spec.get("name", ""), "category": cat, "budget_tris": budget, "tex_max": tex_max}
	var ps := load(String(spec["src"])) as PackedScene
	if ps == null:
		report["error"] = "cannot load"
		return 3
	var root := ps.instantiate() as Node3D
	# --- выбросить лишние меши
	for part in spec.get("drop_meshes", []):
		for mi in root.find_children("*" + String(part) + "*", "MeshInstance3D", true, false):
			mi.get_parent().remove_child(mi)
			mi.free()
	var mis: Array[MeshInstance3D] = []
	for n in root.find_children("*", "MeshInstance3D", true, false):
		if (n as MeshInstance3D).mesh != null:
			mis.append(n)
	# --- до: треугольники, площади, AABB
	var before_tris := 0
	var areas: Array[float] = []
	var aabb := AABB()
	var first := true
	for mi in mis:
		var xf := _xf_to_root(mi, root)
		var t := 0
		var area := 0.0
		for s in mi.mesh.get_surface_count():
			var a := mi.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
			if idx.is_empty():
				idx = _seq(v.size())
			t += idx.size() / 3
			for i in range(0, idx.size(), 3):
				area += ((v[idx[i + 1]] - v[idx[i]]).cross(v[idx[i + 2]] - v[idx[i]])).length() * 0.5
			var pts := _posed_points(mi, a, root)
			for p in (pts if not pts.is_empty() else v):
				var wp: Vector3 = p if not pts.is_empty() else xf * p
				if first:
					aabb = AABB(wp, Vector3.ZERO)
					first = false
				else:
					aabb = aabb.expand(wp)
		before_tris += t
		areas.append(sqrt(area) * sqrt(float(t)))   # важность части: площадь и плотность сетки
	report["before_tris"] = before_tris
	report["before_surfaces"] = _count_surfaces(mis)
	report["before_size"] = [aabb.size.x, aabb.size.y, aabb.size.z]
	# --- упрощение: бюджет делится по важности частей
	var total_w := 0.0
	for w in areas:
		total_w += w
	var after_tris := 0
	var parts := []
	for k in mis.size():
		var mi := mis[k]
		var tris_now := _tris(mi.mesh)
		var share := int(float(budget) * areas[k] / maxf(total_w, 0.0001))
		var target := clampi(share, MIN_PART_TRIS, tris_now)
		if before_tris <= budget:
			target = tris_now
		var skel := mi.get_node_or_null(mi.skeleton) as Skeleton3D if mi.skeleton != NodePath() else null
		var new_mesh := _decimate(mi.mesh, target, skel)
		mi.mesh = new_mesh
		var got := _tris(new_mesh)
		after_tris += got
		parts.append({"mesh": String(mi.name), "before": tris_now, "target": target, "after": got})
	report["parts"] = parts
	report["after_tris"] = after_tris
	# --- материалы и текстуры
	var tex_bytes := 0
	var mats_done := {}
	var by_key := {}
	for mi in mis:
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			var nm := m.resource_name if m else "surf%d" % s
			var key := _mat_key(nm)
			var sm: StandardMaterial3D
			if key != "" and by_key.has(key):
				sm = by_key[key]
			else:
				sm = _make_material(nm, m, tex_max)
				if key != "":
					sm.resource_name = key
					by_key[key] = sm
			mi.mesh.surface_set_material(s, sm)
			if not mats_done.has(sm.resource_name):
				mats_done[sm.resource_name] = true
				tex_bytes += _mat_tex_bytes(sm)
		mi.mesh = _merge_same_material(mi.mesh)
	report["materials"] = mats_done.keys()
	report["tex_mb_uncompressed"] = snappedf(float(tex_bytes) / 1048576.0, 0.01)
	report["tex_mb_vram_est"] = snappedf(float(tex_bytes) / 1048576.0 / 4.0 * 1.33, 0.01)  # BC/ETC ≈ 1/4 + mip
	# --- скелет
	var bones := 0
	for sk in root.find_children("*", "Skeleton3D", true, false):
		bones = maxi(bones, (sk as Skeleton3D).get_bone_count())
	report["bones"] = bones
	# --- анимации
	var keep: Array = spec.get("keep_anims", [])
	var ren: Dictionary = spec.get("rename_anims", {})
	var anims := []
	for ap in root.find_children("*", "AnimationPlayer", true, false):
		var p := ap as AnimationPlayer
		for lib_name in p.get_animation_library_list():
			var lib := p.get_animation_library(lib_name)
			for an in lib.get_animation_list():
				if not keep.is_empty() and not keep.has(String(an)):
					lib.remove_animation(an)
					continue
				var a := lib.get_animation(an)
				var dur := _anim_real_length(a)
				if dur > 0.0:
					a.length = dur
				if ren.has(String(an)):
					var a2 := a
					lib.remove_animation(an)
					lib.add_animation(StringName(ren[String(an)]), a2)
					an = StringName(ren[String(an)])
				anims.append({"name": String(an), "length": snappedf(a.length, 0.01)})
	report["animations"] = anims
	# --- масштаб и поворот (на корне; скелет и меши сохраняют свои локальные данные)
	var size := float(spec.get("size", 0.0))
	var sc := 1.0
	if size > 0.0:
		var ref := aabb.size.y if String(spec.get("size_axis", "max")) == "y" else maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
		sc = size / maxf(ref, 0.0001)
	var holder := Node3D.new()
	holder.name = String(spec.get("name", "model"))
	root.scale *= sc
	root.rotate_y(deg_to_rad(float(spec.get("rotate_y", 0.0))))
	# пивот: основание по Y (минимум) и центр по XZ — для деревьев/камней; для животных — центр
	var base_y := aabb.position.y
	var ctr := aabb.get_center()
	var piv := Vector3(ctr.x, base_y if cat in ["tree", "bush", "plant", "grass", "rock", "structure", "seaweed", "coral"] else ctr.y, ctr.z)
	root.position = -(root.basis * piv)
	holder.add_child(root)
	root.owner = holder
	_own(root, holder)
	report["scale"] = sc
	report["after_size"] = [aabb.size.x * sc, aabb.size.y * sc, aabb.size.z * sc]
	# --- экспорт
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_scene(holder, st)
	if err == OK:
		err = doc.write_to_filesystem(st, String(spec["out"]))
	report["export_err"] = err
	if FileAccess.file_exists(String(spec["out"])):
		report["glb_mb"] = snappedf(float(FileAccess.get_file_as_bytes(String(spec["out"])).size()) / 1048576.0, 0.01)
	report["after_surfaces"] = _count_surfaces(mis)
	holder.free()
	return 0 if err == OK else 4


func _own(n: Node, owner_node: Node) -> void:
	for c in n.get_children():
		c.owner = owner_node
		_own(c, owner_node)


func _xf_to_root(n: Node, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur := n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func _seq(n: int) -> PackedInt32Array:
	var r := PackedInt32Array()
	r.resize(n)
	for i in n:
		r[i] = i
	return r


func _tris(m: Mesh) -> int:
	var t := 0
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		t += (idx.size() if not idx.is_empty() else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return t


func _count_surfaces(mis: Array[MeshInstance3D]) -> int:
	var c := 0
	for mi in mis:
		c += mi.mesh.get_surface_count()
	return c


## Упростить меш до ~target треугольников (сумма по поверхностям, пропорционально).
func _decimate(src: Mesh, target: int, skel: Skeleton3D) -> ArrayMesh:
	var total := _tris(src)
	var out := ArrayMesh.new()
	out.resource_name = src.resource_name
	for s in src.get_surface_count():
		var arrays := src.surface_get_arrays(s)
		var fmt: int = src.surface_get_format(s)
		var mat := src.surface_get_material(s)
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if idx.is_empty():
			idx = _seq(v.size())
			arrays[Mesh.ARRAY_INDEX] = idx
		var surf_t := idx.size() / 3
		var surf_target := maxi(MIN_PART_TRIS / 2, int(float(target) * float(surf_t) / maxf(float(total), 1.0)))
		var best := idx
		var mname0 := mat.resource_name if mat else ""
		if _is_leaflet(mname0):
			var cards := _leaflet_cards(arrays)
			if (cards[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3 > surf_target:
				cards = _compact(cards, _thin_islands(cards[Mesh.ARRAY_INDEX], surf_target))
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, cards)
			out.surface_set_material(out.get_surface_count() - 1, mat)
			continue
		if surf_t > surf_target:
			var im := ImporterMesh.new()
			im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, mat, "", fmt & ~Mesh.ARRAY_FORMAT_INDEX & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
			var bones := []
			if skel:
				for bi in skel.get_bone_count():
					bones.append(skel.get_bone_global_rest(bi))
			im.generate_lods(25.0, 60.0, bones)
			for l in im.get_surface_lod_count(0):
				var li := im.get_surface_lod_indices(0, l)
				if li.size() / 3 <= surf_target:
					best = li
					break
				best = li   # самый грубый из доступных, если до цели не дошли
		var mname := mat.resource_name if mat else ""
		if best.size() / 3 > surf_target and _is_thin(mname):
			best = _thin_islands(best, surf_target)
		var compact := _compact(arrays, best)
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, compact, [], {}, fmt & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
		out.surface_set_material(out.get_surface_count() - 1, mat)
		out.surface_set_name(out.get_surface_count() - 1, src.surface_get_name(s) if src is ArrayMesh else "")
	return out


## Оставить только вершины, на которые ссылаются индексы.
func _compact(arrays: Array, idx: PackedInt32Array) -> Array:
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n := v.size()
	var remap := PackedInt32Array()
	remap.resize(n)
	remap.fill(-1)
	var order := PackedInt32Array()
	var new_idx := PackedInt32Array()
	new_idx.resize(idx.size())
	for i in idx.size():
		var o := idx[i]
		if remap[o] < 0:
			remap[o] = order.size()
			order.append(o)
		new_idx[i] = remap[o]
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for k in Mesh.ARRAY_MAX:
		var a = arrays[k]
		if a == null or k == Mesh.ARRAY_INDEX:
			continue
		var sz: int = a.size()
		if sz == 0:
			continue
		var stride := sz / n
		var na = a.duplicate()
		na.resize(order.size() * stride)
		for j in order.size():
			for c in stride:
				na[j * stride + c] = a[order[j] * stride + c]
		out[k] = na
	out[Mesh.ARRAY_INDEX] = new_idx
	return out


func _make_material(nm: String, m: Material, tex_max: int) -> StandardMaterial3D:
	var sm: StandardMaterial3D = (m.duplicate() as StandardMaterial3D) if m is StandardMaterial3D else StandardMaterial3D.new()
	sm.resource_name = nm
	var cfg := {}
	var mats: Dictionary = spec.get("materials", {})
	for key in mats:
		if nm.findn(String(key)) >= 0:
			cfg = mats[key]
			if cfg.has("same_as") and mats.has(cfg["same_as"]):
				cfg = mats[cfg["same_as"]]
			break
	if cfg.has("tex"):
		tex_max = int(cfg["tex"])
	if cfg.has("albedo"):
		sm.albedo_texture = _tex(String(cfg["albedo"]), tex_max)
		sm.albedo_color = Color.WHITE
	if cfg.has("color"):
		sm.albedo_color = Color(String(cfg["color"]))
	if cfg.has("normal"):
		sm.normal_enabled = true
		sm.normal_texture = _tex(String(cfg["normal"]), tex_max)
	if cfg.has("orm"):
		var orm := _tex(String(cfg["orm"]), tex_max)
		sm.ao_enabled = true
		sm.ao_texture = orm
		sm.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		sm.roughness_texture = orm
		sm.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		sm.roughness = 1.0
		sm.metallic_texture = orm
		sm.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
		sm.metallic = 1.0
	if cfg.has("roughness"):
		sm.roughness = float(cfg["roughness"])
	if bool(cfg.get("alpha_scissor", false)):
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		sm.alpha_scissor_threshold = 0.5
	elif sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR   # прозрачность — дорого, только scissor
	if bool(cfg.get("cull_disabled", false)):
		sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	# текстуры, пришедшие из исходника — тоже ужать
	for prop in ["albedo_texture", "normal_texture", "roughness_texture", "metallic_texture", "ao_texture"]:
		var t: Texture2D = sm.get(prop)
		if t != null and not (t is ImageTexture):
			var img := t.get_image()
			if img:
				sm.set(prop, _shrink(img, tex_max))
	return sm


func _tex(path: String, tex_max: int) -> Texture2D:
	var img := Image.load_from_file(path)
	if img == null:
		push_warning("no texture " + path)
		return null
	return _shrink(img, tex_max)


func _shrink(img: Image, tex_max: int) -> ImageTexture:
	if img.is_compressed():
		img.decompress()
	var w := img.get_width()
	var h := img.get_height()
	var k := minf(1.0, float(tex_max) / float(maxi(w, h)))
	if k < 1.0:
		img.resize(maxi(4, int(w * k)), maxi(4, int(h * k)), Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)


func _mat_tex_bytes(sm: StandardMaterial3D) -> int:
	var seen := {}
	var b := 0
	for prop in ["albedo_texture", "normal_texture", "roughness_texture", "metallic_texture", "ao_texture"]:
		var t: Texture2D = sm.get(prop)
		if t != null and not seen.has(t):
			seen[t] = true
			b += t.get_width() * t.get_height() * 4
	return b


## У FBX из Blender длина клипа часто стоит 1.0 — берём время последнего ключа.
func _anim_real_length(a: Animation) -> float:
	var mx := 0.0
	for t in a.get_track_count():
		var kc := a.track_get_key_count(t)
		if kc > 0:
			mx = maxf(mx, a.track_get_key_time(t, kc - 1))
	return mx


## Позиции вершин в позе покоя скелета (для скиннинга), в пространстве корня. Пусто — меш без скина.
func _posed_points(mi: MeshInstance3D, a: Array, root: Node) -> PackedVector3Array:
	var out := PackedVector3Array()
	if mi.skin == null or mi.skeleton == NodePath() or a[Mesh.ARRAY_BONES] == null:
		return out
	var sk := mi.get_node_or_null(mi.skeleton) as Skeleton3D
	if sk == null:
		return out
	var skin := mi.skin
	var sk_xf := _xf_to_root(sk, root)
	var mats: Array[Transform3D] = []
	for b in skin.get_bind_count():
		var bone := skin.get_bind_bone(b)
		if bone < 0:
			bone = sk.find_bone(skin.get_bind_name(b))
		mats.append(sk_xf * sk.get_bone_global_rest(maxi(bone, 0)) * skin.get_bind_pose(b))
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var bones = a[Mesh.ARRAY_BONES]
	var w = a[Mesh.ARRAY_WEIGHTS]
	var per: int = bones.size() / maxi(v.size(), 1)
	out.resize(v.size())
	for i in v.size():
		var acc := Vector3.ZERO
		var ws := 0.0
		for j in per:
			var wt: float = w[i * per + j]
			if wt <= 0.0:
				continue
			var bi: int = bones[i * per + j]
			if bi < mats.size():
				acc += (mats[bi] * v[i]) * wt
				ws += wt
		out[i] = acc / ws if ws > 0.0 else _xf_to_root(mi, root) * v[i]
	return out


func _mat_key(nm: String) -> String:
	var mats: Dictionary = spec.get("materials", {})
	for key in mats:
		if nm.findn(String(key)) >= 0:
			var c: Dictionary = mats[key]
			return String(c.get("same_as", key))
	return ""


func _is_thin(nm: String) -> bool:
	for k in spec.get("thin", []):
		if nm.findn(String(k)) >= 0:
			return true
	return false


## Прореживание листвы: убрать часть отдельных «островков» (листочков) равномерно, до target треугольников.
func _thin_islands(idx: PackedInt32Array, target: int) -> PackedInt32Array:
	var nv := 0
	for i in idx:
		nv = maxi(nv, i + 1)
	var parent := PackedInt32Array()
	parent.resize(nv)
	for i in nv:
		parent[i] = i
	for t in range(0, idx.size(), 3):
		var a := _find(parent, idx[t])
		for k in [1, 2]:
			var b := _find(parent, idx[t + k])
			if a != b:
				parent[b] = a
	var comp_tris := {}
	for t in range(0, idx.size(), 3):
		var c := _find(parent, idx[t])
		comp_tris[c] = int(comp_tris.get(c, 0)) + 1
	var total := idx.size() / 3
	var keep_ratio := float(target) / float(total)
	var acc := 0.0
	var keep := {}
	for c in comp_tris:
		acc += keep_ratio
		if acc >= 1.0:
			acc -= 1.0
			keep[c] = true
	var out := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		if keep.has(_find(parent, idx[t])):
			out.append(idx[t]); out.append(idx[t + 1]); out.append(idx[t + 2])
	return out if out.size() > 0 else idx


func _find(parent: PackedInt32Array, x: int) -> int:
	while parent[x] != x:
		parent[x] = parent[parent[x]]
		x = parent[x]
	return x


## Слить поверхности с одним и тем же материалом (меньше вызовов отрисовки).
func _merge_same_material(m: Mesh) -> ArrayMesh:
	var groups := {}
	var order := []
	for s in m.get_surface_count():
		var mat := m.surface_get_material(s)
		var fmt: int = m.surface_get_format(s)
		var key := [mat, fmt & (Mesh.ARRAY_FORMAT_NORMAL | Mesh.ARRAY_FORMAT_TANGENT | Mesh.ARRAY_FORMAT_COLOR | Mesh.ARRAY_FORMAT_TEX_UV | Mesh.ARRAY_FORMAT_TEX_UV2 | Mesh.ARRAY_FORMAT_BONES | Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)]
		var hk := str(mat.get_instance_id() if mat else 0) + ":" + str(key[1])
		if not groups.has(hk):
			groups[hk] = {"mat": mat, "fmt": fmt, "surfs": []}
			order.append(hk)
		groups[hk]["surfs"].append(s)
	if order.size() == m.get_surface_count():
		return m as ArrayMesh
	var out := ArrayMesh.new()
	for hk in order:
		var g: Dictionary = groups[hk]
		var merged := []
		merged.resize(Mesh.ARRAY_MAX)
		var base := 0
		for s in g["surfs"]:
			var a := m.surface_get_arrays(s)
			var nvtx := (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			for k in Mesh.ARRAY_MAX:
				if a[k] == null:
					continue
				if k == Mesh.ARRAY_INDEX:
					var ix: PackedInt32Array = a[k]
					var shifted := PackedInt32Array()
					shifted.resize(ix.size())
					for i in ix.size():
						shifted[i] = ix[i] + base
					merged[k] = shifted if merged[k] == null else merged[k] + shifted
				else:
					merged[k] = a[k] if merged[k] == null else merged[k] + a[k]
			base += nvtx
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, merged, [], {}, int(g["fmt"]) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
		out.surface_set_material(out.get_surface_count() - 1, g["mat"])
	return out


func _is_leaflet(nm: String) -> bool:
	for k in spec.get("leaflets", []):
		if nm.findn(String(k)) >= 0:
			return true
	return false


## Каждый листочек (связный островок) → ромб из 2 треугольников по его длине и ширине.
func _leaflet_cards(arrays: Array) -> Array:
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var nv := v.size()
	var parent := PackedInt32Array()
	parent.resize(nv)
	for i in nv:
		parent[i] = i
	for t in range(0, idx.size(), 3):
		var a := _find(parent, idx[t])
		for k in [1, 2]:
			var b := _find(parent, idx[t + k])
			if a != b:
				parent[b] = a
	var groups := {}
	for t in idx:
		var c := _find(parent, t)
		if not groups.has(c):
			groups[c] = {}
		groups[c][t] = true
	var isl_area := {}
	for t in range(0, idx.size(), 3):
		var cc := _find(parent, idx[t])
		isl_area[cc] = float(isl_area.get(cc, 0.0)) + ((v[idx[t + 1]] - v[idx[t]]).cross(v[idx[t + 2]] - v[idx[t]])).length() * 0.5
	var ov := PackedVector3Array()
	var on := PackedVector3Array()
	var ou := PackedVector2Array()
	var oi := PackedInt32Array()
	for c in groups:
		var verts: Array = groups[c].keys()
		if verts.size() < 3:
			continue
		var cen := Vector3.ZERO
		var nsum := Vector3.ZERO
		var uvmin := Vector2(INF, INF)
		var uvmax := Vector2(-INF, -INF)
		for vi in verts:
			cen += v[vi]
			if not nrm.is_empty():
				nsum += nrm[vi]
			if not uv.is_empty():
				uvmin = uvmin.min(uv[vi]); uvmax = uvmax.max(uv[vi])
		cen /= verts.size()
		var pa: Vector3 = v[verts[0]]
		var best := -1.0
		for vi in verts:
			var d := v[vi].distance_squared_to(cen)
			if d > best:
				best = d; pa = v[vi]
		var pb := pa
		best = -1.0
		for vi in verts:
			var d := v[vi].distance_squared_to(pa)
			if d > best:
				best = d; pb = v[vi]
		var axis := pb - pa
		var alen := axis.length()
		if alen < 1e-6:
			continue
		var ad := axis / alen
		var side := Vector3.ZERO
		var wmax := 0.0
		for vi in verts:
			var r := v[vi] - pa
			var perp := r - ad * r.dot(ad)
			var pl := perp.length()
			if pl > wmax:
				wmax = pl; side = perp / pl
		if wmax < 1e-6:
			side = ad.cross(Vector3.UP).normalized()
			wmax = alen * 0.08
		# ширина ромба — по площади листочка (у изогнутого листочка «размах» больше реальной ширины)
		var area: float = isl_area.get(c, 0.0)
		var w_area := 2.0 * area / alen
		if w_area > 0.0:
			wmax = minf(wmax, w_area * float(spec.get("leaflet_width", 1.0)))
		# середина ромба — центр листочка (у изогнутого листочка он вне оси — так сохраняется изгиб)
		var mid := cen
		var n := nsum.normalized() if nsum.length() > 0.0 else ad.cross(side).normalized()
		var b0 := ov.size()
		ov.append(pa); ov.append(mid + side * wmax * 0.5); ov.append(pb); ov.append(mid - side * wmax * 0.5)
		for k in 4:
			on.append(n)
		var um := (uvmin + uvmax) * 0.5 if uvmin.x != INF else Vector2.ZERO
		ou.append(Vector2(uvmin.x if uvmin.x != INF else 0.0, um.y)); ou.append(Vector2(um.x, uvmin.y if uvmin.y != INF else 0.0))
		ou.append(Vector2(uvmax.x if uvmax.x != -INF else 0.0, um.y)); ou.append(Vector2(um.x, uvmax.y if uvmax.y != -INF else 0.0))
		oi.append_array(PackedInt32Array([b0, b0 + 1, b0 + 2, b0, b0 + 2, b0 + 3]))
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = ov
	out[Mesh.ARRAY_NORMAL] = on
	out[Mesh.ARRAY_TEX_UV] = ou
	out[Mesh.ARRAY_INDEX] = oi
	return out
