extends TestCase
## VAT на настоящей модели: акула из пака пользователя, анимация «swim» запечена в
## текстуру (tools/bake_vat.gd) — три особи одним MultiMesh, без скелета.

const VAT := "res://assets/user_pack/animals/shark_vat.res"

func _init() -> void:
	scene_path = "res://scenes/world/world_view.tscn"
	timeout_sec = 2400.0

func run() -> void:
	await wait(1.0)
	var w := get_tree().get_first_node_in_group(&"world") as World
	check(w != null and w.is_ready, "мир готов")
	if w == null or not ResourceLoader.exists(VAT):
		check(false, "нет %s" % VAT)
		return
	w.set_time_of_day(12.0)
	w.set_weather(&"clear", true)
	w.set_time_paused(true)
	var sea := Sea.new()
	sea.auto_populate = false
	sea.life_cells_enabled = false
	scene.add_child(sea)
	sea._find_world()
	var cells := SeaLifeCells.new()
	cells.sea = sea
	cells.set_process(false)
	sea.add_child(cells)
	var d := SeaSpecies._normalize({"id": "vat_shark", "anim": "vat", "vat": VAT, "length": 4.0, "mesh": "",
		"school": [3, 3], "roam": 9.0, "speed": 1.6, "colors": ["#7d8590", "#9aa3ad"]})
	var mi := cells._take(d)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# глубокое место недалеко от острова
	var I: Dictionary = w.islands()[1]
	var c: Vector2 = I.center
	var p := Vector3(c.x + float(I.radius) + 45.0, 0, c.y)
	for i in 36:
		var a := TAU * i / 36.0
		var q := c + Vector2(cos(a), sin(a)) * (float(I.radius) + 45.0)
		if sea.depth_at(q.x, q.y) > 9.0:
			p = Vector3(q.x, 0, q.y)
			break
	var wy := sea.water_y()
	var pos := Vector3(p.x, maxf(wy - 4.0, sea.floor_at(p.x, p.z) + 2.5), p.z)
	cells._setup_group(mi, d, pos, rng, 10.0)
	check(int((mi.material_override as ShaderMaterial).get_shader_parameter(&"anim_mode")) == 5, "материал на VAT")
	print("[test] вершин меша VAT: %d" % (mi.multimesh.mesh as ArrayMesh).surface_get_array_len(0))
	var cam := Camera3D.new()
	scene.add_child(cam)
	cam.current = true
	cam.global_position = pos + Vector3(-14, 1.0, -6)
	cam.look_at(pos)
	await wait(1.0)
	await shot("a")
	await wait(0.7)
	await shot("b")
	cam.global_position = pos + Vector3(0, 9.0, 0.1)
	cam.look_at(pos)
	await wait(0.5)
	await shot("top")
