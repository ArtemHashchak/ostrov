class_name PolygonIslands
extends RefCounted
## Острова полигона: по одному острову каждого рецепта генератора, новый архипелаг
## версии 5 (если генератор агента C на месте) и текущая карта матча (пресет).
## Загружаются по одному — отдельной сценой PolygonIslandStage (музей выгружается).
##
## Контракт с генератором (docs/V5_AGENTS.md п.2): раскладка — класс-наследник
## Archipelago/IslandGen; архипелаги (v5 и пресет матча) строит сам World (gen_version)
## — со всем, что у мира игры: потоковый рельеф, карта зон, тропы, рассадка.

static func list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append({"id": "archipelago_v5", "name": "Новый архипелаг 3×3 км (версия 5)", "kind": "v5"})
	out.append({"id": "archipelago_match", "name": "Карта матча (пресет)", "kind": "match"})
	for e: Array in _order():
		var t: StringName = e[0]
		out.append({"id": String(t), "name": IslandGen.type_name(t), "kind": "recipe"})
	return out

## Порядок рецептов — как на прежнем «полигоне островов» (без построения раскладки).
static func _order() -> Array:
	return [[&"volcanic"], [&"atoll"], [&"karst"], [&"mangrove"], [&"cay"], [&"islet"], [&"savanna"], [&"coral"],
		[&"tombolo"], [&"plateau"]]

static func name_of(id: String) -> String:
	for e in list():
		if e.id == id:
			return String(e.name)
	return id

## Раскладка для острова/архипелага по id.
static func make_arch(id: String, seed_value: int) -> Archipelago:
	match id:
		"archipelago_v5":
			return ArchipelagoV5.new(seed_value)
		"archipelago_match":
			return Archipelago.new(seed_value)
	OneIslandArch.only = StringName(id)
	return OneIslandArch.new(seed_value)
