extends SceneTree
## Запуск: godot --headless --path . -s tools/islands/relief_preview.gd → /tmp/island_relief/*.png
## Быстрый предпросмотр рельефа островов ShowcaseArch без рендера: карта
## высот с отмывкой, цвет по высоте/биому, вода по глубине. PNG на остров.

func _init() -> void:
	var arch := ShowcaseArch.new(2026)
	var out := "/tmp/island_relief"
	DirAccess.make_dir_recursive_absolute(out)
	var i := 0
	for e: Dictionary in arch.showcase:
		var c: Vector2 = e.center
		var ext: float = float(e.extent) * 1.35 + 40.0
		var n := 360
		var img := Image.create(n, n, false, Image.FORMAT_RGB8)
		var step := ext * 2.0 / n
		var hs := PackedFloat32Array()
		hs.resize(n * n)
		for j in n:
			for k in n:
				hs[j * n + k] = arch.height(c.x - ext + k * step, c.y - ext + j * step)
		var L := Vector3(-1, 1.6, -1).normalized()
		for j in n:
			for k in n:
				var h := hs[j * n + k]
				var hx := hs[j * n + mini(k + 1, n - 1)] - hs[j * n + maxi(k - 1, 0)]
				var hz := hs[mini(j + 1, n - 1) * n + k] - hs[maxi(j - 1, 0) * n + k]
				var nrm := Vector3(-hx, 2.0 * step, -hz).normalized()
				var sh := clampf(nrm.dot(L) * 0.8 + 0.35, 0.15, 1.2)
				var col: Color
				var x := c.x - ext + k * step
				var z := c.y - ext + j * step
				if h < 0.0:
					var t := clampf(-h / 15.0, 0.0, 1.0)
					col = Color(0.55, 0.85, 0.8).lerp(Color(0.04, 0.16, 0.32), sqrt(t))
					if h > -0.9:
						col = col.lerp(Color(0.85, 0.8, 0.6), 0.25)
				else:
					var bw := arch.biome_weights(x, z, h)
					col = Color(0.86, 0.8, 0.6)   # песок
					if h > 1.6:
						col = Color(0.55, 0.62, 0.32)
					col = col.lerp(Color(0.12, 0.36, 0.12), bw.r)
					col = col.lerp(Color(0.32, 0.3, 0.22), bw.g)
					col = col.lerp(Color(0.55, 0.53, 0.5), bw.b)
					col = col.lerp(Color(0.15, 0.13, 0.13), bw.a)
					if nrm.y < 0.6:
						col = col.lerp(Color(0.5, 0.48, 0.45), 0.6)
					col = Color(col.r * sh, col.g * sh, col.b * sh)
				img.set_pixel(k, j, col)
		img.save_png("%s/%02d_%s.png" % [out, i + 1, String(e.type)])
		print("relief ", e.type, " ext ", ext, " hmax ", hs[hs.size() / 2])
		i += 1
	quit()
