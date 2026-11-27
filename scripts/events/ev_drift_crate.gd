extends SeasonEvent
## Дрейфующий ящик: посылка спонсоров «упала в море» и плывёт на деревянной лодке по
## течению (направление — от ветра с поворотом, ~0,45 м/с). Цветной дым, метка на карте,
## объявление со стороной света. Кто первый доплывёт и вскроет (E ~3 с) — того и добыча.
## Боты гонятся (BotBrain: ящики с meta drift, радиус chase_r, по воде).

const BOAT := "res://assets/user_pack/vehicles/vehicle_wooden_boat.glb"

var crate: SupplyCrate
var drift := Vector3.ZERO

func begin() -> void:
	var w := world()
	if w == null:
		done = true
		return
	var p := player()
	var c := p.global_position if p else Vector3.ZERO
	var wd: Vector2 = w.call(&"wind_dir")
	var cur := wd.rotated(deg_to_rad(rng.randf_range(-35.0, 35.0)))
	if cur.length() < 0.1:
		cur = Vector2.RIGHT.rotated(rng.randf() * TAU)
	cur = cur.normalized()
	drift = Vector3(cur.x, 0.0, cur.y) * float(cfg.get("drift_ms", 0.45))
	var pos := Vector3.INF
	var dr: Array = cfg.get("dist_m", [280, 560])
	for i in 80:
		# старт — выше по течению от игрока, чтобы ящик шёл к людям
		var a := atan2(-cur.y, -cur.x) + rng.randf_range(-1.1, 1.1)
		var r := rng.randf_range(float(dr[0]), float(dr[1]))
		var q := Vector3(c.x + cos(a) * r, 0.0, c.z + sin(a) * r)
		if cfg.has("pos"):
			q = cfg.pos
		if bool(w.call(&"sea_ok", q.x, q.z, 3.0)) or cfg.has("pos"):
			pos = q
			break
	if pos == Vector3.INF:
		done = true
		return
	crate = SupplyCrate.new()
	crate.name = "DriftCrate"
	crate.tier = int(cfg.get("tier", 1))
	crate.number = 900 + rng.randi_range(0, 99)
	crate.island_name = ""
	var srng := RandomNumberGenerator.new()
	srng.seed = rng.randi()
	crate.loot = SupplyItems.roll_loot(crate.tier, srng)
	crate.set_meta(&"drift", drift)
	crate.set_meta(&"float_lift", 0.42)
	crate.set_meta(&"chase_r", float(cfg.get("bot_chase_r", 380.0)))
	var host: Node = w.get_parent() if w.get_parent() else self
	host.add_child(crate)
	var ws := float(w.call(&"water_level"))
	crate.global_position = Vector3(pos.x, ws - 0.25, pos.z)
	# лодка под ящиком (модель лодок ботов)
	var ps := load(BOAT) as PackedScene if ResourceLoader.exists(BOAT) else null
	if ps:
		var boat := ps.instantiate() as Node3D
		boat.name = "DriftBoat"
		crate.add_child(boat)
		var ab := BotBoat._aabb_of(boat)
		var k := 3.6 / maxf(maxf(ab.size.x, ab.size.z), 0.01)
		boat.scale = Vector3.ONE * k
		if ab.size.x > ab.size.z:
			boat.rotation.y = PI * 0.5
		var cc := ab.get_center()
		if ab.size.x > ab.size.z:
			cc = Vector3(cc.z, cc.y, -cc.x)
		boat.position = Vector3(-cc.x * k, -BotBoat._hull_bottom(boat) * k - 0.42 - 0.06, -cc.z * k)
	crate.opened.connect(func(_c: SupplyCrate, by: Node) -> void:
		if by:
			director.call(&"award", by, &"airdrop_claimed", 25.0, [&"risky"])
		done = true)
	say(host_line("drift_crate", [where(pos)]), true)

func step(_dt: float) -> void:
	if crate == null or not is_instance_valid(crate):
		done = true

func finish() -> void:
	# не вскрыли — ящик уходит в открытый океан и тонет
	if crate and is_instance_valid(crate) and crate.state != SupplyCrate.State.OPENED:
		crate.queue_free()
	super.finish()

func hud_line() -> String:
	if crate == null or not is_instance_valid(crate):
		return ""
	return "Дрейфующий ящик — %s (%s)" % [where(crate.global_position), left_text()]

func markers(_viewer: Node) -> Array[Dictionary]:
	if crate == null or not is_instance_valid(crate):
		return []
	return [{"pos": crate.global_position, "color": Color(0.4, 0.7, 1.0), "kind": &"event", "label": "Ящик на лодке"}]
