extends SeasonEvent
## Отравленный родник на сутки (24 мин). Компания либо называет остров (exact_warning_chance),
## либо намекает — и тогда каждому участнику приходит тест-полоска (water_test_kit: смотри на
## воду с полоской в руке и жми E). Признаки на месте: дохлая рыба кверху брюхом, дохлые
## лягушки на берегу, запах (подсказка в радиусе smell_r). Выпил/набрал — отравление (яд
## Survival). Боты обходят: если предупреждение было точным или они видят признаки (≤ 30 м).

const FISH_MESH := "res://assets/user_pack/sea/fish_tropical_spotted.res"
const FROG := "res://assets/user_pack/animals/frog/animal_frog.glb"

var spot := Vector3.INF
var radius := 6.0
var island_name := ""
var exact := false
var _smell_told: Dictionary = {}
var _decor: Node3D
var _bob_t := 0.0

func begin() -> void:
	var w := world()
	if w == null:
		done = true
		return
	_pick(w)
	if spot == Vector3.INF:
		done = true
		return
	exact = bool(cfg.get("exact", rng.randf() < float(cfg.get("exact_warning_chance", 0.55))))
	if exact:
		say(host_line("poison_exact", [island_name if island_name != "" else "без имени"]), true)
	else:
		say(host_line("poison_vague"), true)
		_give_kits()
	_make_signs(w)

func _pick(w: Node) -> void:
	var cands: Array[Dictionary] = []
	for n in get_tree().get_nodes_in_group(&"sv_fresh"):
		if n is Node3D:
			cands.append({"pos": (n as Node3D).global_position, "r": 3.2})
	for L: Dictionary in w.call(&"lakes"):
		cands.append({"pos": L.pos, "r": float(L.radius)})
	if cands.is_empty():
		return
	if cfg.has("pos"):
		var best := cands[0]
		for c in cands:
			if (c.pos as Vector3).distance_to(cfg.pos) < (best.pos as Vector3).distance_to(cfg.pos):
				best = c
		cands = [best]
	var c: Dictionary = cands[rng.randi_range(0, cands.size() - 1)]
	spot = c.pos
	radius = float(c.r)
	var I: Dictionary = w.call(&"island_at", spot.x, spot.z)
	island_name = String(I.get("name", ""))

func _give_kits() -> void:
	SeasonItems.register()
	for ch in characters():
		var inv := BuildEnv.inventory(ch)
		if inv and inv.has_method(&"add"):
			inv.call(&"add", &"water_test_kit", int(cfg.get("kit_per_player", 1)))

## Дохлая рыба на воде и лягушки на берегу.
func _make_signs(w: Node) -> void:
	_decor = Node3D.new()
	_decor.name = "PoisonSigns"
	add_child(_decor)
	var fish := load(FISH_MESH) as Mesh if ResourceLoader.exists(FISH_MESH) else null
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.72, 0.74, 0.7)
	fm.roughness = 0.35
	for i in 7:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.2, 0.75) * radius
		var p := spot + Vector3(cos(a) * r, 0.0, sin(a) * r)
		var mi := MeshInstance3D.new()
		if fish:
			mi.mesh = fish
			var ab := fish.get_aabb()
			var k := 0.22 / maxf(maxf(ab.size.x, ab.size.z), 0.001)
			mi.scale = Vector3.ONE * k
		else:
			var cm := CapsuleMesh.new()
			cm.radius = 0.04
			cm.height = 0.22
			mi.mesh = cm
		mi.material_override = fm
		_decor.add_child(mi)
		# кверху брюхом
		mi.global_position = Vector3(p.x, spot.y + 0.02, p.z)
		mi.rotation = Vector3(0.0, rng.randf() * TAU, PI)
	var frog_ps := load(FROG) as PackedScene if ResourceLoader.exists(FROG) else null
	if frog_ps:
		for i in 3:
			var a := rng.randf() * TAU
			var p := spot + Vector3(cos(a) * (radius + 0.8), 0.0, sin(a) * (radius + 0.8))
			var fr := frog_ps.instantiate() as Node3D
			_decor.add_child(fr)
			fr.global_position = Vector3(p.x, float(w.call(&"height_at", p.x, p.z)) + 0.05, p.z)
			fr.rotation = Vector3(0.0, rng.randf() * TAU, PI * 0.92)

func step(dt: float) -> void:
	_bob_t += dt
	if _decor:
		var i := 0
		for c in _decor.get_children():
			if c is MeshInstance3D:
				var gp := (c as Node3D).global_position
				gp.y = spot.y + 0.02 + sin(_bob_t * 1.3 + float(i)) * 0.012
				(c as Node3D).global_position = gp
				i += 1
	# запах — подсказка игроку
	for p in get_tree().get_nodes_in_group(&"player"):
		if p is Node3D and (p as Node3D).global_position.distance_to(spot) < radius + float(cfg.get("smell_r", 14.0)):
			var id := p.get_instance_id()
			if not _smell_told.has(id):
				_smell_told[id] = true
				Events.toast.emit("От воды тянет тухлым. На поверхности — дохлая рыба.")

func poisoned_at(pos: Vector3) -> bool:
	if spot == Vector3.INF:
		return false
	return Vector2(pos.x - spot.x, pos.z - spot.z).length() < radius + 3.5

func bot_knows(pos: Vector3, bot: Node) -> bool:
	if not poisoned_at(pos):
		return false
	if exact:
		return true
	return bot is Node3D and (bot as Node3D).global_position.distance_to(spot) < radius + 30.0

## Выпил или набрал отравленную воду.
func poison(ch: Node) -> void:
	var sv := Survival.instance()
	if sv and sv.has_method(&"apply_poison"):
		sv.apply_poison(ch, float(cfg.get("poison_dps", 1.2)), float(cfg.get("poison_time_s", 40)))
	else:
		Survival.set_poison(ch, float(cfg.get("poison_dps", 1.2)), float(cfg.get("poison_time_s", 40)))
	if ch.is_in_group(&"player"):
		Events.toast.emit("Вода была отравлена! Тошнит, кружится голова…")

func hud_line() -> String:
	if exact:
		return "Отравлен родник: остров «%s» (%s)" % [island_name, left_text()]
	return "Один из родников отравлен — проверяй воду полоской (%s)" % left_text()

func markers(_viewer: Node) -> Array[Dictionary]:
	if not exact or spot == Vector3.INF:
		return []
	return [{"pos": spot, "color": Color(0.55, 0.85, 0.2), "kind": &"event", "label": "Отравлено"}]
