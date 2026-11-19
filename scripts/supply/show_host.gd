class_name ShowHost
extends CanvasLayer
## Лор шоу: «Ведущий» (docs/LORE.md) — вежливый, ироничный голос из громкоговорителей.
## Озвучки нет: реплика — субтитр внизу по центру («ВЕДУЩИЙ» + текст) с коротким
## радиощелчком, держится ~5 с, реплики идут очередью и не перебивают друг друга.
## Поводы: начало матча, первая кровь, сброс посылки, флаг уничтожен, команда выбыла,
## конец матча, и изредка «рейтинги» (кто дольше всех без потерь).
##
## API: ShowHost.instance(), say(text, prio=false), current (текст на экране), said (история)

const SHOW_SEC := 5.0
const GAP_SEC := 0.6
const RATING_EVERY := 600.0

const LINES := {
	"start": ["Добрый вечер, дорогие зрители. Четыре флага, четыре команды, один выход. Эфир начат.",
		"Мы снова в эфире. Напоминаю участникам: пока флаг стоит — контракт продлевается.",
		"Камеры включены, акулы накормлены. Начинаем."],
	"first_blood": ["Первая кровь. Ставки на этот раунд закрыты — спасибо, %s.",
		"%s открывает счёт. Зрители оживились.",
		"А вот и первая потеря. %s — запомните это имя."],
	"drop": ["Наши спонсоры щедры сегодня: посылка уже в воздухе. Смотрите на дым.",
		"Внимание, сброс. Кто первый — того и подарок. Спонсоры любят зрелище.",
		"Борт над архипелагом. Цвет дыма скажет, насколько вам повезло."],
	"flag": ["Флаг %s уничтожен. С этой минуты — без возвращений. Как трогательно.",
		"%s остаются без флага. Контракт больше не продлевается.",
		"Минус флаг: %s. Рекомендую им беречь себя."],
	"flag_mine": ["Ваш флаг пал. Дрон-медик к вам больше не прилетит — постарайтесь не умирать."],
	"out": ["Команда %s покидает шоу. Благодарим за участие.",
		"%s выбывают. Их места в рейтинге уже никто не займёт."],
	"win": ["Победители определены: %s. Свобода — ваша. По крайней мере, так написано в контракте.",
		"И последний флаг стоит у команды %s. Поздравляю. Эфир завершён."],
	"draw": ["Ничья. Зрители недовольны. Спонсоры — тоже."],
	"rating": ["Промежуточный рейтинг: у команды %s ни одной потери. Зрители ставят на них.",
		"Рейтинг эфира: лидеры — %s. Остальным стоит постараться."],
}

var current := ""
var said: Array[String] = []
var _queue: Array[String] = []
var _t := 0.0
var _first_blood := false
var _rating_t := 0.0
var _rng := RandomNumberGenerator.new()
var _panel: PanelContainer
var _label: RichTextLabel

static func instance() -> ShowHost:
	var t := Engine.get_main_loop() as SceneTree
	return t.get_first_node_in_group(&"show_host") as ShowHost if t else null

func _ready() -> void:
	name = "ShowHost"
	layer = 5
	add_to_group(&"show_host")
	_rng.randomize()
	_build_ui()
	Events.match_started.connect(_on_match_started)
	Events.match_ended.connect(_on_match_ended)
	Events.flag_destroyed.connect(_on_flag_destroyed)
	Events.team_eliminated.connect(_on_team_eliminated)
	Events.character_died.connect(_on_died)
	var sup := get_parent() as Supply
	if sup:
		sup.drop_announced.connect(_on_drop)

func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.05, 0.62)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	sb.border_width_left = 3
	sb.border_color = Color(0.95, 0.42, 0.08)
	_panel.add_theme_stylebox_override(&"panel", sb)
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -330
	_panel.offset_right = 330
	_panel.offset_top = -190
	_panel.offset_bottom = -130
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(_panel)
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override(&"normal_font_size", 17)
	_label.add_theme_font_size_override(&"bold_font_size", 13)
	_panel.add_child(_label)
	_panel.visible = false

## Реплика ведущего (prio — в начало очереди).
func say(text: String, prio: bool = false) -> void:
	if text == "":
		return
	if prio:
		_queue.push_front(text)
	else:
		_queue.append(text)
	while _queue.size() > 4:
		_queue.pop_back()

func _process(delta: float) -> void:
	var __pt := PerfStats.begin()
	_perf_process(delta)
	PerfStats.end(&"supply", __pt)

func _perf_process(delta: float) -> void:
	if _t > 0.0:
		_t -= delta
		var a := clampf(_t / 0.4, 0.0, 1.0) if _t < 0.4 else clampf((SHOW_SEC + GAP_SEC - _t) / 0.25, 0.0, 1.0)
		_panel.modulate.a = a
		if _t <= GAP_SEC and _panel.visible and current != "":
			current = ""
		if _t <= 0.0:
			_panel.visible = false
	elif not _queue.is_empty():
		_show(_queue.pop_front())
	if Game.is_playing():
		_rating_t += delta
		if _rating_t >= RATING_EVERY:
			_rating_t = 0.0
			_rating()

func _show(text: String) -> void:
	current = text
	said.append(text)
	if said.size() > 40:
		said.pop_front()
	_label.text = "[b][color=#f2a35c]ВЕДУЩИЙ[/color][/b]\n%s" % text
	_panel.visible = true
	_panel.modulate.a = 0.0
	_t = SHOW_SEC + GAP_SEC
	# радиощелчок перед репликой
	var st := CombatFx.stream("dry_click")
	if st:
		var p := AudioStreamPlayer.new()
		p.stream = st
		p.volume_db = -12.0
		p.pitch_scale = 1.6
		add_child(p)
		p.play()
		p.finished.connect(p.queue_free)

func _exit_tree() -> void:
	# играющий звук при выходе остаётся в аудиосервере («resources still in use»)
	var n := 0
	for c in get_children():
		if c is AudioStreamPlayer and (c as AudioStreamPlayer).playing:
			(c as AudioStreamPlayer).stop()
			n += 1
	if n > 0:
		OS.delay_msec(200)

func _pick(kind: String, arg: String = "") -> String:
	var arr: Array = LINES.get(kind, [])
	if arr.is_empty():
		return ""
	var s: String = arr[_rng.randi() % arr.size()]
	return s % arg if s.contains("%s") else s

static func _team_gen(team: int) -> String:
	return Game.TEAM_NAMES_GEN[team % 4] if team >= 0 else "?"

func _player_team() -> int:
	var p := get_tree().get_first_node_in_group(&"player")
	return int(p.get(&"team")) if p and p.get(&"team") != null else -1

func _on_match_started(_cfg: Dictionary) -> void:
	_first_blood = false
	_rating_t = 0.0
	say(_pick("start"), true)

func _on_died(ch: Node, killer: Node) -> void:
	if _first_blood or ch == null or not ch.is_in_group(&"characters") or not Game.is_playing():
		return
	_first_blood = true
	var k := Game.character_of(killer)
	var who := Game.display_name(k) if k and k != ch else Game.display_name(ch)
	say(_pick("first_blood", who))

func _on_drop(_info: Dictionary) -> void:
	say(_pick("drop"))

func _on_flag_destroyed(team: int, _by: Node) -> void:
	if team == _player_team():
		say(_pick("flag_mine"), true)
	else:
		say(_pick("flag", _team_gen(team)), true)

func _on_team_eliminated(team: int) -> void:
	say(_pick("out", _team_gen(team)))

func _on_match_ended(winner: int) -> void:
	if winner < 0:
		say(_pick("draw"), true)
	else:
		say(_pick("win", Game.TEAM_NAMES[winner % 4]), true)

## «Рейтинг»: команда с целым флагом и без выбывших (первая подходящая).
func _rating() -> void:
	for i in Game.teams.size():
		var t: Variant = Game.teams[i]
		if t == null or not bool(t.flag_alive):
			continue
		say(_pick("rating", Game.TEAM_NAMES[i % 4]))
		return
