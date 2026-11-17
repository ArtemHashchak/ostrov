extends SceneTree
# Asset preview: godot --path <proj> -s res://tools/asset_preview.gd -- <out_dir>
# Builds a small beach scene from assets/ and saves screenshots.

const M := "res://assets/models/"
const T := "res://assets/textures/"
var out_dir := "res://tests/shots"
var cam: Camera3D
var root3d: Node3D

func tex_mat(name: String, uv := 1.0, alpha := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var b := T + name + "/" + name
	if ResourceLoader.exists(b + "_albedo.png"): m.albedo_texture = load(b + "_albedo.png")
	if ResourceLoader.exists(b + "_normal.png"):
		m.normal_enabled = true; m.normal_texture = load(b + "_normal.png")
	if ResourceLoader.exists(b + "_roughness.png"):
		m.roughness_texture = load(b + "_roughness.png")
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	if ResourceLoader.exists(b + "_ao.png"):
		m.ao_enabled = true; m.ao_texture = load(b + "_ao.png")
	if alpha:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.uv1_scale = Vector3(uv, uv, uv)
	return m

func put(path: String, pos: Vector3, s := 1.0, rot := 0.0) -> Node3D:
	if not ResourceLoader.exists(path):
		push_warning("missing " + path); return null
	var r = load(path)
	var n: Node3D
	if r is PackedScene: n = r.instantiate()
	elif r is Mesh:
		var mi := MeshInstance3D.new(); mi.mesh = r; n = mi
	else: return null
	n.position = pos; n.scale = Vector3.ONE * s; n.rotation.y = rot
	root3d.add_child(n)
	return n

func plane(size: Vector2, mat: Material, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = size; pm.subdivide_width = 32; pm.subdivide_depth = 32
	mi.mesh = pm; mi.material_override = mat; mi.position = pos
	root3d.add_child(mi)

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: out_dir = args[0]
	root3d = Node3D.new(); root.add_child(root3d)
	# Sky / light
	var env := Environment.new()
	var sky := Sky.new(); var psm := PanoramaSkyMaterial.new()
	psm.panorama = load("res://assets/hdri/kloofendal_48d_partly_cloudy_puresky.hdr")
	sky.sky_material = psm; env.background_mode = Environment.BG_SKY; env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true; env.fog_density = 0.004; env.fog_light_color = Color(0.7, 0.8, 0.9)
	var we := WorldEnvironment.new(); we.environment = env; root3d.add_child(we)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40, -30, 0)
	sun.light_energy = 1.3; sun.shadow_enabled = true; root3d.add_child(sun)
	# Ground: sand beach, wet sand strip, grass inland; ocean
	plane(Vector2(60, 40), tex_mat("coast_sand_01", 12), Vector3(0, 0, -10))
	plane(Vector2(60, 6), tex_mat("damp_sand", 12), Vector3(0, 0.01, 11))
	plane(Vector2(60, 14), tex_mat("leafy_grass", 10), Vector3(0, 0.02, -24))
	var wm = load("res://addons/ostrova_water/antz_foam_water/water_material.tres")
	var water := MeshInstance3D.new(); var qm := PlaneMesh.new(); qm.size = Vector2(200, 120)
	qm.subdivide_width = 100; qm.subdivide_depth = 100
	water.mesh = qm; water.material_override = wm; water.position = Vector3(0, 0.15, 72)
	root3d.add_child(water)
	# Models
	put(M + "polyhaven/boulder_01.glb", Vector3(-6, 0, -2), 1.5, 0.4)
	put(M + "polyhaven/rock_moss_set_01_rock01.glb", Vector3(5, 0, -4), 2.0)
	put(M + "polyhaven/rock_07.glb", Vector3(8, 0, 6), 1.5)
	put(M + "polyhaven/tree_stump_01.glb", Vector3(-3, 0, -8), 1.0)
	put(M + "polyhaven/dead_tree_trunk.glb", Vector3(2, 0, 3), 1.0, 1.2)
	for i in 4:
		put(M + "polyhaven/shrub_02_%s.glb" % ["a","b","c","d"][i], Vector3(-10 + i * 4, 0, -14), 1.5, i)
		put(M + "polyhaven/fern_02_%s.glb" % ["a","b","c","d"][i], Vector3(-8 + i * 4, 0, -11), 1.5, i * 2)
	put(M + "polyhaven/wooden_barrels_01_barrel01.glb", Vector3(-1, 0, 6), 1.0)
	put(M + "polyhaven/wooden_crate_01.glb", Vector3(0.5, 0, 7), 1.0, 0.5)
	put(M + "polyhaven_obj/wooden_lantern_01/wooden_lantern_01.obj", Vector3(-2, 0, 6.5), 1.0, 0.3)
	put(M + "polyhaven_obj/shrub_04/shrub_04.obj", Vector3(6, 0, -9), 1.0)
	put(M + "polyhaven_obj/dead_tree_trunk_02/dead_tree_trunk_02.obj", Vector3(-9, 0, 2), 1.0, 0.7)
	put(M + "polyhaven/wooden_barrels_01_barrel02.glb", Vector3(-0.3, 0, 7.8), 1.0, 1.0)
	put(M + "polyhaven/cannon_01.glb", Vector3(4, 0, 4), 1.0, 2.5)
	put(M + "polyhaven_obj/periwinkle_plant/periwinkle_plant.obj", Vector3(3, 0, -10), 2.0)
	put(M + "polyhaven_obj/shrub_03/shrub_03.obj", Vector3(-12, 0, -16), 1.0)
	for i in 6:
		put(M + "polyhaven_obj/grass_medium_01/grass_medium_01.obj", Vector3(-6 + i * 2.5, 0, -18), 1.0, i)
	put(M + "ships/dutch_ship_medium_2k.glb", Vector3(-25, 0, 55), 1.0, 0.8)
	put(M + "khronos/BarramundiFish.glb", Vector3(1.5, 0.15, 9.5), 1.5, 1.0)
	cam = Camera3D.new(); cam.fov = 70; root3d.add_child(cam)
	call_deferred("_shots")

func _shots() -> void:
	var views := [
		["assets_beach", Vector3(0, 2.2, 13), Vector3(0, 0.8, 0)],
		["assets_props", Vector3(2.5, 1.4, 10.5), Vector3(-0.5, 0.4, 6)],
		["assets_jungle", Vector3(0, 1.7, -5), Vector3(-1, 0.6, -13)],
		["assets_ocean", Vector3(5, 3, 10), Vector3(-20, 2, 50)],
	]
	for v in views:
		cam.look_at_from_position(v[1], v[2])
		for f in 12: await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var p := out_dir.path_join(v[0] + ".png")
		img.save_png(p if p.is_absolute_path() and not p.begins_with("res://") else ProjectSettings.globalize_path(p))
		print("saved ", p)
	quit()
