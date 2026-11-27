extends Node
## Раны и кровь на крупных существах (v5.1, агент I). Автозагрузка «Wounds».
## Любое попадание по существу крупнее MIN_SIZE (пуля, дробь, стрела, острога, нож, мачете, топор, удар)
## оставляет рану ровно в точке попадания: она прикреплена к ближайшей кости скелета (BoneAttachment3D)
## и двигается с телом, остаётся на туше. Из раны бьёт струйка крови, пока зверь жив — капает:
## на суше пятна на земле (след крови), в воде — облако крови через Sea.add_blood (акулы чуют).
## Источники: Combat.hit_landed (пули, стрелы, острога, удары ботов) и Events.player_swing (удар игрока).
## Работает в gl_compatibility (рана — сетка, не Decal).

const MIN_SIZE := 0.5          # наибольший габарит существа (м), начиная с которого — раны
const MAX_WOUNDS_PER := 24     # ран на одном существе
const MAX_SPOTS := 220         # пятен крови на земле всего
const SPOT_LIFE := 120.0       # с, потом пятно тает
const BLEED_TIME := 45.0       # с, за которые кровотечение раны стихает

## Тип раны по оружию: r — радиус (м), len — вытянутость (порез), bleed — сила кровотечения.
const KINDS := {
	&"bullet_small": {"r": 0.011, "len": 1.0, "bleed": 0.8, "spurt": 18},
	&"bullet_rifle": {"r": 0.016, "len": 1.0, "bleed": 1.1, "spurt": 26},
	&"pellet": {"r": 0.007, "len": 1.0, "bleed": 0.4, "spurt": 8},
	&"arrow": {"r": 0.014, "len": 1.6, "bleed": 0.9, "spurt": 14},
	&"spear": {"r": 0.02, "len": 1.8, "bleed": 1.2, "spurt": 20},
	&"cut": {"r": 0.022, "len": 3.6, "bleed": 1.3, "spurt": 22},
	&"chop": {"r": 0.03, "len": 3.0, "bleed": 1.6, "spurt": 28},
	&"blunt": {"r": 0.035, "len": 1.2, "bleed": 0.25, "spurt": 6},
	&"bite": {"r": 0.04, "len": 1.5, "bleed": 1.4, "spurt": 16},
}

var _spots: Array[Node3D] = []
var _bleeders: Array[Node3D] = []      # существа с кровоточащими ранами
var _combat_hooked := false
var _swing_hooked := false
var _host: Node3D                      # куда класть пятна и брызги (корень сцены)
var _wound_tex: Dictionary = {}        # kind → ImageTexture
var _spot_tex: ImageTexture
var _drop_mat: StandardMaterial3D
var _spot_mat_base: StandardMaterial3D
var _t := 0.0
var _cloud_t := {}                     # instance_id → время последнего облака в воде
## Для тестов: последние раны [{target, node, kind, pos}]
var last: Array[Dictionary] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_try_hook()

func _process(dt: float) -> void:
	_t += dt
	if not _combat_hooked or not _swing_hooked:
		_try_hook()
	_bleed_tick(dt)

func _try_hook() -> void:
	if not _combat_hooked:
		var c: Node = get_tree().get_first_node_in_group(&"combat_module") if is_inside_tree() else null
		if c and c.has_signal(&"hit_landed"):
			c.connect(&"hit_landed", _on_hit_landed)
			_combat_hooked = true
	if not _swing_hooked:
		var ev := get_node_or_null(^"/root/Events")
		if ev and ev.has_signal(&"player_swing"):
			ev.connect(&"player_swing", _on_player_swing)
			_swing_hooked = true

# ============================== входы ==============================

func _on_hit_landed(info: Dictionary) -> void:
	if float(info.get("damage", 0.0)) <= 0.0:
		return
	var t: Variant = info.get("target")
	if not (t is Node) or not is_instance_valid(t):
		return
	add_hit(t as Node, info.get("position", Vector3.ZERO), info.get("normal", Vector3.UP),
		StringName(info.get("weapon", &"")), StringName(info.get("kind", &"")))

func _on_player_swing(_player: Node, hit: Dictionary) -> void:
	if hit.get("miss", false) or not hit.has("collider"):
		return
	var col := hit.collider as Node
	if col == null:
		return
	var t := _find_damageable(col)
	if t == null or float(hit.get("damage", 0.0)) <= 0.0:
		return
	add_hit(t, hit.get("position", Vector3.ZERO), hit.get("normal", Vector3.UP), StringName(hit.get("item", &"")), &"melee")

static func _find_damageable(n: Node) -> Node:
	var cur := n
	while cur:
		if cur.has_method(&"apply_damage") or cur.has_method(&"on_hit"):
			return cur
		cur = cur.get_parent()
	return null

# ============================== раны ==============================

## Добавить рану. target — то, что приняло урон (зверь, акула, хитбокс существа…).
## Возвращает узел раны или null (не существо / слишком мелкое).
func add_hit(target: Node, pos: Vector3, normal: Vector3, weapon: StringName, kind: StringName) -> Node3D:
	var root := creature_root(target)
	if root == null:
		return null
	var wk := wound_kind(weapon, kind)
	var size := creature_size(root)
	if size < MIN_SIZE:
		return null
	if normal.length_squared() < 0.01:
		normal = (pos - root.global_position).normalized()
	normal = normal.normalized()
	var w := _make_wound(root, pos, normal, wk, size)
	if w == null:
		return null
	var cfg: Dictionary = KINDS[wk]
	var in_water := _in_water(pos)
	_spurt(pos, normal, int(cfg.spurt), in_water)
	if in_water:
		_water_blood(root, pos, float(cfg.bleed) * 2.5)
	if not _is_dead(root):
		if not _bleeders.has(root):
			_bleeders.append(root)
	elif not in_water:
		_drip_spot(pos, float(cfg.bleed))
	last.append({"target": root, "node": w, "kind": wk, "pos": pos})
	if last.size() > 32:
		last.pop_front()
	return w

## Корень существа: хитбокс → его цель; иначе вверх до Animal/Shark/морской особи.
static func creature_root(n: Node) -> Node3D:
	if n == null or not is_instance_valid(n):
		return null
	if n is CreatureHitbox:
		return (n as CreatureHitbox).target
	var cur := n
	while cur:
		if cur.is_in_group(&"characters") or cur.is_in_group(&"player") or cur.is_in_group(&"bots") \
				or cur.is_in_group(&"buildable"):
			return null
		if cur is Animal or cur is Shark or cur is SeaCreature or cur is SeaCritter or cur is UserSeaActor \
				or cur.is_in_group(&"animals") or cur.is_in_group(&"sharks") or cur.has_node(^"CreatureHitbox"):
			return cur as Node3D
		cur = cur.get_parent()
	return null

static func creature_size(root: Node3D) -> float:
	if root.has_meta(&"wound_size"):
		return float(root.get_meta(&"wound_size"))
	var ab := CreatureHitbox.local_bounds(root)
	var s := ab.get_longest_axis_size() * maxf(root.global_basis.get_scale().x, 0.001)
	root.set_meta(&"wound_size", s)
	return s

static func wound_kind(weapon: StringName, kind: StringName) -> StringName:
	var w := String(weapon)
	if kind == &"bite" or kind == &"animal":
		return &"bite"
	if w.contains("shotgun") or w.contains("12"):
		return &"pellet"
	if w.contains("rifle") or w.contains("ak") or w.contains("sniper") or w.contains("ar15") or w.contains("musket"):
		return &"bullet_rifle"
	if w.contains("pistol") or w.contains("revolver") or w.contains("9mm") or w.contains("smg"):
		return &"bullet_small"
	if w.contains("arrow") or w.contains("bolt") or w.contains("bow"):
		return &"arrow"
	if w.contains("spear") or w.contains("harpoon"):
		return &"spear"
	if w.contains("machete") or w.contains("knife") or w.contains("sword") or w.contains("blade"):
		return &"cut"
	if w.contains("axe") or kind == &"axe":
		return &"chop"
	if kind == &"bullet":
		return &"bullet_small"
	if w.contains("club") or w.contains("rock") or w.contains("stone") or w == "" or w == "hand":
		return &"blunt"
	return &"cut" if kind == &"melee" else &"bullet_small"

func _make_wound(root: Node3D, pos: Vector3, normal: Vector3, wk: StringName, size: float) -> Node3D:
	var count := int(root.get_meta(&"wound_count", 0))
	if count >= MAX_WOUNDS_PER:
		# самая старая рана уступает место
		var old: Array = root.get_meta(&"wound_nodes", [])
		if not old.is_empty():
			var o: Variant = old.pop_front()
			if is_instance_valid(o):
				(o as Node).queue_free()
			root.set_meta(&"wound_nodes", old)
	var cfg: Dictionary = KINDS[wk]
	var k := clampf(sqrt(size / 1.5), 0.7, 2.2)     # крупный зверь — рана чуть больше
	var r := float(cfg.r) * k
	var parent := _attach_parent(root, pos)
	var mi := MeshInstance3D.new()
	mi.name = "Wound"
	var q := QuadMesh.new()
	q.size = Vector2(r * 2.0 * float(cfg.len), r * 2.0)
	mi.mesh = q
	mi.material_override = _wound_material(wk)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# ось Z квада — нормаль поверхности, порез — вдоль случайного направления в плоскости
	var z := normal
	var tmp := Vector3.UP if absf(z.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var x := tmp.cross(z).normalized().rotated(z, randf() * TAU)
	var y := z.cross(x).normalized()
	var xf := Transform3D(Basis(x, y, z), pos + normal * 0.004)
	parent.add_child(mi)
	mi.global_transform = xf
	# подтёк крови вокруг — больший полупрозрачный квад
	var sp := MeshInstance3D.new()
	sp.name = "WoundBlood"
	var q2 := QuadMesh.new()
	q2.size = Vector2(r * 5.0 * float(cfg.len) * 0.6 + r * 2.5, r * 5.0)
	sp.mesh = q2
	sp.material_override = _smear_material()
	sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(sp)
	sp.global_transform = Transform3D(Basis(x, y, z), pos + normal * 0.003 - y * r * 0.8)
	mi.set_meta(&"bleed", float(cfg.bleed))
	mi.set_meta(&"born", _t)
	mi.add_to_group(&"wound")
	var nodes: Array = root.get_meta(&"wound_nodes", [])
	nodes.append(mi)
	root.set_meta(&"wound_nodes", nodes)
	root.set_meta(&"wound_count", nodes.size())
	return mi

## Родитель раны: кость скелета рядом с точкой (BoneAttachment3D), иначе сам корень.
func _attach_parent(root: Node3D, pos: Vector3) -> Node3D:
	var sk := _skeleton_of(root)
	if sk == null or sk.get_bone_count() == 0:
		return root
	var best := -1
	var bd := INF
	var inv := sk.global_transform
	for i in sk.get_bone_count():
		var bp := inv * sk.get_bone_global_pose(i).origin
		var d := bp.distance_squared_to(pos)
		if d < bd:
			bd = d
			best = i
	if best < 0:
		return root
	var bname := sk.get_bone_name(best)
	var an := "WoundBone_%d" % best
	var att := sk.get_node_or_null(NodePath(an)) as BoneAttachment3D
	if att == null:
		att = BoneAttachment3D.new()
		att.name = an
		sk.add_child(att)
		att.bone_name = bname
		att.global_transform = inv * sk.get_bone_global_pose(best)
	return att

static func _skeleton_of(root: Node3D) -> Skeleton3D:
	var list := root.find_children("*", "Skeleton3D", true, false)
	var best: Skeleton3D = null
	for s: Node in list:
		var sk := s as Skeleton3D
		if best == null or sk.get_bone_count() > best.get_bone_count():
			best = sk
	return best

# ============================== кровь ==============================

func _spurt(pos: Vector3, normal: Vector3, n: int, in_water: bool) -> void:
	var host := _fx_host()
	if host == null or n <= 0:
		return
	var p := CPUParticles3D.new()
	p.name = "BloodSpurt"
	p.one_shot = true
	p.emitting = false
	p.amount = n
	p.lifetime = 1.4 if in_water else 0.7
	p.explosiveness = 0.85
	p.direction = normal
	p.spread = 22.0
	p.initial_velocity_min = 0.6 if in_water else 1.4
	p.initial_velocity_max = 1.2 if in_water else 3.2
	p.gravity = Vector3(0, -0.3, 0) if in_water else Vector3(0, -9.8, 0)
	p.damping_min = 2.5 if in_water else 0.2
	p.damping_max = 4.0 if in_water else 0.6
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var m := SphereMesh.new()
	m.radius = 0.008 if not in_water else 0.02
	m.height = m.radius * 2.0
	m.radial_segments = 6
	m.rings = 3
	m.material = _drop_material()
	p.mesh = m
	var g := Gradient.new()
	g.set_color(0, Color(0.55, 0.02, 0.02, 1.0))
	g.set_color(1, Color(0.3, 0.0, 0.0, 0.0 if in_water else 0.9))
	p.color_ramp = g
	host.add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(p.lifetime + 0.5, false).timeout.connect(p.queue_free)
	if not in_water:
		# первые капли падают на землю под раной
		_drip_spot(pos + normal * 0.25, 1.2)

func _bleed_tick(dt: float) -> void:
	if _bleeders.is_empty():
		return
	for i in range(_bleeders.size() - 1, -1, -1):
		var root := _bleeders[i]
		if not is_instance_valid(root) or not root.is_inside_tree():
			_bleeders.remove_at(i)
			continue
		var dead := _is_dead(root)
		var any := false
		for w: Variant in root.get_meta(&"wound_nodes", []):
			if not is_instance_valid(w):
				continue
			var mi := w as Node3D
			var age := _t - float(mi.get_meta(&"born", _t))
			var s := float(mi.get_meta(&"bleed", 1.0)) * clampf(1.0 - age / BLEED_TIME, 0.0, 1.0)
			if s <= 0.02:
				continue
			any = true
			# частота капель ~ сила кровотечения; после смерти — ещё немного и стоп
			var rate := s * (0.35 if dead else 1.2)
			if randf() < rate * dt:
				var wp := mi.global_position
				if _in_water(wp):
					_water_blood(root, wp, s)
				else:
					_drip_spot(wp, s)
					_drop(wp)
		if dead:
			# туша: одна лужа под телом и кровотечение кончается
			if not root.get_meta(&"wound_pool", false):
				root.set_meta(&"wound_pool", true)
				var p := root.global_position
				if not _in_water(p):
					_drip_spot(p + Vector3.UP * 0.3, 3.5)
			_bleeders.remove_at(i)
		elif not any:
			_bleeders.remove_at(i)

func _water_blood(root: Node3D, pos: Vector3, s: float) -> void:
	var id := root.get_instance_id()
	var last_t := float(_cloud_t.get(id, -10.0))
	var sea := get_tree().get_first_node_in_group(&"sea")
	if sea == null or not sea.has_method(&"add_blood"):
		return
	var cloud := _t - last_t > 1.6
	if cloud:
		_cloud_t[id] = _t
	sea.call(&"add_blood", pos, clampf(s * 3.0, 0.5, 8.0), cloud)

## Капля, падающая с раны (короткая частица).
func _drop(pos: Vector3) -> void:
	var host := _fx_host()
	if host == null:
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 2
	p.lifetime = 0.6
	p.explosiveness = 0.6
	p.direction = Vector3.DOWN
	p.spread = 6.0
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.3
	p.gravity = Vector3(0, -9.8, 0)
	var m := SphereMesh.new()
	m.radius = 0.006
	m.height = 0.014
	m.radial_segments = 5
	m.rings = 2
	m.material = _drop_material()
	p.mesh = m
	host.add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.0, false).timeout.connect(p.queue_free)

## Пятно крови на земле под точкой (луч вниз). s — размер/сила.
func _drip_spot(from: Vector3, s: float) -> void:
	var host := _fx_host()
	if host == null or not is_inside_tree():
		return
	var space := (host as Node3D).get_world_3d().direct_space_state if host is Node3D else null
	if space == null:
		return
	var q := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 0.1, from + Vector3.DOWN * 4.0)
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var p: Vector3 = hit.position
	if _in_water(p + Vector3.UP * 0.02):
		return
	var nrm: Vector3 = hit.normal
	if _spots.size() >= MAX_SPOTS:
		var o: Variant = _spots.pop_front()
		if is_instance_valid(o):
			o.queue_free()
	var mi := MeshInstance3D.new()
	mi.name = "BloodSpot"
	var q2 := QuadMesh.new()
	var r := clampf(0.035 * sqrt(s) * randf_range(0.7, 1.4), 0.02, 0.22)
	q2.size = Vector2(r * 2.0, r * 2.0 * randf_range(0.7, 1.0))
	mi.mesh = q2
	var mat := _spot_material()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(mi)
	var z := nrm.normalized()
	var tmp := Vector3.FORWARD if absf(z.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := tmp.cross(z).normalized().rotated(z, randf() * TAU)
	mi.global_transform = Transform3D(Basis(x, z.cross(x), z), p + z * 0.012)
	mi.add_to_group(&"blood_spot")
	_spots.append(mi)
	var tw := mi.create_tween()
	tw.tween_interval(SPOT_LIFE)
	tw.tween_property(mat, ^"albedo_color:a", 0.0, 8.0)
	tw.tween_callback(mi.queue_free)

# ============================== вспомогательное ==============================

func _fx_host() -> Node:
	if is_instance_valid(_host) and _host.is_inside_tree():
		return _host
	var t := get_tree()
	if t == null:
		return null
	var cs := t.current_scene
	if cs is Node3D:
		_host = cs as Node3D
		return _host
	var w := t.get_first_node_in_group(&"world")
	if w is Node3D:
		_host = w as Node3D
		return _host
	return cs if cs else t.root

func _in_water(p: Vector3) -> bool:
	var ws := BuildEnv.water_surface(p.x, p.z)
	return ws > -1e5 and p.y < ws - 0.05

static func _is_dead(root: Node3D) -> bool:
	if not is_instance_valid(root):
		return true
	if root.has_method(&"is_dead"):
		return bool(root.call(&"is_dead"))
	var hb := root.get_node_or_null(^"CreatureHitbox") as CreatureHitbox
	if hb:
		return hb.dead
	return bool(root.get(&"dead")) if &"dead" in root else false

func _wound_material(wk: StringName) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _wound_texture(wk)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.25
	m.metallic_specular = 0.7
	m.render_priority = 2
	return m

func _smear_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _spot_texture()
	m.albedo_color = Color(0.45, 0.02, 0.02, 0.75)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.3
	m.render_priority = 1
	return m

func _spot_material() -> StandardMaterial3D:
	if _spot_mat_base == null:
		_spot_mat_base = StandardMaterial3D.new()
		_spot_mat_base.albedo_texture = _spot_texture()
		_spot_mat_base.albedo_color = Color(0.32, 0.01, 0.01, 0.92)
		_spot_mat_base.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_spot_mat_base.roughness = 0.35
		_spot_mat_base.render_priority = 1
	return _spot_mat_base.duplicate() as StandardMaterial3D

func _drop_material() -> StandardMaterial3D:
	if _drop_mat == null:
		_drop_mat = StandardMaterial3D.new()
		_drop_mat.albedo_color = Color(0.5, 0.02, 0.02)
		_drop_mat.vertex_color_use_as_albedo = true
		_drop_mat.roughness = 0.2
		_drop_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return _drop_mat

## Текстура раны: тёмная середина, красная мякоть, рваный край (процедурно, 64×64).
func _wound_texture(wk: StringName) -> ImageTexture:
	var key := &"blunt" if wk == &"blunt" else &"open"
	if _wound_tex.has(key):
		return _wound_tex[key]
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.18
	for y in n:
		for x in n:
			var u := (x + 0.5) / n * 2.0 - 1.0
			var v := (y + 0.5) / n * 2.0 - 1.0
			var d := sqrt(u * u + v * v) + noise.get_noise_2d(x, y) * 0.22
			var c: Color
			if key == &"blunt":
				# ушиб/ссадина: тёмно-багровое пятно без дыры
				var a := clampf(1.0 - d, 0.0, 1.0)
				c = Color(0.35, 0.05, 0.08, pow(a, 0.7) * 0.85)
			elif d < 0.32:
				c = Color(0.08, 0.0, 0.0, 1.0)                  # отверстие
			elif d < 0.62:
				var k := (d - 0.32) / 0.3
				c = Color(0.55 - k * 0.15, 0.03, 0.03, 1.0)     # мякоть
			elif d < 0.95:
				var k2 := (d - 0.62) / 0.33
				c = Color(0.4, 0.02, 0.02, 1.0 - k2)            # кровь вокруг
			else:
				c = Color(0, 0, 0, 0)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_wound_tex[key] = tex
	return tex

## Текстура пятна крови: неровная клякса с брызгами (64×64).
func _spot_texture() -> ImageTexture:
	if _spot_tex:
		return _spot_tex
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 11
	noise.frequency = 0.09
	for y in n:
		for x in n:
			var u := (x + 0.5) / n * 2.0 - 1.0
			var v := (y + 0.5) / n * 2.0 - 1.0
			var d := sqrt(u * u + v * v) + noise.get_noise_2d(x, y) * 0.45
			var a := clampf((0.85 - d) * 5.0, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	_spot_tex = ImageTexture.create_from_image(img)
	return _spot_tex
