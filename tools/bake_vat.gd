extends SceneTree
## Запечь скелетную анимацию модели в VAT (для SeaSpecies anim = "vat").
##   godot --headless --path . -s tools/bake_vat.gd -- res://path/model.glb res://path/out_vat.res [анимация] [кадров]
## Результат — меш (одна поверхность) с метаданными vat_texture/vat_frames/vat_fps.
## В реестре вида: "anim": "vat", "vat": "res://path/out_vat.res".

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("нужно: <модель> <выход.res> [анимация] [кадров]")
		quit(1)
		return
	var ps := load(args[0]) as PackedScene
	if ps == null:
		printerr("не загрузить ", args[0])
		quit(1)
		return
	var root := ps.instantiate()
	get_root().add_child(root)
	await process_frame
	var anim := args[2] if args.size() > 2 else ""
	var frames := int(args[3]) if args.size() > 3 else 32
	var t0 := Time.get_ticks_msec()
	var data := VatBaker.bake(root, anim, frames)
	if data.is_empty():
		printerr("VAT не запечён")
		quit(1)
		return
	var err := VatBaker.save(data, args[1])
	print("VAT: анимация «%s», %d вершин × %d кадров, %d мс, сохранено %s (%s)" % [data.anim, data.verts, frames,
		Time.get_ticks_msec() - t0, args[1], error_string(err)])
	quit(0 if err == OK else 1)
