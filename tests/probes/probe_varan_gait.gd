## test-timeout: 300
extends TestCase
## Зонд походки варана: скорость опорной лапы клипа (м/с при speed_scale 1), размах бокового изгиба
## позвоночника и высота корпуса над лапами — клип автора и с поправкой UserClipRig.gait (v5.1).

func run() -> void:
	await wait_frames(2)
	for fixed in [false, true]:
		UserClipRig.next_variant = 0
		var root := UserClipRig.build_variant(&"monitor", 0)
		add_child(root)
		var c: UserClipRig = root.get_meta(&"anim")
		if not fixed:
			c.variant = c.variant.duplicate()
			c.variant.erase("gait")
		for clip in ["walk", "run"]:
			c.player.play(clip, 0.0)
			c.player.seek(0.0, true)
			var an := c.player.get_animation(clip)
			var dt := an.length / 60.0
			# прогрев веса поправки
			for k in 40:
				c.player.advance(dt)
				if fixed:
					c._gait_fix(dt)
			var sk := root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
			c._skel = sk
			var feet := [sk.find_bone("foot.L"), sk.find_bone("foot.R"), sk.find_bone("hand.L"), sk.find_bone("hand.R")]
			var s0 := sk.find_bone("spine.00")
			var s3 := sk.find_bone("spine.03")
			var ymin := INF
			var ymax := -INF
			var bh := 0.0
			var low_all := INF
			for i in 60:
				c.player.advance(dt)
				if fixed:
					c._gait_fix(dt)
				var low := INF
				for f: int in feet:
					low = minf(low, c._gpose(f).origin.y)
				var d := c._gpose(s3).origin - c._gpose(s0).origin
				var yaw := rad_to_deg(atan2(d.x, -d.z))
				ymin = minf(ymin, yaw)
				ymax = maxf(ymax, yaw)
				bh += c._gpose(s0).origin.y - low
				low_all = minf(low_all, low)
			print("[varan] fixed=%s %s yaw_range=%.1f° body_h=%.3f low=%.3f lift=%.3f" % [fixed, clip, ymax - ymin, bh / 60.0, low_all, c.gait_lift])
		root.queue_free()
		await wait_frames(1)
	check(true, "зонд")
