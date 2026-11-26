## test-class: render
## test-timeout: 1800
extends TestCase
## Витрина новых растений версии 5 (assets/user_pack/flora_v5 через AssetCatalog): каждое растение
## крупно на песке при дневном свете + группа рядом (масштаб друг к другу) + коллайдеры soft/solid
## на месте. Снимки — tests/shots/test_flora_v5_shots_*.png.

func _init() -> void:
	scene_path = ""
	timeout_sec = 1800.0

const SHOW := ["flora_strelitzia", "flora_matteuccia_a", "flora_liana_wall", "flora_liana_span_01", "flora_liana_hang_curtain_05",
	"flora_kingsville_2", "flora_kingsville_5", "flora_macrozamia_1", "flora_howea_1", "flora_gs_grass4", "flora_gs_daisies",
	"flora_grass_clump_razw"]

func run() -> void:
	AssetCatalog.reload()
	var root := Node3D.new()
	add_child(root)
	var env := WorldEnvironment.new()
	env.environment = RenderProfile.make_environment()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#9DB7D6")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("#C9D6E6")
	env.environment.ambient_light_energy = 0.6
	env.environment.fog_enabled = false
	root.add_child(env)
	root.add_child(RenderProfile.make_sun())
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("#C9B48C")
	gm.roughness = 1.0
	ground.material_override = gm
	root.add_child(ground)
	var cam := Camera3D.new()
	cam.fov = 45.0
	root.add_child(cam)
	cam.current = true
	await wait_frames(3)
	var holder := Node3D.new()
	root.add_child(holder)
	var ok := 0
	for id: String in SHOW:
		for c in holder.get_children():
			c.free()
		var n := AssetCatalog.instantiate(id)
		if n == null:
			print("[test] нет модели ", id)
			continue
		holder.add_child(n)
		var e := AssetCatalog.get_entry(id)
		var sz: Array = e.get("size_m", [1, 1, 1])
		var s := maxf(float(sz[0]), maxf(float(sz[1]), float(sz[2])))
		var c := Vector3(0, float(sz[1]) * 0.45, 0)
		cam.position = c + Vector3(s * 0.9, s * 0.35, s * 1.3)
		cam.look_at(c, Vector3.UP)
		await wait_frames(6)
		await shot(id)
		ok += 1
	check(ok == SHOW.size(), "все модели витрины показаны (%d/%d)" % [ok, SHOW.size()])
	# ---- группа: деревья и растения рядом, с коллайдерами
	for c in holder.get_children():
		c.free()
	var x := -14.0
	var cols := 0
	for id: String in SHOW:
		var n := AssetCatalog.instantiate(id)
		if n == null:
			continue
		var e := AssetCatalog.get_entry(id)
		var w := maxf(float((e.get("size_m", [1, 1, 1]) as Array)[0]), 0.6)
		x += w * 0.5
		n.position = Vector3(x, 0, 0)
		holder.add_child(n)
		var col := AssetCatalog.make_collider(id)
		if col:
			col.position = n.position
			holder.add_child(col)
			cols += 1
		x += w * 0.5 + 0.6
	cam.position = Vector3(0, 4.0, 22.0)
	cam.look_at(Vector3(0, 1.8, 0), Vector3.UP)
	await wait_frames(8)
	await shot("group")
	check(cols >= 8, "у soft/solid растений есть коллайдеры (%d)" % cols)
