class_name WaterContainers
## Вода в таре (V5). Лестница ёмкостей — MechItems (плошка кокоса 0,3 л → колено бамбука
## 0,8 → панцирь черепахи 1,0 → тыква 2,0 → бутылка 1,5 → канистра 20 л / бочка / тент).
## Мелкая тара — схема SURVIVAL «пустая ↔ полная» (fill_fresh/fill_salt/returns).
## Открытая тара (data.open): на бегу расплёскивается, в воде — заливает морской,
## у прибоя волна может испортить пресную, на солнце испаряется. Канистра хранит объём в
## слоте (ключи "l", "liq": fresh/salt): набрать у воды, налить в пустую мелкую тару или отпить.
## Ставки — assets/data/balance.json, раздел water.

static func _data(id: StringName) -> Dictionary:
	var d := Items.get_item(id)
	return d.data if d else {}

static func is_open_filled(id: StringName) -> bool:
	var dd := _data(id)
	return bool(dd.get("open", false)) and dd.has("returns") and float(dd.get("container_l", 0.0)) > 0.0

static func _b(k: String, d: float) -> float:
	return DataTables.f("balance", "water/" + k, d)

## Раз в кадр для игрока (BodyState).
static func tick(p: Node, dt: float) -> void:
	var inv: Variant = p.get(&"inventory")
	if inv == null:
		return
	var swimming := bool(p.get(&"swimming"))
	var running := bool(p.get(&"sprinting"))
	var in_surf := false
	if p is Node3D and not swimming:
		in_surf = (p as Node3D).global_position.y < BuildEnv.water_level() + 0.2
	var sun := 0.0
	var w := BuildEnv.world()
	if w and w.has_method(&"sun_elevation"):
		sun = clampf(float(w.call(&"sun_elevation")), 0.0, 1.0)
	var slots: Array = inv.get(&"slots")
	for i in slots.size():
		var s: Dictionary = slots[i]
		if s.is_empty():
			continue
		var id := StringName(s.get("id", &""))
		var n := int(s.get("n", 0))
		if n <= 0 or not is_open_filled(id):
			continue
		var dd := _data(id)
		var empty := StringName(dd.returns)
		var salt_id := StringName(_data(empty).get("fill_salt", &""))
		var fresh := StringName(dd.get("liquid", &"fresh")) == &"fresh" or id == &"shell_water"
		if swimming:
			# в море открытая тара заливается солёной
			if fresh and salt_id != &"":
				_swap(inv, i, salt_id, n)
			continue
		var p_spill := 0.0
		if running:
			p_spill = _b("spill_run_per_s", 0.03)
		if sun > 0.6:
			p_spill += _b("evap_open_per_h_sun", 0.08) / 60.0 * sun
		if p_spill > 0.0 and randf() < p_spill * dt * n:
			_swap(inv, i, empty, 1)
			continue
		if in_surf and fresh and salt_id != &"" and randf() < _b("contaminate_wave_chance", 0.3) * 0.05 * dt:
			_swap(inv, i, salt_id, 1)

## Заменить k предметов слота i на other (то же место в инвентаре, если весь слот).
static func _swap(inv: Variant, i: int, other: StringName, k: int) -> void:
	var s: Dictionary = (inv.get(&"slots") as Array)[i]
	var id := StringName(s.id)
	if inv.has_method(&"remove") and inv.has_method(&"add"):
		inv.call(&"remove", id, k)
		inv.call(&"add", other, k)

# ---------------- канистра ----------------

static func big_slot(p: Node, id: StringName) -> Dictionary:
	return GearWear._slot_of(p, id)

static func litres(p: Node, id: StringName) -> float:
	return float(big_slot(p, id).get("l", 0.0))

## Набрать в канистру (у воды): пресная/морская; смешивание — морская.
static func fill_big(p: Node, id: StringName, fresh: bool) -> float:
	var s := big_slot(p, id)
	if s.is_empty():
		return 0.0
	var cap := float(_data(id).get("container_l", 20.0))
	var had := float(s.get("l", 0.0))
	s["l"] = cap
	if had <= 0.01:
		s["liq"] = &"fresh" if fresh else &"salt"
	elif not fresh:
		s["liq"] = &"salt"
	return cap - had

## ПКМ с канистрой: налить в первую пустую мелкую тару; нет тары — отпить 0,25 л.
static func use_big(p: Node, id: StringName) -> String:
	var s := big_slot(p, id)
	var l := float(s.get("l", 0.0))
	if l <= 0.01:
		return "Канистра пуста — набери воды у берега/родника (E)"
	var liq := StringName(s.get("liq", &"fresh"))
	var inv: Variant = p.get(&"inventory")
	for t: Dictionary in inv.get(&"slots"):
		if t.is_empty():
			continue
		var tid := StringName(t.get("id", &""))
		var td := _data(tid)
		if td.has("fill_fresh") and not td.has("big_container"):
			var cap := float(td.get("container_l", 0.5))
			if l + 0.001 < cap:
				continue
			var to := StringName(td.get("fill_fresh" if liq == &"fresh" else "fill_salt"))
			inv.call(&"remove", tid, 1)
			inv.call(&"add", to, 1)
			s["l"] = l - cap
			return "Налил %.1f л в «%s»" % [cap, Items.item_name(tid)]
	var dl := minf(l, _b("drink_l", 0.25))
	s["l"] = l - dl
	if liq == &"fresh":
		p.set(&"thirst", minf(100.0, float(p.get(&"thirst")) + dl * _b("thirst_per_l", 35.0)))
		return "Отпил из канистры (осталось %.1f л)" % float(s["l"])
	var sv := Survival.instance()
	if sv:
		sv.apply_salt(p)
	return "Солёная! (осталось %.1f л)" % float(s["l"])
