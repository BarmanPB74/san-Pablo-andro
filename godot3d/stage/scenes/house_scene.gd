class_name HouseScene
extends StageScene
## La Casa: donde vivía Andro cuando era un niño humano. Un solo piso con cocina, sala, comedor, 4 habitaciones,
## un baño y un patio grande. Los objetos, recuerdos y poderes de la historia se agregan después; hoy es la
## estructura, el mobiliario básico y la luz.
##
## Plano (metros; -Z = norte; el patio queda al sur):
##
##   z = -8  ┌──────┬──────┬──────┬──────┬──────┐   Habitaciones 1-2 | Baño | Habitaciones 3-4 (4.8 × 5.8 m)
##           │ hab1 │ hab2 │ baño │ hab3 │ hab4 │
##   z = -2.2├──────┴──────┴──────┴──────┴──────┤
##           │            PASILLO               │   2.2 × 24 m, con puerta a cada cuarto
##   z = 0.8 ├───────────┬─────────┬────────────┤
##           │   SALA    │ COMEDOR │   COCINA   │   puerta de entrada y puerta grande al patio (sur)
##   z = 8   └───────────┴─────────┴────────────┘
##                       PATIO (x ±22, z 8 a 36)
##
## Andro mide 1.32 m de ancho (campo de fuerza) y 1.86 m de alto en colisión, y flota: por eso las puertas son de
## 2.0 × 2.8 m, el techo está a 3.6 m y ningún mueble cierra un paso de menos de 1.5 m.
## Todo por código. La geometría estática se funde en pocas mallas por zona de 6 m (cada malla ve pocas luces:
## el móvil admite 8 luces por objeto) y las colisiones son cajas en un solo StaticBody3D.

const H := 3.6                     # alto del techo
const T := 0.2                     # grosor de los muros
const DH := 2.8                    # alto de las puertas
const WIN_Y0 := 1.2                # ventanas: del suelo 1.2 m a 2.6 m
const WIN_Y1 := 2.6
const CELL := 6.0                  # tamaño de la zona en que se funden las mallas
const CEILING_LAYER := 2           # capa visual del techo y el tejado; las luces de ambiente solo alumbran la capa 1
const X := 12.0                    # la casa ocupa x ±12, z ±8
const Z := 8.0
const WALL_N := -2.2               # muro entre las habitaciones y el pasillo
const WALL_S := 0.8                # muro entre el pasillo y sala / comedor / cocina
const LOT_X := 22.0                # lote: x ±22, z de -14 a 36
const LOT_Z0 := -14.0
const LOT_Z1 := 36.0
const GROUND_Y := -0.06            # el pasto queda 6 cm bajo el piso de la casa (umbral en las puertas)

static var _tex_cache := {}

var _mats := {}
var _st := {}                      # zona + material -> SurfaceTool
var _st_mat := {}                  # zona + material -> clave del material
var _body: StaticBody3D


func _init() -> void:
	title = "La Casa"
	spawn_pos = Vector3(-6.5, 0.1, 4.5)
	spawn_yaw = -PI * 0.5                # mira al este: sala → comedor → cocina
	spawn_pitch = -0.1
	portal_distance = 3.6
	portal_size = Vector2(2.2, 2.4)      # con el marco mide 3.4 m: cabe bajo el techo de 3.6


func build() -> void:
	_make_materials()
	_make_environment_day()
	_body = StaticBody3D.new()
	_body.name = "Colliders"
	_body.collision_layer = 1
	_body.collision_mask = 0
	add_child(_body)
	add_ground(140.0, _mats["grass"], GROUND_Y)

	_build_floors()
	_build_walls()
	_build_roof()
	_build_lot()
	_furnish_living()
	_furnish_kitchen()
	_furnish_bedrooms()
	_furnish_bath()
	_flush()
	_build_garden()
	_build_lights()


# ------------------------------------------------------------------ entorno y luces

func _make_environment_day() -> void:
	var sky := ProceduralSkyMaterial.new()
	sky.sky_top_color = Color(0.30, 0.50, 0.82)
	sky.sky_horizon_color = Color(0.80, 0.85, 0.92)
	sky.ground_horizon_color = Color(0.80, 0.85, 0.92)
	sky.ground_bottom_color = Color(0.46, 0.52, 0.46)
	# el sol entra por el sur-este y se cuela por la puerta grande del patio y las ventanas
	make_environment(sky, Color(0.80, 0.85, 0.92), 0.0, 0.55, Color(1.0, 0.92, 0.78), 1.15, Vector3(-0.35, -0.72, -0.6))
	env.fog_enabled = false
	env.sky.radiance_size = Sky.RADIANCE_SIZE_256
	set_flat_ambient(Color(0.96, 0.91, 0.82), 0.55)      # ambiente cálido (el del cielo azulaba los pisos oscuros)


func _light(pos: Vector3, energy: float, range_m: float, color := Color(1.0, 0.82, 0.60)) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = range_m
	l.shadow_enabled = false
	l.light_cull_mask = 1
	l.position = pos
	add_child(l)


func _build_lights() -> void:
	# una luz cálida por cuarto (sin sombra, alcance corto para que no se cuele por las paredes)
	for x in [-9.6, -4.8, 4.8, 9.6]:
		_light(Vector3(x, 2.7, -5.1), 1.2, 4.2)
	_light(Vector3(0.0, 2.7, -5.1), 1.2, 4.2, Color(0.92, 0.96, 1.0))      # baño: más fría
	_light(Vector3(-6.0, 2.7, -0.7), 1.4, 4.5)                              # pasillo
	_light(Vector3(6.0, 2.7, -0.7), 1.4, 4.5)
	_light(Vector3(-7.0, 2.8, 4.4), 1.3, 6.0)                               # sala
	_light(Vector3(2.0, 2.8, 4.4), 1.3, 5.5)                                # comedor
	_light(Vector3(9.0, 2.8, 4.4), 1.3, 5.0, Color(1.0, 0.92, 0.75))       # cocina


# ------------------------------------------------------------------ materiales y texturas

static func _img_tex(img: Image) -> ImageTexture:
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _tex_noise(seed_v: int, freq: float, lo: float, hi: float) -> ImageTexture:
	var key := "noise%d" % seed_v
	if _tex_cache.has(key):
		return _tex_cache[key]
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
	var t := _img_tex(img)
	_tex_cache[key] = t
	return t


## Tablas de madera (8 por tile) con tono propio, vetas y juntas de testa.
static func _tex_planks() -> ImageTexture:
	if _tex_cache.has("planks"):
		return _tex_cache["planks"]
	var n := 128
	var planks := 8
	var pw := n / planks
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var tones: Array[float] = []
	var offs: Array[int] = []
	for i in planks:
		tones.append(rng.randf_range(0.80, 1.0))
		offs.append(rng.randi_range(0, n - 1))
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var i := clampi(x / pw, 0, planks - 1)
			var c: float = tones[i] * (0.96 + 0.04 * sin(TAU * 7.0 * float(y) / float(n) + float(i) * 1.7))
			if x % pw == 0:
				c *= 0.55
			if (y + offs[i]) % 64 == 0:
				c *= 0.6
			img.set_pixel(x, y, Color(c, c, c))
	var t := _img_tex(img)
	_tex_cache["planks"] = t
	return t


## Baldosas (2 × 2 por tile) con junta oscura y tono distinto en cada una.
static func _tex_tiles() -> ImageTexture:
	if _tex_cache.has("tiles"):
		return _tex_cache["tiles"]
	var n := 64
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var tones: Array[float] = []
	for i in 4:
		tones.append(rng.randf_range(0.88, 1.0))
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var ti := (y / 32) * 2 + (x / 32)
			var c: float = tones[ti]
			if x % 32 < 2 or y % 32 < 2:
				c = 0.55
			img.set_pixel(x, y, Color(c, c, c))
	var t := _img_tex(img)
	_tex_cache["tiles"] = t
	return t


## Material con textura repetida en el mundo (triplanar): `tile_m` = metros que cubre cada repetición.
static func _tex_mat(tex: Texture2D, tint: Color, tile_m: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.albedo_texture = tex
	m.roughness = rough
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	var s := 1.0 / tile_m
	m.uv1_scale = Vector3(s, s, s)
	return m


func _make_materials() -> void:
	var plaster := _tex_noise(11, 0.025, 0.92, 1.0)
	_mats["plaster"] = _tex_mat(plaster, Color(0.93, 0.86, 0.72), 3.0, 0.95)
	_mats["ceiling"] = _tex_mat(plaster, Color(0.96, 0.94, 0.89), 3.0, 0.95)
	_mats["lotwall"] = _tex_mat(plaster, Color(0.70, 0.64, 0.55), 3.0, 0.95)
	_mats["roof"] = mat(Color(0.50, 0.24, 0.17), 0.9)
	_mats["floorwood"] = _tex_mat(_tex_planks(), Color(0.60, 0.43, 0.30), 1.2, 0.6)
	_mats["floorwood2"] = _tex_mat(_tex_planks(), Color(0.78, 0.60, 0.40), 1.2, 0.6)
	_mats["tilek"] = _tex_mat(_tex_tiles(), Color(0.88, 0.84, 0.76), 0.8, 0.45)
	_mats["tileb"] = _tex_mat(_tex_tiles(), Color(0.56, 0.74, 0.84), 0.8, 0.4)
	_mats["paving"] = _tex_mat(_tex_tiles(), Color(0.66, 0.63, 0.58), 3.0, 0.9)
	_mats["grass"] = _tex_mat(_tex_noise(23, 0.03, 0.78, 1.0), Color(0.42, 0.62, 0.30), 4.0, 1.0)
	_mats["wooddark"] = mat(Color(0.28, 0.17, 0.10), 0.7)
	_mats["woodlight"] = mat(Color(0.64, 0.47, 0.30), 0.7)
	_mats["fabricred"] = mat(Color(0.55, 0.14, 0.14), 1.0)
	_mats["fabricblue"] = mat(Color(0.22, 0.32, 0.55), 1.0)
	_mats["fabricgreen"] = mat(Color(0.25, 0.45, 0.30), 1.0)
	_mats["fabriccream"] = mat(Color(0.85, 0.80, 0.66), 1.0)
	_mats["white"] = mat(Color(0.90, 0.90, 0.88), 0.5)
	_mats["metal"] = mat(Color(0.62, 0.64, 0.66), 0.35, 0.6)
	_mats["counter"] = mat(Color(0.20, 0.20, 0.22), 0.4)
	_mats["rug"] = mat(Color(0.45, 0.22, 0.20), 1.0)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.65, 0.80, 0.95, 0.22)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	_mats["glass"] = glass


# ------------------------------------------------------------------ geometría: cajas fundidas por zona

func _vis(c: Vector3, s: Vector3, mkey: String) -> void:
	var key := "%d_%d_%s" % [floori(c.x / CELL), floori(c.z / CELL), mkey]
	var st: SurfaceTool = _st.get(key)
	if st == null:
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[key] = st
		_st_mat[key] = mkey
	var bm := BoxMesh.new()
	bm.size = s
	st.append_from(bm, 0, Transform3D(Basis.IDENTITY, c))


func _col(c: Vector3, s: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = s
	cs.shape = sh
	cs.position = c
	_body.add_child(cs)


func _box(c: Vector3, s: Vector3, mkey: String, collide := true) -> void:
	_vis(c, s, mkey)
	if collide:
		_col(c, s)


## Losa o muro entre esquinas: la malla se parte en piezas de ≤ 6 m (para que cada una vea pocas luces) y la colisión es una sola caja.
func _slab(x0: float, x1: float, z0: float, z1: float, y0: float, y1: float, mkey: String, collide := true) -> void:
	var nx := maxi(1, ceili((x1 - x0) / CELL))
	var nz := maxi(1, ceili((z1 - z0) / CELL))
	var sx := (x1 - x0) / float(nx)
	var sz := (z1 - z0) / float(nz)
	for ix in nx:
		for iz in nz:
			_vis(Vector3(x0 + sx * (float(ix) + 0.5), (y0 + y1) * 0.5, z0 + sz * (float(iz) + 0.5)),
				Vector3(sx, y1 - y0, sz), mkey)
	if collide:
		_col(Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5), Vector3(x1 - x0, y1 - y0, z1 - z0))


func _flush() -> void:
	var keys := _st.keys()
	keys.sort()
	for k in keys:
		var st: SurfaceTool = _st[k]
		var mkey: String = _st_mat[k]
		var mi := MeshInstance3D.new()
		mi.name = "Casa_" + str(k)
		mi.mesh = st.commit()
		mi.material_override = _mats[mkey]
		if mkey == "glass" or mkey == "rug":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mkey == "ceiling" or mkey == "roof":
			mi.layers = CEILING_LAYER          # las luces de los cuartos no lo alumbran: no cuenta contra su límite de luces
		add_child(mi)
	_st.clear()
	_st_mat.clear()


## Mueble apoyado en el piso: centro (x, z), tamaño (sx, sy, sz) y altura de la base `y0`.
func _f(x: float, z: float, sx: float, sy: float, sz: float, mkey: String, y0 := 0.0, collide := true) -> void:
	_box(Vector3(x, y0 + sy * 0.5, z), Vector3(sx, sy, sz), mkey, collide)


# ------------------------------------------------------------------ muros

func _door(c: float, w := 2.0) -> Dictionary:
	return {"c": c, "w": w, "y0": 0.0, "y1": DH}


func _win(c: float, w := 1.8, glass := true) -> Dictionary:
	return {"c": c, "w": w, "y0": WIN_Y0, "y1": WIN_Y1, "glass": glass}


func _wall_piece(along_x: bool, fixed: float, p0: float, p1: float, y0: float, y1: float, mkey: String, thick := T) -> void:
	if along_x:
		_slab(p0, p1, fixed - thick * 0.5, fixed + thick * 0.5, y0, y1, mkey)
	else:
		_slab(fixed - thick * 0.5, fixed + thick * 0.5, p0, p1, y0, y1, mkey)


## Muro entre `a` y `b` (a lo largo de X si `along_x`, si no a lo largo de Z) con aberturas
## {c: centro, w: ancho, y0, y1, glass}: debajo y encima de cada abertura queda muro; si lleva vidrio, un panel fino con colisión.
func _wall(along_x: bool, fixed: float, a: float, b: float, openings: Array = []) -> void:
	var ops: Array = openings.duplicate()
	ops.sort_custom(func(p, q) -> bool: return float(p["c"]) < float(q["c"]))
	var cur := a
	for o in ops:
		var d: Dictionary = o
		var c: float = d["c"]
		var w: float = d["w"]
		var y0: float = d.get("y0", 0.0)
		var y1: float = d.get("y1", DH)
		var o0 := c - w * 0.5
		var o1 := c + w * 0.5
		if o0 > cur + 0.001:
			_wall_piece(along_x, fixed, cur, o0, 0.0, H, "plaster")
		if y0 > 0.001:
			_wall_piece(along_x, fixed, o0, o1, 0.0, y0, "plaster")
		if y1 < H - 0.001:
			_wall_piece(along_x, fixed, o0, o1, y1, H, "plaster")
		if d.get("glass", false):
			_wall_piece(along_x, fixed, o0, o1, y0, y1, "glass", 0.05)
		cur = o1
	if b > cur + 0.001:
		_wall_piece(along_x, fixed, cur, b, 0.0, H, "plaster")


func _build_walls() -> void:
	var e := T * 0.5
	# exteriores
	_wall(true, -Z, -X - e, X + e, [_win(-9.6), _win(-4.8), _win(0.0), _win(4.8), _win(9.6)])
	_wall(true, Z, -X - e, X + e, [
		_door(-9.0, 2.2),                      # puerta de entrada (sala)
		_win(-5.0, 2.4),                       # ventana de la sala
		_door(2.0, 3.2),                       # puerta grande al patio (comedor)
		_win(8.0, 2.0)])                       # ventana de la cocina
	_wall(false, -X, -Z + e, Z - e, [_win(-5.0, 2.0), _win(4.5, 2.4)])
	_wall(false, X, -Z + e, Z - e, [_win(-5.0, 2.0), _win(4.5, 2.0)])
	# dormitorios y baño: un muro con 5 puertas hacia el pasillo y 4 divisiones
	_wall(true, WALL_N, -X, X, [_door(-9.6), _door(-4.8), _door(0.0), _door(4.8), _door(9.6)])
	for x in [-7.2, -2.4, 2.4, 7.2]:
		_wall(false, x, -Z, WALL_N)
	# pasillo | sala, comedor y cocina (aberturas anchas)
	_wall(true, WALL_S, -X, X, [_door(-7.0, 3.0), _door(2.0, 3.0), _door(9.0, 2.2)])
	# sala | comedor
	_wall(false, -2.0, WALL_S, Z, [_door(4.4, 3.0)])
	# comedor | cocina: puerta y ventanilla de barra (abierta, no se puede cruzar)
	_wall(false, 6.0, WALL_S, Z, [_door(4.4, 2.2), {"c": 6.4, "w": 1.6, "y0": 1.0, "y1": 2.2}])


func _build_floors() -> void:
	var e := T * 0.5
	var x0 := -X - e
	var x1 := X + e
	var z0 := -Z - e
	var z1 := Z
	# habitaciones y baño (4.8 m de ancho cada una)
	_slab(x0, -7.2, z0, WALL_N, -0.3, 0.0, "floorwood2")
	_slab(-7.2, -2.4, z0, WALL_N, -0.3, 0.0, "floorwood2")
	_slab(-2.4, 2.4, z0, WALL_N, -0.3, 0.0, "tileb")
	_slab(2.4, 7.2, z0, WALL_N, -0.3, 0.0, "floorwood2")
	_slab(7.2, x1, z0, WALL_N, -0.3, 0.0, "floorwood2")
	# pasillo, sala y comedor, cocina
	_slab(x0, x1, WALL_N, WALL_S, -0.3, 0.0, "floorwood")
	_slab(x0, 6.0, WALL_S, z1, -0.3, 0.0, "floorwood")
	_slab(6.0, x1, WALL_S, z1, -0.3, 0.0, "tilek")
	# terraza frente al patio y camino de piedra
	_slab(x0, x1, z1, 12.5, -0.3, 0.0, "paving")
	_slab(-1.5, 1.5, 12.5, 34.0, -0.3, 0.0, "paving")


func _build_roof() -> void:
	var e := T * 0.5
	_slab(-X - e, X + e, -Z - e, Z + e, H, H + 0.2, "ceiling")
	_slab(-X - 0.7, X + 0.7, -Z - 0.7, Z + 0.7, H + 0.2, H + 0.4, "roof")      # alero de 0.6 m


## Muro perimetral del lote (el patio es grande pero cerrado).
func _build_lot() -> void:
	var wt := 0.4
	var wh := 2.6
	_slab(-LOT_X - wt, LOT_X + wt, LOT_Z0 - wt, LOT_Z0, -0.2, wh, "lotwall")
	_slab(-LOT_X - wt, LOT_X + wt, LOT_Z1, LOT_Z1 + wt, -0.2, wh, "lotwall")
	_slab(-LOT_X - wt, -LOT_X, LOT_Z0, LOT_Z1, -0.2, wh, "lotwall")
	_slab(LOT_X, LOT_X + wt, LOT_Z0, LOT_Z1, -0.2, wh, "lotwall")


# ------------------------------------------------------------------ mobiliario

func _furnish_living() -> void:
	# sala: sofá contra el muro oeste, mesa de centro, alfombra, biblioteca y sillón
	_f(-11.35, 4.5, 1.0, 0.45, 3.6, "fabricred")
	_f(-11.7, 4.5, 0.3, 1.0, 3.6, "fabricred")
	_f(-11.35, 2.55, 1.0, 0.65, 0.3, "fabricred")
	_f(-11.35, 6.45, 1.0, 0.65, 0.3, "fabricred")
	_f(-9.6, 4.5, 3.8, 0.02, 3.2, "rug", 0.0, false)
	_f(-9.4, 4.5, 1.3, 0.4, 0.8, "wooddark")
	_f(-10.6, 1.15, 2.4, 2.2, 0.4, "wooddark")
	_f(-5.5, 6.8, 1.0, 0.5, 1.0, "fabricblue")
	_f(-5.5, 7.35, 1.0, 0.55, 0.25, "fabricblue", 0.5)
	# comedor: mesa con 6 sillas y aparador contra el muro sur
	_f(2.0, 4.2, 2.6, 0.08, 1.2, "wooddark", 0.72)
	for lx in [-1.2, 1.2]:
		for lz in [-0.5, 0.5]:
			_f(2.0 + lx, 4.2 + lz, 0.1, 0.72, 0.1, "wooddark", 0.0, false)
	for cx in [0.9, 2.0, 3.1]:
		_f(cx, 3.3, 0.5, 0.45, 0.5, "woodlight")
		_f(cx, 3.02, 0.5, 0.5, 0.08, "woodlight", 0.45)
		_f(cx, 5.1, 0.5, 0.45, 0.5, "woodlight")
		_f(cx, 5.38, 0.5, 0.5, 0.08, "woodlight", 0.45)
	_f(-0.9, 7.6, 1.8, 0.9, 0.5, "wooddark")


func _furnish_kitchen() -> void:
	# cocina: mesón largo bajo la ventana este, mesón y estufa al sur, nevera junto a la división
	_f(11.55, 4.6, 0.7, 0.9, 6.0, "woodlight")
	_f(11.55, 4.6, 0.76, 0.05, 6.06, "counter", 0.9, false)
	_f(9.4, 7.55, 3.4, 0.9, 0.7, "woodlight")
	_f(9.4, 7.55, 3.46, 0.05, 0.76, "counter", 0.9, false)
	_f(10.2, 7.55, 0.8, 0.06, 0.62, "metal", 0.95, false)
	_f(10.2, 7.7, 0.8, 0.45, 0.4, "metal", 1.9, false)
	_f(6.6, 7.4, 0.8, 1.9, 0.8, "white")


func _furnish_bedrooms() -> void:
	var rooms := [[-9.6, "fabricblue", -1.0], [-4.8, "fabricgreen", -1.0], [4.8, "fabricred", 1.0], [9.6, "fabriccream", 1.0]]
	for r in rooms:
		var rx: float = r[0]
		var linen: String = r[1]
		var side: float = r[2]
		_f(rx, -6.8, 1.6, 0.35, 2.1, "wooddark")                     # cama
		_f(rx, -6.8, 1.5, 0.2, 2.0, linen, 0.35, false)
		_f(rx, -7.5, 0.6, 0.12, 0.35, "white", 0.55, false)
		_f(rx, -7.83, 1.7, 1.0, 0.1, "wooddark")                     # cabecera
		_f(rx + 1.25, -7.6, 0.5, 0.5, 0.45, "woodlight")             # mesita
		_f(rx + side * 2.05, -4.0, 0.6, 2.3, 1.8, "woodlight")       # closet contra la división


func _furnish_bath() -> void:
	_f(0.0, -7.45, 2.0, 0.55, 0.8, "white")                        # bañera
	_f(-1.85, -5.2, 0.5, 0.42, 0.4, "white")                       # sanitario
	_f(-2.2, -5.2, 0.2, 0.4, 0.4, "white", 0.45, false)
	_f(2.0, -5.2, 0.6, 0.85, 0.55, "white")                        # lavamanos
	_f(2.27, -5.2, 0.05, 0.8, 0.9, "metal", 1.2, false)            # espejo


# ------------------------------------------------------------------ patio

func _build_garden() -> void:
	var trunk := mat(Color(0.30, 0.20, 0.12), 0.95)
	var leaves := mat(Color(0.20, 0.42, 0.18), 0.95)
	for t in [Vector3(-14.0, 0.0, 20.0), Vector3(13.0, 0.0, 27.0), Vector3(-8.0, 0.0, 31.0)]:
		add_cylinder(Vector3(t.x, 1.75, t.z), 0.32, 3.5, trunk, true, 10)
		add_sphere(Vector3(t.x, 5.3, t.z), 2.4, leaves, false)
		add_sphere(Vector3(t.x + 1.2, 4.6, t.z + 0.8), 1.7, leaves, false)
	# matas bajas junto a la fachada
	for b in [Vector3(-5.5, 0.5, 9.1), Vector3(6.5, 0.5, 9.1), Vector3(-12.6, 0.5, 9.4)]:
		add_sphere(b, 0.7, leaves, false)
