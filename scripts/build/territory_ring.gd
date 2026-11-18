class_name TerritoryRing
extends MeshInstance3D
## Рамка территории флага: светящаяся полупрозрачная лента цвета команды,
## идёт по рельефу (над водой — по воде). Показывается в режиме стройки.

const SEGMENTS := 160
const HEIGHT := 1.6

static func make(team: int, center: Vector3, radius: float) -> TerritoryRing:
	var r := TerritoryRing.new()
	r.name = "Territory_%d" % team
	r.mesh = _ribbon(center, radius, Game.team_color(team))
	r.material_override = BuildMats.mat(&"territory")
	r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return r

static func _ribbon(c: Vector3, radius: float, col: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wl := BuildEnv.water_level()
	var bottom := Color(col.r, col.g, col.b, 0.7)
	var top := Color(col.r, col.g, col.b, 0.0)
	var prev_b := Vector3.ZERO
	var prev_t := Vector3.ZERO
	for i in SEGMENTS + 1:
		var a := TAU * i / float(SEGMENTS)
		var x := c.x + cos(a) * radius
		var z := c.z + sin(a) * radius
		var y := maxf(BuildEnv.height_at(x, z), wl) + 0.05
		var b := Vector3(x, y, z)
		var t := b + Vector3.UP * HEIGHT
		if i > 0:
			for v: Array in [[prev_b, bottom], [b, bottom], [t, top], [prev_b, bottom], [t, top], [prev_t, top]]:
				st.set_color(v[1])
				st.add_vertex(v[0])
		prev_b = b
		prev_t = t
	return st.commit()
