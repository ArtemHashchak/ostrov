class_name PackSharkAnim
extends RefCounted
## Большая белая из пака пользователя: все 10 клипов модели через AnimationTree с плавным
## смешиванием вместо переключения AnimationPlayer.play():
##   * ход — BlendSpace2D: x — поворот (turn_left … turn_right), y — скорость (idle → swim → swim_fast);
##   * разовые — OneShot с плавным входом/выходом: bite / bite_2 (по очереди), eat, hurt;
##   * смерть — переход в die (последний кадр держится);
##   * пасть — модификатор скелета JawGape: в атаке у жертвы пасть приоткрывается заранее
##     (кость JawLower), сам укус — клип bite.
## Корневого смещения нет: клипы двигают кости на месте, перемещает акулу её ИИ (Shark).

const LOOPS := ["idle", "swim", "swim_fast", "turn_left", "turn_right"]

var tree: AnimationTree
var jaw: JawGape
var _clips: Dictionary = {}       # короткое имя → полное имя в библиотеке
var _bite_alt := false
var _blend := Vector2(0.0, 1.0)
var _gape := 0.0
var _dead := false

## Собрать дерево анимации под моделью пака (узел "Skel" из SharkModel.build_pack).
func setup(model: Node3D) -> bool:
	var skel_root := model.get_node_or_null(^"Skel")
	if skel_root == null:
		return false
	var aps := skel_root.find_children("*", "AnimationPlayer", true, false)
	if aps.is_empty():
		return false
	var ap := aps[0] as AnimationPlayer
	for an in ap.get_animation_list():
		var short := String(an).get_slice("/", String(an).get_slice_count("/") - 1)
		_clips[short] = an
		if LOOPS.has(short):
			ap.get_animation(an).loop_mode = Animation.LOOP_LINEAR
	for need in ["swim", "idle", "swim_fast", "turn_left", "turn_right"]:
		if not _clips.has(need):
			return false
	ap.stop()
	ap.active = false
	tree = AnimationTree.new()
	tree.name = "AnimTree"
	ap.get_parent().add_child(tree)
	tree.anim_player = tree.get_path_to(ap)
	tree.tree_root = _build_tree()
	tree.active = true
	tree.set(&"parameters/life/transition_request", "alive")
	var sks := skel_root.find_children("*", "Skeleton3D", true, false)
	if not sks.is_empty():
		var sk := sks[0] as Skeleton3D
		if sk.find_bone("JawLower") >= 0:
			jaw = JawGape.new()
			jaw.name = "JawGape"
			sk.add_child(jaw)
	return true

func _anim(short: String) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = _clips.get(short, _clips["swim"])
	return a

func _build_tree() -> AnimationNodeBlendTree:
	var bt := AnimationNodeBlendTree.new()
	var loco := AnimationNodeBlendSpace2D.new()
	loco.min_space = Vector2(-1.0, 0.0)
	loco.max_space = Vector2(1.0, 2.0)
	loco.blend_mode = AnimationNodeBlendSpace2D.BLEND_MODE_INTERPOLATED
	loco.add_blend_point(_anim("idle"), Vector2(0.0, 0.0), -1, &"idle")
	loco.add_blend_point(_anim("swim"), Vector2(0.0, 1.0), -1, &"swim")
	loco.add_blend_point(_anim("swim_fast"), Vector2(0.0, 2.0), -1, &"fast")
	loco.add_blend_point(_anim("turn_left"), Vector2(-1.0, 1.0), -1, &"left1")
	loco.add_blend_point(_anim("turn_right"), Vector2(1.0, 1.0), -1, &"right1")
	loco.add_blend_point(_anim("turn_left"), Vector2(-1.0, 0.0), -1, &"left0")
	loco.add_blend_point(_anim("turn_right"), Vector2(1.0, 0.0), -1, &"right0")
	loco.add_blend_point(_anim("turn_left"), Vector2(-1.0, 2.0), -1, &"left2")
	loco.add_blend_point(_anim("turn_right"), Vector2(1.0, 2.0), -1, &"right2")
	bt.add_node(&"loco", loco, Vector2(0, 0))
	var ts := AnimationNodeTimeScale.new()
	bt.add_node(&"ts", ts, Vector2(200, 0))
	bt.connect_node(&"ts", 0, &"loco")
	var prev := &"ts"
	var x := 400
	for os_name: String in ["bite", "bite_2", "eat", "hurt"]:
		var os := AnimationNodeOneShot.new()
		os.fadein_time = 0.12 if os_name != "eat" else 0.25
		os.fadeout_time = 0.25
		os.mix_mode = AnimationNodeOneShot.MIX_MODE_BLEND
		var node := StringName("os_" + os_name)
		bt.add_node(node, os, Vector2(x, 0))
		var clip := StringName("clip_" + os_name)
		bt.add_node(clip, _anim(os_name), Vector2(x, 200))
		bt.connect_node(node, 0, prev)
		bt.connect_node(node, 1, clip)
		prev = node
		x += 200
	var life := AnimationNodeTransition.new()
	life.add_input("alive")
	life.add_input("dead")
	life.xfade_time = 0.2
	bt.add_node(&"life", life, Vector2(x, 0))
	bt.add_node(&"clip_die", _anim("die"), Vector2(x, 200))
	bt.connect_node(&"life", 0, prev)
	bt.connect_node(&"life", 1, &"clip_die")
	bt.connect_node(&"output", 0, &"life")
	return bt

## Каждый кадр вблизи. rel — скорость к крейсерской (0…~3), turn — скорость поворота −1…1
## (+ — влево), gape — пасть 0…1 (атака у жертвы).
func update(dt: float, rel: float, turn: float, gape: float) -> void:
	if tree == null or _dead:
		return
	var y := clampf((rel - 0.25) / 0.75, 0.0, 1.0) if rel < 1.0 else clampf(1.0 + (rel - 1.0) / 0.9, 1.0, 2.0)
	var want := Vector2(clampf(-turn, -1.0, 1.0), y)
	_blend = _blend.lerp(want, clampf(dt * 4.0, 0.0, 1.0))
	tree.set(&"parameters/loco/blend_position", _blend)
	tree.set(&"parameters/ts/scale", clampf(0.6 + rel * 0.4, 0.5, 1.8))
	_gape = move_toward(_gape, gape, dt * (5.0 if gape > _gape else 2.5))
	if jaw:
		jaw.amount = _gape

## Разовая анимация: bite (по очереди bite/bite_2), eat, hurt; die — смерть.
func fire(short: StringName) -> void:
	if tree == null:
		return
	if short == &"die":
		_dead = true
		tree.set(&"parameters/life/transition_request", "dead")
		if jaw:
			jaw.amount = 0.0
		return
	var node := String(short)
	if short == &"bite":
		node = "bite_2" if _bite_alt and _clips.has("bite_2") else "bite"
		_bite_alt = not _bite_alt
		_gape = 0.0
	if not _clips.has(node):
		return
	tree.set(StringName("parameters/os_%s/request" % node), AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

func is_playing_oneshot() -> bool:
	if tree == null:
		return false
	for n in ["bite", "bite_2", "eat", "hurt"]:
		if bool(tree.get(StringName("parameters/os_%s/active" % n))):
			return true
	return false

## Что сейчас видно (для тестов и отладки): die / разовый клип / основной клип хода.
func current() -> String:
	if _dead:
		return "die"
	if tree:
		for n in ["bite", "bite_2", "eat", "hurt"]:
			if bool(tree.get(StringName("parameters/os_%s/active" % n))):
				return n
	if _blend.y < 0.5:
		return "idle"
	if absf(_blend.x) > 0.5:
		return "turn_left" if _blend.x < 0.0 else "turn_right"
	return "swim_fast" if _blend.y > 1.5 else "swim"

func is_active() -> bool:
	return tree != null and tree.active

func set_active(on: bool) -> void:
	if tree:
		tree.active = on


## Модификатор скелета: приоткрыть нижнюю челюсть поверх анимации.
class JawGape extends SkeletonModifier3D:
	var amount := 0.0
	var max_angle := 0.42
	var axis := Vector3(1.0, 0.0, 0.0)
	var _bone := -1

	func _process_modification() -> void:
		var sk := get_skeleton()
		if sk == null:
			return
		if _bone < 0:
			_bone = sk.find_bone("JawLower")
			if _bone < 0:
				return
		if amount <= 0.001:
			return
		var q := sk.get_bone_pose_rotation(_bone)
		sk.set_bone_pose_rotation(_bone, q * Quaternion(axis, max_angle * amount))
