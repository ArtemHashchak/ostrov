## test-timeout: 900
extends TestCase
## Каталог ассетов (AssetCatalog, docs/V5_AGENTS.md п.1): все записи flora.json валидны по контракту,
## каждая модель загружается (instantiate), у soft/solid есть простая форма коллизии и коллайдер
## (solid — StaticBody3D, soft — Area3D группы soft_plant с мета slow), у ground — текстуры.

func _init() -> void:
	scene_path = ""
	timeout_sec = 900.0

func run() -> void:
	AssetCatalog.reload()
	var all := AssetCatalog.entries()
	check(all.size() > 0, "каталог не пуст (%d записей)" % all.size())
	var flora := 0
	var bad := 0
	var cats := {}
	for e: Dictionary in all:
		if String(e.get("_file", "")) != "flora.json":
			continue
		flora += 1
		var id := String(e["id"])
		var cat := String(e.get("category", ""))
		cats[cat] = int(cats.get(cat, 0)) + 1
		var ok := AssetCatalog.CATEGORIES.has(cat)
		for z in e.get("zones", []):
			ok = ok and AssetCatalog.ZONES.has(String(z))
		ok = ok and ["none", "soft", "solid"].has(String(e.get("collision", "")))
		ok = ok and (e.get("size_m", []) as Array).size() == 3
		if not ok:
			bad += 1
			print("[test] запись не по контракту: ", id)
			continue
		if cat == "ground":
			var tex: Dictionary = e.get("tex", {})
			var has_all := tex.has("albedo") and tex.has("normal") and tex.has("roughness")
			for k in tex:
				has_all = has_all and ResourceLoader.exists(String(tex[k]))
			if not has_all:
				bad += 1
				print("[test] грунт без текстур: ", id)
			continue
		var n := AssetCatalog.instantiate(id)
		if n == null:
			bad += 1
			print("[test] не загрузилось: ", id, " ", e.get("scene"))
			continue
		var lods: Array = e.get("lod", [])
		if not lods.is_empty():
			var n1 := AssetCatalog.instantiate(id, 1)
			if n1 == null:
				bad += 1
				print("[test] нет LOD1: ", id)
			else:
				n1.free()
		n.free()
		var col := String(e.get("collision"))
		if col != "none":
			var c := AssetCatalog.make_collider(id)
			var good := c != null and c.get_child_count() == 1
			if good:
				good = (col == "solid" and c is StaticBody3D) or (col == "soft" and c is Area3D and c.is_in_group(&"soft_plant") and float(c.get_meta(&"slow", 1.0)) < 1.0)
				var cs := c.get_child(0) as CollisionShape3D
				good = good and cs != null and cs.shape != null
			if not good:
				bad += 1
				print("[test] нет коллайдера: ", id)
			if c:
				c.free()
		if flora % 50 == 0:
			await wait_frames(1)
	print("[test] flora.json: %d записей %s" % [flora, cats])
	check(flora > 0, "есть записи флоры")
	check(bad == 0, "все записи флоры валидны, грузятся и с коллайдерами (ошибок: %d)" % bad)
