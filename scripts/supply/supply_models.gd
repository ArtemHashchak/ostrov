class_name SupplyModels
extends RefCounted
## Процедурные модели модуля SUPPLY: ящик спонсоров (пластиковый военный кейс с
## рёбрами, защёлками, ремнями и трафаретной маркировкой шоу), парашют, самолёт,
## дымовая шашка и «современные» предметы (автомат, дробовик, ракетница, граната,
## мачете, бензопила, горелка, бинокль, фонарик, рация, ласты, бронежилет, аптечка…).
## Соглашение HeldModels: корень — хват правой руки, +Y вверх по рукояти, -Z вперёд.
## Маркеры оружия как у CombatModels: Muzzle, Sight, Forend, Mag (магазин), Flame.
## Никаких реальных брендов: на кейсе — вымышленная эмблема шоу «Глаз».

const TIER_COLORS: Array[Color] = [Color(0.35, 0.85, 0.35), Color(0.62, 0.38, 1.0), Color(1.0, 0.3, 0.16)]
const TIER_NAMES: Array[String] = ["обычная", "редкая", "легендарная"]

static var _mats: Dictionary = {}

static func clear_caches() -> void:
	_mats.clear()

# ======================= материалы =======================

static func mat(kind: String) -> Material:
	if _mats.has(kind):
		return _mats[kind]
	var m: Material
	match kind:
		"steel": m = CombatModels.mat("iron")
		"walnut": m = CombatModels.mat("walnut_tip")
		"brass": m = CombatModels.mat("brass")
		"polymer": m = HeldModels.color_mat(Color(0.075, 0.075, 0.07), 0.62)
		"polymer_olive": m = HeldModels.color_mat(Color(0.25, 0.27, 0.18), 0.7)
		"case": # пластик кейса: тёмно-оливковый, с лёгкой фактурой ткани в шероховатости
			var c := HeldModels.pbr("Fabric004", Vector3(3.0, 3.0, 1.0), Color(0.3, 0.33, 0.22)).duplicate() as StandardMaterial3D
			c.albedo_texture = null
			c.roughness = 0.72
			m = c
		"case_dark": m = HeldModels.color_mat(Color(0.16, 0.17, 0.12), 0.75)
		"foam": m = HeldModels.color_mat(Color(0.07, 0.07, 0.075), 0.95)
		"strap": m = HeldModels.pbr("Fabric004", Vector3(1.0, 6.0, 1.0), Color(0.42, 0.38, 0.26))
		"buckle": m = HeldModels.color_mat(Color(0.12, 0.12, 0.12), 0.45, 0.6)
		"orange": m = HeldModels.color_mat(Color(0.95, 0.42, 0.08), 0.5)
		"red": m = HeldModels.color_mat(Color(0.72, 0.1, 0.08), 0.5)
		"blue_can": m = HeldModels.color_mat(Color(0.12, 0.3, 0.7), 0.35, 0.5)
		"white": m = HeldModels.color_mat(Color(0.92, 0.92, 0.88), 0.6)
		"chrome": m = HeldModels.color_mat(Color(0.8, 0.8, 0.82), 0.18, 1.0)
		"tin":
			m = HeldModels.color_mat(Color(0.74, 0.74, 0.72), 0.3, 0.9)
		"rubber": m = HeldModels.color_mat(Color(0.05, 0.05, 0.05), 0.9)
		"rubber_green": m = HeldModels.color_mat(Color(0.16, 0.2, 0.13), 0.85)
		"lens":
			var l := HeldModels.color_mat(Color(0.95, 0.95, 0.85), 0.05)
			l.emission_enabled = true
			l.emission = Color(1.0, 0.95, 0.8)
			l.emission_energy_multiplier = 0.6
			m = l
		"glass_blue":
			var g := HeldModels.color_mat(Color(0.2, 0.35, 0.45), 0.05, 0.3)
			m = g
		"screen":
			var s := HeldModels.color_mat(Color(0.3, 0.8, 0.35), 0.3)
			s.emission_enabled = true
			s.emission = Color(0.3, 0.9, 0.35)
			s.emission_energy_multiplier = 0.8
			m = s
		"canopy_white":
			var cw := HeldModels.color_mat(Color(0.9, 0.88, 0.82), 0.55)
			cw.cull_mode = BaseMaterial3D.CULL_DISABLED
			cw.backlight_enabled = true
			cw.backlight = Color(0.55, 0.53, 0.5)
			m = cw
		"line": m = HeldModels.color_mat(Color(0.85, 0.83, 0.78), 0.9)
		"plane":
			m = HeldModels.color_mat(Color(0.55, 0.57, 0.58), 0.45, 0.4)
		"plane_dark": m = HeldModels.color_mat(Color(0.22, 0.23, 0.24), 0.5, 0.3)
		"prop":
			var pm := HeldModels.color_mat(Color(0.1, 0.1, 0.1, 0.35), 0.5)
			pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			pm.cull_mode = BaseMaterial3D.CULL_DISABLED
			m = pm
		"paint": m = HeldModels.color_mat(Color(0.93, 0.9, 0.78), 0.8)
		"label_paper": m = HeldModels.color_mat(Color(0.86, 0.66, 0.2), 0.7)
		"cardboard": m = HeldModels.color_mat(Color(0.45, 0.42, 0.28), 0.9)
		"yellow": m = HeldModels.color_mat(Color(0.95, 0.75, 0.1), 0.55)
		_: m = HeldModels.color_mat(Color.MAGENTA)
	_mats[kind] = m
	return m

static func tier_mat(tier: int, cloth: bool = false) -> Material:
	var key := "tier%d%s" % [tier, "c" if cloth else ""]
	if _mats.has(key):
		return _mats[key]
	var c := TIER_COLORS[clampi(tier, 0, 2)]
	var m: StandardMaterial3D
	if cloth:
		m = HeldModels.color_mat(c, 0.55)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.backlight_enabled = true
		m.backlight = c * 0.6
	else:
		m = HeldModels.color_mat(c.darkened(0.1), 0.6)
	_mats[key] = m
	return m

# ======================= примитивы =======================

static func box(p: Node3D, size: Vector3, m: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	return HeldModels._box(p, size, m, pos, rot)

static func cyl(p: Node3D, r_top: float, r_bot: float, h: float, m: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, segs: int = 12) -> MeshInstance3D:
	return HeldModels._cyl(p, r_top, r_bot, h, m, pos, rot, segs)

static func tube(p: Node3D, pts: Array, rads: Array, m: Material, ref: Vector3 = Vector3.UP, segs: int = 10, nm: String = "") -> MeshInstance3D:
	var pa := PackedVector3Array()
	for v: Vector3 in pts:
		pa.append(v)
	var ra := []
	for r: Variant in rads:
		ra.append(r if r is Vector2 else Vector2(float(r), float(r)))
	return CombatModels.mesh(p, CombatModels.loft(pa, ra, ref, segs, 2.0), m, nm)

static func marker(p: Node3D, nm: String, pos: Vector3) -> void:
	CombatModels.marker(p, nm, pos)

static func label(p: Node3D, text: String, pos: Vector3, rot: Vector3, px: float, col: Color, size: int = 64) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = UITheme.font(true)
	l.font_size = size
	l.pixel_size = px
	l.modulate = col
	l.outline_size = 0
	l.position = pos
	l.rotation = rot
	l.double_sided = false
	l.shaded = true
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	p.add_child(l)
	return l

# ======================= предметы в руке =======================

## Callable для data["held"] (HeldModels._generic).
static func held(id: StringName) -> Callable:
	return _build.bind(id)

static func _build(id: StringName) -> Node3D:
	var r := Node3D.new()
	r.name = "Supply_" + String(id)
	match id:
		&"rifle": rifle(r)
		&"pistol_9mm": pistol_9mm(r)
		&"ammo_9mm": ammo_box_9mm(r)
		&"shotgun": shotgun(r)
		&"flare_gun": flare_gun(r)
		&"grenade": grenade(r)
		&"machete": machete(r)
		&"chainsaw": chainsaw(r)
		&"gas_torch": gas_torch(r)
		&"gas_can": gas_can(r)
		&"fuel_can": fuel_can(r)
		&"binoculars": binoculars(r)
		&"flashlight": flashlight(r)
		&"radio": radio(r)
		&"fins": fins(r)
		&"armor_vest": armor_vest(r)
		&"medkit": medkit(r)
		&"canned_food": canned(r)
		&"rifle_ammo": ammo_box(r)
		&"shotgun_shell": shells(r)
		&"flare": flare_shell(r)
		_: box(r, Vector3(0.08, 0.08, 0.08), mat("case"), Vector3.ZERO)
	return r

## Автомат (вымышленный, по мотивам классического АК): ствольная коробка, газовая трубка,
## деревянные цевьё и приклад, изогнутый магазин, дульный тормоз.
static func rifle(root: Node3D) -> void:
	var by := 0.062
	var steel := mat("steel")
	var wood := mat("walnut")
	# ствольная коробка + крышка
	box(root, Vector3(0.046, 0.064, 0.33), steel, Vector3(0, by - 0.012, -0.075))
	tube(root, [Vector3(0, by + 0.02, 0.085), Vector3(0, by + 0.024, -0.235)], [Vector2(0.012, 0.022), Vector2(0.012, 0.022)], steel, Vector3.UP, 10)
	# ПОДВИЖНЫЕ ДЕТАЛИ (контракт имён — WeaponDef: BoltCarrier / Trigger / Selector / Magazine).
	# Затворная рама с рукояткой взведения справа: на выстреле откатывается назад (+Z).
	var bolt := Node3D.new()
	bolt.name = "BoltCarrier"
	root.add_child(bolt)
	box(bolt, Vector3(0.006, 0.015, 0.075), steel, Vector3(0.0215, by + 0.008, -0.11)) # рама в окне ствольной коробки
	cyl(bolt, 0.005, 0.005, 0.03, steel, Vector3(0.033, by + 0.006, -0.135), Vector3(0, 0, PI / 2), 6) # рукоятка взведения
	box(bolt, Vector3(0.008, 0.009, 0.012), steel, Vector3(0.047, by + 0.006, -0.135)) # «грибок» рукоятки
	# переводчик-предохранитель: длинный рычаг справа, ось спереди; вверху — предохранитель,
	# ниже — автоматический, в самом низу — одиночный (поворот вокруг X)
	var sel := Node3D.new()
	sel.name = "Selector"
	sel.position = Vector3(0.026, by + 0.004, -0.068)
	root.add_child(sel)
	box(sel, Vector3(0.004, 0.016, 0.085), steel, Vector3(0.0, -0.004, 0.042))
	box(sel, Vector3(0.007, 0.01, 0.012), steel, Vector3(0.002, -0.012, 0.08)) # «полочка» под палец
	# ствол и дульный тормоз
	tube(root, [Vector3(0, by, -0.23), Vector3(0, by, -0.7)], [0.0115, 0.0105], steel, Vector3.UP, 12, "Barrel")
	tube(root, [Vector3(0, by, -0.66), Vector3(0, by, -0.73)], [0.0145, 0.014], steel, Vector3.UP, 10)
	# газовая трубка над стволом
	tube(root, [Vector3(0, by + 0.027, -0.24), Vector3(0, by + 0.027, -0.5)], [0.0095, 0.009], steel, Vector3.UP, 10)
	box(root, Vector3(0.022, 0.034, 0.03), steel, Vector3(0, by + 0.012, -0.505)) # газовый блок
	# цевьё: нижнее и верхняя накладка
	tube(root, [Vector3(0, by - 0.012, -0.245), Vector3(0, by - 0.014, -0.335), Vector3(0, by - 0.012, -0.455)],
		[Vector2(0.026, 0.022), Vector2(0.028, 0.024), Vector2(0.024, 0.021)], wood, Vector3.UP, 12)
	tube(root, [Vector3(0, by + 0.028, -0.25), Vector3(0, by + 0.028, -0.44)], [Vector2(0.013, 0.015), Vector2(0.012, 0.014)], wood, Vector3.UP, 10)
	# прицел: целик и мушка (одна высота — линия прицеливания параллельна стволу)
	box(root, Vector3(0.028, 0.03, 0.05), steel, Vector3(0, by + 0.035, -0.205))
	box(root, Vector3(0.004, 0.012, 0.01), steel, Vector3(0, by + 0.056, -0.205))
	box(root, Vector3(0.014, 0.05, 0.016), steel, Vector3(0, by + 0.03, -0.645))
	box(root, Vector3(0.003, 0.012, 0.004), steel, Vector3(0, by + 0.061, -0.645))
	# пистолетная рукоять (полимер) и спусковая скоба
	tube(root, [Vector3(0, by - 0.042, 0.02), Vector3(0, 0.0, 0.035), Vector3(0, -0.07, 0.062)],
		[Vector2(0.018, 0.014), Vector2(0.019, 0.015), Vector2(0.02, 0.016)], mat("polymer"), Vector3.BACK, 10)
	var tg := []
	var tr := []
	for i in 9:
		var a := PI * float(i) / 8.0
		tg.append(Vector3(0, by - 0.045 - sin(a) * 0.026, -0.02 + cos(a) * 0.04))
		tr.append(Vector2(0.003, 0.004))
	tube(root, tg, tr, steel, Vector3.RIGHT, 6)
	# спусковой крючок: ось сверху, при нажатии низ уходит назад
	var trg := Node3D.new()
	trg.name = "Trigger"
	trg.position = Vector3(0, by - 0.043, -0.026)
	root.add_child(trg)
	CombatModels.rod(trg, Vector3(0, -0.002, 0.0), Vector3(0, -0.019, 0.011), 0.0025, steel, 6)
	# приклад (дерево) с затыльником
	tube(root, [Vector3(0, by - 0.01, 0.085), Vector3(0, by - 0.02, 0.18), Vector3(0, by - 0.04, 0.3), Vector3(0, by - 0.05, 0.37)],
		[Vector2(0.024, 0.018), Vector2(0.03, 0.019), Vector2(0.045, 0.021), Vector2(0.052, 0.022)], wood, Vector3.UP, 12)
	box(root, Vector3(0.044, 0.11, 0.012), mat("polymer"), Vector3(0, by - 0.05, 0.376))
	# изогнутый магазин
	# магазин: узел «Magazine» с осью у переднего зацепа (АК: магазин «качают» вперёд)
	var mag := Node3D.new()
	mag.name = "Magazine"
	var mpiv := Vector3(0, by - 0.04, -0.06)
	mag.position = mpiv
	root.add_child(mag)
	var mp := []
	var mr := []
	for i in 7:
		var t := float(i) / 6.0
		var a := t * 0.55
		mp.append(Vector3(0, by - 0.04 - sin(a + 0.9) * 0.2 + sin(0.9) * 0.2, -0.075 - (1.0 - cos(a + 0.9)) * 0.2 + (1.0 - cos(0.9)) * 0.2) - mpiv)
		mr.append(Vector2(0.036, 0.0125))
	tube(mag, mp, mr, mat("steel"), Vector3.FORWARD, 8, "MagBody")
	marker(root, "Mag", Vector3(0, by - 0.1, -0.1))
	marker(root, "Sight", Vector3(0, by + 0.065, -0.205))
	marker(root, "Muzzle", Vector3(0, by, -0.74))
	marker(root, "Forend", Vector3(0, by - 0.035, -0.36))
	# GUNPLAY (WeaponDef): окно выброса гильз справа и точка совмещения прицела (целик–мушка)
	box(root, Vector3(0.003, 0.016, 0.05), mat("polymer"), Vector3(0.0235, by + 0.004, -0.11))
	marker(root, "ejection_port", Vector3(0.026, by + 0.006, -0.11))
	marker(root, "ads_anchor", Vector3(0, by + 0.064, -0.205))

## Современный пистолет 9 мм (вымышленный, полимерная рамка): затвор-кожух «Slide»
## (откатывается при выстреле, встаёт на задержку пустым), сокеты muzzle / ejection_port /
## ads_anchor, магазин «Mag».
static func pistol_9mm(root: Node3D) -> void:
	var by := 0.05
	var steel := HeldModels.color_mat(Color(0.11, 0.115, 0.12), 0.38, 0.75)
	var poly := mat("polymer")
	# рамка и рукоять
	box(root, Vector3(0.026, 0.02, 0.15), poly, Vector3(0, by - 0.021, -0.055))
	box(root, Vector3(0.022, 0.012, 0.04), poly, Vector3(0, by - 0.034, -0.105)) # планка под фонарь
	tube(root, [Vector3(0, by - 0.03, 0.02), Vector3(0, -0.005, 0.03), Vector3(0, -0.075, 0.048)],
		[Vector2(0.0145, 0.016), Vector2(0.0145, 0.017), Vector2(0.015, 0.018)], poly, Vector3.BACK, 10)
	box(root, Vector3(0.03, 0.012, 0.036), poly, Vector3(0, -0.083, 0.05), Vector3(-0.3, 0, 0)) # пятка магазина
	var mg := Node3D.new()
	mg.name = "Mag"
	mg.position = Vector3(0, -0.06, 0.042)
	root.add_child(mg)
	# спусковая скоба и спуск
	var tg := []
	var tr := []
	for i in 9:
		var a := PI * float(i) / 8.0
		tg.append(Vector3(0, by - 0.031 - sin(a) * 0.022, -0.01 + cos(a) * 0.03))
		tr.append(Vector2(0.0035, 0.004))
	tube(root, tg, tr, poly, Vector3.RIGHT, 6)
	CombatModels.rod(root, Vector3(0, by - 0.03, -0.012), Vector3(0, by - 0.047, -0.006), 0.0025, steel, 6)
	# затвор-кожух (подвижный)
	var sl := Node3D.new()
	sl.name = "Slide"
	root.add_child(sl)
	box(sl, Vector3(0.028, 0.03, 0.19), steel, Vector3(0, by + 0.004, -0.06))
	for k in 5:
		box(sl, Vector3(0.0285, 0.022, 0.0025), HeldModels.color_mat(Color(0.06, 0.06, 0.065), 0.6, 0.6),
			Vector3(0, by + 0.004, 0.022 - k * 0.006))
	box(sl, Vector3(0.002, 0.012, 0.045), HeldModels.color_mat(Color(0.03, 0.03, 0.03), 0.7), Vector3(0.0141, by + 0.008, -0.03)) # окно выброса
	# прицельные приспособления: целик с прорезью, мушка (точки)
	box(sl, Vector3(0.008, 0.008, 0.008), steel, Vector3(-0.007, by + 0.023, 0.028))
	box(sl, Vector3(0.008, 0.008, 0.008), steel, Vector3(0.007, by + 0.023, 0.028))
	box(sl, Vector3(0.004, 0.007, 0.006), steel, Vector3(0, by + 0.0225, -0.148))
	HeldModels._sphere(sl, 0.0012, mat("white"), Vector3(0, by + 0.024, -0.1512), Vector3.ONE, 6)
	# ствол виден в окне кожуха спереди
	cyl(root, 0.0068, 0.0068, 0.012, steel, Vector3(0, by, -0.151), Vector3(PI / 2, 0, 0), 10)
	cyl(root, 0.0045, 0.0045, 0.0125, HeldModels.color_mat(Color(0.01, 0.01, 0.01), 0.9), Vector3(0, by, -0.151), Vector3(PI / 2, 0, 0), 8)
	marker(sl, "ejection_port", Vector3(0.016, by + 0.01, -0.03))
	marker(root, "ads_anchor", Vector3(0, by + 0.026, 0.028)) # не на кожухе: прицел не дёргается при откате
	marker(root, "muzzle", Vector3(0, by, -0.16))

## Помповый дробовик: ствол + подствольный магазин, цевьё-помпа, полимерный приклад.
static func shotgun(root: Node3D) -> void:
	var by := 0.056
	var steel := mat("steel")
	var poly := mat("polymer")
	box(root, Vector3(0.046, 0.066, 0.24), steel, Vector3(0, by - 0.006, -0.06))
	tube(root, [Vector3(0, by + 0.002, -0.18), Vector3(0, by + 0.002, -0.74)], [0.0125, 0.0125], steel, Vector3.UP, 12, "Barrel")
	tube(root, [Vector3(0, by - 0.026, -0.18), Vector3(0, by - 0.026, -0.66)], [0.0115, 0.0115], steel, Vector3.UP, 10)
	cyl(root, 0.013, 0.013, 0.012, steel, Vector3(0, by - 0.026, -0.66), Vector3(PI / 2, 0, 0), 10)
	# помпа (рифлёная)
	var pump := Node3D.new()
	pump.name = "Pump"
	root.add_child(pump)
	tube(pump, [Vector3(0, by - 0.026, -0.29), Vector3(0, by - 0.028, -0.37), Vector3(0, by - 0.026, -0.45)],
		[Vector2(0.024, 0.022), Vector2(0.026, 0.024), Vector2(0.024, 0.022)], poly, Vector3.UP, 12)
	for k in 6:
		cyl(pump, 0.0255, 0.0255, 0.006, mat("rubber"), Vector3(0, by - 0.027, -0.31 - k * 0.025), Vector3(PI / 2, 0, 0), 12)
	# мушка-бусина и прицельная планка
	box(root, Vector3(0.008, 0.004, 0.5), steel, Vector3(0, by + 0.016, -0.46))
	HeldModels._sphere(root, 0.0035, mat("brass"), Vector3(0, by + 0.021, -0.72), Vector3.ONE, 8)
	# рукоять, скоба, спуск
	tube(root, [Vector3(0, by - 0.04, 0.03), Vector3(0, 0.0, 0.045), Vector3(0, -0.07, 0.07)],
		[Vector2(0.018, 0.014), Vector2(0.019, 0.015), Vector2(0.02, 0.016)], poly, Vector3.BACK, 10)
	var tg := []
	var tr := []
	for i in 9:
		var a := PI * float(i) / 8.0
		tg.append(Vector3(0, by - 0.04 - sin(a) * 0.024, -0.005 + cos(a) * 0.036))
		tr.append(Vector2(0.003, 0.004))
	tube(root, tg, tr, poly, Vector3.RIGHT, 6)
	tube(root, [Vector3(0, by - 0.008, 0.06), Vector3(0, by - 0.03, 0.2), Vector3(0, by - 0.05, 0.34)],
		[Vector2(0.026, 0.019), Vector2(0.042, 0.02), Vector2(0.056, 0.022)], poly, Vector3.UP, 12)
	box(root, Vector3(0.044, 0.115, 0.018), mat("rubber"), Vector3(0, by - 0.05, 0.35))
	marker(root, "Mag", Vector3(0, by - 0.03, -0.2))
	marker(root, "Sight", Vector3(0, by + 0.024, -0.02))
	marker(root, "Muzzle", Vector3(0, by + 0.002, -0.75))
	marker(root, "Forend", Vector3(0, by - 0.05, -0.37))

## Сигнальная ракетница: оранжевый пластик, толстый ствол.
static func flare_gun(root: Node3D) -> void:
	var by := 0.048
	var o := mat("orange")
	tube(root, [Vector3(0, by, 0.0), Vector3(0, by, -0.2)], [0.021, 0.02], o, Vector3.UP, 14, "Barrel")
	cyl(root, 0.017, 0.017, 0.004, mat("rubber"), Vector3(0, by, -0.2015), Vector3(PI / 2, 0, 0), 14)
	box(root, Vector3(0.036, 0.04, 0.08), o, Vector3(0, by - 0.006, 0.02))
	tube(root, [Vector3(0, by - 0.012, 0.015), Vector3(0, -0.02, 0.04), Vector3(0, -0.085, 0.07)],
		[Vector2(0.02, 0.015), Vector2(0.021, 0.016), Vector2(0.024, 0.018)], o, Vector3.BACK, 10)
	var tg := []
	var tr := []
	for i in 9:
		var a := PI * float(i) / 8.0
		tg.append(Vector3(0, by - 0.03 - sin(a) * 0.022, -0.035 + cos(a) * 0.03))
		tr.append(Vector2(0.004, 0.005))
	tube(root, tg, tr, o, Vector3.RIGHT, 6)
	box(root, Vector3(0.008, 0.02, 0.012), mat("polymer"), Vector3(0, by + 0.024, 0.045)) # курок
	box(root, Vector3(0.004, 0.008, 0.006), o, Vector3(0, by + 0.024, -0.19))
	marker(root, "Sight", Vector3(0, by + 0.03, 0.0))
	marker(root, "Muzzle", Vector3(0, by, -0.21))

static func grenade(root: Node3D) -> void:
	var pts := []
	var rr := []
	for i in 9:
		var t := float(i) / 8.0
		pts.append(Vector3(0, -0.04 + t * 0.085, 0))
		var r := sin(t * PI) * 0.03 + 0.008
		rr.append(Vector2(r, r))
	tube(root, pts, rr, mat("polymer_olive"), Vector3.FORWARD, 14)
	# насечки
	for k in 3:
		cyl(root, 0.0385, 0.0385, 0.004, mat("polymer_olive"), Vector3(0, -0.012 + k * 0.018, 0), Vector3.ZERO, 14)
	cyl(root, 0.011, 0.012, 0.024, mat("steel"), Vector3(0, 0.055, 0), Vector3.ZERO, 10)
	# спусковой рычаг и кольцо
	tube(root, [Vector3(0.008, 0.066, 0), Vector3(0.022, 0.06, 0), Vector3(0.034, 0.02, 0), Vector3(0.036, -0.01, 0)],
		[Vector2(0.002, 0.006), Vector2(0.002, 0.006), Vector2(0.002, 0.006), Vector2(0.002, 0.006)], mat("steel"), Vector3.FORWARD, 6)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.011
	tm.outer_radius = 0.014
	ring.mesh = tm
	ring.material_override = mat("chrome")
	ring.position = Vector3(-0.018, 0.06, 0)
	ring.rotation = Vector3(PI / 2, 0, 0)
	root.add_child(ring)
	marker(root, "Flame", Vector3(0, 0.07, 0))

## Мачете: полимерная рукоять, длинный клинок (лезвие вперёд, -Z), тёмный обух.
static func machete(root: Node3D) -> void:
	tube(root, [Vector3(0, -0.09, 0), Vector3(0, 0.0, 0.0), Vector3(0, 0.08, -0.002)],
		[Vector2(0.017, 0.013), Vector2(0.016, 0.012), Vector2(0.015, 0.012)], mat("polymer"), Vector3.FORWARD, 10)
	box(root, Vector3(0.026, 0.012, 0.05), mat("polymer"), Vector3(0, 0.085, -0.008))
	var pts := []
	var rr := []
	for i in 11:
		var t := float(i) / 10.0
		var w := lerpf(0.022, 0.032, smoothstep(0.2, 0.8, t))
		if t > 0.85:
			w *= lerpf(1.0, 0.25, (t - 0.85) / 0.15)
		pts.append(Vector3(0, 0.09 + t * 0.44, -w * 0.6 - 0.006))
		rr.append(Vector2(w, 0.0022))
	tube(root, pts, rr, mat("chrome"), Vector3.FORWARD, 8)
	# обух (воронёная полоса)
	box(root, Vector3(0.0045, 0.4, 0.007), mat("steel"), Vector3(0, 0.3, 0.004))

## Бензопила: корпус, задняя и передняя рукояти, шина с цепью. Корень — задняя рукоять.
static func chainsaw(root: Node3D) -> void:
	var o := mat("orange")
	var poly := mat("polymer")
	var body := Node3D.new()
	body.name = "Body"
	body.position = Vector3(0, -0.06, -0.12)
	root.add_child(body)
	box(body, Vector3(0.12, 0.15, 0.26), o, Vector3(0, 0, 0))
	box(body, Vector3(0.125, 0.06, 0.2), poly, Vector3(0, -0.06, 0.02))
	box(body, Vector3(0.13, 0.05, 0.1), poly, Vector3(0.0, 0.06, 0.06)) # крышка фильтра
	cyl(body, 0.03, 0.03, 0.02, mat("polymer"), Vector3(0.068, 0.0, 0.05), Vector3(0, 0, PI / 2), 12) # стартёр
	# задняя рукоять (корень на ней)
	tube(root, [Vector3(0, -0.02, 0.06), Vector3(0, 0.0, 0.03), Vector3(0, 0.0, -0.05), Vector3(0, -0.02, -0.08)],
		[0.016, 0.016, 0.016, 0.016], poly, Vector3.UP, 8)
	# передняя дуговая рукоять
	var arc := []
	var ar := []
	for i in 9:
		var a := PI * float(i) / 8.0
		arc.append(Vector3(cos(a) * 0.08, -0.06 + sin(a) * 0.09, -0.23))
		ar.append(0.012)
	tube(root, arc, ar, poly, Vector3.FORWARD, 8)
	# щиток
	box(root, Vector3(0.1, 0.09, 0.006), poly, Vector3(0, 0.03, -0.27), Vector3(deg_to_rad(-15.0), 0, 0))
	# шина и цепь
	box(root, Vector3(0.006, 0.055, 0.44), mat("chrome"), Vector3(0, -0.07, -0.47))
	box(root, Vector3(0.012, 0.062, 0.44), mat("steel"), Vector3(0, -0.07, -0.47))
	cyl(root, 0.031, 0.031, 0.012, mat("steel"), Vector3(0, -0.07, -0.69), Vector3(0, 0, PI / 2), 12)
	marker(root, "Muzzle", Vector3(0, -0.07, -0.6))

## Газовая горелка: синий баллон, латунный вентиль, изогнутое сопло.
static func gas_torch(root: Node3D) -> void:
	cyl(root, 0.032, 0.032, 0.15, mat("blue_can"), Vector3(0, -0.02, 0), Vector3.ZERO, 16)
	cyl(root, 0.022, 0.032, 0.025, mat("blue_can"), Vector3(0, 0.067, 0), Vector3.ZERO, 16)
	box(root, Vector3(0.05, 0.014, 0.003), mat("white"), Vector3(0, -0.01, -0.032)) # этикетка-полоса
	cyl(root, 0.014, 0.016, 0.03, mat("brass"), Vector3(0, 0.094, 0), Vector3.ZERO, 12)
	cyl(root, 0.013, 0.013, 0.012, mat("polymer"), Vector3(0.022, 0.1, 0), Vector3(0, 0, PI / 2), 10) # ручка регулятора
	tube(root, [Vector3(0, 0.105, 0), Vector3(0, 0.13, -0.02), Vector3(0, 0.15, -0.08), Vector3(0, 0.16, -0.13)],
		[0.009, 0.009, 0.0085, 0.0085], mat("chrome"), Vector3.UP, 10)
	cyl(root, 0.013, 0.01, 0.035, mat("chrome"), Vector3(0, 0.163, -0.145), Vector3(PI / 2 - 0.15, 0, 0), 12)
	marker(root, "Flame", Vector3(0, 0.166, -0.17))

static func gas_can(root: Node3D) -> void:
	cyl(root, 0.033, 0.033, 0.13, mat("blue_can"), Vector3(0, 0.0, 0), Vector3.ZERO, 16)
	cyl(root, 0.02, 0.033, 0.024, mat("blue_can"), Vector3(0, 0.077, 0), Vector3.ZERO, 16)
	cyl(root, 0.034, 0.034, 0.006, mat("tin"), Vector3(0, -0.064, 0), Vector3.ZERO, 16)
	cyl(root, 0.007, 0.007, 0.014, mat("brass"), Vector3(0, 0.095, 0), Vector3.ZERO, 8)
	box(root, Vector3(0.05, 0.03, 0.002), mat("white"), Vector3(0, 0.0, -0.033))

static func fuel_can(root: Node3D) -> void:
	box(root, Vector3(0.11, 0.16, 0.06), mat("red"), Vector3(0, 0.0, 0))
	for k in 2:
		box(root, Vector3(0.112, 0.008, 0.062), mat("red"), Vector3(0, -0.04 + k * 0.08, 0))
	tube(root, [Vector3(-0.04, 0.08, 0), Vector3(-0.03, 0.105, 0), Vector3(0.02, 0.105, 0), Vector3(0.03, 0.08, 0)],
		[0.008, 0.008, 0.008, 0.008], mat("red"), Vector3.FORWARD, 8)
	cyl(root, 0.012, 0.012, 0.02, mat("polymer"), Vector3(0.045, 0.09, 0), Vector3(0, 0, -0.5), 10)

static func binoculars(root: Node3D) -> void:
	for s: float in [-1.0, 1.0]:
		var x := 0.034 * s
		cyl(root, 0.024, 0.024, 0.1, mat("rubber_green"), Vector3(x, 0.02, -0.02), Vector3(PI / 2, 0, 0), 16)
		cyl(root, 0.026, 0.026, 0.018, mat("rubber"), Vector3(x, 0.02, -0.075), Vector3(PI / 2, 0, 0), 16)
		cyl(root, 0.021, 0.021, 0.002, mat("glass_blue"), Vector3(x, 0.02, -0.085), Vector3(PI / 2, 0, 0), 16)
		cyl(root, 0.015, 0.017, 0.03, mat("rubber"), Vector3(x, 0.02, 0.045), Vector3(PI / 2, 0, 0), 12)
	box(root, Vector3(0.03, 0.016, 0.07), mat("polymer"), Vector3(0, 0.03, -0.01))
	cyl(root, 0.008, 0.008, 0.018, mat("polymer"), Vector3(0, 0.04, 0.02), Vector3.ZERO, 10)

static func flashlight(root: Node3D) -> void:
	cyl(root, 0.015, 0.015, 0.14, mat("polymer"), Vector3(0, 0, 0.0), Vector3(PI / 2, 0, 0), 12)
	cyl(root, 0.022, 0.016, 0.045, mat("polymer"), Vector3(0, 0, -0.09), Vector3(PI / 2, 0, 0), 14)
	cyl(root, 0.019, 0.019, 0.003, mat("lens"), Vector3(0, 0, -0.113), Vector3(PI / 2, 0, 0), 14)
	cyl(root, 0.008, 0.008, 0.01, mat("rubber"), Vector3(0, 0, 0.074), Vector3(PI / 2, 0, 0), 8)
	for k in 4:
		cyl(root, 0.0158, 0.0158, 0.004, mat("rubber"), Vector3(0, 0, 0.02 - k * 0.012), Vector3(PI / 2, 0, 0), 12)
	marker(root, "Lens", Vector3(0, 0, -0.12))

static func radio(root: Node3D) -> void:
	box(root, Vector3(0.058, 0.11, 0.034), mat("polymer"), Vector3(0, 0.03, 0))
	box(root, Vector3(0.06, 0.03, 0.036), mat("rubber"), Vector3(0, -0.02, 0))
	box(root, Vector3(0.036, 0.018, 0.002), mat("screen"), Vector3(0, 0.068, -0.0175))
	for k in 5:
		box(root, Vector3(0.036, 0.0025, 0.002), mat("rubber"), Vector3(0, 0.045 - k * 0.007, -0.0175))
	cyl(root, 0.004, 0.006, 0.11, mat("rubber"), Vector3(0.018, 0.14, 0.004), Vector3.ZERO, 8)
	cyl(root, 0.008, 0.008, 0.012, mat("polymer"), Vector3(-0.016, 0.091, 0), Vector3.ZERO, 10)
	box(root, Vector3(0.004, 0.03, 0.012), mat("rubber"), Vector3(-0.031, 0.04, 0)) # тангента

static func fins(root: Node3D) -> void:
	for s: float in [-1.0, 1.0]:
		var f := Node3D.new()
		f.position = Vector3(0.05 * s, 0.0, 0.0)
		f.rotation = Vector3(0, 0, 0.08 * s)
		root.add_child(f)
		tube(f, [Vector3(0, 0, 0.06), Vector3(0, 0, -0.04)], [Vector2(0.035, 0.03), Vector2(0.04, 0.025)], mat("rubber"), Vector3.UP, 12)
		var pts := []
		var rr := []
		for i in 7:
			var t := float(i) / 6.0
			pts.append(Vector3(0, -0.01 - t * 0.02, -0.04 - t * 0.3))
			rr.append(Vector2(lerpf(0.04, 0.085, t), 0.004))
		tube(f, pts, rr, mat("yellow"), Vector3.RIGHT, 8)

static func armor_vest(root: Node3D) -> void:
	var olive := mat("polymer_olive")
	box(root, Vector3(0.28, 0.34, 0.045), olive, Vector3(0, 0.1, 0))
	box(root, Vector3(0.24, 0.3, 0.02), mat("case_dark"), Vector3(0, 0.1, -0.03))
	for k in 3:
		box(root, Vector3(0.07, 0.09, 0.03), olive, Vector3(-0.08 + k * 0.08, 0.0, -0.045)) # подсумки
	for s: float in [-1.0, 1.0]:
		box(root, Vector3(0.05, 0.12, 0.03), mat("strap"), Vector3(0.09 * s, 0.31, 0.0)) # лямки
	box(root, Vector3(0.12, 0.035, 0.002), mat("paint"), Vector3(0, 0.2, -0.041))

static func medkit(root: Node3D) -> void:
	var r := mat("red")
	box(root, Vector3(0.18, 0.12, 0.07), r, Vector3(0, 0.03, 0))
	box(root, Vector3(0.182, 0.008, 0.072), mat("polymer"), Vector3(0, 0.07, 0)) # молния
	box(root, Vector3(0.05, 0.016, 0.002), mat("white"), Vector3(0, 0.03, -0.036))
	box(root, Vector3(0.016, 0.05, 0.002), mat("white"), Vector3(0, 0.03, -0.036))
	tube(root, [Vector3(-0.04, 0.09, 0), Vector3(-0.02, 0.11, 0), Vector3(0.02, 0.11, 0), Vector3(0.04, 0.09, 0)],
		[Vector2(0.004, 0.012), Vector2(0.004, 0.012), Vector2(0.004, 0.012), Vector2(0.004, 0.012)], mat("strap"), Vector3.FORWARD, 6)

static func canned(root: Node3D) -> void:
	cyl(root, 0.036, 0.036, 0.1, mat("tin"), Vector3(0, 0.03, 0), Vector3.ZERO, 18)
	cyl(root, 0.0365, 0.0365, 0.07, mat("label_paper"), Vector3(0, 0.03, 0), Vector3.ZERO, 18)
	for y: float in [-0.02, 0.08]:
		cyl(root, 0.038, 0.038, 0.004, mat("tin"), Vector3(0, y, 0), Vector3.ZERO, 18)

static func ammo_box(root: Node3D) -> void:
	box(root, Vector3(0.08, 0.05, 0.05), mat("cardboard"), Vector3(0, 0.0, 0))
	for k in 4:
		cyl(root, 0.0045, 0.0045, 0.04, mat("brass"), Vector3(-0.024 + k * 0.016, 0.035, 0.0), Vector3.ZERO, 8)
		cyl(root, 0.003, 0.0045, 0.012, mat("steel"), Vector3(-0.024 + k * 0.016, 0.06, 0.0), Vector3.ZERO, 8)

static func ammo_box_9mm(root: Node3D) -> void:
	box(root, Vector3(0.07, 0.04, 0.045), HeldModels.color_mat(Color(0.25, 0.32, 0.45), 0.8), Vector3(0, 0.0, 0))
	for k in 5:
		cyl(root, 0.0048, 0.0048, 0.019, mat("brass"), Vector3(-0.024 + k * 0.012, 0.028, 0.0), Vector3.ZERO, 8)
		HeldModels._sphere(root, 0.0045, mat("brass"), Vector3(-0.024 + k * 0.012, 0.039, 0.0), Vector3(1, 1.3, 1), 8)

static func shells(root: Node3D) -> void:
	for k in 3:
		var p := Vector3(-0.025 + k * 0.025, 0.0, (k % 2) * 0.01)
		cyl(root, 0.0105, 0.0105, 0.055, mat("red"), p + Vector3(0, 0.01, 0), Vector3.ZERO, 12)
		cyl(root, 0.011, 0.011, 0.014, mat("brass"), p + Vector3(0, -0.02, 0), Vector3.ZERO, 12)

static func flare_shell(root: Node3D) -> void:
	cyl(root, 0.017, 0.017, 0.07, mat("orange"), Vector3(0, 0.01, 0), Vector3.ZERO, 14)
	cyl(root, 0.019, 0.019, 0.01, mat("brass"), Vector3(0, -0.028, 0), Vector3.ZERO, 14)
	cyl(root, 0.0172, 0.0172, 0.008, mat("red"), Vector3(0, 0.046, 0), Vector3.ZERO, 14)

# ======================= ящик спонсоров =======================

## Кейс 1.1×0.5×0.62 м. Узлы: "Lid" (откидывается, шарнир сзади), "Inside" (поролон).
## Цвет полосы и трафарет — по редкости.
static func crate(root: Node3D, tier: int, number: int) -> void:
	var W := 1.1
	var H := 0.5
	var D := 0.62
	var body_h := H * 0.68
	var cm := mat("case")
	var dark := mat("case_dark")
	# корпус: дно и стенки (внутри — пусто, видно поролон при открытой крышке)
	box(root, Vector3(W, 0.04, D), cm, Vector3(0, 0.02, 0))
	box(root, Vector3(W, body_h, 0.035), cm, Vector3(0, body_h * 0.5, D * 0.5 - 0.0175))
	box(root, Vector3(W, body_h, 0.035), cm, Vector3(0, body_h * 0.5, -D * 0.5 + 0.0175))
	box(root, Vector3(0.035, body_h, D), cm, Vector3(W * 0.5 - 0.0175, body_h * 0.5, 0))
	box(root, Vector3(0.035, body_h, D), cm, Vector3(-W * 0.5 + 0.0175, body_h * 0.5, 0))
	# рёбра жёсткости и полозья
	for x: float in [-0.4, -0.13, 0.13, 0.4]:
		box(root, Vector3(0.05, body_h * 0.92, D + 0.03), dark, Vector3(x, body_h * 0.5, 0))
	for z: float in [-0.2, 0.2]:
		box(root, Vector3(W - 0.06, 0.035, 0.06), dark, Vector3(0, -0.012, z))
	# поролон с вырезами
	var inside := Node3D.new()
	inside.name = "Inside"
	root.add_child(inside)
	box(inside, Vector3(W - 0.08, 0.02, D - 0.08), mat("foam"), Vector3(0, body_h - 0.09, 0))
	for k in 3:
		box(inside, Vector3(0.22, 0.012, 0.36), dark, Vector3(-0.3 + k * 0.3, body_h - 0.083, 0))
	# полоса редкости по корпусу
	box(root, Vector3(W + 0.004, 0.05, D + 0.034), tier_mat(tier), Vector3(0, body_h * 0.42, 0))
	# защёлки и ручки
	for x: float in [-0.3, 0.3]:
		box(root, Vector3(0.08, 0.06, 0.03), mat("buckle"), Vector3(x, body_h - 0.02, -D * 0.5 - 0.022))
	for s: float in [-1.0, 1.0]:
		tube(root, [Vector3(s * (W * 0.5 + 0.01), body_h * 0.62, -0.1), Vector3(s * (W * 0.5 + 0.04), body_h * 0.62, -0.06),
			Vector3(s * (W * 0.5 + 0.04), body_h * 0.62, 0.06), Vector3(s * (W * 0.5 + 0.01), body_h * 0.62, 0.1)],
			[0.012, 0.012, 0.012, 0.012], mat("buckle"), Vector3.UP, 6)
	# трафарет на боку
	label(root, "ПОСЫЛКА СПОНСОРОВ", Vector3(0, body_h * 0.74, -D * 0.5 - 0.019), Vector3(0, PI, 0), 0.0012, Color(0.92, 0.9, 0.78))
	label(root, "№ %03d  ·  %s" % [number, TIER_NAMES[clampi(tier, 0, 2)].to_upper()], Vector3(0, body_h * 0.2, -D * 0.5 - 0.019), Vector3(0, PI, 0), 0.0009, TIER_COLORS[clampi(tier, 0, 2)].lightened(0.2))
	label(root, "НЕ БРОСАТЬ  ↑", Vector3(W * 0.5 + 0.019, body_h * 0.74, 0), Vector3(0, PI / 2, 0), 0.0009, Color(0.92, 0.9, 0.78))
	label(root, "ШОУ «ОСТРОВА»", Vector3(-W * 0.5 - 0.019, body_h * 0.74, 0), Vector3(0, -PI / 2, 0), 0.0009, Color(0.92, 0.9, 0.78))
	# крышка на шарнире (задний край)
	var lid := Node3D.new()
	lid.name = "Lid"
	lid.position = Vector3(0, body_h, D * 0.5)
	root.add_child(lid)
	var lh := H - body_h
	box(lid, Vector3(W, lh * 0.7, D), cm, Vector3(0, lh * 0.35, -D * 0.5))
	box(lid, Vector3(W - 0.12, lh * 0.35, D - 0.12), cm, Vector3(0, lh * 0.82, -D * 0.5))
	for x: float in [-0.4, -0.13, 0.13, 0.4]:
		box(lid, Vector3(0.05, lh * 0.75, D + 0.03), dark, Vector3(x, lh * 0.38, -D * 0.5))
	box(lid, Vector3(W - 0.06, lh * 0.04, D - 0.06), mat("foam"), Vector3(0, -0.002, -D * 0.5))
	_emblem(lid, Vector3(0, lh + 0.002, -D * 0.5), tier)
	# ремни поверх (снимаются при открытии) — узел "Straps"
	var straps := Node3D.new()
	straps.name = "Straps"
	root.add_child(straps)
	for x: float in [-0.27, 0.27]:
		box(straps, Vector3(0.05, 0.006, D + 0.05), mat("strap"), Vector3(x, H + 0.003, 0))
		box(straps, Vector3(0.05, H + 0.02, 0.006), mat("strap"), Vector3(x, H * 0.5, D * 0.5 + 0.022))
		box(straps, Vector3(0.05, H + 0.02, 0.006), mat("strap"), Vector3(x, H * 0.5, -D * 0.5 - 0.022))
		box(straps, Vector3(0.06, 0.04, 0.012), mat("buckle"), Vector3(x, H * 0.75, -D * 0.5 - 0.026))
	# петля строп парашюта
	marker(root, "Rig", Vector3(0, H + 0.02, 0))

## Вымышленная эмблема шоу: «глаз» в круге (белая краска) + полосы редкости.
static func _emblem(p: Node3D, c: Vector3, tier: int) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.105
	tm.outer_radius = 0.125
	tm.rings = 24
	tm.ring_segments = 4
	ring.mesh = tm
	ring.material_override = mat("paint")
	ring.position = c
	ring.scale = Vector3(1, 0.05, 1)
	p.add_child(ring)
	# глаз: две «дуги» (сплющенная сфера) и зрачок
	HeldModels._sphere(p, 0.075, mat("paint"), c, Vector3(1.0, 0.03, 0.45), 16)
	HeldModels._sphere(p, 0.03, mat("case_dark"), c + Vector3(0, 0.003, 0), Vector3(1.0, 0.05, 1.0), 12)
	HeldModels._sphere(p, 0.012, tier_mat(tier), c + Vector3(0, 0.005, 0), Vector3(1.0, 0.05, 1.0), 10)
	for s: float in [-1.0, 1.0]:
		box(p, Vector3(0.18, 0.004, 0.035), tier_mat(tier), c + Vector3(0.33 * s, 0, 0))

## Купол парашюта (радиус R) со стропами к точке (0, -hang, 0). Узел "Canopy".
static func parachute(root: Node3D, tier: int, R: float = 3.2, hang: float = 4.2) -> void:
	var canopy := Node3D.new()
	canopy.name = "Canopy"
	root.add_child(canopy)
	var segs := 16
	var rings := 6
	var st := SurfaceTool.new()
	var mats: Array[Material] = [tier_mat(tier, true), mat("canopy_white")]
	for panel in 2:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for s in segs:
			if s % 2 != panel:
				continue
			for r in rings:
				var a0 := TAU * s / segs
				var a1 := TAU * (s + 1) / segs
				var t0 := float(r) / rings
				var t1 := float(r + 1) / rings
				var q: Array[Vector3] = [_dome(a0, t0, R), _dome(a1, t0, R), _dome(a1, t1, R), _dome(a0, t1, R)]
				st.set_uv(Vector2(0, t0)); st.add_vertex(q[0])
				st.set_uv(Vector2(1, t0)); st.add_vertex(q[1])
				st.set_uv(Vector2(1, t1)); st.add_vertex(q[2])
				st.set_uv(Vector2(0, t0)); st.add_vertex(q[0])
				st.set_uv(Vector2(1, t1)); st.add_vertex(q[2])
				st.set_uv(Vector2(0, t1)); st.add_vertex(q[3])
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = mats[panel]
		canopy.add_child(mi)
	# стропы: от кромки купола к общей точке над ящиком
	var lines := Node3D.new()
	lines.name = "Lines"
	root.add_child(lines)
	for s in segs:
		var a := TAU * s / segs
		var edge := _dome(a, 1.0, R)
		CombatModels.rod(lines, edge, Vector3(0, -hang, 0), 0.012, mat("line"), 4)
	for k in 4:
		var a2 := TAU * k / 4.0 + PI / 4
		CombatModels.rod(lines, Vector3(0, -hang, 0), Vector3(cos(a2) * 0.32, -hang - 0.5, sin(a2) * 0.22), 0.015, mat("strap"), 4)

## Точка купола: a — азимут, t — 0 (вершина) .. 1 (кромка). Кромка слегка гофрирована.
static func _dome(a: float, t: float, R: float) -> Vector3:
	var phi := t * deg_to_rad(68.0)
	var r := sin(phi) * R
	var y := cos(phi) * R * 0.62 - R * 0.62 * cos(deg_to_rad(68.0))
	var scallop := 1.0 - 0.06 * t * t * (0.5 + 0.5 * cos(a * 16.0))
	return Vector3(cos(a) * r * scallop, y, sin(a) * r * scallop)

## Дымовая шашка (цилиндр), стоит рядом с ящиком.
static func smoke_can(root: Node3D, tier: int) -> void:
	cyl(root, 0.035, 0.035, 0.13, mat("polymer_olive"), Vector3(0, 0.065, 0), Vector3.ZERO, 12)
	cyl(root, 0.036, 0.036, 0.03, tier_mat(tier), Vector3(0, 0.11, 0), Vector3.ZERO, 12)
	cyl(root, 0.012, 0.012, 0.02, mat("steel"), Vector3(0, 0.14, 0), Vector3.ZERO, 8)

# ======================= самолёт =======================

## Транспортный двухмоторный высокоплан (≈16 м). Нос — к -Z. Узлы "PropL"/"PropR" вращаются.
static func plane(root: Node3D) -> void:
	var pm := mat("plane")
	var dark := mat("plane_dark")
	var pts := []
	var rr := []
	var prof := [[-8.0, 0.25], [-7.4, 0.95], [-6.4, 1.25], [-2.0, 1.35], [3.0, 1.3], [5.5, 0.9], [7.6, 0.35], [8.0, 0.18]]
	for p in prof:
		var z := float(p[0])
		pts.append(Vector3(0, 0.25 * smoothstep(3.0, 8.0, z), z))
		rr.append(Vector2(float(p[1]), float(p[1]) * 0.95))
	tube(root, pts, rr, pm, Vector3.UP, 16)
	# кабина: остекление
	box(root, Vector3(1.6, 0.4, 0.8), mat("glass_blue"), Vector3(0, 0.95, -6.3), Vector3(deg_to_rad(-25.0), 0, 0))
	# крыло (верхнее) с законцовками
	box(root, Vector3(21.0, 0.32, 2.4), pm, Vector3(0, 1.45, -2.2))
	box(root, Vector3(21.2, 0.08, 0.3), dark, Vector3(0, 1.36, -1.1))
	# мотогондолы и винты
	for s: float in [-1.0, 1.0]:
		var x := 3.3 * s
		tube(root, [Vector3(x, 1.0, -5.2), Vector3(x, 1.05, -4.4), Vector3(x, 1.1, -1.6), Vector3(x, 1.2, -0.6)],
			[0.45, 0.62, 0.58, 0.3], pm, Vector3.UP, 12)
		var prop := Node3D.new()
		prop.name = "PropL" if s < 0 else "PropR"
		prop.position = Vector3(x, 1.0, -5.3)
		root.add_child(prop)
		var disc := MeshInstance3D.new()
		var dm := CylinderMesh.new()
		dm.top_radius = 1.6
		dm.bottom_radius = 1.6
		dm.height = 0.02
		dm.radial_segments = 24
		disc.mesh = dm
		disc.material_override = mat("prop")
		disc.rotation = Vector3(PI / 2, 0, 0)
		prop.add_child(disc)
		for k in 3:
			var blade := box(prop, Vector3(0.18, 1.6, 0.04), dark, Vector3.ZERO, Vector3(0, 0, TAU * k / 3.0))
			blade.position = Vector3(sin(TAU * k / 3.0) * -0.8, cos(TAU * k / 3.0) * 0.8, 0)
		cyl(prop, 0.25, 0.05, 0.4, dark, Vector3(0, 0, -0.15), Vector3(-PI / 2, 0, 0), 10)
	# хвост: стабилизатор и киль
	box(root, Vector3(7.5, 0.18, 1.6), pm, Vector3(0, 1.2, 7.0))
	box(root, Vector3(0.2, 3.0, 2.0), pm, Vector3(0, 2.3, 7.1), Vector3(deg_to_rad(-18.0), 0, 0))
	# грузовая рампа (приоткрыта) и шасси-обтекатели
	box(root, Vector3(1.8, 0.1, 2.6), dark, Vector3(0, -0.85, 5.2), Vector3(deg_to_rad(12.0), 0, 0))
	for s: float in [-1.0, 1.0]:
		box(root, Vector3(0.7, 0.6, 2.4), pm, Vector3(1.25 * s, -0.95, -0.8))
	# опознавательная эмблема шоу на киле и фюзеляже (вымышленная)
	for s: float in [-1.0, 1.0]:
		label(root, "ОСТРОВА · ПРЯМОЙ ЭФИР", Vector3(1.37 * s, 0.2, 0.0), Vector3(0, PI / 2 * s, 0), 0.02, Color(0.95, 0.85, 0.3), 64)
		var eye := Node3D.new()
		eye.position = Vector3(0.13 * s, 2.6, 7.4)
		eye.rotation = Vector3(0, 0, PI / 2 * -s)
		root.add_child(eye)
		_emblem_big(eye)
	marker(root, "Ramp", Vector3(0, -0.6, 6.4))

static func _emblem_big(p: Node3D) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.55
	tm.outer_radius = 0.65
	ring.mesh = tm
	ring.material_override = mat("paint")
	ring.scale = Vector3(1, 0.05, 1)
	p.add_child(ring)
	HeldModels._sphere(p, 0.4, mat("paint"), Vector3.ZERO, Vector3(1.0, 0.03, 0.45), 16)
	HeldModels._sphere(p, 0.16, mat("plane_dark"), Vector3(0, 0.01, 0), Vector3(1.0, 0.05, 1.0), 12)
