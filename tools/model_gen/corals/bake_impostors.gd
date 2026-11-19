extends TestCase
## Запекание импосторов («заранее снятых» кораллов) — только твёрдые кораллы без щупалец.
## Запуск (под xvfb, как тест):
##   CORAL_HI=/tmp/c4/corals_hi.glb IMP_OUT=/tmp/c4/imp TEST_TIMEOUT=3600 tests/run.sh tools/model_gen/corals/bake_impostors.gd
## Затем: python3 tools/model_gen/corals/impostor_post.py /tmp/c4/imp assets/corals/impostors
## Для каждого варианта: модель высокой детализации (tools/model_gen/corals/gen.py --hi) снимается
## ортокамерой с N×N направлений верхней полусферы (полу-октаэдрическая раскладка), кадр S×S пикселей,
## два прохода: альбедо (RGBA, альфа — покрытие) и нормаль в координатах модели. Атлас N·S × N·S.
## Мета (центр, радиус, N) пишется в IMP_OUT/meta.json.

const HARD := [&"table", &"staghorn", &"corymbose", &"lobed", &"foliose", &"antler", &"mound", &"millepora"]
const N := 8
const S := 256

func _init() -> void:
	scene_path = ""
	timeout_sec = 3500.0

var vp: SubViewport
var cam: Camera3D
var mi: MeshInstance3D
var mat: ShaderMaterial

## Полу-октаэдр: направление верхней полусферы ↔ точка квадрата [-1,1]².
static func hemi_decode(o: Vector2) -> Vector3:
	var p := Vector2(o.x + o.y, o.x - o.y) * 0.5
	var y := 1.0 - absf(p.x) - absf(p.y)
	return Vector3(p.x, maxf(y, 0.0), p.y).normalized()

static func frame_basis(d: Vector3) -> Basis:
	var x: Vector3
	if absf(d.y) > 0.999:
		x = Vector3(1, 0, 0)
	else:
		x = Vector3.UP.cross(d).normalized()
	var y := d.cross(x).normalized()
	return Basis(x, y, d)

func run() -> void:
	var src := OS.get_environment("CORAL_HI")
	if src == "":
		src = "/tmp/c4/corals_hi.glb"
	var out_dir := OS.get_environment("IMP_OUT")
	if out_dir == "":
		out_dir = "/tmp/c4/imp"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_file(src, st)
	check(err == OK, "загружен %s" % src)
	if err != OK:
		return
	var scene_root := doc.generate_scene(st)
	var meshes := {}
	_collect(scene_root, meshes)
	print("[test] мешей высокой детализации: %d" % meshes.size())

	vp = SubViewport.new()
	vp.size = Vector2i(S, S)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment.fog_enabled = false
	env.environment.glow_enabled = false
	vp.add_child(env)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	vp.add_child(cam)
	cam.current = true
	mi = MeshInstance3D.new()
	vp.add_child(mi)
	mat = ShaderMaterial.new()
	mat.shader = load("res://scripts/sea/shaders/coral_bake.gdshader")
	mi.material_override = mat

	var meta := {}
	var only := OS.get_environment("CORAL_TYPES")
	for t in HARD:
		if only != "" and not (String(t) in only.split(",")):
			continue
		var d: Dictionary = CoralPack.TYPES.get(t, {})
		for v in int(d.get("vars", 1)):
			var key := "%s_v%d" % [t, v]
			var m: Mesh = meshes.get(key + "_hi")
			if m == null:
				check(false, "нет %s_hi" % key)
				continue
			mi.mesh = m
			mat.set_shader_parameter(&"pattern", int(d.get("pattern", 0)))
			mat.set_shader_parameter(&"pattern_scale", float(d.get("pscale", 90.0)))
			var aabb := m.get_aabb()
			var c := aabb.get_center()
			var r := aabb.size.length() * 0.5 * 1.02
			cam.size = r * 2.0
			cam.near = 0.01
			cam.far = r * 6.0
			var imgs := []
			for mode in 2:
				mat.set_shader_parameter(&"mode", mode)
				var atlas := Image.create(N * S, N * S, false, Image.FORMAT_RGBA8)
				for j in N:
					for i in N:
						var o := Vector2((i + 0.5) / N * 2.0 - 1.0, (j + 0.5) / N * 2.0 - 1.0)
						var dir := hemi_decode(o)
						var b := frame_basis(dir)
						cam.transform = Transform3D(b, c + dir * r * 3.0)
						await RenderingServer.frame_post_draw
						await RenderingServer.frame_post_draw
						var img := vp.get_texture().get_image()
						img.convert(Image.FORMAT_RGBA8)
						atlas.blit_rect(img, Rect2i(0, 0, S, S), Vector2i(i * S, j * S))
				var path := "%s/%s_%s.png" % [out_dir, key, "albedo" if mode == 0 else "normal"]
				atlas.save_png(path)
				imgs.append(path)
			meta[key] = {"center": [c.x, c.y, c.z], "radius": r, "frames": N}
			print("[test] %s: центр %s, радиус %.3f" % [key, c, r])
	var f := FileAccess.open(out_dir + "/meta.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "\t"))
	f.close()
	check(meta.size() > 0, "запечено импосторов: %d" % meta.size())
	scene_root.free()


func _collect(n: Node, out: Dictionary) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var m := (n as MeshInstance3D).mesh
		var xf := (n as MeshInstance3D).transform
		if not xf.is_equal_approx(Transform3D.IDENTITY):
			m = CoralPack._baked(m, xf)
		out[String(n.name)] = m
	for c in n.get_children():
		_collect(c, out)
