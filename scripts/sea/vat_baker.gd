class_name VatBaker
extends RefCounted
## Запекание скелетной анимации в текстуру (Vertex Animation Texture, VAT).
## Один раз (инструментом или при импорте): кости проигрываются на процессоре, позиции
## вершин каждого кадра пишутся в строку текстуры (RGBH, ширина = число вершин).
## В игре шейдер sea_species (anim_mode 5) читает строку по времени и VERTEX_ID —
## скелета, AnimationPlayer и пересчёта костей нет, особей можно рисовать сотнями
## в одном MultiMesh. Нормали — из позы покоя (для плавающих тел незаметно).
##
##   var data := VatBaker.bake(scene_root, "Swim", 32)   # -> {mesh, texture, frames, fps}
##   VatBaker.save(data, "res://assets/user_pack/animals/shark_vat.res")
##   VatBaker.apply(load(...), shader_material)

const MAX_VERTS := 16384

## root — инстанс сцены модели (в дереве не обязателен). anim — имя анимации ("" — первая).
static func bake(root: Node, anim: String = "", frames: int = 32, fps: float = 0.0) -> Dictionary:
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
	if anim == "" or not ap.has_animation(anim):
		anim = names[0]
		for n in names:
			if String(n).to_lower().contains("swim"):
				anim = n
				break
	var a := ap.get_animation(anim)
	var length := maxf(a.length, 0.01)
	if fps <= 0.0:
		fps = frames / length
	# объединённая поверхность (VERTEX_ID сквозной)
	var merged := _merge(mi.mesh)
	var verts: PackedVector3Array = merged.v
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
	var mi_to_skel := (skel.global_transform.affine_inverse() * mi.global_transform) if mi.is_inside_tree() else Transform3D.IDENTITY
	var img := Image.create(nv, frames, false, Image.FORMAT_RGBH)
	ap.play(anim)
	for f in frames:
		ap.seek(length * f / frames, true)
		var mats: Array[Transform3D] = []
		for b in skin.get_bind_count():
			var bi := bind_bone[b]
			var g := skel.get_bone_global_pose(bi) if bi >= 0 else Transform3D.IDENTITY
			mats.append(g * skin.get_bind_pose(b))
		for i in nv:
			var v := verts[i]
			var acc := Vector3.ZERO
			var wsum := 0.0
			for j in per:
				var w := weights[i * per + j]
				if w <= 0.0:
					continue
				var bi := bones[i * per + j]
				if bi < mats.size():
					acc += (mats[bi] * v) * w
					wsum += w
			var p := acc / wsum if wsum > 0.0 else v
			p = mi_to_skel * p
			img.set_pixel(i, f, Color(p.x, p.y, p.z))
	ap.stop()
	return {"mesh": merged.mesh, "texture": ImageTexture.create_from_image(img), "frames": frames, "fps": fps,
		"anim": String(anim), "verts": nv}

## Сохранить результат как ресурс (меш + текстура + параметры в метаданных меша).
static func save(data: Dictionary, path: String) -> Error:
	var m: ArrayMesh = data.mesh
	m.set_meta(&"vat_texture", data.texture)
	m.set_meta(&"vat_frames", data.frames)
	m.set_meta(&"vat_fps", data.fps)
	return ResourceSaver.save(m, path)

## Настроить материал sea_species на VAT (data — словарь bake() или сохранённый меш).
static func apply(data: Variant, mat: ShaderMaterial) -> void:
	var tex: Texture2D
	var frames := 1.0
	var fps := 24.0
	if data is Dictionary:
		tex = data.texture
		frames = float(data.frames)
		fps = float(data.fps)
	elif data is Mesh:
		tex = (data as Mesh).get_meta(&"vat_texture", null)
		frames = float((data as Mesh).get_meta(&"vat_frames", 1))
		fps = float((data as Mesh).get_meta(&"vat_fps", 24.0))
	if tex == null:
		return
	mat.set_shader_parameter(&"anim_mode", 5)
	mat.set_shader_parameter(&"vat_pos", tex)
	mat.set_shader_parameter(&"vat_frames", frames)
	mat.set_shader_parameter(&"vat_fps", fps)
	mat.set_shader_parameter(&"vat_min", Vector3.ZERO)
	mat.set_shader_parameter(&"vat_scale", Vector3.ONE)

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
	return {"mesh": am, "v": v, "b": b, "w": w}

static func _find_skinned(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh and not (n as MeshInstance3D).skeleton.is_empty() \
			and (n as MeshInstance3D).get_node_or_null((n as MeshInstance3D).skeleton) is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skinned(c)
		if r:
			return r
	return null

static func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null
