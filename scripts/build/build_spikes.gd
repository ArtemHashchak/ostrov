class_name BuildSpikes
extends Blueprint
## Колья: заострённые палки, вбитые под углом наружу (+Z). Ранят чужих людей
## и зверей, которые в них лезут, и отталкивают. Сами понемногу ломаются.

const DAMAGE := 18.0
const COOLDOWN := 0.9
const WEAR := 2.5
const SCAN := 0.2
const MIN_STAKES := 4

var hits_dealt: int = 0
var _scan_t: float = 0.0
var _last_hit: Dictionary = {}

func is_armed() -> bool:
	return not preview and not _dead and filled_count(&"stick") >= MIN_STAKES

func _physics_process(delta: float) -> void:
	super(delta)
	if not is_armed():
		return
	_scan_t -= delta
	if _scan_t > 0.0:
		return
	_scan_t = SCAN
	var now := BuildEnv.now()
	var inv := global_transform.affine_inverse()
	for n in _victims(get_tree()):
		if not is_instance_valid(n):
			continue
		if _friendly(n):
			continue
		var l: Vector3 = inv * (n as Node3D).global_position
		if absf(l.x) > 1.55 or l.y < -0.6 or l.y > 1.4 or l.z < -0.3 or l.z > 1.45:
			continue
		var id := n.get_instance_id()
		if now - float(_last_hit.get(id, -99.0)) < COOLDOWN:
			continue
		_last_hit[id] = now
		_stab(n as Node3D)
		if not is_armed():
			return

# Общий на все колья список целей, пересобирается раз в кадр (а не 3 запроса групп на каждый кол).
static var _vic_frame := -1
static var _vic: Array[Node3D] = []

static func _victims(tree: SceneTree) -> Array[Node3D]:
	var f := Engine.get_physics_frames()
	if f == _vic_frame:
		return _vic
	_vic_frame = f
	_vic.clear()
	var seen := {}
	for g: StringName in [&"characters", &"player", &"animals"]:
		for n in tree.get_nodes_in_group(g):
			if seen.has(n) or not (n is Node3D) or not n.has_method(&"apply_damage"):
				continue
			seen[n] = true
			_vic.append(n as Node3D)
	return _vic

func _friendly(n: Node) -> bool:
	if n.has_method(&"is_dead") and bool(n.call(&"is_dead")):
		return true
	var t: Variant = n.get(&"team")
	return t != null and team >= 0 and int(t) == team

func _stab(n: Node3D) -> void:
	hits_dealt += 1
	n.call(&"apply_damage", DAMAGE, self, &"spikes")
	if n is CharacterBody3D:
		(n as CharacterBody3D).velocity += global_basis.z.normalized() * 5.0 + Vector3.UP * 1.5
	apply_damage(WEAR, null, &"melee")

func get_interact_text(player: Node) -> String:
	if complete:
		return "Колья — ранят чужих и зверей"
	return super(player)
