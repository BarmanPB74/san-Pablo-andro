class_name MatPaving
extends RefCounted
## Familia "paving" (F1-02): andenes, adoquines, baldosa táctil y sardinel.
## Texturas en art/tex/paving/ (generadas por tools/texgen/paving.py).
##
## Cada superficie tiene dos variantes:
##   <nombre>()      ShaderMaterial con look/wet_asphalt.gdshader (use_tex = true): charcos, humedad,
##                   fresnel y ondas de lluvia ENCIMA de la textura. Se registra en el caché de Palette,
##                   así Palette.set_weather() (StreetLook) le actualiza wetness/rain/cielo como a los demás pisos.
##                   Si el shader aún no tuviera los uniforms de textura, devuelve la variante seca.
##   <nombre>_dry()  ORMMaterial3D seco vía TexMat.pbr (triplanar en mundo): respaldo / interiores / pruebas.
## Proyección siempre en coordenadas de mundo (no hacen falta UVs). En caras horizontales u = X, v = Z.
## OJO: con textura, NO se usan las juntas procedurales del shader (tile_size = 0): las juntas vienen en la textura.

const DIR := "res://art/tex/paving/"

static var _cache := {}
static var _has_tex_uniforms := -1   # -1 = sin comprobar


# ------------------------------------------------------------------ andén de concreto
## Andén de concreto en losas de 1 x 1 m, borde bruñado, juntas, grietas, chicles, parche.
## tile_m = 2.0 (2 x 2 losas por repetición). Para andenes normales de calle (ref. 1 y 7).
static func sidewalk_concrete() -> Material:
	return _wet("anden_concreto", 2.0, {
		"puddle_color": Color(0.1, 0.105, 0.11),
		"puddle_coverage": 0.22, "puddle_scale": 0.18,
		"dry_roughness": 0.85, "damp_roughness": 0.5,
		"reflect_boost": 0.35,
	})

## Variante seca de sidewalk_concrete(). tile_m = 2.0.
static func sidewalk_concrete_dry() -> Material:
	return TexMat.pbr(DIR + "anden_concreto", {"tile_m": 2.0})


# ------------------------------------------------------------------ baldosa táctil
## Franja táctil GUÍA (barras) amarilla, baldosas de 20 cm (2 x 2 por repetición). tile_m = 0.4.
## Las barras corren a lo largo de Z del mundo; along_x = true las gira 90° (textura rotada en
## memoria una sola vez, ~1 MB extra). Para la franja de guía en medio del andén (ref. 1).
static func tactile_guide(along_x := false) -> Material:
	return _wet("tactil_guia", 0.4, _tactile_params(), along_x)

## Variante seca de tactile_guide(). tile_m = 0.4.
static func tactile_guide_dry(along_x := false) -> Material:
	if not along_x:
		return TexMat.pbr(DIR + "tactil_guia", {"tile_m": 0.4})
	var key := "tactil_guia_dry_rot"
	if not _cache.has(key):
		var m: ORMMaterial3D = TexMat.pbr(DIR + "tactil_guia", {"tile_m": 0.4}).duplicate()
		var t := _rotated("tactil_guia")
		m.albedo_texture = t[0]
		m.normal_texture = t[1]
		m.orm_texture = t[2]
		_cache[key] = m
	return _cache[key]

## Baldosa táctil de ALERTA (botones 3 x 3 por baldosa de 20 cm). tile_m = 0.4.
## Para el remate de la franja guía: esquinas, bordes de cruce peatonal, rampas, paradas.
static func tactile_alert() -> Material:
	return _wet("tactil_alerta", 0.4, _tactile_params())

## Variante seca de tactile_alert(). tile_m = 0.4.
static func tactile_alert_dry() -> Material:
	return TexMat.pbr(DIR + "tactil_alerta", {"tile_m": 0.4})


# ------------------------------------------------------------------ adoquines
## Adoquín HEXAGONAL gris del Parque de Boston (~28.6 cm entre caras), musgo y humedad en juntas.
## tile_m = 2.0. Para senderos y plaza del parque (ref. 5).
static func hex_pavers() -> Material:
	if ClayStyle.enabled:
		return brick_sidewalk()   # pueblo de plastilina: senderos de ladrillo rojo
	return _wet("adoquin_hex", 2.0, {
		"puddle_color": Color(0.09, 0.095, 0.1),
		"puddle_coverage": 0.3, "puddle_scale": 0.15,
		"dry_roughness": 0.86, "damp_roughness": 0.45,
		"reflect_boost": 0.4,
	})

## Variante seca de hex_pavers(). tile_m = 2.0.
static func hex_pavers_dry() -> Material:
	return TexMat.pbr(DIR + "adoquin_hex", {"tile_m": 2.0})

## Adoquín rectangular 20 x 10 cm en espina de pescado (90°), gris de plaza. tile_m = 2.0.
## Para la plaza del parque, plazoletas y entradas de edificios (ref. 4).
static func herringbone_pavers() -> Material:
	if ClayStyle.enabled:
		return brick_sidewalk()   # pueblo de plastilina: senderos de ladrillo rojo
	return _wet("adoquin_espina", 2.0, {
		"puddle_color": Color(0.09, 0.095, 0.1),
		"puddle_coverage": 0.3, "puddle_scale": 0.15,
		"dry_roughness": 0.85, "damp_roughness": 0.42,
		"reflect_boost": 0.4,
	})

## Variante seca de herringbone_pavers(). tile_m = 2.0.
static func herringbone_pavers_dry() -> Material:
	return TexMat.pbr(DIR + "adoquin_espina", {"tile_m": 2.0})


# ------------------------------------------------------------------ ladrillo
## Andén de ladrillo tolete (24.5 x 12 cm + junta 1 cm) en hiladas trabadas, hiladas a lo largo de X.
## tile_m = 2.0. Para andenes de edificios residenciales de ladrillo (ref. 6) y bordes de jardineras.
## Reemplazo natural de Palette.plaza_tile() (que era color ladrillo).
static func brick_sidewalk() -> Material:
	return _wet("anden_ladrillo", 2.0, {
		"puddle_color": Color(0.1, 0.06, 0.05),
		"puddle_coverage": 0.3, "puddle_scale": 0.15,
		"dry_roughness": 0.8, "damp_roughness": 0.42,
		"reflect_boost": 0.4,
	})

## Variante seca de brick_sidewalk(). tile_m = 2.0.
static func brick_sidewalk_dry() -> Material:
	return TexMat.pbr(DIR + "anden_ladrillo", {"tile_m": 2.0})


# ------------------------------------------------------------------ sardinel
## Sardinel / bordillo de concreto prefabricado: junta entre piezas cada 1 m (en X = 0, 1, 2…),
## desportillado junto a la junta, poros de vaciado, escurridos. tile_m = 1.0.
## Para el BoxMesh del borde del andén (caras laterales y tapa). Sustituye a Palette.curb().
static func curb() -> Material:
	return _wet("sardinel", 1.0, {
		"puddle_color": Color(0.12, 0.12, 0.12),
		"puddle_coverage": 0.05, "puddle_scale": 0.2,
		"dry_roughness": 0.83, "damp_roughness": 0.55,
		"reflect_boost": 0.25,
	})

## Variante seca de curb(). tile_m = 1.0.
static func curb_dry() -> Material:
	return TexMat.pbr(DIR + "sardinel", {"tile_m": 1.0})


# ------------------------------------------------------------------ internos
static func _tactile_params() -> Dictionary:
	return {
		"puddle_color": Color(0.12, 0.1, 0.05),
		"puddle_coverage": 0.12, "puddle_scale": 0.18,
		"dry_roughness": 0.72, "damp_roughness": 0.45,
		"reflect_boost": 0.3,
	}


## ¿El shader de piso mojado ya tiene los uniforms de textura (tex_albedo, use_tex…)?
static func shader_supports_textures() -> bool:
	if _has_tex_uniforms == -1:
		_has_tex_uniforms = 0
		var sh: Shader = load(Palette.WET_SHADER)
		if sh != null:
			var names := {}
			for u in sh.get_shader_uniform_list():
				names[u["name"]] = true
			if names.has("use_tex") and names.has("tex_albedo") and names.has("tex_normal") \
					and names.has("tex_orm") and names.has("tex_tile_m"):
				_has_tex_uniforms = 1
	return _has_tex_uniforms == 1


static func _wet(name: String, tile_m: float, params: Dictionary, rotated := false) -> Material:
	if not shader_supports_textures():
		if name == "tactil_guia":
			return tactile_guide_dry(rotated)
		return TexMat.pbr(DIR + name, {"tile_m": tile_m})
	var key := "paving_" + name + ("_rot" if rotated else "")
	# Palette._cached: queda en el caché de Palette → Palette.set_weather() lo actualiza.
	return Palette._cached(key, func():
		var p := params.duplicate()
		p["use_tex"] = true
		p["tex_tile_m"] = tile_m
		p["tile_size"] = 0.0          # sin juntas procedurales: vienen en la textura
		if rotated:
			var t := _rotated(name)
			p["tex_albedo"] = t[0]
			p["tex_normal"] = t[1]
			p["tex_orm"] = t[2]
		else:
			p["tex_albedo"] = load(DIR + name + "_albedo.png")
			p["tex_normal"] = load(DIR + name + "_normal.png")
			p["tex_orm"] = load(DIR + name + "_orm.png")
		return Palette._wet(p))


## Devuelve [albedo, normal, orm] girados 90° (horario) como ImageTexture.
## La normal se re-orienta: R' = G, G' = 1 - R (convención OpenGL).
static func _rotated(name: String) -> Array:
	var key := "rot_" + name
	if _cache.has(key):
		return _cache[key]
	var out := []
	for suf in ["albedo", "normal", "orm"]:
		var tex: Texture2D = load(DIR + name + "_" + suf + ".png")
		var img := tex.get_image()
		if img.is_compressed():
			img.decompress()
		img.clear_mipmaps()
		img.convert(Image.FORMAT_RGB8)
		img.rotate_90(CLOCKWISE)
		if suf == "normal":
			var data := img.get_data()
			for i in range(0, data.size(), 3):
				var r := data[i]
				data[i] = data[i + 1]
				data[i + 1] = 255 - r
			img = Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGB8, data)
		img.generate_mipmaps()
		out.append(ImageTexture.create_from_image(img))
	_cache[key] = out
	return out
