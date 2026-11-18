class_name BuildStorage
extends RefCounted
## Хранилище сундука: N слотов {id, n} или {}. API как у Inventory
## (add/remove/count/has/get_slot/take_slot), чтобы боты и UI работали одинаково.

signal changed

var slots: Array[Dictionary] = []

func _init(n: int = 12) -> void:
	slots.resize(n)
	for i in n:
		slots[i] = {}

func size() -> int:
	return slots.size()

## Положить n штук. Возвращает остаток, который не влез. Брёвна не кладутся.
func add(id: StringName, n: int = 1) -> int:
	if n <= 0 or id == &"" or Inventory.is_heavy(id):
		return n
	var left := n
	var st := Inventory.stack_of(id)
	for s in slots:
		if left <= 0:
			break
		if not s.is_empty() and s.id == id and int(s.n) < st:
			var put := mini(st - int(s.n), left)
			s.n = int(s.n) + put
			left -= put
	for i in slots.size():
		if left <= 0:
			break
		if slots[i].is_empty():
			var put2 := mini(st, left)
			slots[i] = {"id": id, "n": put2}
			left -= put2
	if left != n:
		changed.emit()
	return left

func remove(id: StringName, n: int = 1) -> bool:
	if count(id) < n:
		return false
	var left := n
	for i in range(slots.size() - 1, -1, -1):
		var s := slots[i]
		if left <= 0:
			break
		if not s.is_empty() and s.id == id:
			var take := mini(int(s.n), left)
			s.n = int(s.n) - take
			left -= take
			if int(s.n) <= 0:
				slots[i] = {}
	changed.emit()
	return true

func count(id: StringName) -> int:
	var c := 0
	for s in slots:
		if not s.is_empty() and s.id == id:
			c += int(s.n)
	return c

func has(needs: Dictionary) -> bool:
	for k in needs.keys():
		if count(StringName(k)) < int(needs[k]):
			return false
	return true

func get_slot(i: int) -> Dictionary:
	return slots[i] if i >= 0 and i < slots.size() else {}

func take_slot(i: int) -> Dictionary:
	var s := get_slot(i)
	if s.is_empty():
		return {}
	slots[i] = {}
	changed.emit()
	return s

func set_slot(i: int, s: Dictionary) -> void:
	if i >= 0 and i < slots.size():
		slots[i] = s
		changed.emit()

func is_empty() -> bool:
	for s in slots:
		if not s.is_empty():
			return false
	return true

func total() -> int:
	var c := 0
	for s in slots:
		if not s.is_empty():
			c += int(s.n)
	return c

func stacks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in slots:
		if not s.is_empty():
			out.append(s.duplicate())
	return out

func clear() -> void:
	for i in slots.size():
		slots[i] = {}
	changed.emit()
