## test-timeout: 600
extends TestCase
## v5, агент B «Существа и предметы»: каталог (assets/catalog/{creatures,sea,items,weapons,characters}.json) —
## каждая запись грузится и ставится; модели в руке (UserHeld): АК с деталями и сокетами (контракт №3), мачете,
## топор, нож, фонарик, бутылка, зажигалка; персонаж пользователя у ботов (клипы, рука, повязка команды);
## новые существа призываются консолью (CreatureSpawner) и получают хитбокс; морские особи (SeaCritter:
## тунец со скелетом, пиранья/кит из пака) — хитбокс, луч пули попадает, урон убивает, добыча падает.

const MY_FILES := ["creatures", "sea", "items", "weapons", "characters"]

func run() -> void:
	await wait_frames(5)
	# ---- каталог
	AssetCatalog.reload()
	var n := 0
	var bad: Array[String] = []
	for fn: String in MY_FILES:
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/catalog/%s.json" % fn))
		check(v is Dictionary and (v as Dictionary).has("entries"), "каталог %s.json читается" % fn)
		if not (v is Dictionary):
			continue
		for e: Dictionary in (v as Dictionary).entries:
			n += 1
			var sc := String(e.get("scene", ""))
			if not ResourceLoader.exists(sc):
				bad.append("%s: нет %s" % [e.id, sc])
				continue
			var res := load(sc)
			var inst: Node = null
			if res is PackedScene:
				inst = (res as PackedScene).instantiate()
			if inst == null:
				bad.append("%s: не создаётся" % e.id)
			else:
				inst.free()
			check(AssetCatalog.has(String(e.id)), "AssetCatalog знает %s" % e.id)
	print("[test] записей каталога B: %d" % n)
	check(n >= 55, "записей каталога ≥ 55 (%d)" % n)
	check(bad.is_empty(), "все модели каталога грузятся: %s" % ", ".join(bad))

	# ---- предметы в руке
	for id: StringName in UserHeld.MODELS:
		var m := UserHeld.build(id)
		check(m != null, "UserHeld.build(%s)" % id)
		if m:
			check(not m.find_children("*", "MeshInstance3D", true, false).is_empty(), "%s: есть меши" % id)
			m.free()
	var ak := SupplyModels._build(&"rifle")
	check(ak != null and ak.has_meta(&"user_model"), "автомат в руке — АК пользователя")
	if ak:
		for nm: String in ["BoltCarrier", "Trigger", "Selector", "Magazine"]:
			check(ak.find_child(nm, true, false) != null, "АК: деталь %s" % nm)
		for s: StringName in [&"muzzle", &"ejection_port", &"ads_anchor", &"mag", &"forend"]:
			check(WeaponDef.socket(ak, s) != null, "АК: сокет %s" % s)
		var mz := WeaponDef.socket(ak, &"muzzle")
		var ads := WeaponDef.socket(ak, &"ads_anchor")
		if mz and ads:
			check(mz.position.z < ads.position.z - 0.3, "ствол АК смотрит в −Z (дуло %.2f, прицел %.2f)" % [mz.position.z, ads.position.z])
			check(absf(mz.position.x) < 0.02, "дуло по оси")
		var sel := ak.find_child("Selector", true, false) as Node3D
		if sel:
			check(sel.position.x > 0.0, "переводчик справа (x=%.3f)" % sel.position.x)
		ak.free()
	var hm := HeldModels.build(&"axe_modern")
	check(hm != null and not hm.find_children("User_axe_modern", "", true, false).is_empty(), "топор в руке — модель пользователя")
	if hm:
		hm.free()
	SupplyItems.register()
	check(Items.get_item(&"knife_combat") != null, "предмет «Нож» (боевой) зарегистрирован")
	check(Items.get_item(&"lighter") != null, "предмет «Зажигалка» зарегистрирован")

	# ---- персонаж пользователя у бота
	var bm := BotModel.new().setup(1, 3)
	scene.add_child(bm)
	await wait_frames(3)
	check(bm.user_model, "бот — в модели персонажа пользователя")
	check(bm.anim != null, "у персонажа AnimationPlayer")
	if bm.anim:
		for a: StringName in [&"idle", &"walk", &"run", &"death"]:
			check(bm.anim.has_animation(a), "клип персонажа %s" % a)
	check(bm.hand_r != null, "кость правой руки найдена")
	bm.update_pose(0.1, 1.2, false, false)
	check(bm._cur == &"walk", "медленно — шаг (%s)" % bm._cur)
	bm.update_pose(0.1, 4.5, false, true)
	check(bm._cur == &"run", "быстро — бег")
	bm.set_held(&"rifle")
	check(bm._held_node != null, "предмет в руке бота")
	bm.set_dead(true)
	check(bm._cur == &"death", "смерть — клип death")
	bm.queue_free()

	# ---- призыв новых существ (консоль) и хитбоксы
	var cs := CreatureSpawner.instance()
	check(cs != null, "CreatureSpawner есть")
	if cs == null:
		return
	var p0 := Vector3(0, 0, 0)
	var pl := get_tree().get_first_node_in_group(&"player") as Node3D
	if pl:
		p0 = pl.global_position + Vector3(4, 0, 4)
	for id: String in ["frog_tree", "butterfly", "parrot_amazon_perch"]:
		check(not CreatureSpawner.find(id).is_empty(), "в списке консоли: %s" % id)
		var before := cs.spawned.size()
		CreatureSpawner.spawn(id, p0, 2, 1.5)
		await wait_frames(6)
		check(cs.spawned.size() >= before + 1, "%s призван" % id)
		var last: Dictionary = cs.spawned.back()
		var node := last.get("node") as Node3D
		var hb := node.get_node_or_null(^"CreatureHitbox") as CreatureHitbox if node else null
		check(hb != null, "%s: хитбокс" % id)
		if hb:
			hb.apply_damage(1000.0, null, &"bullet")
			check(hb.dead, "%s: убит" % id)

	# ---- море: тунец со скелетом, пиранья и кит из пака
	check(SeaSkel.has("tuna"), "SeaSkel: тунец")
	check(OceanRoster.species("tuna").get("model", "") == "skel:tuna", "в составе океана тунец со своей моделью")
	check(OceanRoster.species("whale").get("model", "") == "whale_humpback_user", "кит — модель пользователя")
	var sea_obj: Object = cs
	var wy := float(sea_obj.call(&"water_y"))
	var spot := p0 + Vector3(0, 0, 0)
	spot.y = wy - 3.0
	for sid: String in ["tuna", "piranha", "whale"]:
		var sp := OceanRoster.species(sid)
		check(not sp.is_empty(), "вид %s в составе" % sid)
		var c := SeaCritter.make(sp, sea_obj, spot, 77)
		check(c != null, "SeaCritter %s создан" % sid)
		if c == null:
			continue
		scene.add_child(c)
		await wait_frames(2)
		check(c.hitbox != null, "%s: хитбокс" % sid)
		if c.hitbox:
			var q := PhysicsRayQueryParameters3D.create(c.global_position + Vector3(0, 3.0 + c.length * 2.0, 0), c.global_position - Vector3(0, 3, 0))
			q.collision_mask = Shark.HIT_LAYER
			await get_tree().physics_frame
			await get_tree().physics_frame
			var hit := c.get_world_3d().direct_space_state.intersect_ray(q)
			check(not hit.is_empty() and hit.collider == c.hitbox, "%s: луч пули попадает в хитбокс" % sid)
			var dealt := Combat.deliver(null, c.hitbox, c.global_position, Vector3.UP, 5000.0, &"bullet", &"rifle")
			check(dealt > 0.0, "%s: Combat.deliver наносит урон" % sid)
			check(c.dead, "%s: убит" % sid)
		c.queue_free()
	await wait_frames(2)
	if failures.is_empty():
		print("[test] v5 существа и предметы: всё в порядке")
