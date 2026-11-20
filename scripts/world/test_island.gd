extends Node3D
## Сцена-заглушка: плоский остров, вода, небо/свет/туман, несколько деревьев,
## камни, бревно (переносится) и мишень. Нужна для тестов игрока и других
## модулей, пока WORLD строит настоящий мир.

const SIZE := 160          # метров по стороне сетки
const STEP := 1.0
const ISLAND_R := 55.0

var player: Player
var noise := FastNoiseLite.new()

func _ready() -> void:
	noise.seed = 1234
	noise.frequency = 0.035
	var env := WorldEnvironment.new()
	env.environment = RenderProfile.make_environment()
	add_child(env)
	add_child(RenderProfile.make_sun())
	_build_terrain()
	_build_water()
	_scatter_props()
	player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Player
	add_child(player)
	player.global_position = Vector3(0.0, height_at(0.0, 0.0) + 0.1, 0.0)
	Game.start_match({"minutes": 180, "teams": 4})

func height_at(x: float, z: float) -> float:
	var d := Vector2(x, z).length()
	var fall := clampf(1.0 - (d - ISLAND_R * 0.55) / (ISLAND_R * 0.6), 0.0, 1.0)
	fall = fall * fall * (3.0 - 2.0 * fall)
	var hills := noise.get_noise_2d(x, z) * 2.2 + 2.4
	return lerpf(-4.0, hills, fall)

func _build_terrain() -> void:
	var n := int(SIZE / STEP) + 1
	var half := SIZE * 0.5
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	for j in n:
		for i in n:
			heights[j * n + i] = height_at(-half + i * STEP, -half + j * STEP)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in n:
		for i in n:
			var h := heights[j * n + i]
			var c := Color(0.86, 0.80, 0.62) # песок
			if h > 1.2:
				c = Color(0.36, 0.48, 0.22).lerp(Color(0.45, 0.52, 0.28), clampf(noise.get_noise_2d(i * 3.0, j * 3.0) + 0.5, 0.0, 1.0))
			elif h > 0.6:
				c = Color(0.86, 0.80, 0.62).lerp(Color(0.40, 0.50, 0.25), (h - 0.6) / 0.6)
			elif h < 0.0:
				c = Color(0.70, 0.66, 0.50)
			st.set_color(c)
			st.set_uv(Vector2(i, j) * 0.25)
			st.add_vertex(Vector3(-half + i * STEP, h, -half + j * STEP))
	for j in n - 1:
		for i in n - 1:
			var a := j * n + i
			st.add_index(a); st.add_index(a + 1); st.add_index(a + n)
			st.add_index(a + 1); st.add_index(a + n + 1); st.add_index(a + n)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = st.commit()
	mi.material_override = TerrainMaterial.make(0.0)
	add_child(mi)
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	var hm := HeightMapShape3D.new()
	hm.map_width = n
	hm.map_depth = n
	hm.map_data = heights
	var cs := CollisionShape3D.new()
	cs.shape = hm
	cs.scale = Vector3(STEP, 1.0, STEP)
	body.add_child(cs)
	add_child(body)

func _build_water() -> void:
	add_child(WaterFactory.make(1200.0, 220))

func _scatter_props() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var bark := TerrainMaterial.pbr("palm_bark", 2.0)
	var log_bark := TerrainMaterial.pbr("bark_brown_02", 1.5)
	var leaf := StandardMaterial3D.new()
	leaf.albedo_color = Color(0.20, 0.38, 0.14)
	leaf.roughness = 0.9
	for k in 40:
		var a := rng.randf() * TAU
		var r := rng.randf_range(8.0, ISLAND_R * 0.75)
		var x := cos(a) * r
		var z := sin(a) * r
		var y := height_at(x, z)
		if y < 1.0:
			continue
		var tree := StaticBody3D.new()
		tree.name = "Tree%d" % k
		var h := rng.randf_range(6.0, 11.0)
		var trunk := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.18
		cm.bottom_radius = 0.32
		cm.height = h
		trunk.mesh = cm
		trunk.material_override = bark
		trunk.position.y = h * 0.5
		tree.add_child(trunk)
		var crown := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = rng.randf_range(2.0, 3.2)
		sm.height = sm.radius * 1.5
		crown.mesh = sm
		crown.material_override = leaf
		crown.position.y = h
		tree.add_child(crown)
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.3
		cyl.height = h
		cs.shape = cyl
		cs.position.y = h * 0.5
		tree.add_child(cs)
		tree.position = Vector3(x, y - 0.1, z)
		add_child(tree)
	var rock_scenes: Array[PackedScene] = []
	var rock_paths: Array[String] = []
	var names := UserRocks.SHAPES if UserRocks.available() else ["boulder_01", "boulder_02", "rock_07", "rock_moss_set_01_rock03", "rock_moss_set_02_rock09"]
	for f in names:
		var path: String = (UserRocks.DIR + f + ".glb") if UserRocks.available() else "res://assets/models/polyhaven/%s.glb" % f
		if ResourceLoader.exists(path):
			rock_scenes.append(load(path) as PackedScene)
			rock_paths.append(path)
	var plant_scenes: Array[PackedScene] = []
	for f in ["fern_02_a", "fern_02_b", "shrub_02_a", "shrub_02_c"]:
		var path := "res://assets/models/polyhaven/%s.glb" % f
		if ResourceLoader.exists(path):
			plant_scenes.append(load(path) as PackedScene)
	for k in 18:
		if rock_scenes.is_empty():
			break
		var a := rng.randf() * TAU
		var r := rng.randf_range(6.0, ISLAND_R * 0.85)
		var pos := Vector3(cos(a) * r, 0.0, sin(a) * r)
		pos.y = height_at(pos.x, pos.z) - 0.15
		var rock := rock_scenes[k % rock_scenes.size()].instantiate() as Node3D
		UserRocks.dress(rock, rock_paths[k % rock_paths.size()])
		rock.position = pos
		rock.rotation.y = rng.randf() * TAU
		rock.scale = Vector3.ONE * rng.randf_range(0.7, 1.6)
		add_child(rock)
	for k in 70:
		if plant_scenes.is_empty():
			break
		var a := rng.randf() * TAU
		var r := rng.randf_range(4.0, ISLAND_R * 0.7)
		var pos := Vector3(cos(a) * r, 0.0, sin(a) * r)
		pos.y = height_at(pos.x, pos.z)
		if pos.y < 1.4:
			continue
		var plant := plant_scenes[k % plant_scenes.size()].instantiate() as Node3D
		plant.position = pos
		plant.rotation.y = rng.randf() * TAU
		plant.scale = Vector3.ONE * rng.randf_range(0.8, 1.4)
		add_child(plant)
	# Бревно для проверки переноски и мишень для удара — перед игроком.
	var log_prop := TestProp.new()
	log_prop.name = "TestLog"
	log_prop.kind = &"log"
	var lm := MeshInstance3D.new()
	var lc := CylinderMesh.new()
	lc.top_radius = 0.18
	lc.bottom_radius = 0.2
	lc.height = 2.0
	lm.mesh = lc
	lm.material_override = log_bark
	lm.rotation.z = PI / 2.0
	log_prop.add_child(lm)
	var lcs := CollisionShape3D.new()
	var lcyl := CylinderShape3D.new()
	lcyl.radius = 0.2
	lcyl.height = 2.0
	lcs.shape = lcyl
	lcs.rotation.z = PI / 2.0
	log_prop.add_child(lcs)
	log_prop.position = Vector3(0.0, height_at(0.0, -2.0) + 0.2, -2.0)
	add_child(log_prop)
	var target := TestProp.new()
	target.name = "TestTarget"
	target.kind = &"target"
	var tm := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(0.6, 1.6, 0.6)
	tm.mesh = tb
	tm.material_override = log_bark
	tm.position.y = 0.8
	target.add_child(tm)
	var tcs := CollisionShape3D.new()
	var tbs := BoxShape3D.new()
	tbs.size = tb.size
	tcs.shape = tbs
	tcs.position.y = 0.8
	target.add_child(tcs)
	target.position = Vector3(2.5, height_at(2.5, -1.5), -1.5)
	add_child(target)
