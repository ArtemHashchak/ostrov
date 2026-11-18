class_name VatBaker
extends RefCounted
## Запекание скелетной анимации в текстуру (Vertex Animation Texture, VAT) — единственная
## реализация в проекте (море, полигон, паки моделей).
## Один раз (tools/bake_vat.gd или при подготовке пака): кости проигрываются на процессоре,
## для каждого кадра пишется СМЕЩЕНИЕ вершины от кадра 0 (RGBH, ширина = число вершин,
## строка = кадр). Меш — поза кадра 0 в пространстве модели (корень сцены), нормали
## повёрнуты так же. В игре шейдер подключает res://shaders/vat.gdshaderinc:
##     VERTEX += vat_offset(float(VERTEX_ID), TIME * скорость + фаза);
## скелета, AnimationPlayer и пересчёта костей нет, особей можно рисовать сотнями
## в одном MultiMesh; кадры интерполируются.
## Берётся самый большой скинованный меш модели (тело); глаза/зубы — у скелетной модели вблизи.
##
##   var data := VatBaker.bake(scene_root, "swim", 32)
##   VatBaker.save(data, "res://.../model_vat.res")      # меш + метаданные vat_*
##   VatBaker.apply(load("res://.../model_vat.res"), shader_material)

const MAX_VERTS := 16384

## root — инстанс сцены модели (лучше в дереве). anim — имя анимации ("" — swim или первая).
static func bake(root: Node, anim: String = "", frames: int = 32, _fps: float = 0.0) -> Dictionary:
	var mi := _find_skinned(root)
	if mi == null:
		push_warning("VatBaker: нет MeshInstance3D со скелетом")
		return {}
	var skel := mi.get_node_or_null(mi.skeleton) as Skeleton3D
	var ap := _find(root, "AnimationPlayer") as AnimationPlayer
	if skel == null or ap == null:
		push_warning("VatBaker: нет Skeleton3D или AnimationPlayer")
		return {}
	var names := ap.get_animation_list()
	if names.is_empty():
		return {}
	var picked := ""
	for n in names:
		var sn := String(n)
		if anim != "" and (sn == anim or sn.ends_with("/" + anim)):
			picked = sn
			break
	if picked == "":
		picked = String(names[0])
		for n in names:
			if String(n).to_lower().ends_with("swim"):
				picked = String(n)
				break
	var a := ap.get_animation(picked)
	var length := maxf(a.length, 0.01)
	var merged := _merge(mi.mesh)
	var verts: PackedVector3Array = merged.v
	var norms: PackedVector3Array = merged.n
	var bones: PackedInt32Array = merged.b
	var weights: PackedFloat32Array = merged.w
	var nv := verts.size()
	if nv > MAX_VERTS:
		push_warning("VatBaker: %d вершин > %d — упростите модель" % [nv, MAX_VERTS])
		return {}
	var per := 4 if bones.size() == nv * 4 else 8
	var skin := mi.skin
	if skin == null:
		skin = skel.create_skin_from_rest_transforms()
	var bind_bone := PackedInt32Array()
	for b in skin.get_bind_count():
		var bi := skin.get_bind_bone(b)
		if bi < 0:
			bi = skel.find_bone(skin.get_bind_name(b))
		bind_bone.append(bi)
	# скелетное пространство -> пространство модели (корня)
	var to_model := Transform3D.IDENTITY
	if skel.is_inside_tree() and root is Node3D and (root as Node3D).is_inside_tree():
		to_model = (root as Node3D).global_transform.affine_inverse() * skel.global_transform
	var img := Image.create(nv, frames, false, Image.FORMAT_RGBH)
	var rest := PackedVector3Array()
	var rest_n := PackedVector3Array()
	var bounds := AABB()
	ap.play(picked)
	for f in frames:
		ap.seek(length * f / frames, true)
		var mats: Array[Transform3D] = []
		for b in skin.get_bind_count():
			var bi := bind_bone[b]
			var g := skel.get_bone_global_pose(bi) if bi >= 0 else Transform3D.IDENTITY
			mats.append(to_model * g * skin.get_bind_pose(b))
		for i in nv:
			var v := verts[i]
			var acc := Vector3.ZERO
			var accn := Vector3.ZERO
			var wsum := 0.0
			for j in per:
				var w := weights[i * per + j]
				if w <= 0.0:
					continue
				var bi := bones[i * per + j]
				if bi < mats.size():
					acc += (mats[bi] * v) * w
					if f == 0:
						accn += (mats[bi].basis * norms[i]) * w
					wsum += w
			var p := acc / wsum if wsum > 0.0 else to_model * v
			if f == 0:
				rest.append(p)
				rest_n.append(accn.normalized() if wsum > 0.0 else (to_model.basis * norms[i]).normalized())
				bounds = AABB(p, Vector3.ZERO) if i == 0 else bounds.expand(p)
			else:
				bounds = bounds.expand(p)
			var off := p - rest[i]
			img.set_pixel(i, f, Color(off.x, off.y, off.z))
	ap.stop()
	# меш кадра 0 в пространстве модели
	var arr: Array = (merged.mesh as ArrayMesh).surface_get_arrays(0)
	arr[Mesh.ARRAY_VERTEX] = rest
	arr[Mesh.ARRAY_NORMAL] = rest_n
	arr[Mesh.ARRAY_TANGENT] = null
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := (merged.mesh as ArrayMesh).surface_get_material(0)
	if mat:
		out.surface_set_material(0, mat)
	out.custom_aabb = bounds.grow(0.05)
	return {"mesh": out, "texture": ImageTexture.create_from_image(img), "frames": frames,
		"length": length, "anim": picked, "verts": nv, "aabb": bounds}

## Сохранить как один ресурс: меш кадра 0 + метаданные vat_texture/vat_frames/vat_length/vat_aabb.
static func save(data: Dictionary, path: String) -> Error:
	var m: ArrayMesh = data.mesh
	m.set_meta(&"vat_texture", data.texture)
	m.set_meta(&"vat_frames", data.frames)
	m.set_meta(&"vat_length", data.length)
	m.set_meta(&"vat_aabb", data.aabb)
	m.set_meta(&"vat_anim", data.anim)
	return ResourceSaver.save(m, path)

## Настроить материал с vat.gdshaderinc (data — словарь bake() или сохранённый меш).
static func apply(data: Variant, mat: ShaderMaterial) -> void:
	var tex: Texture2D
	var frames := 1.0
	var length := 1.0
	if data is Dictionary:
		tex = data.texture
		frames = float(data.frames)
		length = float(data.length)
	elif data is Mesh:
		tex = (data as Mesh).get_meta(&"vat_texture", null)
		frames = float((data as Mesh).get_meta(&"vat_frames", 1))
		length = float((data as Mesh).get_meta(&"vat_length", 1.0))
	if tex == null:
		return
	mat.set_shader_parameter(&"vat_tex", tex)
	mat.set_shader_parameter(&"vat_frames", frames)
	mat.set_shader_parameter(&"vat_length", length)

## Длина модели по самой длинной оси (с учётом анимации).
static func model_length(data: Variant) -> float:
	var a: AABB
	if data is Dictionary:
		a = data.aabb
	elif data is Mesh:
		a = (data as Mesh).get_meta(&"vat_aabb", (data as Mesh).get_aabb())
	return maxf(a.size.x, maxf(a.size.y, a.size.z))

static func _merge(mesh: Mesh) -> Dictionary:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var b := PackedInt32Array()
	var w := PackedFloat32Array()
	var idx := PackedInt32Array()
	for si in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(si)
		var base := v.size()
		var sv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		v.append_array(sv)
		var sn: Variant = arr[Mesh.ARRAY_NORMAL]
		if sn is PackedVector3Array and (sn as PackedVector3Array).size() == sv.size():
			n.append_array(sn)
		else:
			for i in sv.size():
				n.append(Vector3.UP)
		var su: Variant = arr[Mesh.ARRAY_TEX_UV]
		if su is PackedVector2Array and (su as PackedVector2Array).size() == sv.size():
			uv.append_array(su)
		else:
			for i in sv.size():
				uv.append(Vector2.ZERO)
		var sb: Variant = arr[Mesh.ARRAY_BONES]
		var sw: Variant = arr[Mesh.ARRAY_WEIGHTS]
		if sb != null and sw != null:
			b.append_array(sb)
			w.append_array(sw)
		var si_idx: Variant = arr[Mesh.ARRAY_INDEX]
		if si_idx is PackedInt32Array:
			for k in (si_idx as PackedInt32Array):
				idx.append(base + k)
		else:
			for k in sv.size():
				idx.append(base + k)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = v
	out[Mesh.ARRAY_NORMAL] = n
	out[Mesh.ARRAY_TEX_UV] = uv
	out[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	if mesh.get_surface_count() > 0 and mesh.surface_get_material(0):
		am.surface_set_material(0, mesh.surface_get_material(0))
	return {"mesh": am, "v": v, "n": n, "b": b, "w": w}

static func _find_skinned(root: Node) -> MeshInstance3D:
	var best: MeshInstance3D = null
	var best_n := -1
	for n in [root] + root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null or mi.skeleton.is_empty() or not (mi.get_node_or_null(mi.skeleton) is Skeleton3D):
			continue
		var cnt := 0
		for si in mi.mesh.get_surface_count():
			cnt += mi.mesh.surface_get_array_len(si)
		if cnt > best_n:
			best_n = cnt
			best = mi
	return best

static func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null
