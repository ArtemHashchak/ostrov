extends SceneTree
## Выгрузка/загрузка текстур морских мешей пака (.res) для стилевой калибровки.
##   godot --headless --path . -s tools/style/sea_res_io.gd -- dump <out_dir> <res...>
##   godot --headless --path . -s tools/style/sea_res_io.gd -- inject <in_dir> <res...>
## dump: <out_dir>/<имя>_albedo.png (+ _mesh.json: вершины, UV, индексы, класс текстуры).
## inject: берёт <in_dir>/<имя>_albedo.png и кладёт в материал поверхности 0 как
## ImageTexture (с mipmap) — так же, как было в исходном .res.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		push_error("нужно: dump|inject <dir> <res...>")
		quit(2)
		return
	var mode := args[0]
	var dir := args[1]
	DirAccess.make_dir_recursive_absolute(dir)
	var code := 0
	for i in range(2, args.size()):
		var path: String = args[i]
		var mesh := load(path) as Mesh
		if mesh == null:
			push_error("не загрузился " + path)
			code = 1
			continue
		var name := path.get_file().get_basename()
		var mat := mesh.surface_get_material(0) as BaseMaterial3D
		if mode == "dump":
			var info := {"res": path, "surfaces": mesh.get_surface_count(), "tex_class": "", "w": 0, "h": 0}
			if mat and mat.albedo_texture:
				var img := mat.albedo_texture.get_image()
				if img.is_compressed():
					img.decompress()
				img.convert(Image.FORMAT_RGBA8)
				img.save_png(dir.path_join(name + "_albedo.png"))
				info.tex_class = mat.albedo_texture.get_class()
				info.w = img.get_width()
				info.h = img.get_height()
				info.albedo_color = [mat.albedo_color.r, mat.albedo_color.g, mat.albedo_color.b]
				info.roughness = mat.roughness
			var verts := []
			var uvs := []
			var idx := []
			var base := 0
			for s in mesh.get_surface_count():
				var arr := mesh.surface_get_arrays(s)
				var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var t = arr[Mesh.ARRAY_TEX_UV]
				var ix = arr[Mesh.ARRAY_INDEX]
				for p in v:
					verts.append([p.x, p.y, p.z])
				if t != null:
					for q: Vector2 in t:
						uvs.append([q.x, q.y])
				if ix != null and (ix as PackedInt32Array).size() > 0:
					for k: int in ix:
						idx.append(base + k)
				else:
					for k in v.size():
						idx.append(base + k)
				base += v.size()
			info.verts = verts
			info.uvs = uvs
			info.idx = idx
			var f := FileAccess.open(dir.path_join(name + "_mesh.json"), FileAccess.WRITE)
			f.store_string(JSON.stringify(info))
			f.close()
			print("dump ", path, " ", info.tex_class, " ", info.w, "x", info.h)
		elif mode == "inject":
			var png := dir.path_join(name + "_albedo.png")
			if mat == null or not FileAccess.file_exists(png):
				print("пропуск ", path)
				continue
			var img := Image.load_from_file(png)
			img.generate_mipmaps()
			# ImageTexture, как в исходных .res: PortableCompressedTexture2D внутри сжатого .res
			# сохранялся пустым (size 0) — модель теряла текстуру
			mat.albedo_texture = ImageTexture.create_from_image(img)
			var err := ResourceSaver.save(mesh, path, ResourceSaver.FLAG_COMPRESS)
			if err != OK:
				push_error("не сохранился %s: %d" % [path, err])
				code = 1
			else:
				print("inject ", path)
	quit(code)
