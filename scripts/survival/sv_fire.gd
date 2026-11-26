class_name SvFire
extends SvStation
## Костёр SURVIVAL: топливо (палки), жарка на решётке (до 4 штук), кипячение
## морской воды в котелке. Пока горит — в группе `campfire` (рецепты у костра).
## Два режима: свой костёр (набор campfire_kit) и «готовка» поверх каменного
## очага BUILD (fire_pit) — attached=true, своя модель только решётка и огонь.

const GRILL_MAX := 4
const COOK_TIME := 25.0
const BURN_TIME := 70.0 # сколько готовое может лежать на огне, пока не сгорит
const BOIL_TIME := 30.0
const BOIL_MAX := 4
const FUEL_PER_STICK := 90.0
const FUEL_MAX := 600.0
const LIGHT_STICKS := 2

var attached := false
var lit := false
var fuel := 0.0
## [{id, t, out}] — t: сек на огне
var grill: Array[Dictionary] = []
## Котелок на огне: {items: Array[StringName], t}
var pot: Dictionary = {}
var _fire: Node3D
var _grill_root: Node3D
var _pot_root: Node3D
var _steam: CPUParticles3D
var _sound: AudioStreamPlayer3D
var _dirty := true

func _ready() -> void:
	kind = &"campfire"
	name = "SvFire"
	max_hp = 40.0
	hp = max_hp
	if not attached:
		salvage = {&"stick": 2, &"rock": 3}
		model = Node3D.new()
		add_child(model)
		SurvivalModels.campfire(model)
		add_shape(Vector3(1.3, 0.5, 1.3), Vector3.ZERO, true)
	else:
		salvage = {}
		model = Node3D.new()
		add_child(model)
		SurvivalModels.grill(model, 0.74)
		# Оболочка больше камней очага — луч попадает сюда, а не в части чертежа.
		add_shape(Vector3(1.75, 0.95, 1.75), Vector3(0, -0.02, 0), true)
	_fire = SurvivalModels.fire(self, 1.0, Vector3(0, 0.06, 0))
	_grill_root = Node3D.new()
	add_child(_grill_root)
	_pot_root = Node3D.new()
	_pot_root.position = Vector3(0, 0.5, 0)
	add_child(_pot_root)
	_steam = SurvivalModels.smoke_only(self, Vector3(0, 0.66, 0), Color(0.9, 0.92, 0.95, 0.22), 8, 0.35)
	var fl := "res://assets/sounds/combat/fire_loop.wav"
	if ResourceLoader.exists(fl):
		_sound = AudioStreamPlayer3D.new()
		_sound.stream = load(fl) as AudioStream
		_sound.unit_size = 3.0
		_sound.volume_db = -6.0
		add_child(_sound)
	_apply_lit()

func _apply_lit() -> void:
	_fire.visible = lit
	for c in _fire.get_children():
		if c is CPUParticles3D:
			(c as CPUParticles3D).emitting = lit
	_steam.emitting = lit and not pot.is_empty()
	if lit:
		add_to_group(&"campfire")
		if _sound and is_inside_tree() and not _sound.playing:
			_sound.play()
	else:
		remove_from_group(&"campfire")
		if _sound:
			_sound.stop()

func light(ch: Node = null) -> bool:
	if lit:
		return true
	if ch and Survival.count(ch, &"stick") < LIGHT_STICKS:
		toast(ch, "Чтобы разжечь, нужны палки ×%d" % LIGHT_STICKS)
		return false
	var smoke_amt := 0.6
	if ch is Player:
		# V5: разжечь — чем и насколько сыро (FireMaking); неудача палки не тратит
		var r := FireMaking.attempt(ch, global_position)
		smoke_amt = float(r.smoke_amount)
		if not bool(r.ok):
			toast(ch, String(r.msg))
			return false
	set_meta(&"smoke_amount", smoke_amt)
	if ch:
		Survival.take(ch, &"stick", LIGHT_STICKS)
	fuel = maxf(fuel, FUEL_PER_STICK * LIGHT_STICKS)
	lit = true
	_apply_lit()
	if ch:
		toast(ch, "Костёр горит" + (" (сырые дрова — много дыма)" if smoke_amt > 1.1 else ""))
	return true

func add_fuel(ch: Node) -> bool:
	if fuel >= FUEL_MAX - FUEL_PER_STICK * 0.5:
		toast(ch, "Огонь и так большой")
		return false
	if not Survival.take(ch, &"stick", 1):
		return false
	fuel = minf(FUEL_MAX, fuel + FUEL_PER_STICK)
	toast(ch, "Подбросил палку")
	return true

func extinguish() -> void:
	lit = false
	fuel = 0.0
	_apply_lit()

func tick(dt: float) -> void:
	if lit:
		var drain := 1.0 + Survival.rain() * 1.5
		fuel -= dt * drain
		if fuel <= 0.0:
			extinguish()
		else:
			var l := _fire.get_node_or_null(^"Light") as OmniLight3D
			if l:
				l.light_energy = clampf(fuel / 120.0, 0.5, 1.0) * (2.0 + randf() * 0.4)
	if lit:
		for g in grill:
			var q0 := int(float(g.t) / COOK_TIME * 4.0)
			g.t = float(g.t) + dt
			if int(float(g.t) / COOK_TIME * 4.0) != q0 and float(g.t) <= COOK_TIME + 1.0:
				_dirty = true
			if float(g.t) >= COOK_TIME + BURN_TIME and g.out != &"rotten_food":
				g.out = &"rotten_food" # сгорело в уголь
				_dirty = true
		if not pot.is_empty():
			pot.t = float(pot.t) + dt
	_steam.emitting = lit and not pot.is_empty() and float(pot.get("t", 0.0)) > 5.0
	if _dirty:
		_rebuild_food()

func _rebuild_food() -> void:
	_dirty = false
	for c in _grill_root.get_children():
		c.queue_free()
	var n := grill.size()
	for i in n:
		var g := grill[i]
		var done := clampf(float(g.t) / COOK_TIME, 0.0, 1.0)
		var mi := SurvivalModels.grill_food(StringName(g.id), done if g.out != &"rotten_food" else 1.6)
		mi.position = Vector3(-0.3 + i * 0.2, 0.74, 0.0)
		_grill_root.add_child(mi)
	for c in _pot_root.get_children():
		c.queue_free()
	if not pot.is_empty():
		var pm := SurvivalModels.pot_model(1.0)
		_pot_root.add_child(pm)
		_pot_root.position = Vector3(0.0, 0.5 if not attached else 0.42, 0.18)

# ----------------------------------------------------- взаимодействие

func cookable(id: StringName) -> bool:
	return Survival.data(id).has("cook")

func boilable(id: StringName) -> bool:
	return Survival.data(id).has("boil")

func grill_ready() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for g in grill:
		if float(g.t) >= COOK_TIME:
			out.append(g)
	return out

func pot_ready() -> bool:
	return not pot.is_empty() and float(pot.t) >= BOIL_TIME

func _first_cookable(ch: Node) -> StringName:
	var h := held(ch)
	if cookable(h):
		return h
	var inv := Survival.inv(ch)
	if inv:
		for s in inv.slots:
			if not s.is_empty() and cookable(StringName(s.id)):
				return StringName(s.id)
	return &""

func _first_boilable(ch: Node) -> StringName:
	var h := held(ch)
	if boilable(h):
		return h
	var inv := Survival.inv(ch)
	if inv:
		for s in inv.slots:
			if not s.is_empty() and boilable(StringName(s.id)):
				return StringName(s.id)
	return &""

func get_interact_text(ch: Node) -> String:
	var head := "Костёр" if not attached else "Очаг"
	if not grill_ready().is_empty():
		return "%s — E: снять готовое (%d)" % [head, grill_ready().size()]
	if pot_ready():
		return "%s — E: снять котелок (кипячёная вода)" % head
	if not lit:
		return "%s — E: разжечь (палки ×%d, есть %d)" % [head, LIGHT_STICKS, Survival.count(ch, &"stick")]
	var bits: PackedStringArray = ["огонь %d с" % int(fuel)]
	if not grill.is_empty():
		bits.append("жарится %d" % grill.size())
	if not pot.is_empty():
		bits.append("кипит %d%%" % int(clampf(float(pot.t) / BOIL_TIME, 0.0, 1.0) * 100.0))
	var act := ""
	var c := _first_cookable(ch)
	var b := _first_boilable(ch)
	if held(ch) == &"stick":
		act = "E: подбросить палку"
	elif c != &"" and grill.size() < GRILL_MAX:
		act = "E: жарить «%s»" % iname(c)
	elif b != &"" and pot.is_empty():
		act = "E: кипятить «%s»" % iname(b) if Survival.count(ch, &"pot") > 0 else "кипятить воду — нужен котелок"
	elif Survival.count(ch, &"stick") > 0:
		act = "E: подбросить палку"
	return "%s (%s)%s" % [head, ", ".join(bits), (" — " + act) if act != "" else ""]

func interact(ch: Node) -> void:
	# 1. снять готовое
	var ready := grill_ready()
	if not ready.is_empty():
		for g in ready:
			Survival.give(ch, StringName(g.out), 1, global_position + Vector3.UP)
			grill.erase(g)
		_dirty = true
		return
	if pot_ready():
		for id in pot.items:
			Survival.give(ch, StringName(Survival.data(id).get("boil", id)), 1, global_position + Vector3.UP)
		Survival.give(ch, &"pot", 1, global_position + Vector3.UP)
		toast(ch, "Вода вскипела — теперь пресная")
		pot = {}
		_dirty = true
		return
	# 2. разжечь
	if not lit:
		light(ch)
		return
	if held(ch) == &"stick":
		add_fuel(ch)
		return
	# 3. жарить
	var c := _first_cookable(ch)
	if c != &"" and grill.size() < GRILL_MAX:
		put_on_grill(ch, c)
		return
	# 4. кипятить
	var b := _first_boilable(ch)
	if b != &"" and pot.is_empty():
		boil(ch, b)
		return
	if Survival.count(ch, &"stick") > 0:
		add_fuel(ch)

func put_on_grill(ch: Node, id: StringName) -> bool:
	if not lit or grill.size() >= GRILL_MAX or not cookable(id):
		return false
	if not Survival.take(ch, id, 1):
		return false
	grill.append({"id": id, "t": 0.0, "out": StringName(Survival.data(id).get("cook"))})
	_dirty = true
	toast(ch, "Жарится: %s" % iname(id))
	return true

## Поставить котелок со всей морской водой этого вида (до BOIL_MAX).
func boil(ch: Node, id: StringName = &"") -> bool:
	if not lit or not pot.is_empty():
		return false
	if Survival.count(ch, &"pot") <= 0:
		toast(ch, "Нужен котелок (жесть ×3 + верёвка)")
		return false
	if id == &"":
		id = _first_boilable(ch)
	if id == &"" or not boilable(id):
		return false
	var n := mini(BOIL_MAX, Survival.count(ch, id))
	if n <= 0 or not Survival.take(ch, id, n):
		return false
	Survival.take(ch, &"pot", 1)
	var arr: Array[StringName] = []
	for i in n:
		arr.append(id)
	pot = {"items": arr, "t": 0.0}
	_dirty = true
	toast(ch, "Котелок на огне: %s ×%d" % [iname(id), n])
	return true

func on_hit(by: Node, hit: Dictionary) -> void:
	if attached and get_parent() and get_parent().has_method(&"on_hit"):
		get_parent().call(&"on_hit", by, hit)
		return
	super.on_hit(by, hit)

func apply_damage(amount: float, source: Node = null, k: StringName = &"melee") -> void:
	if attached and get_parent() and get_parent().has_method(&"apply_damage"):
		get_parent().call(&"apply_damage", amount, source, k)
		return
	super.apply_damage(amount, source, k)

func on_broken(by: Node) -> void:
	for g in grill:
		Survival.give(by, StringName(g.id if float(g.t) < COOK_TIME else g.out), 1, global_position + Vector3.UP)
	if not pot.is_empty():
		for id in pot.items:
			Survival.give(by, StringName(id), 1, global_position + Vector3.UP)
		Survival.give(by, &"pot", 1, global_position + Vector3.UP)
