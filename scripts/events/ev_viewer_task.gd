extends SeasonEvent
## Задание от зрителей: одно задание из списка (events.json → viewer_task.tasks), открыто всем
## участникам (боты тоже могут выполнить — честно). Награда — очки шоу (ShowBus, тег задания).
## Виды: kill_shark_melee · crabs (поймать n) · night_no_fire · kill_species_weapon · spear_fish.

var task: Dictionary = {}
var progress: Dictionary = {}     # instance_id → int
var winner: Node = null
## ночь без костра: кто был жив с начала ночи и ни разу не грелся у огня
var _night_started := false
var _night_ok: Dictionary = {}    # instance_id → Node
var _fire_t := 0.0

func begin() -> void:
	var tasks: Array = cfg.get("tasks", [])
	if tasks.is_empty():
		done = true
		return
	if cfg.has("task_id"):
		for t0: Dictionary in tasks:
			if String(t0.id) == String(cfg.task_id):
				task = t0
	if task.is_empty():
		task = tasks[rng.randi_range(0, tasks.size() - 1)]
	if String(task.kind) == "night_no_fire":
		duration = maxf(duration, 1440.0)
	Events.character_died.connect(_on_died)
	if director and director.has_signal(&"game_fact"):
		director.connect(&"game_fact", _on_fact)
	say(String(task.text) + ". Награда — %d очков." % int(task.get("points", 50)))

func finish() -> void:
	if Events.character_died.is_connected(_on_died):
		Events.character_died.disconnect(_on_died)
	if director and director.is_connected(&"game_fact", _on_fact):
		director.disconnect(&"game_fact", _on_fact)
	super.finish()

static func _weapon_kind(killer: Node) -> String:
	if killer == null or not killer.has_method(&"held_item"):
		return ""
	var wid := StringName(killer.call(&"held_item"))
	var s := String(wid)
	if s.contains("spear") or s.contains("harpoon"):
		return "spear"
	if s.contains("knife") or wid == &"machete":
		return "knife"
	if Combat.is_weapon(wid):
		var tp := StringName(Combat.weapon(wid).get("type", &""))
		if tp == &"melee":
			return "melee"
		if tp == &"gun":
			return "gun"
	return ""

func _on_died(ch: Node, killer: Node) -> void:
	if killer == null or not is_instance_valid(killer) or not killer.is_in_group(&"characters"):
		return
	match String(task.kind):
		"kill_shark_melee":
			if ch.is_in_group(&"sharks") and _weapon_kind(killer) in ["knife", "melee"]:
				_add(killer, 1)
		"crabs":
			var sp: Variant = ch.get(&"species")
			if sp != null and String(sp) in ["crab", "hermit_crab", "coconut_crab"]:
				_add(killer, 1)
		"kill_species_weapon":
			var sp2: Variant = ch.get(&"species")
			if sp2 != null and String(sp2) == String(task.get("species", "")) and _weapon_kind(killer) == String(task.get("weapon", "")):
				_add(killer, 1)

func _on_fact(kind: StringName, by: Node, data: Dictionary) -> void:
	if by == null or not is_instance_valid(by) or not by.is_in_group(&"characters"):
		return
	match String(task.kind):
		"crabs":
			if kind == &"crab_caught":
				_add(by, int(data.get("n", 1)))
		"spear_fish":
			if kind == &"creature_killed" and _weapon_kind(by) == "spear":
				_add(by, 1)
		"kill_shark_melee":
			if kind == &"creature_killed" and _weapon_kind(by) in ["knife", "melee"]:
				var tg: Variant = data.get("target")
				if tg is Node and (tg as Node).is_in_group(&"sharks"):
					_add(by, 1)

func _add(ch: Node, n: int) -> void:
	if winner != null:
		return
	var id := ch.get_instance_id()
	progress[id] = int(progress.get(id, 0)) + n
	if ch.is_in_group(&"player") and int(task.get("n", 1)) > 1:
		Events.toast.emit("Задание зрителей: %d / %d" % [mini(int(progress[id]), int(task.n)), int(task.n)])
	if int(progress[id]) >= int(task.get("n", 1)):
		_complete(ch)

func _complete(ch: Node) -> void:
	winner = ch
	director.call(&"award", ch, &"viewer_task", float(task.get("points", 50)), [], {"task": String(task.id)})
	say(host_line("task_done", [Game.display_name(ch)]), true)
	done = true

func step(dt: float) -> void:
	if String(task.get("kind", "")) != "night_no_fire":
		return
	var w := world()
	if w == null:
		return
	var night := bool(w.call(&"is_night"))
	if night and not _night_started:
		_night_started = true
		for c in characters():
			_night_ok[c.get_instance_id()] = c
	elif night:
		_fire_t -= dt
		if _fire_t <= 0.0:
			_fire_t = 2.0
			for id in _night_ok.keys():
				var c: Node3D = _night_ok[id]
				if not alive(c) or _near_fire(c):
					_night_ok.erase(id)
	elif _night_started:
		# утро: лучший — игрок, иначе любой оставшийся
		var best: Node = null
		for id in _night_ok.keys():
			var c2: Node = _night_ok[id]
			if alive(c2) and (best == null or c2.is_in_group(&"player")):
				best = c2
		if best:
			_complete(best)
		else:
			done = true

func _near_fire(c: Node3D) -> bool:
	for f in get_tree().get_nodes_in_group(&"campfire"):
		if f is Node3D and bool(f.get(&"lit")) and (f as Node3D).global_position.distance_to(c.global_position) < 6.0:
			return true
	return false

func hud_line() -> String:
	if task.is_empty():
		return ""
	var p := player()
	var extra := ""
	if p and int(task.get("n", 1)) > 1:
		extra = " — %d/%d" % [mini(int(progress.get(p.get_instance_id(), 0)), int(task.n)), int(task.n)]
	if String(task.kind) == "night_no_fire":
		extra = " — %s" % ("идёт ночь" if _night_started else "ждём ночи")
	return "Задание зрителей: %s%s (+%d)" % [String(task.text).trim_prefix("Задание от зрителей: "), extra, int(task.get("points", 50))]
