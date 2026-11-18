class_name ReefSchool
extends MultiMeshInstance3D
## Группа рыб одного вида (MultiMesh). Движение — в reef_fish.gdshader; здесь
## только раскладка и те же формулы на процессоре (fish_pos) — для сценок охоты.
## Узел стоит в (x, 0, z) — мировая высота = локальная.

var species: StringName
var mode: int = 0
var roam := Vector3(5, 0.6, 5)
var swim_speed: float = 0.3
var lag: float = 0.12
var y_min: float = -100.0
var homes: PackedVector3Array = PackedVector3Array()   # мировые «дома»
var custom: PackedColorArray = PackedColorArray()
var center: Vector3 = Vector3.ZERO                     # мировой центр группы (у дна/в толще)
var radius: float = 2.0
var mat: ShaderMaterial
var scare_t: float = -1000.0
var scare_pos: Vector3 = Vector3.ZERO
var scare_power: float = 4.0
var hidden_i: int = -1
var hidden_until: float = 0.0
var size_avg: float = 0.2

## Построить группу: homes — мировые точки, sizes — размер каждой рыбы.
func setup(sp: StringName, at: Vector3, fish_homes: PackedVector3Array, rng: RandomNumberGenerator, floor_min: float) -> void:
	species = sp
	var d: Dictionary = ReefSpecies.FISH[sp]
	mode = int(d["mode"])
	var r: Array = d["roam"]
	roam = Vector3(r[0], r[1], r[2])
	swim_speed = float(d["speed"]) * rng.randf_range(0.85, 1.15)
	y_min = floor_min
	center = at
	homes = fish_homes
	position = Vector3(at.x, 0.0, at.z)
	var look: Dictionary = (d["col"] as Dictionary).duplicate()
	mat = ReefSpecies.make_material(look, mode)
	mat.set_shader_parameter(&"roam", roam)
	mat.set_shader_parameter(&"swim_speed", swim_speed)
	mat.set_shader_parameter(&"lag", lag)
	mat.set_shader_parameter(&"y_min", y_min)
	mat.set_shader_parameter(&"scare_power", scare_power)
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = true   # без цветов экземпляров COLOR в шейдере обнуляется (gl_compatibility)
	mm.mesh = ReefMeshes.fish(d["shape"])
	mm.instance_count = homes.size()
	var smin: float = d["size"][0]
	var smax: float = d["size"][1]
	custom.resize(homes.size())
	var ext := Vector3.ZERO
	var tot := 0.0
	for i in homes.size():
		var h := homes[i]
		var local := Vector3(h.x - position.x, h.y, h.z - position.z)
		mm.set_instance_transform(i, Transform3D(Basis(), local))
		var s := rng.randf_range(smin, smax)
		tot += s
		var c := Color(rng.randf(), rng.randf_range(0.6, 1.0), s, rng.randf())
		custom[i] = c
		mm.set_instance_custom_data(i, c)
		mm.set_instance_color(i, Color(1, 1, 1, 1))
		ext = ext.max(Vector3(absf(local.x), 0, absf(local.z)))
	size_avg = tot / maxf(homes.size(), 1)
	multimesh = mm
	var R := ext + roam * 1.2 + Vector3(scare_power + 2.0, 0, scare_power + 2.0)
	custom_aabb = AABB(Vector3(-R.x, y_min - 2.0, -R.z), Vector3(R.x * 2.0, absf(y_min) + 6.0, R.z * 2.0))
	radius = maxf(ext.x, ext.z) + roam.x * 0.5
	visibility_range_end = clampf(28.0 + size_avg * 90.0 + homes.size() * 0.12, 30.0, 70.0)
	visibility_range_end_margin = 6.0

# ---------------- те же формулы, что в шейдере ----------------

func _path(t: float, c: Color, home: Vector3) -> Vector3:
	if mode == 0:
		var tt := t * swim_speed - (home.z * 0.8 + home.x * 0.25) * lag
		var d := Vector3(sin(tt * 0.37 + 1.3) + 0.4 * sin(tt * 0.11 + 0.5), sin(tt * 0.23 + 0.7),
			sin(tt * 0.29 + 0.4) + 0.4 * cos(tt * 0.13)) * roam
		var ph := c.r * TAU
		d += Vector3(sin(t * 0.9 + ph * 3.0), 0.5 * sin(t * 0.7 + ph * 2.0), cos(t * 0.8 + ph * 5.0)) * 0.12 * c.g
		return d
	var ph1 := c.r * TAU
	var sp := swim_speed * (0.7 + 0.6 * fposmod(c.r * 7.31, 1.0))
	var t1 := t * sp + ph1 * 3.0 + 0.8 * sin(t * 0.37 + ph1)
	return Vector3(sin(t1 * 0.5 + ph1), sin(t1 * 0.31 + ph1 * 2.0) * 0.35, sin(t1 * 0.41 + ph1 * 1.3)) * roam * c.g

## Мировая позиция рыбы i в момент t (по умолчанию — сейчас).
func fish_pos(i: int, t: float = -1.0) -> Vector3:
	if t < 0.0:
		t = ReefLife.time
	var c := custom[i]
	var home := homes[i]
	var d := _path(t, c, home)
	var wp := home + d
	var sdt := t - scare_t
	if sdt > 0.0 and sdt < 9.0:
		var f := (1.0 - exp(-sdt * 6.0)) * exp(-sdt * 0.55)
		var aw := wp - scare_pos
		aw.y *= 0.35
		var dist := aw.length() + 0.001
		d += aw / dist * scare_power * f * clampf(1.4 - dist / 12.0, 0.0, 1.0)
	var y := clampf(home.y + d.y, y_min + 0.25 + c.b * 0.3, ReefLife.level - 0.35)
	d.y = y - home.y
	return home + d

## Центр группы сейчас (для стай — где сейчас стая).
func current_center() -> Vector3:
	if mode == 0 and homes.size() > 0:
		return fish_pos(0)
	return center

func count() -> int:
	return homes.size()

## Испуг: веерный разлёт от точки (мировой).
func scare(from: Vector3, power: float = -1.0) -> void:
	if ReefLife.time - scare_t < 2.5:
		return
	scare_t = ReefLife.time
	scare_pos = from
	if power > 0.0:
		scare_power = power
		mat.set_shader_parameter(&"scare_power", power)
	mat.set_shader_parameter(&"scare", Vector4(from.x, from.y, from.z, scare_t))

func is_scared() -> bool:
	return ReefLife.time - scare_t < 4.0

## Спрятать одну рыбу (её «съели»); вернётся через sec секунд.
func hide_fish(i: int, sec: float = 25.0) -> void:
	hidden_i = i
	hidden_until = ReefLife.time + sec
	mat.set_shader_parameter(&"hidden", i)

func tick() -> void:
	if hidden_i >= 0 and ReefLife.time > hidden_until:
		hidden_i = -1
		mat.set_shader_parameter(&"hidden", -1)

## Ближайшая к точке рыба (индекс).
func nearest_fish(p: Vector3) -> int:
	var best := -1
	var bd := INF
	var step := maxi(1, homes.size() / 24)
	for i in range(0, homes.size(), step):
		if i == hidden_i:
			continue
		var d := fish_pos(i).distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	return best
