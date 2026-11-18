extends SceneTree
## Запечь анимацию модели пака в формат модуля моря (VatBaker → один .res для SeaSpecies "vat").
##   godot --headless --path . -s res://tools/bake_vat_sea.gd -- <res://model.glb> <anim> <frames> <res://out.res>
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var root := (load(a[0]) as PackedScene).instantiate()
	var data := VatBaker.bake(root, a[1], int(a[2]))
	var err := VatBaker.save(data, a[3]) if not data.is_empty() else ERR_CANT_CREATE
	print("bake_vat_sea: ", a[3], " err=", err, " verts=", data.get("verts", 0))
	root.free()
	quit(0 if err == OK else 1)
