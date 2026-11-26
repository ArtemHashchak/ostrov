class_name WetBody
extends RefCounted
## Мокрые персонажи (v5, агент D). У каждого персонажа (group characters) — сырость 0..1 в meta
## &"wetness": купание — сразу 1, дождь — растёт до силы дождя, сохнет (на солнце и ветру быстрее).
## Видно: руки от первого лица блестят и в каплях (fp_skin.wet), с мокрого капает (частицы у тела),
## мокрые следы на камне и досках (тёмные отпечатки, высыхают за ~30 с). Сырость читают и механики
## (температура, порох): n.get_meta(&"wetness", 0.0).

const DRY_BASE := 1.0 / 420.0      # в тени без ветра — ~7 мин
const DRY_SUN := 1.0 / 150.0       # на солнце добавочно
const DRY_WIND := 1.0 / 900.0      # за каждый м/с ветра
const PRINT_LIFE := 30.0
const MAX_PRINTS := 60
const PRINT_STRIDE := 0.75

static var _prints: Array = []     # [Decal, age]
static var _last: Dictionary = {}  # id -> {pos, side}
static var _tex: Texture2D

static func of(n: Node) -> float:
	return float(n.get_meta(&"wetness", 0.0)) if n else 0.0

static func update(tree: SceneTree, dt: float, rain: float, sun_k: float, wind: float, cam: Camera3D) -> void:
	if tree == null:
		return
	var dry := (DRY_BASE + DRY_SUN * sun_k + DRY_WIND * wind) * dt
	for n in tree.get_nodes_in_group(&"characters"):
		var nd := n as Node3D
		if nd == null or not is_instance_valid(nd):
			continue
		var w := of(nd)
		if nd.get("swimming") == true:
			w = 1.0
		elif rain > 0.02:
			w = maxf(w, minf(w + rain * dt / 20.0, rain))
		else:
			w = maxf(0.0, w - dry)
		nd.set_meta(&"wetness", w)
		var near := cam != null and cam.global_position.distance_to(nd.global_position) < 30.0
		_drips(nd, w if near and nd.get("swimming") != true else 0.0)
		if nd.is_in_group(&"player"):
			var hands = nd.get("hands")
			if hands:
				var sm = hands.get("_skin_mat")
				if sm is ShaderMaterial:
					(sm as ShaderMaterial).set_shader_parameter(&"wet", w)
		if near and w > 0.3 and nd.get("swimming") != true:
			_wet_prints(nd, w)
	_age_prints(tree, dt)

static func _drips(nd: Node3D, w: float) -> void:
	var p := nd.get_node_or_null(^"WetDrips") as CPUParticles3D
	if w < 0.2:
		if p:
			p.emitting = false
		return
	if p == null:
		p = CPUParticles3D.new()
		p.name = "WetDrips"
		p.amount = 14
		p.lifetime = 0.55
		p.local_coords = false
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = Vector3(0.22, 0.5, 0.15)
		p.position = Vector3(0, 0.9, 0)
		p.direction = Vector3.DOWN
		p.spread = 5.0
		p.initial_velocity_min = 0.2
		p.initial_velocity_max = 0.6
		p.gravity = Vector3(0, -9.8, 0)
		p.scale_amount_min = 0.008
		p.scale_amount_max = 0.016
		var m := SphereMesh.new()
		m.radius = 0.5
		m.height = 1.4
		m.radial_segments = 6
		m.rings = 3
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.85, 0.92, 1.0, 0.55)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness = 0.05
		mat.metallic_specular = 0.9
		m.material = mat
		p.mesh = m
		nd.add_child(p)
	p.emitting = true
	# у CPUParticles3D нет amount_ratio: сила капели — через скорость выпуска
	p.speed_scale = clampf((w - 0.2) / 0.8, 0.1, 1.0)

static func _ground_is_hard(nd: Node3D) -> bool:
	var w := nd.get_tree().get_first_node_in_group(&"world")
	if w == null or not w.has_method(&"biome_at"):
		return true
	var g := nd.global_position
	var b: StringName = w.biome_at(g.x, g.z)
	# песок пляжа рисует SandTracks; мокрые следы — на камне, досках, траве у воды
	return b != &"beach" and b != &"water"

static func _wet_prints(nd: Node3D, w: float) -> void:
	var id := nd.get_instance_id()
	var g := nd.global_position
	var st: Dictionary = _last.get(id, {})
	if st.is_empty():
		_last[id] = {"pos": g, "side": 0}
		return
	var d: Vector3 = g - st.pos
	d.y = 0.0
	if d.length() < PRINT_STRIDE:
		return
	st.pos = g
	st.side = 1 - int(st.side)
	if not _ground_is_hard(nd) and not _on_deck(nd):
		return
	var dir := d.normalized()
	var right := Vector3(-dir.z, 0, dir.x)
	var dc := Decal.new()
	if _tex == null:
		_tex = _make_tex()
	dc.texture_albedo = _tex
	dc.size = Vector3(0.13, 0.4, 0.3)
	dc.modulate = Color(0.0, 0.0, 0.0, 0.42 * w)
	dc.albedo_mix = 1.0
	dc.cull_mask = 1
	nd.get_parent().add_child(dc)
	dc.global_position = g + right * (0.1 if int(st.side) == 1 else -0.1) + Vector3(0, 0.05, 0)
	dc.look_at(dc.global_position + dir, Vector3.UP)
	_prints.append([dc, 0.0, 0.42 * w])
	while _prints.size() > MAX_PRINTS:
		var e: Array = _prints.pop_front()
		if is_instance_valid(e[0]):
			(e[0] as Node).queue_free()

static func _on_deck(nd: Node3D) -> bool:
	for r in nd.get_tree().get_nodes_in_group(&"raft_deck"):
		if (r as Node3D).global_position.distance_to(nd.global_position) < 2.0:
			return true
	return false

static func _age_prints(tree: SceneTree, dt: float) -> void:
	var keep: Array = []
	for e: Array in _prints:
		var dc := e[0] as Decal
		if dc == null or not is_instance_valid(dc):
			continue
		e[1] = float(e[1]) + dt
		var k := 1.0 - float(e[1]) / PRINT_LIFE
		if k <= 0.0:
			dc.queue_free()
			continue
		dc.modulate.a = float(e[2]) * k
		keep.append(e)
	_prints = keep

static func print_count() -> int:
	return _prints.size()

## Тёмный овал ступни (мягкий край) — альфа-маска декали.
static func _make_tex() -> Texture2D:
	var n := 32
	var img := Image.create(n, n * 2, false, Image.FORMAT_RGBA8)
	for y in n * 2:
		for x in n:
			var u := (x + 0.5) / n * 2.0 - 1.0
			var v := (y + 0.5) / (n * 2) * 2.0 - 1.0
			var heel := Vector2(u / 0.75, (v - 0.55) / 0.4).length()
			var ball := Vector2(u / 0.9, (v + 0.25) / 0.5).length()
			var a := maxf(1.0 - smoothstep(0.7, 1.0, heel), 1.0 - smoothstep(0.7, 1.0, ball))
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)
