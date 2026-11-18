extends SceneTree
func _init() -> void:
	var w := World.new()
	root.add_child(w)
	await process_frame
	await physics_frame
	await physics_frame
	var space := w.get_world_3d().direct_space_state
	var rng := RandomNumberGenerator.new()
	var e := [0.0, 0.0]
	var worst := Vector3.ZERO
	for k in 600:
		var x := rng.randf_range(-200, 600)
		var z := rng.randf_range(-250, 200)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 80, z), Vector3(x, -60, z)))
		if hit.is_empty(): continue
		var hy: float = hit.position.y
		var t: TerrainChunks = w.terrain
		var key := Vector2i(int(floor(x / 64.0)), int(floor(z / 64.0)))
		var d: Dictionary = t._chunks[key]
		var n: int = d.n; var st: float = d.step; var o: Vector2 = d.origin
		var fx := (x - o.x) / st; var fz := (z - o.y) / st
		var i := int(floor(fx)); var j := int(floor(fz)); var u := fx - i; var v := fz - j
		var hh: PackedFloat32Array = d.h
		var h00 := hh[j*n+i]; var h10 := hh[j*n+i+1]; var h01 := hh[(j+1)*n+i]; var h11 := hh[(j+1)*n+i+1]
		var a := (h00 + (h10-h00)*u + (h11-h10)*v) if u >= v else (h00 + (h11-h01)*u + (h01-h00)*v)
		var b := (h00 + (h10-h00)*u + (h01-h00)*v) if u+v <= 1.0 else (h11 + (h01-h11)*(1.0-u) + (h10-h11)*(1.0-v))
		e[0] = maxf(e[0], absf(a-hy)); e[1] = maxf(e[1], absf(b-hy))
		if absf(a-hy) > 0.05 and worst == Vector3.ZERO:
			worst = Vector3(x, hy, z); print("bad ", x, " ", z, " st=", st, " hy=", hy, " main=", a, " anti=", b, " o=", o, " n=", n)
	print("err main=", e[0], " anti=", e[1])
	quit()
