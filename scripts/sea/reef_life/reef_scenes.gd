class_name ReefScenes
extends Node3D
## Режиссёр сценок живого моря: короткие эпизоды охоты рядом с камерой, там, где
## их видно. Одновременно — не больше MAX_ACTIVE, новые — раз в 10–25 с, только
## если камера у воды. Персонажей нет: только узлы-модели и параметры шейдеров.
##   hunt   — барракуда/стайка каранксов врывается в стаю, стая веером, одна рыба поймана;
##   shark  — рифовая акула хватает рыбу у рифа, облачко крови;
##   ray    — электрический скат на песке бьёт разрядом подплывшую рыбку и накрывает её;
##   gull   — чайка кружит над косяком сардин, пикирует, выныривает с рыбой.
## API: force(kind) -> bool (для тестов), predator_positions(), active_count(), done[kind].

const MAX_ACTIVE := 2
const VIEW_R := 55.0

var life: ReefLife = null
var enabled: bool = true
var done: Dictionary = {}          # kind → сколько сценок закончено с добычей
var started: Dictionary = {}
var _active: Array[Dictionary] = []
var _next: float = 6.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

func active_count() -> int:
	return _active.size()

func predator_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for s in _active:
		for n: Node3D in s.get("predators", []):
			if is_instance_valid(n):
				out.append(n.global_position)
	return out

func _cam() -> Camera3D:
	return get_viewport().get_camera_3d()

func _process(delta: float) -> void:
	var __pt := PerfStats.begin()
	_perf_process(delta)
	PerfStats.end(&"reef", __pt)

func _perf_process(delta: float) -> void:
	for i in range(_active.size() - 1, -1, -1):
		var s: Dictionary = _active[i]
		s.t = float(s.t) + delta
		var alive: bool = call("_step_" + String(s.kind), s, delta)
		if not alive or float(s.t) > 40.0:
			_finish(s)
			_active.remove_at(i)
	if not enabled or life == null:
		return
	if ReefLife.time < _next or _active.size() >= MAX_ACTIVE:
		return
	_next = ReefLife.time + _rng.randf_range(10.0, 25.0)
	var cam := _cam()
	if cam == null:
		return
	var under := cam.global_position.y < ReefLife.level
	var opts := {&"hunt": 3.0, &"shark": 1.5, &"ray": 1.5, &"gull": 1.0} if under else {&"gull": 3.0, &"hunt": 1.0, &"shark": 0.6}
	var tot := 0.0
	for k: StringName in opts:
		tot += float(opts[k])
	var r := _rng.randf() * tot
	for k: StringName in opts:
		r -= float(opts[k])
		if r <= 0.0:
			force(k)
			break

func _finish(s: Dictionary) -> void:
	for n: Node in s.get("nodes", []):
		if is_instance_valid(n):
			n.queue_free()

## Видимая цель: группа рыб перед камерой в 8–VIEW_R м.
func _pick_school(want_open: bool, cam: Camera3D, near_surface: bool = false) -> ReefSchool:
	var cp := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var best: ReefSchool = null
	var bs := -INF
	var pool: Array = life.bait_balls if near_surface else life.schools_near(cp, VIEW_R)
	for s: ReefSchool in pool:
		if not is_instance_valid(s) or s.is_scared() or s.hidden_i >= 0:
			continue
		if want_open and s.mode != 0:
			continue
		if not want_open and s.mode == 0:
			continue
		if s.species == &"clownfish":
			continue
		var c := s.current_center()
		var d := c.distance_to(cp)
		if d < 6.0 or d > VIEW_R:
			continue
		var score := (c - cp).normalized().dot(fwd) * 2.0 - d / VIEW_R + _rng.randf() * 0.5
		if score > bs:
			bs = score
			best = s
	return best

func force(kind: StringName) -> bool:
	var cam := _cam()
	if cam == null or life == null:
		return false
	var s: Dictionary = {}
	match kind:
		&"hunt": s = _start_hunt(cam)
		&"shark": s = _start_shark(cam)
		&"ray": s = _start_ray(cam)
		&"gull": s = _start_gull(cam)
	if s.is_empty():
		return false
	s.kind = kind
	s.t = 0.0
	_active.append(s)
	started[kind] = int(started.get(kind, 0)) + 1
	return true

func _won(kind: StringName) -> void:
	done[kind] = int(done.get(kind, 0)) + 1

## Плыть к точке: поворот носом (-Z) по скорости.
static func _swim(n: Node3D, vel: Vector3, delta: float, turn: float = 4.0) -> void:
	if vel.length_squared() < 0.0001:
		return
	n.global_position += vel * delta
	if absf(vel.normalized().y) > 0.97:
		return
	var want := Basis.looking_at(vel.normalized(), Vector3.UP)
	var cur := n.global_transform.basis.orthonormalized()
	var sc := n.scale
	n.global_transform.basis = Basis(cur.get_rotation_quaternion().slerp(want.get_rotation_quaternion(), clampf(delta * turn, 0.0, 1.0))).scaled(sc)

func _clamp_water(p: Vector3, size: float = 0.3) -> Vector3:
	var f := float(life.sea.call(&"floor_at", p.x, p.z))
	p.y = clampf(p.y, f + 0.3 + size, ReefLife.level - 0.4)
	return p

## Блёстки чешуи/пузыри в точке.
func _puff(p: Vector3, col: Color, n: int = 14) -> void:
	var c := CPUParticles3D.new()
	c.one_shot = true
	c.amount = n
	c.lifetime = 1.6
	c.explosiveness = 0.9
	c.spread = 180.0
	c.direction = Vector3.UP
	c.initial_velocity_min = 0.3
	c.initial_velocity_max = 1.2
	c.gravity = Vector3(0, -0.4, 0)
	c.damping_min = 1.0
	c.damping_max = 2.0
	var q := QuadMesh.new()
	q.size = Vector2(0.04, 0.04)
	q.material = Sea.soft_material(col, true)
	c.mesh = q
	add_child(c)
	c.global_position = p
	c.emitting = true
	get_tree().create_timer(2.5).timeout.connect(c.queue_free)

# ================================ hunt ================================

func _start_hunt(cam: Camera3D) -> Dictionary:
	var target := _pick_school(_rng.randf() < 0.6, cam)
	if target == null:
		target = _pick_school(false, cam)
	if target == null:
		target = _pick_school(true, cam)
	if target == null:
		return {}
	var pack := _rng.randf() < 0.4
	var c := target.current_center()
	var dir := Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized()
	# заходим сбоку от камеры, чтобы было видно
	var side := cam.global_transform.basis.x * (1.0 if _rng.randf() < 0.5 else -1.0)
	dir = (dir * 0.3 + side).normalized()
	var preds: Array[Node3D] = []
	var nodes: Array[Node] = []
	var n := 3 if pack else 1
	for i in n:
		var m := ReefSpecies.actor_node(&"trevally" if pack else &"barracuda")
		add_child(m)
		m.global_position = _clamp_water(c + dir * (20.0 + i * 1.5) + Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)), 0.4)
		m.look_at(c, Vector3.UP)
		preds.append(m)
		nodes.append(m)
	return {"target": target, "predators": preds, "nodes": nodes, "phase": 0, "fish": -1, "prey": null, "pack": pack, "dash_t": 0.0}

func _step_hunt(s: Dictionary, delta: float) -> bool:
	if not _alive(s, [&"target"]):
		return false
	var target: ReefSchool = s.target
	var preds: Array = s.predators
	if not is_instance_valid(target) or preds.is_empty():
		return false
	var lead: Node3D = preds[0]
	var c := target.current_center()
	match int(s.phase):
		0: # подход
			var to := c - lead.global_position
			for i in preds.size():
				var p: Node3D = preds[i]
				var aim := c + Vector3(i * 0.8, 0, -i * 0.6)
				_swim(p, (aim - p.global_position).normalized() * 3.2, delta, 3.0)
			if to.length() < 7.0:
				s.phase = 1
				s.fish = target.nearest_fish(lead.global_position)
				target.scare(lead.global_position, 5.0)
		1: # бросок
			s.dash_t = float(s.dash_t) + delta
			var fi: int = s.fish
			var fp := target.fish_pos(fi) if fi >= 0 else c
			for i in preds.size():
				var p: Node3D = preds[i]
				var aim := fp if i == 0 else fp + Vector3(i * 1.2, 0, i * 0.8)
				_swim(p, (aim - p.global_position).normalized() * 10.0, delta, 8.0)
			if fi >= 0 and (lead.global_position.distance_to(fp) < 0.5 or float(s.dash_t) > 1.6):
				target.hide_fish(fi)
				var prey := ReefSpecies.actor_node(target.species, true)
				prey.scale = Vector3.ONE * clampf(target.size_avg, 0.06, 0.3) / maxf(lead.scale.x, 0.01)
				lead.add_child(prey)
				prey.position = Vector3(0, 0, -0.55)
				prey.rotation = Vector3(0, PI * 0.5, 0)
				(prey.material_override as ShaderMaterial).set_shader_parameter(&"stun", 1.0)
				s.prey = prey
				_puff(fp, Color(0.9, 0.95, 1.0, 0.8))
				_won(&"hunt")
				s.phase = 2
				s.leave_t = 0.0
			elif fi < 0:
				s.phase = 2
				s.leave_t = 0.0
		2: # уход
			s.leave_t = float(s.leave_t) + delta
			for p: Node3D in preds:
				var v := -p.global_transform.basis.z.normalized() * 3.0
				v.y = 0.0
				_swim(p, v, delta, 1.0)
			if float(s.leave_t) > 1.5 and s.prey and is_instance_valid(s.prey):
				(s.prey as Node).queue_free()
				s.prey = null
			if float(s.leave_t) > 8.0:
				return false
	return true

# ================================ shark ================================

func _start_shark(cam: Camera3D) -> Dictionary:
	var target := _pick_school(false, cam)
	if target == null:
		target = _pick_school(true, cam)
	if target == null:
		return {}
	var c := target.current_center()
	var side := cam.global_transform.basis.x * (1.0 if _rng.randf() < 0.5 else -1.0)
	var sh := SharkModel.build(&"reef", 1)
	add_child(sh)
	sh.global_position = _clamp_water(c + side * 24.0 + Vector3(0, 0.5, 0), 0.5)
	sh.look_at(c, Vector3.UP)
	var body := sh.get_node_or_null(^"Body") as MeshInstance3D
	return {"target": target, "predators": [sh], "nodes": [sh], "phase": 0, "fish": -1, "body": body, "swim": 0.0, "dash_t": 0.0}

func _step_shark(s: Dictionary, delta: float) -> bool:
	if not _alive(s, [&"target"]) or (s.predators as Array).is_empty() or not is_instance_valid((s.predators as Array)[0]):
		return false
	var target: ReefSchool = s.target
	var sh: Node3D = s.predators[0]
	if not is_instance_valid(target) or not is_instance_valid(sh):
		return false
	var spd := 2.2
	var c := target.current_center()
	match int(s.phase):
		0:
			_swim(sh, (c - sh.global_position).normalized() * spd, delta, 1.6)
			if sh.global_position.distance_to(c) < 6.0:
				s.phase = 1
				s.fish = target.nearest_fish(sh.global_position)
				target.scare(sh.global_position, 6.0)
		1:
			spd = 7.0
			s.dash_t = float(s.dash_t) + delta
			var fi: int = s.fish
			var fp := target.fish_pos(fi) if fi >= 0 else c
			_swim(sh, (fp - sh.global_position).normalized() * spd, delta, 5.0)
			if fi < 0 or sh.global_position.distance_to(fp) < 0.9 or float(s.dash_t) > 2.0:
				if fi >= 0:
					target.hide_fish(fi)
					if life.sea and life.sea.has_method(&"_blood_cloud"):
						life.sea.call(&"_blood_cloud", fp, 6.0)
					_puff(fp, Color(0.95, 0.95, 1.0, 0.8), 18)
					_won(&"shark")
				s.phase = 2
				s.leave_t = 0.0
		2:
			s.leave_t = float(s.leave_t) + delta
			var v := -sh.global_transform.basis.z.normalized() * 2.4
			v.y = 0.0
			_swim(sh, v, delta, 1.0)
			if float(s.leave_t) > 9.0:
				return false
	# изгиб тела по скорости
	s.swim = float(s.swim) + delta * spd * 2.4
	var body: MeshInstance3D = s.body
	if body and body.material_override:
		(body.material_override as ShaderMaterial).set_shader_parameter(&"swim_phase", s.swim)
	return true

# ================================ ray ================================

func _start_ray(cam: Camera3D) -> Dictionary:
	var cp := cam.global_position
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var spot := Vector3.INF
	for k in 16:
		var p := cp + fwd.rotated(Vector3.UP, _rng.randf_range(-0.5, 0.5)) * _rng.randf_range(5.0, 11.0)
		var d := float(life.sea.call(&"depth_at", p.x, p.z))
		if d > 1.0 and d < 12.0:
			spot = Vector3(p.x, float(life.sea.call(&"floor_at", p.x, p.z)), p.z)
			break
	if spot == Vector3.INF:
		return {}
	var ray := MeshInstance3D.new()
	ray.mesh = SeaMeshes.ray_mesh()
	ray.material_override = SeaCreature._material(0, ReefLife.level)
	ray.scale = Vector3.ONE * 0.8
	ray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ray)
	ray.global_position = spot + Vector3(0, 0.06, 0)
	ray.rotation.y = _rng.randf() * TAU
	ray.set_instance_shader_parameter(&"amp", 0.2)
	var fish := ReefSpecies.actor_node(&"damsel" if _rng.randf() < 0.5 else &"wrasse", true)
	fish.scale = Vector3.ONE * 0.16
	add_child(fish)
	var a := _rng.randf() * TAU
	fish.global_position = _clamp_water(spot + Vector3(cos(a) * 4.0, 0.6, sin(a) * 4.0), 0.1)
	# вспышка: в Forward+ — свет (кластерный, дёшев); в compatibility — только светящееся облачко
	var light: OmniLight3D = null
	if not RenderProfile.is_compat():
		light = OmniLight3D.new()
		light.light_color = Color(0.55, 0.75, 1.0)
		light.light_energy = 0.0
		light.omni_range = 4.0
		light.shadow_enabled = false
		add_child(light)
		light.global_position = spot + Vector3(0, 0.4, 0)
	var glow := MeshInstance3D.new()
	var gq := QuadMesh.new()
	gq.size = Vector2(2.2, 2.2)
	gq.material = Sea.soft_material(Color(0.55, 0.8, 1.0, 0.85), true)
	glow.mesh = gq
	glow.visible = false
	add_child(glow)
	glow.global_position = spot + Vector3(0, 0.3, 0)
	var bolt := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	bolt.mesh = im
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_color = Color(0.75, 0.9, 1.0)
	bm.emission_enabled = true
	bm.emission = Color(0.6, 0.85, 1.0)
	bm.emission_energy_multiplier = 3.0
	bm.disable_fog = true
	bolt.material_override = bm
	bolt.visible = false
	add_child(bolt)
	var nodes: Array = [ray, fish, bolt, glow]
	if light:
		nodes.append(light)
	return {"ray": ray, "fish": fish, "light": light, "glow": glow, "bolt": bolt, "nodes": nodes, "phase": 0,
		"spot": spot, "zap_t": 0.0, "wander": a, "predators": []}

func _bolt(s: Dictionary) -> void:
	var im: ImmediateMesh = (s.bolt as MeshInstance3D).mesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var a: Vector3 = (s.ray as Node3D).global_position + Vector3(0, 0.12, 0)
	var b: Vector3 = (s.fish as Node3D).global_position
	for k in 3:
		var prev := a
		for i in range(1, 7):
			var t := float(i) / 6.0
			var p := a.lerp(b, t) + Vector3(_rng.randf_range(-0.12, 0.12), _rng.randf_range(-0.12, 0.12), _rng.randf_range(-0.12, 0.12)) * (1.0 - absf(t - 0.5) * 2.0 + 0.2)
			if i == 6:
				p = b
			im.surface_add_vertex(prev - (s.bolt as Node3D).global_position)
			im.surface_add_vertex(p - (s.bolt as Node3D).global_position)
			prev = p
	im.surface_end()

func _step_ray(s: Dictionary, delta: float) -> bool:
	if not _alive(s, [&"fish", &"ray"]):
		return false
	var fish: Node3D = s.fish
	var ray: Node3D = s.ray
	var light: OmniLight3D = s.light
	var glow: Node3D = s.glow
	if not is_instance_valid(fish) or not is_instance_valid(ray):
		return false
	var spot: Vector3 = s.spot
	var fm := fish.material_override as ShaderMaterial
	match int(s.phase):
		0: # рыбка кружит и подплывает
			s.wander = float(s.wander) + delta * 0.5
			var r := maxf(4.0 - float(s.t) * 0.55, 0.3)
			var goal := spot + Vector3(cos(s.wander) * r, 0.3 + 0.15 * sin(float(s.t) * 1.3), sin(s.wander) * r)
			var to := goal - fish.global_position
			_swim(fish, to.normalized() * minf(to.length() * 1.5, 1.2), delta, 5.0)
			if fish.global_position.distance_to(ray.global_position) < 1.0 or float(s.t) > 9.0:
				s.phase = 1
		1: # разряд
			s.zap_t = float(s.zap_t) + delta
			var z := float(s.zap_t)
			var on := (z < 0.18) or (z > 0.3 and z < 0.45)
			if light:
				light.light_energy = 8.0 if on else 0.0
			glow.visible = on
			glow.global_position = ray.global_position.lerp(fish.global_position, 0.5)
			(s.bolt as Node3D).visible = on
			if on:
				_bolt(s)
			fm.set_shader_parameter(&"stun", 1.0)
			if z > 0.5:
				if light:
					light.light_energy = 0.0
				glow.visible = false
				(s.bolt as Node3D).visible = false
				s.phase = 2
				s.sink_t = 0.0
				life.scare_at(fish.global_position, 8.0)
		2: # рыбка оглушена — тонет боком
			s.sink_t = float(s.sink_t) + delta
			var f := float(life.sea.call(&"floor_at", fish.global_position.x, fish.global_position.z))
			fish.global_position.y = maxf(fish.global_position.y - delta * 0.35, f + 0.08)
			fish.rotation.z = lerpf(fish.rotation.z, PI * 0.5, delta * 2.0)
			if float(s.sink_t) > 1.6:
				s.phase = 3
				s.cover_t = 0.0
		3: # скат накрывает добычу
			s.cover_t = float(s.cover_t) + delta
			var to := fish.global_position - ray.global_position
			to.y = 0.0
			if to.length() > 0.08:
				ray.global_position += to.normalized() * minf(delta * 0.8, to.length())
			ray.global_position.y = lerpf(ray.global_position.y, fish.global_position.y + 0.1, delta * 3.0)
			ray.set_instance_shader_parameter(&"amp", 0.8)
			if float(s.cover_t) > 1.6:
				fish.visible = false
				_won(&"ray")
				s.phase = 4
				s.end_t = 0.0
		4:
			s.end_t = float(s.end_t) + delta
			ray.set_instance_shader_parameter(&"amp", 0.2)
			if float(s.end_t) > 6.0:
				return false
	return true

# ================================ gull ================================

func _start_gull(cam: Camera3D) -> Dictionary:
	var cp := cam.global_position
	var best: ReefSchool = null
	var bd := INF
	for b: ReefSchool in life.bait_balls:
		if not is_instance_valid(b) or b.hidden_i >= 0:
			continue
		var d := b.current_center().distance_to(cp)
		if d < bd and d < 75.0:
			bd = d
			best = b
	if best == null:
		return {}
	var gull := AnimalModels.build(&"gull")
	gull.scale = Vector3.ONE * 1.6
	add_child(gull)
	var c := best.current_center()
	var a := _rng.randf() * TAU
	gull.global_position = Vector3(c.x + cos(a) * 20.0, ReefLife.level + 14.0, c.z + sin(a) * 20.0)
	return {"target": best, "gull": gull, "nodes": [gull], "phase": 0, "ang": a, "flap": 0.0, "predators": []}

func _gull_wings(s: Dictionary, flap: float) -> void:
	var g: Node3D = s.gull
	for w: MeshInstance3D in g.get_meta(&"wings", []):
		(w.material_override as ShaderMaterial).set_shader_parameter(&"flap", flap)

func _step_gull(s: Dictionary, delta: float) -> bool:
	if not _alive(s, [&"target", &"gull"]):
		return false
	var target: ReefSchool = s.target
	var g: Node3D = s.gull
	if not is_instance_valid(target) or not is_instance_valid(g):
		return false
	var c := target.current_center()
	var wy := ReefLife.level
	match int(s.phase):
		0: # кружит над косяком
			s.ang = float(s.ang) + delta * 0.55
			var goal := Vector3(c.x + cos(s.ang) * 9.0, wy + 11.0, c.z + sin(s.ang) * 9.0)
			var v := (goal - g.global_position)
			_swim(g, v.normalized() * minf(7.0, v.length() * 2.0 + 4.0), delta, 3.0)
			s.flap = float(s.flap) + delta
			_gull_wings(s, sin(float(s.flap) * 7.0) * 0.8 if fmod(float(s.flap), 3.0) < 1.6 else 0.15)
			if float(s.t) > 5.0:
				s.phase = 1
				s.fish = target.nearest_fish(Vector3(c.x, wy, c.z))
		1: # пике
			var fi: int = s.fish
			var fp := target.fish_pos(fi) if fi >= 0 else c
			var aim := Vector3(fp.x, wy - 0.3, fp.z)
			_swim(g, (aim - g.global_position).normalized() * 16.0, delta, 6.0)
			_gull_wings(s, -0.9)
			if g.global_position.y <= wy + 0.1:
				if life.sea and life.sea.has_method(&"splash"):
					life.sea.call(&"splash", Vector3(g.global_position.x, wy, g.global_position.z), 0.8)
				life.scare_at(g.global_position, 10.0)
				var caught := fi >= 0 and Vector2(fp.x, fp.z).distance_to(Vector2(g.global_position.x, g.global_position.z)) < 2.5 and _rng.randf() < 0.8
				if caught:
					target.hide_fish(fi)
					var prey := ReefSpecies.actor_node(target.species, true)
					prey.scale = Vector3.ONE * 0.12 / 1.6
					g.add_child(prey)
					prey.position = Vector3(0, 0.0, -0.24)
					prey.rotation = Vector3(0, PI * 0.5, 0)
					(prey.material_override as ShaderMaterial).set_shader_parameter(&"stun", 1.0)
					s.prey = prey
					_won(&"gull")
				s.phase = 2
				s.under_t = 0.0
		2: # под водой мгновение
			s.under_t = float(s.under_t) + delta
			if float(s.under_t) > 0.35:
				s.phase = 3
				s.leave_t = 0.0
				if life.sea and life.sea.has_method(&"splash"):
					life.sea.call(&"splash", Vector3(g.global_position.x, wy, g.global_position.z), 0.5)
		3: # взлёт с добычей
			s.leave_t = float(s.leave_t) + delta
			var fwd := -g.global_transform.basis.z
			fwd.y = 0.0
			fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
			_swim(g, fwd * 7.0 + Vector3(0, 3.5, 0), delta, 2.0)
			s.flap = float(s.flap) + delta
			_gull_wings(s, sin(float(s.flap) * 10.0) * 0.9)
			if float(s.leave_t) > 8.0:
				return false
	return true

## Узлы сценки ещё живы (до типизированного присваивания — иначе ошибка
## «previously freed instance», если косяк/хищник удалён раньше сценки).
static func _alive(s: Dictionary, keys: Array) -> bool:
	for k in keys:
		var v: Variant = s.get(k)
		if typeof(v) == TYPE_NIL or (typeof(v) == TYPE_OBJECT and not is_instance_valid(v)):
			return false
	return true
