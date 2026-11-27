## test-class: render
## test-timeout: 1100
extends TestCase
## v5.1 (агент I): раны и кровь на крупных существах; походка варана (поправка UserClipRig.gait);
## зелёный кокос в руке. Свой мир в SubViewport (пустая сцена). В рендере — снимки отдельными файлами
## /mnt/user-data/outputs/v51_I_*.png.

const OUT_DIR := "/mnt/user-data/outputs"

var vp: SubViewport
var stage: Node3D
var cam: Camera3D

func _init() -> void:
	scene_path = "res://tests/empty_stage.tscn"
	timeout_sec = 1080.0

func run() -> void:
	await wait_frames(5)
	_make_stage()
	var W := get_node_or_null(^"/root/Wounds")
	check(W != null, "автозагрузка Wounds есть")
	if W == null:
		return
	W.set(&"host_override", stage)
	# ---------- варан с хитбоксом
	var root := Node3D.new()
	root.name = "Varan"
	stage.add_child(root)
	var model := UserClipRig.build_variant(&"monitor", 0)
	root.add_child(model)
	var c: UserClipRig = model.get_meta(&"anim")
	c.player.play("idle", 0.0)
	c.player.advance(0.1)
	var hb := CreatureHitbox.attach(root, {"hp": 500.0})
	check(hb != null, "хитбокс варана")
	await wait_frames(2)
	var sk := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var bxf := sk.global_transform
	var spine := bxf * sk.get_bone_global_pose(sk.find_bone("spine.02")).origin
	var head := bxf * sk.get_bone_global_pose(sk.find_bone("head")).origin
	var thigh := bxf * sk.get_bone_global_pose(sk.find_bone("thigh.R")).origin
	var side := root.global_basis.x
	# точки — как на коробке хитбокса (снаружи тела): рана должна лечь на кожу
	var w1: Node3D = W.call(&"add_hit", hb, spine + side * 0.6 + Vector3.UP * 0.05, side, &"ak47", &"bullet")
	var w2: Node3D = W.call(&"add_hit", hb, head + side * 0.4, side, &"machete", &"melee")
	var w3: Node3D = W.call(&"add_hit", hb, thigh + side * 0.5, side, &"arrow", &"bullet")
	check(w1 != null and w2 != null and w3 != null, "три раны на варане (пуля, мачете, стрела)")
	if w1 == null:
		return
	var spurts := get_tree().get_nodes_in_group(&"blood_spurt").size()
	_look(w1.global_position + side * 0.75 + Vector3(0.0, 0.18, 0.25), w1.global_position)
	await wait_frames(6)
	await _save("wounds_spurt")
	# сквозное ранение: выходное отверстие с другой стороны тела (винтовка через тело ≤ 0,6 м)
	var exits := 0
	for wn in get_tree().get_nodes_in_group(&"wound"):
		if (wn as Node).get_meta(&"kind", &"") == &"exit":
			exits += 1
	check(exits >= 1, "винтовочная пуля навылет — выходное отверстие с другой стороны (%d)" % exits)
	check(w1.get_parent() is BoneAttachment3D, "рана пули прикреплена к кости (%s)" % w1.get_parent().get_class())
	# рана на коже: ближе к кости спины, чем точка попадания (≈ толщина тела, 0.1–0.4 м)
	var dsk := w1.global_position.distance_to(spine)
	print("[test] рана пули от оси тела %.3f м" % dsk)
	check(dsk > 0.08 and dsk < 0.45, "рана на коже, а не в воздухе (%.3f м от оси)" % dsk)
	check(String(Wounds.wound_kind(&"machete", &"melee")) == "cut" and String(Wounds.wound_kind(&"ak47", &"bullet")) == "bullet_rifle"
		and String(Wounds.wound_kind(&"pistol_9mm", &"bullet")) == "bullet_small" and String(Wounds.wound_kind(&"spear", &"bullet")) == "spear",
		"вид раны по оружию")
	# рана двигается с телом: играем бег — расстояние до кости постоянно, а сама рана смещается
	var att := w1.get_parent() as BoneAttachment3D
	var bi := sk.find_bone(att.bone_name)
	var p0 := w1.global_position
	var rel0 := (sk.global_transform * sk.get_bone_global_pose(bi)).affine_inverse() * w1.global_position
	c.player.play("run", 0.0)
	var moved := 0.0
	var drift := 0.0
	for i in 20:
		c.player.advance(0.033)
		await wait_frames(1)
		var bx := sk.global_transform * sk.get_bone_global_pose(bi)
		drift = maxf(drift, (bx.affine_inverse() * w1.global_position).distance_to(rel0))
		moved = maxf(moved, w1.global_position.distance_to(p0))
	print("[test] рана: сдвиг с телом %.3f м, отклонение от кости %.4f м" % [moved, drift])
	check(moved > 0.01 and drift < 0.01, "рана едет вместе с телом (сдвиг %.3f, от кости %.4f)" % [moved, drift])
	# маска повреждений: рана нарисована в UV меша, материал — с наложением крови, подтёки растут по коже
	check(w1.has_meta(&"mask"), "рана в маске повреждений (UV меша)")
	var dm: DamageMask = w1.get_meta(&"mask") if w1.has_meta(&"mask") else null
	if dm:
		var bm0 := dm.mi.get_active_material(0)
		var has_ov := false
		var mm: Material = bm0
		while mm:
			if mm is ShaderMaterial and (mm as ShaderMaterial).shader == DamageMask.OVERLAY:
				has_ov = true
			mm = mm.next_pass
		check(has_ov, "у материала варана next_pass с кровью из маски")
		var px0 := _mask_px(dm)
		var dd0 := dm.drip_dist
		c.player.play("idle", 0.0)
		await wait(4.5)
		var px1 := _mask_px(dm)
		print("[test] маска %d px: крови %d → %d пикселей, подтёки протекли %.2f → %.2f м, в работе %d" % [dm.size, px0, px1, dd0, dm.drip_dist, dm.drips.size()])
		check(px0 > 40, "рана нарисована в маске (%d px)" % px0)
		check(px1 > px0 and dm.drip_dist > dd0 + 0.2, "подтёки поползли по коже за 4,5 с (%.2f → %.2f м)" % [dd0, dm.drip_dist])
		check(dm.drips.is_empty(), "подтёки дотекли за 2–5 с")
	# брызги и кровь на земле
	var spots := get_tree().get_nodes_in_group(&"blood_spot").size()
	print("[test] брызг %d, пятен %d" % [spurts, spots])
	check(spurts >= 3, "из ран брызжет кровь: %d" % spurts)
	check(spots >= 2, "кровь капает на землю: %d пятен" % spots)
	# мелкое существо — без ран
	var small := Node3D.new()
	stage.add_child(small)
	var bm := MeshInstance3D.new()
	var bxm := BoxMesh.new()
	bxm.size = Vector3(0.2, 0.1, 0.15)
	bm.mesh = bxm
	small.add_child(bm)
	small.position = Vector3(3, 0.1, 0)
	var shb := CreatureHitbox.attach(small, {})
	check(W.call(&"add_hit", shb, small.global_position, Vector3.UP, &"ak47", &"bullet") == null, "мелкое существо (<0,5 м) — без ран")
	# не существа: персонажи и постройки — без ран
	check(Wounds.creature_root(stage) == null, "сцена — не существо")
	# крупные планы живого (подтёки дотекли), затем смерть: раны остаются на туше
	await _shots_close(root)
	hb.dead = true
	await wait(1.5)
	check(is_instance_valid(w1) and is_instance_valid(w2), "раны остаются на туше")
	if dm:
		await wait(26.0)
		print("[test] туша: spread %.2f dry %.2f" % [dm.spread, dm.dry])
		check(dm.spread > 0.8 and dm.dry > 0.6, "на туше кровь расползлась и побурела (%.2f/%.2f)" % [dm.spread, dm.dry])
	await _shots_wounds(root, sk)
	# ---------- походка варана: изгиб и высота корпуса
	await _gait_check()
	# ---------- кокос
	await _coconut_shot()

func _make_stage() -> void:
	vp = SubViewport.new()
	vp.size = Vector2i(1400, 900)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	(scene as Node).add_child(vp)
	stage = Node3D.new()
	stage.name = "ShotStage"
	vp.add_child(stage)
	cam = Camera3D.new()
	cam.fov = 35.0
	cam.near = 0.01
	cam.far = 200.0
	stage.add_child(cam)
	cam.current = true
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	stage.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -140, 0)
	fill.light_energy = 0.45
	stage.add_child(fill)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	sky.sky_material = psm
	env.sky = sky
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.66, 0.7)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	stage.add_child(we)
	# земля (песок) с коллизией — для пятен крови
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(40, 0.2, 40)
	cs.shape = bs
	cs.position = Vector3(0, -0.1, 0)
	ground.add_child(cs)
	var gm := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	gm.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.7, 0.55)
	mat.roughness = 0.95
	gm.material_override = mat
	ground.add_child(gm)
	stage.add_child(ground)

func _save(nm: String) -> void:
	if is_fast():
		print("[test] снимок (пропущен, быстрый режим) ", nm)
		return
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	img.save_png("%s/v51_I_%s.png" % [OUT_DIR, nm])
	print("[test] снимок ", nm)

func _look(from: Vector3, at: Vector3) -> void:
	cam.global_position = from
	cam.look_at(at, Vector3.UP)

func _mask_px(dm: DamageMask) -> int:
	var n := 0
	for y in range(0, dm.size, 2):
		for x in range(0, dm.size, 2):
			if dm.img.get_pixel(x, y).r > 0.3:
				n += 1
	return n

func _wound_of(kind: Array) -> Node3D:
	for w in get_tree().get_nodes_in_group(&"wound"):
		if kind.has((w as Node).get_meta(&"kind", &"")):
			return w as Node3D
	return null

## Крупно: входное отверстие, разрез, выходное — каждое отдельным снимком, камера по нормали раны.
func _shots_close(root: Node3D) -> void:
	var shots := [["wounds_entry_close", [&"bullet_rifle"], 0.30], ["wounds_gash_close", [&"cut"], 0.36],
		["wounds_exit_close", [&"exit"], 0.32], ["wounds_arrow_close", [&"arrow"], 0.30]]
	for sh: Array in shots:
		var wn := _wound_of(sh[1])
		if wn == null:
			continue
		var n: Vector3 = wn.get_meta(&"normal", root.global_basis.x)
		n = Vector3(n.x, maxf(n.y, 0.0) + 0.3, n.z).normalized()
		_look(wn.global_position + n * float(sh[2]), wn.global_position + Vector3.DOWN * 0.035)
		await wait_frames(4)
		await _save(String(sh[0]))

func _shots_wounds(root: Node3D, sk: Skeleton3D) -> void:
	var side := root.global_basis.x
	var c := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("spine.01")).origin
	_look(c + side * 2.2 + Vector3(0, 0.8, 0.3), c + Vector3(0, -0.05, 0))
	await wait_frames(4)
	await _save("wounds_varan_side")
	var g := Vector3(c.x, 0.0, c.z) + side * 0.6
	_look(g + Vector3(1.2, 1.4, 0.9), g)
	await wait_frames(3)
	await _save("wounds_blood_ground")
	# туша через ~25 с: кровь вокруг ран расползлась и запеклась
	var entry := _wound_of([&"bullet_rifle"])
	if entry:
		var n: Vector3 = entry.get_meta(&"normal", side)
		n = Vector3(n.x, maxf(n.y, 0.0) + 0.35, n.z).normalized()
		_look(entry.global_position + n * 0.45, entry.global_position + Vector3.DOWN * 0.04)
		await wait_frames(4)
		await _save("wounds_corpse_matted")
	root.visible = false
	for nn in get_tree().get_nodes_in_group(&"blood_spot"):
		(nn as Node).queue_free()

## Поправка походки: изгиб позвоночника при беге меньше, корпус выше; снимки бега до/после.
func _gait_check() -> void:
	for fixed in [false, true]:
		var m := UserClipRig.build_variant(&"monitor", 0)
		stage.add_child(m)
		m.position = Vector3(0, 0, 0)
		var c: UserClipRig = m.get_meta(&"anim")
		if not fixed:
			c.variant = c.variant.duplicate()
			c.variant.erase("gait")
		c.player.play("run", 0.0)
		var an := c.player.get_animation("run")
		var dt := an.length / 40.0
		for k in 40:
			c.player.advance(dt)
			if fixed:
				c._gait_fix(dt)
		var sk := m.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		c._skel = sk
		var ymin := INF
		var ymax := -INF
		var s0 := sk.find_bone("spine.00")
		var s3 := sk.find_bone("spine.03")
		for i in 40:
			c.player.advance(dt)
			if fixed:
				c._gait_fix(dt)
			var d := c._gpose(s3).origin - c._gpose(s0).origin
			var yaw := rad_to_deg(atan2(d.x, -d.z))
			ymin = minf(ymin, yaw)
			ymax = maxf(ymax, yaw)
		print("[test] варан бег %s: размах изгиба %.1f°, подъём %.3f м" % ["с поправкой" if fixed else "клип", ymax - ymin, c.gait_lift])
		if fixed:
			check(ymax - ymin < 20.0 and c.gait_lift > 0.02, "бег варана: изгиб вбок ≤ 20° (%.1f), корпус выше (%.3f м)" % [ymax - ymin, c.gait_lift])
		# снимки: сверху и сбоку в 3 фазах шага
		for ph in 3:
			c.player.seek(an.length * (0.15 + ph * 0.28), true)
			if fixed:
				c._gw = {"walk": 0.0, "run": 1.0}
				c._gait_fix(0.0)
			await wait_frames(2)
			_look(Vector3(0.01, 4.2, 0.0), Vector3(0, 0.2, 0))
			await wait_frames(2)
			await _save("varan_run_top_%s_%d" % ["fixed" if fixed else "clip", ph])
			_look(Vector3(3.4, 0.55, 0.0), Vector3(0, 0.3, 0))
			await wait_frames(2)
			await _save("varan_run_side_%s_%d" % ["fixed" if fixed else "clip", ph])
		m.queue_free()
		await wait_frames(2)

func _coconut_shot() -> void:
	var g := HeldModels.build(&"coconut")
	stage.add_child(g)
	g.position = Vector3(-0.15, 0.0, 0)
	var p := HeldModels.build(&"coconut_peeled")
	stage.add_child(p)
	p.position = Vector3(0.15, 0.0, 0)
	var n := 0
	for mi in g.find_children("*", "MeshInstance3D", true, false):
		n += 1
	check(n > 0, "у зелёного кокоса в руке есть модель")
	_look(Vector3(0, 0.35, 0.75), Vector3(0, 0.05, 0))
	await wait_frames(3)
	await _save("coconut_green_and_peeled")
