class_name SandboxZones
extends Node3D
## Содержимое зон «Полигона»: таблички, ряды растений, загоны с животными,
## столы со всеми предметами, стрельбище, все постройки, мосты, выживание,
## пирс над морем, риф, арена ботов. Точки быстрого перемещения — points.

const P := preload("res://scripts/sandbox/sandbox_props.gd")

## Зоны: id → {name, c: Vector2 (центр), r: радиус «чистой» области}.
const ZONES := {
	&"hub": {"name": "Центр", "c": Vector2(0, 0), "r": 18.0},
	&"flora": {"name": "Растения и ресурсы", "c": Vector2(-62, -64), "r": 40.0},
	&"fauna": {"name": "Животные", "c": Vector2(59, -62), "r": 34.0},
	&"items": {"name": "Предметы", "c": Vector2(0, 24), "r": 22.0},
	&"range": {"name": "Стрельбище", "c": Vector2(0, 66), "r": 30.0},
	&"build": {"name": "Стройка", "c": Vector2(-80, 4), "r": 34.0},
	&"survival": {"name": "Выживание", "c": Vector2(-60, 74), "r": 26.0},
	&"bots": {"name": "Арена ботов", "c": Vector2(68, 62), "r": 26.0},
	&"pack": {"name": "Пак моделей", "c": Vector2(40, 8), "r": 18.0},
}

const FLORA_NAMES := {
	&"palm": "Кокосовая пальма", &"broadleaf": "Лиственное дерево", &"banyan": "Баньян", &"mangrove": "Мангровое дерево",
	&"liana": "Лиана — волокно", &"bush": "Куст", &"herb": "Лечебная трава", &"wild_taro": "Дикое таро",
	&"wild_maize": "Дикая кукуруза", &"wild_melon": "Дикая дыня", &"berries": "Ягодный куст", &"cotton": "Хлопок",
	&"stick": "Палка", &"stone": "Камень", &"boulder": "Валун", &"iron_ore": "Железная руда", &"sulfur": "Сера",
}
const SPECIES_ORDER: Array[StringName] = [&"boar", &"croc", &"monkey", &"monitor", &"snake", &"iguana", &"crab",
	&"scorpion", &"spider", &"turtle"]
const BIRDS: Array[StringName] = [&"parrot", &"gull", &"bat"]

var world: World
var player: Node3D
## id → {pos: Vector3 (где встать), look: Vector3 (куда смотреть), name}
var points: Dictionary = {}
## Порядок точек для меню.
var order: Array[StringName] = []
var _roots: Dictionary = {}       # id → Node3D (статичные постройки зоны)
var _ext: Dictionary = {}         # id → Array[Node] (животные, чертежи, станции, предметы)
var _dummies: Array = []          # [{dummy, label, n}]
var _bridge_info: Dictionary = {}
var _pens: Array = []             # [{a: Animal, c: Vector3, r: float}] — загоны держат животных
const FLORA_AREA := Rect2(-100.0, -95.0, 75.0, 50.0)

func _ready() -> void:
	process_physics_priority = 50   # после Fauna: поправляем позицию за оградой

# ------------------------------------------------------------ раскладка флоры (до populate)

## Записи для SandboxFlora.showcase и зоны без рассадки — вызывать до создания флоры.
static func flora_layout() -> Array:
	var out: Array = []
	var x := -94.0
	for i in 5:
		out.append({"kind": &"palm", "pos": Vector2(x, -86.0), "idx": i})
		x += 8.0
	for i in 3:
		out.append({"kind": &"mangrove", "pos": Vector2(x + 2.0, -86.0), "idx": i})
		x += 8.0
	x = -94.0
	for i in 4:
		out.append({"kind": &"broadleaf", "pos": Vector2(x, -71.0), "idx": i})
		x += 9.0
	out.append({"kind": &"liana", "pos": Vector2(x - 9.0, -71.0)})
	for i in 2:
		out.append({"kind": &"banyan", "pos": Vector2(x + 6.0, -71.0), "idx": i})
		x += 15.0
	var res: Array[StringName] = [&"bush", &"herb", &"wild_taro", &"wild_maize", &"wild_melon", &"berries", &"cotton",
		&"stick", &"stone", &"boulder", &"iron_ore", &"sulfur"]
	for i in res.size():
		out.append({"kind": res[i], "pos": Vector2(-92.0 + i * 5.0, -55.0)})
	return out

static func clear_zones() -> Array:
	var out: Array = []
	for id: StringName in ZONES:
		var z: Dictionary = ZONES[id]
		out.append([Vector3(z.c.x, 0.0, z.c.y), float(z.r)])
	return out

# ------------------------------------------------------------ сборка

func setup(w: World) -> void:
	world = w

func build_all() -> void:
	for id: StringName in [&"hub", &"flora", &"fauna", &"items", &"range", &"build", &"bridge", &"survival", &"beach",
			&"sea", &"reef", &"bots", &"pack"]:
		build_zone(id)
		await get_tree().process_frame
	_add_island_points()

func build_zone(id: StringName) -> void:
	var root := Node3D.new()
	root.name = "Zone_" + String(id)
	add_child(root)
	_roots[id] = root
	_ext[id] = []
	match id:
		&"hub": _hub(root)
		&"flora": _flora(root)
		&"fauna": _fauna(root)
		&"items": _items(root)
		&"range": _range(root)
		&"build": _build(root)
		&"bridge": _bridge(root)
		&"survival": _survival(root)
		&"beach": _beach(root)
		&"sea": _sea(root)
		&"reef": _reef(root)
		&"bots": _bots(root)
		&"pack":
			SandboxPack.build(self, root, ZONES[&"pack"].c)
			SandboxPack.build_sea(self, root)

## Вернуть зону к начальному виду (деревья в зоне растений не восстанавливаются).
func reset_zone(id: StringName) -> void:
	if _roots.has(id) and is_instance_valid(_roots[id]):
		(_roots[id] as Node).queue_free()
	for n in _ext.get(id, []):
		if is_instance_valid(n):
			(n as Node).queue_free()
	_dummies = _dummies.filter(func(d: Dictionary) -> bool: return is_instance_valid(d.dummy) and not (d.dummy as Node).is_queued_for_deletion())
	if id == &"flora":
		var fl := Flora.instance()
		if fl is SandboxFlora:
			(fl as SandboxFlora).reset_showcase(FLORA_AREA)
	await get_tree().process_frame
	await get_tree().process_frame
	build_zone(id)

func _point(id: StringName, name_: String, pos: Vector3, look: Vector3) -> void:
	if not points.has(id):
		order.append(id)
	points[id] = {"pos": pos, "look": look, "name": name_}

func _stand(id: StringName, name_: String, x: float, z: float, lx: float, lz: float, ly: float = 1.0) -> void:
	_point(id, name_, Vector3(x, P.ground(x, z) + 0.2, z), Vector3(lx, P.ground(lx, lz) + ly, lz))

func _own(id: StringName, n: Node) -> void:
	if n:
		(_ext[id] as Array).append(n)

func _bm() -> BuildModule:
	return BuildModule.instance()

## Достроить чертёж целиком.
static func complete(bp: Blueprint) -> void:
	if bp == null:
		return
	var need := bp.needs_left()
	for t: StringName in need:
		bp.add_material(t, int(need[t]))

func _place(id: StringName, def_id: StringName, x: float, z: float, yaw: float = 0.0, finish: bool = true) -> Blueprint:
	var bm := _bm()
	if bm == null:
		return null
	var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(x, P.ground(x, z), z))
	var bp := bm.place_blueprint(def_id, xf, 0)
	if bp and finish:
		complete(bp)
	_own(id, bp)
	return bp

func _place_xf(id: StringName, def_id: StringName, xf: Transform3D, anchor: Dictionary = {}, ctx: Dictionary = {}) -> Blueprint:
	var bm := _bm()
	if bm == null:
		return null
	var bp := bm.place_blueprint(def_id, xf, 0, anchor, ctx)
	complete(bp)
	_own(id, bp)
	return bp

# ------------------------------------------------------------ центр

func _hub(root: Node3D) -> void:
	P.signpost(root, 0.0, 0.0, "ПОЛИГОН", "F1 или M — меню и быстрое перемещение\nV — полёт · Shift — быстрее · колесо — скорость")
	var dirs := {&"flora": "Растения", &"fauna": "Животные", &"items": "Предметы и оружие", &"build": "Стройка",
		&"survival": "Выживание", &"bots": "Арена ботов", &"pack": "Пак моделей"}
	for id: StringName in dirs:
		var c: Vector2 = ZONES[id].c
		var d := c.normalized()
		var p := d * 7.0
		P.tag(root, p.x, p.y, "%s  →  %d м" % [dirs[id], int(c.length())], 1.3, 40.0)
	_stand(&"hub", "Центр", 0.0, -7.0, 0.0, 0.0, 2.6)

# ------------------------------------------------------------ растения

func _flora(root: Node3D) -> void:
	P.signpost(root, -71.0, -44.0, "РАСТЕНИЯ И РЕСУРСЫ", "Рубите, собирайте, копайте — мир не восстанавливается")
	for e: Dictionary in flora_layout():
		var q: Vector2 = e.pos
		var nm: String = FLORA_NAMES.get(e.kind, String(e.kind))
		if e.has("idx") and e.kind in [&"palm", &"broadleaf", &"banyan", &"mangrove"]:
			nm += " · вид %d" % (int(e.idx) + 1)
		if e.kind == &"liana":
			continue
		var tree: bool = e.kind in [&"palm", &"broadleaf", &"banyan", &"mangrove"]
		P.tag(root, q.x, q.y + (3.0 if tree else 1.6), nm, 1.0 if tree else 1.0, 30.0)
	P.tag(root, -71.0, -67.0, "Лиана на дереве — волокно", 1.0, 30.0)
	_stand(&"flora", "Растения и ресурсы", -62.0, -40.0, -62.0, -66.0, 2.0)

# ------------------------------------------------------------ животные

func _fauna(root: Node3D) -> void:
	P.signpost(root, 47.0, -37.0, "ЖИВОТНЫЕ", "Все виды в загонах · еду можно дать с руки (E)")
	var fa := Fauna.instance()
	var slots: Array[Vector2] = []
	for row in 3:
		for col in 4:
			slots.append(Vector2(45.0 + col * 9.5, -76.0 + row * 10.0))
	for i in SPECIES_ORDER.size():
		var sp := SPECIES_ORDER[i]
		var s := slots[i]
		var small := sp in [&"crab", &"scorpion", &"spider", &"snake", &"iguana"]
		var r := 2.6 if small else 3.6
		P.pen(root, s.x, s.y, r)
		var nm := sp as String
		if fa:
			var a := _penned(fa, sp, s, r)
			if a:
				nm = String(a.cfg.get("name", sp))
		P.tag(root, s.x, s.y + r + 0.4, nm, 1.5, 30.0)
	# птицы — стайками над зоной
	if fa:
		for i in BIRDS.size():
			var s := slots[SPECIES_ORDER.size() + i] if SPECIES_ORDER.size() + i < slots.size() else Vector2(80, -50)
			for a in fa.spawn_flock(BIRDS[i], Vector3(s.x, 0.0, s.y), 3 if BIRDS[i] != &"bat" else 4, 7.0):
				_own(&"fauna", a)
			P.tag(root, s.x, s.y, ["Попугаи", "Чайки", "Летучие мыши (ночью)"][i], 1.2, 40.0)
	# стол с кормом для приручения
	var t := P.table(root, 71.0, -42.0, 3.0)
	var foods: Array[StringName] = []
	for id: StringName in [&"banana", &"mango", &"papaya", &"coconut", &"berries", &"seed_taro", &"taro", &"meat_raw", &"fish_raw"]:
		if Items.get_item(id):
			foods.append(id)
	_lay(&"fauna", root, t, foods, 3)
	P.tag(root, 71.0, -42.0, "Корм для приручения", 1.5, 30.0)
	# загон приручения: дикий кабан, корм на столе рядом
	P.pen(root, 62.0, -43.0, 3.6)
	if fa:
		_penned(fa, &"boar", Vector2(62.0, -43.0), 3.6)
	P.tag(root, 62.0, -39.0, "Приручение: дайте кабану корм с руки (E)\nили меню F1 → «Приручить у прицела»", 1.5, 30.0)
	_stand(&"fauna", "Животные", 60.0, -36.0, 60.0, -62.0, 0.5)

## Животное в загоне: держится внутри ограды, пока не приручено.
func _penned(fa: Fauna, sp: StringName, s: Vector2, r: float) -> Animal:
	var a := fa.spawn(sp, Vector3(s.x, P.ground(s.x, s.y) + 0.3, s.y), r * 0.45)
	if a:
		_own(&"fauna", a)
		_pens.append({"a": a, "c": Vector3(s.x, 0.0, s.y), "r": maxf(0.6, r - 0.5)})
	return a

func _physics_process(_delta: float) -> void:
	for e: Dictionary in _pens:
		var a: Variant = e.a
		if not is_instance_valid(a):
			continue
		var an := a as Animal
		if an.tamed or an.is_queued_for_deletion():
			continue
		var c: Vector3 = e.c
		var off := Vector2(an.global_position.x - c.x, an.global_position.z - c.z)
		var lim: float = e.r
		if off.length() > lim:
			off = off.normalized() * lim
			var p := an.global_position
			p.x = c.x + off.x
			p.z = c.z + off.y
			an.global_position = p
	_pens = _pens.filter(func(e: Dictionary) -> bool: return is_instance_valid(e.a))

# ------------------------------------------------------------ предметы

## Разложить предметы на столе (по count штук; стопкой по n).
func _lay(zone: StringName, _root: Node3D, table: StaticBody3D, ids: Array, n: int = 1) -> void:
	var length := 0.0
	for c in table.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh is BoxMesh:
			length = maxf(length, ((c as MeshInstance3D).mesh as BoxMesh).size.x)
	var step := minf(0.5, (length - 0.4) / maxf(1.0, ids.size() - 1.0))
	for i in ids.size():
		var id: StringName = ids[i]
		var lx := -step * (ids.size() - 1) * 0.5 + step * i
		var w := table.global_transform * Vector3(lx, 0.98, (0.18 if i % 2 == 0 else -0.18))
		var cnt := mini(n, Inventory.stack_of(id))
		var pk := ItemPickup.spawn(self, w, [{"id": id, "n": cnt}])
		if pk:
			pk.freeze = true
			pk.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			_own(zone, pk)
			var l := P.label(pk, w + Vector3(0, 0.3, 0), Items.item_name(id), 30, P.SIGN_COLOR, 10.0)
			l.pixel_size = 0.0032

static func all_items() -> Array[StringName]:
	var arr: Array[StringName] = []
	for id: StringName in Items.items:
		var d := Items.get_item(id)
		if d == null or d.weight >= Inventory.HEAVY_WEIGHT or id == &"flag":
			continue
		arr.append(id)
	arr.sort_custom(func(a: StringName, b: StringName) -> bool:
		var ka := String(Items.get_item(a).kind)
		var kb := String(Items.get_item(b).kind)
		if ka != kb:
			return ka < kb
		return Items.item_name(a) < Items.item_name(b))
	return arr

const KIND_NAMES := {&"resource": "Ресурсы", &"tool": "Инструменты", &"weapon": "Оружие", &"food": "Еда",
	&"build": "Стройка", &"misc": "Разное", &"ammo": "Боеприпасы", &"medicine": "Лечение"}

func _items(root: Node3D) -> void:
	P.signpost(root, -9.0, 11.0, "ПРЕДМЕТЫ", "Все предметы игры — подходите и берите (E)")
	var ids := all_items().filter(func(id: StringName) -> bool: return Items.get_item(id).kind != &"weapon")
	var per := 8
	var tables := ceili(ids.size() / float(per))
	var cols := 5
	for ti in tables:
		var col := ti % cols
		var row := ti / cols
		var x := -24.0 + col * 12.0
		var z := 16.0 + row * 5.0
		var t := P.table(root, x, z, 4.0)
		var part := ids.slice(ti * per, mini(ids.size(), (ti + 1) * per))
		_lay(&"items", root, t, part, 1)
	_stand(&"items", "Предметы", 0.0, 9.0, 0.0, 22.0, 0.5)

func _range(root: Node3D) -> void:
	P.signpost(root, -15.0, 42.0, "СТРЕЛЬБИЩЕ", "Мишени на 10, 25 и 50 м · урон над чучелом")
	# стойка с оружием и боеприпасами
	var weapons := all_items().filter(func(id: StringName) -> bool:
		var d := Items.get_item(id)
		return d.kind == &"weapon" or d.kind == &"ammo" or String(id).contains("arrow") or String(id).contains("bolt") \
			or String(id).contains("bullet") or String(id).contains("powder") or String(id).contains("shot"))
	var half := ceili(weapons.size() / 2.0)
	var t1 := P.table(root, -5.0, 38.0, 4.5)
	_lay(&"range", root, t1, weapons.slice(0, half), 20)
	var t2 := P.table(root, 5.0, 38.0, 4.5)
	_lay(&"range", root, t2, weapons.slice(half), 20)
	P.tag(root, 0.0, 37.0, "Оружие и боеприпасы", 1.6, 30.0)
	# линия стрельбы
	for i in 9:
		var x := -12.0 + i * 3.0
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(2.6, 0.06, 0.12)
		mi.mesh = bm
		mi.material_override = HeldModels.pbr("rough_wood", Vector3.ONE, Color(0.9, 0.85, 0.7))
		root.add_child(mi)
		mi.global_position = Vector3(x, P.ground(x, 41.0) + 0.03, 41.0)
	for e in [[-8.0, 10.0], [0.0, 25.0], [8.0, 50.0]]:
		var x: float = e[0]
		var z: float = 41.0 + float(e[1])
		_dummy(&"range", root, x, z, "%d м" % int(e[1]))
	_dummy(&"range", root, -20.0, 36.0, "Ближний бой")
	_stand(&"range", "Стрельбище", 0.0, 40.0, 0.0, 70.0, 1.2)

func _dummy(zone: StringName, root: Node3D, x: float, z: float, title: String) -> void:
	var d := TrainingDummy.new()
	root.add_child(d)
	d.global_position = Vector3(x, P.ground(x, z), z)
	d.rotation.y = PI
	P.tag(root, x, z, title, 2.55, 80.0)
	var l := P.label(root, Vector3(x, P.ground(x, z) + 2.15, z), "", 44, Color(1.0, 0.6, 0.4), 80.0)
	_dummies.append({"dummy": d, "label": l, "n": 0})

func _process(_delta: float) -> void:
	for e: Dictionary in _dummies:
		var d := e.dummy as TrainingDummy
		if not is_instance_valid(d):
			continue
		if d.hits.size() != int(e.n):
			var last: Dictionary = d.hits[d.hits.size() - 1]
			e.n = d.hits.size()
			(e.label as Label3D).text = "−%d  (всего %d)" % [int(round(float(last.amount))), int(round(d.total))]
			_float_number(d.global_position + Vector3(randf_range(-0.3, 0.3), 1.9, 0), float(last.amount))

func _float_number(pos: Vector3, amount: float) -> void:
	var l := P.label(self, pos, "%d" % int(round(amount)), 64, Color(1.0, 0.85, 0.3))
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, ^"position:y", pos.y + 1.2, 1.1)
	tw.tween_property(l, ^"modulate:a", 0.0, 1.1).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)

# ------------------------------------------------------------ стройка

func _build(root: Node3D) -> void:
	P.signpost(root, -56.0, -5.0, "СТРОЙКА", "Все постройки: готовые и чертежи · B — меню стройки")
	var bm := _bm()
	if bm == null:
		return
	# флаг команды и территория
	var fz := Vector2(-74.0, 26.0)
	var flag := bm.place_flag(0, Vector3(fz.x, P.ground(fz.x, fz.y), fz.y), 0.0)
	_own(&"build", flag)
	P.tag(root, fz.x, fz.y, "Флаг команды — возрождение\nтерритория 40 м (видна в режиме стройки)", 3.6)
	# дом: стены, окно, проём, дверь, крыша
	var base := Transform3D(Basis(), Vector3(-96.0, P.ground(-96.0, -14.0), -14.0))
	var w1 := _place_xf(&"build", &"wall", base)
	_place_xf(&"build", &"wall_window", base * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(1.5, 0, -1.5)))
	var w3 := _place_xf(&"build", &"wall_door", base * Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -3.0)))
	_place_xf(&"build", &"wall", base * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-1.5, 0, -1.5)))
	if w1:
		var rs := bm.find_socket(&"roof", base.origin + Vector3.UP * BuildDefs.WALL_H + Vector3(0, 0, -1.5), 3.0)
		if not rs.is_empty():
			_place_xf(&"build", &"roof", rs.xform)
	if w3:
		var ds := bm.find_socket(&"door", w3.global_position, 3.0)
		if not ds.is_empty():
			_place_xf(&"build", &"door", ds.xform)
	P.tag(root, -96.0, -10.5, "Дом: стены, окно, дверь, крыша", 3.2)
	# платформа на сваях + лестница + стена с окном
	var plat := _place(&"build", &"platform", -84.0, -16.0)
	if plat:
		var s := bm.find_socket(&"wall", plat.base_xform * Vector3(0, BuildDefs.DECK_H, -1.5), 1.0)
		if not s.is_empty():
			_place_xf(&"build", &"wall_window", s.xform)
		var st := bm.find_socket(&"stairs", plat.base_xform * Vector3(0, 0, 3.0), 3.0)
		if not st.is_empty():
			_place_xf(&"build", &"stairs", st.xform, {}, st.ctx)
	P.tag(root, -84.0, -11.0, "Платформа, лестница", 3.0)
	_place(&"build", &"shelter", -72.0, -16.0, 0.4)
	P.tag(root, -72.0, -13.0, "Шалаш", 2.4)
	_place(&"build", &"fire_pit", -65.0, -14.0)
	P.tag(root, -65.0, -14.0, "Каменный очаг", 1.3)
	# оборона: частокол с воротами, колья, вышка, фундамент
	for i in 4:
		var x := -98.0 + i * 3.0
		var xf := Transform3D(Basis(), Vector3(x, P.ground(x, 4.0), 4.0))
		_place_xf(&"build", &"gate" if i == 2 else &"palisade", xf)
	P.tag(root, -93.5, 5.5, "Частокол и ворота", 3.4)
	_place(&"build", &"spikes", -84.0, 6.0)
	P.tag(root, -84.0, 6.0, "Колья — ловушка", 1.6)
	var tower := _place(&"build", &"watchtower", -74.0, 6.0)
	if tower:
		var ts := bm.find_socket(&"stairs", tower.base_xform * Vector3(0, 0, 3.0), 5.0)
		if not ts.is_empty():
			_place_xf(&"build", &"stairs", ts.xform, {}, ts.ctx)
	P.tag(root, -74.0, 2.5, "Сторожевая вышка", 5.6)
	_place(&"build", &"foundation", -64.0, 5.0)
	P.tag(root, -64.0, 5.0, "Каменный фундамент — не горит", 1.6)
	# хранение и верстак
	var chest := _place(&"build", &"chest", -98.0, 16.0)
	if chest is BuildChest:
		for e in [[&"stick", 20], [&"stone", 20], [&"rope", 10], [&"coconut", 5]]:
			if Items.get_item(e[0]):
				(chest as BuildChest).storage.add(e[0], e[1])
	P.tag(root, -98.0, 16.0, "Сундук (с вещами)", 1.4)
	var lh := _place(&"build", &"log_holder", -92.0, 16.0)
	if lh is BuildLogHolder:
		(lh as BuildLogHolder).add_logs(BuildLogHolder.MAX_LOGS)
	P.tag(root, -92.0, 16.0, "Поленница: 10 брёвен", 1.9)
	_place(&"build", &"workbench", -86.0, 16.0)
	P.tag(root, -86.0, 16.0, "Верстак", 1.7)
	# чертежи: недостроенные
	var half := _place(&"build", &"wall", -78.0, 16.0, 0.0, false)
	if half:
		half.add_material(&"log", 3)
	P.tag(root, -78.0, 16.0, "Чертёж стены — наполовину", 3.0)
	_place(&"build", &"palisade", -71.0, 16.0, 0.0, false)
	P.tag(root, -71.0, 16.0, "Чертёж частокола — пустой", 3.0)
	# взрывать и жечь
	_place(&"build", &"wall", -92.0, 30.0)
	_place(&"build", &"palisade", -86.0, 30.0)
	P.tag(root, -89.0, 30.0, "Взорвите динамитом или подожгите", 3.0)
	var t := P.table(root, -89.0, 25.0, 3.0)
	var boom: Array[StringName] = []
	for id: StringName in [&"dynamite", &"molotov"]:
		if Items.get_item(id):
			boom.append(id)
	_lay(&"build", root, t, boom, 5)
	_stand(&"build", "Стройка", -52.0, 4.0, -80.0, 4.0, 2.0)

# ------------------------------------------------------------ мосты

func _bridge(root: Node3D) -> void:
	var bm := _bm()
	if bm == null or world == null:
		return
	var isl := world.islands()
	var a: Dictionary = isl[0]
	var b: Dictionary = isl[1]
	var tg := bm.find_bridge_target(a, b)
	if not bool(tg.get("ok", false)):
		push_warning("[sandbox] не нашёл место для моста")
		return
	_bridge_info = tg
	var n := int(tg.sections)
	_chain(&"bridge", tg.xform as Transform3D, n, int(n / 2.0))
	var dir: Vector3 = tg.dir
	var start: Vector3 = tg.start
	var side := Vector3(-dir.z, 0, dir.x)
	# короткий мост для поджога — в стороне
	var ca: Vector2 = a.center
	var cb: Vector2 = b.center
	var off := Vector2(side.x, side.z) * 24.0
	var stub: Dictionary = bm.call(&"_bridge_line", ca + off, cb + off, Vector2(dir.x, dir.z))
	if bool(stub.get("ok", false)):
		_chain(&"bridge", stub.xform as Transform3D, 3, -1)
		var sx: Vector3 = (stub.xform as Transform3D).origin - dir * 4.0
		var t := P.table(root, sx.x - side.x * 2.5, sx.z - side.z * 2.5, 2.5, atan2(dir.x, dir.z) + PI * 0.5)
		var boom: Array[StringName] = []
		for id: StringName in [&"molotov", &"dynamite"]:
			if Items.get_item(id):
				boom.append(id)
		_lay(&"bridge", root, t, boom, 5)
		P.tag(root, sx.x, sx.z, "Подожгите мост коктейлем Молотова", 2.0)
	var sp := start - dir * 6.0 - side * 4.0
	P.signpost(root, sp.x, sp.z, "МОСТЫ", "Связки брёвен на воде · секция с воротами · огонь")
	var gp: Vector3 = (tg.xform as Transform3D).origin + dir * BuildDefs.RAFT_L * int(n / 2.0)
	P.label(root, gp + Vector3(0, 2.6, 0), "Секция с воротами", 34, P.SIGN_COLOR, 40.0)
	var stand := start - dir * 5.0
	_point(&"bridge", "Мосты", Vector3(stand.x, P.ground(stand.x, stand.z) + 0.2, stand.z), start + dir * 20.0 + Vector3.UP)

## Цепочка секций моста от первой (у берега). gate_at — индекс секции с воротами (−1 — нет).
func _chain(zone: StringName, first: Transform3D, n: int, gate_at: int) -> void:
	var bm := _bm()
	var prev := _place_xf(zone, &"raft_gate" if gate_at == 0 else &"raft", first, {"type": &"shore"})
	for i in range(1, n):
		if prev == null:
			return
		var sock := bm.raft_socket(prev.base_now() * Vector3(0, 0, -BuildDefs.RAFT_L), 1.5)
		if sock.is_empty():
			return
		prev = _place_xf(zone, &"raft_gate" if i == gate_at else &"raft", sock.xform,
				{"type": &"raft", "parent": sock.parent, "offset": sock.offset})

# ------------------------------------------------------------ выживание

func _survival(root: Node3D) -> void:
	P.signpost(root, -38.0, 65.0, "ВЫЖИВАНИЕ", "Вода, костёр, копчение, огород, травы")
	var sv := Survival.instance()
	if sv == null:
		return
	var put := func(kit: StringName, x: float, z: float, title: String, h: float = 1.6) -> Node3D:
		var n := sv.place_structure(null, kit, Vector3(x, P.ground(x, z), z), 0.3)
		_own(&"survival", n)
		P.tag(root, x, z, title, h)
		return n
	var fire := put.call(&"campfire", -70.0, 64.0, "Костёр с котелком", 1.6) as SvFire
	if fire:
		fire.light()
		fire.fuel = SvFire.FUEL_MAX
		for id: StringName in Items.items:
			if Survival.data(id).has("boil"):
				var arr: Array[StringName] = [id, id]
				fire.pot = {"items": arr, "t": 0.0}
				fire.set(&"_dirty", true)
				break
	var sm := put.call(&"smoker", -76.0, 66.0, "Коптильня", 2.2) as SvSmoker
	if sm:
		sm.fuel = SvSmoker.FUEL_MAX * 0.5
	put.call(&"still", -80.0, 72.0, "Опреснитель", 1.6)
	put.call(&"rain_barrel", -82.0, 78.0, "Дождевая бочка", 1.8)
	put.call(&"tarp", -78.0, 84.0, "Тент для сбора дождя", 2.4)
	P.tag(root, -62.0, 86.0, "Пресный пруд — можно пить", 1.2)
	# огород: все стадии роста
	var crops: Array[StringName] = [&"taro", &"maize", &"melon", &"berry"]
	var stages := [0.05, 0.4, 0.75, 1.0]
	for i in 4:
		var x := -52.0 + i * 3.5
		var g := put.call(&"garden", x, 66.0, ["Посажено", "Росток", "Растёт", "Созрело"][i], 1.5) as SvGarden
		if g:
			g.crop = crops[i]
			g.growth = stages[i]
			g.moisture = 1.0
			g.call(&"_refresh")
	P.tag(root, -46.75, 68.5, "Огород — единственная возобновляемая еда", 2.1)
	# дикие травы и растения
	for i in 3:
		var kind: StringName = [&"herb", &"berry", &"taro"][i]
		var x := -52.0 + i * 4.0
		var w := SvWild.new()
		w.kind = kind
		sv.structures.add_child(w)
		w.global_position = Vector3(x, P.ground(x, 76.0) - 0.03, 76.0)
		_own(&"survival", w)
		P.tag(root, x, 76.0, ["Лечебная трава (яд)", "Дикие ягоды", "Дикое таро"][i], 1.2)
	_stand(&"survival", "Выживание", -44.0, 58.0, -62.0, 74.0, 0.5)

func _beach(root: Node3D) -> void:
	var sv := Survival.instance()
	if sv == null or world == null:
		return
	var I: Dictionary = world.arch.islands[0]
	var a0 := Vector2(-60.0, 80.0).angle()
	var kinds: Array[StringName] = [&"barrel", &"crate", &"bottles", &"net", &"scrap", &"crate"]
	var names := {&"barrel": "Бочка", &"crate": "Ящик", &"bottles": "Бутылки", &"net": "Сеть", &"scrap": "Металлолом"}
	var mid := Vector2.ZERO
	for i in kinds.size():
		var a := a0 + (i - 2.5) * 0.035
		var q := _dry_beach(I, a)
		var d := SvDebris.new()
		d.kind = kinds[i]
		d.seed_v = 100 + i
		sv.structures.add_child(d)
		d.global_position = Vector3(q.x, P.ground(q.x, q.y) - 0.05, q.y)
		d.rotation.y = a
		_own(&"beach", d)
		P.tag(root, q.x, q.y, names.get(kinds[i], ""), 1.4, 25.0)
		mid += q
	mid /= kinds.size()
	var inland := mid - Vector2.from_angle(a0) * 9.0 + Vector2.from_angle(a0 + PI * 0.5) * 6.0
	P.signpost(root, inland.x, inland.y, "МУСОРНЫЙ ПЛЯЖ", "Обломки после штормов: ящики, бочки, сети, металл")
	var stand := mid - Vector2.from_angle(a0) * 8.0
	_point(&"beach", "Мусорный пляж", Vector3(stand.x, P.ground(stand.x, stand.y) + 0.2, stand.y), Vector3(mid.x, P.ground(mid.x, mid.y) + 0.5, mid.y))

## Сухой песок у берега под углом a (ищем от воды вглубь).
func _dry_beach(I: Dictionary, a: float) -> Vector2:
	var c: Vector2 = I.center
	var R := world.arch._coast_r(I, a)
	var d := 1.02
	while d > 0.7:
		var q := c + Vector2.from_angle(a) * R * d
		var h := P.ground(q.x, q.y)
		if h > world.tide_amplitude + 0.25:
			return q
		d -= 0.01
	return c + Vector2.from_angle(a) * R * 0.9

# ------------------------------------------------------------ море и риф

func _sea(root: Node3D) -> void:
	if world == null:
		return
	var I: Dictionary = world.arch.islands[0]
	var a := -PI * 0.5 + 0.25
	var shore := _dry_beach(I, a)
	var dir := Vector3(cos(a), 0, sin(a))
	var start := Vector3(shore.x, 0.0, shore.y) - dir * 3.0
	var deck := 1.35
	var length := 30.0
	while length < 90.0:
		var e := start + dir * length
		if P.ground(e.x, e.z) < -7.0:
			break
		length += 2.0
	P.pier(root, start, dir, length, deck)
	P.signpost(root, start.x - dir.z * 3.0, start.z + dir.x * 3.0, "МОРЕ", "Пирс над глубиной · акулы, рыбы, скаты, медузы")
	var end := start + dir * (length - 1.0)
	P.label(root, Vector3(end.x, deck + 1.6, end.z), "Глубина ≈ %d м · не плавайте с кровью!" % int(maxf(0.0, -P.ground(end.x, end.z))),
			30, P.SIGN_COLOR, 40.0)
	var sea := get_tree().get_first_node_in_group(&"sea") as Sea
	if sea:
		var c2 := Vector2(end.x, end.z) + Vector2(dir.x, dir.z) * 14.0
		_own(&"sea", sea.spawn_shark(&"reef", c2, 10.0, 901))
		_own(&"sea", sea.spawn_shark(&"tiger", c2 + Vector2(dir.x, dir.z) * 12.0, 20.0, 902))
		sea.call(&"_spawn_school", Vector3(end.x, 0.0, end.z) + dir * 6.0, 3)
	_point(&"sea", "Море (пирс)", Vector3(end.x, deck + 0.15, end.z) - dir * 2.0, Vector3(end.x, -1.0, end.z) + dir * 14.0)

func _reef(root: Node3D) -> void:
	if world == null:
		return
	var isl := world.arch.islands
	var at: Dictionary = isl[4]
	var c: Vector2 = at.center
	# пляж атолла, обращённый к полигону
	var a := (Vector2.ZERO - c).angle()
	var q := c + Vector2.from_angle(a) * world.arch._coast_r(at, a) * 0.78
	var g := P.ground(q.x, q.y)
	var qs := q + Vector2.from_angle(a + PI * 0.5) * 4.0
	P.signpost(root, qs.x, qs.y, "РИФ", "Атолл с кораллами · ныряйте (Ctrl), следите за воздухом")
	var out := Vector2.from_angle(a)
	var look := q + out * 30.0
	_point(&"reef", "Коралловый риф", Vector3(q.x, g + 0.2, q.y) - Vector3(out.x, 0, out.y) * 3.0, Vector3(look.x, -1.5, look.y))
	# под водой у рифа
	var sea := get_tree().get_first_node_in_group(&"sea") as Sea
	if sea:
		var best := Vector2.INF
		var bd := INF
		for z: Dictionary in sea.reef_zones():
			var zc: Vector2 = z.center
			var d := zc.distance_to(c)
			if d < bd:
				bd = d
				best = zc
		if best.x < INF:
			_point(&"reef_dive", "Риф — под водой", Vector3(best.x, -1.6, best.y), Vector3(best.x + 6.0, -4.0, best.y))

# ------------------------------------------------------------ боты

func _bots(root: Node3D) -> void:
	var c: Vector2 = ZONES[&"bots"].c
	P.ring_marks(root, c.x, c.y, 16.0)
	P.signpost(root, c.x - 22.0, c.y - 9.0, "АРЕНА БОТОВ", "Меню полигона (F1): создать бота любой команды и сложности")
	_stand(&"bots", "Арена ботов", c.x - 18.0, c.y - 18.0, c.x, c.y, 1.0)

func arena_center() -> Vector3:
	var c: Vector2 = ZONES[&"bots"].c
	return Vector3(c.x, P.ground(c.x, c.y) + 0.3, c.y)

func _add_island_points() -> void:
	if world == null:
		return
	var isl := world.islands()
	for i in range(1, mini(4, isl.size())):
		var I: Dictionary = isl[i]
		var t := int(I.team)
		var p := world.spawn_point(t)
		_point(StringName("island_%d" % t), "Остров: %s" % Game.TEAM_NAMES[t], p + Vector3.UP * 0.2, Vector3(0, 2, 0))
