class_name SandboxZones
extends Node3D
## Содержимое зон «Полигона»: таблички, ряды растений, загоны с животными,
## столы со всеми предметами, стрельбище, все постройки, мосты, выживание,
## пирс над морем, риф, арена ботов. Точки быстрого перемещения — points.

const P := preload("res://scripts/sandbox/sandbox_props.gd")

## Компактная раскладка: всё рядом с центром (HUB) — меньше ходьбы, быстрые точки остались.
const HUB := Vector2(10.0, -80.0)
## Зоны: id → {name, c: Vector2 (центр), r: радиус «чистой» области}.
const ZONES := {
	&"hub": {"name": "Центр", "c": Vector2(10, -80), "r": 10.0},
	&"flora": {"name": "Растения и ресурсы", "c": Vector2(-30, -110), "r": 24.0},
	&"fauna": {"name": "Животные", "c": Vector2(52, -66), "r": 24.0},
	&"items": {"name": "Предметы", "c": Vector2(-28, -76), "r": 17.0},
	&"range": {"name": "Стрельбище", "c": Vector2(10, -60), "r": 12.0},
	&"build": {"name": "Стройка", "c": Vector2(-30, -40), "r": 20.0},
	&"survival": {"name": "Выживание", "c": Vector2(46, -26), "r": 20.0},
	&"bots": {"name": "Арена ботов", "c": Vector2(-62, -60), "r": 15.0},
	&"pack": {"name": "Пак моделей", "c": Vector2(42, -112), "r": 18.0},
	&"style": {"name": "Полка стиля", "c": Vector2(9, -106), "r": 12.0},
}
## Стройка: исходная раскладка (центр (−81, 7)) ужата и перенесена к BUILD_C.
const BUILD_C := Vector2(-30.0, -40.0)
## Выживание: сдвиг исходной раскладки (пруд в SandboxArch тоже сдвинут).
const SURV_D := Vector2(110.0, -98.0)
## Пирс и мусорный пляж — на северном берегу, ближе к центру.
const PIER_ANGLE := -PI * 0.5 + 0.25
const BEACH_ANGLE := -PI * 0.5 - 0.25
## Через сколько секунд убитое животное/акула появляется снова.
const RESPAWN_S := 12.0

const FLORA_NAMES := {
	&"palm": "Кокосовая пальма", &"broadleaf": "Лиственное дерево", &"banyan": "Баньян", &"mangrove": "Мангровое дерево",
	&"liana": "Лиана — волокно", &"bush": "Куст", &"herb": "Лечебная трава", &"wild_taro": "Дикое таро",
	&"wild_maize": "Дикая кукуруза", &"wild_melon": "Дикая дыня", &"berries": "Ягодный куст", &"cotton": "Хлопок",
	&"stick": "Палка", &"stone": "Камень", &"boulder": "Валун", &"iron_ore": "Железная руда", &"sulfur": "Сера",
}
const SPECIES_ORDER: Array[StringName] = [&"boar", &"croc", &"monkey", &"monitor", &"snake", &"python", &"iguana", &"crab",
	&"hermit_crab", &"scorpion", &"spider", &"centipede", &"salamander", &"turtle"]
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
const FLORA_AREA := Rect2(-56.0, -126.0, 56.0, 30.0)

func _ready() -> void:
	process_physics_priority = 50   # после Fauna: поправляем позицию за оградой

# ------------------------------------------------------------ раскладка флоры (до populate)

## Записи для SandboxFlora.showcase и зоны без рассадки — вызывать до создания флоры.
static func flora_layout() -> Array:
	var out: Array = []
	var x := -51.0
	for i in 5:
		out.append({"kind": &"palm", "pos": Vector2(x, -120.0), "idx": i})
		x += 6.0
	for i in 3:
		out.append({"kind": &"mangrove", "pos": Vector2(x, -120.0), "idx": i})
		x += 6.0
	x = -51.0
	for i in 4:
		out.append({"kind": &"broadleaf", "pos": Vector2(x, -110.0), "idx": i})
		x += 7.0
	out.append({"kind": &"liana", "pos": Vector2(x - 7.0, -110.0)})
	for i in 2:
		out.append({"kind": &"banyan", "pos": Vector2(x + 4.0, -110.0), "idx": i})
		x += 12.0
	var res: Array[StringName] = [&"bush", &"herb", &"wild_taro", &"wild_maize", &"wild_melon", &"berries", &"cotton",
		&"stick", &"stone", &"boulder", &"iron_ore", &"sulfur"]
	for i in res.size():
		out.append({"kind": res[i], "pos": Vector2(-50.0 + i * 3.6, -100.0)})
	return out

static func clear_zones() -> Array:
	var out: Array = []
	for id: StringName in ZONES:
		var z: Dictionary = ZONES[id]
		out.append([Vector3(z.c.x, 0.0, z.c.y), float(z.r)])
	# дорожка стрельбища до 100 м (от центра вглубь острова, +z) — без деревьев
	for zz in [-45.0, -25.0, -5.0, 15.0, 35.0]:
		out.append([Vector3(10.0, 0.0, zz), 14.0])
	# пруд выживания, витрины пака кораллов и морской живности
	out.append([Vector3(48.0, 0.0, -12.0), 10.0])
	out.append([Vector3(50.0, 0.0, -88.0), 22.0])
	return out

# ------------------------------------------------------------ сборка

func setup(w: World) -> void:
	world = w

func build_all() -> void:
	for id: StringName in [&"hub", &"flora", &"fauna", &"items", &"range", &"build", &"bridge", &"survival", &"beach",
			&"sea", &"reef", &"bots", &"pack", &"style"]:
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
			SandboxLand2.build(self, root, ZONES[&"pack"].c)      # пак №3: рептилии и птицы с клипами автора
			SandboxSeaPack.build(self, root, ZONES[&"pack"].c)   # морская часть пака
			SandboxSeaPack.build_sea(self, root)
			SandboxSeaSkel.build(self, root, ZONES[&"pack"].c)    # море: модели со скелетом и клипами автора
			SandboxSeaSkel.build_sea(self, root)
			SandboxCorals.build(self, root, ZONES[&"pack"].c)      # кораллы по референсу пользователя
			SandboxCorals.build_sea(self, root)
		&"style": SandboxStyleShelf.build(self, root, ZONES[&"style"].c)   # полка стиля: все модели пака при одном свете

## Вернуть зону к начальному виду (деревья в зоне растений не восстанавливаются).
func reset_zone(id: StringName) -> void:
	if _roots.has(id) and is_instance_valid(_roots[id]):
		(_roots[id] as Node).queue_free()
	for n in _ext.get(id, []):
		if is_instance_valid(n):
			(n as Node).queue_free()
	_dummies = _dummies.filter(func(d: Dictionary) -> bool: return is_instance_valid(d.dummy) and not (d.dummy as Node).is_queued_for_deletion())
	_table_items = _table_items.filter(func(e: Dictionary) -> bool: return e.zone != id)
	_respawns = _respawns.filter(func(e: Dictionary) -> bool: return not (id == &"fauna" and e.kind != &"shark"))
	if id == &"fauna":
		_pens.clear()
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
	P.signpost(root, HUB.x, HUB.y, "ПОЛИГОН", "F1 или M — меню · F5 — погода · F6 — время суток\nV — полёт · Shift — быстрее · колесо — скорость")
	var dirs := {&"flora": "Растения", &"fauna": "Животные", &"items": "Предметы", &"range": "Стрельбище",
		&"build": "Стройка", &"survival": "Выживание", &"bots": "Арена ботов", &"pack": "Пак моделей"}
	for id: StringName in dirs:
		var c: Vector2 = ZONES[id].c
		var d := (c - HUB).normalized()
		var p := HUB + d * 6.0
		P.tag(root, p.x, p.y, "%s  →  %d м" % [dirs[id], int((c - HUB).length())], 1.3, 40.0)
	_stand(&"hub", "Центр", HUB.x, HUB.y - 6.0, HUB.x, HUB.y + 10.0, 1.6)

# ------------------------------------------------------------ растения

func _flora(root: Node3D) -> void:
	P.signpost(root, -12.0, -98.0, "РАСТЕНИЯ И РЕСУРСЫ", "Рубите, собирайте, копайте — мир не восстанавливается")
	for e: Dictionary in flora_layout():
		var q: Vector2 = e.pos
		var nm: String = FLORA_NAMES.get(e.kind, String(e.kind))
		if e.has("idx") and e.kind in [&"palm", &"broadleaf", &"banyan", &"mangrove"]:
			nm += " · вид %d" % (int(e.idx) + 1)
		if e.kind == &"liana":
			continue
		var tree: bool = e.kind in [&"palm", &"broadleaf", &"banyan", &"mangrove"]
		P.tag(root, q.x, q.y + (3.0 if tree else 1.6), nm, 1.0 if tree else 1.0, 30.0)
	P.tag(root, -30.0, -107.0, "Лиана на дереве — волокно", 1.0, 30.0)
	_stand(&"flora", "Растения и ресурсы", -28.0, -94.0, -28.0, -112.0, 2.0)

# ------------------------------------------------------------ животные

func _fauna(root: Node3D) -> void:
	P.signpost(root, 30.0, -55.0, "ЖИВОТНЫЕ", "Все виды в ряд · еду можно дать с руки (E)\nубитые появляются снова через %d с" % int(RESPAWN_S))
	var fa := Fauna.instance()
	# два ряда по 8 загонов вплотную: 14 видов + приручение + стол с кормом
	var slots: Array[Vector2] = []
	for row in 2:
		for col in 8:
			slots.append(Vector2(33.0 + col * 6.5, -74.0 + row * 11.0))
	for i in SPECIES_ORDER.size():
		var sp := SPECIES_ORDER[i]
		var s := slots[i]
		var small := sp in [&"crab", &"scorpion", &"spider", &"snake", &"iguana", &"python", &"hermit_crab", &"centipede", &"salamander"]
		var r := 2.6 if small else 3.4
		P.pen(root, s.x, s.y, r)
		var nm := sp as String
		if fa:
			var a := _penned(fa, sp, s, r)
			if a:
				nm = String(a.cfg.get("name", sp))
		P.tag(root, s.x, s.y + r + 0.4, nm, 1.5, 30.0)
	# птицы — стайками над рядами
	if fa:
		for i in BIRDS.size():
			var s := Vector2(40.0 + i * 15.0, -84.0)
			_flock(fa, BIRDS[i], Vector3(s.x, 0.0, s.y), 3 if BIRDS[i] != &"bat" else 4)
			P.tag(root, s.x, s.y, ["Попугаи", "Чайки", "Летучие мыши (ночью)"][i], 1.2, 40.0)
	# загон приручения: дикий кабан, рядом стол с кормом
	var tp := slots[SPECIES_ORDER.size()]
	P.pen(root, tp.x, tp.y, 3.4)
	if fa:
		_penned(fa, &"boar", tp, 3.4)
	P.tag(root, tp.x, tp.y + 4.0, "Приручение: дайте кабану корм с руки (E)\nили меню F1 → «Приручить у прицела»", 1.5, 30.0)
	var fp := slots[SPECIES_ORDER.size() + 1]
	var t := P.table(root, fp.x, fp.y, 3.0)
	var foods: Array[StringName] = []
	for id: StringName in [&"banana", &"mango", &"papaya", &"coconut", &"berries", &"seed_taro", &"taro", &"meat_raw", &"fish_raw"]:
		if Items.get_item(id):
			foods.append(id)
	_lay(&"fauna", root, t, foods, 3)
	P.tag(root, fp.x, fp.y, "Корм для приручения", 1.5, 30.0)
	_stand(&"fauna", "Животные", 52.0, -54.0, 52.0, -70.0, 0.5)

## Животное в загоне: держится внутри ограды, пока не приручено; убитое появляется снова.
## variant ≥ 0 — вариант модели вида (UserClipRig: зелёная/синяя куфия, кеа…), и после возрождения тот же.
func _penned(fa: Fauna, sp: StringName, s: Vector2, r: float, variant: int = -1) -> Animal:
	UserClipRig.next_variant = variant
	var a := fa.spawn(sp, Vector3(s.x, P.ground(s.x, s.y) + 0.3, s.y), r * 0.45)
	UserClipRig.next_variant = -1
	if a:
		_own(&"fauna", a)
		var pen := {"a": a, "c": Vector3(s.x, 0.0, s.y), "r": maxf(0.6, r - 0.5)}
		_pens.append(pen)
		_track({"kind": &"pen", "sp": sp, "s": s, "r": r, "node": a, "variant": variant})
	return a

func _flock(fa: Fauna, sp: StringName, c: Vector3, n: int) -> void:
	for a in fa.spawn_flock(sp, c, n, 7.0):
		_own(&"fauna", a)
		_track({"kind": &"bird", "sp": sp, "c": c, "node": a})

# ------------------------------------------------------------ возрождение убитых

## Записи: {kind: pen|bird|shark, node, t (таймер до возрождения, −1 — жив), …}
var _respawns: Array = []

func _track(e: Dictionary) -> void:
	e["t"] = -1.0
	_respawns.append(e)

static func _is_gone(n: Variant) -> bool:
	if not is_instance_valid(n):
		return true
	var o := n as Node
	if o.is_queued_for_deletion():
		return true
	return o.has_method(&"is_dead") and bool(o.call(&"is_dead"))

func _tick_respawn(dt: float) -> void:
	for e: Dictionary in _respawns:
		if float(e.t) < 0.0:
			if _is_gone(e.node):
				e.t = RESPAWN_S
			continue
		e.t = float(e.t) - dt
		if float(e.t) <= 0.0:
			_respawn(e)

## Вернуть всех убитых сразу (кнопка в меню F1).
func respawn_all() -> int:
	var n := 0
	for e: Dictionary in _respawns:
		if _is_gone(e.node):
			_respawn(e)
			n += 1
	return n

func _respawn(e: Dictionary) -> void:
	e.t = -1.0
	var old: Variant = e.node
	if is_instance_valid(old) and not (old as Node).is_queued_for_deletion():
		(old as Node).queue_free()
	var fa := Fauna.instance()
	match e.kind:
		&"pen":
			if fa == null:
				return
			var s: Vector2 = e.s
			UserClipRig.next_variant = int(e.get("variant", -1))
			var a := fa.spawn(e.sp, Vector3(s.x, P.ground(s.x, s.y) + 0.3, s.y), float(e.r) * 0.45)
			UserClipRig.next_variant = -1
			if a:
				_own(&"fauna", a)
				_pens.append({"a": a, "c": Vector3(s.x, 0.0, s.y), "r": maxf(0.6, float(e.r) - 0.5)})
				e.node = a
		&"bird":
			if fa == null:
				return
			var arr := fa.spawn_flock(e.sp, e.c, 1, 7.0)
			if not arr.is_empty():
				_own(&"fauna", arr[0])
				e.node = arr[0]
		&"shark":
			var sea := get_tree().get_first_node_in_group(&"sea") as Sea
			if sea:
				var sh := sea.spawn_shark(e.sp, e.c, float(e.ring), int(e.seed) + randi() % 1000)
				_own(&"sea", sh)
				e.node = sh

func _physics_process(delta: float) -> void:
	_tick_respawn(delta)
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
		var e := {"zone": zone, "pos": w, "id": id, "n": cnt, "node": null}
		_table_items.append(e)
		_spawn_table_item(e)

## Предметы на столах: взятый предмет сразу появляется снова (если включены бесконечные предметы).
var infinite_tables := true
var _table_items: Array = []
var _table_t := 0.0

func _spawn_table_item(e: Dictionary) -> void:
	var w: Vector3 = e.pos
	var pk := ItemPickup.spawn(self, w, [{"id": e.id, "n": e.n}])
	e.node = pk
	if pk:
		pk.freeze = true
		pk.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		_own(e.zone, pk)
		var l := P.label(pk, w + Vector3(0, 0.3, 0), Items.item_name(e.id), 30, P.SIGN_COLOR, 10.0)
		l.pixel_size = 0.0032

func _tick_tables(dt: float) -> void:
	if not infinite_tables:
		return
	_table_t -= dt
	if _table_t > 0.0:
		return
	_table_t = 0.25
	for e: Dictionary in _table_items:
		var n: Variant = e.node
		if n == null or not is_instance_valid(n) or (n as Node).is_queued_for_deletion():
			if (_roots.has(e.zone) and is_instance_valid(_roots[e.zone])):
				_spawn_table_item(e)

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
	P.signpost(root, -12.0, -64.0, "ПРЕДМЕТЫ", "Все предметы игры — берите (E), на столе они не кончаются")
	var ids := all_items().filter(func(id: StringName) -> bool: return Items.get_item(id).kind != &"weapon")
	var per := 8
	var tables := ceili(ids.size() / float(per))
	var cols := 3
	for ti in tables:
		var col := ti % cols
		var row := ti / cols
		var x := -40.0 + col * 12.0
		var z := -88.0 + row * 4.5
		var t := P.table(root, x, z, 4.0)
		var part := ids.slice(ti * per, mini(ids.size(), (ti + 1) * per))
		_lay(&"items", root, t, part, 1)
	_stand(&"items", "Предметы", -10.0, -76.0, -28.0, -76.0, 0.5)

func _range(root: Node3D) -> void:
	P.signpost(root, -5.0, -70.0, "СТРЕЛЬБИЩЕ", "Мишени на 10, 25, 50 и 100 м · гонги, бумага, чучела\nПКМ — прицел · R — перезарядка · V — режим огня")
	# стойка с оружием и боеприпасами
	var weapons := all_items().filter(func(id: StringName) -> bool:
		var d := Items.get_item(id)
		return d.kind == &"weapon" or d.kind == &"ammo" or String(id).contains("arrow") or String(id).contains("bolt") \
			or String(id).contains("bullet") or String(id).contains("powder") or String(id).contains("shot"))
	var half := ceili(weapons.size() / 2.0)
	var t1 := P.table(root, 5.0, -70.0, 4.5)
	_lay(&"range", root, t1, weapons.slice(0, half), 20)
	var t2 := P.table(root, 15.0, -70.0, 4.5)
	_lay(&"range", root, t2, weapons.slice(half), 20)
	P.tag(root, 10.0, -71.0, "Оружие и боеприпасы", 1.6, 30.0)
	# линия стрельбы
	# дорожка 10/25/50/100 м: бумага, гонги, чучела, образцы поверхностей (SandboxRange)
	var rg := SandboxRange.build(root, Vector3(10.0, P.ground(10.0, -67.0), -67.0), Vector3.BACK,
		func(x: float, z: float) -> float: return P.ground(x, z))
	for dm: TrainingDummy in rg.dummies:
		var l := P.label(root, dm.global_position + Vector3.UP * 2.15, "", 44, Color(1.0, 0.6, 0.4), 120.0)
		_dummies.append({"dummy": dm, "label": l, "n": 0})
	_dummy(&"range", root, -4.0, -62.0, "Ближний бой")
	_stand(&"range", "Стрельбище", 10.0, -68.5, 10.0, -40.0, 1.2)

func _dummy(zone: StringName, root: Node3D, x: float, z: float, title: String) -> void:
	var d := TrainingDummy.new()
	root.add_child(d)
	d.global_position = Vector3(x, P.ground(x, z), z)
	d.rotation.y = PI
	P.tag(root, x, z, title, 2.55, 80.0)
	var l := P.label(root, Vector3(x, P.ground(x, z) + 2.15, z), "", 44, Color(1.0, 0.6, 0.4), 80.0)
	_dummies.append({"dummy": d, "label": l, "n": 0})

func _process(delta: float) -> void:
	_tick_tables(delta)
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
	var sg := _b(-56.0, -5.0)
	P.signpost(root, sg.x, sg.y, "СТРОЙКА", "Все постройки: готовые и чертежи · B — меню стройки")
	var bm := _bm()
	if bm == null:
		return
	# флаг команды и территория
	var fz := _b(-74.0, 26.0)
	var flag := bm.place_flag(0, Vector3(fz.x, P.ground(fz.x, fz.y), fz.y), 0.0)
	_own(&"build", flag)
	P.tag(root, fz.x, fz.y, "Флаг команды — возрождение\nтерритория 40 м (видна в режиме стройки)", 3.6)
	# дом: стены, окно, проём, дверь, крыша
	var hb := _b(-96.0, -14.0)
	var base := Transform3D(Basis(), Vector3(hb.x, P.ground(hb.x, hb.y), hb.y))
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
	_tb(root, -96.0, -10.5, "Дом: стены, окно, дверь, крыша", 3.2)
	# платформа на сваях + лестница + стена с окном
	var plat := _pb(&"platform", -84.0, -16.0)
	if plat:
		var s := bm.find_socket(&"wall", plat.base_xform * Vector3(0, BuildDefs.DECK_H, -1.5), 1.0)
		if not s.is_empty():
			_place_xf(&"build", &"wall_window", s.xform)
		var st := bm.find_socket(&"stairs", plat.base_xform * Vector3(0, 0, 3.0), 3.0)
		if not st.is_empty():
			_place_xf(&"build", &"stairs", st.xform, {}, st.ctx)
	_tb(root, -84.0, -11.0, "Платформа, лестница", 3.0)
	_pb(&"shelter", -72.0, -16.0, 0.4)
	_tb(root, -72.0, -13.0, "Шалаш", 2.4)
	_pb(&"fire_pit", -65.0, -14.0)
	_tb(root, -65.0, -14.0, "Каменный очаг", 1.3)
	# оборона: частокол с воротами, колья, вышка, фундамент
	var pq := _b(-98.0, 4.0)
	for i in 4:
		var x := pq.x + i * 3.0
		var xf := Transform3D(Basis(), Vector3(x, P.ground(x, pq.y), pq.y))
		_place_xf(&"build", &"gate" if i == 2 else &"palisade", xf)
	_tb(root, -93.5, 5.5, "Частокол и ворота", 3.4)
	_pb(&"spikes", -84.0, 6.0)
	_tb(root, -84.0, 6.0, "Колья — ловушка", 1.6)
	var tower := _pb(&"watchtower", -74.0, 6.0)
	if tower:
		var ts := bm.find_socket(&"stairs", tower.base_xform * Vector3(0, 0, 3.0), 5.0)
		if not ts.is_empty():
			_place_xf(&"build", &"stairs", ts.xform, {}, ts.ctx)
	_tb(root, -74.0, 2.5, "Сторожевая вышка", 5.6)
	_pb(&"foundation", -64.0, 5.0)
	_tb(root, -64.0, 5.0, "Каменный фундамент — не горит", 1.6)
	# хранение и верстак
	var chest := _pb(&"chest", -98.0, 16.0)
	if chest is BuildChest:
		for e in [[&"stick", 20], [&"stone", 20], [&"rope", 10], [&"coconut", 5]]:
			if Items.get_item(e[0]):
				(chest as BuildChest).storage.add(e[0], e[1])
	_tb(root, -98.0, 16.0, "Сундук (с вещами)", 1.4)
	var lh := _pb(&"log_holder", -92.0, 16.0)
	if lh is BuildLogHolder:
		(lh as BuildLogHolder).add_logs(BuildLogHolder.MAX_LOGS)
	_tb(root, -92.0, 16.0, "Поленница: 10 брёвен", 1.9)
	_pb(&"workbench", -86.0, 16.0)
	_tb(root, -86.0, 16.0, "Верстак", 1.7)
	# чертежи: недостроенные
	var half := _pb(&"wall", -78.0, 16.0, 0.0, false)
	if half:
		half.add_material(&"log", 3)
	_tb(root, -78.0, 16.0, "Чертёж стены — наполовину", 3.0)
	_pb(&"palisade", -71.0, 16.0, 0.0, false)
	_tb(root, -71.0, 16.0, "Чертёж частокола — пустой", 3.0)
	# взрывать и жечь
	_pb(&"wall", -92.0, 30.0)
	_pb(&"palisade", -86.0, 30.0)
	_tb(root, -89.0, 30.0, "Взорвите динамитом или подожгите", 3.0)
	var t := _tab(root, -89.0, 25.0, 3.0)
	var boom: Array[StringName] = []
	for id: StringName in [&"dynamite", &"molotov"]:
		if Items.get_item(id):
			boom.append(id)
	_lay(&"build", root, t, boom, 5)
	_stand(&"build", "Стройка", BUILD_C.x + 22.0, BUILD_C.y + 2.0, BUILD_C.x, BUILD_C.y, 2.0)

## Перенос координат исходной раскладки стройки (центр (−81, 7)) к BUILD_C, чуть плотнее.
func _b(x: float, z: float) -> Vector2:
	return BUILD_C + Vector2((x + 81.0) * 0.9, (z - 7.0) * 0.7)

func _pb(def_id: StringName, x: float, z: float, yaw: float = 0.0, finish: bool = true) -> Blueprint:
	var q := _b(x, z)
	return _place(&"build", def_id, q.x, q.y, yaw, finish)

func _tb(root: Node3D, x: float, z: float, text: String, h: float = 1.6) -> void:
	var q := _b(x, z)
	P.tag(root, q.x, q.y, text, h)

func _tab(root: Node3D, x: float, z: float, length: float = 4.0) -> StaticBody3D:
	var q := _b(x, z)
	return P.table(root, q.x, q.y, length)

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
	P.signpost(root, -38.0 + SURV_D.x, 65.0 + SURV_D.y, "ВЫЖИВАНИЕ", "Вода, костёр, копчение, огород, травы")
	var sv := Survival.instance()
	if sv == null:
		return
	var put := func(kit: StringName, x: float, z: float, title: String, h: float = 1.6) -> Node3D:
		var q := Vector2(x, z) + SURV_D
		var n := sv.place_structure(null, kit, Vector3(q.x, P.ground(q.x, q.y), q.y), 0.3)
		_own(&"survival", n)
		P.tag(root, q.x, q.y, title, h)
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
	P.tag(root, -62.0 + SURV_D.x, 86.0 + SURV_D.y, "Пресный пруд — можно пить", 1.2)
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
	P.tag(root, -46.75 + SURV_D.x, 68.5 + SURV_D.y, "Огород — единственная возобновляемая еда", 2.1)
	# дикие травы и растения
	for i in 3:
		var kind: StringName = [&"herb", &"berry", &"taro"][i]
		var x := -52.0 + i * 4.0 + SURV_D.x
		var wz := 76.0 + SURV_D.y
		var w := SvWild.new()
		w.kind = kind
		sv.structures.add_child(w)
		w.global_position = Vector3(x, P.ground(x, wz) - 0.03, wz)
		_own(&"survival", w)
		P.tag(root, x, wz, ["Лечебная трава (яд)", "Дикие ягоды", "Дикое таро"][i], 1.2)
	_stand(&"survival", "Выживание", 34.0, -48.0, 48.0, -28.0, 0.5)

func _beach(root: Node3D) -> void:
	var sv := Survival.instance()
	if sv == null or world == null:
		return
	var I: Dictionary = world.arch.islands[0]
	var a0 := BEACH_ANGLE
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
	var a := PIER_ANGLE
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
		for e in [[&"reef", c2, 10.0, 901], [&"tiger", c2 + Vector2(dir.x, dir.z) * 12.0, 20.0, 902]]:
			var sh := sea.spawn_shark(e[0], e[1], e[2], e[3])
			_own(&"sea", sh)
			_track({"kind": &"shark", "sp": e[0], "c": e[1], "ring": e[2], "seed": e[3], "node": sh})
		sea.call(&"_spawn_school", Vector3(end.x, 0.0, end.z) + dir * 6.0, 3)
	_point(&"pier", "Пирс (у берега)", Vector3(start.x, deck + 0.15, start.z) + dir * 2.0, start + dir * 30.0 + Vector3.UP * 0.5)
	_point(&"sea", "Море (конец пирса)", Vector3(end.x, deck + 0.15, end.z) - dir * 2.0, Vector3(end.x, -1.0, end.z) + dir * 14.0)

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
	_stand(&"bots", "Арена ботов", c.x + 18.0, c.y - 8.0, c.x, c.y, 1.0)

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
