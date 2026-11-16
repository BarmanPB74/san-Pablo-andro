class_name FxTex
extends RefCounted
## Texturas procedurales compartidas por los efectos (humo, esferas de energía). Se generan una vez y se reutilizan.

static var _noise: ImageTexture
static var _puff: ImageTexture


## Ruido suave que se repite sin costuras (256 × 256, un canal). Sirve para humo y energía.
static func noise() -> ImageTexture:
	if _noise == null:
		var fn := FastNoiseLite.new()
		fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		fn.fractal_type = FastNoiseLite.FRACTAL_FBM
		fn.fractal_octaves = 4
		fn.frequency = 0.012
		fn.seed = 7
		var img := fn.get_seamless_image(256, 256, false, false, 0.1, true)
		_noise = ImageTexture.create_from_image(img)
	return _noise


## Bocanada de humo: disco suave con bordes irregulares (128 × 128, alfa).
static func puff() -> ImageTexture:
	if _puff == null:
		var fn := FastNoiseLite.new()
		fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		fn.fractal_type = FastNoiseLite.FRACTAL_FBM
		fn.fractal_octaves = 3
		fn.frequency = 0.035
		fn.seed = 21
		var n := 128
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var dx := (float(x) + 0.5) / float(n) * 2.0 - 1.0
				var dy := (float(y) + 0.5) / float(n) * 2.0 - 1.0
				var r := sqrt(dx * dx + dy * dy)
				var nv := fn.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
				var a := pow(clampf(1.0 - r, 0.0, 1.0), 1.5) * (0.45 + 0.9 * nv)
				img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
		_puff = ImageTexture.create_from_image(img)
	return _puff
