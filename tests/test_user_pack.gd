extends TestCase
## Витрина пака на старом полигоне убрана (полигон v5 показывает все модели сам — test_polygon_v5).
## Пак моделей пользователя на полигоне: зона «Пак моделей» собрана, нормализованные
## акула и пальма загружаются в бюджете, акула анимирована, водоросли расталкиваются.
## Скриншоты: зона, акула крупно, живая акула в море, водоросли под водой.


func _init() -> void:
	scene_path = ""
	timeout_sec = 3500.0

func run() -> void:
	Engine.max_physics_steps_per_frame = 30
	# бюджеты моделей
	for e in [["res://assets/user_pack/animals/animal_shark_great_white.glb", 12000],
			["res://assets/user_pack/trees/tree_palm_coconut_user.glb", 12000]]:
		var ps := load(e[0]) as PackedScene
		check(ps != null, "загружается %s" % e[0].get_file())
		if ps:
			var n := ps.instantiate()
			var tris := 0
			var surfs := 0
			for mi in n.find_children("*", "MeshInstance3D", true, false):
				var m: Mesh = (mi as MeshInstance3D).mesh
				surfs += m.get_surface_count()
				for s in m.get_surface_count():
					tris += (m.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			check(tris <= int(e[1]), "%s: %d треуг. ≤ %d, поверхностей %d" % [e[0].get_file(), tris, e[1], surfs])
			n.free()
