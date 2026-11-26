class_name WindFx
extends RefCounted
## Частицы, которые сносит ветер мира (v5, агент D): дым костров и пожаров, искры, пепел.
## WindFx.register(p, &"smoke"|&"sparks"|&"ash") — запоминает исходную «гравитацию» эмиттера; SkyWeather
## раз в 0.2 с пересчитывает её по ветру (world.wind_dir/wind_speed/gust) и сырости:
## в сухую погоду дым поднимается столбом и уходит по ветру, в сырость/дождь — стелется у земли.

const GROUP := &"wind_particles"

static func register(p: CPUParticles3D, kind: StringName = &"smoke") -> void:
	if p == null:
		return
	p.set_meta(&"wind_kind", kind)
	p.set_meta(&"wind_base", p.gravity)
	p.add_to_group(GROUP)

## Гравитация частиц при данном ветре: wd — направление (x, z), ws — м/с, gust 0..1, wet 0..1.
static func gravity_for(kind: StringName, base: Vector3, wd: Vector2, ws: float, gust: float, wet: float) -> Vector3:
	var push := ws * (1.0 + 0.5 * gust)
	match kind:
		&"sparks":
			return Vector3(wd.x * push * 0.22, base.y, wd.y * push * 0.22)
		&"ash":
			return Vector3(wd.x * push * 0.3, base.y * 0.6, wd.y * push * 0.3)
		_:
			# дым: подъём слабее в сырость (стелется), снос сильнее с ветром
			var up := absf(base.y) * lerpf(1.0, 0.3, clampf(wet, 0.0, 1.0)) * lerpf(1.0, 0.55, clampf(ws / 14.0, 0.0, 1.0))
			return Vector3(wd.x * push * 0.32, up, wd.y * push * 0.32)

static func update_all(tree: SceneTree, wd: Vector2, ws: float, gust: float, wet: float) -> void:
	if tree == null:
		return
	for n in tree.get_nodes_in_group(GROUP):
		var p := n as CPUParticles3D
		if p == null or not is_instance_valid(p):
			continue
		p.gravity = gravity_for(StringName(p.get_meta(&"wind_kind", &"smoke")), p.get_meta(&"wind_base", p.gravity), wd, ws, gust, wet)
