class_name BuildChest
extends Blueprint
## Сундук на 12 ячеек. Открывают только свои; чужие могут лишь сломать —
## тогда всё содержимое высыпается на землю (мешок, который можно подобрать).

const SLOTS := 12

var storage: BuildStorage = BuildStorage.new(SLOTS)
var _viewers: int = 0

func can_open(ch: Node) -> bool:
	if team < 0 or ch == null:
		return true
	var t: Variant = ch.get(&"team")
	return t != null and int(t) == team

func get_interact_text(player: Node) -> String:
	if not complete:
		return super(player)
	if can_open(player):
		var n := storage.total()
		return "E — открыть сундук" + (" (%d шт.)" % n if n > 0 else " (пусто)")
	return "Чужой сундук заперт — сломай, чтобы забрать вещи"

func interact(player: Node) -> void:
	if not complete:
		super(player)
		return
	if not can_open(player):
		BuildEnv.toast("Заперто")
		return
	BuildChestPanel.open_for(player, self)

## UI сообщает: сундук открыт/закрыт (крышка).
func viewer(on: bool) -> void:
	_viewers = maxi(0, _viewers + (1 if on else -1))
	set_leaf_open(_viewers > 0)

func destroy(by: Node = null) -> void:
	if _dead:
		return
	_spill()
	super(by)

func _spill() -> void:
	if storage.is_empty() or get_parent() == null or not is_inside_tree():
		return
	var items := storage.stacks()
	storage.clear()
	ItemPickup.spawn(get_parent(), global_position + Vector3.UP * 0.6, items, Vector3(0, 1.5, 0))
