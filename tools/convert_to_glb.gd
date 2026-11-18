extends SceneTree
## Конвертер любого формата, который импортирует Godot (FBX/OBJ/DAE/GLB/BLEND без Blender — нет),
## в .glb через GLTFDocument. Запуск во временном проекте (tools/asset_normalize.py делает это сам):
##   godot --headless -s res://convert_to_glb.gd -- res://src/model.fbx /abs/out.glb [--no-anim]
## Текстуры, назначенные материалам, встраиваются в glb.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: -- <res://in> <out.glb> [--no-anim]")
		quit(2)
		return
	var src: String = args[0]
	var dst: String = args[1]
	var no_anim := args.has("--no-anim")
	var ps := load(src) as PackedScene
	if ps == null:
		push_error("cannot load " + src)
		quit(3)
		return
	var root := ps.instantiate()
	if no_anim:
		for ap in root.find_children("*", "AnimationPlayer", true, false):
			ap.get_parent().remove_child(ap)
			ap.free()
	# FBX-импорт держит материалы во внешних ресурсах — GLTF возьмёт их как есть.
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_scene(root, st)
	if err == OK:
		err = doc.write_to_filesystem(st, dst)
	print("convert_to_glb: ", src, " -> ", dst, " err=", err)
	root.free()
	quit(0 if err == OK else 4)
