class_name TestProp
extends StaticBody3D
## Тестовые интерактивные объекты для сцены-заглушки:
##  kind = "log"   — бревно: E — взять на плечо / положить (как в The Forest)
##  kind = "target"— мишень для удара: считает попадания

@export var kind: StringName = &"log"
var hits: int = 0
var _carrier: Node = null

func get_interact_text(player: Node) -> String:
	match kind:
		&"log":
			return "E — положить бревно" if _carrier == player else "E — поднять бревно"
		_:
			return ""

func interact(player: Node) -> void:
	if kind != &"log":
		return
	if _carrier == null and not player.get(&"carrying_log"):
		_carrier = player
		visible = false
		collision_layer = 0
		player.call(&"set_carrying_log", true, self)
	elif _carrier == player:
		_carrier = null
		var p := player as Node3D
		var fwd: Vector3 = player.call(&"get_look_dir")
		fwd.y = 0.0
		global_position = p.global_position + fwd.normalized() * 1.6 + Vector3.UP * 0.25
		visible = true
		collision_layer = 1
		player.call(&"set_carrying_log", false)

func on_hit(_by: Node, _hit: Dictionary) -> void:
	hits += 1
	var tw := create_tween()
	tw.tween_property(self, ^"rotation:z", 0.06, 0.05)
	tw.tween_property(self, ^"rotation:z", 0.0, 0.12)
