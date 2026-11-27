class_name ShoreSeaweed
extends Node3D
## v5.2 (агент O, мелочь 23.11 «водоросли сохнут на отливе»): пучки водорослей в приливной
## полосе пляжей вокруг игрока. Под водой — тёмные, блестящие, мокрые; на воздухе после
## отлива за ~3 мин светлеют до буро-соломенных, теряют блеск и чуть съёживаются; прилив
## снова их намачивает. Один MultiMesh на чанк 48 м, сухость — INSTANCE_CUSTOM.r.

const CHUNK := 48.0
const STREAM_R := 70.0
const DRY_TIME := 180.0       # с — от мокрых до сухих на воздухе
const WET_TIME := 6.0         # с — намокают под водой
const TICK := 0.5

var world: Node
var _chunks: Dictionary = {}  # Vector2i → {mmi, pos: PackedVector3Array, dry: PackedFloat32Array}
var _t := 0.0
var stats := {"clumps": 0, "chunks": 0}
static var _mesh: ArrayMesh
static var _mat: ShaderMaterial

const SHADER := """
shader_type spatial;
render_mode cull_disabled;
varying float v_dry;
void vertex() {
	v_dry = INSTANCE_CUSTOM.r;
	// сохнет — съёживается и прижимается к песку
	VERTEX.xz *= mix(1.0, 0.82, v_dry);
	VERTEX.y *= mix(1.0, 0.55, v_dry);
}
void fragment() {
	vec3 wet = vec3(0.10, 0.13, 0.05) * (0.8 + 0.4 * COLOR.r);
	vec3 dry = vec3(0.42, 0.33, 0.20) * (0.8 + 0.4 * COLOR.r);
	ALBEDO = mix(wet, dry, smoothstep(0.0, 1.0, v_dry));
	ROUGHNESS = mix(0.18, 0.92, v_dry);
	SPECULAR = mix(0.75, 0.35, v_dry);
}
"""

func _ready() -> void:
	add_to_group(&"shore_seaweed")
	set_process(true)

## Сухость в точке пучка ближайшего (тесты/зонды): -1 — нет.
func dryness_near(p: Vector3, r: float = 2.0) -> float:
	for k in _chunks:
		var c: Dictionary = _chunks[k]
		var ps: PackedVector3Array = c.pos
		for i in ps.size():
			if Vector2(ps[i].x - p.x, ps[i].z - p.z).length() < r:
				return (c.dry as PackedFloat32Array)[i]
	return -1.0

func _process(delta: float) -> void:
	_t += delta
	if _t < TICK:
		return
	var dt := _t
	_t = 0.0
	if world == null:
		return
	var cp: Variant = _player_pos()
	if cp == null:
		return
	_stream(cp as Vector3)
	var wl := float(world.call(&"water_level"))
	for k in _chunks:
		_update(_chunks[k], wl, dt)

func _player_pos() -> Variant:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	for n in get_tree().get_nodes_in_group(&"player"):
		if n is Node3D:
			return (n as Node3D).global_position
	return cam.global_position if cam else null

func _stream(cp: Vector3) -> void:
	var c0 := Vector2i(int(floor((cp.x - STREAM_R) / CHUNK)), int(floor((cp.z - STREAM_R) / CHUNK)))
	var c1 := Vector2i(int(floor((cp.x + STREAM_R) / CHUNK)), int(floor((cp.z + STREAM_R) / CHUNK)))
	var built := 0
	for j in range(c0.y, c1.y + 1):
		for i in range(c0.x, c1.x + 1):
			var k := Vector2i(i, j)
			if not _chunks.has(k) and built < 2:
				_chunks[k] = _gen(k)
				built += 1
	for k in _chunks.keys():
		var cc := Vector2((k.x + 0.5) * CHUNK, (k.y + 0.5) * CHUNK)
		if cc.distance_to(Vector2(cp.x, cp.z)) > STREAM_R + CHUNK * 1.5:
			var c: Dictionary = _chunks[k]
			if c.mmi:
				(c.mmi as Node).queue_free()
			_chunks.erase(k)
	stats.chunks = _chunks.size()

## Пучки — в приливной полосе пляжа: высота между малой и полной водой (+чуть выше — выброс).
func gen_chunk_for_test(k: Vector2i) -> Dictionary:
	return _gen(k)

func _gen(k: Vector2i) -> Dictionary:
	var amp := float(world.get(&"tide_amplitude")) if world.get(&"tide_amplitude") != null else 0.8
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(k.x, k.y, 5151))
	var pos := PackedVector3Array()
	var xfs: Array = []
	var n := 0
	var step := 2.2
	for j in int(CHUNK / step):
		for i in int(CHUNK / step):
			var x := k.x * CHUNK + (i + rng.randf()) * step
			var z := k.y * CHUNK + (j + rng.randf()) * step
			var h := float(world.call(&"height_at", x, z))
			if h < -amp + 0.08 or h > amp + 0.25:
				continue
			if world.has_method(&"zone_at"):
				var zn: StringName = world.call(&"zone_at", x, z)
				if zn != &"beach" and zn != &"shallows" and zn != &"dunes" and zn != &"rocks":
					continue
			if rng.randf() > 0.07:
				continue
			# кучкой: 1–4 пучка рядом
			for q in rng.randi_range(1, 4):
				var p := Vector3(x + rng.randf_range(-0.6, 0.6), 0.0, z + rng.randf_range(-0.6, 0.6))
				p.y = float(world.call(&"height_at", p.x, p.z)) + 0.01
				pos.append(p)
				xfs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.6, 1.25)), p))
				n += 1
	var dry := PackedFloat32Array()
	dry.resize(pos.size())
	var wl := float(world.call(&"water_level"))
	for i in pos.size():
		dry[i] = 1.0 if pos[i].y > wl + 0.3 else 0.0
	var out := {"mmi": null, "pos": pos, "dry": dry}
	if n == 0:
		return out
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _clump_mesh()
	mm.instance_count = n
	for i in n:
		mm.set_instance_transform(i, xfs[i])
		mm.set_instance_custom_data(i, Color(dry[i], 0, 0, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Seaweed_%d_%d" % [k.x, k.y]
	mmi.multimesh = mm
	mmi.material_override = _material()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = STREAM_R + 10.0
	add_child(mmi)
	out.mmi = mmi
	stats.clumps = int(stats.clumps) + n
	return out

func _update(c: Dictionary, wl: float, dt: float) -> void:
	var ps: PackedVector3Array = c.pos
	var dry: PackedFloat32Array = c.dry
	var mm: MultiMesh = (c.mmi as MultiMeshInstance3D).multimesh if c.mmi else null
	for i in ps.size():
		var d := dry[i]
		var nd := d
		if ps[i].y < wl + 0.02:
			nd = maxf(0.0, d - dt / WET_TIME)
		else:
			nd = minf(1.0, d + dt / DRY_TIME)
		if absf(nd - d) > 0.0001:
			dry[i] = nd
			if mm:
				mm.set_instance_custom_data(i, Color(nd, 0, 0, 0))
	c.dry = dry

static func _material() -> ShaderMaterial:
	if _mat == null:
		var sh := Shader.new()
		sh.code = SHADER
		_mat = ShaderMaterial.new()
		_mat.shader = sh
	return _mat

## Пучок: 7 плоских лент-«ламинарий», разбросанных лучами, лежат на песке с изгибом.
static func _clump_mesh() -> ArrayMesh:
	if _mesh:
		return _mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for b in 7:
		var a := b * TAU / 7.0 + rng.randf_range(-0.3, 0.3)
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x)
		var L := rng.randf_range(0.35, 0.7)
		var W := rng.randf_range(0.05, 0.09)
		var shade := rng.randf_range(0.6, 1.0)
		var segs := 5
		for s in segs:
			var t0 := float(s) / segs
			var t1 := float(s + 1) / segs
			var p0 := dir * L * t0 + Vector3(0, 0.03 * sin(t0 * PI) + 0.01, 0) + side * sin(t0 * 5.0 + b) * 0.04
			var p1 := dir * L * t1 + Vector3(0, 0.03 * sin(t1 * PI) + 0.01, 0) + side * sin(t1 * 5.0 + b) * 0.04
			var w0 := W * (1.0 - t0 * 0.6)
			var w1 := W * (1.0 - t1 * 0.6)
			var c := Color(shade, 0, 0)
			for v in [p0 - side * w0, p0 + side * w0, p1 + side * w1, p0 - side * w0, p1 + side * w1, p1 - side * w1]:
				st.set_color(c)
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
	_mesh = st.commit()
	return _mesh
