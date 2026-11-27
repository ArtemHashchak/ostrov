extends Node
## Раны и кровь на крупных существах (v5.1, агент I). Автозагрузка «Wounds».
## Любое попадание по существу крупнее MIN_SIZE (пуля, дробь, стрела, острога, нож, мачете, топор, удар)
## оставляет рану ровно в точке попадания: она прикреплена к ближайшей кости скелета (BoneAttachment3D)
## и двигается с телом, остаётся на туше. Из раны бьёт струйка крови, пока зверь жив — капает:
## на суше пятна на земле (след крови), в воде — облако крови через Sea.add_blood (акулы чуют).
## Источники: Combat.hit_landed (пули, стрелы, острога, удары ботов) и Events.player_swing (удар игрока).
## Рана и подтёки рисуются в маске повреждений в UV меша (DamageMask + шейдер blood_overlay, next_pass):
## кровь лежит прямо на коже и течёт по ней вниз. Работает в gl_compatibility и Forward+ (не Decal).

const MIN_SIZE := 0.5          # наибольший габарит существа (м), начиная с которого — раны
const MAX_WOUNDS_PER := 24     # ран на одном существе
const MAX_SPOTS := 220         # пятен крови на земле всего
const SPOT_LIFE := 120.0       # с, потом пятно тает
const BLEED_TIME := 45.0       # с, за которые кровотечение раны стихает

## Тип раны по оружию: r — радиус (м), len — вытянутость (порез), bleed — сила кровотечения.
const KINDS := {
	&"bullet_small": {"r": 0.012, "len": 1.0, "bleed": 0.9, "spurt": 30, "tex": &"hole", "drips": 3},
	&"bullet_rifle": {"r": 0.017, "len": 1.0, "bleed": 1.2, "spurt": 44, "tex": &"hole", "drips": 4},
	&"exit": {"r": 0.04, "len": 1.15, "bleed": 1.6, "spurt": 50, "tex": &"exit", "drips": 5},
	&"pellet": {"r": 0.008, "len": 1.0, "bleed": 0.45, "spurt": 12, "tex": &"hole", "drips": 1},
	&"arrow": {"r": 0.015, "len": 1.5, "bleed": 1.0, "spurt": 22, "tex": &"hole", "drips": 3},
	&"spear": {"r": 0.022, "len": 1.7, "bleed": 1.3, "spurt": 30, "tex": &"gash", "drips": 4},
	&"cut": {"r": 0.016, "len": 4.2, "bleed": 1.4, "spurt": 34, "tex": &"gash", "drips": 5},
	&"chop": {"r": 0.024, "len": 3.4, "bleed": 1.7, "spurt": 40, "tex": &"gash", "drips": 5},
	&"blunt": {"r": 0.04, "len": 1.25, "bleed": 0.25, "spurt": 6, "tex": &"bruise", "drips": 0},
	&"bite": {"r": 0.04, "len": 1.5, "bleed": 1.4, "spurt": 26, "tex": &"gash", "drips": 4},
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
var _masks: Array[DamageMask] = []     # живые маски повреждений (подтёки ползут, текстура обновляется)
## Для тестов: последние раны [{target, node, kind, pos}]
var last: Array[Dictionary] = []
## Куда класть брызги и пятна (тесты/витрины в своём SubViewport); иначе — текущая сцена.
var host_override: Node3D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_try_hook()

func _process(dt: float) -> void:
	_t += dt
	if not _combat_hooked or not _swing_hooked:
		_try_hook()
	_bleed_tick(dt)
	for i in range(_masks.size() - 1, -1, -1):
		var dm := _masks[i]
		if not is_instance_valid(dm.mi):
			_masks.remove_at(i)
			continue
		dm.tick(dt)

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
	# точка попадания — на коробке хитбокса; рану ставим на настоящую кожу (кость + её толщина)
	var surf := surface_point(root, pos, normal)
	pos = surf.pos
	normal = surf.normal
	var w := _make_wound(root, pos, normal, wk, size, int(surf.bone))
	if w == null:
		return null
	# винтовочная пуля навылет через небольшое тело (до ~0,6 м толщиной): выходное отверстие больше
	if wk == &"bullet_rifle" and float(surf.thick) > 0.0 and float(surf.thick) < 0.6 and surf.has("exit_pos"):
		var ep: Vector3 = surf.exit_pos
		var en: Vector3 = surf.exit_normal
		_make_wound(root, ep, en, &"exit", size, int(surf.bone))
		_spurt(ep, en, int(KINDS[&"exit"].spurt), _in_water(ep))
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

func _make_wound(root: Node3D, pos: Vector3, normal: Vector3, wk: StringName, size: float, bone := -1) -> Node3D:
	var count := int(root.get_meta(&"wound_count", 0))
	if count >= MAX_WOUNDS_PER:
		# самая старая рана уступает место
		var old: Array = root.get_meta(&"wound_nodes", [])
		if not old.is_empty():
			var o: Variant = old.pop_front()
			if is_instance_valid(o):
				for ch: Variant in (o as Node).get_meta(&"parts", []):
					if is_instance_valid(ch):
						(ch as Node).queue_free()
				(o as Node).queue_free()
			root.set_meta(&"wound_nodes", old)
	var cfg: Dictionary = KINDS[wk]
	var k := clampf(sqrt(size / 1.5), 0.7, 2.2)     # крупный зверь — рана чуть больше
	var r := float(cfg.r) * k
	var parent := _attach_parent(root, pos, bone)
	var parts: Array = []
	# 1) основной путь: рана и подтёки рисуются в маске повреждений (UV меша) — кровь прямо на коже
	var painted := _paint_mask(root, pos, normal, wk, r, size, bone)
	var mi: Node3D
	if painted.is_empty():
		# запасной путь (меш без UV/треугольников): только пятно раны квадом, без подтёков-полосок
		var z := normal
		var down := Vector3.DOWN - z * Vector3.DOWN.dot(z)
		if down.length_squared() < 0.01:
			down = (Vector3.FORWARD - z * Vector3.FORWARD.dot(z))
		var y := -down.normalized()
		var x := y.cross(z).normalized()
		var ang := randf_range(-1.0, 1.0) if cfg.tex == &"gash" else randf() * TAU
		var xr := x.rotated(z, ang)
		var yr := z.cross(xr).normalized()
		mi = _quad(parent, Vector2(r * 2.0 * float(cfg.len), r * 2.0), _wound_material(StringName(cfg.tex)),
			Transform3D(Basis(xr, yr, z), pos + z * 0.004))
	else:
		# узел-метка раны на кости (кровотечение, тесты); видимое — в маске
		mi = Node3D.new()
		parent.add_child(mi)
		mi.global_position = pos
		mi.set_meta(&"mask", painted.mask)
		mi.set_meta(&"uv", painted.uv)
	mi.name = "Wound"
	mi.set_meta(&"parts", parts)
	mi.set_meta(&"bleed", float(cfg.bleed))
	mi.set_meta(&"born", _t)
	mi.set_meta(&"kind", wk)
	mi.set_meta(&"normal", normal)
	mi.add_to_group(&"wound")
	var nodes: Array = root.get_meta(&"wound_nodes", [])
	nodes.append(mi)
	root.set_meta(&"wound_nodes", nodes)
	root.set_meta(&"wound_count", nodes.size())
	return mi

## Главный меш существа с UV (крупнейший по числу вершин) и его скелет.
static func _body_mesh(root: Node3D) -> MeshInstance3D:
	var best: MeshInstance3D = null
	var bn := 0
	for m: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree() or mi.mesh is PrimitiveMesh:
			continue
		if mi.get_parent() is BoneAttachment3D:
			continue
		var n := 0
		for si in mi.mesh.get_surface_count():
			if mi.mesh.surface_get_format(si) & Mesh.ARRAY_FORMAT_TEX_UV:
				n += mi.mesh.surface_get_array_len(si)
		if n > bn:
			bn = n
			best = mi
	return best

## Рана в маску повреждений: луч по треугольникам меша → UV → рисунок раны, + подтёки по коже.
## → {mask, uv} или {} (нет подходящего меша).
func _paint_mask(root: Node3D, pos: Vector3, normal: Vector3, wk: StringName, r: float, size: float, bone: int) -> Dictionary:
	var body := _body_mesh(root)
	if body == null:
		return {}
	var sk: Skeleton3D = null
	if body.skin:
		sk = body.get_node_or_null(body.skeleton) as Skeleton3D
		if sk == null:
			sk = _skeleton_of(root)
	var dm := DamageMask.of(body, sk, size > 1.5)
	if dm == null:
		return {}
	if not _masks.has(dm):
		_masks.append(dm)
	var ws := maxf(dm.world_scale(), 1e-4)
	var p_rest := dm.to_rest(pos, bone)
	var n_rest := dm.dir_to_rest(normal, bone)
	var hit := dm.raycast(p_rest + n_rest * (0.25 / ws), -n_rest, 0.6 / ws)
	if hit.is_empty():
		var q := dm.closest(p_rest)
		if q.is_empty() or float(q.d) * ws > 0.2:
			return {}
		hit = q
	var cfg: Dictionary = KINDS[wk]
	var tex := StringName(cfg.tex)
	# направление разреза: косо-горизонтально по боку (мачете/топор/клыки)
	var cut := normal.cross(Vector3.UP)
	if cut.length_squared() < 0.01:
		cut = normal.cross(Vector3.RIGHT)
	cut = cut.normalized().rotated(normal, randf_range(-0.6, 0.6))
	var hp: Vector3 = hit.p
	var g_rest := dm.dir_to_rest(Vector3.DOWN, bone)
	var cut_rest := dm.dir_to_rest(cut, bone)
	var rr := r
	if tex == &"gash":
		rr = r * 0.8
	elif tex == &"bruise":
		rr = r * 0.8
	dm.paint_wound(hp, n_rest, tex, rr, cut_rest, g_rest)
	# подтёки: от нижнего края раны вниз по коже, 2–5 с, по проекции силы тяжести на поверхность
	var nd := int(cfg.drips)
	var span := r * (float(cfg.len) * 0.7 if tex == &"gash" else 0.8)
	var gt := g_rest - n_rest * g_rest.dot(n_rest)
	gt = gt.normalized() if gt.length() > 0.1 else Vector3.ZERO
	for i in nd:
		var off := (randf_range(-1.0, 1.0) * span) / ws
		var start := hp + cut_rest * off + gt * (r * randf_range(0.5, 1.4) / ws)
		var L := r * randf_range(5.0, 12.0) * (0.8 + float(cfg.bleed) * 0.4)
		dm.add_drip(start, g_rest, clampf(L, 0.05, 0.3), randf_range(2.0, 5.0), r * randf_range(0.2, 0.34), randf_range(0.0, 0.8))
	return {"mask": dm, "uv": dm.uv_of(int(hit.tri), hit.bary)}

func _quad(parent: Node3D, sz: Vector2, mat: Material, xf: Transform3D, center := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = sz
	q.center_offset = center
	mi.mesh = q
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_transform = xf
	return mi

## Родитель раны: кость скелета рядом с точкой (BoneAttachment3D), иначе сам корень.
func _attach_parent(root: Node3D, pos: Vector3, bone := -1) -> Node3D:
	var sk := _skeleton_of(root)
	if sk == null or sk.get_bone_count() == 0:
		return root
	var best := bone
	var inv := sk.global_transform
	if best < 0:
		var bd := INF
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

# ============================== поверхность тела ==============================

static var _radii_cache: Dictionary = {}   # id меша → {bone: радиус}

## Точка на коже рядом с попаданием: ближайшая к точке кость (отрезок кость→дочерняя) и её толщина
## (из вершин меша в позе покоя). Без скелета — точка как есть. → {pos, normal, bone}
static func surface_point(root: Node3D, pos: Vector3, normal: Vector3) -> Dictionary:
	var out := {"pos": pos, "normal": normal, "bone": -1, "thick": -1.0}
	var sk := _skeleton_of(root)
	if sk == null or sk.get_bone_count() == 0:
		return out
	var radii := _bone_radii(root, sk)
	if radii.is_empty():
		return out
	var gx := sk.global_transform
	var ks := gx.basis.get_scale().x
	# луч «пули» снаружи внутрь (против нормали коробки) — первая капсула кости, в которую он входит
	var o := pos + normal * 0.6
	var dir := -normal
	var far := o + dir * 3.0
	var best := -1
	var best_t := INF
	var best_p := Vector3.ZERO
	var best_n := normal
	var near_b := -1
	var near_d := INF
	var near_c := Vector3.ZERO
	for b: int in radii:
		var seg := _segment(sk, b)
		var a: Vector3 = gx * seg[0]
		var e: Vector3 = gx * seg[1]
		var r := float(radii[b]) * ks
		var cps := Geometry3D.get_closest_points_between_segments(o, far, a, e)
		var d: float = (cps[0] as Vector3).distance_to(cps[1])
		if d < r:
			var tc: float = ((cps[0] as Vector3) - o).dot(dir)
			var t := tc - sqrt(maxf(r * r - d * d, 0.0))
			if t < best_t:
				best_t = t
				best = b
				best_p = o + dir * maxf(t, 0.0)
				var cc := Geometry3D.get_closest_point_to_segment(best_p, a, e)
				best_n = (best_p - cc).normalized() if best_p.distance_to(cc) > 1e-4 else normal
				# выход: луч покидает капсулу с другой стороны (сквозное ранение)
				var te := tc + sqrt(maxf(r * r - d * d, 0.0))
				var ep := o + dir * te
				var ce := Geometry3D.get_closest_point_to_segment(ep, a, e)
				out["exit_pos"] = ep
				out["exit_normal"] = (ep - ce).normalized() if ep.distance_to(ce) > 1e-4 else dir
				out["thick"] = te - t
		# запасной вариант: ближайшая кость к точке попадания
		var c := Geometry3D.get_closest_point_to_segment(pos, a, e)
		var dd := pos.distance_to(c) - r
		if dd < near_d:
			near_d = dd
			near_b = b
			near_c = c
	if best >= 0:
		out.pos = best_p
		out.normal = best_n
		out.bone = best
		return out
	if near_b < 0:
		return out
	var dir2 := pos - near_c
	dir2 = dir2.normalized() if dir2.length_squared() > 1e-6 else normal
	out.pos = near_c + dir2 * float(radii[near_b]) * ks
	out.normal = dir2
	out.bone = near_b
	return out

## Отрезок кости в пространстве скелета: от неё к первой дочерней (лист — продолжение родителя).
static func _segment(sk: Skeleton3D, b: int) -> Array:
	var h := sk.get_bone_global_pose(b).origin
	var ch := sk.get_bone_children(b)
	if not ch.is_empty():
		return [h, sk.get_bone_global_pose(ch[0]).origin]
	var p := sk.get_bone_parent(b)
	if p >= 0:
		var hp := sk.get_bone_global_pose(p).origin
		return [h, h + (h - hp) * 0.5]
	return [h, h]

## Толщина тела у каждой кости: 85-й перцентиль расстояний её вершин до отрезка кости (поза покоя).
static func _bone_radii(root: Node3D, sk: Skeleton3D) -> Dictionary:
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	var key := ""
	for m: Node in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh and mi.skin:
			key += str(mi.mesh.get_rid().get_id()) + "_"
	if key == "":
		return {}
	if _radii_cache.has(key):
		return _radii_cache[key]
	var dists := {}     # bone → Array[float] (Array — по ссылке; Packed* копировались бы)
	for m: Node in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh == null or mi.skin == null:
			continue
		var skin := mi.skin
		# bind индекс → кость скелета
		var bind_bone := PackedInt32Array()
		bind_bone.resize(skin.get_bind_count())
		for bi in skin.get_bind_count():
			var bn := skin.get_bind_bone(bi)
			if bn < 0:
				bn = sk.find_bone(skin.get_bind_name(bi))
			bind_bone[bi] = bn
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bo: Variant = arr[Mesh.ARRAY_BONES]
			var we: Variant = arr[Mesh.ARRAY_WEIGHTS]
			if not (bo is PackedInt32Array) or not (we is PackedFloat32Array) or v.is_empty():
				continue
			var bones: PackedInt32Array = bo
			var wts: PackedFloat32Array = we
			var per := bones.size() / v.size()
			var step := maxi(1, v.size() / 6000)
			for i in range(0, v.size(), step):
				# главная кость вершины
				var bw := -1.0
				var bix := -1
				for k in per:
					var w := wts[i * per + k]
					if w > bw:
						bw = w
						bix = bones[i * per + k]
				if bix < 0 or bix >= bind_bone.size():
					continue
				var b := bind_bone[bix]
				if b < 0:
					continue
				var vp := sk.get_bone_global_rest(b) * (skin.get_bind_pose(bix) * v[i])
				var seg := _segment_rest(sk, b)
				var c := Geometry3D.get_closest_point_to_segment(vp, seg[0], seg[1])
				if not dists.has(b):
					dists[b] = []
				(dists[b] as Array).append(vp.distance_to(c))
	var out := {}
	for b: int in dists:
		var arr2: Array = dists[b]
		if arr2.size() < 6:
			continue
		arr2.sort()
		out[b] = arr2[int(arr2.size() * 0.85)]
	_radii_cache[key] = out
	return out

static func _segment_rest(sk: Skeleton3D, b: int) -> Array:
	var h := sk.get_bone_global_rest(b).origin
	var ch := sk.get_bone_children(b)
	if not ch.is_empty():
		return [h, sk.get_bone_global_rest(ch[0]).origin]
	var p := sk.get_bone_parent(b)
	if p >= 0:
		var hp := sk.get_bone_global_rest(p).origin
		return [h, h + (h - hp) * 0.5]
	return [h, h]

# ============================== кровь ==============================

func _spurt(pos: Vector3, normal: Vector3, n: int, in_water: bool) -> void:
	var host := _fx_host()
	if host == null or n <= 0:
		return
	var p := CPUParticles3D.new()
	p.name = "BloodSpurt"
	p.add_to_group(&"blood_spurt")
	p.one_shot = true
	p.emitting = false
	p.amount = int(n * 1.3)
	p.lifetime = 1.6 if in_water else 0.9
	p.explosiveness = 0.85
	p.direction = normal
	p.spread = 22.0
	p.initial_velocity_min = 0.6 if in_water else 1.2
	p.initial_velocity_max = 1.4 if in_water else 3.6
	p.gravity = Vector3(0, -0.3, 0) if in_water else Vector3(0, -9.8, 0)
	p.damping_min = 2.5 if in_water else 0.2
	p.damping_max = 4.0 if in_water else 0.6
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var m := SphereMesh.new()
	m.radius = 0.014 if not in_water else 0.025
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
			# туша: одна лужа под телом и кровотечение кончается; кровь вокруг ран засыхает и расползается
			if not root.get_meta(&"wound_pool", false):
				root.set_meta(&"wound_pool", true)
				_mat_corpse(root)
				var p := root.global_position
				if not _in_water(p):
					_drip_spot(p + Vector3.UP * 0.3, 3.5)
			_bleeders.remove_at(i)
		elif not any:
			_bleeders.remove_at(i)

## Туша: пятна крови вокруг ран за ~25 с расползаются вдвое, темнеют (запёкшаяся, бурая), подтёки длиннее.
func _mat_corpse(root: Node3D) -> void:
	var body := _body_mesh(root)
	if body == null or not body.has_meta(&"damage_mask"):
		return
	var dm: DamageMask = body.get_meta(&"damage_mask")
	var tw := body.create_tween().set_parallel(true)
	tw.tween_method(func(v: float) -> void: dm.set_corpse(v, dm.dry), 0.0, 1.0, 25.0).set_trans(Tween.TRANS_SINE)
	tw.tween_method(func(v: float) -> void: dm.set_corpse(dm.spread, v), 0.0, 1.0, 35.0)
	# кровь из ран расползается по коже (в 3D вокруг раны — швы UV не мешают)
	# из ран на туше ещё натекает: подтёки длиннее
	var g := Vector3.DOWN
	for w: Variant in root.get_meta(&"wound_nodes", []):
		if not (w is Node3D) or not is_instance_valid(w) or not (w as Node).has_meta(&"mask"):
			continue
		var wp := (w as Node3D).global_position
		var bone := -1
		var par := (w as Node).get_parent()
		if par is BoneAttachment3D and dm.sk:
			bone = dm.sk.find_bone((par as BoneAttachment3D).bone_name)
		var q := dm.closest(dm.to_rest(wp, bone))
		if q.is_empty():
			continue
		dm.add_seep(q.p, q.n, 0.06 * float((w as Node).get_meta(&"bleed", 1.0)) + 0.03, 25.0)
		for i in 2:
			dm.add_drip(q.p, dm.dir_to_rest(g, bone), randf_range(0.12, 0.25), randf_range(6.0, 12.0), 0.007, randf_range(0.0, 4.0))

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
	if is_instance_valid(host_override) and host_override.is_inside_tree():
		return host_override
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

func _wound_material(tex: StringName) -> StandardMaterial3D:
	var key := "mat_" + String(tex)
	if _wound_tex.has(key):
		return _wound_tex[key]
	var t := _wound_maps(tex)
	var m := StandardMaterial3D.new()
	m.albedo_texture = t[0]
	m.normal_enabled = true
	m.normal_texture = t[1]
	m.normal_scale = 1.6
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.14 if tex != &"bruise" else 0.5   # свежая кровь — мокрая, блестит
	m.metallic_specular = 0.85
	m.render_priority = 3
	_wound_tex[key] = m
	return m

## Кровь вокруг раны: своя копия (на туше темнеет и расползается).
func _smear_material() -> StandardMaterial3D:
	if not _wound_tex.has("mat_smear"):
		var t := _wound_maps(&"smear")
		var m0 := StandardMaterial3D.new()
		m0.albedo_texture = t[0]
		m0.normal_enabled = true
		m0.normal_texture = t[1]
		m0.normal_scale = 0.8
		m0.albedo_color = Color(1, 1, 1, 0.92)
		m0.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m0.cull_mode = BaseMaterial3D.CULL_DISABLED
		m0.roughness = 0.18
		m0.metallic_specular = 0.8
		m0.render_priority = 1
		_wound_tex["mat_smear"] = m0
	return _wound_tex["mat_smear"]

## Подтёк: узкая полоска, к низу тоньше, на конце капля.
func _streak_material() -> StandardMaterial3D:
	if not _wound_tex.has("mat_streak"):
		var t := _wound_maps(&"streak")
		var m := StandardMaterial3D.new()
		m.albedo_texture = t[0]
		m.normal_enabled = true
		m.normal_texture = t[1]
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.roughness = 0.12
		m.metallic_specular = 0.85
		m.render_priority = 2
		_wound_tex["mat_streak"] = m
	return _wound_tex["mat_streak"]

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

## Процедурные карты (128×128): [альбедо с альфой, карта нормалей] по виду:
##  hole — входное отверстие: чёрная глубина, рваный край мякоти, вывернутые лоскуты, кровь вокруг;
##  exit — выходное: шире, рваное, с вывернутой мякотью; gash — разрез: длинная щель с губами;
##  bruise — ушиб без дыры; smear — кровь вокруг (мокрая, от тёмно-красной к бурой);
##  streak — подтёк вниз (сверху шире, внизу капля). Нормали — из карты высот (дыра вдавлена).
func _wound_maps(kind: StringName) -> Array:
	var key := "maps_" + String(kind)
	if _wound_tex.has(key):
		return _wound_tex[key]
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var hgt := PackedFloat32Array()
	hgt.resize(n * n)
	var nz := FastNoiseLite.new()
	nz.seed = hash(kind) & 0xffff
	nz.frequency = 0.09
	var nz2 := FastNoiseLite.new()
	nz2.seed = (hash(kind) >> 8) & 0xffff
	nz2.frequency = 0.03
	for yy in n:
		for xx in n:
			var u := (xx + 0.5) / n * 2.0 - 1.0
			var v := (yy + 0.5) / n * 2.0 - 1.0
			var tone := nz2.get_noise_2d(xx, yy) * 0.5 + 0.5          # красный ↔ бурый
			var fresh := Color(0.36, 0.015, 0.02).lerp(Color(0.22, 0.04, 0.02), tone)
			var c := Color(0, 0, 0, 0)
			var h := 0.0
			match kind:
				&"hole", &"exit":
					var big := 1.0 if kind == &"hole" else 1.35
					var jag := nz.get_noise_2d(xx * (1.0 if kind == &"hole" else 1.8), yy) * (0.14 if kind == &"hole" else 0.32)
					var d := sqrt(u * u + v * v) * big + jag
					var hole_r := 0.22 if kind == &"hole" else 0.3
					if d < hole_r:
						c = Color(0.03, 0.0, 0.0, 1.0)                        # глубина
						h = -1.0 + d / hole_r * 0.4
					elif d < hole_r + 0.22:
						var kk := (d - hole_r) / 0.22                         # мякоть, вывернута
						c = Color(0.48, 0.06, 0.07).lerp(Color(0.3, 0.02, 0.02), kk)
						h = 0.25 + sin(kk * PI) * 0.35 + nz.get_noise_2d(xx * 3.0, yy * 3.0) * 0.25
					elif d < 0.98:
						var k2 := (d - hole_r - 0.22) / (0.98 - hole_r - 0.22)
						c = fresh
						c.a = clampf(1.0 - k2 * k2, 0.0, 1.0)
						h = 0.05 * (1.0 - k2)
				&"gash":
					var ww := 0.28 + nz.get_noise_2d(xx * 0.6, 0.0) * 0.08     # ширина щели вдоль
					var e2 := absf(u) * 1.05 + nz2.get_noise_2d(xx, yy * 0.2) * 0.05
					var vv := absf(v) / maxf(ww * (1.0 - pow(e2, 4.0)), 0.02)
					if e2 > 1.0:
						vv = 9.0
					if vv < 0.35:
						c = Color(0.04, 0.0, 0.0, 1.0)
						h = -1.0 + vv
					elif vv < 1.0:
						var k3 := (vv - 0.35) / 0.65
						c = Color(0.5, 0.07, 0.08).lerp(Color(0.32, 0.02, 0.02), k3)
						h = 0.3 * sin(k3 * PI) + 0.1
					elif vv < 2.6:
						var k4 := (vv - 1.0) / 1.6
						c = fresh
						c.a = clampf(1.0 - k4, 0.0, 1.0) * clampf((1.0 - e2) * 4.0, 0.0, 1.0)
						h = 0.04 * (1.0 - k4)
				&"bruise":
					var d2 := sqrt(u * u + v * v) + nz.get_noise_2d(xx, yy) * 0.12
					var a := clampf(1.0 - d2, 0.0, 1.0)
					c = Color(0.3, 0.06, 0.09, pow(a, 0.8) * 0.8)
					h = a * 0.15
				&"smear":
					var d3 := sqrt(u * u * 0.9 + v * v) + nz.get_noise_2d(xx, yy) * 0.35
					var a2 := clampf((0.85 - d3) * 4.0, 0.0, 1.0)
					c = fresh.darkened(0.15)
					c.a = a2 * 0.9
					h = a2 * 0.1
				&"streak":
					# u — поперёк, v от -1 (верх, у раны) до 1 (низ): к низу тоньше, капля на конце
					var t01 := (v + 1.0) * 0.5
					var wdt := lerpf(0.75, 0.32, t01) + nz.get_noise_2d(0.0, yy * 2.0) * 0.1
					var drop := 0.0
					if t01 > 0.86:
						var dy := (t01 - 0.93) / 0.07
						drop = clampf(1.0 - sqrt(u * u / 0.55 + dy * dy), 0.0, 1.0)
					var a3 := clampf((wdt - absf(u)) * 6.0, 0.0, 1.0) * (1.0 if t01 < 0.88 else 0.0)
					a3 = maxf(a3, ceilf(drop))
					c = fresh.darkened(0.25)
					c.a = a3 * 0.88
					h = 0.2 * maxf(a3 * (1.0 - absf(u) / maxf(wdt, 0.05)), drop)
			img.set_pixel(xx, yy, c)
			hgt[yy * n + xx] = h
	var nimg := Image.create(n, n, false, Image.FORMAT_RGB8)
	for yy in n:
		for xx in n:
			var hl := hgt[yy * n + maxi(xx - 1, 0)]
			var hr := hgt[yy * n + mini(xx + 1, n - 1)]
			var hu := hgt[maxi(yy - 1, 0) * n + xx]
			var hd := hgt[mini(yy + 1, n - 1) * n + xx]
			var nv := Vector3((hl - hr) * 2.5, (hd - hu) * 2.5, 1.0).normalized()
			nimg.set_pixel(xx, yy, Color(nv.x * 0.5 + 0.5, nv.y * 0.5 + 0.5, nv.z * 0.5 + 0.5))
	img.generate_mipmaps()
	nimg.generate_mipmaps()
	var out := [ImageTexture.create_from_image(img), ImageTexture.create_from_image(nimg)]
	_wound_tex[key] = out
	return out

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
