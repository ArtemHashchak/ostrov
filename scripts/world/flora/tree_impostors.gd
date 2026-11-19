class_name TreeImpostors
extends RefCounted
## Дальние деревья (дальше TREE_FAR ≈ 650 м) — «заранее снятые» картинки: каждый вид
## дерева один раз фотографируется сбоку (SubViewport, орто-камера, ровный свет) в
## текстуру, а вдали рисуется одним квадом (2 треугольника), повёрнутым к камере.
## Раньше дальше 650 м деревьев не было вовсе — дальние острова «лысели», и вокруг
## игрока читался круг леса. Квады плавно проявляются дизерингом на 595–650 м
## (перекрываясь с LOD2), дальше — до горизонта (дальность камеры 1500 м).

const SHADER := preload("res://scripts/world/flora/tree_impostor.gdshader")
const RES := 256

## Квад: x ∈ [-0.5, 0.5], y ∈ [0, 1]; растягивается шейдером под размер вида.
static func quad_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := [Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, 1, 0), Vector3(-0.5, 1, 0)]
	var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_normal(Vector3(0, 0, 1))
		st.set_uv(uvs[i])
		st.add_vertex(pts[i])
	return st.commit()

## Материал вида дерева: размеры квада берутся из AABB меша LOD1 (вариант 0).
static func make_material(mesh: Mesh, fade_in0: float, fade_in1: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	var ab := mesh.get_aabb()
	# квад центрирован на стволе (начале координат): ширина — по самой дальней точке кроны
	var half := maxf(maxf(absf(ab.position.x), absf(ab.end.x)), maxf(absf(ab.position.z), absf(ab.end.z)))
	var s := maxf(half * 2.06, ab.size.y * 1.02)
	m.set_shader_parameter(&"size", Vector2(s, s))
	m.set_shader_parameter(&"y0", ab.position.y)
	m.set_shader_parameter(&"fade_in", Vector2(fade_in0, fade_in1))
	m.set_meta(&"aabb", ab)
	return m

## Снимок вида сбоку в текстуру (асинхронно: нужен кадр отрисовки). В headless —
## пропуск (текстура не появится, квады остаются невидимыми: alpha 0).
static func bake(host: Node, mesh: Mesh, mat: ShaderMaterial) -> void:
	if DisplayServer.get_name() == "headless" or not host.is_inside_tree():
		return
	var ab: AABB = mat.get_meta(&"aabb")
	var vp := SubViewport.new()
	vp.size = Vector2i(RES, RES)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.msaa_3d = Viewport.MSAA_DISABLED
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-35.0), deg_to_rad(20.0), 0)
	sun.light_energy = 0.35
	vp.add_child(sun)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	vp.add_child(mi)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var sz: Vector2 = mat.get_shader_parameter(&"size")
	cam.size = sz.y
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.position = Vector3(0.0, ab.position.y + cam.size * 0.5, 200.0)
	cam.near = 1.0
	cam.far = 400.0
	vp.add_child(cam)
	cam.current = true
	host.add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if not is_instance_valid(vp):
		return
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		return
	img.generate_mipmaps()
	mat.set_shader_parameter(&"albedo_tex", ImageTexture.create_from_image(img))
	mat.set_shader_parameter(&"ready", 1.0)
