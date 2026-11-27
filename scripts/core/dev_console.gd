extends CanvasLayer
## Консоль разработчика (автозагрузка DevConsole). Клавиша ` / Ё.
## Работает всегда на «Полигоне», в матчах — если в Настройках включён «Режим разработчика».
## История (↑/↓), автодополнение (Tab), help. Команды (RU и EN):
##   spawn/призвать <вид> [n] [радиус]   — у прицела (вид — id или название, можно начало слова)
##   spawn_all/все_виды [категория]      — по одному каждого вида в ряд
##   list/список [категория]             — animals/birds/sea/plants/all (живьём из реестров)
##   kill/убить <вид|all> [радиус]       — убить (по умолчанию радиус 60 м, 0 — везде)
##   clear/очистить [радиус]             — убрать всё созданное консолью
##   tame/приручить <вид> [радиус]       count/счёт
##   tp/тп <x z>|<зона>   time/время [ч]   weather/погода [ясно|облачно|дождь|гроза|туман]
##   god/бог   fly/полёт   give/дать <предмет> [n]   fps   help/помощь   cls

const MAX_LOG := 400

var _root: Control
var _log: RichTextLabel
var _edit: LineEdit
var _head: Label
var _hint: Label
var _open := false
var _history: PackedStringArray = []
var _hist_i := -1
var _head_t := 0.0
var _fps_label: Label
var _tab_base := ""
var _tab_opts: PackedStringArray = []
var _tab_i := -1

const CMDS := {
	"spawn": ["spawn", "призвать", "создать", "спавн"],
	"spawn_all": ["spawn_all", "все_виды", "всех"],
	"list": ["list", "список", "виды", "ls"],
	"kill": ["kill", "убить"],
	"clear": ["clear", "очистить", "убрать"],
	"tame": ["tame", "приручить"],
	"count": ["count", "счёт", "счет", "сколько"],
	"tp": ["tp", "тп", "teleport", "телепорт"],
	"time": ["time", "время"],
	"weather": ["weather", "погода"],
	"god": ["god", "бог"],
	"fly": ["fly", "полёт", "полет", "лететь"],
	"give": ["give", "дать"],
	"fps": ["fps", "фпс"],
	"replay": ["replay", "реплей", "повтор"],
	"event": ["event", "событие", "ивент"],
	"help": ["help", "помощь", "?", "справка"],
	"cls": ["cls", "стереть"],
}
const HELP := {
	"spawn": "spawn <вид> [кол-во] [радиус] — призвать у прицела (до 500 за раз). Пример: spawn краб 100",
	"spawn_all": "spawn_all [категория] — по одному каждого вида в ряд перед вами",
	"list": "list [animals|birds|sea|plants|all] — какие виды есть (берётся из реестров игры)",
	"kill": "kill <вид|all> [радиус] — убить (радиус по умолч. 60 м; 0 — по всему миру)",
	"clear": "clear [радиус] — убрать всё, что создано консолью (0/пусто — всё)",
	"tame": "tame <вид> [радиус] — приручить ближайших (если вид приручается)",
	"count": "count — сколько живых существ (всего и созданных консолью, по видам)",
	"tp": "tp <x> <z> | tp <раздел> — телепорт (разделы — как в меню полигона: животные, птицы, море…)",
	"time": "time [часы] — время суток (без аргумента — показать)",
	"weather": "weather [ясно|облачно|дождь|гроза|туман] — погода",
	"god": "god — бессмертие вкл/выкл",
	"fly": "fly — полёт сквозь стены вкл/выкл",
	"give": "give <предмет> [n] — выдать предмет (id или название)",
	"fps": "fps — счётчик кадров вкл/выкл",
	"event": "event <migration|red_crabs|tsunami|bounty|poison_spring|drift_crate|viewer_task|calm> | event list | event stop — события сезона",
	"replay": "replay [сек] — реплей последних секунд (до 60) в максимальной графике (только на полигоне)",
	"help": "help [команда] — справка",
	"cls": "cls — очистить журнал",
}
const WEATHER_RU := {"ясно": &"clear", "солнце": &"clear", "облачно": &"cloudy", "тучи": &"cloudy",
	"дождь": &"rain", "гроза": &"storm", "шторм": &"storm", "туман": &"fog"}

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.visible = false

func _build() -> void:
	_root = PanelContainer.new()
	_root.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_root.offset_bottom = 380
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.08, 0.88)
	sb.border_color = Color(0.3, 0.75, 0.7, 0.8)
	sb.border_width_bottom = 2
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	_root.add_theme_stylebox_override(&"panel", sb)
	add_child(_root)
	var v := VBoxContainer.new()
	_root.add_child(v)
	_head = Label.new()
	_head.add_theme_color_override(&"font_color", Color(0.55, 0.95, 0.85))
	v.add_child(_head)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.selection_enabled = true
	_log.add_theme_font_size_override(&"normal_font_size", 15)
	v.add_child(_log)
	_hint = Label.new()
	_hint.add_theme_color_override(&"font_color", Color(0.6, 0.65, 0.7))
	_hint.add_theme_font_size_override(&"font_size", 13)
	_hint.clip_text = true
	v.add_child(_hint)
	_edit = LineEdit.new()
	_edit.placeholder_text = "команда… (help — справка, Tab — дополнить, ↑/↓ — история)"
	_edit.add_theme_font_size_override(&"font_size", 17)
	_edit.text_submitted.connect(_on_submit)
	_edit.text_changed.connect(_on_changed)
	_edit.gui_input.connect(_on_edit_input)
	v.add_child(_edit)
	_fps_label = Label.new()
	_fps_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_fps_label.position = Vector2(-140, 6)
	_fps_label.visible = false
	add_child(_fps_label)
	println("[color=#8fd]Консоль разработчика.[/color] help — список команд. Пример: [b]spawn краб 100[/b]")

# ============================== доступ и переключение ==============================

func _sandbox() -> Node:
	var cs := get_tree().current_scene
	if cs and cs.is_in_group(&"polygon"):
		return cs
	var pg := get_tree().get_first_node_in_group(&"polygon")
	if pg:
		return pg
	return null

func enabled() -> bool:
	return _sandbox() != null or Settings.dev_mode

func _player() -> Node:
	return get_tree().get_first_node_in_group(&"player")

func is_open() -> bool:
	return _open

func _input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo:
		return
	var k := e as InputEventKey
	if k.physical_keycode == KEY_QUOTELEFT:
		if _open:
			close()
		elif enabled():
			open()
		else:
			return
		get_viewport().set_input_as_handled()
	elif _open and k.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

func open() -> void:
	_open = true
	_root.visible = true
	var p := _player()
	if p and p.has_method(&"set_ui_open"):
		p.call(&"set_ui_open", true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_update_head()
	_edit.call_deferred(&"grab_focus")
	# символ ` / ё от нажатия не должен попасть в строку
	_edit.call_deferred(&"set", &"text", _edit.text.replace("`", "").replace("ё", "").replace("Ё", ""))

func close() -> void:
	_open = false
	_root.visible = false
	_edit.release_focus()
	var p := _player()
	if p and p.has_method(&"set_ui_open"):
		p.call(&"set_ui_open", false)

func _process(dt: float) -> void:
	if _fps_label.visible:
		_fps_label.text = "FPS %d  (%.1f мс)" % [Engine.get_frames_per_second(), 1000.0 / maxf(Engine.get_frames_per_second(), 1.0)]
	if not _open:
		return
	_head_t -= dt
	if _head_t <= 0.0:
		_head_t = 0.3
		_update_head()

func _update_head() -> void:
	var fa := Fauna.instance() if is_inside_tree() else null
	var total := fa.living_count() if fa else 0
	var cs := get_tree().get_first_node_in_group(&"creature_spawner") as CreatureSpawner
	var mine := cs.live_count() if cs else 0
	var q := cs.queued() if cs else 0
	var sea_n := 0
	var sea := get_tree().get_first_node_in_group(&"sea") as Sea
	if sea:
		sea_n = sea.sharks.size()
	_head.text = "Консоль ` / Ё   |   живых животных: %d   акул: %d   создано консолью: %d%s   |   видов в реестрах: %d" % [
		total, sea_n, mine, ("  (в очереди %d)" % q) if q > 0 else "", CreatureSpawner.all_species().size()]

# ============================== журнал ==============================

func println(s: String) -> void:
	_log.append_text(s + "\n")
	if _log.get_paragraph_count() > MAX_LOG:
		var txt := _log.get_parsed_text()
		_log.clear()
		_log.append_text(txt.substr(txt.length() / 2))

func _err(s: String) -> void:
	println("[color=#f88]" + s + "[/color]")

# ============================== ввод ==============================

func _on_submit(t: String) -> void:
	var line := t.strip_edges()
	_edit.text = ""
	_tab_i = -1
	if line == "":
		return
	if _history.is_empty() or _history[_history.size() - 1] != line:
		_history.append(line)
	_hist_i = -1
	println("[color=#9ab]> " + line.replace("[", "[lb]") + "[/color]")
	execute(line)
	_update_head()

func _on_changed(t: String) -> void:
	if t.contains("`"):
		_edit.text = t.replace("`", "")
		_edit.caret_column = _edit.text.length()
	_tab_i = -1
	_show_hint(_edit.text)

func _on_edit_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed:
		return
	var k := e as InputEventKey
	match k.keycode:
		KEY_UP:
			if _history.is_empty():
				return
			_hist_i = _history.size() - 1 if _hist_i < 0 else maxi(_hist_i - 1, 0)
			_edit.text = _history[_hist_i]
			_edit.caret_column = _edit.text.length()
			_edit.accept_event()
		KEY_DOWN:
			if _hist_i < 0:
				return
			_hist_i += 1
			if _hist_i >= _history.size():
				_hist_i = -1
				_edit.text = ""
			else:
				_edit.text = _history[_hist_i]
			_edit.caret_column = _edit.text.length()
			_edit.accept_event()
		KEY_TAB:
			_complete()
			_edit.accept_event()

## Варианты дополнения для строки (последнее слово).
func completions(line: String) -> PackedStringArray:
	var parts := line.split(" ", true)
	var out: PackedStringArray = []
	if parts.size() <= 1:
		var w := parts[0].to_lower() if parts.size() > 0 else ""
		for c: String in CMDS:
			for a: String in CMDS[c]:
				if a.begins_with(w) and not out.has(a):
					out.append(a)
		return out
	var cmd := _cmd_of(parts[0])
	var w2 := parts[parts.size() - 1].to_lower().replace("ё", "е")
	match cmd:
		"spawn", "kill", "tame":
			if parts.size() == 2:
				if cmd == "kill" and "all".begins_with(w2):
					out.append("all")
				for d in CreatureSpawner.all_species():
					if String(d.id).to_lower().begins_with(w2):
						out.append(String(d.id))
				for d in CreatureSpawner.all_species():
					var nm := String(d.name).to_lower().replace(" ", "_")
					if nm.replace("ё", "е").begins_with(w2) and not out.has(String(d.id)):
						out.append(nm)
		"list", "spawn_all":
			for c: String in ["animals", "birds", "sea", "plants", "all", "животные", "птицы", "море", "растения"]:
				if c.begins_with(w2):
					out.append(c)
		"event":
			for c: String in ["migration", "red_crabs", "tsunami", "bounty", "poison_spring", "drift_crate", "viewer_task", "calm", "list", "stop"]:
				if c.begins_with(w2):
					out.append(c)
		"weather":
			for c: String in ["ясно", "облачно", "дождь", "гроза", "туман", "clear", "cloudy", "rain", "storm", "fog"]:
				if c.begins_with(w2):
					out.append(c)
		"tp":
			if _sandbox() is Polygon:
				for s0: Dictionary in PolygonLayout.get_layout().sections:
					var nm := String(s0.name).to_lower()
					if nm.begins_with(w2):
						out.append(nm)
		"help":
			for c: String in CMDS:
				if c.begins_with(w2):
					out.append(c)
		"give":
			for id: Variant in Items.items:
				if String(id).begins_with(w2):
					out.append(String(id))
	return out

func _complete() -> void:
	var t := _edit.text
	if _tab_i < 0:
		_tab_base = t
		_tab_opts = completions(t)
		if _tab_opts.is_empty():
			return
	_tab_i = (_tab_i + 1) % _tab_opts.size()
	var parts := _tab_base.split(" ", true)
	parts[parts.size() - 1] = _tab_opts[_tab_i]
	_edit.text = " ".join(parts) + (" " if _tab_opts.size() == 1 else "")
	_edit.caret_column = _edit.text.length()
	var shown := _tab_opts.slice(0, 14)
	_hint.text = "  ".join(shown) + ("  …ещё %d" % (_tab_opts.size() - shown.size()) if _tab_opts.size() > shown.size() else "")
	if _tab_opts.size() == 1:
		_tab_i = -1

func _show_hint(t: String) -> void:
	var parts := t.strip_edges().split(" ", false)
	if parts.is_empty():
		_hint.text = ""
		return
	var c := _cmd_of(parts[0])
	_hint.text = String(HELP.get(c, "")) if c != "" else "  ".join(completions(t).slice(0, 12))

func _cmd_of(w: String) -> String:
	var s := w.to_lower()
	for c: String in CMDS:
		if s in CMDS[c]:
			return c
	return ""

# ============================== выполнение ==============================

## Выполнить строку команды. Возвращает текст результата (его же пишет в журнал).
func execute(line: String) -> String:
	var parts := line.strip_edges().split(" ", false)
	if parts.is_empty():
		return ""
	var cmd := _cmd_of(parts[0])
	var args := parts.slice(1)
	var res := ""
	match cmd:
		"spawn": res = _c_spawn(args)
		"spawn_all": res = _c_spawn_all(args)
		"list": res = _c_list(args)
		"kill": res = _c_kill(args)
		"clear": res = _c_clear(args)
		"tame": res = _c_tame(args)
		"count": res = _c_count()
		"tp": res = _c_tp(args)
		"time": res = _c_time(args)
		"weather": res = _c_weather(args)
		"god": res = _c_god()
		"fly": res = _c_fly()
		"give": res = _c_give(args)
		"fps":
			_fps_label.visible = not _fps_label.visible
			res = "Счётчик FPS: " + ("вкл" if _fps_label.visible else "выкл")
		"replay":
			var secs := float(args[0]) if not args.is_empty() and args[0].is_valid_float() else 30.0
			close()
			var path := ReplayRecorder.request(get_tree(), secs)
			res = ("Реплей: рендер %d с в максимальной графике…" % int(secs)) if path != "" else "!Реплей — только на полигоне (и после нескольких секунд игры)"
		"event": res = _c_event(args)
		"help": res = _c_help(args)
		"cls":
			_log.clear()
			return ""
		_:
			res = "!Неизвестная команда «%s». help — список." % parts[0]
	if res.begins_with("!"):
		_err(res.substr(1))
	elif res != "":
		println(res)
	return res

func _spawner() -> CreatureSpawner:
	return CreatureSpawner.instance()

## Точка у прицела (как в меню полигона) — луч из камеры, иначе 8 м перед игроком.
func aim_point() -> Vector3:
	var sb := _sandbox()
	if sb and sb.get(&"panel") and sb.get(&"panel").has_method(&"aim_point"):
		return sb.get(&"panel").call(&"aim_point")
	var p := _player() as Node3D
	if p == null:
		return Vector3.ZERO
	var cam := p.get(&"camera") as Camera3D
	if cam:
		var from := cam.global_position
		var dir := -cam.global_transform.basis.z
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * 250.0)
		q.exclude = [p.get_rid()] if p is CollisionObject3D else []
		var hit := p.get_world_3d().direct_space_state.intersect_ray(q)
		if hit:
			return hit.position
		var w := get_tree().get_first_node_in_group(&"world")
		if w:
			var wl := float(w.call(&"water_level"))
			for i in 200:
				var pt := from + dir * float(i + 1)
				if pt.y <= maxf(float(w.call(&"height_at", pt.x, pt.z)), wl):
					return pt
	return p.global_position - p.global_transform.basis.z * 8.0

func _pos() -> Vector3:
	var p := _player() as Node3D
	return p.global_position if p else Vector3.ZERO

func _num(args: PackedStringArray, i: int, def: float) -> float:
	return float(args[i]) if args.size() > i and args[i].is_valid_float() else def

## Разобрать «<вид из нескольких слов> [n] [r]»: числа — с конца.
func _species_args(args: PackedStringArray) -> Array:
	var words := args.duplicate()
	var nums: Array[float] = []
	while not words.is_empty() and words[words.size() - 1].is_valid_float() and nums.size() < 2:
		nums.push_front(float(words[words.size() - 1]))
		words.remove_at(words.size() - 1)
	return [" ".join(words).replace("_", " "), nums]

func _c_spawn(args: PackedStringArray) -> String:
	if args.is_empty():
		return "!" + HELP.spawn
	var pa := _species_args(args)
	var q: String = pa[0]
	var nums: Array = pa[1]
	var info := CreatureSpawner.find(q)
	if info.is_empty():
		info = CreatureSpawner.find(q.replace(" ", "_"))
	if info.is_empty():
		return "!Нет вида «%s». list — список видов." % q
	var n := int(nums[0]) if nums.size() > 0 else 1
	var r := float(nums[1]) if nums.size() > 1 else -1.0
	var asked := n
	var got := _spawner().request(String(info.id), aim_point(), n, r)
	if got <= 0:
		return "!Лимит: уже %d созданных (максимум %d). clear — убрать." % [_spawner().live_count(), CreatureSpawner.MAX_TOTAL]
	var note := "" if got == asked else "  (лимит: %d из %d)" % [got, asked]
	return "Призываю: %s ×%d  [%s, %s]%s" % [info.name, got, info.id, CreatureSpawner.CATS.get(info.cat, info.cat), note]

func _c_spawn_all(args: PackedStringArray) -> String:
	var cat := CreatureSpawner.cat_of(args[0]) if args.size() > 0 else "all"
	if cat == "":
		return "!Категории: animals, birds, sea, plants, all"
	var list := CreatureSpawner.all_species(cat)
	var p := _player() as Node3D
	var fwd := Vector3.FORWARD
	if p:
		var cam := p.get(&"camera") as Camera3D
		fwd = -(cam.global_transform.basis.z if cam else p.global_transform.basis.z)
	fwd.y = 0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var side := fwd.cross(Vector3.UP)
	var base := _pos() + fwd * 10.0
	var step := 3.5
	var k := 0
	for d in list:
		var off := (float(k) - float(list.size() - 1) * 0.5) * step
		if _spawner().request(String(d.id), base + side * off, 1, 0.5) > 0:
			k += 1
	return "Ряд из %d видов (%s) перед вами." % [k, cat]

func _c_list(args: PackedStringArray) -> String:
	var cat := CreatureSpawner.cat_of(args[0]) if args.size() > 0 else "all"
	if cat == "":
		return "!Категории: animals, birds, sea, plants, all"
	var lines: PackedStringArray = []
	var total := 0
	for c: String in CreatureSpawner.CATS:
		if cat != "all" and c != cat:
			continue
		var l := CreatureSpawner.all_species(c)
		total += l.size()
		var items: PackedStringArray = []
		for d in l:
			items.append("%s [color=#789](%s)[/color]" % [d.name, d.id])
		lines.append("[b]%s (%d):[/b] %s" % [CreatureSpawner.CATS[c], l.size(), ", ".join(items)])
	return "\n".join(lines) + "\nВсего видов: %d" % total

func _c_kill(args: PackedStringArray) -> String:
	if args.is_empty():
		return "!" + HELP.kill
	var pa := _species_args(args)
	var q: String = pa[0]
	var nums: Array = pa[1]
	var r := float(nums[0]) if nums.size() > 0 else 60.0
	var id := ""
	if q.to_lower() not in ["all", "все", "всех", "всё"]:
		var info := CreatureSpawner.find(q)
		if info.is_empty():
			return "!Нет вида «%s»." % q
		id = String(info.id)
	var k := _spawner().kill(id, _pos(), r)
	return "Убито: %d%s" % [k, "" if r > 0 else " (по всему миру)"]

func _c_clear(args: PackedStringArray) -> String:
	var r := _num(args, 0, 0.0)
	var k := _spawner().clear(_pos(), r)
	return "Убрано созданных консолью: %d" % k

func _c_tame(args: PackedStringArray) -> String:
	if args.is_empty():
		return "!" + HELP.tame
	var pa := _species_args(args)
	var info := CreatureSpawner.find(pa[0])
	if info.is_empty():
		return "!Нет вида «%s»." % pa[0]
	var nums: Array = pa[1]
	var k := _spawner().tame(String(info.id), _player(), _pos(), float(nums[0]) if nums.size() > 0 else 40.0)
	if k == 0 and not bool(Animal.SPECIES.get(StringName(info.id), {}).get("tame", false)):
		return "!%s не приручается." % info.name
	return "Приручено: %s ×%d" % [info.name, k]

func _c_count() -> String:
	var fa := Fauna.instance()
	var cs := _spawner()
	var cen := cs.census()
	var parts: PackedStringArray = []
	for id: String in cen:
		var info := CreatureSpawner.find(id)
		parts.append("%s %d" % [info.get("name", id), cen[id]])
	return "Живых животных в мире: %d. Создано консолью: %d%s" % [
		fa.living_count() if fa else 0, cs.live_count(), (" — " + ", ".join(parts)) if not parts.is_empty() else ""]

func _c_tp(args: PackedStringArray) -> String:
	if args.size() >= 2 and args[0].is_valid_float() and args[1].is_valid_float():
		var x := float(args[0])
		var z := float(args[1])
		var w := get_tree().get_first_node_in_group(&"world")
		var y := float(w.call(&"height_at", x, z)) if w else 0.0
		if w:
			y = maxf(y, float(w.call(&"water_level")))
		_teleport(Vector3(x, y + 1.2, z))
		return "Телепорт: %.0f, %.0f" % [x, z]
	var sb0 := _sandbox()
	if sb0 is Polygon:
		var pg := sb0 as Polygon
		if args.is_empty():
			return "Разделы: центр, " + ", ".join(PackedStringArray(PolygonLayout.get_layout().sections.map(func(s0: Dictionary) -> String: return String(s0.name).to_lower())))
		var q0 := " ".join(args).to_lower()
		if "центр".begins_with(q0) or q0 == "hub":
			pg.goto_hub()
			return "Телепорт: центр"
		for s0: Dictionary in PolygonLayout.get_layout().sections:
			if String(s0.name).to_lower().begins_with(q0) or String(s0.id).begins_with(q0):
				pg.goto_section(s0.id)
				return "Телепорт: " + String(s0.name)
		return "!Нет раздела «%s». tp — список." % q0
	return "!tp <x> <z> (разделы — только в музее полигона)"

func _teleport(pos: Vector3, look: Variant = null) -> void:
	var sb := _sandbox()
	if sb and sb.get(&"cheats"):
		sb.get(&"cheats").call(&"teleport", pos, look)
		return
	var p := _player() as Node3D
	if p:
		p.global_position = pos
		if p is CharacterBody3D:
			(p as CharacterBody3D).velocity = Vector3.ZERO

func _c_time(args: PackedStringArray) -> String:
	var w := get_tree().get_first_node_in_group(&"world")
	if w == null:
		return "!Нет мира."
	if args.is_empty() or not args[0].replace(":", ".").is_valid_float():
		var h := float(w.call(&"time_of_day"))
		return "Время: %02d:%02d" % [int(h), int(fmod(h, 1.0) * 60.0)]
	var t := args[0].split(":")
	var hh := fposmod(float(t[0]) + (float(t[1]) / 60.0 if t.size() > 1 else 0.0), 24.0)
	var sb := _sandbox()
	if sb and sb.get(&"cheats"):
		sb.get(&"cheats").call(&"set_time", hh)
	else:
		w.call(&"set_time_of_day", hh)
	return "Время: %02d:%02d" % [int(hh), int(fmod(hh, 1.0) * 60.0)]

func _c_weather(args: PackedStringArray) -> String:
	var w := get_tree().get_first_node_in_group(&"world")
	if w == null:
		return "!Нет мира."
	if args.is_empty():
		return "Погода: ясно | облачно | дождь | гроза | туман"
	var a := args[0].to_lower()
	var wv: StringName = WEATHER_RU.get(a, StringName(a))
	if wv not in [&"clear", &"cloudy", &"rain", &"storm", &"fog"]:
		return "!Нет такой погоды. ясно | облачно | дождь | гроза | туман"
	var sb := _sandbox()
	if sb and sb.get(&"cheats"):
		sb.get(&"cheats").call(&"set_weather", wv)
	else:
		w.call(&"set_weather", wv, false)
	return "Погода: " + String(SandboxCheats.WEATHER_NAMES.get(wv, wv))

const EVENT_RU := {"миграция": &"migration", "манты": &"migration", "крабы": &"red_crabs", "цунами": &"tsunami",
	"награда": &"bounty", "родник": &"poison_spring", "яд": &"poison_spring", "ящик": &"drift_crate",
	"задание": &"viewer_task", "штиль": &"calm"}

func _c_event(args: PackedStringArray) -> String:
	var se := SeasonEvents.ensure()
	if se == null:
		return "!Нет мира."
	if args.is_empty() or args[0] == "list" or args[0] == "список":
		var act := se.active_ids().map(func(x: StringName) -> String: return String(SeasonEvents.NAMES.get(x, x)))
		return "События: %s. Активны: %s" % [", ".join(SeasonEvents.IDS.map(func(x: StringName) -> String: return String(x))),
			", ".join(act) if not act.is_empty() else "нет"]
	var a := args[0].to_lower()
	if a == "stop" or a == "стоп":
		se.stop_all()
		return "Все события остановлены"
	var id: StringName = EVENT_RU.get(a, StringName(a))
	if not SeasonEvents.SCRIPTS.has(id):
		return "!Нет такого события. event list — список"
	var opts := {}
	if args.size() > 1 and id == &"viewer_task":
		opts["task_id"] = args[1]
	var e := se.start(id, opts)
	return ("Событие: " + String(SeasonEvents.NAMES[id])) if e else "!Событие «%s» не запустилось (нет места/условий)" % String(SeasonEvents.NAMES[id])

func _c_god() -> String:
	var sb := _sandbox()
	if sb and sb.get(&"cheats"):
		var ch: Node = sb.get(&"cheats")
		ch.call(&"set_god", not bool(ch.get(&"god")))
		return "Бессмертие: " + ("вкл" if ch.get(&"god") else "выкл")
	var p := _player()
	if p == null:
		return "!Нет игрока."
	var on := not bool(p.get_meta(&"dev_god", false))
	p.set_meta(&"dev_god", on)
	if on:
		_god_tick.call_deferred()
	return "Бессмертие: " + ("вкл" if on else "выкл")

func _god_tick() -> void:
	var p := _player()
	while p and is_instance_valid(p) and bool(p.get_meta(&"dev_god", false)):
		if p.get(&"max_health") != null:
			p.set(&"health", p.get(&"max_health"))
		await get_tree().create_timer(0.2, true).timeout

func _c_fly() -> String:
	var sb := _sandbox()
	if sb and sb.get(&"cheats"):
		var ch: Node = sb.get(&"cheats")
		ch.call(&"set_fly", not bool(ch.get(&"fly")))
		return "Полёт: " + ("вкл (V — переключать)" if ch.get(&"fly") else "выкл")
	return "!Полёт — только на полигоне."

func _c_give(args: PackedStringArray) -> String:
	if args.is_empty():
		return "!" + HELP.give
	var n := 1
	var words := args.duplicate()
	if words.size() > 1 and words[words.size() - 1].is_valid_int():
		n = clampi(int(words[words.size() - 1]), 1, 999)
		words.remove_at(words.size() - 1)
	var q := " ".join(words).to_lower()
	var id: StringName = &""
	if Items.items.has(StringName(q)):
		id = StringName(q)
	else:
		for k: Variant in Items.items:
			if String(k).begins_with(q) or Items.item_name(StringName(k)).to_lower().begins_with(q):
				id = StringName(k)
				break
	if id == &"":
		return "!Нет предмета «%s» (Tab — дополнить)." % q
	var p := _player()
	if p == null:
		return "!Нет игрока."
	Flora.give(p, id, n)
	return "Выдано: %s ×%d" % [Items.item_name(id), n]

func _c_help(args: PackedStringArray) -> String:
	if args.size() > 0:
		var c := _cmd_of(args[0])
		return String(HELP.get(c, "!Нет команды «%s»." % args[0])) + ("" if c == "" else "   (синонимы: %s)" % ", ".join(CMDS[c]))
	var lines: PackedStringArray = []
	for c: String in HELP:
		lines.append("  " + String(HELP[c]))
	return "Команды (есть русские синонимы, help <команда>):\n" + "\n".join(lines)
