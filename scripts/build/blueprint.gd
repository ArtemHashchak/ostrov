class_name Blueprint
extends AnimatableBody3D
## Чертёж/постройка в духе The Forest. Ставится призраком, затем игрок
## укладывает детали (брёвна носит на плече, палки/камни/верёвку — из
## инвентаря): видно, какие брёвна уже на месте. Готовая постройка —
## твёрдая, её можно ломать, жечь. Для мостов (def «raft») — плавучая
## связка брёвен: качается на волнах, держится за берег или соседнюю секцию,
## при разрыве связи уплывает.

signal completed(bp: Blueprint)
signal destroyed(bp: Blueprint)

const BURN_DPS := 9.0
const BURN_SPREAD_AFTER := 4.0
const CHAR_AFTER := 5.0
const DRIFT_SPEED := 0.75
const RAFT_FLOAT := 0.02

var def_id: StringName = &"wall"
var team: int = -1
var preview: bool = false
var ctx: Dictionary = {}
var parts: Array[Dictionary] = []
var filled: Array[bool] = []
var complete: bool = false
var hp: float = 0.0
var base_xform: Transform3D = Transform3D.IDENTITY

# огонь
var burning: bool = false
var _burn_t: float = 0.0
var _charred: bool = false
var _spread_done: Dictionary = {}
var _fire_root: Node3D = null
var _fire_light: OmniLight3D = null

# дверь
var door_open: bool = false

# мост-плот
var anchor: Dictionary = {}          # {type: &"shore"} | {type: &"raft", parent: Blueprint, offset: Transform3D} | {type: &"drift"}
var raft_children: Array[Blueprint] = []
var _drift_t: float = 0.0
var _drift_dir: Vector3 = Vector3(1, 0, 0.3).normalized()
var _sink: float = 0.0

var _nodes: Array[MeshInstance3D] = []
var _shapes: Array[CollisionShape3D] = []
var _extra_shapes: Array[CollisionShape3D] = []
var _area: Area3D = null
var _parts_root: Node3D = null
var _ghost_mat: StringName = &"ghost"
var _dead: bool = false

func setup(id: StringName, owner_team: int, context: Dictionary = {}, is_preview: bool = false) -> Blueprint:
	def_id = id
	team = owner_team
	ctx = context
	preview = is_preview
	if preview:
		_ghost_mat = &"ghost_ok"
	return self

func is_raft() -> bool:
	return BuildDefs.kind_of(def_id) == &"raft"

func _ready() -> void:
	sync_to_physics = is_raft()
	if preview:
		collision_layer = 0
		collision_mask = 0
	else:
		add_to_group(&"buildable")
		if is_raft():
			add_to_group(&"raft_deck")
		if base_xform == Transform3D.IDENTITY:
			base_xform = global_transform
	_parts_root = Node3D.new()
	_parts_root.name = "Parts"
	add_child(_parts_root)
	if preview and is_raft():
		_parts_root.position.y = BuildDefs.R * 0.9   # призрак над водой, чтобы его было видно
	_build_parts()
	if not preview:
		_make_area()

# --- детали ---

func _build_parts() -> void:
	for n in _nodes:
		n.queue_free()
	for s in _shapes:
		if s:
			s.queue_free()
	_nodes.clear()
	_shapes.clear()
	var keep: Array[bool] = filled.duplicate()
	parts = BuildDefs.parts(def_id, ctx)
	filled.resize(parts.size())
	for i in parts.size():
		filled[i] = keep[i] if i < keep.size() else false
		var mi := _make_part_mesh(parts[i])
		_parts_root.add_child(mi)
		_nodes.append(mi)
		_shapes.append(null)
		_apply_look(i)
		if filled[i]:
			_add_shape(i)

## Перестроить детали под новый контекст (сваи по рельефу у призрака).
func rebuild(context: Dictionary) -> void:
	ctx = context
	_build_parts()

func _part_xform(p: Dictionary) -> Transform3D:
	return Transform3D(Basis.from_euler(p.rot), p.pos)

func _make_part_mesh(p: Dictionary) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var t: StringName = p.t
	var r: float = p.r
	var length: float = p.len
	match t:
		&"log", &"stick":
			mi.mesh = BuildMats.cylinder(r, length, 10 if t == &"log" else 6)
		&"rope":
			if length > 0.0:
				mi.mesh = BuildMats.cylinder(r, length, 6)
			else:
				mi.mesh = BuildMats.torus(r * 0.72, r)
		&"stone":
			mi.mesh = BuildMats.rock_mesh(r)
	mi.transform = _part_xform(p)
	if t == &"stone":
		mi.scale = Vector3(1.0, 0.7, 0.85)
	return mi

func _apply_look(i: int) -> void:
	var mi := _nodes[i]
	if preview or not filled[i]:
		mi.material_override = BuildMats.mat(_ghost_mat)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		var t: StringName = parts[i].t
		var m := t
		if _charred and (t == &"log" or t == &"stick"):
			m = &"charred"
		mi.material_override = BuildMats.mat(m)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

func set_preview_valid(ok: bool) -> void:
	var want: StringName = &"ghost_ok" if ok else &"ghost_bad"
	if want == _ghost_mat:
		return
	_ghost_mat = want
	for i in _nodes.size():
		_apply_look(i)

func _add_shape(i: int) -> void:
	if preview:
		return
	var p: Dictionary = parts[i]
	if not bool(p.solid) or p.shape == &"none":
		return
	var cs := CollisionShape3D.new()
	var r: float = p.r
	var length: float = p.len
	if p.shape == &"cyl":
		var cy := CylinderShape3D.new()
		cy.radius = r
		cy.height = length
		cs.shape = cy
	else:
		var b := BoxShape3D.new()
		b.size = Vector3(r * 2.0, length, r * 2.0)
		cs.shape = b
	cs.transform = _part_xform(p)
	add_child(cs)
	_shapes[i] = cs

func _remove_shape(i: int) -> void:
	if _shapes[i]:
		_shapes[i].queue_free()
		_shapes[i] = null

# --- доп. коллизии (пандус лестницы, скаты крыши, сходни моста) ---

func _update_extra_shapes() -> void:
	if preview:
		return
	var want := false
	match def_id:
		&"stairs", &"roof":
			want = complete
		&"raft":
			want = filled_count(&"log") >= 3
	if want == (not _extra_shapes.is_empty()):
		return
	for s in _extra_shapes:
		s.queue_free()
	_extra_shapes.clear()
	if not want:
		return
	match def_id:
		&"stairs":
			var dims := BuildDefs.stairs_dims(ctx)
			var L := dims.length()
			var a := atan2(dims.x, dims.y)
			_add_box(Vector3(1.4, 0.2, L + 0.3), Transform3D(Basis(Vector3.RIGHT, a), Vector3(0, dims.x * 0.5, 0)))
		&"roof":
			var ridge := 1.35
			var eave := 1.75
			var L2 := sqrt(ridge * ridge + eave * eave)
			for side in [-1.0, 1.0]:
				var a2: float = atan2(ridge, eave) * side
				_add_box(Vector3(3.4, 0.25, L2), Transform3D(Basis(Vector3.RIGHT, a2), Vector3(0, ridge * 0.5 + BuildDefs.R, side * eave * 0.5)))
		&"raft":
			# сходни-скосы на торцах: можно зайти с пляжа и с соседней секции
			for sz in [-1.0, 1.0]:
				var w := BuildDefs.RAFT_W * 0.5
				var z0: float = sz * BuildDefs.RAFT_L * 0.5
				var z1: float = sz * (BuildDefs.RAFT_L * 0.5 + 0.7)
				var top := BuildDefs.R
				var bot := -BuildDefs.R - 0.12
				var pts := PackedVector3Array([
					Vector3(-w, top, z0), Vector3(w, top, z0), Vector3(-w, bot, z0), Vector3(w, bot, z0),
					Vector3(-w, bot, z1), Vector3(w, bot, z1)])
				var cp := ConvexPolygonShape3D.new()
				cp.points = pts
				var cs := CollisionShape3D.new()
				cs.shape = cp
				add_child(cs)
				_extra_shapes.append(cs)

func _add_box(size: Vector3, xf: Transform3D) -> void:
	var b := BoxShape3D.new()
	b.size = size
	var cs := CollisionShape3D.new()
	cs.shape = b
	cs.transform = xf
	add_child(cs)
	_extra_shapes.append(cs)

# --- зона взаимодействия ---

func _make_area() -> void:
	_area = Area3D.new()
	_area.name = "InteractArea"
	_area.monitoring = false
	_area.monitorable = true
	_area.collision_layer = 1
	_area.collision_mask = 0
	var aabb := _parts_aabb()
	var b := BoxShape3D.new()
	b.size = aabb.size + Vector3(0.3, 0.3, 0.3)
	var cs := CollisionShape3D.new()
	cs.shape = b
	cs.position = aabb.get_center()
	_area.add_child(cs)
	add_child(_area)

func _parts_aabb() -> AABB:
	var box := AABB()
	var first := true
	for p: Dictionary in parts:
		var ext := maxf(float(p.len) * 0.5, float(p.r))
		var pb := AABB(Vector3(p.pos) - Vector3.ONE * ext, Vector3.ONE * ext * 2.0)
		if p.t == &"log" or p.t == &"stick":
			# вытянутые вдоль своей оси — грубо, но достаточно
			pb = AABB(Vector3(p.pos) - Vector3(ext, ext, ext), Vector3(ext, ext, ext) * 2.0)
		box = pb if first else box.merge(pb)
		first = false
	return box

# --- заполнение ---

func next_needed(t: StringName) -> int:
	for i in parts.size():
		if not filled[i] and parts[i].t == t:
			return i
	return -1

func needs_left() -> Dictionary:
	var n: Dictionary = {}
	for i in parts.size():
		if not filled[i]:
			var t: StringName = parts[i].t
			n[t] = int(n.get(t, 0)) + 1
	return n

func filled_count(t: StringName = &"") -> int:
	var c := 0
	for i in parts.size():
		if filled[i] and (t == &"" or parts[i].t == t):
			c += 1
	return c

func total_count(t: StringName) -> int:
	var c := 0
	for p: Dictionary in parts:
		if p.t == t:
			c += 1
	return c

func is_complete() -> bool:
	return complete

func fill_part(i: int, _by: Node = null) -> void:
	if i < 0 or i >= parts.size() or filled[i]:
		return
	filled[i] = true
	hp += float(BuildDefs.HP_PER.get(parts[i].t, 10.0))
	_apply_look(i)
	_add_shape(i)
	var mi := _nodes[i]
	var target := mi.position
	mi.position = target + Vector3(0, 0.55, 0)
	var tw := create_tween()
	tw.tween_property(mi, ^"position", target, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_update_extra_shapes()
	if not complete and needs_left().is_empty():
		complete = true
		_update_extra_shapes()
		completed.emit(self)
		if Events.has_signal(&"structure_completed"):
			Events.structure_completed.emit(self, def_id)
		BuildEnv.toast("Построено: %s" % BuildDefs.name_of(def_id))

## Добавить n единиц материала (боты, отладка). Возвращает сколько уложено.
func add_material(t: StringName, n: int, by: Node = null) -> int:
	var done := 0
	while done < n:
		var i := next_needed(t)
		if i < 0:
			break
		fill_part(i, by)
		done += 1
	return done

## Принять бревно, которое игрок несёт на плече (CONTRACT_G1).
func accept_log(player: Node) -> bool:
	if not bool(player.get(&"carrying_log")):
		return false
	var i := next_needed(&"log")
	if i < 0:
		return false
	var obj: Node = player.get(&"carried_object") as Node
	player.call(&"set_carrying_log", false)
	if obj and is_instance_valid(obj):
		obj.queue_free()
	fill_part(i, player)
	return true

func get_interact_text(player: Node) -> String:
	if complete:
		if def_id == &"door":
			return "E — %s дверь" % ("закрыть" if door_open else "открыть")
		return BuildDefs.name_of(def_id)
	var left := needs_left()
	var bits: PackedStringArray = []
	for t: StringName in [&"log", &"stick", &"stone", &"rope"]:
		if left.has(t):
			bits.append("%s %d/%d" % [BuildDefs.NEED_NAMES[t], total_count(t) - int(left[t]), total_count(t)])
	var head := BuildDefs.name_of(def_id)
	if bool(player.get(&"carrying_log")) and left.has(&"log"):
		return "%s — E: уложить бревно · %s" % [head, " · ".join(bits)]
	for t: StringName in [&"stick", &"stone", &"rope"]:
		if left.has(t) and BuildEnv.inv_count(player, t) > 0:
			return "%s — E: добавить %s · %s" % [head, BuildDefs.NEED_NAMES[t], " · ".join(bits)]
	return "%s — нужно: %s" % [head, " · ".join(bits)]

func interact(player: Node) -> void:
	if _dead:
		return
	if complete:
		if def_id == &"door":
			toggle_door()
		return
	if bool(player.get(&"carrying_log")):
		if accept_log(player):
			return
		BuildEnv.toast("Брёвна сюда больше не нужны")
		return
	for t: StringName in [&"stick", &"stone", &"rope"]:
		if next_needed(t) >= 0 and BuildEnv.inv_count(player, t) > 0 and BuildEnv.inv_remove(player, t, 1):
			fill_part(next_needed(t), player)
			return
	var left := needs_left()
	var bits: PackedStringArray = []
	for t: StringName in left.keys():
		bits.append("%s ×%d" % [BuildDefs.NEED_NAMES.get(t, String(t)), int(left[t])])
	BuildEnv.toast("Нужно: %s" % ", ".join(bits) + ("  (брёвна неси на плече)" if left.has(&"log") else ""))

func toggle_door() -> void:
	door_open = not door_open
	var from := global_transform.basis.get_rotation_quaternion()
	var to := (base_xform.basis * Basis(Vector3.UP, -PI * 0.5 if door_open else 0.0)).get_rotation_quaternion()
	var origin := base_xform.origin
	var tw := create_tween()
	tw.tween_method(func(q: Quaternion) -> void: global_transform = Transform3D(Basis(q), origin), from, to, 0.35)

# --- урон ---

func apply_damage(amount: float, source: Node, kind: StringName) -> void:
	if preview or _dead or amount <= 0.0:
		return
	var mul := 1.0
	match kind:
		&"explosion": mul = 1.6
		&"axe": mul = 1.0
		&"melee": mul = 0.5
		&"bullet": mul = 0.25
		&"fire": mul = 1.0
	hp -= amount * mul
	# снимаем верхние детали, пока их прочность больше оставшейся
	var sum := _filled_hp()
	while sum > hp + 0.01 and filled_count() > 0:
		var i := _top_filled()
		if i < 0:
			break
		var phv := float(BuildDefs.HP_PER.get(parts[i].t, 10.0))
		if sum - phv < hp - 0.01:
			break
		_unfill(i, true)
		sum -= phv
	if filled_count() == 0 or hp <= 0.0:
		destroy(source)

func _filled_hp() -> float:
	var s := 0.0
	for i in parts.size():
		if filled[i]:
			s += float(BuildDefs.HP_PER.get(parts[i].t, 10.0))
	return s

func _top_filled() -> int:
	for i in range(parts.size() - 1, -1, -1):
		if filled[i]:
			return i
	return -1

func _unfill(i: int, debris: bool) -> void:
	filled[i] = false
	complete = false
	_remove_shape(i)
	_apply_look(i)
	if debris and (parts[i].t == &"log"):
		_spawn_debris(parts[i])
	_update_extra_shapes()

func on_hit(by: Node, hit: Dictionary) -> void:
	var tool: StringName = StringName(hit.get("tool", &"hand"))
	if tool == &"torch":
		ignite()
		return
	var dmg := float(hit.get("damage", 0.0))
	if dmg <= 0.0:
		match tool:
			&"axe", &"axe_crude", &"axe_modern": dmg = 22.0
			&"rock", &"stone": dmg = 7.0
			&"spear": dmg = 6.0
			_: dmg = 3.0
	var kind: StringName = &"axe" if String(tool).begins_with("axe") else &"melee"
	# мост: топором можно перерубить связку, если секция уже потрёпана
	if is_raft() and kind == &"axe" and not anchor.is_empty() and anchor.get("type") == &"raft" and hp < _max_hp() * 0.35:
		detach("Связка перерублена — секция уплывает")
		return
	apply_damage(dmg, by, kind)

func _max_hp() -> float:
	var s := 0.0
	for p: Dictionary in parts:
		s += float(BuildDefs.HP_PER.get(p.t, 10.0))
	return s

func destroy(by: Node = null) -> void:
	if _dead:
		return
	_dead = true
	for i in parts.size():
		if filled[i] and parts[i].t == &"log" and randf() < 0.6:
			_spawn_debris(parts[i])
	for c in raft_children:
		if is_instance_valid(c):
			c.detach("Мост разорван — секция уплывает")
	if anchor.get("type") == &"raft":
		var par: Blueprint = anchor.get("parent") as Blueprint
		if par and is_instance_valid(par):
			par.raft_children.erase(self)
	destroyed.emit(self)
	if Events.has_signal(&"structure_destroyed"):
		Events.structure_destroyed.emit(self, def_id, by)
	remove_from_group(&"buildable")
	remove_from_group(&"raft_deck")
	collision_layer = 0
	var tw := create_tween()
	tw.tween_property(_parts_root, ^"scale", Vector3(1, 0.05, 1), 0.6)
	tw.tween_callback(queue_free)

func _spawn_debris(p: Dictionary) -> void:
	var parent := get_parent()
	if parent == null or not is_inside_tree():
		return
	var rb := RigidBody3D.new()
	rb.mass = 30.0
	var mi := MeshInstance3D.new()
	mi.mesh = BuildMats.cylinder(float(p.r), float(p.len), 8)
	mi.material_override = BuildMats.mat(&"charred" if _charred else &"log")
	rb.add_child(mi)
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = float(p.r)
	cy.height = float(p.len)
	cs.shape = cy
	rb.add_child(cs)
	parent.add_child(rb)
	rb.global_transform = global_transform * _part_xform(p)
	rb.apply_impulse(Vector3(randf_range(-1, 1), 2.0, randf_range(-1, 1)) * 40.0)
	var tw := rb.create_tween()
	tw.tween_interval(8.0)
	tw.tween_callback(rb.queue_free)

# --- огонь ---

func has_wood() -> bool:
	for i in parts.size():
		if filled[i] and (parts[i].t == &"log" or parts[i].t == &"stick" or parts[i].t == &"rope"):
			return true
	return false

func ignite(_by: Node = null) -> void:
	if preview or _dead or burning or not has_wood():
		return
	burning = true
	_burn_t = 0.0
	_spread_done.clear()
	_make_fire()

func extinguish() -> void:
	burning = false
	if _fire_root:
		_fire_root.queue_free()
		_fire_root = null
		_fire_light = null

func _make_fire() -> void:
	_fire_root = Node3D.new()
	_fire_root.name = "Fire"
	add_child(_fire_root)
	var aabb := _parts_aabb()
	var flames := CPUParticles3D.new()
	flames.amount = 48
	flames.lifetime = 0.9
	flames.local_coords = false
	var q := QuadMesh.new()
	q.size = Vector2(0.7, 0.9)
	q.material = BuildMats.mat(&"flame")
	flames.mesh = q
	flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	flames.emission_box_extents = Vector3(aabb.size.x * 0.45, 0.15, aabb.size.z * 0.45)
	flames.position = aabb.get_center() + Vector3(0, aabb.size.y * 0.3, 0)
	flames.direction = Vector3.UP
	flames.spread = 12.0
	flames.gravity = Vector3(0, 1.5, 0)
	flames.initial_velocity_min = 0.8
	flames.initial_velocity_max = 1.8
	flames.scale_amount_min = 0.6
	flames.scale_amount_max = 1.3
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.85, 0.35, 0.9))
	g.set_color(1, Color(0.9, 0.2, 0.05, 0.0))
	flames.color_ramp = g
	_fire_root.add_child(flames)
	var smoke := CPUParticles3D.new()
	smoke.amount = 20
	smoke.lifetime = 3.0
	smoke.local_coords = false
	var sq := QuadMesh.new()
	sq.size = Vector2(1.4, 1.4)
	sq.material = BuildMats.mat(&"smoke")
	smoke.mesh = sq
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	smoke.emission_box_extents = flames.emission_box_extents
	smoke.position = flames.position + Vector3(0, 0.8, 0)
	smoke.direction = Vector3.UP
	smoke.gravity = Vector3(0.4, 1.0, 0)
	smoke.initial_velocity_min = 0.6
	smoke.initial_velocity_max = 1.2
	smoke.scale_amount_min = 1.0
	smoke.scale_amount_max = 2.5
	var sg := Gradient.new()
	sg.set_color(0, Color(0.3, 0.28, 0.26, 0.45))
	sg.set_color(1, Color(0.3, 0.3, 0.3, 0.0))
	smoke.color_ramp = sg
	_fire_root.add_child(smoke)
	_fire_light = OmniLight3D.new()
	_fire_light.light_color = Color(1.0, 0.6, 0.25)
	_fire_light.light_energy = 2.0
	_fire_light.omni_range = 7.0
	_fire_light.position = flames.position + Vector3(0, 0.5, 0)
	_fire_root.add_child(_fire_light)

func _process_fire(delta: float) -> void:
	_burn_t += delta
	if _fire_light:
		_fire_light.light_energy = 1.6 + sin(_burn_t * 17.0) * 0.4 + sin(_burn_t * 7.3) * 0.3
	var w := BuildEnv.weather()
	if (w == &"rain" or w == &"storm") and randf() < 0.12 * delta:
		extinguish()
		BuildEnv.toast("Дождь потушил огонь")
		return
	if not _charred and _burn_t > CHAR_AFTER:
		_charred = true
		for i in _nodes.size():
			_apply_look(i)
	if _burn_t > BURN_SPREAD_AFTER:
		for nb in _fire_neighbours():
			if not _spread_done.has(nb.get_instance_id()):
				_spread_done[nb.get_instance_id()] = true
				nb.ignite(self)
	apply_damage(BURN_DPS * delta, self, &"fire")
	if not has_wood():
		extinguish()

func _fire_neighbours() -> Array[Blueprint]:
	var out: Array[Blueprint] = []
	if is_raft():
		if anchor.get("type") == &"raft":
			var par: Blueprint = anchor.get("parent") as Blueprint
			if par and is_instance_valid(par):
				out.append(par)
		for c in raft_children:
			if is_instance_valid(c):
				out.append(c)
	else:
		for n in get_tree().get_nodes_in_group(&"buildable"):
			var b := n as Blueprint
			if b and b != self and b.global_position.distance_to(global_position) < 3.6:
				out.append(b)
	return out

# --- мост-плот ---

func base_now() -> Transform3D:
	if anchor.get("type") == &"raft":
		var par: Blueprint = anchor.get("parent") as Blueprint
		if par and is_instance_valid(par):
			return par.base_now() * Transform3D(anchor.get("offset", Transform3D.IDENTITY))
	return base_xform

## Порвать связь: секция (со своими «детьми») уплывает по течению.
func detach(msg: String = "") -> void:
	if not is_raft() or anchor.get("type") == &"drift":
		return
	base_xform = base_now()
	if anchor.get("type") == &"raft":
		var par: Blueprint = anchor.get("parent") as Blueprint
		if par and is_instance_valid(par):
			par.raft_children.erase(self)
			_drift_dir = (base_xform.origin - par.base_now().origin).normalized()
			_drift_dir.y = 0.0
			if _drift_dir.length() < 0.1:
				_drift_dir = Vector3(1, 0, 0)
			_drift_dir = _drift_dir.normalized()
	anchor = {"type": &"drift"}
	_drift_t = 0.0
	if msg != "":
		BuildEnv.toast(msg)

func is_drifting() -> bool:
	return anchor.get("type") == &"drift"

## Высота настила над водой (для акул, CONTRACT_G1).
func deck_height() -> float:
	return global_position.y + BuildDefs.R - BuildEnv.water_level()

func _physics_process(delta: float) -> void:
	if burning:
		_process_fire(delta)
	if is_raft() and not preview and is_inside_tree():
		_float(delta)

func _float(delta: float) -> void:
	if anchor.get("type") == &"raft":
		var par: Blueprint = anchor.get("parent") as Blueprint
		if par == null or not is_instance_valid(par):
			detach("Мост разорван — секция уплывает")
	if anchor.get("type") == &"drift":
		_drift_t += delta
		base_xform.origin += _drift_dir * DRIFT_SPEED * delta
		base_xform.basis = base_xform.basis * Basis(Vector3.UP, 0.04 * delta)
		if _drift_t > 45.0:
			_sink += delta * 0.08
		if _drift_t > 75.0:
			destroy(null)
			return
	var b := base_now()
	var o := b.origin
	var fz := b.basis.z.normalized()
	var fx := b.basis.x.normalized()
	var hf := BuildEnv.wave_height(o.x - fz.x * 1.3, o.z - fz.z * 1.3)
	var hb := BuildEnv.wave_height(o.x + fz.x * 1.3, o.z + fz.z * 1.3)
	var hr := BuildEnv.wave_height(o.x + fx.x * 0.9, o.z + fx.z * 0.9)
	var hl := BuildEnv.wave_height(o.x - fx.x * 0.9, o.z - fx.z * 0.9)
	var y := BuildEnv.water_level() + (hf + hb + hr + hl) * 0.25 + RAFT_FLOAT - _sink
	# груз: каждый стоящий на секции чуть притапливает её
	var riders := 0
	for c in get_tree().get_nodes_in_group(&"characters"):
		var c3 := c as Node3D
		if c3 and c3.global_position.distance_to(Vector3(o.x, y, o.z)) < 1.8 and absf(c3.global_position.y - y) < 1.0:
			riders += 1
	y -= riders * 0.05
	var pitch := atan2(hf - hb, 2.6)
	var roll := atan2(hr - hl, 1.8)
	var bas := b.basis.orthonormalized() * Basis.from_euler(Vector3(pitch, 0.0, roll))
	global_transform = Transform3D(bas, Vector3(o.x, y, o.z))
