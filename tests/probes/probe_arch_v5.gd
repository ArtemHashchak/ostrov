extends SceneTree
func _init() -> void:
	for sd in [1, 2, 2026]:
		var t0 := Time.get_ticks_msec()
		var a := ArchipelagoV5.new(sd)
		var t1 := Time.get_ticks_msec()
		print("seed %d build %d ms %s" % [sd, t1 - t0, a.summary()])
		var mn := 1e9
		for i in a.islands.size():
			for j in range(i + 1, a.islands.size()):
				mn = minf(mn, a.strait_gap(a.islands[i], a.islands[j]))
		var gaps := []
		for L in a.links:
			gaps.append(int(L.gap))
		print("  min pair gap %.0f, link gaps %s" % [mn, str(gaps)])
		var mx := 0.0
		for I in a.islands:
			mx = maxf(mx, (I.center as Vector2).length() + float(I.radius))
			print("  #%d %s/%s cls=%s c=%s R=%.0f" % [I.id, I.type, I.kind, a.class_of(I), str(Vector2i(I.center)), I.radius])
		var ts := Time.get_ticks_usec()
		var s := 0.0
		for k in 20000:
			s += a.height(randf_range(-1500, 1500), randf_range(-1500, 1500))
		print("  height avg %.1f us; reach %.0f" % [(Time.get_ticks_usec() - ts) / 20000.0, mx])
		var hr := []
		for k in 12:
			var ang := k * TAU / 12.0
			hr.append(snappedf(a.height(cos(ang) * a.ring_r(ang), sin(ang) * a.ring_r(ang)), 0.1))
		print("  ring crest h ", hr, " passes ", a.reef_passes)
	quit()
