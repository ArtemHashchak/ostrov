class_name SeaScenesLib
extends RefCounted
## Каталог сцен моря: id → описание (где и когда уместна) и класс-режиссура.
## Режиссёр (SeaSceneDirector) выбирает сцену по среде (глубина), времени суток и погоде.
## Виды — из океанского состава (OceanRoster): пока у вида нет модели, его играет дублёр,
## и сцены сами подхватят настоящую модель, когда её впишут в слот «model».

## depth — глубина дна в точке сцены; time — day|night|dusk|any; weather — calm|storm|any;
## view — underwater (видно под водой) | surface (с поверхности/берега) | both.
const CATALOG := {
	"hide_coral": {"title": "Рыбы прячутся в кораллы", "depth": [2.0, 10.0], "time": "day", "weather": "any", "view": "underwater"},
	"coral_grazing": {"title": "Стая кормится у коралла", "depth": [1.5, 8.0], "time": "day", "weather": "calm", "view": "underwater"},
	"territorial": {"title": "Дамсель гонит чужаков от своего коралла", "depth": [1.0, 8.0], "time": "day", "weather": "any", "view": "underwater"},
	"cleaner_station": {"title": "Станция чистки: губаны и креветки чистят групера", "depth": [3.0, 14.0], "time": "day", "weather": "calm", "view": "underwater"},
	"spawning_dusk": {"title": "Нерест на закате: стая поднимается облаком, вода мутнеет от икры", "depth": [3.0, 14.0], "time": "dusk", "weather": "calm", "view": "underwater"},
	"shark_hunt": {"title": "Охота акулы на косяк", "depth": [5.0, 40.0], "time": "any", "weather": "any", "view": "both"},
	"crab_chase": {"title": "Краб гоняется за мальком на мелководье", "depth": [0.3, 1.6], "time": "any", "weather": "calm", "view": "both"},
	"crab_rivals": {"title": "Два краба меряются клешнями", "depth": [0.2, 1.6], "time": "any", "weather": "any", "view": "both"},
	"octopus_hunt": {"title": "Осьминог охотится на краба", "depth": [0.8, 4.0], "time": "any", "weather": "calm", "view": "underwater"},
	"octopus_den": {"title": "Осьминог маскируется и прячется в нору", "depth": [1.0, 8.0], "time": "any", "weather": "any", "view": "underwater"},
	"bait_ball": {"title": "Барракуды сбивают мелочь в шар у поверхности, рыбки выпрыгивают", "depth": [4.0, 40.0], "time": "any", "weather": "calm", "view": "both"},
	"blood_sharks": {"title": "Кровь в воде стягивает акул", "depth": [2.0, 40.0], "time": "any", "weather": "any", "view": "both", "reaction": true},
	"storm_churn": {"title": "Шторм: муть, обломки, рыба уходит глубже", "depth": [1.0, 12.0], "time": "any", "weather": "storm", "view": "underwater"},
	"night_reef": {"title": "Ночной риф: осьминог и мурена на охоте, лангусты на марше", "depth": [1.5, 10.0], "time": "night", "weather": "any", "view": "underwater"},
	"parrotfish_crunch": {"title": "Рыба-попугай грызёт коралл и «сыплет» песок", "depth": [1.5, 10.0], "time": "day", "weather": "any", "view": "underwater"},
	"moray_ambush": {"title": "Мурена бросается из расщелины", "depth": [2.0, 12.0], "time": "any", "weather": "any", "view": "underwater"},
	"barracuda_line": {"title": "Барракуды патрулируют цепью и бросаются на мелочь", "depth": [4.0, 30.0], "time": "any", "weather": "any", "view": "underwater"},
	"turtle_grazing": {"title": "Черепаха пасётся на траве и всплывает подышать", "depth": [1.0, 6.0], "time": "day", "weather": "calm", "view": "both"},
	"ray_bury": {"title": "Скат зарылся в песок и взлетает, если подплыть", "depth": [0.8, 8.0], "time": "any", "weather": "any", "view": "underwater"},
	"manta_loops": {"title": "Манты кормятся планктоном петлями на закате", "depth": [6.0, 40.0], "time": "dusk", "weather": "calm", "view": "underwater"},
	"dolphins_bait": {"title": "Дельфины загоняют косяк и выпрыгивают", "depth": [6.0, 200.0], "time": "day", "weather": "calm", "view": "both"},
	"jelly_drift": {"title": "Медузы дрейфуют стаей по течению", "depth": [3.0, 200.0], "time": "any", "weather": "any", "view": "underwater"},
	"clownfish_anemone": {"title": "Рыбы-клоуны в актинии", "depth": [1.0, 8.0], "time": "day", "weather": "any", "view": "underwater"},
	"hermit_swap": {"title": "Рак-отшельник меняет раковину", "depth": [0.15, 1.2], "time": "any", "weather": "calm", "view": "both"},
	"star_barrens": {"title": "Морские ежи и звёзды ползут по «пустоши»", "depth": [0.8, 6.0], "time": "any", "weather": "any", "view": "underwater"},
	"lobster_march": {"title": "Лангусты идут цепочкой по дну", "depth": [2.0, 12.0], "time": "night", "weather": "any", "view": "underwater"},
	"seahorse_grass": {"title": "Морские коньки держатся хвостом за траву", "depth": [0.8, 5.0], "time": "day", "weather": "calm", "view": "underwater"},
	"tide_school": {"title": "Стая держится против приливного течения", "depth": [3.0, 20.0], "time": "any", "weather": "any", "view": "underwater"},
	"seagrass_nursery": {"title": "Морской луг: мальки прячутся в траве", "depth": [0.6, 4.0], "time": "day", "weather": "any", "view": "underwater"},
	"kelp_forest": {"title": "Лес келпа качается в прибое, рыбы снуют между стеблями", "depth": [3.0, 12.0], "time": "any", "weather": "any", "view": "underwater"},
	"whale_breach": {"title": "Кит выпрыгивает вдали", "depth": [15.0, 2000.0], "time": "day", "weather": "calm", "view": "surface", "far": true},
	"coral_spawning": {"title": "Ночной нерест кораллов: всплывают розовые пучки", "depth": [1.5, 10.0], "time": "night", "weather": "calm", "view": "underwater"},
	"gulls_steal": {"title": "Чайки выхватывают рыбу у поверхности", "depth": [2.0, 40.0], "time": "day", "weather": "calm", "view": "surface"},
	"sargassum_raft": {"title": "Плот саргассума: мальки и рыбы под ним", "depth": [3.0, 200.0], "time": "any", "weather": "calm", "view": "both"},
}

static func make(id: String) -> SeaScene:
	var s: SeaScene = null
	match id:
		"hide_coral": s = HideCoral.new()
		"coral_grazing": s = CoralGrazing.new()
		"territorial": s = Territorial.new()
		"cleaner_station": s = CleanerStation.new()
		"spawning_dusk": s = SpawningDusk.new()
		"shark_hunt": s = SharkHunt.new()
		"crab_chase": s = CrabChase.new()
		"crab_rivals": s = CrabRivals.new()
		"octopus_hunt": s = OctopusHunt.new()
		"octopus_den": s = OctopusDen.new()
		"bait_ball": s = BaitBall.new()
		"blood_sharks": s = BloodSharks.new()
		"storm_churn": s = StormChurn.new()
		"night_reef": s = NightReef.new()
		"parrotfish_crunch": s = ParrotfishCrunch.new()
		"moray_ambush": s = MorayAmbush.new()
		"barracuda_line": s = BarracudaLine.new()
		"turtle_grazing": s = TurtleGrazing.new()
		"ray_bury": s = RayBury.new()
		"manta_loops": s = MantaLoops.new()
		"dolphins_bait": s = DolphinsBait.new()
		"jelly_drift": s = JellyDrift.new()
		"clownfish_anemone": s = ClownfishAnemone.new()
		"hermit_swap": s = HermitSwap.new()
		"star_barrens": s = StarBarrens.new()
		"lobster_march": s = LobsterMarch.new()
		"seahorse_grass": s = SeahorseGrass.new()
		"tide_school": s = TideSchool.new()
		"seagrass_nursery": s = SeagrassNursery.new()
		"kelp_forest": s = KelpForest.new()
		"whale_breach": s = WhaleBreach.new()
		"coral_spawning": s = CoralSpawning.new()
		"gulls_steal": s = GullsSteal.new()
		"sargassum_raft": s = SargassumRaft.new()
	if s:
		s.id = id
		s.name = "Scene_" + id
		s.title = String((CATALOG.get(id, {}) as Dictionary).get("title", id))
	return s

static func ids() -> Array:
	return CATALOG.keys()


# =====================================================================================
# Риф днём
# =====================================================================================

## Стая хирургов кормится у кораллов; при приближении пловца или проходящей рифовой акулы
## каждая рыба ныряет в ветви коралла (своё укрытие), потом выплывает.
class HideCoral extends SeaScene:
	var sch: SeaSchool
	var predator: SeaCritter
	var spots: Array = []
	var calm_t := 0.0
	func _begin() -> void:
		duration = 60.0
		spots = cover_spots(at, 4.0, 8)
		sch = school("surgeonfish", 14, in_water(Vector3.ZERO, 1.2), 1.4)
		sch.hold_at(in_water(Vector3.ZERO, 1.0))
	func _step(dt: float) -> void:
		var threat := swimmer_dist(sch.center) < 6.0
		if t > 14.0 and predator == null:
			predator = critter("reef_shark", in_water(Vector3(-14, 0, 3), 1.8))
			if predator:
				predator.goto(in_water(Vector3(14, 0, -2), 1.6), predator.cruise)
		if predator and is_instance_valid(predator) and predator.global_position.distance_to(sch.center) < 7.0:
			threat = true
		if threat:
			calm_t = 0.0
			if sch.mode != SeaSchool.M.HIDE:
				sch.hide_in(spots)
		else:
			calm_t += dt
			if sch.mode == SeaSchool.M.HIDE and calm_t > 4.0:
				sch.hold_at(in_water(Vector3.ZERO, 1.0))

## Хирурги и бабочки пасутся: стая перебирается от коралла к кораллу, особи «клюют».
class CoralGrazing extends SeaScene:
	var sch: SeaSchool
	var pair: Array[SeaCritter] = []
	var spots: Array = []
	var k := 0
	func _begin() -> void:
		duration = 50.0
		spots = cover_spots(at, 5.0, 5)
		sch = school("surgeonfish", 12, in_water(Vector3.ZERO, 0.8), 0.9)
		sch.radius = 0.6
		sch.hold_at(spots[0])
		for i in 2:
			var c := critter("butterflyfish", (spots[1] as Vector3) + Vector3(i * 0.3, 0.3, 0))
			if c:
				pair.append(c)
	func _step(_dt: float) -> void:
		if phase_t > 6.0:
			next_phase()
			k = (k + 1) % spots.size()
			sch.hold_at((spots[k] as Vector3) + Vector3(0, 0.2, 0))
		# бабочки — парой, «клюют» полипы короткими подходами
		for i in pair.size():
			var c := pair[i]
			var sp: Vector3 = spots[(k + 2) % spots.size()]
			var peck := sin(t * 1.3 + i) > 0.6
			c.hold(sp + Vector3(i * 0.25, 0.12 if peck else 0.45, 0.0), sp - c.global_position)

## Дамсель охраняет свой коралл: бросается на пару бабочек, те отступают и возвращаются.
class Territorial extends SeaScene:
	var damsel: SeaCritter
	var intruders: Array[SeaCritter] = []
	var home := Vector3.ZERO
	var dash_t := 0.0
	func _begin() -> void:
		duration = 45.0
		home = (cover_spots(at, 2.0, 1)[0] as Vector3) + Vector3(0, 0.25, 0)
		damsel = critter("damselfish", home)
		for i in 2:
			var c := critter("butterflyfish", home + Vector3(3.0 + i * 0.4, 0.3, 1.0))
			if c:
				intruders.append(c)
	func _step(dt: float) -> void:
		dash_t = maxf(dash_t - dt, 0.0)
		for c in intruders:
			var d := c.global_position.distance_to(home)
			if dash_t <= 0.0 and d < 1.6:
				damsel.goto(c.global_position, damsel.cruise * 4.0)
				damsel.startle(c.global_position + c.forward())
				c.flee(damsel.global_position, 3.0)
				dash_t = 1.2
			elif c.mode != SeaCritter.M.GOTO and c.mode != SeaCritter.M.FLEE:
				c.goto(home + Vector3(0.4, 0.3, 0.2), c.cruise * 0.7)
			elif c.mode == SeaCritter.M.FLEE and c.global_position.distance_to(home) > 4.0:
				c.goto(home + Vector3(0.4, 0.3, 0.2), c.cruise * 0.6)
		if dash_t <= 0.4:
			damsel.hold(home, home - damsel.global_position + Vector3(1, 0, 0))

## Станция чистки: групер замер с приоткрытым ртом, губаны снуют у головы, креветки по дну.
class CleanerStation extends SeaScene:
	var grouper: SeaCritter
	var cleaners: Array[SeaCritter] = []
	var shrimps: Array[SeaCritter] = []
	var station := Vector3.ZERO
	func _begin() -> void:
		duration = 55.0
		station = in_water(Vector3.ZERO, 0.9)
		grouper = critter("grouper", station + Vector3(-6, 0.3, 2))
		if grouper:
			grouper.goto(station, grouper.cruise * 0.8)
		for i in 3:
			var c := critter("cleaner_wrasse", station + Vector3(i * 0.3, 0.2, 0))
			if c:
				c.hold(station + Vector3(0.3 * i, 0.1, 0))
				cleaners.append(c)
		for i in 3:
			var s := critter("cleaner_shrimp", on_floor(Vector3(0.4 * i - 0.4, 0.0, 0.5)))
			if s:
				shrimps.append(s)
	func _step(_dt: float) -> void:
		if grouper == null:
			return
		var g := grouper.global_position
		if t < 40.0:
			if g.distance_to(station) < 0.6:
				grouper.hold(station, grouper.forward())
			for i in cleaners.size():
				# губаны «облетают» голову и жабры клиента
				var head := g + grouper.forward() * grouper.length * 0.35
				var a := t * (1.6 + i * 0.3) + i * 2.1
				cleaners[i].hold(head + Vector3(cos(a) * 0.25, sin(a * 1.3) * 0.12 + 0.05, sin(a) * 0.25))
		else:
			grouper.goto(station + Vector3(8, 0.5, -4), grouper.cruise)
			for c in cleaners:
				c.hold(station + Vector3(0, -0.2, 0))
		for i in shrimps.size():
			var s := shrimps[i]
			s.hold(on_floor(Vector3(0.4 * i - 0.4 + sin(t * 0.3 + i) * 0.1, 0.0, 0.5)), Vector3(0, 0, -1))

## Нерест на закате: стая сжимается, свечой поднимается к поверхности, выпускает облако икры.
class SpawningDusk extends SeaScene:
	var sch: SeaSchool
	func _begin() -> void:
		duration = 45.0
		sch = school("surgeonfish", 24, in_water(Vector3.ZERO, 1.0), 1.6)
		sch.mill(in_water(Vector3.ZERO, 1.2), 1.4)
	func _step(_dt: float) -> void:
		match phase:
			0:
				if phase_t > 8.0:
					next_phase()
					sch.mill_axis_speed = 3.0
					sch.radius = 0.7
					sch.cruise_to(Vector3(at.x, water_y() - 1.0, at.z), 2.2)
			1:
				if sch.center.y > water_y() - 1.4 or phase_t > 6.0:
					next_phase()
					SeaSceneFx.cloud(self, sch.center, 1.4, Color(1.0, 0.92, 0.85, 0.55), 70, 6.0, 0.06, 0.02)
					sch.scatter(sch.center, 2.0, 1.0)
			2:
				if phase_t > 3.0:
					next_phase()
					sch.mill_axis_speed = 1.2
					sch.radius = 1.6
					sch.cruise_to(in_water(Vector3.ZERO, 1.0), 0.8)


# =====================================================================================
# Хищники
# =====================================================================================

## Акула кружит у косяка, бросается — косяк взрывается в стороны (flash expansion) и
## собирается; обрывки добычи тонут, к ним слетается мелочь, у поверхности — чайки.
class SharkHunt extends SeaScene:
	var sch: SeaSchool
	var sh: Node3D = null            # настоящая акула моря (если сцена в море)
	var stand: SeaCritter = null     # дублёр в заглушке
	var small: Array[SeaCritter] = []
	var gulls: Array = []
	var hits := 0
	var cd := 0.0
	func _begin() -> void:
		duration = 55.0
		var c := in_water(Vector3.ZERO, maxf(depth(at.x, at.z) * 0.5, 1.5))
		sch = school("baitfish", 48, c, 1.8)
		sch.mill(c, 1.8)
		sh = shark(&"white", c, 12.0)
		if sh == null:
			stand = critter("tiger_shark", c + Vector3(-12, 0.3, 0))
			if stand:
				stand.orbit(c, 9.0, 1.0, stand.cruise)
	func _shark_pos() -> Vector3:
		if sh and is_instance_valid(sh):
			return sh.global_position
		if stand:
			return stand.global_position
		return Vector3.INF
	func _step(dt: float) -> void:
		cd = maxf(cd - dt, 0.0)
		var sp := _shark_pos()
		if sp == Vector3.INF:
			return
		match phase:
			0:
				if phase_t > 9.0:
					next_phase()
					if sh:
						(sh as Shark).home = Vector2(sch.center.x, sch.center.z)
						(sh as Shark).lure(sch.center, 14.0)
					elif stand:
						stand.goto(sch.center, stand.cruise * 3.0)
			1:
				if stand:
					stand.goal = sch.center
				if sp.distance_to(sch.center) < 3.2 and cd <= 0.0:
					cd = 2.5
					hits += 1
					sch.scatter(sp, 5.0, 1.8)
					SeaSceneFx.scraps(self, sch.center)
					SeaSceneFx.bubbles(self, sch.center, 12, 0.06)
					if sh and sh.has_method(&"_play"):
						sh.call(&"_play", &"bite", true, 0.08)
					if stand:
						stand.startle(sch.center + Vector3(1, 0, 0))
						stand.orbit(sch.center, 7.0, -1.0, stand.cruise * 1.4)
					if small.is_empty():
						for i in 4:
							var f := critter("cleaner_wrasse", sch.center + Vector3(rng.randf_range(-3, 3), -1.0, rng.randf_range(-3, 3)))
							if f:
								f.goto(sch.center + Vector3(0, -0.8, 0), f.cruise * 2.0)
								small.append(f)
					if sch.center.y > water_y() - 3.0 and gulls.is_empty():
						gulls = birds(&"gull", Vector3(sch.center.x, water_y(), sch.center.z), 4)
				if phase_t > 3.0 and cd <= 0.0 and stand:
					stand.goto(sch.center, stand.cruise * 3.0)
				if hits >= 3:
					next_phase()
			2:
				if stand:
					stand.goto(sch.center + Vector3(20, 0, 10), stand.cruise)
		for f in small:
			if is_instance_valid(f):
				f.hold(sch.center + Vector3(sin(t + f.get_instance_id()) * 0.6, -0.9, cos(t * 1.3) * 0.6))
		if not gulls.is_empty():
			birds_to(gulls, Vector3(sch.center.x, water_y() + 3.0, sch.center.z))

## Кровь: две рифовые акулы сходятся к пятну крови и кружат (в море — ещё и настоящие).
class BloodSharks extends SeaScene:
	var sharks_c: Array[SeaCritter] = []
	var blood := Vector3.ZERO
	func _begin() -> void:
		duration = 40.0
		blood = in_water(Vector3.ZERO, 1.5)
		SeaSceneFx.cloud(self, blood, 1.2, Color(0.55, 0.05, 0.05, 0.45), 40, 8.0, 0.3, 0.0)
		if sea is Sea:
			(sea as Sea).add_blood(blood, 1.0)
		for i in 2:
			var c := critter("reef_shark", blood + Vector3(-16 + i * 32, 0.5, 8 - i * 16))
			if c:
				c.goto(blood, c.cruise * 1.6)
				sharks_c.append(c)
	func _step(_dt: float) -> void:
		for i in sharks_c.size():
			var c := sharks_c[i]
			if c.global_position.distance_to(blood) < 5.0 and c.mode == SeaCritter.M.GOTO:
				c.orbit(blood, 2.5 + i, 1.0 if i == 0 else -1.0, c.cruise * 1.5)

## Мурена в расщелине: торчит голова; рыба проходит рядом — бросок, хватает, прячется.
class MorayAmbush extends SeaScene:
	var moray: SeaCritter
	var lair := Vector3.ZERO
	var fish: Array[SeaCritter] = []
	var strike_t := -1.0
	var victim: SeaCritter = null
	func _begin() -> void:
		duration = 50.0
		lair = (cover_spots(at, 2.0, 1)[0] as Vector3) + Vector3(0, 0.05, 0)
		moray = critter("moray", lair)
		if moray:
			moray.hold(lair, Vector3(1, 0, 0))
			moray.max_speed = 4.0
		for i in 3:
			var f := critter("surgeonfish", lair + Vector3(3 + i, 0.5, -2 + i))
			if f:
				f.wander(lair + Vector3(1.5, 0.5, 0), 2.5, f.cruise * 0.8)
				fish.append(f)
	func _step(dt: float) -> void:
		if moray == null:
			return
		if strike_t >= 0.0:
			strike_t += dt
			if strike_t < 0.35 and victim and is_instance_valid(victim):
				moray.goto(victim.global_position, 4.0)
			elif strike_t < 0.5 and victim and is_instance_valid(victim):
				SeaSceneFx.scraps(self, victim.global_position)
				critters.erase(victim)
				victim.queue_free()
				victim = null
			else:
				moray.goto(lair, 1.0)
				if strike_t > 2.5:
					strike_t = -1.0
					moray.hold(lair, Vector3(1, 0, 0))
			return
		# в засаде: голова «дышит», чуть покачивается из расщелины
		moray.hold(lair + Vector3(sin(t * 0.8) * 0.05, 0, 0), Vector3(1, 0, 0))
		for f in fish:
			if is_instance_valid(f) and f.global_position.distance_to(lair) < 1.1:
				strike_t = 0.0
				victim = f
				fish.erase(f)
				for o in fish:
					o.flee(lair, 3.0)
				break

## Барракуды цепью патрулируют край рифа; рывок к косяку мелочи — косяк рассыпается.
class BarracudaLine extends SeaScene:
	var line: Array[SeaCritter] = []
	var sch: SeaSchool
	var lead_goal := Vector3.ZERO
	func _begin() -> void:
		duration = 50.0
		var c := in_water(Vector3.ZERO, 2.0)
		sch = school("baitfish", 30, c + Vector3(6, 0, 4), 1.4)
		sch.hold_at(c + Vector3(6, 0, 4))
		for i in 6:
			var b := critter("barracuda", c + Vector3(-10 - i * 1.4, 0, -4))
			if b:
				line.append(b)
		lead_goal = c + Vector3(10, 0, -4)
	func _step(_dt: float) -> void:
		if line.is_empty():
			return
		var lead := line[0]
		if phase == 0:
			lead.goto(lead_goal, lead.cruise)
			if phase_t > 12.0:
				next_phase()
		elif phase == 1:
			lead.goto(sch.center, lead.cruise * 3.5)
			if lead.global_position.distance_to(sch.center) < 2.5:
				sch.scatter(lead.global_position, 5.0, 2.0)
				next_phase()
		else:
			lead.goto(lead_goal + Vector3(10, 0, 8), lead.cruise)
			if phase_t > 8.0:
				phase = 0
				phase_t = 0.0
				sch.hold_at(sch.center)
		for i in range(1, line.size()):
			line[i].follow(line[i - 1], -line[i - 1].forward() * 1.3, 2.2)

## Шар мелочи у поверхности: барракуды кружат и прорезают его, рыбки выпрыгивают из воды.
class BaitBall extends SeaScene:
	var sch: SeaSchool
	var hunters: Array[SeaCritter] = []
	var cd := 0.0
	var gulls: Array = []
	func _begin() -> void:
		duration = 50.0
		var c := Vector3(at.x, water_y() - 1.4, at.z)
		sch = school("baitfish", 60, c, 1.5)
		sch.mill(c, 1.5)
		for i in 4:
			var b := critter("barracuda", c + Vector3(cos(i * 1.6) * 6, -0.5, sin(i * 1.6) * 6))
			if b:
				b.orbit(c, 4.5, 1.0 if i % 2 == 0 else -1.0, b.cruise * 1.2)
				hunters.append(b)
		gulls = birds(&"gull", Vector3(c.x, water_y(), c.z), 5)
	func _step(dt: float) -> void:
		cd = maxf(cd - dt, 0.0)
		if cd <= 0.0 and not hunters.is_empty():
			cd = 3.0
			var h := hunters[rng.randi() % hunters.size()]
			h.goto(sch.center + (sch.center - h.global_position).normalized() * 3.0, h.cruise * 4.0)
			sch.scatter(h.global_position, 3.0, 1.2)
			sch.leap(rng.randi_range(3, 7), h.global_position)
		for h in hunters:
			if h.mode == SeaCritter.M.GOTO and h.global_position.distance_to(h.goal) < 1.0:
				h.orbit(sch.center, 4.5, 1.0, h.cruise * 1.2)
		birds_to(gulls, Vector3(sch.center.x, water_y() + 2.5, sch.center.z))
		if sch.airborne() > 0 and rng.randf() < dt * 0.8 and sea and sea.has_method(&"splash"):
			sea.call(&"splash", Vector3(sch.center.x + rng.randf_range(-1, 1), water_y(), sch.center.z + rng.randf_range(-1, 1)), 0.6)


# =====================================================================================
# Дно и мелководье
# =====================================================================================

## Краб на мелководье гоняется за мальком: малёк отскакивает, краб щёлкает клешнями впустую.
class CrabChase extends SeaScene:
	var cr: Node3D
	var fry: SeaCritter
	var snap_cd := 0.0
	func _begin() -> void:
		duration = 40.0
		cr = crab(on_floor(Vector3.ZERO), 1.0)
		fry = critter("clownfish", in_water(Vector3(1.2, 0, 0.5), 0.25))
		if fry:
			fry.min_above_floor = 0.05
			fry.wander(on_floor(Vector3(1.0, 0.2, 0)), 1.5, fry.cruise * 0.6)
	func _step(dt: float) -> void:
		snap_cd = maxf(snap_cd - dt, 0.0)
		if fry == null or not is_instance_valid(cr):
			return
		var d := Vector2(fry.global_position.x - cr.global_position.x, fry.global_position.z - cr.global_position.z).length()
		crab_chase(cr, fry)
		if d < 0.55 and snap_cd <= 0.0:
			snap_cd = 1.4
			crab_pinch(cr)
			fry.flee(cr.global_position, 3.5)
		elif fry.mode == SeaCritter.M.FLEE and d > 2.0:
			fry.wander(fry.global_position, 1.2, fry.cruise * 0.6)

## Два краба: поднятые клешни, обмен щипками, проигравший удирает и закапывается.
class CrabRivals extends SeaScene:
	var a: Node3D
	var b: Node3D
	var cd := 0.0
	func _begin() -> void:
		duration = 35.0
		a = crab(on_floor(Vector3(-0.5, 0, 0)), 1.0)
		b = crab(on_floor(Vector3(0.5, 0, 0)), 0.85)
	func _step(dt: float) -> void:
		cd = maxf(cd - dt, 0.0)
		if not (is_instance_valid(a) and is_instance_valid(b)):
			return
		if t < 20.0:
			var d := a.global_position.distance_to(b.global_position)
			if d > 0.6:
				crab_go(a, b.global_position)
				crab_go(b, a.global_position)
			else:
				crab_warn(a, b)
				crab_warn(b, a)
				if cd <= 0.0:
					cd = rng.randf_range(0.6, 1.4)
					crab_pinch(a if rng.randf() < 0.5 else b)
		elif phase == 0:
			next_phase()
			crab_flee(b, a)
		elif phase == 1 and phase_t > 3.0:
			next_phase()
			crab_burrow(b)
			SeaSceneFx.sand_plume(self, b.global_position, 0.4)
			crab_warn(a, b)

## Осьминог подкрадывается к крабу, тот замечает и удирает; рывок — хват (иногда успешный).
class OctopusHunt extends SeaScene:
	var octo: SeaCritter
	var cr: Node3D
	var caught := false
	func _begin() -> void:
		duration = 40.0
		octo = critter("octopus", on_floor(Vector3(-3.0, 0, 0)))
		cr = crab(on_floor(Vector3(1.0, 0, 0.5)), 0.8)
		if octo:
			octo.octo.crawl = 1.0
			octo.octo.camo = 0.6
	func _step(_dt: float) -> void:
		if octo == null or not is_instance_valid(cr):
			return
		var d := octo.global_position.distance_to(cr.global_position)
		match phase:
			0:
				octo.goto(cr.global_position, octo.cruise * 0.7)
				octo.octo.crawl = 1.0
				if d < 1.4:
					next_phase()
					crab_flee(cr, octo)
					octo.octo.threat = 0.6
			1:
				# рывок: оторвался от дна и летит к крабу
				octo.bottom = false
				octo.octo.jet = 1.0
				octo.octo.camo = 0.0
				octo.goto(cr.global_position + Vector3(0, 0.15, 0), 2.6)
				if phase_t > 0.8:
					next_phase()
					caught = rng.randf() < 0.5
					octo.octo.jet = 0.0
					octo.octo.grab = 1.0
					octo.bottom = true
					if caught:
						cr.visible = false
			2:
				octo.hold(octo.global_position, Vector3.ZERO)
				if phase_t > 3.0:
					next_phase()
					octo.octo.grab = 0.0
					if caught:
						crabs.erase(cr)
						cr.queue_free()
			_:
				octo.octo.crawl = 1.0
				octo.goto(on_floor(Vector3(-4, 0, 3)), octo.cruise * 0.6)

## Осьминог ползёт к камню, распластывается и становится цвета дна; подплывёшь — угроза,
## рывок мантией и облако чернил, потом снова прячется в другом месте.
class OctopusDen extends SeaScene:
	var octo: SeaCritter
	var den := Vector3.ZERO
	var den2 := Vector3.ZERO
	func _begin() -> void:
		duration = 50.0
		den = cover_spots(at, 2.5, 1)[0]
		den.y = floor_y(den.x, den.z)
		den2 = on_floor(Vector3(4.0, 0, -2.5))
		octo = critter("octopus", on_floor(Vector3(-2.5, 0, 1.5)))
	func _step(_dt: float) -> void:
		if octo == null:
			return
		var sd := swimmer_dist(octo.global_position)
		match phase:
			0:
				octo.octo.crawl = 1.0
				octo.goto(den, octo.cruise)
				if octo.global_position.distance_to(den) < 0.4:
					next_phase()
			1:
				octo.hold(den)
				octo.octo.crawl = 0.0
				octo.octo.flatten = 1.0
				octo.octo.camo = 1.0
				if sd < 3.0:
					next_phase()
					octo.octo.flatten = 0.0
					octo.octo.camo = 0.0
					octo.octo.threat = 1.0
			2:
				if phase_t > 1.2:
					next_phase()
					octo.octo.threat = 0.0
					octo.octo.jet = 1.0
					octo.bottom = false
					if octo.actor:
						octo.actor.puppet_ink()
					else:
						SeaSceneFx.cloud(self, octo.global_position, 0.4, Color(0.05, 0.05, 0.08, 0.8), 26, 0.4, 0.5)
					octo.goto(den2 + Vector3(0, 0.6, 0), 2.4)
			3:
				if phase_t > 2.0:
					next_phase()
					octo.octo.jet = 0.0
					octo.bottom = true
					den = den2
					phase = 0

## Скат лежит, присыпанный песком; подплывёшь — облако песка и плавный взлёт.
class RayBury extends SeaScene:
	var ray: SeaCritter
	var spot := Vector3.ZERO
	func _begin() -> void:
		duration = 45.0
		spot = on_floor(Vector3.ZERO)
		ray = critter("stingray", spot + Vector3(0, 0.05, 0))
		if ray:
			ray.bottom = true
			ray.hold(spot)
			SeaSceneFx.sand_plume(self, spot, 0.8)
	func _step(_dt: float) -> void:
		if ray == null:
			return
		match phase:
			0:
				# лёжа: тело чуть ниже уровня дна, крылья едва шевелятся
				ray.hold(spot)
				if ray.body:
					ray.body.position.y = lerpf(ray.body.position.y, -0.04, 0.05)
				if swimmer_dist(spot) < 3.0 or (t > 25.0 and swimmer_pos() == Vector3.INF):
					next_phase()
					SeaSceneFx.sand_plume(self, spot, 1.0)
					ray.bottom = false
					ray.goto(in_water(Vector3(8, 0, 5), 1.0), ray.cruise * 2.0)
			1:
				if ray.body:
					ray.body.position.y = lerpf(ray.body.position.y, 0.0, 0.1)
				if phase_t > 8.0:
					ray.goto(in_water(Vector3(-6, 0, 8), 0.8), ray.cruise)

## Морские ежи «пустоши» и звёзды медленно ползут, по камням — красные водоросли.
class StarBarrens extends SeaScene:
	var crawlers: Array[SeaCritter] = []
	func _begin() -> void:
		duration = 60.0
		plant_patch("red_algae", at, 3.0, 10)
		plant_patch("padina", at, 3.0, 12)
		plant_patch("encrusting_sponge", at, 2.5, 6)
		for i in 16:
			var c := critter("urchin", on_floor(Vector3(rng.randf_range(-2.5, 2.5), 0, rng.randf_range(-2.5, 2.5))))
			if c:
				crawlers.append(c)
		for i in 4:
			var c := critter("starfish", on_floor(Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3))))
			if c:
				c.yaw = rng.randf() * TAU
				crawlers.append(c)
	func _step(_dt: float) -> void:
		for c in crawlers:
			if c.mode == SeaCritter.M.HOLD or c.global_position.distance_to(c.goal) < 0.05:
				c.goto(c.global_position + Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6)), 0.03)

## Лангусты ночью идут цепочкой по песку, «держась» за впереди идущего.
class LobsterMarch extends SeaScene:
	var line: Array = []
	var dest := Vector3.ZERO
	func _begin() -> void:
		duration = 50.0
		dest = on_floor(Vector3(12, 0, 4))
		for i in 6:
			line.append(crab(on_floor(Vector3(-i * 0.7, 0, -i * 0.25)), 0.8))
	func _step(_dt: float) -> void:
		for i in line.size():
			var a: Node3D = line[i]
			if not is_instance_valid(a):
				continue
			if i == 0:
				crab_go(a, dest)
			else:
				var prev: Node3D = line[i - 1]
				if is_instance_valid(prev) and a.global_position.distance_to(prev.global_position) > 0.55:
					crab_go(a, prev.global_position)

## Рак-отшельник находит пустую раковину, ощупывает клешнями и переселяется.
class HermitSwap extends SeaScene:
	var hermit: Node3D
	var rival: Node3D
	var shell: Node3D
	func _begin() -> void:
		duration = 40.0
		hermit = crab(on_floor(Vector3(-1.0, 0, 0)), 0.35)
		rival = crab(on_floor(Vector3(-1.2, 0, 0.8)), 0.4)
		if ResourceLoader.exists(UserSeaPack.SHELL):
			shell = (load(UserSeaPack.SHELL) as PackedScene).instantiate() as Node3D
			add_child(shell)
			shell.global_position = on_floor(Vector3(0.8, 0.02, 0.2))
			shell.scale = Vector3.ONE * 1.4
			# у соперника — своя раковина на спине
			var s2 := (load(UserSeaPack.SHELL) as PackedScene).instantiate() as Node3D
			rival.add_child(s2)
			s2.position = Vector3(0, 0.05, 0.05)
			s2.scale = Vector3.ONE * 1.2
	func _step(_dt: float) -> void:
		if not is_instance_valid(hermit) or shell == null:
			return
		match phase:
			0:
				crab_go(hermit, shell.global_position)
				crab_go(rival, shell.global_position + Vector3(0.3, 0, 0.3))
				if hermit.global_position.distance_to(shell.global_position) < 0.25:
					next_phase()
			1:
				# ощупывает: клешни, повороты
				crab_warn(hermit, shell)
				crab_warn(rival, hermit)
				if fmod(phase_t, 1.0) < 0.05:
					crab_pinch(hermit)
				if phase_t > 4.0:
					next_phase()
					SeaSceneFx.sand_plume(self, shell.global_position, 0.25)
					shell.reparent(hermit, false)
					shell.position = Vector3(0, 0.05, 0.05)
					shell.scale = Vector3.ONE * 1.4 / maxf(hermit.scale.x, 0.01)
			2:
				crab_go(hermit, on_floor(Vector3(3, 0, -1)))
				crab_flee(rival, hermit)


# =====================================================================================
# Луг, келп, ночь, течение
# =====================================================================================

## Черепаха пасётся на траве (кивки головой), раз в полминуты всплывает подышать.
class TurtleGrazing extends SeaScene:
	var tu: SeaCritter
	var graze := Vector3.ZERO
	func _begin() -> void:
		duration = 70.0
		plant_patch("turtle_grass", at, 4.0, 60)
		plant_patch("manatee_grass", at, 4.5, 40)
		graze = in_water(Vector3.ZERO, 0.45)
		tu = critter("sea_turtle", graze + Vector3(-3, 0.5, 0))
		if tu:
			tu.goto(graze, tu.cruise)
	func _step(_dt: float) -> void:
		if tu == null:
			return
		match phase:
			0:
				tu.hold(graze + Vector3(sin(t * 0.2) * 0.4, 0, cos(t * 0.17) * 0.4), Vector3(1, 0, 0))
				tu.pitch = sin(t * 1.4) * 0.25 - 0.15     # кивает к траве
				if phase_t > 25.0:
					next_phase()
					tu.max_below_surface = 0.05
					tu.goto(Vector3(graze.x + 2, water_y() - 0.1, graze.z), tu.cruise * 1.2)
			1:
				if tu.global_position.y > water_y() - 0.4:
					next_phase()
					SeaSceneFx.bubbles(self, tu.global_position, 8, 0.08)
					if sea and sea.has_method(&"splash"):
						sea.call(&"splash", Vector3(tu.global_position.x, water_y(), tu.global_position.z), 0.4)
			2:
				tu.hold(Vector3(tu.global_position.x, water_y() - 0.12, tu.global_position.z))
				if phase_t > 3.0:
					next_phase()
					tu.max_below_surface = 0.15
					tu.goto(graze, tu.cruise)
			_:
				if tu.global_position.distance_to(graze) < 0.6:
					phase = 0
					phase_t = 0.0

## Морские коньки держатся хвостом за траву и покачиваются вместе с ней.
class SeahorseGrass extends SeaScene:
	var horses: Array[SeaCritter] = []
	var anchors: Array = []
	func _begin() -> void:
		duration = 60.0
		plant_patch("turtle_grass", at, 2.5, 45)
		plant_patch("caulerpa", at, 2.5, 10)
		for i in 3:
			var a := in_water(Vector3(rng.randf_range(-1.5, 1.5), 0, rng.randf_range(-1.5, 1.5)), 0.35)
			anchors.append(a)
			var c := critter("seahorse", a)
			if c:
				horses.append(c)
	func _step(_dt: float) -> void:
		for i in horses.size():
			var a: Vector3 = anchors[i]
			horses[i].hold(a + Vector3(sin(t * 0.7 + i) * 0.04, 0, cos(t * 0.6 + i) * 0.03), Vector3(cos(t * 0.1 + i), 0, sin(t * 0.1 + i)))

## Морской луг с мальками: стайка снуёт над травой и ныряет в неё, если подплыть.
class SeagrassNursery extends SeaScene:
	var sch: SeaSchool
	var spots: Array = []
	var calm := 0.0
	func _begin() -> void:
		duration = 60.0
		plant_patch("turtle_grass", at, 5.0, 90)
		plant_patch("halimeda", at, 4.0, 14)
		plant_patch("ulva", at, 4.0, 10)
		plant_patch("turbinaria", at, 3.5, 8)
		for i in 10:
			spots.append(on_floor(Vector3(rng.randf_range(-4, 4), 0.12, rng.randf_range(-4, 4))))
		sch = school("juvenile", 32, in_water(Vector3.ZERO, 0.7), 1.2)
		sch.hold_at(in_water(Vector3.ZERO, 0.6))
	func _step(dt: float) -> void:
		if swimmer_dist(sch.center) < 4.0:
			calm = 0.0
			if sch.mode != SeaSchool.M.HIDE:
				sch.hide_in(spots)
		else:
			calm += dt
			if sch.mode == SeaSchool.M.HIDE and calm > 3.0:
				sch.hold_at(in_water(Vector3.ZERO, 0.6))
			elif sch.mode != SeaSchool.M.HIDE and fmod(t, 8.0) < dt:
				sch.hold_at(in_water(Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3)), 0.6))

## Лес келпа: высокие ленты качаются в прибое, между стеблями снуют окуни, у дна — групер.
class KelpForest extends SeaScene:
	var fish: Array[SeaCritter] = []
	func _begin() -> void:
		duration = 70.0
		plant_patch("kelp", at, 6.0, 26, 1.6)
		plant_patch("red_algae", at, 5.0, 12)
		plant_patch("codium", at, 5.0, 10)
		plant_patch("vase_sponge", at, 6.0, 4)
		plant_patch("sea_whip_algae", at, 4.0, 16)
		for i in 5:
			var c := critter("parrotfish" if i == 0 else "angelfish", in_water(Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4)), rng.randf_range(0.8, 2.5)))
			if c:
				c.wander(at + Vector3(0, 1.4, 0), 5.0, c.cruise * 0.7)
				fish.append(c)
		var g := critter("grouper", in_water(Vector3(1, 0, -1), 0.6))
		if g:
			g.wander(at + Vector3(0, 0.6, 0), 3.0, g.cruise * 0.4)

## Стая держится против течения: «висит» на месте, мимо несёт планктон.
class TideSchool extends SeaScene:
	var sch: SeaSchool
	var flow := Vector3.ZERO
	var fx_t := 0.0
	func _begin() -> void:
		duration = 50.0
		var c := in_water(Vector3.ZERO, 2.0)
		sch = school("baitfish", 40, c, 1.8)
		sch.hold_at(c)
		var wd: Vector2 = director.call(&"wind_dir") if director and director.has_method(&"wind_dir") else Vector2(1, 0)
		flow = Vector3(wd.x, 0.0, wd.y).normalized()
	func _step(dt: float) -> void:
		fx_t -= dt
		# стая чуть «сносится» и выгребает обратно
		sch.hold_at(at + Vector3(0, 2.0, 0) + flow * sin(t * 0.35) * 0.8)
		if fx_t <= 0.0:
			fx_t = 3.5
			var p := SeaSceneFx.cloud(self, sch.center - flow * 6.0, 1.6, Color(0.85, 0.95, 0.9, 0.35), 40, 3.0, 0.03, 0.0)
			if p:
				p.direction = flow
				p.spread = 8.0
				p.initial_velocity_min = 1.0
				p.initial_velocity_max = 1.6

## Ночной риф: осьминог ползает на охоте, мурена выходит из норы, лангусты на марше.
class NightReef extends SeaScene:
	var octo: SeaCritter
	var moray: SeaCritter
	var line: Array = []
	func _begin() -> void:
		duration = 70.0
		octo = critter("octopus", on_floor(Vector3(-2, 0, 0)))
		if octo:
			octo.octo.crawl = 1.0
			octo.wander(at, 4.0, octo.cruise * 0.8)
		moray = critter("moray", in_water(Vector3(2, 0, 1), 0.4))
		if moray:
			moray.wander(at + Vector3(0, 0.5, 0), 4.0, moray.cruise)
		for i in 4:
			line.append(crab(on_floor(Vector3(-4 - i * 0.7, 0, 3)), 0.75))
	func _step(_dt: float) -> void:
		for i in line.size():
			var a: Node3D = line[i]
			if not is_instance_valid(a):
				continue
			if i == 0:
				crab_go(a, on_floor(Vector3(6, 0, 3)))
			elif is_instance_valid(line[i - 1]):
				crab_go(a, (line[i - 1] as Node3D).global_position)

## Ночной нерест кораллов: из кораллов поднимаются розовые пучки икры и спермы.
class CoralSpawning extends SeaScene:
	var spots: Array = []
	var k := 0
	var acc := 0.0
	func _begin() -> void:
		duration = 60.0
		spots = cover_spots(at, 5.0, 10)
	func _step(dt: float) -> void:
		acc -= dt
		if acc <= 0.0 and not spots.is_empty():
			acc = 1.2
			var p: Vector3 = spots[k % spots.size()]
			k += 1
			SeaSceneFx.cloud(self, p + Vector3(0, 0.2, 0), 0.25, Color(1.0, 0.72, 0.78, 0.8), 24, 4.0, 0.05, 0.12)

## Шторм: муть у дна, по течению несёт клочья водорослей; стаи уходят ко дну.
class StormChurn extends SeaScene:
	var sch: SeaSchool
	var acc := 0.0
	var flow := Vector3.ZERO
	func _begin() -> void:
		duration = 60.0
		var wd: Vector2 = director.call(&"wind_dir") if director and director.has_method(&"wind_dir") else Vector2(1, 0)
		flow = Vector3(wd.x, 0, wd.y).normalized()
		sch = school("juvenile", 30, on_floor(Vector3(0, 0.3, 0)), 0.8)
		sch.hold_at(on_floor(Vector3(0, 0.25, 0)))
		SeaSceneFx.cloud(self, on_floor(Vector3(0, 0.6, 0)), 4.0, Color(0.55, 0.5, 0.38, 0.35), 90, 50.0, 0.9, 0.05)
	func _step(dt: float) -> void:
		acc -= dt
		if acc <= 0.0:
			acc = 2.0
			var p := SeaSceneFx.cloud(self, in_water(-flow * 6.0, 1.2), 2.0, Color(0.6, 0.48, 0.25, 0.7), 12, 2.0, 0.12, 0.0)
			if p:
				p.direction = flow
				p.spread = 15.0
				p.initial_velocity_min = 1.5
				p.initial_velocity_max = 3.0


# =====================================================================================
# Открытая вода и поверхность
# =====================================================================================

## Манты на закате: кормятся петлями (вертикальное «колесо») в облаке планктона.
class MantaLoops extends SeaScene:
	var mantas: Array[SeaCritter] = []
	var c := Vector3.ZERO
	func _begin() -> void:
		duration = 60.0
		c = in_water(Vector3.ZERO, 3.0)
		SeaSceneFx.cloud(self, c, 4.0, Color(0.85, 0.9, 0.75, 0.25), 80, 55.0, 0.05, 0.0)
		for i in 2:
			var m := critter("manta", c + Vector3(i * 6 - 3, 0, 0))
			if m:
				mantas.append(m)
	func _step(_dt: float) -> void:
		for i in mantas.size():
			var m := mantas[i]
			# петля: круг по горизонтали + подъём/спуск — «колесо» с креном
			var a := t * 0.35 + i * PI
			var p := c + Vector3(cos(a) * 4.0, sin(a * 2.0) * 1.2, sin(a) * 4.0)
			m.goto(p, m.cruise * 1.2)

## Дельфины кружат вокруг шара мелочи, прорезают его и выпрыгивают из воды.
class DolphinsBait extends SeaScene:
	var pod: Array[SeaCritter] = []
	var sch: SeaSchool
	var cd := 4.0
	func _begin() -> void:
		duration = 60.0
		var c := Vector3(at.x, water_y() - 2.0, at.z)
		sch = school("baitfish", 60, c, 1.6)
		sch.mill(c, 1.6)
		for i in 4:
			var d := critter("dolphin", c + Vector3(cos(i * 1.57) * 8, 0.5, sin(i * 1.57) * 8))
			if d:
				d.orbit(c, 6.0, 1.0, d.cruise * 0.8)
				pod.append(d)
	func _step(dt: float) -> void:
		cd -= dt
		if cd <= 0.0 and not pod.is_empty():
			cd = rng.randf_range(3.0, 5.0)
			var d := pod[rng.randi() % pod.size()]
			if rng.randf() < 0.5:
				d.leap((sch.center - d.global_position).normalized() * 4.0 + Vector3(0, 5.5, 0))
				d.global_position.y = water_y() - 0.2
			else:
				d.goto(sch.center + (sch.center - d.global_position).normalized() * 4.0, d.cruise * 1.6)
				sch.scatter(d.global_position, 3.0, 1.0)
		for d in pod:
			if d.mode == SeaCritter.M.GOTO and d.global_position.distance_to(d.goal) < 1.5:
				d.orbit(sch.center, 6.0, 1.0, d.cruise * 0.8)

## Медузы дрейфуют стаей по течению, медленно пульсируя.
class JellyDrift extends SeaScene:
	var flow := Vector3.ZERO
	func _begin() -> void:
		duration = 60.0
		var wd: Vector2 = director.call(&"wind_dir") if director and director.has_method(&"wind_dir") else Vector2(1, 0)
		flow = Vector3(wd.x, 0, wd.y).normalized() * 0.12
		for i in 16:
			var j := critter("jellyfish", in_water(Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4)), rng.randf_range(1.0, 3.5)))
			if j:
				j.drift(flow + Vector3(rng.randf_range(-0.03, 0.03), rng.randf_range(-0.01, 0.02), rng.randf_range(-0.03, 0.03)))

## Рыбы-клоуны в актинии: держатся среди щупалец, выскакивают к чужаку и прячутся обратно.
class ClownfishAnemone extends SeaScene:
	var clowns: Array[SeaCritter] = []
	var host := Vector3.ZERO
	func _begin() -> void:
		duration = 60.0
		host = on_floor(Vector3.ZERO)
		plant_patch("anemone", at, 0.4, 3)
		for i in 3:
			var c := critter("clownfish", host + Vector3(i * 0.1, 0.25, 0))
			if c:
				clowns.append(c)
	func _step(_dt: float) -> void:
		var sd := swimmer_dist(host)
		for i in clowns.size():
			var c := clowns[i]
			if sd < 2.2 and sd > 0.8 and i == 0:
				# самый смелый выскакивает навстречу
				var s := swimmer_pos()
				c.hold(host.lerp(s, 0.35) + Vector3(0, 0.3, 0), s - c.global_position)
			else:
				var a := t * (0.8 + i * 0.2) + i * 2.0
				c.hold(host + Vector3(cos(a) * 0.15, 0.22 + sin(a * 1.7) * 0.05, sin(a) * 0.15))

## Плот саргассума на поверхности: мальки и бабочки держатся в его тени.
class SargassumRaft extends SeaScene:
	var sch: SeaSchool
	var pair: Array[SeaCritter] = []
	var raft := Vector3.ZERO
	func _begin() -> void:
		duration = 60.0
		raft = Vector3(at.x, water_y(), at.z)
		plant_patch("sargassum", raft, 2.0, 16)
		sch = school("juvenile", 26, raft + Vector3(0, -0.6, 0), 0.8)
		sch.hold_at(raft + Vector3(0, -0.6, 0))
		for i in 2:
			var c := critter("butterflyfish", raft + Vector3(i * 0.5, -0.9, 0))
			if c:
				pair.append(c)
	func _step(_dt: float) -> void:
		sch.hold_at(raft + Vector3(sin(t * 0.3) * 0.5, -0.6, cos(t * 0.25) * 0.5))
		for i in pair.size():
			pair[i].hold(raft + Vector3(cos(t * 0.5 + i * PI) * 0.8, -1.0, sin(t * 0.5 + i * PI) * 0.8))

## Рыба-попугай кусает коралл (облачко коралловой пыли), потом «сыплет» песок на ходу.
class ParrotfishCrunch extends SeaScene:
	var pf: SeaCritter
	var spots: Array = []
	var k := 0
	var bite_cd := 0.0
	func _begin() -> void:
		duration = 50.0
		spots = cover_spots(at, 4.0, 4)
		pf = critter("parrotfish", in_water(Vector3(-3, 0, 0), 1.0))
	func _step(dt: float) -> void:
		if pf == null:
			return
		bite_cd = maxf(bite_cd - dt, 0.0)
		var sp: Vector3 = spots[k % spots.size()]
		var mouth := pf.global_position + pf.forward() * pf.length * 0.5
		if phase == 0:
			pf.goto(sp + Vector3(0, 0.25, 0), pf.cruise)
			if mouth.distance_to(sp) < 0.55:
				next_phase()
		elif phase == 1:
			pf.hold(sp + Vector3(0, 0.3, 0) - pf.forward() * 0.2, sp - pf.global_position)
			if bite_cd <= 0.0:
				bite_cd = 1.1
				pf.startle(pf.global_position - pf.forward())   # рывок-укус
				SeaSceneFx.sand_plume(self, sp + Vector3(0, 0.2, 0), 0.25, Color(0.92, 0.9, 0.86))
			if phase_t > 6.0:
				next_phase()
		else:
			pf.goto(sp + Vector3(4, 0.8, 2), pf.cruise)
			if fmod(phase_t, 1.5) < dt:
				SeaSceneFx.sand_plume(self, pf.global_position - pf.forward() * pf.length * 0.6, 0.18, Color(0.95, 0.93, 0.88))
			if phase_t > 5.0:
				phase = 0
				phase_t = 0.0
				k += 1

## Кит вдали: выныривает, выпрыгивает и падает с огромным всплеском (виден с поверхности/берега).
class WhaleBreach extends SeaScene:
	var wh: SeaCritter
	var cd := 3.0
	func _begin() -> void:
		duration = 70.0
		wh = critter("whale", Vector3(at.x, water_y() - 6.0, at.z))
		if wh:
			wh.max_below_surface = 0.5
			wh.wander(Vector3(at.x, water_y() - 5.0, at.z), 30.0, wh.cruise * 0.6)
	func _step(dt: float) -> void:
		if wh == null:
			return
		cd -= dt
		if cd <= 0.0 and wh.mode != SeaCritter.M.BALLISTIC:
			cd = rng.randf_range(16.0, 24.0)
			wh.global_position.y = water_y() - 2.0
			wh.leap(wh.forward() * 3.0 + Vector3(0, 9.0, 0))
		if wh.mode == SeaCritter.M.GOTO and wh.global_position.y < water_y() - 3.0:
			wh.wander(Vector3(at.x, water_y() - 5.0, at.z), 30.0, wh.cruise * 0.6)

## Чайки над косяком у поверхности: кружат низко, пикируют за рыбой (всплески).
class GullsSteal extends SeaScene:
	var sch: SeaSchool
	var gulls: Array = []
	var cd := 2.0
	func _begin() -> void:
		duration = 45.0
		var c := Vector3(at.x, water_y() - 0.8, at.z)
		sch = school("baitfish", 40, c, 1.2)
		sch.mill(c, 1.2)
		gulls = birds(&"gull", Vector3(c.x, water_y(), c.z), 6)
	func _step(dt: float) -> void:
		cd -= dt
		birds_to(gulls, Vector3(sch.center.x, water_y() + 2.0, sch.center.z))
		if cd <= 0.0:
			cd = rng.randf_range(1.5, 3.0)
			var p := Vector3(sch.center.x + rng.randf_range(-1.2, 1.2), water_y(), sch.center.z + rng.randf_range(-1.2, 1.2))
			if sea and sea.has_method(&"splash"):
				sea.call(&"splash", p, 0.5)
			sch.scatter(p + Vector3(0, -0.3, 0), 2.0, 0.8)
			sch.leap(2, p)
