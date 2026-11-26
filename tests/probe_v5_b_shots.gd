## test-timeout: 2400
extends TestCase
## Снимки новых моделей агента B (v5) для пользователя: каждая модель — отдельный кадр
## на нейтральном фоне в отдельном SubViewport (свой мир). Кадры: /mnt/user-data/outputs/v5_B_<имя>.png.

const U := "res://assets/user_pack/"
const OUT_DIR := "/mnt/user-data/outputs"
const SHOTS := [
	["ak47", [["weapons/ak47/weapon_ak47.glb", Vector3(0, 0, 0.1), Vector3(0, 90, 0), 1.0]], 1.6, Vector3(0, 0.05, 0)],
	["character_male", [["bot", Vector3.ZERO, Vector3(0, 200, 0), 1.0]], 3.0, Vector3(0, 0.95, 0)],
	["character_male_side", [["bot_rifle", Vector3.ZERO, Vector3(0, 110, 0), 1.0]], 3.0, Vector3(0, 0.95, 0)],
	["melee", [["weapons/melee/weapon_machete.glb", Vector3(-0.35, 0, 0), Vector3(0, 90, 0), 1.0], ["weapons/melee/weapon_axe.glb", Vector3(0.05, 0, 0), Vector3(0, 90, 0), 1.0],
		["weapons/melee/weapon_knife.glb", Vector3(0.4, 0, 0), Vector3(0, 90, 0), 1.0]], 1.4, Vector3(0, 0.25, 0)],
	["items", [["items/item_flashlight.glb", Vector3(-0.25, 0, 0), Vector3(0, 60, 0), 1.0], ["items/item_lighter.glb", Vector3(-0.05, 0, 0), Vector3(0, 30, 0), 1.5],
		["items/item_water_bottle.glb", Vector3(0.12, 0, 0), Vector3.ZERO, 1.0], ["items/item_tourniquet.glb", Vector3(0.3, 0, 0), Vector3(0, 40, 0), 1.0]], 0.9, Vector3(0, 0.02, 0)],
	["ammo", [["items/ammo/ammo_box_762.glb", Vector3(-0.15, 0, 0), Vector3(0, 30, 0), 1.0], ["items/ammo/ammo_box_9mm.glb", Vector3(0.0, 0, 0), Vector3(0, 30, 0), 1.0],
		["items/ammo/ammo_box_12g.glb", Vector3(0.17, 0, 0), Vector3(0, 30, 0), 1.0], ["items/ammo/round_762x39.glb", Vector3(-0.06, -0.06, 0.12), Vector3(90, 0, 0), 2.0],
		["items/ammo/round_12x70.glb", Vector3(0.08, -0.06, 0.12), Vector3(90, 0, 0), 1.5]], 0.6, Vector3(0, 0.0, 0)],
	["pmx", [["weapons/pmx/weapon_beretta_pmx.glb", Vector3.ZERO, Vector3(0, 90, 0), 1.0]], 0.9, Vector3(0, 0.0, 0)],
	["macaw", [["animals/parrots/parrot_macaw_red.glb", Vector3.ZERO, Vector3(0, 60, 0), 1.0]], 1.0, Vector3(0, 0.25, 0)],
	["amazon_frog_butterfly", [["animals/parrots/bird_amazon_parrot.glb", Vector3(-0.15, 0, 0), Vector3(-90, 0, 0), 0.01], ["animals/frog/animal_frog.glb", Vector3(0.2, 0, 0.05), Vector3(0, -30, 0), 0.25],
		["animals/insects/insect_butterfly.glb", Vector3(0.2, 0.22, 0.0), Vector3(0, 20, 0), 0.02]], 0.9, Vector3(0, 0.12, 0)],
	["tuna", [["sea_skel/animal_fish_tuna.glb", Vector3.ZERO, Vector3(0, 90, 0), 0.12]], 1.8, Vector3(0, 0.0, 0)],
	["piranha", [["sea/src_v5/animal_fish_piranha.glb", Vector3.ZERO, Vector3(0, 0, 0), 1.0]], 0.45, Vector3(0, 0.07, 0)],
	["whale", [["sea/src_v5/animal_whale_humpback.glb", Vector3.ZERO, Vector3(0, 90, 0), 0.3]], 18.0, Vector3(0, 0.6, 0)],
	["boat_crate", [["vehicles/vehicle_wooden_boat.glb", Vector3(-1.5, 0, 0), Vector3(0, 30, 0), 0.6], ["items/item_wooden_crate.glb", Vector3(2.3, 0, 0.5), Vector3(0, -20, 0), 1.0],
		["items/item_sticks.glb", Vector3(2.3, 0.45, 0.5), Vector3(0, -20, 0), 1.0]], 7.5, Vector3(0, 0.8, 0)],
]

func _init() -> void:
	scene_path = "res://tests/empty_stage.tscn"   # пустая сцена: рендерится только кадр SubViewport
	timeout_sec = 2400.0

func run() -> void:
	await wait_frames(5)
	var base := Vector3.ZERO
	var vp := SubViewport.new()
	vp.size = Vector2i(1400, 900)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	(scene as Node).add_child(vp)
	var stage := Node3D.new()
	stage.name = "ShotStage"
	vp.add_child(stage)
	var cam := Camera3D.new()
	cam.fov = 35.0
	cam.near = 0.01
	cam.far = 400.0
	stage.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 35, 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	stage.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -140, 0)
	fill.light_energy = 0.5
	stage.add_child(fill)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	# небо для отражений (металл без окружения выглядит чёрным), фон — ровный серый
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.45, 0.6, 0.8)
	psm.sky_horizon_color = Color(0.75, 0.8, 0.85)
	psm.ground_bottom_color = Color(0.35, 0.33, 0.3)
	psm.ground_horizon_color = Color(0.6, 0.6, 0.6)
	sky.sky_material = psm
	env.sky = sky
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.66, 0.7)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	stage.add_child(we)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	for s: Array in SHOTS:
		var holder := Node3D.new()
		stage.add_child(holder)
		holder.global_position = base
		var only := OS.get_environment("SHOT_ONLY")
		if only != "" and not (String(s[0]) in only.split(",")):
			holder.queue_free()
			continue
		for m: Array in s[1]:
			if String(m[0]).begins_with("bot"):
				# персонаж — как у ботов (BotModel: клипы с прибитым корнем, повязка команды)
				var bm := BotModel.new().setup(0, 1)
				holder.add_child(bm)
				bm.rotation_degrees = m[2]
				if String(m[0]) == "bot_rifle":
					bm.set_held(&"rifle")
				continue
			var ps := load(U + String(m[0])) as PackedScene
			check(ps != null, "грузится %s" % m[0])
			if ps == null:
				continue
			var n := ps.instantiate() as Node3D
			holder.add_child(n)
			n.position = m[1]
			n.rotation_degrees = m[2]
			n.scale = Vector3.ONE * float(m[3])
			for ap: AnimationPlayer in n.find_children("*", "AnimationPlayer", true, false):
				var l := ap.get_animation_list()
				if l.has(&"idle"):
					ap.play(&"idle")
				elif l.has(&"idle_perch"):
					ap.play(&"idle_perch")
				elif l.has(&"swim"):
					ap.play(&"swim")
		var dist: float = s[2]
		var look: Vector3 = base + (s[3] as Vector3)
		cam.global_position = look + Vector3(0.0, dist * 0.18, dist)
		cam.look_at(look, Vector3.UP)
		cam.current = true
		await wait_frames(12)
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.save_png(OUT_DIR + "/v5_B_%s.png" % String(s[0]))
		print("[test] снимок v5_B_%s.png" % String(s[0]))
		holder.queue_free()
		await wait_frames(2)
