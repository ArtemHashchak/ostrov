extends SeasonEvent
## Нашествие красных крабов (как на острове Рождества): сотни крабов идут из джунглей к морю
## через остров. Дёшево: один MultiMesh (модель краба игры, перекрашенная в ярко-красный),
## движение на CPU по рельефу, «семенящая» походка — в шейдере. Поток замедляет (Area3D группы
## soft_plant, speed_mul), удар по крабам у ног — добыча (crab_meat), боты в потоке собирают сами.
## Факт «краб пойман» → SeasonEvents.game_fact (задания зрителей).

const SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 tint : source_color = vec4(0.78, 0.12, 0.06, 1.0);
uniform vec4 belly : source_color = vec4(0.95, 0.55, 0.35, 1.0);
varying float v_shade;
void vertex() {
	float ph = INSTANCE_CUSTOM.x * 6.2831;
	float run = INSTANCE_CUSTOM.y;
	// ноги/корпус семенят: подскок и покачивание (только при движении)
	float bob = abs(sin(TIME * 22.0 + ph)) * 0.012 * run;
	float sway = sin(TIME * 11.0 + ph) * 0.06 * run;
	VERTEX.y += bob;
	VERTEX.x += sway * VERTEX.y * 0.6;
	v_shade = clamp(VERTEX.y * 6.0 + 0.6, 0.0, 1.0);
}
void fragment() {
	ALBEDO = mix(belly.rgb, tint.rgb, v_shade);
	ROUGHNESS = 0.42;
	SPECULAR = 0.55;
}
"""

var mm: MultiMesh
var mmi: MultiMeshInstance3D
var island: Dictionary = {}
var crabs: Array[Dictionary] = []   # {p: Vector2, d: Vector2, s: float, ph: float, alive: bool}
var reached := 0
var caught := 0
var _area: Area3D
var _shape: CylinderShape3D
var _bot_t := 0.0
var _scale := 1.0
var _y_off := 0.0
var _src_ang := 0.0
var _spawned := 0

func begin() -> void:
	var w := world()
	if w == null:
		done = true
		return
	island = _pick_island(w)
	if island.is_empty():
		done = true
		return
	var mesh := _crab_mesh()
	if mesh == null:
		done = true
		return
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	var n := int(cfg.get("count", 420))
	mm.instance_count = n
	mm.visible_instance_count = n
	mmi = MultiMeshInstance3D.new()
	mmi.name = "RedCrabs"
	mmi.multimesh = mm
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	sm.shader = sh
	mmi.material_override = sm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	mmi.global_transform = Transform3D.IDENTITY
	_src_ang = rng.randf() * TAU
	for i in n:
		crabs.append(_new_crab(w, true))
	_spawned = n
	# зона замедления
	_area = Area3D.new()
	_area.name = "RedCrabsSlow"
	_area.add_to_group(&"soft_plant")
	_area.set_meta(&"speed_mul", float(cfg.get("slow_mul", 0.62)))
	_area.set_meta(&"red_crabs", true)
	_area.monitoring = false
	_area.collision_layer = 1 << 19
	_area.collision_mask = 0
	var cs := CollisionShape3D.new()
	_shape = CylinderShape3D.new()
	_shape.height = 1.2
	_shape.radius = 10.0
	cs.shape = _shape
	_area.add_child(cs)
	add_child(_area)
	Events.player_swing.connect(_on_swing)
	say(host_line("red_crabs", [String(island.get("name", "?"))]))
	_update(w, 0.0)

func _pick_island(w: Node) -> Dictionary:
	var p := player()
	var best := {}
	var bd := INF
	for I: Dictionary in w.call(&"islands"):
		var r := float(I.radius)
		if r < 45.0:
			continue
		var c: Vector2 = I.center
		var d := c.distance_to(Vector2(p.global_position.x, p.global_position.z)) if p else rng.randf() * 1000.0
		# свой/ближайший остров, но не скалу
		if String(I.get("kind", "")) == "rocky":
			d += 400.0
		if d < bd:
			bd = d
			best = I
	if cfg.has("island_id"):
		for I: Dictionary in w.call(&"islands"):
			if int(I.id) == int(cfg.island_id):
				return I
	return best

## Меш краба игры (самая крупная часть модели), масштаб — до crab_len_m.
func _crab_mesh() -> Mesh:
	var model := AnimalModels.build(&"crab")
	if model == null:
		return null
	var best: MeshInstance3D = null
	var best_xf := Transform3D.IDENTITY
	var bv := -1.0
	var stack: Array = [[model, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var e: Array = stack.pop_back()
		var n: Node = e[0]
		var xf: Transform3D = e[1]
		if n is Node3D:
			xf = xf * (n as Node3D).transform
		if n is MeshInstance3D and (n as MeshInstance3D).mesh:
			var ab := (n as MeshInstance3D).mesh.get_aabb()
			var v := ab.size.x * ab.size.y * ab.size.z
			if v > bv:
				bv = v
				best = n
				best_xf = xf
		for c in n.get_children():
			stack.append([c, xf])
	if best == null:
		model.free()
		return null
	# запекаем трансформ части в копию меша
	var src := best.mesh
	var st := SurfaceTool.new()
	var am := ArrayMesh.new()
	for si in src.get_surface_count():
		st.clear()
		st.create_from(src, si)
		var arr := st.commit_to_arrays()
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		for i in verts.size():
			verts[i] = best_xf * verts[i]
		for i in norms.size():
			norms[i] = (best_xf.basis * norms[i]).normalized()
		arr[Mesh.ARRAY_VERTEX] = verts
		if not norms.is_empty():
			arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_BONES] = null
		arr[Mesh.ARRAY_WEIGHTS] = null
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	model.free()
	var ab2 := am.get_aabb()
	var L := maxf(ab2.size.x, ab2.size.z)
	_scale = float(cfg.get("crab_len_m", 0.16)) / maxf(L, 0.001)
	_y_off = -ab2.position.y * _scale
	return am

func _new_crab(w: Node, first: bool) -> Dictionary:
	var c: Vector2 = island.center
	var r := float(island.radius)
	var dir := Vector2(cos(_src_ang), sin(_src_ang))
	var side := Vector2(-dir.y, dir.x)
	# старт — полоса в глубине острова, со стороны, противоположной морю назначения
	var along := rng.randf_range(-0.55, 0.1) * r if first else rng.randf_range(-0.6, -0.45) * r
	var across := rng.randf_range(-0.45, 0.45) * r
	var p := c + dir * along + side * across
	var tries := 0
	while not bool(w.call(&"is_land", p.x, p.y)) and tries < 12:
		p = c + dir * rng.randf_range(-0.5, 0.0) * r + side * rng.randf_range(-0.4, 0.4) * r
		tries += 1
	var sr: Array = cfg.get("speed", [0.25, 0.55])
	return {"p": p, "d": (dir + side * rng.randf_range(-0.25, 0.25)).normalized(),
		"s": rng.randf_range(float(sr[0]), float(sr[1])), "ph": rng.randf(), "alive": true, "stop": 0.0}

func step(dt: float) -> void:
	var w := world()
	if w == null or mm == null:
		return
	_update(w, dt)
	_bot_t -= dt
	if _bot_t <= 0.0:
		_bot_t = 2.0
		_bots_collect()
	var alive_n := 0
	for c in crabs:
		if c.alive:
			alive_n += 1
	if alive_n == 0:
		done = true

func _update(w: Node, dt: float) -> void:
	var wl := float(w.call(&"water_level"))
	var cen := Vector2.ZERO
	var cnt := 0
	var dir := Vector2(cos(_src_ang), sin(_src_ang))
	var refill := t < duration * 0.6
	for i in crabs.size():
		var c: Dictionary = crabs[i]
		if not c.alive:
			if refill and rng.randf() < dt * 0.25:
				crabs[i] = _new_crab(w, false)
				_spawned += 1
			else:
				mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), Vector3(0, -500, 0)))
			continue
		var p: Vector2 = c.p
		var d: Vector2 = c.d
		# поток: в целом к морю, с блужданием; изредка замирают
		c.stop = maxf(0.0, float(c.stop) - dt)
		if float(c.stop) <= 0.0 and rng.randf() < dt * 0.05:
			c.stop = rng.randf_range(0.6, 2.5)
		var run := 0.0 if float(c.stop) > 0.0 else 1.0
		d = (d + dir * dt * 0.4 + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * dt * 0.8).normalized()
		p += d * float(c.s) * dt * run
		c.d = d
		c.p = p
		var h := float(w.call(&"height_at", p.x, p.y))
		if h < wl - 0.05:
			c.alive = false
			reached += 1
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), Vector3(0, -500, 0)))
			continue
		var yaw := atan2(d.x, d.y) + PI * 0.5   # краб ходит боком
		var b := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * _scale)
		mm.set_instance_transform(i, Transform3D(b, Vector3(p.x, h + _y_off + 0.01, p.y)))
		mm.set_instance_custom_data(i, Color(float(c.ph), run, 0, 0))
		cen += p
		cnt += 1
	if cnt > 0 and _area:
		cen /= float(cnt)
		var rad := 4.0
		for c in crabs:
			if c.alive:
				rad = maxf(rad, (c.p as Vector2).distance_to(cen))
		_shape.radius = minf(rad * 0.85, 60.0)
		_area.global_position = Vector3(cen.x, float(w.call(&"height_at", cen.x, cen.y)), cen.y)

## Удар по крабам у ног — добыча.
func _on_swing(p: Node, hit: Dictionary) -> void:
	if not (p is Node3D):
		return
	var pt: Vector3
	if hit.has("position"):
		pt = hit.position
	else:
		var cam := p.get(&"camera") as Camera3D
		var fwd := -(cam.global_basis.z if cam else (p as Node3D).global_basis.z)
		pt = (p as Node3D).global_position + Vector3(fwd.x, 0, fwd.z).normalized() * 1.3
	catch_at(p, pt, int(cfg.get("harvest_per_hit", 3)))

func catch_at(by: Node, pt: Vector3, n: int) -> int:
	var got := 0
	for i in crabs.size():
		if got >= n:
			break
		var c: Dictionary = crabs[i]
		if c.alive and (c.p as Vector2).distance_to(Vector2(pt.x, pt.z)) < 1.4:
			c.alive = false
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), Vector3(0, -500, 0)))
			got += 1
	if got > 0:
		caught += got
		var inv := BuildEnv.inventory(by)
		if inv and inv.has_method(&"add"):
			inv.call(&"add", &"crab_meat", got)
		if by.is_in_group(&"player"):
			Events.toast.emit("Поймал красных крабов ×%d" % got)
		if director and director.has_signal(&"game_fact"):
			director.emit_signal(&"game_fact", &"crab_caught", by, {"n": got})
	return got

func _bots_collect() -> void:
	if _area == null:
		return
	var c := _area.global_position
	for b in get_tree().get_nodes_in_group(&"bots"):
		if b is Node3D and alive(b) and (b as Node3D).global_position.distance_to(c) < _shape.radius + 1.0:
			if rng.randf() < 0.5:
				catch_at(b, (b as Node3D).global_position, 1)

func finish() -> void:
	if Events.player_swing.is_connected(_on_swing):
		Events.player_swing.disconnect(_on_swing)
	super.finish()

func alive_count() -> int:
	var n := 0
	for c in crabs:
		if c.alive:
			n += 1
	return n

func hud_line() -> String:
	return "Красные крабы: остров «%s», %d в пути (%s)" % [String(island.get("name", "?")), alive_count(), left_text()]

func markers(_viewer: Node) -> Array[Dictionary]:
	if _area == null:
		return []
	return [{"pos": _area.global_position, "color": Color(0.9, 0.2, 0.1), "kind": &"event", "label": "Красные крабы"}]
