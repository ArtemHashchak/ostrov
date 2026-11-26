class_name OneIslandArch
extends ShowcaseArch
## Раскладка «один остров» для полигона: тот же генератор рецептов (ShowcaseArch /
## IslandGen), но из ряда берётся только тип OneIslandArch.only — остров
## строится и держится в памяти один.

static var only: StringName = &"volcanic"

func _layout(seed_value: int) -> void:
	var keep: Array = []
	for e: Array in ORDER:
		if e[0] == only:
			keep.append(e)
	if keep.is_empty():
		keep.append(ORDER[0])
	ORDER = keep
	super._layout(seed_value)
