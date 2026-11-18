class_name BuildGate
extends Blueprint
## Ворота частокола и ворота на мосту. Свои проходят: створка сама открывается
## перед своими и закрывается за ними. Чужих не пускает — ломай топором,
## взрывай или жги. E (свой) — держать открытыми / закрыть.

const AUTO_R := 2.8
const CLOSE_DELAY := 1.8
const SCAN := 0.15

var held_open: bool = false
var _near_t: float = 0.0
var _scan_t: float = 0.0

func _physics_process(delta: float) -> void:
	super(delta)
	if preview or _dead:
		return
	_scan_t -= delta
	if _scan_t > 0.0:
		return
	_scan_t = SCAN
	if not complete:
		set_leaf_open(false)
		return
	if friend_near():
		_near_t = CLOSE_DELAY
	else:
		_near_t -= SCAN
	set_leaf_open(held_open or _near_t > 0.0)

## Центр створки в мире.
func leaf_center() -> Vector3:
	var lf := BuildDefs.leaf(def_id)
	return global_transform * Vector3(lf.get("box_pos", Vector3.ZERO))

## Рядом есть живой свой (игрок, бот, приручённый зверь).
func friend_near() -> bool:
	if team < 0:
		return false
	var c := leaf_center()
	var seen := {}
	for g: StringName in [&"characters", &"player", &"tamed_animals"]:
		for n in get_tree().get_nodes_in_group(g):
			if seen.has(n):
				continue
			seen[n] = true
			if not can_pass(n):
				continue
			var n3 := n as Node3D
			if n3 and n3.global_position.distance_to(c) < AUTO_R:
				return true
	return false

## Может ли персонаж пройти (своя команда и жив).
func can_pass(ch: Node) -> bool:
	if ch == null:
		return false
	var t: Variant = ch.get(&"team")
	if t == null or int(t) != team:
		return false
	if ch.has_method(&"is_dead") and bool(ch.call(&"is_dead")):
		return false
	return true

## Открыть/закрыть (держать). false — чужой.
func set_gate_open(on: bool, by: Node = null) -> bool:
	if by != null and not can_pass(by):
		return false
	held_open = on
	if complete:
		set_leaf_open(on or _near_t > 0.0)
	return true

func get_interact_text(player: Node) -> String:
	if not complete:
		return super(player)
	if can_pass(player):
		return "%s — E: %s" % [BuildDefs.name_of(def_id), "закрыть" if held_open else "держать открытыми"]
	var tn := Game.TEAM_NAMES[team] if team >= 0 and team < Game.TEAM_NAMES.size() else "?"
	return "Ворота «%s» заперты — ломай топором или жги" % tn

func interact(player: Node) -> void:
	if not complete:
		super(player)
		return
	if not set_gate_open(not held_open, player):
		BuildEnv.toast("Заперто")
