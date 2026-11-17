extends Node
## База предметов и рецептов. Модули РЕГИСТРИРУЮТ свои предметы в _ready своей
## автозагрузки/узла через register_item / register_recipe — файл не правят.

class ItemDef:
	var id: StringName
	var name: String = ""
	var kind: StringName = &"resource" # resource, tool, weapon, food, build, misc
	var stack: int = 64
	var weight: float = 1.0 # тяжёлые ресурсы (брёвна) несут в руках, как в The Forest
	var icon: Texture2D = null
	var data: Dictionary = {}

class RecipeDef:
	var id: StringName
	var output: StringName
	var count: int = 1
	var needs: Dictionary = {} # item_id -> count
	var station: StringName = &"" # "" — в руках; иначе группа станции
	var data: Dictionary = {}

var items: Dictionary = {} # StringName -> ItemDef
var recipes: Dictionary = {} # StringName -> RecipeDef

func _ready() -> void:
	# Базовые предметы ядра; остальное регистрируют модули.
	register_item(&"log", "Бревно", &"resource", 1, 12.0)
	register_item(&"stick", "Палка", &"resource", 20, 0.5)
	register_item(&"stone", "Камень", &"resource", 20, 1.5)
	register_item(&"flag", "Флаг", &"build", 1, 3.0)

func register_item(id: StringName, display_name: String, kind: StringName = &"resource",
		stack: int = 64, weight: float = 1.0, data: Dictionary = {}) -> ItemDef:
	var d := ItemDef.new()
	d.id = id
	d.name = display_name
	d.kind = kind
	d.stack = stack
	d.weight = weight
	d.data = data
	items[id] = d
	return d

func register_recipe(id: StringName, output: StringName, needs: Dictionary,
		count: int = 1, station: StringName = &"") -> RecipeDef:
	var r := RecipeDef.new()
	r.id = id
	r.output = output
	r.needs = needs
	r.count = count
	r.station = station
	recipes[id] = r
	return r

func get_item(id: StringName) -> ItemDef:
	return items.get(id) as ItemDef

func item_name(id: StringName) -> String:
	var d := get_item(id)
	return d.name if d else String(id)
