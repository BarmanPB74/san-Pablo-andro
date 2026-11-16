class_name HouseMaterials
extends RefCounted
## Materiales de La Casa: piedra gris, madera oscura y telas apagadas. Solo colores góticos (grises fríos, negro, vino
## y morado muy apagados, bronce deslucido); nada saturado. Texturas procedurales que se generan una vez y se reutilizan.

static var _mats := {}
static var _tex := {}


static func all() -> Dictionary:
	if _mats.is_empty():
		_build()
	return _mats


@warning_ignore("integer_division")
static func _tex_stone(key: String, rows: int, cols: int, stagger: bool, seed_v: int, lo: float, hi: float) -> ImageTexture:
	if _tex.has(key):
		return _tex[key]
	var n := 128
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.fractal_octaves = 3
	fn.frequency = 0.05
	fn.seed = seed_v
	var src := fn.get_seamless_image(n, n, false, false, 0.1, true)
	var rh := n / rows
	var cw := n / cols
	var tones: Array[float] = []
	for i in rows * cols:
		tones.append(rng.randf_range(lo, hi))
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		var r := y / rh
		var off := (cw / 2) if (stagger and r % 2 == 1) else 0
		for x in n:
			var xx := (x + off) % n
			var tone: float = tones[r * cols + xx / cw]
			var v := tone * (0.84 + 0.16 * src.get_pixel(x, y).r)
			if y % rh < 2 or xx % cw < 2:
				v *= 0.5
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex[key] = t
	return t


static func _tex_noise(key: String, seed_v: int, freq: float, lo: float, hi: float) -> ImageTexture:
	if _tex.has(key):
		return _tex[key]
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.fractal_octaves = 3
	fn.frequency = freq
	fn.seed = seed_v
	var src := fn.get_seamless_image(128, 128, false, false, 0.1, true)
	var img := Image.create(128, 128, false, Image.FORMAT_RGB8)
	for y in 128:
		for x in 128:
			var v := lerpf(lo, hi, clampf(src.get_pixel(x, y).r, 0.0, 1.0))
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex[key] = t
	return t


## Tablas de madera: 8 por tile, cada una con su tono, vetas y juntas de testa.
@warning_ignore("integer_division")
static func _tex_planks() -> ImageTexture:
	if _tex.has("planks"):
		return _tex["planks"]
	var n := 128
	var planks := 8
	var pw := n / planks
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var tones: Array[float] = []
	var offs: Array[int] = []
	for i in planks:
		tones.append(rng.randf_range(0.78, 1.0))
		offs.append(rng.randi_range(0, n - 1))
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var i := clampi(x / pw, 0, planks - 1)
			var c: float = tones[i] * (0.94 + 0.06 * sin(TAU * 7.0 * float(y) / float(n) + float(i) * 1.7))
			if x % pw == 0:
				c *= 0.5
			if (y + offs[i]) % 64 == 0:
				c *= 0.55
			img.set_pixel(x, y, Color(c, c, c))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex["planks"] = t
	return t


static func _textured(tex: Texture2D, tint: Color, tile_m: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.albedo_texture = tex
	m.roughness = rough
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	var s := 1.0 / tile_m
	m.uv1_scale = Vector3(s, s, s)
	return m


static func _plain(color: Color, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m


static func _unlit(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


static func _emissive(albedo: Color, glow: Color, energy: float, rough := 0.3) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = rough
	m.emission_enabled = true
	m.emission = glow
	m.emission_energy_multiplier = energy
	return m


static func _build() -> void:
	var blocks := _tex_stone("blocks", 4, 2, true, 31, 0.80, 1.0)
	var slabs := _tex_stone("slabs", 2, 2, false, 47, 0.82, 1.0)
	var grain := _tex_noise("grain", 11, 0.03, 0.88, 1.0)
	_mats["wall"] = _textured(blocks, Color(0.50, 0.50, 0.55), 4.0, 0.95)
	_mats["stone"] = _textured(grain, Color(0.57, 0.57, 0.61), 3.0, 0.9)
	_mats["trim"] = _textured(grain, Color(0.66, 0.66, 0.69), 3.0, 0.85)
	_mats["floor"] = _textured(slabs, Color(0.33, 0.33, 0.37), 4.0, 0.5)
	_mats["floor2"] = _textured(slabs, Color(0.50, 0.50, 0.53), 4.0, 0.5)
	_mats["tile"] = _textured(slabs, Color(0.55, 0.57, 0.61), 2.0, 0.35)
	_mats["ceiling"] = _textured(grain, Color(0.21, 0.21, 0.24), 3.0, 1.0)
	_mats["beam"] = _textured(_tex_planks(), Color(0.20, 0.17, 0.17), 1.5, 0.75)
	_mats["wood"] = _textured(_tex_planks(), Color(0.26, 0.21, 0.20), 1.5, 0.7)
	_mats["burg"] = _plain(Color(0.28, 0.12, 0.15), 1.0)
	_mats["grayfab"] = _plain(Color(0.24, 0.24, 0.28), 1.0)
	_mats["purple"] = _plain(Color(0.20, 0.15, 0.26), 1.0)
	_mats["blackfab"] = _plain(Color(0.07, 0.07, 0.08), 1.0)
	_mats["rug"] = _plain(Color(0.20, 0.11, 0.13), 1.0)
	_mats["iron"] = _plain(Color(0.12, 0.12, 0.14), 0.45, 0.5)
	_mats["bronze"] = _plain(Color(0.38, 0.32, 0.24), 0.5, 0.6)
	_mats["candle"] = _plain(Color(0.78, 0.76, 0.70), 1.0)
	_mats["flame"] = _emissive(Color(0.95, 0.78, 0.56), Color(0.95, 0.74, 0.50), 2.2)
	_mats["flame"].shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mats["glass"] = _emissive(Color(0.07, 0.08, 0.10), Color(0.16, 0.18, 0.23), 0.7, 0.2)       # ventanales ciegos: una luz fría, lejana
	_mats["void"] = _unlit(Color(0.012, 0.012, 0.018))                                              # hogares, nichos hondos
	_mats["water"] = _emissive(Color(0.04, 0.05, 0.07), Color(0.05, 0.07, 0.10), 0.5, 0.1)
	_mats["oculus"] = _unlit(Color(0.42, 0.45, 0.53))
	var veil := ShaderMaterial.new()
	veil.shader = preload("res://stage/shaders/memory_veil.gdshader")
	veil.set_shader_parameter("noise_tex", FxTex.noise())
	_mats["veil"] = veil
