class_name Gunplay
extends RefCounted
## Состояние стрельбы из современного оружия (WeaponDef) у игрока — CombatController
## держит по экземпляру на оружие в руке:
##  • разброс: бедро/прицел, движение, прыжок, присед, рост от очереди (bloom) с возвратом;
##  • отдача: паттерн по номеру выстрела в очереди → смещение прицела (aim), которое после
##    очереди плавно возвращается (recoil_recover); update() отдаёт приращение взгляда;
##  • пружина камеры (визуальный пинок, kick) и отката оружия в руках (gun_kick);
##  • нагрев ствола (heat) — дымок после очереди.

var d: WeaponDef
var bloom := 0.0            # град — добавка разброса от очереди
var burst := 0              # номер выстрела в текущей очереди
var t := 0.0
var last_shot_t := -10.0
var aim_target := Vector2.ZERO   # (pitch, yaw), рад — куда отдача увела прицел
var aim_off := Vector2.ZERO      # плавно догоняет aim_target
var applied := Vector2.ZERO      # уже применено к взгляду игрока
var kick := Vector3.ZERO         # пружина камеры (pitch, yaw, roll), рад
var kick_v := Vector3.ZERO
var gun_kick := 0.0              # откат оружия (0..~1)
var gun_kick_v := 0.0
var heat := 0.0
var shots := 0

func _init(def: WeaponDef) -> void:
	d = def

## Текущий разброс (град). ads 0..1, speed01 — доля скорости бега.
func spread(ads: float, speed01: float, on_floor: bool, crouch: bool) -> float:
	var s := lerpf(d.spread_hip, d.spread_ads, ads)
	s += d.spread_move * clampf(speed01, 0.0, 1.5) * lerpf(1.0, 0.6, ads)
	if not on_floor:
		s += d.spread_jump
	s += bloom * lerpf(1.0, 0.5, ads)
	if crouch:
		s *= d.spread_crouch_mult
	return s

## Выстрел: паттерн отдачи, рост разброса, импульсы пружин, нагрев.
func on_shot(ads: float) -> Vector2:
	var r := d.recoil_at(burst)
	var k := lerpf(1.0, d.recoil_ads_mult, ads)
	r = r * k + Vector2(randf_range(-1.0, 1.0), randf_range(-0.3, 0.3)) * d.recoil_random
	# вверх — pitch +, вправо — yaw − (как мышь)
	aim_target += Vector2(deg_to_rad(r.y), -deg_to_rad(r.x))
	burst += 1
	shots += 1
	last_shot_t = t
	bloom = minf(bloom + d.spread_per_shot, d.spread_max)
	var v0 := deg_to_rad(d.camera_kick) * sqrt(d.spring_stiffness) * 1.7 * k
	kick_v += Vector3(v0, randf_range(-0.35, 0.35) * v0, randf_range(-0.6, 0.6) * v0)
	gun_kick_v += 22.0 * k
	heat = minf(heat + 0.09, 1.5)
	return r

## Кадр: возврат прицела и разброса, пружины. Возвращает приращение взгляда (pitch, yaw).
func update(delta: float) -> Vector2:
	var t_prev := t
	t += delta
	var since := t - last_shot_t
	# возврат — только за время после задержки (при низком FPS не гасим отдачу в кадре выстрела целиком)
	var rec_dt := clampf(t - maxf(t_prev, last_shot_t + d.recoil_recover_delay), 0.0, delta)
	if rec_dt > 0.0:
		aim_target *= exp(-d.recoil_recover * rec_dt)
		if aim_target.length() < 0.0002:
			aim_target = Vector2.ZERO
		bloom = move_toward(bloom, 0.0, d.spread_recover * rec_dt)
	if since > maxf(0.3, d.cooldown() * 2.5):
		burst = 0
	aim_off = aim_off.lerp(aim_target, 1.0 - exp(-38.0 * delta))
	var dl := aim_off - applied
	applied = aim_off
	# пружины (полунеявный Эйлер, мелкими шагами — устойчиво при просадках FPS)
	var steps := clampi(ceili(delta / 0.008), 1, 8)
	var h := delta / steps
	for i in steps:
		kick_v += (-d.spring_stiffness * kick - d.spring_damping * kick_v) * h
		kick += kick_v * h
		gun_kick_v += (-320.0 * gun_kick - 26.0 * gun_kick_v) * h
		gun_kick += gun_kick_v * h
	heat = move_toward(heat, 0.0, 0.3 * delta)
	return dl

## Сброс при смене оружия: возвращаем непогашенную отдачу взгляду (без рывка — плавно уже не успеем).
func reset() -> Vector2:
	var back := -applied
	aim_target = Vector2.ZERO
	aim_off = Vector2.ZERO
	applied = Vector2.ZERO
	kick = Vector3.ZERO
	kick_v = Vector3.ZERO
	gun_kick = 0.0
	gun_kick_v = 0.0
	bloom = 0.0
	burst = 0
	return back
