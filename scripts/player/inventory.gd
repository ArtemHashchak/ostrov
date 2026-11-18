class_name Inventory
extends Node
## Инвентарь персонажа: 9 слотов хотбара (0..8) + рюкзак (9..). Слот — Dictionary
## {"id": StringName, "n": int} или пустой {}. Брёвна и прочие тяжёлые предметы
## (weight >= HEAVY_WEIGHT) в инвентарь не кладутся — их носят в руках.
## API (CONTRACT_G1): add, remove, count, has, сигнал changed.

signal changed

const HOTBAR := 9
const BACKPACK := 24
const SIZE := HOTBAR + BACKPACK
const HEAVY_WEIGHT := 10.0

var slots: Array[Dictionary] = []
var selected: int = 0 # выбранный слот хотбара (0..8)

func _ready() -> void:
	name = "Inventory"

func _init() -> void:
	slots.resize(SIZE)
	for i in SIZE:
		slots[i] = {}

static func stack_of(id: StringName) -> int:
	var d := Items.get_item(id)
	return maxi(1, d.stack) if d else 64

static func is_heavy(id: StringName) -> bool:
	var d := Items.get_item(id)
	return d != null and d.weight >= HEAVY_WEIGHT

## Добавить n штук. Возвращает остаток, который не поместился.
func add(id: StringName, n: int = 1) -> int:
	if n <= 0 or id == &"":
		return 0
	if is_heavy(id):
		return n
	var left := n
	var st := stack_of(id)
	# Сначала дополняем существующие стеки (хотбар, потом рюкзак).
	for i in SIZE:
		if left <= 0:
			break
		var s := slots[i]
		if not s.is_empty() and s.id == id and int(s.n) < st:
			var put := mini(st - int(s.n), left)
			s.n = int(s.n) + put
			left -= put
	# Потом пустые слоты: инструменты/оружие/еда — сначала в хотбар.
	var order := _empty_order(id)
	for i in order:
		if left <= 0:
			break
		if slots[i].is_empty():
			var put := mini(st, left)
			slots[i] = {"id": id, "n": put}
			left -= put
	if left != n:
		_emit()
	return left

func _empty_order(id: StringName) -> Array[int]:
	var d := Items.get_item(id)
	var prefer_hotbar := d != null and d.kind in [&"tool", &"weapon", &"food", &"build"]
	var a: Array[int] = []
	if prefer_hotbar:
		for i in SIZE: a.append(i)
	else:
		for i in range(HOTBAR, SIZE): a.append(i)
		for i in HOTBAR: a.append(i)
	return a

## Забрать n штук (только если есть все). true — забрано.
func remove(id: StringName, n: int = 1) -> bool:
	if n <= 0:
		return true
	if count(id) < n:
		return false
	var left := n
	# Сначала из рюкзака, чтобы не опустошать хотбар без нужды.
	for pass_i in 2:
		for i in SIZE:
			var in_hotbar := i < HOTBAR
			if (pass_i == 0 and in_hotbar) or (pass_i == 1 and not in_hotbar):
				continue
			if left <= 0:
				break
			var s := slots[i]
			if not s.is_empty() and s.id == id:
				var take := mini(int(s.n), left)
				s.n = int(s.n) - take
				left -= take
				if int(s.n) <= 0:
					slots[i] = {}
	_emit()
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

## Сколько ещё поместится предмета id.
func space_for(id: StringName) -> int:
	if is_heavy(id):
		return 0
	var st := stack_of(id)
	var sp := 0
	for s in slots:
		if s.is_empty():
			sp += st
		elif s.id == id:
			sp += maxi(0, st - int(s.n))
	return sp

# --- работа со слотами (UI) ---

func get_slot(i: int) -> Dictionary:
	return slots[i] if i >= 0 and i < SIZE else {}

func set_slot(i: int, s: Dictionary) -> void:
	if i < 0 or i >= SIZE:
		return
	slots[i] = s.duplicate() if not s.is_empty() else {}
	_emit()

## Перенос/обмен слотов; одинаковые предметы объединяются.
func move(from: int, to: int) -> void:
	if from == to or from < 0 or to < 0 or from >= SIZE or to >= SIZE:
		return
	var a := slots[from]
	var b := slots[to]
	if a.is_empty():
		return
	if not b.is_empty() and b.id == a.id:
		var st := stack_of(a.id)
		var put := mini(st - int(b.n), int(a.n))
		if put > 0:
			b.n = int(b.n) + put
			a.n = int(a.n) - put
			if int(a.n) <= 0:
				slots[from] = {}
			_emit()
			return
	slots[from] = b
	slots[to] = a
	_emit()

## Убрать стек из слота целиком (для выбрасывания). Возвращает его.
func take_slot(i: int) -> Dictionary:
	var s := get_slot(i)
	if s.is_empty():
		return {}
	slots[i] = {}
	_emit()
	return s.duplicate()

func selected_id() -> StringName:
	var s := slots[selected]
	return s.id if not s.is_empty() else &""

func select(i: int) -> void:
	selected = clampi(i, 0, HOTBAR - 1)
	_emit()

func clear() -> void:
	for i in SIZE:
		slots[i] = {}
	_emit()

func _emit() -> void:
	changed.emit()
	var p := get_parent()
	if p:
		Events.inventory_changed.emit(p)
