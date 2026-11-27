extends SeasonEvent
## Цунами. Признаки: море уходит от берега (~1–2 мин, обнажается дно у пляжей), птицы
## взлетают; ведущий предупреждает. Потом из открытого океана через архипелаг идёт волна
## (стена воды с пеной): где фронт проходит по низкому берегу/воде — сносит людей и ботов по
## ходу волны с уроном, разбивает лодки, уносит предметы; море поднимается на surge_m и
## медленно спадает. Уровень моря — World.event_sea_offset (минимальная правка мира).
## Боты в фазе предупреждения уходят наверх (BotBrain: задание «evade»).

const WALL_SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_draw_always;
uniform vec4 deep : source_color = vec4(0.05, 0.22, 0.27, 0.92);
uniform vec4 foam : source_color = vec4(0.93, 0.96, 0.97, 1.0);
varying vec3 lp;
float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float n2(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
void vertex() {
	lp = VERTEX;
	// гребень: передняя кромка наклонена вперёд, по длине — неровно
	float up = clamp(VERTEX.y / 4.0 + 0.5, 0.0, 1.0);
	VERTEX.z -= up * up * 3.5;
	VERTEX.y += sin(VERTEX.x * 0.031 + TIME * 0.7) * 0.6 + n2(vec2(VERTEX.x * 0.02, TIME * 0.3)) * 1.2 * up;
}
void fragment() {
	float up = clamp(lp.y / 4.0 + 0.5, 0.0, 1.0);
	float f = smoothstep(0.62, 0.9, up + n2(vec2(lp.x * 0.15, lp.z * 0.3 + TIME * 2.0)) * 0.25);
	vec3 c = mix(deep.rgb, foam.rgb, f);
	ALBEDO = c;
	ROUGHNESS = mix(0.08, 0.7, f);
	SPECULAR = 0.6;
	float ends = smoothstep(0.0, 0.06, UV.x) * smoothstep(1.0, 0.94, UV.x);
	ALPHA = mix(deep.a, 1.0, f) * ends;
}
"""

var dir := Vector2.RIGHT
var phase := "withdraw"
var front := 0.0        # проекция фронта на dir, м
var _start_front := 0.0
var _end_front := 0.0
var _hit: Dictionary = {}   # instance_id → true (уже накрыло)
var _sweeps: Array[Dictionary] = []  # {node, left, v}
var _wall: MeshInstance3D
var _phase_t := 0.0
var _hit_said := false

func begin() -> void:
	var w := world()
	if w == null or not (&"event_sea_offset" in w):
		done = true
		return
	var a := float(cfg.get("dir_deg", rng.randf() * 360.0))
	dir = Vector2(cos(deg_to_rad(a)), sin(deg_to_rad(a)))
	var half := ArchipelagoV5.HALF
	_start_front = -half * 1.45 - 200.0
	_end_front = half * 1.45 + 200.0
	front = _start_front
	duration = float(cfg.get("withdraw_s", 80)) + (_end_front - _start_front) / float(cfg.get("front_speed", 38.0)) \
		+ float(cfg.get("surge_hold_s", 40)) + float(cfg.get("recede_s", 150)) + 5.0
	say(host_line("tsunami_warn"), true)
	# птицы и звери чуют заранее
	var pl := player()
	if pl:
		Perception.shot(pl.global_position, null, 2.5)

func info() -> Dictionary:
	return {"phase": phase, "dir": dir, "front": front}

func step(dt: float) -> void:
	var w := world()
	if w == null:
		return
	_phase_t += dt
	var wd := float(cfg.get("withdraw_s", 80))
	var wm := float(cfg.get("withdraw_m", -2.6))
	var sm := float(cfg.get("surge_m", 2.8))
	match phase:
		"withdraw":
			w.set(&"event_sea_offset", wm * smoothstep(0.0, wd * 0.7, _phase_t))
			if _phase_t >= wd:
				_set_phase("wave")
				_make_wall()
		"wave":
			front += float(cfg.get("front_speed", 38.0)) * dt
			_place_wall(w)
			# у камеры вода поднимается, когда фронт рядом/прошёл
			var cam := get_viewport().get_camera_3d()
			var cp := Vector2(cam.global_position.x, cam.global_position.z) if cam else Vector2.ZERO
			var rel := front - cp.dot(dir)   # >0 — фронт уже прошёл камеру
			var k := smoothstep(-160.0, 30.0, rel)
			w.set(&"event_sea_offset", lerpf(wm, sm, k))
			_apply_front(w)
			if not _hit_said and rel > -120.0:
				_hit_said = true
				say(host_line("tsunami_hit"), true)
			if front >= _end_front:
				w.set(&"event_sea_offset", sm)
				_set_phase("surge")
				if _wall:
					_wall.queue_free()
					_wall = null
		"surge":
			if _phase_t >= float(cfg.get("surge_hold_s", 40)):
				_set_phase("recede")
		"recede":
			var rs := float(cfg.get("recede_s", 150))
			w.set(&"event_sea_offset", sm * (1.0 - smoothstep(0.0, rs, _phase_t)))
			if _phase_t >= rs:
				done = true
	_tick_sweeps(w, dt)

func _set_phase(p: String) -> void:
	phase = p
	_phase_t = 0.0

func _make_wall() -> void:
	_wall = MeshInstance3D.new()
	_wall.name = "TsunamiWall"
	var bm := BoxMesh.new()
	bm.size = Vector3(ArchipelagoV5.HALF * 3.2, 8.0, 14.0)
	bm.subdivide_width = 160
	bm.subdivide_height = 6
	bm.subdivide_depth = 3
	_wall.mesh = bm
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = WALL_SHADER
	sm.shader = sh
	_wall.material_override = sm
	_wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_wall)

func _place_wall(w: Node) -> void:
	if _wall == null:
		return
	var base := float(w.call(&"water_level")) - float(w.get(&"event_sea_offset"))
	var c := dir * front
	_wall.global_position = Vector3(c.x, base + 1.8, c.y)
	# ось X стены — вдоль фронта, −Z — по ходу волны
	_wall.global_basis = Basis.looking_at(Vector3(dir.x, 0, dir.y), Vector3.UP)

## Фронт прошёл точку — накрыть, если низко (вода/пляж/низина).
func _apply_front(w: Node) -> void:
	var base := float(w.call(&"water_level")) - float(w.get(&"event_sea_offset"))
	var lim := base + float(cfg.get("surge_m", 2.8)) + 1.3
	var targets: Array = get_tree().get_nodes_in_group(&"characters")
	targets.append_array(get_tree().get_nodes_in_group(&"boat"))
	targets.append_array(get_tree().get_nodes_in_group(&"pickups"))
	targets.append_array(get_tree().get_nodes_in_group(&"supply_crates"))
	for nv: Variant in targets:
		if not is_instance_valid(nv) or not (nv is Node3D):
			continue
		var n := nv as Node3D
		var id: int = n.get_instance_id()
		if _hit.has(id):
			continue
		var p := n.global_position
		var s := Vector2(p.x, p.z).dot(dir)
		if s > front or s < front - 25.0:
			continue
		_hit[id] = true
		var gh := float(w.call(&"height_at", p.x, p.z))
		if gh > lim and p.y > lim:
			continue
		var depth := clampf((lim - maxf(gh, 0.0)) / 3.0, 0.3, 1.0)
		if n.is_in_group(&"boat"):
			if n.has_method(&"apply_damage"):
				n.call(&"apply_damage", 9999.0, null, &"tsunami")
			continue
		if n.is_in_group(&"characters"):
			if not alive(n):
				continue
			var dr: Array = cfg.get("damage", [14, 32])
			var dmg := lerpf(float(dr[0]), float(dr[1]), depth)
			if bool(n.get(&"swimming")):
				dmg *= 1.25
			if n.has_method(&"apply_damage"):
				n.call(&"apply_damage", dmg, null, &"tsunami")
			if n.is_in_group(&"player"):
				Events.toast.emit("Волна сбила с ног и потащила!")
		_sweeps.append({"node": n, "left": float(cfg.get("sweep_time_s", 1.6)) * (0.6 + depth * 0.8),
			"v": Vector3(dir.x, 0, dir.y) * float(cfg.get("sweep_speed", 9.0)) * depth})

func _tick_sweeps(w: Node, dt: float) -> void:
	for sw in _sweeps.duplicate():
		var nv: Variant = sw.node
		if not is_instance_valid(nv):
			_sweeps.erase(sw)
			continue
		var n := nv as Node3D
		var p := n.global_position + (sw.v as Vector3) * dt
		var gh := float(w.call(&"height_at", p.x, p.z))
		# не протаскивать сквозь скалы: на крутом подъёме волна теряет силу
		if gh > n.global_position.y + 1.2:
			_sweeps.erase(sw)
			continue
		p.y = maxf(p.y, gh + 0.05)
		n.global_position = p
		sw.left = float(sw.left) - dt
		if float(sw.left) <= 0.0:
			_sweeps.erase(sw)

func finish() -> void:
	var w := world()
	if w and (&"event_sea_offset" in w):
		w.set(&"event_sea_offset", 0.0)
	if _wall:
		_wall.queue_free()
	super.finish()

## Боту стоит уйти наверх: идёт предупреждение/волна и он низко у моря.
func bot_should_evade(bot: Node3D) -> bool:
	if phase != "withdraw" and phase != "wave":
		return false
	var w := world()
	if w == null:
		return false
	var p := bot.global_position
	return float(w.call(&"height_at", p.x, p.z)) < 5.5

func hud_line() -> String:
	match phase:
		"withdraw":
			return "Цунами: море отступает — уходите наверх! (%d с)" % int(maxf(float(cfg.get("withdraw_s", 80)) - _phase_t, 0.0))
		"wave":
			return "Цунами: волна идёт с %s" % Supply.compass(-dir)
		"surge":
			return "Цунами: вода стоит высоко"
		"recede":
			return "Цунами: вода уходит"
	return ""
