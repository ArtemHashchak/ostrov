## test-timeout: 900
extends TestCase
## v5.1 (агент H): мерцание света. Камера идёт пляж → джунгли → звериная тропа в полдень,
## каждый кадр (после всех узлов и таймеров Sky3D) снимаются итоговые параметры света окружения.
## Скачков от кадра к кадру быть не должно. Плюс камера качается у поверхности моря —
## «под водой / над водой» не должно переключаться каждый кадр.

func _init() -> void:
	OS.set_environment("OSTROVA_GEN", "5")
	scene_path = "res://scenes/world/world_view.tscn"
	timeout_sec = 880.0

class LateSampler extends Node:
	var env: Environment
	var sky: SkyWeather
	var samples: Array = []
	var on := false
	func _ready() -> void:
		process_priority = 100000
	func _process(_d: float) -> void:
		if not on or env == null:
			return
		var c := env.ambient_light_color
		var lum := (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) * env.ambient_light_energy * env.tonemap_exposure
		samples.append({"lum": lum, "col": c, "exp": env.tonemap_exposure,
			"contrib": env.ambient_light_sky_contribution, "fogd": env.fog_density,
			"uw": sky.is_underwater_view()})

var w: World
var cam: Camera3D

func _find(zone: StringName, c: Vector2, r: float, rng: RandomNumberGenerator) -> Vector2:
	for i in 6000:
		var a := rng.randf() * TAU
		var p := c + Vector2(cos(a), sin(a)) * rng.randf_range(0.0, 1.2) * r
		if w.zone_at(p.x, p.y) == zone:
			return p
	return Vector2.INF

func _walk(path: Array, speed: float) -> void:
	for i in path.size() - 1:
		var a: Vector2 = path[i]
		var b: Vector2 = path[i + 1]
		var n := int(ceil(a.distance_to(b) / (speed / 60.0)))
		for k in n:
			var p := a.lerp(b, float(k) / float(maxi(n, 1)))
			var h := maxf(w.height_at(p.x, p.y), w.water_level()) + 1.6
			cam.global_position = Vector3(p.x, h, p.y)
			var fwd := (b - a).normalized()
			cam.look_at(cam.global_position + Vector3(fwd.x, -0.05, fwd.y), Vector3.UP)
			await wait_frames(1)

func run() -> void:
	await wait(2.0)
	w = get_tree().get_first_node_in_group(&"world") as World
	check(w != null and w.sky != null, "мир и небо готовы")
	if w == null or w.sky == null:
		return
	var sky := w.sky
	sky.set_weather(&"clear", true, false)
	sky.set_time_of_day(12.0)
	cam = Camera3D.new()
	scene.add_child(cam)
	cam.current = true
	var I: Dictionary = w.islands()[0]
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var c: Vector2 = I.center
	var r: float = I.radius
	var beach := _find(&"beach", c, r, rng)
	var jungle := _find(&"jungle", c, r, rng)
	var trail := Vector2.INF
	if w.trails:
		for i in w.trails.trails.size():
			if w.trails.kinds[i] == &"animal" and w.trails.trails[i].size() > 4:
				trail = w.trails.trails[i][2]
				break
	check(beach != Vector2.INF and jungle != Vector2.INF, "найдены пляж и джунгли")
	if beach == Vector2.INF or jungle == Vector2.INF:
		return
	var path := [beach, jungle]
	if trail != Vector2.INF:
		path.append(trail)
	path.append(beach)
	var smp := LateSampler.new()
	smp.env = sky._env
	smp.sky = sky
	scene.add_child(smp)
	cam.global_position = Vector3(beach.x, w.height_at(beach.x, beach.y) + 1.6, beach.y)
	await wait(1.0)
	smp.on = true
	await _walk(path, 6.0)
	smp.on = false
	var s: Array = smp.samples
	check(s.size() > 100, "кадров снято: %d" % s.size())
	var max_rel := 0.0
	var max_col := 0.0
	var max_exp := 0.0
	var max_con := 0.0
	var spikes := 0   # «мигание»: скачок туда и сразу обратно (A-B-A) больше 1 %
	var lo := INF
	var hi := 0.0
	for i in range(1, s.size()):
		var a: Dictionary = s[i - 1]
		var b: Dictionary = s[i]
		var la: float = a.lum
		var lb: float = b.lum
		lo = minf(lo, lb)
		hi = maxf(hi, lb)
		max_rel = maxf(max_rel, absf(lb - la) / maxf(la, 1e-4))
		if i + 1 < s.size():
			var lc: float = s[i + 1].lum
			var d1 := (lb - la) / maxf(la, 1e-4)
			var d2 := (lc - lb) / maxf(lb, 1e-4)
			if absf(d1) > 0.01 and absf(d2) > 0.01 and signf(d1) != signf(d2):
				spikes += 1
		var ca: Color = a.col
		var cb: Color = b.col
		max_col = maxf(max_col, maxf(absf(ca.r - cb.r), maxf(absf(ca.g - cb.g), absf(ca.b - cb.b))))
		max_exp = maxf(max_exp, absf(float(b.exp) - float(a.exp)))
		max_con = maxf(max_con, absf(float(b.contrib) - float(a.contrib)))
	print("[test] свет по пути: кадров %d, яркость %.3f..%.3f, макс. скачок яркости %.2f%%, миганий %d, цвета %.4f, экспозиции %.4f, вклада неба %.4f" % [
		s.size(), lo, hi, max_rel * 100.0, spikes, max_col, max_exp, max_con])
	check(spikes == 0, "нет мигания рассеянного света (скачок туда-обратно >1 %%: %d)" % spikes)
	check(max_rel < 0.05, "рассеянный свет без резких скачков между кадрами (макс. %.2f%% < 5%%)" % (max_rel * 100.0))
	check(max_col < 0.02, "цвет рассеянного света без скачков (макс. %.4f)" % max_col)
	check(max_exp < 0.02, "экспозиция без скачков (макс. %.4f)" % max_exp)
	check(max_con < 0.03, "вклад неба без скачков (макс. %.4f)" % max_con)
	# у поверхности моря: камера качается с волной (±10 см вокруг уровня, где раньше был порог)
	var sea := Vector2.INF
	for i in 4000:
		var a2 := rng.randf() * TAU
		var p2 := c + Vector2(cos(a2), sin(a2)) * r * rng.randf_range(1.4, 2.2)
		if w.height_at(p2.x, p2.y) < w.water_level() - 3.0:
			sea = p2
			break
	check(sea != Vector2.INF, "найдено море")
	if sea == Vector2.INF:
		return
	# A) лёгкое покачивание у самой поверхности (−10…+2 см): переключений быть не должно
	var flipsA := await _bob(smp, sea, -0.04, 0.06)
	print("[test] у поверхности (±6 см): переключений под/над водой %d" % flipsA[0])
	check(flipsA[0] == 0, "под/над водой не мигает при лёгком покачивании (переключений %d)" % flipsA[0])
	# B) настоящие нырки с волной (±20 см): переключения есть, но не чаще раза в ~0,25 с
	var flipsB := await _bob(smp, sea, -0.05, 0.2)
	print("[test] нырки (±20 см): переключений %d, мин. кадров между ними %d" % [flipsB[0], flipsB[1]])
	check(flipsB[1] >= 15, "между переключениями не меньше 15 кадров (мин. %d)" % flipsB[1])

func _bob(smp: LateSampler, sea: Vector2, center: float, amp: float) -> Array:
	smp.samples.clear()
	smp.on = true
	var t := 0.0
	for k in 240:
		t += 1.0 / 60.0
		var surf := w.ocean.wave_height(sea.x, sea.y) if w.ocean else w.water_level()
		cam.global_position = Vector3(sea.x, surf + center + amp * sin(t * 7.0), sea.y)
		cam.look_at(cam.global_position + Vector3(1, 0, 0), Vector3.UP)
		await wait_frames(1)
	smp.on = false
	var flips := 0
	var last := -1000
	var min_gap := 100000
	var s2: Array = smp.samples
	for i in range(1, s2.size()):
		if bool(s2[i].uw) != bool(s2[i - 1].uw):
			flips += 1
			min_gap = mini(min_gap, i - last)
			last = i
	return [flips, min_gap]
