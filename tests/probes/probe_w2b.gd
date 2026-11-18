extends SceneTree
func _init() -> void:
	var a := Archipelago.new(2026)
	var c := a._cell(286.0, 7.0)
	print(c)
	var I: Dictionary = a.islands[9]
	print(a._island_h(I, Vector2(286, 7)), " ", a._island_h(I, Vector2(292, 4)), " ", a._island_h(a.islands[1], Vector2(525, 0)), " ", a.height(525,0), " ", a.height(0,0))
	quit()
