## test-timeout: 300
## test-class: render
extends TestCase
## Снимки интерфейса консоли и «Каталога существ» на лёгкой сцене (без полигона).

func run() -> void:
	await wait(2.0)
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var cat := SandboxCatalog.new()
	layer.add_child(cat)
	await wait_frames(4)
	await shot("catalog")
	cat._filter.text = "акул"
	cat.rebuild()
	await wait_frames(3)
	await shot("catalog_search")
	cat.visible = false
	var con: Node = get_tree().root.get_node(^"DevConsole")
	con.call(&"open")
	con.call(&"execute", "help")
	con.call(&"execute", "list sea")
	await wait_frames(4)
	await shot("console_list")
	con.call(&"close")
