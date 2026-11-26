extends TestCase
## Витрины на старом полигоне убраны (полигон v5 показывает все виды сам — test_polygon_v5).
## Морской пак пользователя: виды из assets/user_pack/sea_species_user_sea.json попали в реестр
## (свой шейдер, анимация щупалец/хвоста), меши в бюджете, ракушка — предмет с моделью из пака,
## витрины и подводные группы на полигоне. Скриншоты: витрины, крупно осьминог/кальмар, под водой, ракушки.


func _init() -> void:
	scene_path = ""
	timeout_sec = 3500.0

func run() -> void:
	Engine.max_physics_steps_per_frame = 30
	SeaSpecies.reload()
	var budgets := {"small": 1500, "medium": 5000, "large": 12000}
	var ids := ["discus_user", "redfish_user", "spotted_user", "shark_pack8_user", "octopus_user", "squid_user"]
	for id in ids:
		var d := SeaSpecies.get_species(id)
		check(not d.is_empty(), "вид в реестре: %s" % id)
		if d.is_empty():
			continue
		var m := load(String(d.mesh)) as Mesh
		check(m != null, "%s: меш загружается" % id)
		if m:
			var tris := (m.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			check(m.get_surface_count() == 1, "%s: одна поверхность (атлас)" % id)
			check(tris <= int(budgets[String(d.category)]), "%s: %d треуг. ≤ бюджета %s" % [id, tris, d.category])
		check(ResourceLoader.exists(String(d.shader)), "%s: шейдер пака" % id)
	UserSeaPack.register_items()
	check(Items.get_item(&"seashell") != null, "предмет «Ракушка» зарегистрирован")
	var held := HeldModels.build(&"seashell")
	check(held.find_children("*", "MeshInstance3D", true, false).size() > 0, "ракушка в руке — модель из пака")
	held.free()
