extends SceneTree
func _init():
	var args = OS.get_cmdline_user_args()
	var m: Mesh = load(args[0])
	var a = m.surface_get_arrays(0)
	var d = {"v": [], "i": Array(a[Mesh.ARRAY_INDEX]) if a[Mesh.ARRAY_INDEX] != null else [], "uv": []}
	for p in a[Mesh.ARRAY_VERTEX]: d.v.append([p.x,p.y,p.z])
	for p in a[Mesh.ARRAY_TEX_UV]: d.uv.append([p.x,p.y])
	var f = FileAccess.open(args[1], FileAccess.WRITE); f.store_string(JSON.stringify(d)); f.close()
	quit()
