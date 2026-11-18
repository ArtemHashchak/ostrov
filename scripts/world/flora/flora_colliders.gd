class_name FloraColliders
extends StaticBody3D
## Дешёвые коллизии стволов «спящих» деревьев одного чанка (деревья в MultiMesh).
## Удар/снаряд по такому стволу «будит» дерево (Flora.promote) и передаёт удар ему.

var flora: Flora
var recs: Dictionary = {} # instance_id формы (CollisionShape3D) -> рекорд дерева

func on_hit(by: Node, hit: Dictionary) -> void:
	var rec = _rec_of(hit)
	if rec == null or flora == null:
		return
	var t := flora.promote(rec)
	if t:
		hit["collider"] = t
		t.on_hit(by, hit)

## Дерево, которому принадлежит форма из результата intersect_ray (hit.shape).
func _rec_of(hit: Dictionary):
	var idx := int(hit.get("shape", -1))
	if idx >= 0:
		var o := shape_owner_get_owner(shape_find_owner(idx))
		if o and recs.has(o.get_instance_id()):
			return recs[o.get_instance_id()]
	# запасной путь: ближайший ствол к точке удара
	var pos: Vector3 = hit.get("position", global_position)
	var best = null
	var bd := 9.0
	for k in recs:
		var r: Dictionary = recs[k]
		var d := Vector2(r.pos.x - pos.x, r.pos.z - pos.z).length_squared()
		if d < bd and int(r.state) == 0:
			bd = d
			best = r
	return best
