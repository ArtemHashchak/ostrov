class_name BuildLogHolder
extends Blueprint
## Поленница: держит до 10 брёвен. Подойди с бревном на плече — E положить;
## без бревна — E взять (бревно ложится на плечо). Если сломать — брёвна
## раскатываются.

const MAX_LOGS := 10
const LOG_R := 0.17
const LOG_L := 2.2

var logs: int = 0
var _log_nodes: Array[MeshInstance3D] = []

static func slot_pos(i: int) -> Vector3:
	var rows := [4, 3, 2, 1]
	var k := i
	for r in rows.size():
		var n: int = rows[r]
		if k < n:
			var z := (k - (n - 1) * 0.5) * (LOG_R * 2.0 + 0.0)
			return Vector3(0.0, BuildDefs.R * 2.0 + LOG_R + r * LOG_R * 1.72, z)
		k -= n
	return Vector3.ZERO

func _ready() -> void:
	super()
	if preview:
		return
	for i in MAX_LOGS:
		var mi := MeshInstance3D.new()
		mi.mesh = BuildMats.cylinder(LOG_R, LOG_L - 0.08 * (i % 3), 10)
		mi.material_override = BuildMats.mat(&"log")
		# бревно вдоль X, чуть провёрнуто вокруг своей оси — кора не повторяется
		var bas := Basis(Vector3.FORWARD, PI * 0.5) * Basis(Vector3.UP, i * 0.9)
		mi.transform = Transform3D(bas, slot_pos(i) + Vector3(0.04 * sin(i * 2.0), 0, 0))
		mi.visible = false
		add_child(mi)
		_log_nodes.append(mi)
	_refresh()

func _refresh() -> void:
	for i in _log_nodes.size():
		_log_nodes[i].visible = i < logs

## Положить бревно с плеча персонажа.
func put_log(ch: Node) -> bool:
	if not complete or logs >= MAX_LOGS or not bool(ch.get(&"carrying_log")):
		return false
	var obj: Node = ch.get(&"carried_object") as Node
	if obj and is_instance_valid(obj) and obj.has_method(&"consume_one"):
		obj.call(&"consume_one", ch)
	else:
		ch.call(&"set_carrying_log", false)
		if obj and is_instance_valid(obj):
			obj.queue_free()
	logs += 1
	_refresh()
	return true

## Взять бревно на плечо. false — пусто или руки заняты.
func take_log(ch: Node) -> bool:
	if not complete or logs <= 0 or bool(ch.get(&"carrying_log")):
		return false
	var lg := make_log()
	get_parent().add_child(lg)
	lg.global_transform = Transform3D(global_basis * Basis(Vector3.BACK, PI * 0.5), global_transform * slot_pos(logs - 1))
	logs -= 1
	_refresh()
	lg.interact(ch)
	return bool(ch.get(&"carrying_log"))

## Боты/API: добавить/убрать брёвна напрямую. Возвращают сколько изменено.
func add_logs(n: int) -> int:
	var put := clampi(n, 0, MAX_LOGS - logs) if complete else 0
	logs += put
	_refresh()
	return put

func remove_logs(n: int) -> int:
	var take := clampi(n, 0, logs)
	logs -= take
	_refresh()
	return take

## Бревно-предмет (как с дерева): переносится на плече, годится для стройки.
static func make_log() -> FloraLog:
	var lg := FloraLog.new()
	lg.length = LOG_L
	lg.radius = LOG_R
	lg._mesh = BuildMats.log_item_mesh(LOG_R, LOG_L)
	var cap := CapsuleShape3D.new()
	cap.radius = LOG_R
	cap.height = LOG_L
	lg._shape = cap
	lg._shape_xform = Transform3D.IDENTITY
	return lg

func get_interact_text(player: Node) -> String:
	if not complete:
		return super(player)
	if bool(player.get(&"carrying_log")):
		return "E — положить бревно (%d/%d)" % [logs, MAX_LOGS] if logs < MAX_LOGS else "Поленница полна (%d/%d)" % [logs, MAX_LOGS]
	return "E — взять бревно (%d/%d)" % [logs, MAX_LOGS] if logs > 0 else "Поленница пуста (0/%d)" % MAX_LOGS

func interact(player: Node) -> void:
	if not complete:
		super(player)
		return
	if bool(player.get(&"carrying_log")):
		if not put_log(player):
			BuildEnv.toast("Поленница полна")
	elif not take_log(player):
		BuildEnv.toast("Поленница пуста")

func destroy(by: Node = null) -> void:
	if _dead:
		return
	var par := get_parent()
	if par and is_inside_tree():
		for i in logs:
			var lg := make_log()
			par.add_child(lg)
			lg.global_transform = Transform3D(global_basis * Basis(Vector3.BACK, PI * 0.5), global_transform * slot_pos(i) + Vector3.UP * 0.3)
	logs = 0
	super(by)
