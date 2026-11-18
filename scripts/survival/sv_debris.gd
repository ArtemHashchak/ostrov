class_name SvDebris
extends SvStation
## Мусор, выброшенный морем на «мусорный берег» (после штормов приносит новый):
##   barrel  — бочка: E — забрать целиком (дождевая бочка), удары — доски + верёвка;
##   crate   — ящик: разбить (доски + случайный груз: ткань, верёвка, семена, бинт…);
##   bottles — бутылки и плёнка: E — собрать;
##   net     — сеть: E — разобрать на верёвку и волокно (ножом быстрее);
##   scrap   — металлолом: бить камнем/топором → ржавая жесть (пушка — много жести).

const CFG := {
	&"barrel": {"name": "Бочка, выброшенная морем", "hp": 45.0},
	&"crate": {"name": "Разбитый ящик", "hp": 35.0},
	&"bottles": {"name": "Бутылки и плёнка", "hp": 10.0},
	&"net": {"name": "Рыболовная сеть", "hp": 30.0},
	&"scrap": {"name": "Металлолом", "hp": 70.0},
}
const CRATE_LOOT := [
	[&"cloth", 2, 3.0], [&"rope", 2, 3.0], [&"seed_maize", 3, 2.0], [&"seed_melon", 2, 2.0],
	[&"bandage", 1, 1.5], [&"bottle_empty", 2, 2.0], [&"plastic_sheet", 1, 2.0], [&"scrap_metal", 1, 1.5],
	[&"seed_taro", 1, 1.0], [&"knife", 1, 0.4], [&"pot", 1, 0.3],
]

var seed_v := 0
var _net_left := 3
var cannon := false
var _scrap_hits := 0

func _ready() -> void:
	name = "SvDebris_" + String(kind)
	add_to_group(&"sv_debris")
	remove_from_group(&"buildable")
	var c: Dictionary = CFG.get(kind, CFG[&"crate"])
	max_hp = float(c.hp)
	model = SurvivalModels.debris(kind, seed_v)
	add_child(model)
	cannon = model.has_meta(&"cannon")
	if cannon:
		max_hp = 160.0
	hp = max_hp
	match kind:
		&"barrel": add_shape(Vector3(0.95, 0.7, 0.7))
		&"crate": add_shape(Vector3(0.7, 0.6, 0.7))
		&"bottles": add_shape(Vector3(1.0, 0.18, 1.0), Vector3.ZERO, true)
		&"net": add_shape(Vector3(1.4, 0.4, 1.2))
		&"scrap": add_shape(Vector3(1.8, 0.7, 0.9) if cannon else Vector3(1.1, 0.35, 1.0))

func display_name() -> String:
	if cannon:
		return "Ржавая пушка"
	return String(CFG.get(kind, {}).get("name", "Обломки"))

func get_interact_text(ch: Node) -> String:
	var n := display_name()
	match kind:
		&"barrel": return n + " — E: забрать бочку · удар: разбить на доски"
		&"bottles": return n + " — E: собрать"
		&"net": return n + " — E: разобрать%s" % (" ножом" if _has_blade(ch) else " (с ножом быстрее)")
		&"crate": return n + " — бей, чтобы вскрыть"
		&"scrap": return n + " — бей камнем или топором: жесть"
	return n

func _has_blade(ch: Node) -> bool:
	return Survival.count(ch, &"knife") > 0 or Survival.count(ch, &"glass_shard") > 0

func interact(ch: Node) -> void:
	match kind:
		&"barrel":
			Survival.give(ch, &"barrel", 1, global_position + Vector3.UP * 0.5)
			Survival.sfx(global_position, "res://assets/sounds/sfx-kit/foley-wood-touch.wav")
			queue_free()
		&"bottles":
			collect(ch)
		&"net":
			strip_net(ch)
		&"crate", &"scrap":
			toast(ch, "Разбей ударами")

func collect(ch: Node) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	Survival.give(ch, &"bottle_empty", 2 + rng.randi() % 2, global_position + Vector3.UP * 0.5)
	Survival.give(ch, &"plastic_sheet", 1, global_position + Vector3.UP * 0.5)
	if rng.randf() < 0.5:
		Survival.give(ch, &"glass_shard", 2, global_position + Vector3.UP * 0.5)
	Survival.sfx(global_position, "res://assets/sounds/combat/glass_break.wav")
	queue_free()

func strip_net(ch: Node) -> void:
	var blade := _has_blade(ch)
	Survival.give(ch, &"rope", 1, global_position + Vector3.UP * 0.5)
	Survival.give(ch, &"fiber", 3 if blade else 2, global_position + Vector3.UP * 0.5)
	_net_left -= 2 if blade else 1
	if _net_left <= 0:
		queue_free()
	else:
		_shake()

func on_hit(by: Node, hit: Dictionary) -> void:
	var tool := StringName(hit.get("tool", &"hand"))
	var dmg := float(hit.get("damage", 4.0))
	if kind == &"scrap":
		if tool in [&"hand", &"stick", &"spear"]:
			toast(by, "Нужен камень или топор")
			_shake()
			return
		# через удар отбивается лист жести
		_scrap_hits += 1
		if _scrap_hits % 2 == 0:
			Survival.give(by, &"scrap_metal", 1, global_position + Vector3.UP * 0.5)
	elif kind == &"net":
		strip_net(by)
		return
	elif kind == &"bottles":
		collect(by)
		return
	if tool == &"hand":
		dmg *= 0.3
	apply_damage(dmg, by, &"melee")

func on_broken(by: Node) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v * 31 + 7
	var at := global_position + Vector3.UP * 0.5
	match kind:
		&"barrel":
			Survival.give(by, &"plank", 3, at)
			Survival.give(by, &"rope", 1, at)
		&"crate":
			Survival.give(by, &"plank", 2 + rng.randi() % 2, at)
			var total := 0.0
			for e in CRATE_LOOT:
				total += float(e[2])
			for k in 2:
				var r := rng.randf() * total
				for e in CRATE_LOOT:
					r -= float(e[2])
					if r <= 0.0:
						Survival.give(by, e[0] as StringName, int(e[1]), at)
						break
		&"scrap":
			Survival.give(by, &"scrap_metal", 4 if cannon else 1, at)
