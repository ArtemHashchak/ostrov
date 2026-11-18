class_name Animal
extends Node3D
## Дикое (или приручённое) животное. Двигается вручную по рельефу мира (Fauna.ground_y),
## поведение — конечный автомат. Тикает менеджер Fauna (LOD), не сам узел.
## Хитбокс — Area3D: его ловят луч удара игрока (on_hit) и луч взаимодействия (interact).
## Дроп — ItemPickup при смерти. Дикие не восстанавливаются: убитое животное не возрождается.

const SPECIES := {
	&"boar": {"name": "Кабан", "hp": 70.0, "walk": 1.3, "run": 6.2, "dmg": 9.0, "reach": 1.5, "cd": 1.2,
		"temper": &"defensive", "aggro_r": 5.0, "flee_r": 0.0, "box": Vector3(0.6, 0.9, 1.5), "box_y": 0.7,
		"drops": [{"id": &"meat_raw", "n": 3}, {"id": &"hide", "n": 2}],
		"tame": true, "food": [&"coconut", &"banana", &"berries", &"root", &"mango", &"papaya", &"seed"], "trust": 3,
		"sound": &"boar_grunt", "hurt": &"boar_squeal"},
	&"crab": {"name": "Краб", "hp": 8.0, "walk": 0.7, "run": 2.6, "dmg": 2.0, "reach": 0.5, "cd": 1.5,
		"temper": &"timid", "aggro_r": 0.0, "flee_r": 3.5, "box": Vector3(0.45, 0.25, 0.35), "box_y": 0.08,
		"drops": [{"id": &"crab_meat", "n": 1}], "sound": &"crab_click", "hurt": &"crab_click"},
	&"snake": {"name": "Змея", "hp": 16.0, "walk": 0.45, "run": 2.2, "dmg": 5.0, "reach": 1.3, "cd": 2.6,
		"temper": &"territorial", "aggro_r": 3.2, "flee_r": 0.0, "box": Vector3(0.5, 0.25, 1.4), "box_y": 0.1,
		"poison": [1.5, 12.0], "warn": 1.0,
		"drops": [{"id": &"meat_raw", "n": 1}], "sound": &"hiss", "hurt": &"hiss"},
	&"croc": {"name": "Крокодил", "hp": 160.0, "walk": 0.8, "run": 7.5, "dmg": 28.0, "reach": 2.3, "cd": 2.2,
		"temper": &"ambush", "aggro_r": 8.0, "flee_r": 0.0, "box": Vector3(0.9, 0.6, 3.3), "box_y": 0.25,
		"drops": [{"id": &"meat_raw", "n": 5}, {"id": &"hide", "n": 3}], "sound": &"croc_growl", "hurt": &"croc_growl"},
	&"monkey": {"name": "Обезьяна", "hp": 28.0, "walk": 1.8, "run": 6.0, "dmg": 3.0, "reach": 1.0, "cd": 1.5,
		"temper": &"thief", "aggro_r": 0.0, "flee_r": 4.0, "box": Vector3(0.5, 0.8, 0.7), "box_y": 0.5,
		"drops": [{"id": &"meat_raw", "n": 1}, {"id": &"hide", "n": 1}],
		"tame": true, "food": [&"banana", &"mango", &"coconut", &"berries", &"papaya"], "trust": 2,
		"sound": &"monkey", "hurt": &"monkey"},
	&"iguana": {"name": "Игуана", "hp": 18.0, "walk": 0.6, "run": 3.5, "dmg": 0.0, "reach": 0.6, "cd": 2.0,
		"temper": &"timid", "aggro_r": 0.0, "flee_r": 4.0, "box": Vector3(0.45, 0.3, 1.2), "box_y": 0.1,
		"drops": [{"id": &"meat_raw", "n": 1}],
		"tame": true, "food": [&"leaf", &"berries", &"banana", &"mango", &"papaya", &"fiber"], "trust": 2,
		"sound": &"lizard", "hurt": &"lizard"},
	&"monitor": {"name": "Варан", "hp": 45.0, "walk": 0.8, "run": 4.5, "dmg": 7.0, "reach": 1.3, "cd": 1.6,
		"temper": &"territorial", "aggro_r": 2.6, "flee_r": 0.0, "box": Vector3(0.55, 0.4, 1.7), "box_y": 0.15, "warn": 0.6,
		"drops": [{"id": &"meat_raw", "n": 2}, {"id": &"hide", "n": 1}], "sound": &"lizard", "hurt": &"hiss"},
	&"scorpion": {"name": "Скорпион", "hp": 5.0, "walk": 0.25, "run": 1.4, "dmg": 3.0, "reach": 0.8, "cd": 2.0,
		"temper": &"territorial", "aggro_r": 1.3, "flee_r": 0.0, "box": Vector3(0.3, 0.2, 0.3), "box_y": 0.05,
		"poison": [1.0, 10.0], "warn": 0.4, "drops": [], "sound": &"scorpion", "hurt": &"scorpion"},
	&"spider": {"name": "Паук-птицеед", "hp": 4.0, "walk": 0.3, "run": 1.8, "dmg": 3.0, "reach": 0.8, "cd": 2.0,
		"temper": &"territorial", "aggro_r": 1.2, "flee_r": 0.0, "box": Vector3(0.3, 0.2, 0.3), "box_y": 0.05,
		"poison": [1.0, 10.0], "warn": 0.3, "drops": [], "sound": &"scorpion", "hurt": &"scorpion"},
	&"parrot": {"name": "Попугай", "hp": 6.0, "walk": 0.5, "run": 9.0, "dmg": 0.0, "reach": 0.3, "cd": 1.0,
		"temper": &"bird", "aggro_r": 0.0, "flee_r": 7.0, "box": Vector3(0.6, 0.3, 0.6), "box_y": 0.0, "fly": true,
		"drops": [{"id": &"meat_raw", "n": 1}, {"id": &"feather", "n": 2}],
		"tame": true, "food": [&"berries", &"seed", &"banana", &"mango", &"papaya"], "trust": 3, "sound": &"parrot", "hurt": &"parrot"},
	&"gull": {"name": "Чайка", "hp": 6.0, "walk": 0.6, "run": 10.0, "dmg": 0.0, "reach": 0.3, "cd": 1.0,
		"temper": &"bird", "aggro_r": 0.0, "flee_r": 6.0, "box": Vector3(0.7, 0.3, 0.5), "box_y": 0.0, "fly": true,
		"drops": [{"id": &"meat_raw", "n": 1}, {"id": &"feather", "n": 2}], "sound": &"gull", "hurt": &"gull"},
	&"bat": {"name": "Летучая мышь", "hp": 3.0, "walk": 0.0, "run": 8.0, "dmg": 0.0, "reach": 0.2, "cd": 1.0,
		"temper": &"bird", "aggro_r": 0.0, "flee_r": 3.0, "box": Vector3(0.5, 0.2, 0.3), "box_y": 0.0, "fly": true,
		"drops": [], "sound": &"bat", "hurt": &"bat", "night": true},
	&"turtle": {"name": "Черепаха", "hp": 90.0, "walk": 0.25, "run": 0.45, "dmg": 0.0, "reach": 0.5, "cd": 2.0,
		"temper": &"turtle", "aggro_r": 0.0, "flee_r": 0.0, "box": Vector3(0.9, 0.45, 1.2), "box_y": 0.15, "swim": 1.4,
		"drops": [{"id": &"meat_raw", "n": 4}], "sound": &"egg_dig", "hurt": &"bite"},
}

signal died(animal: Animal, killer: Node)

var species: StringName = &"boar"
var cfg: Dictionary = {}
var health: float = 50.0
var max_health: float = 50.0
var state: StringName = &"idle"
var state_t: float = 0.0
var home: Vector3 = Vector3.ZERO      # центр участка (откуда не уходит далеко)
var home_r: float = 25.0
var target: Node3D = null             # кого атакуем/от кого бежим
var move_to: Vector3 = Vector3.ZERO
var speed: float = 0.0                # текущая скорость (для анимации)
var heading: float = 0.0              # yaw (нос по -Z)
var alt: float = 0.0                  # высота над землёй (птицы)
var vel_y: float = 0.0
var dead: bool = false
var growth: float = 1.0               # 0.45..1 — детёныш растёт
var fauna: Node = null                # Fauna
var flock: Dictionary = {}            # общий словарь стаи птиц
var flock_offset: Vector3 = Vector3.ZERO
# приручение
var tamed: bool = false
var owner_node: Node = null
var team: int = -1
var trust: int = 0
var follow: bool = true
var fed_t: float = -9999.0            # время последнего кормления (для разведения)
var breed_cd: float = 0.0
var pregnant_t: float = -1.0
# воровство
var stolen: Array[Dictionary] = []
# прочее
var lod: int = 0
var _acc: float = 0.0
var _attack_cd: float = 0.0
var _warn_t: float = 0.0
var _anim_t: float = 0.0
var _hurt_flash: float = 0.0
var _sound_cd: float = 0.0
var _think_t: float = 0.0
var _model: Node3D
var _mat: ShaderMaterial
var _legs: Array = []
var _wings: Array = []
## Контроллер анимации вида (общий интерфейс для всех видов, необязателен).
## Модель кладёт его в meta "anim" (Object). Методы (все необязательны):
##   setup(animal), animate(animal, dt), animate_dead(animal, dt), on_event(animal, ev: StringName)
## События: attack (удар/укус в момент нанесения), hurt, die, eat, threat.
## Если есть animate — встроенная процедурная анимация для вида не выполняется.
var anim_ctrl: Object = null
var _hitbox: Area3D
var _rng := RandomNumberGenerator.new()
var _dead_t: float = 0.0
var _nest_done: bool = false

static func create(sp: StringName, pos: Vector3, fauna_node: Node = null) -> Animal:
	var a := Animal.new()
	a.species = sp
	a.cfg = SPECIES.get(sp, SPECIES[&"boar"])
	a.name = String(sp).capitalize()
	a.fauna = fauna_node
	a.home = pos
	a.position = pos
	return a

func _ready() -> void:
	add_to_group(&"animals")
	add_to_group(&"fauna_animals")
	if cfg.is_empty():
		cfg = SPECIES.get(species, SPECIES[&"boar"])
	_rng.seed = get_instance_id()
	max_health = float(cfg["hp"])
	health = max_health
	heading = _rng.randf() * TAU
	_model = AnimalModels.build(species)
	add_child(_model)
	_mat = _model.get_meta(&"mat")
	_legs = _model.get_meta(&"legs")
	_wings = _model.get_meta(&"wings")
	anim_ctrl = _model.get_meta(&"anim", null)
	if anim_ctrl and anim_ctrl.has_method(&"setup"):
		anim_ctrl.call(&"setup", self)
	if _mat:
		_mat.set_shader_parameter(&"bend_phase", _rng.randf() * TAU)
	_model.scale = Vector3.ONE * growth
	_hitbox = Area3D.new()
	_hitbox.name = "Hitbox"
	_hitbox.monitoring = false
	_hitbox.collision_layer = 1
	_hitbox.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = cfg["box"]
	cs.shape = bs
	cs.position.y = float(cfg["box_y"]) + (cfg["box"] as Vector3).y * 0.25
	_hitbox.add_child(cs)
	add_child(_hitbox)
	_hitbox.scale = Vector3.ONE * growth
	if cfg.get("fly", false):
		alt = 6.0 + _rng.randf() * 6.0
		state = &"fly"
	rotation.y = heading
	_snap_ground(0.0)

# ============================== API ==============================

func display_name() -> String:
	return String(cfg["name"])

func is_dead() -> bool:
	return dead

func is_flying() -> bool:
	return cfg.get("fly", false) and alt > 0.5

func set_growth(g: float) -> void:
	growth = clampf(g, 0.3, 1.0)
	if _model:
		_model.scale = Vector3.ONE * growth
		_hitbox.scale = Vector3.ONE * growth

## Удар игрока (луч удара попал в хитбокс).
func on_hit(by: Node, hit: Dictionary) -> void:
	var dmg := float(hit.get("damage", 5.0))
	if hit.get("tool", &"") == &"spear":
		dmg *= 1.25
	apply_damage(dmg, by, &"melee")

func apply_damage(amount: float, source: Node = null, _kind: StringName = &"melee") -> void:
	if dead or amount <= 0.0:
		return
	health -= amount
	_hurt_flash = 0.25
	anim_event(&"hurt")
	_sound(cfg.get("hurt", &"bite"), 2.0)
	if health <= 0.0:
		die(source)
		return
	if source is Node3D and source != owner_node:
		_react_to_attack(source as Node3D)

func die(killer: Node = null) -> void:
	if dead:
		return
	dead = true
	anim_event(&"die")
	state = &"dead"
	state_t = 0.0
	speed = 0.0
	_dead_t = 0.0
	if _hitbox:
		_hitbox.queue_free()
		_hitbox = null
	var items: Array[Dictionary] = []
	var scale_n := growth >= 0.8
	for d: Dictionary in cfg.get("drops", []):
		if Items.get_item(d["id"]) == null:
			continue
		var n := int(d["n"]) if scale_n else maxi(1, int(d["n"]) / 2)
		items.append({"id": d["id"], "n": n})
	items.append_array(stolen)
	stolen.clear()
	if not items.is_empty() and is_inside_tree():
		var parent := get_parent()
		var gp := global_position + Vector3(0, 0.4 + (0.0 if not is_flying() else 0.0), 0)
		if is_flying():
			gp.y = Fauna.ground_y_at(self, gp.x, gp.z) + 0.4
		ItemPickup.spawn(parent, gp, items, Vector3(_rng.randf_range(-0.5, 0.5), 1.0, _rng.randf_range(-0.5, 0.5)))
	died.emit(self, killer)

## Взаимодействие (E): кормление едой в руке, у приручённых — команда идти/стоять.
func get_interact_text(by: Node) -> String:
	if dead:
		return ""
	var food := _held_food(by)
	if tamed and owner_node == by:
		if food != &"" and _accepts(food):
			return "E — покормить %s (%s)" % [display_name().to_lower(), Items.item_name(food)]
		return "E — %s" % ("ждать здесь" if follow else "за мной")
	if cfg.get("tame", false) and food != &"" and _accepts(food) and not tamed:
		return "E / ПКМ — покормить (%d/%d)" % [trust, int(cfg["trust"])]
	return display_name()

func interact(by: Node) -> void:
	if dead:
		return
	var food := _held_food(by)
	if food != &"" and _accepts(food) and (cfg.get("tame", false)):
		var inv: Inventory = by.get(&"inventory")
		if on_feed(by, food) and inv:
			inv.remove(food, 1)
		return
	if tamed and owner_node == by:
		follow = not follow
		home = global_position
		Events.toast.emit("%s: %s" % [display_name(), "идёт за вами" if follow else "ждёт здесь"])

## Хук кормления (ПКМ игрока с едой или E). true — еда съедена (вызывающий убирает 1 шт).
func on_feed(by: Node, id: StringName) -> bool:
	if dead or not cfg.get("tame", false) or not _accepts(id):
		return false
	if not tamed and state in [&"attack", &"chase"] and target == by:
		return false
	if by is Node3D and (by as Node3D).global_position.distance_to(global_position) > 4.0:
		return false
	fed_t = _now()
	health = minf(max_health, health + 10.0)
	_sound(cfg.get("sound", &"bite"), 0.0)
	if tamed:
		Events.toast.emit("%s сыт%s" % [display_name(), "а" if species in [&"monkey", &"iguana"] else ""])
		return true
	trust += 1
	if state in [&"flee", &"attack", &"chase", &"fly"]:
		_set_state(&"idle")
	target = null
	if trust >= int(cfg["trust"]):
		tame_by(by)
	else:
		Events.toast.emit("%s берёт еду (%d/%d)" % [display_name(), trust, int(cfg["trust"])])
	return true

func tame_by(by: Node) -> void:
	tamed = true
	owner_node = by
	team = int(by.get(&"team")) if by and by.get(&"team") != null else -1
	follow = true
	target = null
	remove_from_group(&"wild_animals")
	add_to_group(&"tamed_animals")
	if cfg.get("fly", false):
		alt = 0.0
	_set_state(&"follow")
	Events.toast.emit("%s приручен%s!" % [display_name(), "а" if species in [&"monkey", &"iguana"] else ""])

# ============================== тик ==============================

func _now() -> float:
	return float(fauna.get(&"clock")) if fauna else Time.get_ticks_msec() / 1000.0

func tick(dt: float) -> void:
	_anim_t += dt
	if dead:
		_tick_dead(dt)
		return
	_attack_cd = maxf(0.0, _attack_cd - dt)
	_sound_cd = maxf(0.0, _sound_cd - dt)
	breed_cd = maxf(0.0, breed_cd - dt)
	_hurt_flash = maxf(0.0, _hurt_flash - dt)
	state_t += dt
	if growth < 1.0 and fauna:
		set_growth(growth + dt / fauna.grow_seconds * 0.55)
	if cfg.get("fly", false) and tamed:
		_tick_shoulder(dt)
	elif cfg.get("fly", false):
		_tick_bird(dt)
	else:
		_think_t -= dt
		if _think_t <= 0.0:
			_think_t = 0.25 + _rng.randf() * 0.2
			_think()
		_act(dt)
	_animate(dt)

func _think() -> void:
	var temper: StringName = cfg["temper"]
	if tamed:
		_think_tamed()
		return
	var pl := _nearest_character(18.0)
	var d := INF
	if pl:
		d = pl.global_position.distance_to(global_position)
	match temper:
		&"timid":
			if pl and d < float(cfg["flee_r"]) * (1.6 if _is_crouching(pl) == false else 0.8):
				target = pl
				_set_state(&"flee")
			elif state == &"flee" and (pl == null or d > float(cfg["flee_r"]) * 3.0):
				_set_state(&"idle")
		&"defensive":
			if state in [&"chase", &"attack"]:
				if target == null or not _alive(target) or target.global_position.distance_to(home) > home_r * 1.6:
					target = null
					_set_state(&"idle")
			elif pl and d < float(cfg["aggro_r"]) and _rng.randf() < 0.12:
				target = pl
				_sound(cfg["sound"], 3.0)
				_set_state(&"chase")
			elif health < max_health * 0.3 and pl and d < 10.0:
				target = pl
				_set_state(&"flee")
		&"territorial":
			if state in [&"chase", &"attack"]:
				if target == null or not _alive(target) or target.global_position.distance_to(global_position) > 8.0:
					target = null
					_set_state(&"idle")
			elif state == &"warn":
				if pl == null or d > float(cfg["aggro_r"]) * 1.4:
					_set_state(&"idle")
			elif pl and d < float(cfg["aggro_r"]):
				target = pl
				_warn_t = float(cfg.get("warn", 0.5))
				_sound(cfg["sound"], 2.0)
				_set_state(&"warn")
			if health < max_health * 0.35 and pl and d < 6.0 and state != &"flee":
				target = pl
				_set_state(&"flee")
		&"ambush":
			_think_croc(pl, d)
		&"thief":
			_think_monkey(pl, d)
		&"turtle":
			_think_turtle(pl, d)
	if state == &"idle" and state_t > _rng.randf_range(2.0, 6.0):
		_pick_wander()
	elif state == &"wander" and (global_position.distance_to(move_to) < 0.6 or state_t > 20.0):
		_set_state(&"idle")

func _act(dt: float) -> void:
	var walk := float(cfg["walk"])
	var run := float(cfg["run"])
	match state:
		&"idle", &"stay", &"ambush", &"nest", &"warn":
			speed = move_toward(speed, 0.0, dt * 4.0)
			if state == &"warn" and target:
				_face(target.global_position, dt * 4.0)
				_warn_t -= dt
				if _warn_t <= 0.0:
					_set_state(&"attack")
			if state == &"nest":
				_tick_nest(dt)
		&"wander":
			_steer(move_to, walk, dt)
		&"follow":
			if owner_node is Node3D and _alive(owner_node):
				var op := (owner_node as Node3D).global_position
				var dd := op.distance_to(global_position)
				if dd > 3.0:
					_steer(op, run * 0.8 if dd > 8.0 else walk * 1.6, dt)
				else:
					speed = move_toward(speed, 0.0, dt * 4.0)
				if dd > 60.0:
					global_position = op + Vector3(1.5, 0, 1.5)
			else:
				speed = move_toward(speed, 0.0, dt * 4.0)
		&"flee":
			if target:
				var away := global_position - target.global_position
				away.y = 0.0
				if away.length() < 0.01:
					away = Vector3(1, 0, 0)
				var dest := global_position + away.normalized() * 6.0
				if species == &"crab" or species == &"turtle":
					dest = _towards_water(dest)
				if not _can_stand(dest) and species != &"crab":
					dest = global_position + away.normalized().rotated(Vector3.UP, 1.2) * 6.0
				_steer(dest, run, dt)
			if state_t > 8.0:
				_set_state(&"idle")
		&"chase":
			if target == null or not _alive(target):
				_set_state(&"idle")
				return
			var tp := target.global_position
			var dd := _flat_dist(tp)
			if dd <= float(cfg["reach"]) * growth + 0.2:
				_set_state(&"attack")
			else:
				_steer(tp, run, dt)
		&"attack":
			if target == null or not _alive(target):
				_set_state(&"idle")
				return
			_face(target.global_position, dt * 8.0)
			var dd := _flat_dist(target.global_position)
			if species == &"croc" and state_t < 0.6:
				_move_forward(float(cfg["run"]) * 1.4, dt) # бросок
			else:
				speed = move_toward(speed, 0.0, dt * 6.0)
			if dd > float(cfg["reach"]) * growth + 0.8:
				_set_state(&"chase" if cfg["temper"] != &"ambush" or state_t > 1.0 else &"attack")
				return
			if _attack_cd <= 0.0 and state_t > 0.15:
				_bite(target)
		&"steal":
			_act_steal(dt)
		&"to_water":
			_steer(move_to, float(cfg.get("swim", walk)) if _in_water() else walk, dt)
			if _flat_dist(move_to) < 1.0:
				_set_state(&"idle")
	_snap_ground(dt)

# ---------------------------- крокодил ----------------------------
func _think_croc(pl: Node3D, d: float) -> void:
	match state:
		&"idle", &"wander", &"ambush":
			if not _in_water():
				# вернуться в воду — засада у берега
				move_to = _towards_water(global_position)
				_set_state(&"to_water")
				return
			if state != &"ambush":
				_set_state(&"ambush")
			if pl and d < float(cfg["aggro_r"]):
				var wl := Fauna.water_y(self)
				var near_water := Fauna.ground_y_at(self, pl.global_position.x, pl.global_position.z) < wl + 1.2
				if near_water or d < 4.0:
					target = pl
					_sound(&"croc_growl", 6.0)
					_set_state(&"attack")
			elif state_t > 40.0:
				_pick_wander(8.0)
		&"attack", &"chase":
			if target == null or not _alive(target) or _flat_dist(target.global_position) > 12.0 or state_t > 6.0:
				target = null
				move_to = _towards_water(global_position)
				_set_state(&"to_water")
		&"flee":
			pass

# ---------------------------- обезьяна ----------------------------
func _think_monkey(pl: Node3D, d: float) -> void:
	if state == &"steal":
		return
	if not stolen.is_empty():
		# с добычей — бежит к дереву и сидит
		if state != &"flee" and state != &"perch":
			move_to = _nearest_tree_pos(global_position, 30.0, global_position + Vector3(8, 0, 8))
			_set_state(&"steal")
			set_meta(&"steal_phase", &"escape")
		return
	if pl and d < float(cfg["flee_r"]) and state != &"flee":
		target = pl
		_sound(&"monkey", 2.0)
		_set_state(&"flee")
		return
	if state in [&"idle", &"wander"] and state_t > 3.0 and _rng.randf() < 0.3:
		var loot := _find_loot(22.0)
		if loot:
			set_meta(&"loot", loot)
			set_meta(&"steal_phase", &"approach")
			_set_state(&"steal")

func _find_loot(r: float) -> Node3D:
	var best: Node3D = null
	var bd := r
	for p in get_tree().get_nodes_in_group(&"pickups"):
		var n := p as Node3D
		if n == null or not n.is_inside_tree():
			continue
		var dd := n.global_position.distance_to(global_position)
		if dd < bd:
			bd = dd
			best = n
	for s in get_tree().get_nodes_in_group(&"storage"):
		var n := s as Node3D
		if n == null:
			continue
		var inv := _storage_inv(n)
		if inv == null or not _inv_has_any(inv):
			continue
		var dd := n.global_position.distance_to(global_position)
		if dd < bd:
			bd = dd
			best = n
	return best

func _inv_has_any(inv: Inventory) -> bool:
	for sl in inv.slots:
		if not sl.is_empty():
			return true
	return false

func _storage_inv(n: Node) -> Inventory:
	var v: Variant = n.get(&"inventory")
	if v is Inventory:
		return v
	for c in n.get_children():
		if c is Inventory:
			return c
	return null

func _act_steal(dt: float) -> void:
	var phase: StringName = get_meta(&"steal_phase", &"approach")
	if phase == &"approach":
		var loot: Node3D = get_meta(&"loot", null)
		if loot == null or not is_instance_valid(loot) or not loot.is_inside_tree():
			_set_state(&"idle")
			return
		_steer(loot.global_position, float(cfg["run"]) * 0.7, dt)
		if _flat_dist(loot.global_position) < 0.9:
			_take_from(loot)
			move_to = _nearest_tree_pos(global_position, 30.0, global_position + Vector3(10, 0, -6))
			set_meta(&"steal_phase", &"escape")
			_sound(&"monkey", 3.0)
		elif state_t > 20.0:
			_set_state(&"idle")
	else:
		_steer(move_to, float(cfg["run"]), dt)
		if _flat_dist(move_to) < 1.2 or state_t > 15.0:
			_set_state(&"perch")
			state_t = 0.0
	if state == &"perch":
		speed = 0.0

func _take_from(n: Node3D) -> void:
	if n is ItemPickup:
		var pu := n as ItemPickup
		if pu.stacks.is_empty():
			return
		var s: Dictionary = pu.stacks.pop_back()
		stolen.append({"id": s.id, "n": int(s.n)})
		if pu.stacks.is_empty():
			pu.queue_free()
		return
	var inv := _storage_inv(n)
	if inv and _inv_has_any(inv):
		var full: Array[Dictionary] = []
		for sl in inv.slots:
			if not sl.is_empty():
				full.append(sl)
		var slot: Dictionary = full[_rng.randi() % full.size()]
		var id: StringName = slot.get("id", &"")
		var take := mini(int(slot.get("n", 1)), 3)
		if id != &"" and inv.remove(id, take):
			stolen.append({"id": id, "n": take})

# ---------------------------- черепаха ----------------------------
func _think_turtle(pl: Node3D, d: float) -> void:
	if state == &"nest" or state == &"to_water":
		return
	var night := Fauna.is_night_now(self)
	if pl and d < 3.0 and not _in_water():
		# прячется в панцирь — стоит
		_set_state(&"stay")
		return
	if state == &"stay" and (pl == null or d > 5.0):
		_set_state(&"idle")
	if not _nest_done and (night or (fauna and fauna.force_nesting)) and not _in_water() and _biome() == &"beach" and state_t > 2.0:
		_set_state(&"nest")
		return
	if _nest_done and state != &"to_water" and not _in_water():
		move_to = _towards_water(global_position)
		_set_state(&"to_water")

func _tick_nest(dt: float) -> void:
	if state_t > 6.0 and not _nest_done:
		_nest_done = true
		if fauna:
			fauna.make_nest(global_position + global_transform.basis.z * 0.5, _rng.randi_range(4, 8))
		_sound(&"egg_dig", 0.0)
		move_to = _towards_water(global_position)
		_set_state(&"to_water")

# ---------------------------- приручённые ----------------------------
func _think_tamed() -> void:
	if owner_node == null or not is_instance_valid(owner_node):
		tamed = false
		owner_node = null
		add_to_group(&"wild_animals")
		_set_state(&"idle")
		return
	# кабан защищает хозяина
	if species == &"boar" or species == &"monitor":
		var foe := _nearest_enemy_of_owner(10.0)
		if foe and state != &"attack":
			target = foe
			_set_state(&"chase")
			return
	if state in [&"chase", &"attack"]:
		if target == null or not _alive(target) or _flat_dist(target.global_position) > 14.0:
			target = null
			_set_state(&"follow" if follow else &"stay")
		return
	# попугай предупреждает о чужих
	if species == &"parrot" and _sound_cd <= 0.0:
		var foe := _nearest_enemy_of_owner(30.0)
		if foe:
			_sound(&"parrot", 6.0)
			_sound_cd = 8.0
			if owner_node.is_in_group(&"player"):
				Events.toast.emit("Попугай кричит: рядом чужой!")
	var want: StringName = &"follow" if follow else &"stay"
	if state != want:
		_set_state(want)

func _nearest_enemy_of_owner(r: float) -> Node3D:
	var best: Node3D = null
	var bd := r
	var op := (owner_node as Node3D).global_position if owner_node is Node3D else global_position
	for c in get_tree().get_nodes_in_group(&"characters"):
		var n := c as Node3D
		if n == null or n == owner_node or not _alive(n):
			continue
		var t: Variant = n.get(&"team")
		if t != null and team >= 0 and int(t) == team:
			continue
		var dd := n.global_position.distance_to(op)
		if dd < bd:
			bd = dd
			best = n
	return best

# ---------------------------- птицы ----------------------------
## Приручённый попугай сидит на плече хозяина (или ждёт на месте).
func _tick_shoulder(dt: float) -> void:
	_think_t -= dt
	if _think_t <= 0.0:
		_think_t = 0.5
		_think_tamed()
	if follow and owner_node is Node3D and _alive(owner_node):
		var o := owner_node as Node3D
		var b := o.global_transform.basis
		var tp := o.global_position + b.x * 0.28 + Vector3.UP * 1.55
		global_position = global_position.lerp(tp, clampf(dt * 8.0, 0.0, 1.0))
		heading = lerp_angle(heading, o.global_rotation.y, clampf(dt * 6.0, 0.0, 1.0))
		state = &"perch" if global_position.distance_to(tp) < 0.4 else &"fly"
	else:
		state = &"perch"
		var g := Fauna.ground_y_at(self, global_position.x, global_position.z)
		global_position.y = move_toward(global_position.y, g, dt * 3.0)
	rotation.y = heading
	speed = 0.0

func _tick_bird(dt: float) -> void:
	var night_bird: bool = cfg.get("night", false)
	var night := Fauna.is_night_now(self)
	if night_bird:
		visible = night or (fauna and fauna.force_night_birds)
		if not visible:
			return
	elif species == &"parrot" and night and state == &"fly":
		# ночью попугаи садятся на деревья
		flock["mode"] = &"perch"
	var c: Vector3 = flock.get("pos", home)
	var mode: StringName = flock.get("mode", &"fly")
	var pl := _nearest_character(float(cfg["flee_r"]))
	if pl and mode != &"fly":
		flock["mode"] = &"fly"
		flock["scare_t"] = 0.0
		mode = &"fly"
		_sound(cfg["sound"], 0.0)
	var goal := c + flock_offset
	if mode == &"perch":
		var perch: Vector3 = flock.get("perch", c)
		goal = perch + Vector3(flock_offset.x * 0.25, 0.0, flock_offset.z * 0.25)
		var g := Fauna.ground_y_at(self, goal.x, goal.z)
		var target_alt := maxf(0.0, perch.y - g)
		var to := goal - global_position
		to.y = 0.0
		var dd := to.length()
		if dd > 0.3:
			var sp := minf(float(cfg["run"]) * 0.6, dd * 1.5 + 0.5)
			global_position += to / dd * sp * dt
			heading = lerp_angle(heading, atan2(-to.x, -to.z), dt * 4.0)
			speed = sp
		else:
			speed = 0.0
		alt = move_toward(alt, target_alt, dt * 3.0)
		global_position.y = g + alt
		state = &"perch" if dd < 0.5 and absf(alt - target_alt) < 0.1 else &"fly"
	else:
		state = &"fly"
		var to := goal - global_position
		var dd := to.length()
		var sp := float(cfg["run"]) * (0.7 + 0.3 * sin(_anim_t * 0.7 + flock_offset.x))
		if species == &"bat":
			to += Vector3(sin(_anim_t * 5.3 + flock_offset.z) * 2.0, sin(_anim_t * 4.1) * 0.6, cos(_anim_t * 4.7 + flock_offset.x) * 2.0)
		var desired := to.normalized() * sp if dd > 0.01 else Vector3.ZERO
		var fwd := Vector3(-sin(heading), 0.0, -cos(heading))
		var cur := fwd * speed
		cur = cur.lerp(Vector3(desired.x, 0.0, desired.z), clampf(dt * 1.6, 0.0, 1.0))
		speed = maxf(cur.length(), sp * 0.6)
		if cur.length() > 0.01:
			heading = lerp_angle(heading, atan2(-cur.x, -cur.z), clampf(dt * 3.0, 0.0, 1.0))
		global_position += Vector3(-sin(heading), 0.0, -cos(heading)) * speed * dt
		var g := Fauna.ground_y_at(self, global_position.x, global_position.z)
		var wl := Fauna.water_y(self)
		var floor_y := maxf(g, wl)
		var want_y := maxf(goal.y, floor_y + 3.0)
		global_position.y = move_toward(global_position.y, want_y, dt * 3.0)
		global_position.y = maxf(global_position.y, floor_y + 1.5)
		alt = global_position.y - g
	rotation.y = heading
	# крен в повороте
	_model.rotation.z = lerpf(_model.rotation.z, clampf(angle_difference(rotation.y, heading) * 2.0, -0.6, 0.6), dt * 3.0)
	if _sound_cd <= 0.0 and _rng.randf() < dt * 0.05:
		_sound(cfg["sound"], -4.0)
		_sound_cd = 4.0

# ============================== помощники ==============================

func _react_to_attack(src: Node3D) -> void:
	var temper: StringName = cfg["temper"]
	if tamed:
		return
	match temper:
		&"timid", &"bird", &"thief":
			target = src
			if cfg.get("fly", false):
				flock["mode"] = &"fly"
			else:
				_set_state(&"flee")
		&"turtle":
			_set_state(&"stay")
		_:
			target = src
			if health < max_health * 0.25 and temper != &"ambush":
				_set_state(&"flee")
			else:
				_set_state(&"chase")
			trust = 0

func _bite(t: Node3D) -> void:
	_attack_cd = float(cfg["cd"])
	anim_event(&"attack")
	var dmg := float(cfg["dmg"]) * (0.5 + 0.5 * growth)
	if dmg <= 0.0:
		return
	_sound(&"croc_snap" if species == &"croc" else (&"boar_squeal" if species == &"boar" else &"bite"), 3.0)
	if t.has_method(&"apply_damage"):
		t.call(&"apply_damage", dmg, self, &"animal")
	var pz: Variant = cfg.get("poison", null)
	if pz != null and fauna:
		fauna.apply_poison(t, float(pz[0]), float(pz[1]))
		if t.is_in_group(&"player"):
			Events.toast.emit("Вас укусил%s %s — яд!" % ["а" if species == &"snake" else "", display_name().to_lower()])
	if species == &"croc" and t is Node3D:
		# тащит к воде
		var to_w := _towards_water(global_position) - (t as Node3D).global_position
		to_w.y = 0.0
		if to_w.length() > 0.1 and t is CharacterBody3D:
			(t as CharacterBody3D).velocity += to_w.normalized() * 4.0
	if cfg["temper"] == &"territorial" and not tamed:
		# ужалив, отползает
		_set_state(&"flee")

func _sound(kind: Variant, db: float) -> void:
	if kind == null or lod > 1:
		return
	FaunaSfx.play(self, kind as StringName, db, 5.0 if growth > 0.7 else 3.0, 1.0 / maxf(growth, 0.6))

## Событие для контроллера анимации (см. anim_ctrl).
func anim_event(ev: StringName) -> void:
	if anim_ctrl and anim_ctrl.has_method(&"on_event"):
		anim_ctrl.call(&"on_event", self, ev)

func _set_state(s: StringName) -> void:
	state = s
	state_t = 0.0

func _pick_wander(r: float = -1.0) -> void:
	var rr := r if r > 0.0 else minf(home_r, 14.0)
	for i in 6:
		var p := home + Vector3(_rng.randf_range(-rr, rr), 0.0, _rng.randf_range(-rr, rr))
		if _can_stand(p):
			move_to = p
			_set_state(&"wander")
			return

## Может ли животное стоять в точке (суша/вода по виду).
func _can_stand(p: Vector3) -> bool:
	var g := Fauna.ground_y_at(self, p.x, p.z)
	var wl := Fauna.water_y(self)
	match species:
		&"croc":
			return g < wl + 1.5 and g > wl - 3.0
		&"turtle":
			return g > wl - 8.0
		&"crab":
			return g > wl - 0.4 and g < wl + 3.0
	return g > wl + 0.15

func _towards_water(from: Vector3) -> Vector3:
	var wl := Fauna.water_y(self)
	var best := from
	var bh := INF
	for i in 12:
		var a := TAU * i / 12.0
		for r: float in [4.0, 8.0, 14.0]:
			var p := from + Vector3(cos(a) * r, 0.0, sin(a) * r)
			var g := Fauna.ground_y_at(self, p.x, p.z)
			var score := absf(g - (wl - 0.6)) + r * 0.05
			if score < bh:
				bh = score
				best = p
	return best

func _nearest_tree_pos(from: Vector3, r: float, fallback: Vector3) -> Vector3:
	var best := fallback
	var bd := r
	for t in get_tree().get_nodes_in_group(&"trees"):
		var n := t as Node3D
		if n == null:
			continue
		var dd := n.global_position.distance_to(from)
		if dd < bd and dd > 2.0:
			bd = dd
			best = n.global_position
	return best

func _in_water() -> bool:
	return Fauna.ground_y_at(self, global_position.x, global_position.z) < Fauna.water_y(self) - 0.15

func _biome() -> StringName:
	return Fauna.biome_of(self, global_position.x, global_position.z)

func _held_food(by: Node) -> StringName:
	if by == null or not by.has_method(&"held_item"):
		return &""
	var id: StringName = by.call(&"held_item")
	if id == &"":
		return &""
	return id

func _accepts(id: StringName) -> bool:
	var foods: Array = cfg.get("food", [])
	if id in foods:
		return true
	# любая растительная еда для кабана/обезьяны
	var d := Items.get_item(id)
	if d == null:
		return false
	if species in [&"boar", &"monkey"] and d.kind == &"food" and not String(id).contains("meat") and not String(id).contains("fish"):
		return true
	return false

func _nearest_character(r: float) -> Node3D:
	var best: Node3D = null
	var bd := r
	for c in get_tree().get_nodes_in_group(&"characters"):
		var n := c as Node3D
		if n == null or not _alive(n):
			continue
		var dd := n.global_position.distance_to(global_position)
		if dd < bd:
			bd = dd
			best = n
	return best

func _alive(n: Node) -> bool:
	if n == null or not is_instance_valid(n) or not n.is_inside_tree():
		return false
	if n.has_method(&"is_dead"):
		return not bool(n.call(&"is_dead"))
	return true

func _is_crouching(n: Node) -> bool:
	var v: Variant = n.get(&"crouching")
	return v == true

func _flat_dist(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()

func _face(p: Vector3, k: float) -> void:
	var to := p - global_position
	if Vector2(to.x, to.z).length() < 0.01:
		return
	heading = lerp_angle(heading, atan2(-to.x, -to.z), clampf(k, 0.0, 1.0))

func _steer(dest: Vector3, sp: float, dt: float) -> void:
	var to := dest - global_position
	to.y = 0.0
	var dd := to.length()
	if dd < 0.2:
		speed = move_toward(speed, 0.0, dt * 4.0)
		return
	var turn := 3.0 if species != &"crab" else 8.0
	_face(dest, dt * turn)
	var want := sp * (1.0 if dd > 1.0 else dd)
	if _in_water() and species != &"croc" and species != &"turtle":
		want *= 0.45
	elif species == &"croc" and _in_water():
		want = maxf(want, sp)
	speed = move_toward(speed, want, dt * (sp * 2.5 + 2.0))
	_move_forward(speed, dt)

func _move_forward(sp: float, dt: float) -> void:
	speed = sp
	var dir := Vector3(-sin(heading), 0.0, -cos(heading))
	if species == &"crab":
		# крабы бегают боком: тело развёрнуто на 90° к направлению
		pass
	var np := global_position + dir * sp * dt
	if (species == &"turtle" or species == &"croc") or _can_stand(np) or not _can_stand(global_position):
		global_position = Vector3(np.x, global_position.y, np.z)
	else:
		heading += PI * 0.5 * (1.0 if _rng.randf() < 0.5 else -1.0)
		if state == &"wander":
			_set_state(&"idle")

func _snap_ground(dt: float) -> void:
	var p := global_position
	var g := Fauna.ground_y_at(self, p.x, p.z)
	var wl := Fauna.water_y(self)
	var y := g
	var pitch := 0.0
	var roll := 0.0
	if (species == &"croc" or species == &"turtle") and g < wl - 0.25:
		# плывёт у поверхности: крокодил — глаза над водой
		y = wl - (0.3 if species == &"croc" else 0.35) * growth
		if species == &"turtle" and g < wl - 1.2:
			y = wl - 0.6
	else:
		var L := float(_model.get_meta(&"length", 1.0)) * 0.4 * growth
		var fwd := Vector3(-sin(heading), 0.0, -cos(heading))
		var right := Vector3(cos(heading), 0.0, -sin(heading))
		var gf := Fauna.ground_y_at(self, p.x + fwd.x * L, p.z + fwd.z * L)
		var gb := Fauna.ground_y_at(self, p.x - fwd.x * L, p.z - fwd.z * L)
		var w := maxf(L * 0.5, 0.1)
		var gr := Fauna.ground_y_at(self, p.x + right.x * w, p.z + right.z * w)
		var gl := Fauna.ground_y_at(self, p.x - right.x * w, p.z - right.z * w)
		pitch = atan2(gf - gb, 2.0 * L)
		roll = atan2(gr - gl, 2.0 * w)
		y = maxf(g, (gf + gb) * 0.5)
		if species == &"monkey" and state == &"perch":
			y += 3.5  # сидит на дереве
	if dt <= 0.0:
		global_position.y = y
	else:
		global_position.y = lerpf(global_position.y, y, clampf(dt * 10.0, 0.0, 1.0))
	rotation = Vector3(0.0, heading, 0.0)
	if not dead:
		_model.rotation.x = lerpf(_model.rotation.x, pitch, clampf(dt * 6.0, 0.0, 1.0)) if dt > 0.0 else pitch
		_model.rotation.z = lerpf(_model.rotation.z, -roll, clampf(dt * 6.0, 0.0, 1.0)) if dt > 0.0 else -roll

func _tick_dead(dt: float) -> void:
	_dead_t += dt
	if anim_ctrl and anim_ctrl.has_method(&"animate_dead"):
		anim_ctrl.call(&"animate_dead", self, dt)
	if cfg.get("fly", false):
		var g := Fauna.ground_y_at(self, global_position.x, global_position.z)
		global_position.y = move_toward(global_position.y, g + 0.05, dt * 9.0)
		_model.rotation.z = move_toward(_model.rotation.z, PI * 0.5, dt * 3.0)
	elif species in [&"crab", &"scorpion", &"spider", &"turtle"]:
		_model.rotation.z = move_toward(_model.rotation.z, PI, dt * 4.0)
	else:
		_model.rotation.z = move_toward(_model.rotation.z, PI * 0.5, dt * 3.0)
	if _mat:
		_mat.set_shader_parameter(&"bend_amp", 0.0)
		_mat.set_shader_parameter(&"flap", 0.0)
	for w in _wings:
		var wm := (w as MeshInstance3D).material_override as ShaderMaterial
		if wm:
			wm.set_shader_parameter(&"flap", -0.3)
	if _dead_t > 90.0:
		queue_free()

# ============================== анимация ==============================

func _animate(dt: float) -> void:
	if anim_ctrl and anim_ctrl.has_method(&"animate"):
		anim_ctrl.call(&"animate", self, dt)
		if _mat:
			_mat.set_shader_parameter(&"wetness", (0.9 if _in_water() else float(AnimalModels.LOOK[species].get("wet", 0.0))))
		return
	var sp_norm := clampf(speed / maxf(float(cfg["walk"]), 0.1), 0.0, 4.0)
	var ph := _anim_t * (4.0 + speed * 3.0)
	var n := _legs.size()
	match species:
		&"crab", &"scorpion", &"spider":
			for i in n:
				var leg := _legs[i] as Node3D
				var is_claw := (species != &"spider") and i < 2
				if is_claw:
					var att := 0.6 if state in [&"attack", &"warn", &"flee"] else 0.0
					leg.rotation.x = -att + sin(_anim_t * 6.0 + i) * 0.08
					continue
				var k := i - (0 if species == &"spider" else 2)
				var alt_ph := ph * 1.6 + (PI if (k / 2 + k) % 2 == 0 else 0.0)
				leg.rotation.z = sin(alt_ph) * 0.25 * minf(sp_norm, 1.5)
				leg.rotation.y = cos(alt_ph) * 0.18 * minf(sp_norm, 1.5)
			if species == &"crab":
				# бег боком: модель повёрнута поперёк движения
				_model.rotation.y = lerp_angle(_model.rotation.y, PI * 0.5 if speed > 0.3 else 0.0, dt * 6.0)
			if species == &"scorpion" and _mat:
				pass
		&"snake":
			if _mat:
				_mat.set_shader_parameter(&"bend_speed", 2.0 + speed * 6.0)
				_mat.set_shader_parameter(&"bend_amp", 0.025 + minf(speed, 2.0) * 0.03 if state != &"warn" else 0.015)
			# предупреждение — приподнятая голова
			_model.position.y = lerpf(_model.position.y, 0.0, dt * 4.0)
			_model.rotation.x = lerpf(_model.rotation.x, -0.12 if state == &"warn" or state == &"attack" else _model.rotation.x, dt * 6.0)
		&"croc", &"iguana", &"monitor":
			for i in n:
				var leg := _legs[i] as Node3D
				var off := 0.0 if (i == 0 or i == 3) else PI
				leg.rotation.y = sin(ph + off) * 0.45 * minf(sp_norm, 1.5)
				leg.rotation.z = (cos(ph + off) * 0.2 * minf(sp_norm, 1.5)) * (1.0 if i % 2 == 0 else -1.0)
			if _mat:
				_mat.set_shader_parameter(&"bend_speed", ph * 0.0 + (3.0 + speed * 2.0) if speed > 0.1 else 0.6)
				_mat.set_shader_parameter(&"bend_amp", (0.02 + minf(speed, 3.0) * 0.012) if speed > 0.1 else 0.008)
			if species == &"croc" and _in_water():
				# плывёт: лапы прижаты к телу назад, работает хвост
				for i in n:
					var leg := _legs[i] as Node3D
					leg.rotation.y = (1.1 if i % 2 == 0 else -1.1)
					leg.rotation.z = 0.0
				if _mat:
					_mat.set_shader_parameter(&"bend_amp", 0.02 + minf(speed, 3.0) * 0.02)
					_mat.set_shader_parameter(&"bend_speed", 2.0 + speed * 2.0)
		&"turtle":
			for i in n:
				var leg := _legs[i] as Node3D
				var front := i < 2
				var side := -1.0 if i % 2 == 0 else 1.0
				var swim := _in_water()
				var f := (ph * (0.6 if swim else 1.0))
				leg.rotation.y = side * sin(f + (0.0 if front else PI)) * (0.6 if swim else 0.35) * minf(sp_norm + (0.3 if swim else 0.0), 1.2)
				leg.rotation.z = side * cos(f) * (0.5 if swim and front else 0.1)
			if state == &"stay":
				_model.position.y = move_toward(_model.position.y, -0.05, dt)
			else:
				_model.position.y = move_toward(_model.position.y, 0.0, dt)
		_:
			# четвероногие: диагональная рысь (передняя левая + задняя правая)
			for i in n:
				var leg := _legs[i] as Node3D
				var off := 0.0 if (i == 0 or i == 3) else PI
				var amp := 0.35 + 0.15 * minf(sp_norm, 3.0)
				leg.rotation.x = sin(ph + off) * amp * minf(sp_norm, 1.0)
			var bob := absf(sin(ph)) * 0.025 * minf(sp_norm, 2.0) * growth
			_model.position.y = bob
			if species == &"monkey" and state == &"perch":
				_model.position.y = 0.0
	# крылья
	for w in _wings:
		var wm := (w as MeshInstance3D).material_override as ShaderMaterial
		if wm == null:
			continue
		var f := 0.0
		if state == &"perch" or (tamed and species == &"parrot"):
			f = -0.9 # сложены
		elif species == &"bat":
			f = sin(_anim_t * 18.0 + flock_offset.x) * 0.9
		elif species == &"gull":
			f = sin(_anim_t * 5.0 + flock_offset.x) * 0.55 if fmod(_anim_t + flock_offset.z, 6.0) < 3.5 else 0.05
		else:
			f = sin(_anim_t * 11.0 + flock_offset.x) * 0.8
		wm.set_shader_parameter(&"flap", f)
	# вспышка урона: краснеет
	if _mat:
		_mat.set_shader_parameter(&"wetness", (0.9 if _in_water() else float(AnimalModels.LOOK[species].get("wet", 0.0))))
