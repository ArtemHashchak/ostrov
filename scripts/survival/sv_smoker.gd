class_name SvSmoker
extends SvStation
## Коптильня-сушилка: до 6 кусков сырого мяса/рыбы на вешалах над тлеющим огнём.
## Топливо — палки (тлеет медленно). Копчёное хранится ~2 часа.

const SLOTS := 6
const SMOKE_TIME := 150.0
const FUEL_PER_STICK := 200.0
const FUEL_MAX := 1200.0

var fuel := 0.0
var racks: Array[Dictionary] = [] # {id, t, out}
var _strips: Node3D
var _smoke: CPUParticles3D
var _embers: Node3D
var _dirty := true

func _ready() -> void:
	kind = &"smoker"
	name = "SvSmoker"
	max_hp = 70.0
	hp = max_hp
	salvage = {&"stick": 4, &"rope": 1}
	model = Node3D.new()
	add_child(model)
	SurvivalModels.smoker(model)
	add_shape(Vector3(1.6, 1.7, 1.2))
	_strips = Node3D.new()
	add_child(_strips)
	_smoke = SurvivalModels.smoke_only(self, Vector3(0, 0.35, 0), Color(0.42, 0.4, 0.38, 0.3), 16, 0.7)
	_embers = SurvivalModels.fire(self, 0.45, Vector3(0, 0.05, 0))
	_apply()

func smoldering() -> bool:
	return fuel > 0.0

func _apply() -> void:
	_smoke.emitting = smoldering()
	_embers.visible = smoldering()
	for c in _embers.get_children():
		if c is CPUParticles3D:
			(c as CPUParticles3D).emitting = smoldering()

func tick(dt: float) -> void:
	if fuel > 0.0:
		fuel = maxf(0.0, fuel - dt * (1.0 + Survival.rain()))
		if fuel <= 0.0:
			_apply()
		for r in racks:
			var q0 := int(float(r.t) / SMOKE_TIME * 4.0)
			r.t = float(r.t) + dt
			if int(float(r.t) / SMOKE_TIME * 4.0) != q0:
				_dirty = true
	if _dirty:
		_rebuild()

func _rebuild() -> void:
	_dirty = false
	for c in _strips.get_children():
		c.queue_free()
	for i in racks.size():
		var r := racks[i]
		var k := &"meat" if String(r.id).begins_with("meat") else &"fish"
		var mi := SurvivalModels.strip(k, float(r.t) / SMOKE_TIME)
		mi.position = Vector3(-0.42 + float(i % 3) * 0.42, 1.12, -0.2 + float(i / 3) * 0.4)
		mi.rotation.y = 0.3 * float(i % 2)
		_strips.add_child(mi)

func ready_count() -> int:
	var n := 0
	for r in racks:
		if float(r.t) >= SMOKE_TIME:
			n += 1
	return n

func smokable(id: StringName) -> bool:
	return Survival.data(id).has("smoke")

func get_interact_text(ch: Node) -> String:
	if ready_count() > 0:
		return "Коптильня — E: снять готовое (%d)" % ready_count()
	var bits := "дым %d с" % int(fuel) if smoldering() else "огонь не горит"
	var act := ""
	var raw := _first_raw(ch)
	if raw != &"" and racks.size() < SLOTS:
		act = "E: повесить «%s»" % iname(raw)
	elif fuel < FUEL_MAX - FUEL_PER_STICK and Survival.count(ch, &"stick") > 0:
		act = "E: подбросить палку"
	return "Коптильня (%s, на вешалах %d/%d)%s" % [bits, racks.size(), SLOTS, (" — " + act) if act != "" else ""]

func _first_raw(ch: Node) -> StringName:
	if smokable(held(ch)):
		return held(ch)
	var inv := Survival.inv(ch)
	if inv:
		for s in inv.slots:
			if not s.is_empty() and smokable(StringName(s.id)):
				return StringName(s.id)
	return &""

func interact(ch: Node) -> void:
	if ready_count() > 0:
		var keep: Array[Dictionary] = []
		for r in racks:
			if float(r.t) >= SMOKE_TIME:
				Survival.give(ch, StringName(r.out), 1, global_position + Vector3.UP)
			else:
				keep.append(r)
		racks = keep
		_dirty = true
		return
	var raw := _first_raw(ch)
	if held(ch) != &"stick" and raw != &"" and racks.size() < SLOTS:
		hang(ch, raw)
		return
	if Survival.count(ch, &"stick") > 0 and fuel < FUEL_MAX - FUEL_PER_STICK * 0.5:
		add_fuel(ch)
		return
	if not smoldering():
		toast(ch, "Нужны палки — разжечь дымный огонь")

## Повесить все куски вида id, сколько влезет.
func hang(ch: Node, id: StringName) -> int:
	var n := mini(SLOTS - racks.size(), Survival.count(ch, id))
	if n <= 0 or not Survival.take(ch, id, n):
		return 0
	for i in n:
		racks.append({"id": id, "t": 0.0, "out": StringName(Survival.data(id).get("smoke"))})
	_dirty = true
	toast(ch, "На вешалах: %s ×%d%s" % [iname(id), n, "" if smoldering() else " (разожги огонь палками)"])
	return n

func add_fuel(ch: Node) -> bool:
	if not Survival.take(ch, &"stick", 1):
		return false
	fuel = minf(FUEL_MAX, fuel + FUEL_PER_STICK)
	_apply()
	toast(ch, "Огонь в коптильне тлеет")
	return true

func on_broken(by: Node) -> void:
	for r in racks:
		Survival.give(by, StringName(r.out if float(r.t) >= SMOKE_TIME else r.id), 1, global_position + Vector3.UP)
