extends SceneTree
## Verifica que todas las funciones públicas de Palette existen y devuelven Material.
## Uso: godot --headless --path . -s res://tests/palette_check.gd

func _initialize() -> void:
	var fails := 0
	var checks := {
		"asphalt": Palette.asphalt(), "wet_asphalt": Palette.wet_asphalt(),
		"sidewalk": Palette.sidewalk(), "curb": Palette.curb(), "plaza_tile": Palette.plaza_tile(),
		"grass": Palette.grass(), "road_line": Palette.road_line(), "brick": Palette.brick(),
		"stucco0": Palette.stucco(), "stucco5": Palette.stucco(5), "stucco-1": Palette.stucco(-1),
		"concrete": Palette.concrete(), "roof_tile": Palette.roof_tile(),
		"window_glass": Palette.window_glass(), "window_lit": Palette.window_lit(),
		"metal_dark": Palette.metal_dark(), "wood": Palette.wood(), "bronze": Palette.bronze(),
		"stone": Palette.stone(), "foliage": Palette.foliage(), "bark": Palette.bark(),
		"neon": Palette.neon(Color.CYAN), "neon_e": Palette.neon(Color.MAGENTA, 6.0),
		"lamp_bulb": Palette.lamp_bulb(), "car_paint": Palette.car_paint(Color.RED),
		"tire": Palette.tire(), "chrome": Palette.chrome(), "headlight": Palette.headlight(),
		"taillight": Palette.taillight(), "cloth": Palette.cloth(Color.BLUE),
		"cloth_r": Palette.cloth(Color.BLUE, 0.5), "skin": Palette.skin(),
		"skin_t": Palette.skin(Color(0.4, 0.3, 0.2)), "mountain_far": Palette.mountain_far(),
		"rain_drop": Palette.rain_drop(), "rain_splash": Palette.rain_splash(),
	}
	for k in checks:
		var m = checks[k]
		if not (m is Material):
			print("FAIL ", k)
			fails += 1
		elif m is ShaderMaterial and (m as ShaderMaterial).shader == null:
			print("FAIL (sin shader) ", k)
			fails += 1
	Palette.set_weather(0.5, 0.5, Color.GRAY, 0.5)
	if Palette.asphalt() != Palette.asphalt():
		print("FAIL cache")
		fails += 1
	print("PALETTE_CHECK ", "OK" if fails == 0 else "FAILS=%d" % fails, " (%d materiales)" % checks.size())
	quit(1 if fails > 0 else 0)
