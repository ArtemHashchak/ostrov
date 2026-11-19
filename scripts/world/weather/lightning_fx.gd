class_name LightningFx
extends Node3D
## Молнии (CONTRACT_WEATHER): ломаный разряд с ветвями (лента к камере, аддитивная),
## мерцание 2–3 вспышки за ~0.4 с, вспышка неба (через SkyWeather.flash), гром с задержкой
## по расстоянию (343 м/с) и громкостью по расстоянию. Близкий удар изредка поджигает
## место удара (Combat.ignite_area), если это суша.

signal strike(pos: Vector3, dist: float)

const SOUND_SPEED := 343.0

var _mesh_i: MeshInstance3D
var _mat: StandardMaterial3D
var _rng := RandomNumberGenerator.new()
var _life := 0.0
var _flicker: PackedFloat32Array = PackedFloat32Array()
var _thunder: AudioStreamPlayer
var _thunder_delay := -1.0
var _thunder_db := 0.0
var flash := 0.0          # 0..1 — для неба/тумана (читает SkyWeather)
var last_strike := Vector3.ZERO
var strikes := 0

func setup(seed_value: int, thunder_stream: AudioStream) -> void:
	_rng.seed = seed_value + 777
	_mesh_i = MeshInstance3D.new()
	_mesh_i.name = "Bolt"
	_mesh_i.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_i.extra_cull_margin = 2000.0
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.disable_fog = true
	_mat.vertex_color_use_as_albedo = true
	_mat.albedo_color = Color(0.85, 0.88, 1.0, 1.0)
	_mesh_i.material_override = _mat
	_mesh_i.visible = false
	add_child(_mesh_i)
	_thunder = AudioStreamPlayer.new()
	_thunder.name = "Thunder"
	_thunder.stream = thunder_stream
	_thunder.bus = &"Master"
	add_child(_thunder)

## Удар молнии. world — для высоты земли; cam — откуда смотрим.
func do_strike(cam_pos: Vector3, world: Node, close_chance: float = 0.12) -> void:
	var ang := _rng.randf() * TAU
	var dist := _rng.randf_range(90.0, 260.0) if _rng.randf() < close_chance else _rng.randf_range(320.0, 1500.0)
	var gx := cam_pos.x + cos(ang) * dist
	var gz := cam_pos.z + sin(ang) * dist
	var gy := 0.0
	if world and world.has_method(&"height_at"):
		gy = maxf(float(world.call(&"height_at", gx, gz)), float(world.call(&"water_level")) if world.has_method(&"water_level") else 0.0)
	var ground := Vector3(gx, gy, gz)
	var top := ground + Vector3(_rng.randf_range(-60.0, 60.0), 420.0, _rng.randf_range(-60.0, 60.0))
	_build_bolt(top, ground, cam_pos, clampf(dist * 0.0035, 1.2, 6.0))
	_mesh_i.visible = true
	_life = 0.45
	_flicker = PackedFloat32Array([0.45, 0.36, 0.3, 0.2, 0.14])
	flash = 1.0 if dist < 600.0 else 0.6
	last_strike = ground
	strikes += 1
	_thunder_delay = dist / SOUND_SPEED
	_thunder_db = lerpf(2.0, -16.0, clampf((dist - 90.0) / 1400.0, 0.0, 1.0))
	strike.emit(ground, dist)
	# близкий удар по суше может поджечь (редко)
	if dist < 260.0 and world and world.has_method(&"is_land") and bool(world.call(&"is_land", gx, gz)) and _rng.randf() < 0.3:
		Combat.ignite_area(ground + Vector3(0, 0.3, 0), 2.5, null, 14.0, get_tree().current_scene)

func _build_bolt(top: Vector3, ground: Vector3, cam_pos: Vector3, wscale: float = 1.0) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var main := _zigzag(top, ground, 22, 26.0)
	_ribbon(st, main, cam_pos, 1.6 * wscale, 1.0)
	_ribbon(st, main, cam_pos, 7.0 * wscale, 0.22)   # свечение вокруг
	for b in _rng.randi_range(2, 4):
		var i := _rng.randi_range(3, main.size() - 6)
		var s := main[i]
		var dir := (main[i + 1] - s).normalized()
		var side := Vector3(_rng.randf_range(-1, 1), 0.0, _rng.randf_range(-1, 1)).normalized()
		var e := s + (dir * 0.6 + side * 0.7).normalized() * _rng.randf_range(60.0, 150.0)
		var br := _zigzag(s, e, 9, 14.0)
		_ribbon(st, br, cam_pos, 0.9 * wscale, 0.7)
	_mesh_i.mesh = st.commit()

func _zigzag(a: Vector3, b: Vector3, n: int, jitter: float) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in n + 1:
		var t := float(i) / float(n)
		var p := a.lerp(b, t)
		if i > 0 and i < n:
			p += Vector3(_rng.randf_range(-jitter, jitter), _rng.randf_range(-jitter * 0.3, jitter * 0.3), _rng.randf_range(-jitter, jitter))
		pts.append(p)
	return pts

func _ribbon(st: SurfaceTool, pts: PackedVector3Array, cam_pos: Vector3, w: float, a: float) -> void:
	for i in pts.size() - 1:
		var p0 := pts[i]
		var p1 := pts[i + 1]
		var d := (p1 - p0).normalized()
		var v := (cam_pos - p0).normalized()
		var r := d.cross(v).normalized() * w * 0.5
		var c := Color(0.85, 0.88, 1.0, a)
		var ce := Color(0.6, 0.65, 1.0, 0.0)
		# центр яркий, края прозрачные: две полосы
		for side in [1.0, -1.0]:
			st.set_color(c); st.add_vertex(p0)
			st.set_color(ce); st.add_vertex(p0 + r * side)
			st.set_color(c); st.add_vertex(p1)
			st.set_color(ce); st.add_vertex(p0 + r * side)
			st.set_color(ce); st.add_vertex(p1 + r * side)
			st.set_color(c); st.add_vertex(p1)

func update(dt: float) -> void:
	if _life > 0.0:
		_life -= dt
		var on := false
		for f in _flicker:
			if absf(_life - f) < 0.035:
				on = true
		_mat.albedo_color.a = 1.0 if on else 0.35
		flash = maxf(flash - dt * 4.0, 0.7 if on else 0.0)
		if _life <= 0.0:
			_mesh_i.visible = false
	else:
		flash = maxf(0.0, flash - dt * 5.0)
	if _thunder_delay >= 0.0:
		_thunder_delay -= dt
		if _thunder_delay < 0.0 and _thunder.stream:
			_thunder.volume_db = _thunder_db
			_thunder.pitch_scale = _rng.randf_range(0.85, 1.08)
			_thunder.play()
