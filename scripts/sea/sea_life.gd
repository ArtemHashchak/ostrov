class_name SeaLife
extends Node3D
## Мирная жизнь моря: скаты у рифов и в лагунах, морские черепахи у островов и
## черепашьих пляжей, медузы роями в проливах. Ближние к камере живут каждый кадр,
## средние — 4 раза в секунду, дальние спят и не рисуются. Медузы жалят персонажей в
## воде: немного урона и тошнота (SURVIVAL.apply_nausea).

const NEAR := 70.0
const MID := 150.0
const STING_R := 1.1
const STING_DMG := 5.0
const STING_CD := 3.0

var sea: Node = null
var density: float = 1.0
var creatures: Array[SeaCreature] = []
var _acc := 0.0
var _sting_acc := 0.0
var _sting_next: Dictionary = {}
var _time := 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	add_to_group(&"sea_life_manager")

func populate() -> void:
	for c in creatures:
		if is_instance_valid(c):
			c.queue_free()
	creatures.clear()
	_rng.seed = 2718
	var seed_i := 5000
	for I in sea.call(&"islands"):
		var kind: StringName = StringName(I.get("kind", &""))
		var c: Vector2 = I["center"]
		var r: float = I["radius"]
		var rays := 0
		var turtles := 1
		match kind:
			&"atoll":
				rays = 3
				turtles = 2
			&"shared":
				rays = 2
				turtles = 2
			&"spring", &"wreck":
				rays = 2
				turtles = 1
			&"home", &"center":
				rays = 1
				turtles = 1
			&"swamp":
				rays = 0
				turtles = 0
			_: rays = 1
		for i in int(round(rays * density)):
			seed_i += 1
			_spawn(SeaCreature.Kind.RAY, _ring_point(c, r, 1.0, 1.35), r * 0.45, seed_i)
		for i in int(round(turtles * density)):
			seed_i += 1
			_spawn(SeaCreature.Kind.TURTLE, _ring_point(c, r, 1.05, 1.5), r * 0.6, seed_i)
	if sea.get(&"world") and sea.get(&"world").has_method(&"turtle_beaches"):
		var tb: Array = sea.get(&"world").call(&"turtle_beaches")
		for b in tb:
			var p: Variant = b.get("pos", b.get("position", null))
			if p is Vector3:
				seed_i += 1
				var v := p as Vector3
				var off := Vector2(v.x, v.z) + Vector2(_rng.randf_range(-20, 20), _rng.randf_range(-20, 20))
				_spawn(SeaCreature.Kind.TURTLE, off, 25.0, seed_i)
	# медузы: рои в части проливов
	var straits: Array = sea.call(&"straits")
	for i in straits.size():
		if _rng.randf() > 0.55:
			continue
		var st: Dictionary = straits[i]
		var mid: Vector2 = st["mid"]
		var n := int(round(_rng.randi_range(4, 8) * density))
		for k in n:
			seed_i += 1
			var p := mid + Vector2(_rng.randf_range(-12, 12), _rng.randf_range(-12, 12))
			_spawn(SeaCreature.Kind.JELLY, p, 22.0, seed_i)

func _ring_point(c: Vector2, r: float, a: float, b: float) -> Vector2:
	for i in 10:
		var ang := _rng.randf() * TAU
		var rr := r * _rng.randf_range(a, b)
		var p := c + Vector2(cos(ang), sin(ang)) * rr
		if float(sea.call(&"depth_at", p.x, p.y)) > 1.6:
			return p
	return c + Vector2(r * b, 0.0)

func _spawn(k: SeaCreature.Kind, p: Vector2, r: float, seed_i: int) -> SeaCreature:
	if float(sea.call(&"depth_at", p.x, p.y)) < 1.0:
		return null
	var cr := SeaCreature.new()
	cr.setup(k, sea, p, r, seed_i)
	add_child(cr)
	var wy: float = sea.call(&"water_y")
	var fy: float = sea.call(&"floor_at", p.x, p.y)
	cr.global_position = Vector3(p.x, lerpf(wy - 0.8, fy + 0.5, 0.5), p.y)
	creatures.append(cr)
	return cr

func count_of(k: SeaCreature.Kind) -> int:
	var n := 0
	for c in creatures:
		if is_instance_valid(c) and c.kind == k and not c.dead:
			n += 1
	return n

func _physics_process(delta: float) -> void:
	if sea == null:
		return
	_time += delta
	var cam := get_viewport().get_camera_3d()
	var cp := cam.global_position if cam else Vector3.ZERO
	_acc += delta
	var mid_tick := _acc >= 0.25
	for i in range(creatures.size() - 1, -1, -1):
		var c := creatures[i]
		if not is_instance_valid(c):
			creatures.remove_at(i)
			continue
		var d := c.global_position.distance_to(cp)
		c.visible = d < MID
		if d < NEAR:
			c.tick(delta)
		elif d < MID and mid_tick:
			c.tick(_acc)
	if mid_tick:
		_acc = 0.0
	_sting_acc += delta
	if _sting_acc >= 0.2:
		_sting_acc = 0.0
		_stings()

func _stings() -> void:
	var chars := get_tree().get_nodes_in_group(&"characters")
	if chars.is_empty():
		return
	for n in chars:
		var ch := n as Node3D
		if ch == null or not ch.has_method(&"is_in_water") or not bool(ch.call(&"is_in_water")):
			continue
		if ch.has_method(&"is_dead") and bool(ch.call(&"is_dead")):
			continue
		var id := ch.get_instance_id()
		if _time < float(_sting_next.get(id, 0.0)):
			continue
		var p := ch.global_position
		for c in creatures:
			if c.kind != SeaCreature.Kind.JELLY or c.dead or not is_instance_valid(c):
				continue
			var q := c.global_position
			if absf(q.x - p.x) > STING_R or absf(q.z - p.z) > STING_R:
				continue
			if absf(q.y - (p.y + 0.3)) > 1.6:
				continue
			_sting_next[id] = _time + STING_CD
			if ch.has_method(&"apply_damage"):
				ch.call(&"apply_damage", STING_DMG, c, &"sting")
			var sv := get_tree().get_first_node_in_group(&"survival")
			if sv and sv.has_method(&"apply_nausea"):
				sv.call(&"apply_nausea", ch, 0.6)
			if ch.is_in_group(&"player"):
				Events.toast.emit("Медуза обожгла!")
			break
