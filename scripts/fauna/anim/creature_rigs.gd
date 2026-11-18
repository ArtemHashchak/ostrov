class_name CreatureRigs
extends RefCounted
## Модели-риги с суставами для кабана, обезьяны, птиц и летучей мыши (анимирует MammalAnim/BirdAnim).
## Геометрия — та же процедурная, что в AnimalModels, но разрезана на части:
## корень (его вращает Animal для рельефа/крена) → узел «Body» (смещения анимации: покачивание,
## наклон, посадка) → туловище, голова (шея), хвост, ноги (бедро → колено), крылья (плечо → кисть).
## Мета корня: legs — бёдра [ПЛ, ПП, ЗЛ, ЗП], knees, rig — словарь узлов.


static func _rig_root(species: StringName, L: float) -> Array:
	var root: Node3D = AnimalModels._root(species, L)
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	var rig := {"body": body}
	root.set_meta(&"rig", rig)
	root.set_meta(&"anim", FaunaAnim.mammal() if species in [&"boar", &"monkey"] else FaunaAnim.bird())
	return [root, body, rig]

## Нога из двух сегментов: бедро (pivot) → колено (pivot). Возвращает [hip, knee].
static func _leg2(parent: Node3D, mat: Material, upper: Mesh, lower: Mesh, hip_pos: Vector3,
		knee_pos: Vector3, name_: String) -> Array:
	var hip := Node3D.new()
	hip.name = name_
	hip.position = hip_pos
	parent.add_child(hip)
	hip.add_child(AnimalModels.mesh_node(upper, mat, "Upper"))
	var knee := Node3D.new()
	knee.name = "Knee"
	knee.position = knee_pos
	hip.add_child(knee)
	knee.add_child(AnimalModels.mesh_node(lower, mat, "Lower"))
	return [hip, knee]

# ============================== кабан ==============================
static func boar() -> Node3D:
	var L := 1.4
	var r := _rig_root(&"boar", L)
	var root: Node3D = r[0]
	var body: Node3D = r[1]
	var rig: Dictionary = r[2]
	var mat: ShaderMaterial = root.get_meta(&"mat")
	var torso := AnimalModels.cached("rig_boar_torso", func() -> ArrayMesh:
		var st := AnimalModels.begin()
		var prof := [[-0.47, 0.53, 0.13, 0.155], [-0.38, 0.57, 0.165, 0.2], [-0.24, 0.61, 0.21, 0.26],
			[-0.08, 0.62, 0.225, 0.27], [0.1, 0.6, 0.215, 0.25], [0.28, 0.6, 0.2, 0.23], [0.43, 0.6, 0.165, 0.2],
			[0.54, 0.6, 0.1, 0.13], [0.6, 0.6, 0.02, 0.03]]
		var rings: Array = []
		for p in prof:
			rings.append({"z": p[0], "y": p[1], "w": p[2], "h": p[3], "flat": 0.35})
		AnimalModels.loft(st, rings, 18, 2.0, 3.0)
		# грива — щетина по хребту
		for i in 12:
			var z := -0.42 + i * 0.065
			var top := 0.86 - absf(z + 0.1) * 0.12
			AnimalModels.tube(st, Vector3(0, top - 0.03, z), Vector3(0, top + 0.07 - i * 0.004, z + 0.05), 0.035, 0.004, 5, Color(1, 0, 0, 0))
		return AnimalModels.commit(st))
	body.add_child(AnimalModels.mesh_node(torso, mat, "Torso"))
	# голова на шее: сустав у холки
	var neck_p := Vector3(0, 0.53, -0.42)
	var neck := AnimalModels._pivot(body, "Neck", neck_p)
	var head := AnimalModels.cached("rig_boar_head", func() -> ArrayMesh:
		var st := AnimalModels.begin()
		var prof := [[-0.8, 0.41, 0.04, 0.04], [-0.78, 0.41, 0.055, 0.052], [-0.72, 0.43, 0.065, 0.065],
			[-0.62, 0.46, 0.085, 0.09], [-0.5, 0.52, 0.12, 0.14], [-0.4, 0.55, 0.15, 0.18], [-0.33, 0.56, 0.12, 0.15]]
		var rings: Array = []
		for p in prof:
			rings.append({"z": p[0] - neck_p.z, "y": p[1] - neck_p.y, "w": p[2], "h": p[3], "flat": 0.35})
		AnimalModels.loft(st, rings, 18, 2.0, 3.0, func(_p: Vector3, _s: float, _c: float, ri: int) -> float:
			return 0.8 if ri <= 1 else 0.0) # пятачок
		for sx: float in [-1.0, 1.0]:
			# клыки
			AnimalModels.tube(st, Vector3(sx * 0.055, 0.41, -0.66) - neck_p, Vector3(sx * 0.09, 0.49, -0.7) - neck_p, 0.012, 0.003, 5, Color(0.5, 1.0, 0.0, 0.0), true)
			# уши
			AnimalModels.tube(st, Vector3(sx * 0.08, 0.64, -0.43) - neck_p, Vector3(sx * 0.13, 0.74, -0.37) - neck_p, 0.035, 0.008, 5, Color(1, 0, 0, 0), true)
		return AnimalModels.commit(st))
	neck.add_child(AnimalModels.mesh_node(head, mat, "Head"))
	AnimalModels._eyes(neck, [Vector3(-0.112, 0.58, -0.49) - neck_p, Vector3(0.112, 0.58, -0.49) - neck_p], 0.015)
	rig["neck"] = neck
	# хвостик с кисточкой
	var tail := AnimalModels._pivot(body, "Tail", Vector3(0, 0.66, 0.58))
	var tm := AnimalModels.cached("rig_boar_tail", func() -> ArrayMesh:
		var st := AnimalModels.begin()
		AnimalModels.tube(st, Vector3.ZERO, Vector3(0, -0.16, 0.08), 0.014, 0.008, 5, Color(1, 0, 0, 0), true)
		AnimalModels.ellipsoid(st, Vector3(0, -0.17, 0.085), Vector3(0.018, 0.03, 0.018), 6, Color(1, 0, 0, 0), false)
		return AnimalModels.commit(st))
	tail.add_child(AnimalModels.mesh_node(tm, mat, "TailMesh"))
	rig["tail"] = [tail]
	# ноги: бедро → колено (копыто на земле при y = 0)
	var up := AnimalModels.cached("rig_boar_up", func() -> ArrayMesh:
		var st := AnimalModels.begin()
		AnimalModels.tube(st, Vector3(0, 0.09, 0), Vector3(0, -0.22, 0.02), 0.088, 0.055, 9, Color(0.65, 0, 0, 0))
		return AnimalModels.commit(st))
	var lo := AnimalModels.cached("rig_boar_lo", func() -> ArrayMesh:
		var st := AnimalModels.begin()
		AnimalModels.tube(st, Vector3(0, 0.02, 0), Vector3(0, -0.2, -0.03), 0.052, 0.033, 8, Color(0.85, 0, 0, 0))
		AnimalModels.tube(st, Vector3(0, -0.2, -0.03), Vector3(0, -0.26, -0.06), 0.034, 0.03, 7, Color(1.0, 0.0, 0, 0), true)
		return AnimalModels.commit(st))
	var legs: Array = []
	var knees: Array = []
	var names := ["LegFL", "LegFR", "LegHL", "LegHR"]
	var pos := [Vector3(-0.12, 0.48, -0.22), Vector3(0.12, 0.48, -0.22), Vector3(-0.13, 0.48, 0.36), Vector3(0.13, 0.48, 0.36)]
	for i in 4:
		var hk := _leg2(body, mat, up, lo, pos[i], Vector3(0, -0.22, 0.02), names[i])
		legs.append(hk[0])
		knees.append(hk[1])
	root.set_meta(&"legs", legs)
	root.set_meta(&"knees", knees)
	rig["legs"] = legs
	rig["knees"] = knees
	rig["leg_len"] = [0.22, 0.26]
	rig["hip_y"] = 0.48
	root.set_meta(&"length", L)
	return root

# ============================== обезьяна ==============================
static func monkey() -> Node3D:
	var r := _rig_root(&"monkey", 0.9)
	var root: Node3D = r[0]
	var body: Node3D = r[1]
	var rig: Dictionary = r[2]
	var mat: ShaderMaterial = root.get_meta(&"mat")
	# таз — опорная точка: туловище с головой и руками поворачивается вокруг него (сесть, встать)
	var H := Vector3(0, 0.43, 0.12)
	var hips := AnimalModels._pivot(body, "Hips", H)
	rig["hips"] = hips
	var torso := AnimalModels.cached("rig_monkey_torso", func() -> ArrayMesh:
		var st := AnimalModels.begin()
		var rings: Array = []
		var prof := [[-0.2, 0.475, 0.07, 0.07], [-0.17, 0.47, 0.1, 0.1], [-0.08, 0.46, 0.13, 0.13], [0.04, 0.44, 0.12, 0.12],
			[0.14, 0.42, 0.11, 0.11], [0.2, 0.41, 0.07, 0.07], [0.23, 0.41, 0.02, 0.02]]
		for p in prof:
			rings.append({"z": p[0] - H.z, "y": p[1] - H.y, "w": p[2], "h": p[3], "flat": 0.2})
		AnimalModels.loft(st, rings, 14, 2.0, 3.0)
		return AnimalModels.commit(st))
	hips.add_child(AnimalModels.mesh_node(torso, mat, "Torso"))
	var neck_p := Vector3(0, 0.55, -0.2) - H
	var neck := AnimalModels._pivot(hips, "Neck", neck_p)
	var N := H + neck_p
	var head := AnimalModels.cached("rig_monkey_head", func() -> ArrayMesh:
		var st := AnimalModels.begin()
		AnimalModels.ellipsoid(st, Vector3(0, 0.6, -0.28) - N, Vector3(0.085, 0.09, 0.085), 12, Color(0.8, 0, 0, 0))
		AnimalModels.ellipsoid(st, Vector3(0, 0.58, -0.35) - N, Vector3(0.06, 0.055, 0.035), 10, Color(0.3, 1.0, 0, 0), false)
		for sx: float in [-1.0, 1.0]:
			AnimalModels.ellipsoid(st, Vector3(sx * 0.085, 0.62, -0.27) - N, Vector3(0.015, 0.028, 0.022), 6, Color(0.4, 1.0, 0, 0), false)
		# шея — перемычка к туловищу
		AnimalModels.tube(st, Vector3(0, 0.0, 0.03), Vector3(0, 0.04, -0.06), 0.055, 0.06, 8, Color(0.6, 0, 0, 0))
		return AnimalModels.commit(st))
	neck.add_child(AnimalModels.mesh_node(head, mat, "Head"))
	AnimalModels._eyes(neck, [Vector3(-0.028, 0.615, -0.355) - N, Vector3(0.028, 0.615, -0.355) - N], 0.011)
	rig["neck"] = neck
	# конечности
	var up := AnimalModels.cached("rig_monkey_up", func() -> ArrayMesh:
		var st := AnimalModels.begin()
		AnimalModels.tube(st, Vector3(0, 0.02, 0), Vector3(0, -0.2, -0.03), 0.037, 0.026, 7, Color(0.6, 0, 0, 0))
		return AnimalModels.commit(st))
	var lo := AnimalModels.cached("rig_monkey_lo", func() -> ArrayMesh:
		var st := AnimalModels.begin()
		AnimalModels.tube(st, Vector3(0, 0.01, 0), Vector3(0, -0.2, 0.03), 0.026, 0.02, 7, Color(0.5, 0, 0, 0))
		AnimalModels.ellipsoid(st, Vector3(0, -0.21, 0.015), Vector3(0.025, 0.012, 0.035), 6, Color(0.2, 1.0, 0, 0), false)
		return AnimalModels.commit(st))
	var legs: Array = []
	var knees: Array = []
	# руки — на тазовом узле (двигаются с туловищем), ноги — на теле
	var front := [Vector3(-0.1, 0.44, -0.14), Vector3(0.1, 0.44, -0.14)]
	var hind := [Vector3(-0.1, 0.42, 0.14), Vector3(0.1, 0.42, 0.14)]
	var fl := _leg2(hips, mat, up, lo, front[0] - H, Vector3(0, -0.2, -0.03), "ArmL")
	var fr := _leg2(hips, mat, up, lo, front[1] - H, Vector3(0, -0.2, -0.03), "ArmR")
	var hl := _leg2(body, mat, up, lo, hind[0], Vector3(0, -0.2, -0.03), "LegL")
	var hr := _leg2(body, mat, up, lo, hind[1], Vector3(0, -0.2, -0.03), "LegR")
	for hk in [fl, fr, hl, hr]:
		legs.append(hk[0])
		knees.append(hk[1])
	var hand := AnimalModels._pivot(fr[1] as Node3D, "Hand", Vector3(0, -0.22, 0.0))
	rig["hand"] = hand
	# хвост — цепочка из 8 звеньев (каждое смотрит по +Z своего узла)
	var seg := AnimalModels.cached("rig_monkey_tailseg", func() -> ArrayMesh:
		var st := AnimalModels.begin()
		AnimalModels.tube(st, Vector3.ZERO, Vector3(0, 0, 0.075), 0.018, 0.015, 6, Color(0.9, 0, 0, 0), true)
		return AnimalModels.commit(st))
	var tail: Array = []
	var parent: Node3D = body
	var tp := Vector3(0, 0.45, 0.22)
	for i in 8:
		var t := AnimalModels._pivot(parent, "Tail%d" % i, tp)
		var mi := AnimalModels.mesh_node(seg, mat, "Seg")
		mi.scale = Vector3.ONE * (1.0 - i * 0.07)
		t.add_child(mi)
		tail.append(t)
		parent = t
		tp = Vector3(0, 0, 0.075 * (1.0 - i * 0.07))
	rig["tail"] = tail
	root.set_meta(&"legs", legs)
	root.set_meta(&"knees", knees)
	rig["legs"] = legs
	rig["knees"] = knees
	rig["leg_len"] = [0.2, 0.21]
	rig["hip_y"] = 0.43
	root.set_meta(&"length", 0.6)
	return root

# ============================== птицы ==============================
static func bird(species: StringName) -> Node3D:
	var parrot := species == &"parrot"
	var L := 0.85 if parrot else 0.5
	var r := _rig_root(species, L)
	var root: Node3D = r[0]
	var body: Node3D = r[1]
	var rig: Dictionary = r[2]
	var mat: ShaderMaterial = root.get_meta(&"mat")
	var torso := AnimalModels.cached("rig_bird_torso_" + String(species), func() -> ArrayMesh:
		var st := AnimalModels.begin()
		var rings: Array = []
		var prof := [[-0.13, 0.025], [-0.11, 0.038], [-0.07, 0.05], [0.0, 0.058], [0.06, 0.048], [0.11, 0.03], [0.14, 0.012]]
		for p in prof:
			rings.append({"z": p[0], "y": 0.0, "w": p[1], "h": p[1] * 1.05, "flat": 0.1})
		AnimalModels.loft(st, rings, 12, 2.0, 3.0)
		return AnimalModels.commit(st))
	body.add_child(AnimalModels.mesh_node(torso, mat, "Torso"))
	var NP := Vector3(0, 0.02, -0.12)
	var neck := AnimalModels._pivot(body, "Neck", NP)
	var head := AnimalModels.cached("rig_bird_head_" + String(species), func() -> ArrayMesh:
		var st := AnimalModels.begin()
		AnimalModels.ellipsoid(st, Vector3(0, 0.035, -0.15) - NP, Vector3(0.038, 0.04, 0.042), 10, Color(0.7, 0.0, 0, 0))
		AnimalModels.tube(st, Vector3(0, 0.0, 0.0), Vector3(0, 0.012, -0.03), 0.03, 0.034, 8, Color(0.6, 0, 0, 0))
		if parrot:
			AnimalModels.ellipsoid(st, Vector3(0, 0.03, -0.172) - NP, Vector3(0.025, 0.022, 0.02), 8, Color(0.2, 1.0, 0, 0), false)
			AnimalModels.tube(st, Vector3(0, 0.04, -0.185) - NP, Vector3(0, 0.0, -0.215) - NP, 0.016, 0.003, 6, Color(0.0, 0.0, 0, 0))
		else:
			AnimalModels.tube(st, Vector3(0, 0.03, -0.185) - NP, Vector3(0, 0.02, -0.235) - NP, 0.009, 0.003, 5, Color(0.5, 1.0, 0, 0))
		return AnimalModels.commit(st))
	neck.add_child(AnimalModels.mesh_node(head, mat, "Head"))
	AnimalModels._eyes(neck, [Vector3(-0.03, 0.05, -0.165) - NP, Vector3(0.03, 0.05, -0.165) - NP], 0.006)
	rig["neck"] = neck
	var tail := AnimalModels._pivot(body, "Tail", Vector3(0, 0.0, 0.12))
	var tm := AnimalModels.cached("rig_bird_tail_" + String(species), func() -> ArrayMesh:
		var st := AnimalModels.begin()
		if parrot:
			AnimalModels.tube(st, Vector3.ZERO, Vector3(0, -0.04, 0.36), 0.025, 0.006, 6, Color(1.0, 0.0, 0, 0))
		else:
			AnimalModels.membrane(st, Vector3.ZERO, [Vector3(-0.03, 0, 0.0), Vector3(-0.04, 0, 0.09), Vector3(0.04, 0, 0.09), Vector3(0.03, 0, 0.0)], Color(1.0, 0, 0, 0))
		return AnimalModels.commit(st))
	tail.add_child(AnimalModels.mesh_node(tm, mat, "TailMesh"))
	rig["tail"] = [tail]
	# лапки
	var legm := AnimalModels.cached("rig_bird_leg", func() -> ArrayMesh:
		var st := AnimalModels.begin()
		AnimalModels.tube(st, Vector3.ZERO, Vector3(0, -0.05, 0.01), 0.005, 0.004, 4, Color(0.0, 0.0, 0, 0))
		for k in 3:
			var a := (float(k) - 1.0) * 0.5
			AnimalModels.tube(st, Vector3(0, -0.05, 0.01), Vector3(sin(a) * 0.02, -0.055, 0.01 - cos(a) * 0.02), 0.003, 0.002, 4, Color(0.0, 0.0, 0, 0))
		AnimalModels.tube(st, Vector3(0, -0.05, 0.01), Vector3(0, -0.055, 0.03), 0.003, 0.002, 4, Color(0.0, 0.0, 0, 0))
		return AnimalModels.commit(st))
	var feet: Array = []
	for sx: float in [-1.0, 1.0]:
		var lp := AnimalModels._pivot(body, "Foot" + ("L" if sx < 0 else "R"), Vector3(sx * 0.02, -0.04, 0.0))
		var lmi := AnimalModels.mesh_node(legm, mat, "LegMesh")
		lmi.material_override = AnimalModels._plain(Color(0.25, 0.22, 0.2) if parrot else Color(0.85, 0.6, 0.2), 0.7)
		lp.add_child(lmi)
		feet.append(lp)
	rig["feet"] = feet
	# крылья: плечо → кисть (две половины, без маски взмаха в шейдере)
	var span := 0.55 if parrot else 0.6
	var wm := mat.duplicate() as ShaderMaterial
	if parrot:
		wm.set_shader_parameter(&"back_color", Color(0.12, 0.32, 0.8))
		wm.set_shader_parameter(&"belly_color", Color(0.9, 0.75, 0.15))
	else:
		wm.set_shader_parameter(&"back_color", Color(0.55, 0.58, 0.62))
	var tip_m: Material = null
	if not parrot:
		var tm2 := mat.duplicate() as ShaderMaterial
		tm2.set_shader_parameter(&"back_color", Color(0.08, 0.08, 0.09))
		tm2.set_shader_parameter(&"belly_color", Color(0.12, 0.12, 0.12))
		tip_m = tm2
	var h := span * 0.45
	var wings: Array = []
	for sx: float in [-1.0, 1.0]:
		var inner := AnimalModels.cached("rig_wing_in_%s_%d" % [species, int(sx)], func() -> ArrayMesh:
			var st := AnimalModels.begin()
			AnimalModels.membrane(st, Vector3(sx * 0.005, 0, 0.0), [Vector3(sx * 0.005, 0, -0.065), Vector3(sx * h, 0.004, -0.06),
				Vector3(sx * h, -0.004, 0.035), Vector3(sx * h * 0.7, -0.004, 0.09), Vector3(sx * 0.005, 0, 0.075)], Color(1.0, 0, 0, 0))
			return AnimalModels.commit(st))
		var outer := AnimalModels.cached("rig_wing_out_%s_%d" % [species, int(sx)], func() -> ArrayMesh:
			var st := AnimalModels.begin()
			AnimalModels.membrane(st, Vector3(0, 0, 0.0), [Vector3(0, 0.004, -0.06), Vector3(sx * span * 0.4, -0.01, -0.01),
				Vector3(sx * span * 0.55, -0.02, 0.05), Vector3(sx * span * 0.3, -0.015, 0.09), Vector3(sx * span * 0.1, -0.008, 0.07),
				Vector3(0, -0.004, 0.035)], Color(1.0, 0, 0, 0))
			return AnimalModels.commit(st))
		var sh := AnimalModels._pivot(body, "Wing" + ("L" if sx < 0 else "R"), Vector3(sx * 0.035, 0.022, -0.03))
		var imi := AnimalModels.mesh_node(inner, wm, "Inner")
		imi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
		sh.add_child(imi)
		var hand := AnimalModels._pivot(sh, "Hand", Vector3(sx * h, 0, 0))
		var omi := AnimalModels.mesh_node(outer, tip_m if tip_m else wm, "Outer")
		omi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
		hand.add_child(omi)
		wings.append({"shoulder": sh, "hand": hand, "side": sx})
	rig["wings"] = wings
	rig["span"] = span
	root.set_meta(&"length", L)
	return root

# ============================== летучая мышь ==============================
static func bat() -> Node3D:
	var r := _rig_root(&"bat", 0.12)
	var root: Node3D = r[0]
	var body: Node3D = r[1]
	var rig: Dictionary = r[2]
	var mat: ShaderMaterial = root.get_meta(&"mat")
	var torso := AnimalModels.cached("rig_bat_body", func() -> ArrayMesh:
		var st := AnimalModels.begin()
		AnimalModels.ellipsoid(st, Vector3(0, 0, 0), Vector3(0.028, 0.03, 0.05), 10, Color(0.6, 0, 0, 0))
		return AnimalModels.commit(st))
	body.add_child(AnimalModels.mesh_node(torso, mat, "Torso"))
	var neck := AnimalModels._pivot(body, "Neck", Vector3(0, 0.005, -0.04))
	var head := AnimalModels.cached("rig_bat_head", func() -> ArrayMesh:
		var st := AnimalModels.begin()
		AnimalModels.ellipsoid(st, Vector3(0, 0.005, -0.017), Vector3(0.02, 0.02, 0.022), 8, Color(0.6, 0, 0, 0))
		for sx: float in [-1.0, 1.0]:
			AnimalModels.tube(st, Vector3(sx * 0.01, 0.02, -0.02), Vector3(sx * 0.018, 0.05, -0.018), 0.008, 0.002, 4, Color(0.5, 0, 0, 0))
		return AnimalModels.commit(st))
	neck.add_child(AnimalModels.mesh_node(head, mat, "Head"))
	rig["neck"] = neck
	var wm := mat.duplicate() as ShaderMaterial
	wm.set_shader_parameter(&"back_color", Color(0.12, 0.09, 0.08))
	wm.set_shader_parameter(&"belly_color", Color(0.18, 0.13, 0.11))
	wm.set_shader_parameter(&"pattern_kind", 0.0)
	var wings: Array = []
	for sx: float in [-1.0, 1.0]:
		var inner := AnimalModels.cached("rig_bat_in_%d" % int(sx), func() -> ArrayMesh:
			var st := AnimalModels.begin()
			AnimalModels.membrane(st, Vector3(0, 0, 0.0), [Vector3(0, 0, -0.03), Vector3(sx * 0.1, 0.018, -0.045),
				Vector3(sx * 0.1, 0.0, 0.045), Vector3(0, 0, 0.045)], Color(0.8, 0, 0, 0))
			AnimalModels.tube(st, Vector3(0, 0, -0.02), Vector3(sx * 0.1, 0.018, -0.045), 0.004, 0.003, 4, Color(0.9, 0, 0, 0))
			return AnimalModels.commit(st))
		var outer := AnimalModels.cached("rig_bat_out_%d" % int(sx), func() -> ArrayMesh:
			var st := AnimalModels.begin()
			AnimalModels.membrane(st, Vector3(0, 0.01, -0.02), [Vector3(0, 0.018, -0.045), Vector3(sx * 0.15, 0.0, -0.025),
				Vector3(sx * 0.11, 0.0, 0.025), Vector3(sx * 0.06, 0.0, 0.02), Vector3(0, 0, 0.045)], Color(0.8, 0, 0, 0))
			# пальцы-спицы
			for tip in [Vector3(sx * 0.15, 0.0, -0.025), Vector3(sx * 0.11, 0.0, 0.025), Vector3(sx * 0.06, 0.0, 0.02)]:
				AnimalModels.tube(st, Vector3(0, 0.018, -0.04), tip, 0.003, 0.0015, 4, Color(0.9, 0, 0, 0))
			return AnimalModels.commit(st))
		var sh := AnimalModels._pivot(body, "Wing" + ("L" if sx < 0 else "R"), Vector3(sx * 0.02, 0.0, -0.005))
		sh.add_child(AnimalModels.mesh_node(inner, wm, "Inner"))
		var hand := AnimalModels._pivot(sh, "Hand", Vector3(sx * 0.1, 0, 0))
		hand.add_child(AnimalModels.mesh_node(outer, wm, "Outer"))
		wings.append({"shoulder": sh, "hand": hand, "side": sx})
	rig["wings"] = wings
	# задние лапки (ими висит)
	var feet: Array = []
	var fm := AnimalModels.cached("rig_bat_foot", func() -> ArrayMesh:
		var st := AnimalModels.begin()
		AnimalModels.tube(st, Vector3.ZERO, Vector3(0, 0, 0.035), 0.004, 0.003, 4, Color(0.5, 0, 0, 0))
		AnimalModels.tube(st, Vector3(0, 0, 0.035), Vector3(0, 0.008, 0.045), 0.003, 0.0015, 4, Color(0.2, 0, 0, 0))
		return AnimalModels.commit(st))
	for sx: float in [-1.0, 1.0]:
		var f := AnimalModels._pivot(body, "Foot" + ("L" if sx < 0 else "R"), Vector3(sx * 0.012, -0.01, 0.045))
		f.add_child(AnimalModels.mesh_node(fm, mat, "FootMesh"))
		feet.append(f)
	rig["feet"] = feet
	rig["span"] = 0.25
	root.set_meta(&"length", 0.12)
	return root
