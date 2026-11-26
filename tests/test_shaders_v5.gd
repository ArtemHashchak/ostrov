## test-class: render
## test-timeout: 300
extends TestCase
## Компиляция шейдеров, которые правил агент D (v5), в настоящем рендере: по одному кубу на шейдер
## перед камерой, несколько кадров. Ошибки компиляции попадают в лог (run.sh → exit 3).

const SHADERS := [
	"res://scripts/world/shaders/terrain_tropic.gdshader",
	"res://scripts/world/shaders/ocean.gdshader",
	"res://scripts/world/flora/foliage.gdshader",
	"res://scripts/world/flora/pack_leaf.gdshader",
	"res://scripts/world/flora/pack_bark.gdshader",
	"res://scripts/world/flora/tree_sway_pbr.gdshader",
	"res://scripts/player/fp_skin.gdshader",
	"res://scripts/world/weather/screen_fx.gdshader",
]

func _init() -> void:
	scene_path = ""

func run() -> void:
	var root := Node3D.new()
	add_child(root)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(0, 0, 6)
	cam.make_current()
	var light := DirectionalLight3D.new()
	root.add_child(light)
	var i := 0
	for path in SHADERS:
		var sh := load(path) as Shader
		check(sh != null, "шейдер загружен: %s" % path)
		if sh == null:
			continue
		var m := ShaderMaterial.new()
		m.shader = sh
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.8, 0.8, 0.8)
		mi.mesh = bm
		mi.material_override = m
		mi.position = Vector3(-3.5 + i * 1.0, 0, 0)
		root.add_child(mi)
		i += 1
	await wait_frames(10)
	await shot("all")
	check(true, "кадры отрисованы")
	root.queue_free()
