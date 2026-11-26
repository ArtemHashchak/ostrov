## test-timeout: 600
## test-class: render
extends CombatTestCase
## Снимки HUD механик V5: отметка попадания (тело/голова/убийство), строка состояния тела
## («мокрый · холодно»), помутнение от жажды.

func run() -> void:
	if not await setup_combat():
		return
	SupplyItems.register()
	await equip(&"rifle")
	await wait(0.5)
	var c := ctrl()
	var m := c._marker as CombatController.HitMarker
	m.show_hit(false)
	m.set_process(false)
	await wait_frames(2)
	await shot("hitmarker_body")
	m.show_hit(true)
	await wait_frames(2)
	await shot("hitmarker_head")
	m.show_hit(false, true)
	await wait_frames(2)
	await shot("hitmarker_kill")
	m._t = 0.0
	m.queue_redraw()
	p.body.set_physics_process(false)
	p.body.wetness = 1.0
	p.body.temp = -0.6
	p.body._label.text = p.body.hud_text()
	await wait_frames(2)
	await shot("body_wet_cold")
	p.thirst = 3.0
	var a := p.body.thirst_blur()
	p.body._blur.visible = true
	(p.body._blur.material as ShaderMaterial).set_shader_parameter(&"amount", a)
	await wait_frames(3)
	await shot("thirst_blur")
