extends TestCase
## Морские модели со скелетом и клипами автора (SeaSkel, assets/user_pack/sea_skel): все игровые GLB
## грузятся, клипы ролей на месте, зацикленные/с обнулённым ходом корня; существо в −Z центрировано;
## состав океана ссылается на них слотами «skel:» и «school:»; SeaCritter ведёт их (плывёт → клип swim,
## стоит → idle, испуг/укус/щелчок — разовые клипы); рефлексы (угроза мурены, скат в песке, свернулась
## звезда); стая сардин — VAT; стая хирургов — меш автора; менеджер вблизи камеры ставит виды со скелетом.

class FakeSea extends RefCounted:
	var wy := 0.0
	var fl := -6.0
	func water_y() -> float:
		return wy
	func floor_at(_x: float, _z: float) -> float:
		return fl
	func depth_at(_x: float, _z: float) -> float:
		return wy - fl

var sea := FakeSea.new()

func _init() -> void:
	scene_path = ""
	timeout_sec = 300.0

func run() -> void:
	var root3 := Node3D.new()
	get_tree().root.add_child(root3)
	var cam := Camera3D.new()
	root3.add_child(cam)
	cam.position = Vector3(0, -2, 6)
	cam.current = true

	# --- все модели
	for id: String in SeaSkel.DEFS:
		check(SeaSkel.has(id), "%s: игровой GLB в паке" % id)
		var s := SeaSkel.create(id)
		if s == null:
			continue
		root3.add_child(s)
		var d := SeaSkel.def(id)
		var ap := s.player()
		check(ap != null, "%s: AnimationPlayer автора" % id)
		for role: String in ["idle", "swim"]:
			check(s.has_role(role), "%s: клип роли %s (%s)" % [id, role, String((d.clips as Dictionary).get(role, ""))])
		for role: String in (d.clips as Dictionary):
			check(s.has_role(role), "%s: клип %s → %s есть в GLB" % [id, role, String(d.clips[role])])
		if ap and s.has_role("swim"):
			check(ap.get_animation(s.clip("swim")).loop_mode == Animation.LOOP_LINEAR, "%s: плавание зациклено" % id)
		if d.has("lod1"):
			check(s.lods.size() == 2, "%s: облегчённый LOD1" % id)
		# центровка: габарит тела вокруг начала координат (донные — низ на нуле)
		var ab := SeaSkel.bounds(id)
		var L := float(d.len)
		check(absf(ab.size.z - L) < L * 0.12, "%s: длина модели %.2f ≈ %.2f м" % [id, ab.size.z, L])
		s.queue_free()
	# корень обнулён: gulp групера, jump дельфина
	for pair: Array in [["giant_grouper", "gulp"], ["dolphin", "jump"]]:
		var s2 := SeaSkel.create(pair[0])
		root3.add_child(s2)
		var an := s2.player().get_animation(s2.clip(pair[1]))
		var moved := 0.0
		for t in an.get_track_count():
			if an.track_get_type(t) == Animation.TYPE_POSITION_3D and an.track_get_key_count(t) > 1:
				var sub := String(an.track_get_path(t).get_concatenated_subnames())
				if sub == "root" or sub.to_lower().contains("root"):
					moved = maxf(moved, (an.track_get_key_value(t, an.track_get_key_count(t) - 1) as Vector3).distance_to(an.track_get_key_value(t, 0)))
		check(moved < 0.001, "%s/%s: ход корня обнулён (%.3f м)" % [pair[0], pair[1], moved])
		s2.queue_free()

	# --- состав океана
	var want := {"clownfish": "skel", "surgeonfish": "skel", "butterflyfish": "skel", "angelfish": "skel", "grouper": "skel",
		"barracuda": "skel", "moray": "skel", "stingray": "skel", "manta": "skel", "sea_turtle": "skel", "starfish": "skel",
		"lobster": "skel", "dolphin": "skel", "pistol_shrimp": "skel", "squid": "skel", "sea_cucumber": "skel", "mandarin": "skel",
		"clown_triggerfish": "skel", "aulonocara": "skel", "discus": "skel", "baitfish": "school_mesh"}
	for sid: String in want:
		var vis := OceanRoster.visual(OceanRoster.species(sid))
		check(String(vis.get("kind", "")) == want[sid], "состав: %s → %s (%s)" % [sid, want[sid], String(vis.get("kind", ""))])
	check(OceanRoster.visual(OceanRoster.species("baitfish")).has("vat"), "сардины — стая VAT")

	# --- существо сцены: ход → swim, стоит → idle, испуг → startle
	var c := SeaCritter.make(OceanRoster.species("surgeonfish"), sea, Vector3(0, -2, 0), 11)
	check(c != null and c.skel != null, "хирург: SeaCritter с моделью со скелетом")
	if c:
		root3.add_child(c)
		c.goto(Vector3(0, -2, -20), c.cruise)
		for i in 60:
			c.tick(1.0 / 30.0)
		check(c.global_position.z < -0.5, "хирург плывёт (z=%.2f)" % c.global_position.z)
		var cur := c.skel.player().current_animation
		check(cur in ["swim", "swim_fast", "turn_L", "turn_R", "eat"], "хирург: клип хода (%s)" % cur)
		c.hold(c.global_position)
		for i in 90:
			c.tick(1.0 / 30.0)
		cur = c.skel.player().current_animation
		check(cur in ["idle_hover", "eat"], "хирург на месте: idle_hover (%s)" % cur)
		c.startle(c.global_position + Vector3(0.3, 0, 0))
		c.tick(1.0 / 30.0)
		check(c.skel.player().current_animation == "startle", "испуг: клип startle")

	# --- рефлексы: мурена (угроза → бросок), звезда сворачивается
	var mo := SeaCritter.make(OceanRoster.species("moray"), sea, Vector3(3, -5.88, 0), 3)
	root3.add_child(mo)
	mo.hold(mo.global_position)
	cam.global_position = mo.global_position + Vector3(0, 0.3, 2.0)
	for i in 20:
		mo.tick(1.0 / 30.0)
	check(mo.skel.posing() == "threat", "мурена: угроза при приближении (%s)" % mo.skel.posing())
	cam.global_position = mo.global_position + Vector3(0, 0.2, 0.6)
	for i in 12:
		mo.tick(1.0 / 30.0)
	check(mo.skel.player().current_animation == "lunge", "мурена: бросок вплотную (%s)" % mo.skel.player().current_animation)
	var st := SeaCritter.make(OceanRoster.species("starfish"), sea, Vector3(-3, -6, 0), 5)
	root3.add_child(st)
	check(st.bottom, "звезда — донная")
	cam.global_position = st.global_position + Vector3(0, 0.3, 0.3)
	for i in 12:
		st.tick(1.0 / 30.0)
	check(st.skel.posing() == "curl", "звезда сворачивается, если тронуть (%s)" % st.skel.posing())
	var sh := SeaCritter.make(OceanRoster.species("pistol_shrimp"), sea, Vector3(6, -6, 0), 7)
	root3.add_child(sh)
	var fx_before := sh.get_child_count()
	sh.act("snap")
	await wait(0.5)
	check(sh.get_child_count() > fx_before, "щелчок креветки: пузырь кавитации")
	cam.global_position = Vector3(0, -2, 30)

	# --- стаи: сардины (VAT) и хирурги (меш автора)
	var sc := SeaScene.new()
	sc.sea = sea
	root3.add_child(sc)
	var sch := sc.school("baitfish", 30, Vector3(0, -3, 0), 1.5)
	check(sch._mm.mesh != null and sch._mm.mesh.has_meta(&"vat"), "сардины: меш VAT")
	var mat := sch._mm.mesh.surface_get_material(0) as ShaderMaterial
	check(mat != null and mat.get_shader_parameter(&"vat_tex") != null, "сардины: текстура смещений")
	var sch2 := sc.school("surgeonfish", 12, Vector3(0, -3, 4), 1.2)
	check(sch2._mm.mesh != null and sch2._mi.material_override == null and sch2._mm.mesh.get_surface_count() >= 2, "хирурги стаей: меш автора (тело, плавники)")
	# --- рядом с камерой (открытый мир): менеджер ставит виды со скелетом
	var mgr := UserSeaActors.new()
	mgr.sea = sea
	root3.add_child(mgr)
	await wait_frames(2)
	check(mgr._skel_species.size() >= 12, "менеджер вблизи: видов со скелетом %d" % mgr._skel_species.size())
	var ids := {}
	for k in 40:
		mgr._refresh_skel(Vector3(0, -1, 0), 2)
	for cr in mgr.critters:
		ids[String(cr.sp.id)] = true
	check(ids.size() >= 8, "вблизи появились: %s" % ", ".join(ids.keys()))
	check(not ids.has("discus") and not ids.has("aulonocara"), "пресноводные — не в море")
	root3.queue_free()
