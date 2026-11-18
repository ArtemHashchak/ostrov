class_name TutorialDirector
extends Node
## Режим «Обучение». Ведёт игрока по шагам на настоящем архипелаге (сцена —
## наследник match.tscn, все модули те же). Каждый шаг завершается настоящим
## событием игры: перемещение, предметы в инвентаре, крафт, срубленное дерево,
## постройка, смерть и возрождение, мост, попадания, гибель бота, огонь, флаг.
##
## Мир готовится под обучение: свой флаг у старта, хищники и акулы рядом
## с домашним островом убраны (акула появляется только у моста — на уроке),
## мост к ближайшему острову почти достроен — последнюю секцию ставит игрок.
## В обучении стройка ускорена: после первой своей детали остальное
## достраивается само (за этим следит _assist).

signal step_changed(index: int, id: StringName)
signal finished

const STEPS: Array[Dictionary] = [
	{"id": &"look", "title": "Осмотрись",
		"text": "Ты на домашнем острове своей команды — Красных. Поводи мышью, чтобы осмотреться."},
	{"id": &"move", "title": "Пройдись",
		"text": "Пройди несколько шагов по острову."},
	{"id": &"jump", "title": "Прыжок",
		"text": "Подпрыгни пару раз — так забираются на камни и брёвна."},
	{"id": &"sprint", "title": "Бег",
		"text": "Пробегись. Бег тратит выносливость: когда она кончается, герой устаёт и замедляется."},
	{"id": &"crouch", "title": "Присядь",
		"text": "Присядь — так ты тише и ниже."},
	{"id": &"gather", "title": "Палки и камень",
		"text": "Всё в игре делается из того, что найдёшь. Подбери 2 палки и камень — они лежат на земле."},
	{"id": &"liana", "title": "Лианы",
		"text": "Лианы свисают со стволов деревьев. Сорви 2 лианы — из них свивают верёвку."},
	{"id": &"craft", "title": "Каменный топор",
		"text": "Открой крафт и сделай верёвку (из лиан), а потом каменный топор: палка + камень + верёвка."},
	{"id": &"chop", "title": "Сруби дерево",
		"text": "Выбери топор на панели быстрого доступа и руби дерево. Оно упадёт и распадётся на брёвна. Подними бревно на плечо.\nМир не восстанавливается: пень останется навсегда — береги лес."},
	{"id": &"thirst", "title": "Вода и еда",
		"text": "Пресной воды на островах мало: озёра есть только на родниковых островах, ещё воду собирают от дождя. Морская вода солёная — пить её вредно.\nСейчас утоли жажду кокосом: подбери его под пальмой (или сбей ударом), выбери на панели и съешь."},
	{"id": &"poison", "title": "Яд и травы",
		"text": "Тебя ужалил скорпион — ты отравлен. Яд снимает припарка: 2 лечебные травы + лист (лист у тебя уже есть). Собери травы, сделай припарку в крафте и используй её."},
	{"id": &"shelter", "title": "Шалаш",
		"text": "Открой меню стройки и выбери «Шалаш». Поставь чертёж, затем носи в него материалы: подойди к чертежу и нажми взаимодействие. Бревно на плече тоже подойдёт.\nВ обучении стройка ускорена: после первой детали шалаш достроится сам."},
	{"id": &"wall", "title": "Стена",
		"text": "Теперь стена из брёвен: меню стройки → «Стена из брёвен». Стены соединяются друг с другом, бывают с окном и с дверью, сверху кладут крышу."},
	{"id": &"flag", "title": "Твой флаг",
		"text": "Это флаг твоей команды. Пока он стоит — ты возрождаешься рядом с ним. Вокруг флага твоя территория (40 м): враги не могут там строить, а ты строишь быстрее. Подойди к флагу."},
	{"id": &"respawn", "title": "Возрождение",
		"text": "Сейчас ты погибнешь — посмотри, как работает возрождение. Через 10 секунд ты появишься у флага. Ресурсы из рюкзака выпадают мешком на месте гибели, инструменты и оружие остаются при тебе."},
	{"id": &"bridge", "title": "Мост",
		"text": "Острова разделены морем, а в море — акулы: плавать опасно, стая убивает за секунды. Поэтому главное в игре — мосты из связок брёвен на воде.\nМост к соседнему острову почти готов — поставь последнюю секцию: меню стройки → «Мост: связка брёвен», в конце моста."},
	{"id": &"cross", "title": "На тот берег",
		"text": "Перейди по мосту на соседний остров. Не падай в воду — под мостом кружит акула!"},
	{"id": &"dummy", "title": "Оружие",
		"text": "Тебе выдали лук, стрелы и копьё. Выбери лук на панели, зажми прицел и стреляй. Копьё бьёт вблизи, его можно и метнуть. Попади в чучело 3 раза."},
	{"id": &"bot", "title": "Противник",
		"text": "Боец команды Синих идёт к тебе! Победи его — оружием или топором. Если погибнешь, возродишься у своего флага."},
	{"id": &"molotov", "title": "Огонь",
		"text": "Деревянные мосты и постройки горят. Сожги мост Синих: выбери коктейль Молотова и брось его в мост."},
	{"id": &"enemy_flag", "title": "Чужой флаг",
		"text": "Флаг Синих — их возрождение. Сломай его топором, оружием или динамитом (поджёг и бросок, отбеги!). Без флага команда больше не возрождается и выбывает, когда гибнет её последний боец. Последний флаг на архипелаге побеждает."},
]

const DANGEROUS: Array[StringName] = [&"snake", &"croc", &"scorpion", &"spider", &"boar", &"monitor", &"monkey"]

var index: int = -1
var ui: TutorialUI
var done: bool = false
var started: bool = false

var player: Node3D
var world: Node
var home: Dictionary = {}
var neighbour: Dictionary = {}
var bridge_info: Dictionary = {}
var bridge: Array = []            # Blueprint — заготовленные секции моста
var shark: Node3D = null
var dummy: Node3D = null
var bot: Node3D = null
var enemy_raft: Node3D = null
var enemy_flag_pos: Vector3 = Vector3.ZERO
var landing: Vector3 = Vector3.ZERO

var _assist: Array = []           # Blueprint, которые достраиваются сами
var _assist_t := 0.0
var _placed: Array = []           # чертежи игрока на текущем шаге
var _acc := 0.0                   # счётчик шага (метры, секунды, радианы…)
var _cnt := 0
var _flag := false
var _prev_pos := Vector3.ZERO
var _prev_fwd := Vector3.ZERO
var _was_air := false
var _min_v := 100.0
var _t := 0.0
var _died := false
var _target_rec: Dictionary = {}
var _next_delay := -1.0
var _prebuilding := false

static func instance() -> TutorialDirector:
	var t := Engine.get_main_loop() as SceneTree
	return t.get_first_node_in_group(&"tutorial") as TutorialDirector if t else null

func _ready() -> void:
	add_to_group(&"tutorial")
	_ensure_action()
	ui = TutorialUI.new()
	add_child(ui)
	ui.panel.visible = false
	ui.start_match_pressed.connect(func() -> void: GameLauncher.start(get_tree(), GameLauncher.load_lobby()))
	ui.menu_pressed.connect(func() -> void: GameLauncher.to_menu(get_tree()))
	Events.structure_completed.connect(_on_structure_completed)
	Events.blueprint_placed.connect(_on_blueprint_placed)
	Events.character_spawned.connect(_on_spawned)
	Events.character_died.connect(_on_died)
	Events.flag_destroyed.connect(_on_flag_destroyed)
	Events.structure_destroyed.connect(_on_structure_destroyed)
	_boot()

static func _ensure_action() -> void:
	if InputMap.has_action(&"tutorial_skip"):
		return
	InputMap.add_action(&"tutorial_skip")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_N
	InputMap.action_add_event(&"tutorial_skip", ev)

func _boot() -> void:
	# ждём мир, игрока и начало матча
	while not (Game.is_playing() and get_tree().get_first_node_in_group(&"player") != null):
		await get_tree().process_frame
	player = get_tree().get_first_node_in_group(&"player") as Node3D
	world = get_tree().get_first_node_in_group(&"world")
	_prepare_world()
	started = true
	await get_tree().create_timer(1.0).timeout
	go_to(0)

# ================================================================== мир

func _prepare_world() -> void:
	for I: Dictionary in world.call(&"islands"):
		if int(I.team) == 0:
			home = I
	# свой флаг — сразу у старта (MatchDirector при auto_flags=false флаги не ставит)
	var bm := BuildModule.instance()
	var md := MatchDirector.instance()
	if not Game.teams[0].flag_placed:
		var fp: Vector3 = md.flag_spot(0) if md else player.global_position + Vector3(4, 0, 0)
		if bm:
			bm.place_flag(0, fp, 0.0)
		else:
			Game.set_flag_placed(0, fp)
	var inv := _inv()
	if inv and inv.count(&"flag") > 0:
		inv.remove(&"flag", inv.count(&"flag"))
	# соседний остров с самым коротким мостом
	var best_len := INF
	if bm:
		for I: Dictionary in world.call(&"islands"):
			if I.id == home.id or (I.center as Vector2).distance_to(home.center) > 320.0:
				continue
			var bt := bm.find_bridge_target(home, I)
			if bool(bt.get("ok", false)) and float(bt.length) < best_len:
				best_len = float(bt.length)
				neighbour = I
				bridge_info = bt
	if not bridge_info.is_empty():
		var e: Vector3 = bridge_info.end
		var lp: Variant = _land_near(e, 0.0, 12.0, 0.25)
		landing = lp if lp is Vector3 else e
	# день, ясно и время стоит — чтобы всё было видно
	if world.has_method(&"set_time_of_day"):
		world.call(&"set_time_of_day", 9.5)
	if world.has_method(&"set_time_paused"):
		world.call(&"set_time_paused", true)
	if world.has_method(&"set_weather"):
		world.call(&"set_weather", &"clear", true)
	_cull_wildlife()
	# акулы ещё могут появиться позже (Sea заселяет море отложенно) — проверяем снова
	get_tree().create_timer(3.0).timeout.connect(_cull_wildlife)
	get_tree().create_timer(12.0).timeout.connect(_cull_wildlife)

## Убрать хищников и акул вокруг домашнего острова и соседа (кроме акулы урока).
func _cull_wildlife() -> void:
	if not is_inside_tree() or home.is_empty():
		return
	var centers: Array[Vector2] = [home.center]
	var radii: Array[float] = [float(home.radius) + 140.0]
	if not neighbour.is_empty():
		centers.append(neighbour.center)
		radii.append(float(neighbour.radius) + 120.0)
	var sea := get_tree().get_first_node_in_group(&"sea")
	if sea and sea.get(&"sharks") is Array:
		var arr: Array = sea.get(&"sharks")
		for s in arr.duplicate():
			if not is_instance_valid(s) or s == shark:
				continue
			if _near_any(s as Node3D, centers, radii):
				arr.erase(s)
				(s as Node).queue_free()
	var fa := Fauna.instance()
	if fa:
		for k in centers.size():
			var c3 := Vector3(centers[k].x, 0, centers[k].y)
			for a in fa.animals_near(c3, radii[k]):
				if DANGEROUS.has(a.species):
					a.queue_free()

static func _near_any(n: Node3D, centers: Array[Vector2], radii: Array[float]) -> bool:
	var p := Vector2(n.global_position.x, n.global_position.z)
	for k in centers.size():
		if p.distance_to(centers[k]) < radii[k]:
			return true
	return false

func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, float(world.call(&"height_at", p.x, p.z)), p.z)

func _dry(x: float, z: float, min_h: float) -> bool:
	if not bool(world.call(&"is_land", x, z)):
		return false
	var h := float(world.call(&"height_at", x, z))
	if h < float(world.call(&"water_level")) + min_h:
		return false
	var n := world.call(&"normal_at", x, z) as Vector3 if world.has_method(&"normal_at") else Vector3.UP
	return n.y > 0.8

## Ближайшая к c ровная суша на кольцах rmin..rmax (null — нет).
func _land_near(c: Vector3, rmin: float, rmax: float, min_h: float = 0.4) -> Variant:
	var r := rmin
	while r <= rmax:
		var steps := maxi(1, int(TAU * maxf(r, 0.5) / 1.5)) if r > 0.0 else 1
		var off := randf() * TAU
		for k in steps:
			var a := off + TAU * float(k) / float(steps)
			var x := c.x + cos(a) * r
			var z := c.z + sin(a) * r
			if _dry(x, z, min_h):
				return _ground(Vector3(x, 0, z))
		r += 1.0
	return null

## Ровная суша острова I, дальше всего от точки from.
func _land_far(I: Dictionary, from: Vector3, min_h: float = 1.0) -> Variant:
	var c: Vector2 = I.center
	var R := float(I.radius) * 1.15
	var best: Variant = null
	var bd := -1.0
	var x := c.x - R
	while x <= c.x + R:
		var z := c.y - R
		while z <= c.y + R:
			if _dry(x, z, min_h):
				var d := Vector2(x - from.x, z - from.z).length()
				if d > bd:
					bd = d
					best = _ground(Vector3(x, 0, z))
			z += 3.0
		x += 3.0
	return best

## Заготовка моста: все секции, кроме последней, достроены.
func build_bridge() -> void:
	if not bridge.is_empty() or bridge_info.is_empty():
		return
	var bm := BuildModule.instance()
	if bm == null:
		return
	var n := int(bridge_info.sections)
	_prebuilding = true
	_build_bridge_sections(bm, n)
	_prebuilding = false

func _build_bridge_sections(bm: BuildModule, n: int) -> void:
	var prev: Blueprint = bm.place_blueprint(&"raft", bridge_info.xform, 0)
	if prev == null:
		return
	_fill_all(prev)
	bridge.append(prev)
	for i in range(1, n - 1):
		var slot := bm.next_raft_slot(prev)
		if slot.is_empty():
			break
		var bp := bm.place_blueprint(&"raft", slot.xform, 0, {"type": &"raft", "parent": slot.parent, "offset": slot.offset})
		if bp == null:
			break
		_fill_all(bp)
		bridge.append(bp)
		prev = bp

## Где ставить последнюю секцию моста (центр свободного слота).
func bridge_socket() -> Variant:
	if bridge.is_empty():
		return null
	var last: Blueprint = bridge[bridge.size() - 1]
	if not is_instance_valid(last):
		return null
	var bm := BuildModule.instance()
	var slot := bm.next_raft_slot(last) if bm else {}
	if slot.is_empty():
		return null
	return (slot.xform as Transform3D).origin

func _fill_all(bp: Blueprint) -> void:
	for t: StringName in [&"log", &"stick", &"rope", &"stone", &"rock", &"cloth"]:
		bp.add_material(t, 999, player)
	# на случай деталей других типов
	for i in bp.parts.size():
		if not bp.filled[i]:
			bp.fill_part(i, player)

func _spawn_lesson_shark() -> void:
	if shark != null or bridge_info.is_empty():
		return
	var sea := get_tree().get_first_node_in_group(&"sea")
	if sea == null or not sea.has_method(&"spawn_shark"):
		return
	var a: Vector3 = bridge_info.start
	var b: Vector3 = bridge_info.end
	var mid := Vector2((a.x + b.x) * 0.5, (a.z + b.z) * 0.5)
	shark = sea.call(&"spawn_shark", &"tiger", mid, 9.0, 4242) as Node3D

## Сторона соседнего острова напротив моста: там флаг и мост Синих.
func _far_side(k: float) -> Vector3:
	var c: Vector2 = neighbour.center
	var away := (c - Vector2(landing.x, landing.z)).normalized()
	var p := c + away * float(neighbour.radius) * k
	return _ground(Vector3(p.x, 0, p.y))

func _setup_enemy_base() -> void:
	if Game.teams.size() < 2 or Game.teams[1].flag_placed or neighbour.is_empty():
		return
	var bm := BuildModule.instance()
	# флаг: на ровной суше, дальше всего от места высадки (территория 40 м не мешает мосту)
	var fv: Variant = _land_far(neighbour, landing, 1.0)
	if not (fv is Vector3):
		fv = _land_far(neighbour, landing, 0.4)
	var fp: Vector3 = fv if fv is Vector3 else _far_side(0.5)
	enemy_flag_pos = fp
	if bm:
		bm.place_flag(1, fp, 0.0)
	else:
		Game.set_flag_placed(1, fp)
	if bm == null:
		return
	# мост Синих — секция у ближайшего к флагу берега
	var c: Vector2 = neighbour.center
	var out := (Vector2(fp.x, fp.z) - c)
	out = out.normalized() if out.length() > 0.5 else (c - Vector2(landing.x, landing.z)).normalized()
	for da: float in [0.0, 0.35, -0.35, 0.7, -0.7, 1.1, -1.1, 1.6, -1.6, 2.2, -2.2, PI]:
		var dir := out.rotated(da)
		var yaw := atan2(-dir.x, -dir.y)
		var water_from := -1.0
		var r := 1.0
		while r < 45.0:
			var q := Vector2(fp.x, fp.z) + dir * r
			if bool(world.call(&"is_land", q.x, q.y)):
				water_from = -1.0
			else:
				if water_from < 0.0:
					water_from = r
				if r - water_from > 6.0:
					break
				var res := bm.shore_raft(Vector3(q.x, 0, q.y), yaw)
				if bool(res.ok):
					var bp := bm.place_blueprint(&"raft", res.xform, 1)
					if bp:
						_fill_all(bp)
						enemy_raft = bp
						var s2 := bm.next_raft_slot(bp)
						if not s2.is_empty():
							var bp2 := bm.place_blueprint(&"raft", s2.xform, 1, {"type": &"raft", "parent": s2.parent, "offset": s2.offset})
							if bp2:
								_fill_all(bp2)
						return
			r += 0.5
	# берега не нашлось — деревянная стена Синих у флага (тоже горит)
	var wv: Variant = _land_near(fp, 5.0, 14.0, 0.4)
	if wv is Vector3:
		var w := bm.place_blueprint(&"wall", Transform3D(Basis(Vector3.UP, randf() * TAU), wv), 1)
		if w:
			_fill_all(w)
			enemy_raft = w

# ================================================================== шаги

func step_id() -> StringName:
	return STEPS[index].id if index >= 0 and index < STEPS.size() else &""

func go_to(i: int) -> void:
	index = i
	_acc = 0.0
	_cnt = 0
	_flag = false
	_t = 0.0
	_died = false
	_placed.clear()
	_target_rec = {}
	_next_delay = -1.0
	if i >= STEPS.size():
		_finish()
		return
	var s: Dictionary = STEPS[i]
	ui.panel.visible = true
	ui.set_step(i, STEPS.size(), s.title, s.text, _hint(s.id))
	ui.set_target(null)
	if player:
		_prev_pos = player.global_position
		_prev_fwd = _fwd()
	_enter(s.id)
	step_changed.emit(i, s.id)
	print("[tutorial] шаг %d: %s" % [i + 1, s.id])

func _k(action: StringName) -> String:
	return "[%s]" % UITheme.key_name(action)

func _hint(id: StringName) -> String:
	match id:
		&"look": return "Мышь — осмотреться"
		&"move": return "%s %s %s %s — ходьба" % [_k(&"move_forward"), _k(&"move_left"), _k(&"move_back"), _k(&"move_right")]
		&"jump": return "%s — прыжок" % _k(&"jump")
		&"sprint": return "%s + движение — бег" % _k(&"sprint")
		&"crouch": return "%s — присесть" % _k(&"crouch")
		&"gather", &"liana": return "%s — подобрать / сорвать" % _k(&"interact")
		&"craft": return "%s — крафт   ·   %s — рюкзак" % [_k(&"craft"), _k(&"inventory")]
		&"chop": return "1–9 или колесо — выбрать предмет   ·   %s — удар   ·   %s — поднять бревно" % [_k(&"attack"), _k(&"interact")]
		&"thirst": return "%s — подобрать   ·   %s — съесть выбранное" % [_k(&"interact"), _k(&"aim")]
		&"poison": return "%s — сорвать траву   ·   %s — крафт   ·   %s — использовать" % [_k(&"interact"), _k(&"craft"), _k(&"aim")]
		&"shelter", &"wall": return "%s — меню стройки   ·   %s — поставить   ·   %s — повернуть   ·   %s — внести материал" % [_k(&"build_menu"), _k(&"attack"), _k(&"build_rotate"), _k(&"interact")]
		&"bridge": return "%s — меню стройки   ·   секция цепляется к концу моста сама" % _k(&"build_menu")
		&"cross": return "Иди по брёвнам аккуратно — с края легко соскользнуть"
		&"dummy": return "%s — прицел   ·   %s — выстрел / удар   ·   %s — перезарядка" % [_k(&"aim"), _k(&"attack"), _k(&"reload")]
		&"bot": return "%s — удар / выстрел   ·   %s — прицел" % [_k(&"attack"), _k(&"aim")]
		&"molotov": return "%s — поджечь и бросить" % _k(&"attack")
		&"enemy_flag": return "%s — удар   ·   динамит: %s — поджечь и бросить" % [_k(&"attack"), _k(&"attack")]
	return ""

func _enter(id: StringName) -> void:
	var inv := _inv()
	match id:
		&"craft":
			_progress_craft()
		&"thirst":
			player.set(&"thirst", minf(float(player.get(&"thirst")), 42.0))
			player.set(&"hunger", minf(float(player.get(&"hunger")), 55.0))
			_min_v = float(player.get(&"thirst"))
		&"poison":
			if inv and inv.count(&"leaf") < 1:
				inv.add(&"leaf", 1)
			Survival.set_poison(player, 0.08, 600.0)
		&"respawn":
			_next_delay = 3.0
		&"bridge":
			build_bridge()
			_spawn_lesson_shark()
			ui.flash("Осторожно: акулы!")
		&"dummy":
			if inv:
				inv.add(&"bow", 1)
				inv.add(&"arrow", 12)
				inv.add(&"spear", 1)
			_spawn_dummy()
		&"bot":
			if dummy and is_instance_valid(dummy):
				dummy.queue_free()
			dummy = null
			_setup_enemy_base()
			_spawn_bot()
		&"molotov":
			_setup_enemy_base()
			if inv:
				inv.add(&"molotov", 2)
		&"enemy_flag":
			_setup_enemy_base()
			if inv:
				inv.add(&"dynamite", 2)

func complete_step() -> void:
	if index < 0 or done:
		return
	ui.flash("Готово!")
	go_to(index + 1)

## Пропустить шаг: то, что нужно дальше, выдаётся / доделывается за игрока.
func skip_step() -> void:
	if index < 0 or done:
		return
	var inv := _inv()
	match step_id():
		&"craft":
			if inv and inv.count(&"axe_crude") == 0:
				inv.add(&"axe_crude", 1)
		&"poison":
			Survival.set_poison(player, 0.0, 0.0)
		&"respawn":
			if not bool(player.get(&"alive")) and player.has_method(&"respawn"):
				player.call(&"respawn")
		&"shelter", &"wall":
			for bp in _placed:
				if is_instance_valid(bp):
					_fill_all(bp)
		&"bridge":
			build_bridge()
			var sock: Variant = bridge_socket()
			var bm := BuildModule.instance()
			if sock is Vector3 and bm and not bridge.is_empty():
				var slot := bm.next_raft_slot(bridge[bridge.size() - 1])
				if not slot.is_empty():
					var bp := bm.place_blueprint(&"raft", slot.xform, 0, {"type": &"raft", "parent": slot.parent, "offset": slot.offset})
					if bp:
						_fill_all(bp)
						bridge.append(bp)
		&"cross":
			if landing != Vector3.ZERO:
				player.global_position = landing + Vector3.UP * 0.4
		&"dummy":
			pass
		&"bot":
			if bot and is_instance_valid(bot) and bot.has_method(&"die"):
				bot.call(&"die", player, &"tutorial")
		&"molotov":
			if enemy_raft and is_instance_valid(enemy_raft) and enemy_raft.has_method(&"destroy"):
				enemy_raft.call(&"destroy", player)
		&"enemy_flag":
			if Game.teams.size() > 1 and Game.teams[1].flag_alive:
				Game.damage_flag(1, Game.FLAG_MAX_HP * 2.0, player)
	ui.flash("Шаг пропущен")
	go_to(index + 1)

func _unhandled_input(event: InputEvent) -> void:
	if not started or done or index < 0:
		return
	if event.is_action_pressed(&"tutorial_skip") and not get_tree().paused:
		skip_step()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not started or done or index < 0 or player == null or not is_instance_valid(player):
		return
	_process_assist(delta)
	_t += delta
	if _next_delay >= 0.0:
		_next_delay -= delta
		if _next_delay < 0.0:
			_timed()
	if _check(step_id(), delta):
		complete_step()
	_prev_pos = player.global_position
	_prev_fwd = _fwd()

## Прыжки ловим на физическом шаге: при низком FPS прыжок целиком
## укладывается между двумя кадрами отрисовки.
func _physics_process(_delta: float) -> void:
	if not started or done or step_id() != &"jump" or player == null:
		return
	var body := player as CharacterBody3D
	var air := body != null and not body.is_on_floor() and body.velocity.y > 0.5 and not bool(player.get(&"swimming"))
	if air and not _was_air:
		_cnt += 1
	_was_air = air

func _fwd() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	return -cam.global_basis.z if cam else Vector3.FORWARD

func _inv() -> Inventory:
	return player.get(&"inventory") as Inventory if player else null

func _cnt_of(id: StringName) -> int:
	var inv := _inv()
	return inv.count(id) if inv else 0

func _flora_target(kind: StringName, r: float = 90.0) -> Variant:
	var fl := Flora.instance()
	if fl == null:
		return null
	var arr := fl.nodes_near(player.global_position, r, kind)
	if arr.is_empty():
		return null
	return (arr[0].position as Vector3)

## Проверка шага за кадр. true — шаг выполнен.
func _check(id: StringName, delta: float) -> bool:
	var p := player
	var alive := bool(p.get(&"alive"))
	match id:
		&"look":
			_acc += _prev_fwd.angle_to(_fwd())
			ui.set_progress("Осмотрено: %d%%" % int(minf(_acc / 2.2, 1.0) * 100.0))
			return _acc >= 2.2
		&"move":
			var d := Vector2(p.global_position.x - _prev_pos.x, p.global_position.z - _prev_pos.z).length()
			if d < 2.0:
				_acc += d
			ui.set_progress("Пройдено: %d / 10 м" % int(minf(_acc, 10.0)))
			return _acc >= 10.0
		&"jump":
			ui.set_progress("Прыжков: %d / 2" % mini(_cnt, 2))
			return _cnt >= 2
		&"sprint":
			var body2 := p as CharacterBody3D
			if bool(p.get(&"sprinting")) and body2 and Vector2(body2.velocity.x, body2.velocity.z).length() > 1.5:
				_acc += delta
			ui.set_progress("Бег: %.1f / 2 с" % minf(_acc, 2.0))
			return _acc >= 2.0
		&"crouch":
			if bool(p.get(&"crouching")):
				_acc += delta
			ui.set_progress("Присел: %.1f / 1 с" % minf(_acc, 1.0))
			return _acc >= 1.0
		&"gather":
			var st := _cnt_of(&"stick")
			var rk := _cnt_of(&"rock")
			ui.set_progress("Палки: %d / 2   ·   Камень: %d / 1" % [mini(st, 2), mini(rk, 1)])
			if fmod(_t, 1.0) < delta or ui.target == null:
				var want := &"stick" if st < 2 else &"rock"
				ui.set_target(_flora_target(want), "Палка" if want == &"stick" else "Камень")
			return st >= 2 and rk >= 1
		&"liana":
			var li := _cnt_of(&"liana") + _cnt_of(&"rope") * 2 + (2 if _cnt_of(&"axe_crude") > 0 else 0)
			ui.set_progress("Лианы: %d / 2" % mini(li, 2))
			if fmod(_t, 1.0) < delta or ui.target == null:
				ui.set_target(_flora_target(&"liana"), "Лиана")
			return li >= 2
		&"craft":
			_progress_craft()
			return _cnt_of(&"axe_crude") > 0 or _cnt_of(&"axe_modern") > 0
		&"chop":
			if _target_rec.is_empty() or int(_target_rec.get("state", 0)) != 0:
				var fl := Flora.instance()
				if fl and not bool(p.get(&"carrying_log")):
					var arr := fl.nodes_near(p.global_position, 90.0, &"tree")
					if not arr.is_empty():
						if not _target_rec.is_empty():
							_flag = true   # предыдущее дерево срублено
						_target_rec = arr[0].rec
			var holding := StringName(p.call(&"held_item")) if p.has_method(&"held_item") else &""
			var txt := "Топор в руке: %s" % ("да" if String(holding).begins_with("axe") else "нет — выбери его на панели")
			if _flag:
				txt = "Дерево срублено — подними бревно (%s)" % UITheme.key_name(&"interact")
				ui.set_target(_nearest_log(), "Бревно")
			elif not _target_rec.is_empty():
				ui.set_target(_target_rec.pos, "Дерево")
			ui.set_progress(txt)
			return bool(p.get(&"carrying_log"))
		&"thirst":
			var th := float(p.get(&"thirst"))
			_min_v = minf(_min_v, th)
			ui.set_progress("Жажда: %d%%" % int(th))
			if fmod(_t, 1.0) < delta or ui.target == null:
				ui.set_target(_flora_target(&"coconut"), "Пальма с кокосами")
			return th >= _min_v + 8.0
		&"poison":
			var pt := Survival.get_poison(p).y
			ui.set_progress("Травы: %d / 2   ·   Припарка: %s   ·   Яд: %s" % [mini(_cnt_of(&"herb"), 2),
				"есть" if _cnt_of(&"poultice") > 0 else "нет", "действует" if pt > 0.0 else "снят"])
			if fmod(_t, 1.0) < delta or ui.target == null:
				var herb_t: Variant = null
				if _cnt_of(&"herb") < 2 and _cnt_of(&"poultice") == 0:
					herb_t = _flora_target(&"herb")
				ui.set_target(herb_t, "Лечебная трава")
			return pt <= 0.0 and _t > 0.5
		&"shelter", &"wall":
			var bp: Node3D = null
			for b in _placed:
				if is_instance_valid(b):
					bp = b
			if bp:
				ui.set_target((bp as Node3D).global_position, "Чертёж")
				var bpb := bp as Blueprint
				ui.set_progress("Деталей: %d / %d" % [bpb.filled_count(), bpb.parts.size()])
			else:
				if id == &"shelter":
					ui.set_target(Game.teams[0].flag_pos, "Строй здесь, у флага")
				else:
					ui.set_target(null)
				ui.set_progress("Чертёж ещё не поставлен")
			return _flag
		&"flag":
			var fp: Vector3 = Game.teams[0].flag_pos
			ui.set_target(fp, "Флаг Красных")
			var dist := p.global_position.distance_to(fp)
			ui.set_progress("До флага: %d м" % int(dist))
			return dist < 5.0
		&"respawn":
			ui.set_target(null)
			if not alive:
				_died = true
				ui.set_progress("Возрождение через %d с" % int(ceilf(float(p.get(&"respawn_left")))))
			elif not _died:
				ui.set_progress("…")
			return _died and alive and _flag
		&"bridge":
			var sock: Variant = bridge_socket()
			ui.set_target(sock if sock != null else (bridge_info.get("start", null)), "Конец моста")
			ui.set_progress("Последняя секция: %s" % ("строится" if not _placed.is_empty() else "не поставлена"))
			return _flag
		&"cross":
			ui.set_target(landing, neighbour.get("name", "Остров"))
			var here: Dictionary = world.call(&"island_at", p.global_position.x, p.global_position.z)
			var on_land := bool(world.call(&"is_land", p.global_position.x, p.global_position.z))
			ui.set_progress("До берега: %d м" % int(p.global_position.distance_to(landing)))
			var at_landing := p.global_position.distance_to(landing) < 5.0 and not bool(p.get(&"swimming"))
			return alive and (at_landing or (on_land and not here.is_empty() and here.id == neighbour.get("id", -99)))
		&"dummy":
			var n := 0
			if dummy and is_instance_valid(dummy):
				n = (dummy.get(&"hits") as Array).size()
				ui.set_target(dummy.global_position + Vector3.UP * 0.6, "Чучело")
			ui.set_progress("Попаданий: %d / 3" % mini(n, 3))
			return n >= 3
		&"bot":
			if bot and is_instance_valid(bot):
				ui.set_target(bot.global_position + Vector3.UP * 0.8, "Синий")
				var hp := float(bot.get(&"health")) if bot.get(&"health") != null else 0.0
				ui.set_progress("Здоровье противника: %d" % int(hp))
			return _flag
		&"molotov":
			if enemy_raft and is_instance_valid(enemy_raft):
				ui.set_target(enemy_raft.global_position, "Мост Синих" if BuildDefs.kind_of(StringName(enemy_raft.get(&"def_id"))) == &"raft" else "Постройка Синих")
				if bool(enemy_raft.get(&"burning")):
					_acc += delta
			ui.set_progress("Мост горит!" if _acc > 0.0 else "Мост цел")
			return _flag or _acc >= 6.0 or (enemy_raft != null and not is_instance_valid(enemy_raft))
		&"enemy_flag":
			ui.set_target(enemy_flag_pos + Vector3.UP * 1.5, "Флаг Синих")
			var t1 = Game.teams[1] if Game.teams.size() > 1 else null
			ui.set_progress("Прочность флага: %d / %d" % [int(t1.flag_hp) if t1 else 0, int(Game.FLAG_MAX_HP)])
			return t1 == null or not t1.flag_alive
	return false

func _progress_craft() -> void:
	var rope := _cnt_of(&"rope") > 0 or _cnt_of(&"axe_crude") > 0
	ui.set_progress("Верёвка: %s   ·   Каменный топор: %s" % ["есть" if rope else "нет", "есть" if _cnt_of(&"axe_crude") > 0 else "нет"])

func _nearest_log() -> Variant:
	var best: Variant = null
	var bd := 40.0
	for n in get_tree().get_nodes_in_group(&"log"):
		var n3 := n as Node3D
		if n3 and n3.is_visible_in_tree():
			var d := n3.global_position.distance_to(player.global_position)
			if d < bd:
				bd = d
				best = n3.global_position
	return best

func _timed() -> void:
	match step_id():
		&"respawn":
			if bool(player.get(&"alive")) and player.has_method(&"apply_damage"):
				player.call(&"apply_damage", 9999.0, null, &"tutorial")

# ================================================================== события

func _on_blueprint_placed(node: Node, def_id: StringName) -> void:
	if _prebuilding or node == null or int(node.get(&"team")) != 0:
		return
	match step_id():
		&"shelter":
			if def_id == &"shelter":
				_placed.append(node)
		&"wall":
			if String(def_id).begins_with("wall"):
				_placed.append(node)
				_assist.append(node)
		&"bridge":
			if BuildDefs.kind_of(def_id) == &"raft" and not bridge.has(node):
				_placed.append(node)
				_assist.append(node)

func _on_structure_completed(node: Node, def_id: StringName) -> void:
	if _prebuilding or node == null or node.get(&"team") == null or int(node.get(&"team")) != 0:
		return
	match step_id():
		&"shelter":
			if def_id == &"shelter":
				_flag = true
		&"wall":
			if String(def_id).begins_with("wall"):
				_flag = true
		&"bridge":
			if BuildDefs.kind_of(def_id) == &"raft" and not bridge.has(node):
				_flag = true

func _on_structure_destroyed(node: Node, _def_id: StringName, _by: Node) -> void:
	if node != null and node == enemy_raft and step_id() == &"molotov":
		_flag = true

func _on_spawned(ch: Node) -> void:
	if ch == player and step_id() == &"respawn" and _died:
		_flag = true

func _on_died(ch: Node, _killer: Node) -> void:
	if ch != null and ch == bot:
		if step_id() == &"bot":
			_flag = true
		var b := bot
		bot = null
		get_tree().create_timer(4.0).timeout.connect(func() -> void: _remove_bot(b))

func _on_flag_destroyed(_team: int, _by: Node) -> void:
	pass

## Ускоренная стройка: детали чертежа заполняются сами одна за другой.
func _process_assist(delta: float) -> void:
	# шалаш — после первой детали, внесённой игроком
	if step_id() == &"shelter":
		for b in _placed:
			if is_instance_valid(b) and not _assist.has(b) and (b as Blueprint).filled_count() >= 1:
				_assist.append(b)
	_assist_t += delta
	if _assist_t < 0.3:
		return
	_assist_t = 0.0
	for b in _assist.duplicate():
		var bp := b as Blueprint
		if bp == null or not is_instance_valid(bp) or bp.is_complete():
			_assist.erase(b)
			continue
		for i in bp.parts.size():
			if not bp.filled[i]:
				bp.fill_part(i, player)
				break

# ================================================================== противники

func _spawn_dummy() -> void:
	if dummy and is_instance_valid(dummy):
		return
	var base := player.global_position
	var fwd := _fwd()
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var pv: Variant = _land_near(base + fwd * 9.0, 0.0, 8.0, 0.3)
	if not (pv is Vector3):
		pv = _land_near(base, 5.0, 20.0, 0.3)
	var p: Vector3 = pv if pv is Vector3 else _ground(base + fwd * 6.0)
	dummy = TrainingDummy.new()
	dummy.name = "TutorialDummy"
	get_parent().add_child(dummy)
	dummy.global_position = p
	dummy.look_at(Vector3(base.x, p.y, base.z), Vector3.UP)

func _spawn_bot() -> void:
	if bot and is_instance_valid(bot):
		return
	var bots := Bots.instance()
	if bots == null:
		_flag = true
		return
	var fwd := _fwd()
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var pv: Variant = _land_near(player.global_position + fwd * 14.0, 0.0, 8.0, 0.3)
	if not (pv is Vector3):
		pv = _land_near(player.global_position, 9.0, 30.0, 0.3)
	var p: Vector3 = pv if pv is Vector3 else enemy_flag_pos
	bot = bots.spawn_bot(1, &"easy", p)
	if bot == null:
		_flag = true
		return
	bot.set(&"display_name", "Синий новобранец")

func _remove_bot(b: Node3D) -> void:
	if b == null or not is_instance_valid(b):
		return
	var bots := Bots.instance()
	if bots:
		bots.bots.erase(b)
		var ta: Variant = b.get(&"team_ai")
		if ta is Object and (ta as Object).get(&"bots") is Array:
			((ta as Object).get(&"bots") as Array).erase(b)
	if Game.teams.size() > 1:
		Game.teams[1].members.erase(b)
	b.queue_free()

# ================================================================== финал

func _finish() -> void:
	done = true
	ui.set_target(null)
	TutorialLauncher.mark_done()
	if player:
		player.set(&"input_enabled", false)
		if player.has_method(&"capture_mouse"):
			player.call(&"capture_mouse", false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var mins := int(Game.match_time / 60.0)
	ui.show_done("Время обучения: %d мин" % mins)
	finished.emit()
	print("[tutorial] завершено")
