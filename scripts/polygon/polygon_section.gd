class_name PolygonSection
extends Node3D
## Один раздел музея полигона. Строится, когда игрок рядом, и целиком удаляется,
## когда он ушёл (PolygonStreamer): в памяти держится только ближний раздел.
## Стенды — модель неподвижна (для осмотра) на низком постаменте с подписью;
## «живые» участки — вольеры, птичники, террариумы, грядки, рощи, сетки в море.
## Все созданные чужими модулями узлы (Fauna, CreatureSpawner, BuildModule) — в owned.

signal built

const P = preload("res://scripts/sandbox/sandbox_props.gd")
const STEP_BUDGET_MS := 6.0     # сколько мс за кадр тратить на постройку

var sec: Dictionary
var owned: Array = []           # узлы вне этого корня, которые надо удалить вместе с разделом
var is_built := false
var replay_mode := false        # в реплее: без «живых» существ (их водит запись)
var stats := {"stands": 0, "plots": 0, "nodes": 0, "ms": 0}
var dummies: Array = []
var _tables: Array = []         # {pos, id, n, node}
var _freeze: Array = []         # узлы, которые «заморозить» через пару кадров (стенды существ)

func setup(s: Dictionary) -> PolygonSection:
	sec = s
	name = "Section_" + String(s.id)
	return self

func ground(x: float, z: float) -> float:
	return P.ground(x, z)

func _own(n: Node) -> void:
	if n:
		owned.append(n)

## Постройка с ограничением по времени на кадр (без долгих подвисаний).
func build() -> void:
	var t0 := Time.get_ticks_msec()
	var tf := Time.get_ticks_usec()
	var tree := get_tree()
	var title: Vector2 = sec.get("title", Vector2.ZERO)
	P.signpost(self, title.x, title.y, String(sec.name).to_upper(), "%d моделей · F1 — меню полигона" % int(sec.count))
	for st: Dictionary in sec.stands:
		_stand(st)
		stats.stands += 1
		if Time.get_ticks_usec() - tf > STEP_BUDGET_MS * 1000.0:
			await tree.process_frame
			if _gone():
				return
			tf = Time.get_ticks_usec()
	for tb: Dictionary in sec.get("tables", []):
		_table(tb)
		await tree.process_frame
		if _gone():
			return
		tf = Time.get_ticks_usec()
	if sec.id == &"buildings":
		for pl: Dictionary in sec.plots:
			var bp2: Vector2 = pl.pos
			var e2: Dictionary = pl.ex
			var did := StringName((e2.entry as Dictionary).def)
			var info2: Dictionary = BuildDefs.INFO.get(did, {})
			var note := ""
			if bool(info2.get("socket_only", false)):
				note = "\n(на доме рядом)"
			elif info2.get("kind", &"") == &"raft":
				note = "\n(мост — в разделе «Море»)"
			else:
				_build_node(did, Vector3(bp2.x, ground(bp2.x, bp2.y), bp2.y))
			_label(bp2.x, bp2.y + 4.2, ground(bp2.x, bp2.y) + (3.6 if note == "" else 1.4), String(e2.name) + note)
			stats.plots += 1
	elif not replay_mode:
		for pl: Dictionary in sec.plots:
			_plot(pl)
			stats.plots += 1
			if Time.get_ticks_usec() - tf > STEP_BUDGET_MS * 1000.0:
				await tree.process_frame
				if _gone():
					return
				tf = Time.get_ticks_usec()
	else:
		for pl: Dictionary in sec.plots:
			_plot_frame(pl)
	match sec.id:
		&"weapons":
			_range()
		&"buildings":
			_house()
		&"sea":
			_sea()
	# заморозить стендовые экземпляры (поза — кадр после появления)
	for i in 3:
		await tree.process_frame
	if _gone():
		return
	for n in _freeze:
		if is_instance_valid(n):
			_freeze_node(n as Node)
	stats.ms = Time.get_ticks_msec() - t0
	stats.nodes = _count(self)
	is_built = true
	built.emit()

func _gone() -> bool:
	return not is_instance_valid(self) or is_queued_for_deletion() or not is_inside_tree()

func unload() -> void:
	for n in owned:
		if is_instance_valid(n) and not (n as Node).is_queued_for_deletion():
			(n as Node).queue_free()
	owned.clear()
	queue_free()

static func _count(n: Node) -> int:
	var c := 1
	for k in n.get_children():
		c += _count(k)
	return c

# ------------------------------------------------------------ стенды

func _plinth(x: float, z: float, w: float, h: float = 0.3) -> float:
	var g := ground(x, z)
	var body := StaticBody3D.new()
	add_child(body)
	body.global_position = Vector3(x, g, z)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, h, w)
	mi.mesh = bm
	mi.material_override = HeldModels.pbr("weathered_planks", Vector3(1, 1, 1), Color(0.86, 0.8, 0.72))
	mi.position.y = h * 0.5
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = bm.size
	cs.shape = bs
	cs.position.y = h * 0.5
	body.add_child(cs)
	return g + h

func _label(x: float, z: float, y: float, text: String) -> void:
	var l := P.label(self, Vector3(x, y, z), text, 34, P.SIGN_COLOR, 46.0)
	l.pixel_size = 0.0038

func _stand(st: Dictionary) -> void:
	var e: Dictionary = st.ex
	var p: Vector2 = st.pos
	var sz: Vector3 = e.size
	var big: bool = e.section == &"trees" or e.section == &"buildings"
	var top := ground(p.x, p.y)
	if sec.id != &"sea" and not big:
		top = _plinth(p.x, p.y, clampf(maxf(sz.x, sz.z) + 0.6, 1.2, 6.0), 0.25 if sz.y > 1.0 else 0.5)
	var n: Node3D = null
	match String(e.src):
		"catalog":
			if bool(e.get("ground", false)):
				n = _swatch(e)
			else:
				n = _catalog_node(String(e.id))
		"spawner":
			n = _spawner_node(e, Vector3(p.x, top, p.y), true)
		"build":
			n = _build_node(StringName((e.entry as Dictionary).def), Vector3(p.x, top, p.y))
	if n and n.get_parent() == null:
		add_child(n)
		n.global_position = Vector3(p.x, top, p.y)
		n.rotation.y = deg_to_rad(-25.0)
	var label_y := top + clampf(sz.y, 0.4, 10.0) + 0.5
	if sec.id == &"sea":
		label_y = ground(p.x, p.y) + 0.6
	_label(p.x, p.y + (0.0 if sec.id == &"sea" else maxf(sz.z, 0.8) * 0.5 + 0.5), label_y if sec.id != &"sea" else 1.9,
		String(e.name))

func _catalog_node(id: String) -> Node3D:
	var cs := PolygonExhibits.catalog_script()
	if cs == null:
		return null
	var n: Variant = cs.call(&"instantiate", id, 0)
	if not (n is Node3D):
		return null
	var col: Variant = cs.call(&"make_collider", id)
	if col is Node3D:
		(n as Node3D).add_child(col as Node3D)
	return n as Node3D

## Образец грунта: плитка 2.4×2.4 м с текстурой из каталога.
func _swatch(e: Dictionary) -> Node3D:
	var tex: Dictionary = (e.entry as Dictionary).get("tex", {})
	var m := StandardMaterial3D.new()
	if tex.has("albedo") and ResourceLoader.exists(String(tex.albedo)):
		m.albedo_texture = load(String(tex.albedo))
	if tex.has("normal") and ResourceLoader.exists(String(tex.normal)):
		m.normal_enabled = true
		m.normal_texture = load(String(tex.normal))
	if tex.has("roughness") and ResourceLoader.exists(String(tex.roughness)):
		m.roughness_texture = load(String(tex.roughness))
	m.uv1_scale = Vector3(1.2, 1.2, 1.2)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.4, 2.4)
	mi.mesh = pm
	mi.material_override = m
	mi.position.y = 0.01
	var root := Node3D.new()
	root.add_child(mi)
	return root

func _spawner_node(e: Dictionary, pos: Vector3, frozen: bool) -> Node3D:
	var sp := CreatureSpawner.instance()
	if sp == null:
		return null
	var info: Dictionary = e.entry
	var n: Node = sp.call(&"_spawn_one", info, pos, 0.0)
	if n == null:
		return null
	_own(n)
	if n is Node3D and (n as Node3D).is_inside_tree() and String(info.get("cat", "")) != "sea" and String(info.get("cat", "")) != "birds":
		(n as Node3D).global_position.y = maxf((n as Node3D).global_position.y, pos.y)
	if frozen:
		n.set_meta(&"polygon_stand", true)
		_freeze.append(n)
	return n as Node3D

func _freeze_node(n: Node) -> void:
	n.process_mode = Node.PROCESS_MODE_DISABLED
	if n is CharacterBody3D:
		(n as CharacterBody3D).velocity = Vector3.ZERO
	if n is RigidBody3D:
		(n as RigidBody3D).freeze = true

func _build_node(def_id: StringName, pos: Vector3) -> Node3D:
	var bm := BuildModule.instance()
	if bm == null:
		return null
	if bool((BuildDefs.INFO.get(def_id, {}) as Dictionary).get("socket_only", false)) or \
			(BuildDefs.INFO.get(def_id, {}) as Dictionary).get("kind", &"") == &"raft":
		return null      # дверь/крыша — в доме, секции моста — в разделе «Море»
	var bp := bm.place_blueprint(def_id, Transform3D(Basis(Vector3.UP, 0.4), pos), 0)
	if bp:
		_complete(bp)
		_own(bp)
	return null

static func _complete(bp: Blueprint) -> void:
	if bp == null:
		return
	var need := bp.needs_left()
	for t: StringName in need:
		bp.add_material(t, int(need[t]))

# ------------------------------------------------------------ живые участки

func _plot(pl: Dictionary) -> void:
	var e: Dictionary = pl.ex
	var p: Vector2 = pl.pos
	var s: float = pl.size
	var g := ground(p.x, p.y)
	match sec.id:
		&"animals":
			P.pen(self, p.x, p.y, s * 0.5, 1.4)
			for i in 2:
				_live(e, Vector3(p.x + (i - 0.5) * 2.0, g + 0.3, p.y), s * 0.22)
		&"birds":
			_aviary(p, s * 0.5)
			for i in 3:
				_live(e, Vector3(p.x + (i - 1) * 1.5, g + 2.0, p.y), s * 0.2)
		&"small":
			_terrarium(p, s * 0.5)
			for i in 2:
				_live(e, Vector3(p.x + (i - 0.5) * 1.2, g + 0.2, p.y), s * 0.2)
		&"plants", &"rocks":
			_bed(p, s)
			for i in 5:
				var a := TAU * i / 5.0
				var q := p + Vector2(cos(a), sin(a)) * s * 0.28
				_live(e, Vector3(q.x, ground(q.x, q.y), q.y), 0.0)
		&"trees":
			for i in 2:
				var q := p + Vector2((i - 0.5) * s * 0.45, 0.0)
				_live(e, Vector3(q.x, ground(q.x, q.y), q.y), 0.0)
		&"sea":
			_net_pen(p, s * 0.5)
			var n := 1 if String(e.id).begins_with("shark") or String(e.name).to_lower().contains("акул") else 4
			for i in n:
				_live(e, Vector3(p.x, PolygonLayout.SHELF_DEPTH * 0.5, p.y), s * 0.3)
	_label(p.x, p.y - s * 0.5 - 0.6, g + (2.0 if sec.id != &"sea" else 1.9), String(e.name))

## Лёгкая рамка участка для кадров реплея (без существ).
func _plot_frame(pl: Dictionary) -> void:
	var p: Vector2 = pl.pos
	var s: float = pl.size
	match sec.id:
		&"animals":
			P.pen(self, p.x, p.y, s * 0.5, 1.4)
		&"birds":
			_aviary(p, s * 0.5)
		&"small":
			_terrarium(p, s * 0.5)
		&"sea":
			_net_pen(p, s * 0.5)
		&"plants", &"rocks", &"trees":
			_plot(pl)

func _live(e: Dictionary, pos: Vector3, home_r: float) -> void:
	var n: Node3D = null
	if String(e.src) == "spawner":
		var info: Dictionary = e.entry
		if String(info.get("src", "")) == "fauna" and Fauna.instance():
			var a := Fauna.instance().spawn(StringName(info.id), pos, maxf(home_r, 1.0))
			_own(a)
			n = a
		else:
			n = _spawner_node(e, pos, false)
			if n:
				n.set_meta(&"replay_spawn", {"type": "spawner", "id": String(info.id)})
	elif String(e.src) == "catalog":
		# виды каталога, которые знает реестр существ — с поведением; иначе — модель
		var found := CreatureSpawner.find(String(e.id))
		if not found.is_empty() and e.section in [&"animals", &"birds", &"small", &"sea"]:
			n = _spawner_node({"entry": found}, pos, false)
			if n:
				n.set_meta(&"replay_spawn", {"type": "spawner", "id": String(found.id)})
		else:
			n = _catalog_node(String(e.id))
			if n:
				add_child(n)
				n.global_position = pos
				n.rotation.y = randf() * TAU
	if n:
		n.set_meta(&"polygon_live", true)
		# движущиеся (не растения/камни) — актёры реплея
		if e.section in [&"animals", &"birds", &"small", &"sea"] and not n.is_in_group(&"wild_animals"):
			n.add_to_group(&"replay_actor")

func _aviary(p: Vector2, r: float) -> void:
	var pen := P.pen(self, p.x, p.y, r, 5.5)
	# сетка сверху (видимая) и потолок-коллизия, чтобы птицы не улетали
	var g := ground(p.x, p.y)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 0.02
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.2, 0.2, 0.18, 0.25)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	pen.add_child(mi)
	mi.global_position = Vector3(p.x, g + 5.6, p.y)
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = r
	cy.height = 0.3
	cs.shape = cy
	pen.add_child(cs)
	cs.global_position = Vector3(p.x, g + 5.7, p.y)

func _terrarium(p: Vector2, r: float) -> void:
	var body := StaticBody3D.new()
	add_child(body)
	var g := ground(p.x, p.y)
	body.global_position = Vector3(p.x, g, p.y)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.75, 0.88, 0.9, 0.16)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.metallic_specular = 1.0
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var h := 1.1
	for k in 4:
		var yaw := k * PI * 0.5
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(r * 2.0, h, 0.03)
		mi.mesh = bm
		mi.material_override = glass
		var off := Vector3(0, h * 0.5, r).rotated(Vector3.UP, yaw)
		mi.position = off
		mi.rotation.y = yaw
		body.add_child(mi)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(r * 2.0, h + 0.4, 0.12)
		cs.shape = bs
		cs.position = off + Vector3(0, 0.2, 0)
		cs.rotation.y = yaw
		body.add_child(cs)
	# подстилка
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(r * 2.0, r * 2.0)
	floor_mi.mesh = pm
	floor_mi.material_override = HeldModels.pbr("forest_leaves_02", Vector3(2, 2, 2)) if ResourceLoader.exists("res://assets/textures/forest_leaves_02") else null
	floor_mi.position.y = 0.02
	body.add_child(floor_mi)

func _bed(p: Vector2, s: float) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(s, s)
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.22, 0.15)
	m.roughness = 1.0
	mi.material_override = m
	add_child(mi)
	mi.global_position = Vector3(p.x, ground(p.x, p.y) + 0.015, p.y)

## Вольер в море: кольцо поплавков и сетка до дна.
func _net_pen(p: Vector2, r: float) -> void:
	var root := Node3D.new()
	add_child(root)
	root.global_position = Vector3(p.x, 0.0, p.y)
	var net := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = absf(PolygonLayout.SHELF_DEPTH) + 0.4
	cm.cap_top = false
	cm.cap_bottom = false
	net.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.12, 0.14, 0.12, 0.35)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	net.material_override = m
	net.position.y = -cm.height * 0.5 + 0.2
	root.add_child(net)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r - 0.12
	tm.outer_radius = r + 0.12
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.85, 0.45, 0.12)
	ring.material_override = rm
	ring.position.y = 0.05
	root.add_child(ring)

# ------------------------------------------------------------ столы с предметами

func _table(tb: Dictionary) -> void:
	var p: Vector2 = tb.pos
	var t := P.table(self, p.x, p.y, 4.0)
	var ids: Array = tb.items
	var step := minf(0.5, 3.6 / maxf(1.0, ids.size() - 1.0))
	for i in ids.size():
		var e: Dictionary = ids[i]
		var id := StringName(e.id)
		var lx := -step * (ids.size() - 1) * 0.5 + step * i
		var w := t.global_transform * Vector3(lx, 0.98, (0.18 if i % 2 == 0 else -0.18))
		var n := 20 if sec.id == &"weapons" else 1
		var te := {"pos": w, "id": id, "n": mini(n, Inventory.stack_of(id)), "node": null, "name": String(e.name)}
		_tables.append(te)
		_spawn_table_item(te)

func _spawn_table_item(te: Dictionary) -> void:
	var items: Array[Dictionary] = [{"id": te.id, "n": te.n}]
	var pk := ItemPickup.spawn(self, te.pos, items)
	te.node = pk
	if pk:
		pk.freeze = true
		pk.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		if not te.has("label"):
			var l := P.label(self, (te.pos as Vector3) + Vector3(0, 0.3, 0), String(te.name), 30, P.SIGN_COLOR, 10.0)
			l.pixel_size = 0.0032
			te["label"] = l

var _tick := 0.0

func _process(delta: float) -> void:
	if not is_built:
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.3
	# предметы на столах не кончаются: взятый — появляется снова
	for te: Dictionary in _tables:
		var n: Variant = te.node
		if n == null or not is_instance_valid(n) or (n as Node).is_queued_for_deletion():
			_spawn_table_item(te)

# ------------------------------------------------------------ особые разделы

func _range() -> void:
	var r: Vector2 = sec.get("range", Vector2.ZERO)
	var origin := Vector3(r.x, ground(r.x, r.y), r.y)
	var rg := SandboxRange.build(self, origin, Vector3.BACK, func(x: float, z: float) -> float: return ground(x, z))
	dummies = rg.dummies
	P.tag(self, r.x - 6.0, r.y, "Стрельбище: мишени на 10, 25, 50 и 100 м", 2.2, 60.0)

func _house() -> void:
	var bm := BuildModule.instance()
	var h: Vector2 = sec.get("house", Vector2.ZERO)
	if bm == null:
		return
	var base := Transform3D(Basis(), Vector3(h.x, ground(h.x, h.y), h.y))
	var w1 := _place_xf(&"wall", base)
	_place_xf(&"wall_window", base * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(1.5, 0, -1.5)))
	var w3 := _place_xf(&"wall_door", base * Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -3.0)))
	_place_xf(&"wall", base * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-1.5, 0, -1.5)))
	if w1:
		var rs := bm.find_socket(&"roof", base.origin + Vector3.UP * BuildDefs.WALL_H + Vector3(0, 0, -1.5), 3.0)
		if not rs.is_empty():
			_place_xf(&"roof", rs.xform)
	if w3:
		var ds := bm.find_socket(&"door", w3.global_position, 3.0)
		if not ds.is_empty():
			_place_xf(&"door", ds.xform)
	P.tag(self, h.x, h.y + 3.0, "Дом: стены, окно, дверь, крыша", 3.4)

func _place_xf(def_id: StringName, xf: Transform3D, anchor: Dictionary = {}, ctx: Dictionary = {}) -> Blueprint:
	var bm := BuildModule.instance()
	if bm == null:
		return null
	var bp := bm.place_blueprint(def_id, xf, 0, anchor, ctx)
	_complete(bp)
	_own(bp)
	return bp

func _sea() -> void:
	var ps: Vector2 = sec.get("pier_start", Vector2.ZERO)
	var plen := float(sec.get("pier_len", 30.0))
	P.pier(self, Vector3(ps.x, 0, ps.y), Vector3.BACK, plen, 1.15, 3.2)
	# аквариумы: стеклянные короба у пирса, верх — у поверхности
	for st: Dictionary in sec.stands:
		var p: Vector2 = st.pos
		_tank(p)
	# морской конёк на тумбах (держится хвостом за траву, все клипы) — у начала пирса на берегу
	SandboxSeahorse.build(self, Vector2(ps.x + 40.0, float(sec.coast) - 8.0))
	# морские модели со скелетом: витрины, каждая по кругу показывает все клипы автора
	SandboxSeaSkel.build(self, Vector2(ps.x - 40.0, float(sec.coast) + 8.0))
	# мост из связок брёвен от берега (секции, ворота)
	var bm := BuildModule.instance()
	if bm:
		var x0 := ps.x + 30.0
		var first := Transform3D(Basis(Vector3.UP, PI), Vector3(x0, 0.0, float(sec.coast) + 1.5))
		var prev := _place_xf(&"raft", first, {"type": &"shore"})
		for i in range(1, 5):
			if prev == null:
				break
			var sock := bm.raft_socket(prev.base_now() * Vector3(0, 0, -BuildDefs.RAFT_L), 1.5)
			if sock.is_empty():
				break
			prev = _place_xf(&"raft_gate" if i == 2 else (&"raft_pile" if i == 4 else &"raft"), sock.xform,
				{"type": &"raft", "parent": sock.parent, "offset": sock.offset})
		P.tag(self, x0, float(sec.coast) - 2.0, "Мост: связки брёвен, ворота, сваи", 2.2)

func _tank(p: Vector2) -> void:
	var floor_y := ground(p.x, p.y)
	var h := -floor_y + 0.15
	if h < 0.6:
		return
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.7, 0.9, 0.95, 0.12)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.04
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var root := Node3D.new()
	add_child(root)
	root.global_position = Vector3(p.x, floor_y, p.y)
	var w := 3.4
	for k in 4:
		var yaw := k * PI * 0.5
		var mi := MeshInstance3D.new()
		var bmesh := BoxMesh.new()
		bmesh.size = Vector3(w, h, 0.04)
		mi.mesh = bmesh
		mi.material_override = glass
		mi.position = Vector3(0, h * 0.5, w * 0.5).rotated(Vector3.UP, yaw)
		mi.rotation.y = yaw
		root.add_child(mi)
