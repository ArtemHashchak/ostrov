class_name GearWear
## Износ снаряжения от соли и воды (V5) и отсыревший порох.
## Состояние оружия хранится в слоте инвентаря: ключ "cond" (1 — как новое, 0 — сломано);
## намокание патронов/пороха — ключ "wet" (0..1).
## «Сутки» таблицы = DAY_S реальных секунд (матч ~4 ч, сутки ~20 мин).
## АК и револьвер (items_props weapon_wear.immortal) — почти бессмертны: ржавчина только
## снаружи (cond не ниже IMMORTAL_FLOOR, на стрельбу не влияет). 9 мм, AR-15 и прочие —
## осечки, заклинивания, поломка.
##   GearWear.tick(player, dt)                      — раз в кадр (BodyState)
##   GearWear.fire_check(player, weapon_id) -> &"ok" / &"misfire" / &"jam" / &"broken"
##   GearWear.condition(player, weapon_id) -> float

const DAY_S := 1200.0
const IMMORTAL_FLOOR := 0.9

static func _slot_of(p: Node, id: StringName) -> Dictionary:
	var inv: Variant = p.get(&"inventory")
	if inv == null:
		return {}
	var sel := int(inv.get(&"selected"))
	var slots: Array = inv.get(&"slots")
	if sel >= 0 and sel < slots.size() and StringName((slots[sel] as Dictionary).get("id", &"")) == id:
		return slots[sel]
	for s: Dictionary in slots:
		if StringName(s.get("id", &"")) == id:
			return s
	return {}

static func condition(p: Node, id: StringName) -> float:
	var s := _slot_of(p, id)
	return float(s.get("cond", 1.0)) if not s.is_empty() else 1.0

static func wear(id: StringName) -> Dictionary:
	return Materials.prop(id, "weapon_wear", {})

## Погружение (плавание/под водой) — соль; дождь — вода. Сушка пороха вне воды.
static func tick(p: Node, dt: float) -> void:
	var inv: Variant = p.get(&"inventory")
	if inv == null:
		return
	var in_sea := bool(p.get(&"swimming")) or (p.has_method(&"is_underwater") and bool(p.call(&"is_underwater")))
	var rain := Survival.rain()
	var dry := DataTables.f("balance", "weapons/powder_dry_per_h", 0.25) / 60.0
	for s: Dictionary in inv.get(&"slots"):
		if s.is_empty():
			continue
		var id := StringName(s.get("id", &""))
		var ww := wear(id)
		if not ww.is_empty():
			var rate := 0.0
			if in_sea:
				rate = float(ww.get("salt", 0.1))
			elif rain > 0.1:
				rate = float(ww.get("water", 0.03)) * rain
			if rate > 0.0:
				var floor_c := IMMORTAL_FLOOR if bool(ww.get("immortal", false)) else 0.0
				s["cond"] = maxf(floor_c, float(s.get("cond", 1.0)) - rate * dt / DAY_S)
				# видимая ржавчина (скин): растёт и у «бессмертных» — снаружи всё ржавеет
				s["rust"] = minf(1.0, float(s.get("rust", 0.0)) + maxf(rate, 0.1) * dt / DAY_S * 2.0)
		if bool(Materials.prop(id, "gunpowder", false)) or id == &"gunpowder":
			var wp := float(Materials.prop(id, "waterproof", 0.0))
			if in_sea and wp < 0.9:
				s["wet"] = 1.0
			elif rain > 0.3 and wp < 0.5 and id == &"gunpowder":
				s["wet"] = minf(1.0, float(s.get("wet", 0.0)) + rain * dt / 120.0)
			elif float(s.get("wet", 0.0)) > 0.0:
				s["wet"] = maxf(0.0, float(s.get("wet", 0.0)) - dry * dt)

## Перед выстрелом игрока: осечка (мокрый порох / изношенный ствол), заклинивание, поломка.
static func fire_check(p: Node, weapon_id: StringName, ammo_id: StringName = &"") -> StringName:
	var ww := wear(weapon_id)
	var cond := condition(p, weapon_id)
	var immortal := bool(ww.get("immortal", false))
	if not immortal and not ww.is_empty():
		if cond <= DataTables.f("balance", "weapons/break_at_condition", 0.08):
			return &"broken"
		var jam_at := DataTables.f("balance", "weapons/jam_at_condition", 0.6)
		if cond < jam_at and randf() < (jam_at - cond) / jam_at * 0.35:
			return &"jam"
		if cond < 0.8 and randf() < (0.8 - cond) * DataTables.f("balance", "weapons/misfire_per_missing", 0.5) * 0.3:
			return &"misfire"
	if ammo_id != &"":
		var s := _slot_of(p, ammo_id)
		var wet := float(s.get("wet", 0.0)) if not s.is_empty() else 0.0
		if wet > 0.0 and randf() < wet * DataTables.f("balance", "weapons/wet_powder_misfire", 0.6):
			return &"misfire"
	return &"ok"

## Почистить и смазать (позже — предмет «масло»): вернуть состояние.
static func service(p: Node, weapon_id: StringName, amount: float = 0.3) -> void:
	var s := _slot_of(p, weapon_id)
	if not s.is_empty():
		s["cond"] = minf(1.0, float(s.get("cond", 1.0)) + amount)
		s["rust"] = maxf(0.0, float(s.get("rust", 0.0)) - amount)
