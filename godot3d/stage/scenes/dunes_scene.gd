class_name DunesScene
extends StageScene
## Las Dunas Blancas (fase 4, dimensión 1): un desierto de arena blanca de noche, bajo la Vía Láctea y una luna enorme.
## Un valle plano en el centro (donde aparece Andro) rodeado de dunas suaves, un círculo de piedras con runas y, al fondo,
## un arco de piedra en ruinas (ref. 84869). Todo procedural; el terreno es una malla de 56×56 celdas con colisión propia.

const SKY_SHADER := preload("res://stage/shaders/star_sky.gdshader")
const SAND_SHADER := preload("res://stage/shaders/sand.gdshader")
const ROCK_SHADER := preload("res://stage/shaders/rock.gdshader")
const MOTES_SHADER := preload("res://stage/shaders/sand_motes.gdshader")

const EXTENT := 100.0              # lado del terreno (m)
const GRID := 56                   # celdas por lado
const PLAY_RADIUS := 44.0          # muro invisible
const STONES := 7                  # piedras del círculo
const STONE_RING := 15.0           # radio del círculo
const MOTES := 120
const MOON_DIR := Vector3(-0.28, 0.32, -0.9)   # hacia dónde está la luna (la luz viaja al revés)


func _init() -> void:
	title = "Las Dunas Blancas"
	spawn_pos = Vector3(0, 0.1, 4.0)
	spawn_yaw = 0.0
	spawn_pitch = -0.08
	fly_ceiling = 60.0
	portal_distance = 7.5


## Altura del terreno en (x, z): dunas suaves de crestas largas; plano en el valle central; sube en el borde.
static func height(x: float, z: float) -> float:
	var d := Vector2(x, z).length()
	var base := sin(x * 0.11 + sin(z * 0.07) * 1.6) * 1.3 + sin(z * 0.09 - x * 0.05 + 1.3) * 1.0 + sin((x + z) * 0.17) * 0.35
	var crest := 1.0 - absf(sin(x * 0.06 + z * 0.035 + sin(z * 0.05) * 1.2))
	var h := (base + crest * 1.8) * 1.0
	var open := smoothstep(11.0, 26.0, d)
	var rim := maxf(0.0, d - 38.0) * 0.3
	return h * open + rim


func build() -> void:
	var sky := ShaderMaterial.new()
	sky.shader = SKY_SHADER
	sky.set_shader_parameter("zenith_col", Color(0.006, 0.010, 0.035))
	sky.set_shader_parameter("horizon_col", Color(0.10, 0.13, 0.25))
	sky.set_shader_parameter("band_col", Color(0.55, 0.62, 0.9))
	sky.set_shader_parameter("nebula_col", Color(0.5, 0.35, 0.7))
	sky.set_shader_parameter("band_normal", Vector3(0.55, 0.65, 0.3))
	sky.set_shader_parameter("band_strength", 1.5)
	sky.set_shader_parameter("star_amount", 0.9)
	make_environment(sky, Color(0.10, 0.13, 0.23), 0.009, 1.0, Color(0.74, 0.84, 1.0), 1.15, -MOON_DIR)
	set_flat_ambient(Color(0.20, 0.25, 0.38), 1.3)
	env.glow_intensity = 0.9
	env.glow_bloom = 0.14
	sun.directional_shadow_max_distance = 45.0

	_build_terrain()
	_build_ring()
	_build_arch()
	_build_motes()
	_build_moon()
	add_bounds_circle(PLAY_RADIUS, 60.0)


func _ground_y(x: float, z: float) -> float:
	return height(x, z)


func _build_terrain() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cell := EXTENT / float(GRID)
	var half := EXTENT * 0.5
	for iz in GRID:
		for ix in GRID:
			var x0 := -half + float(ix) * cell
			var z0 := -half + float(iz) * cell
			var p00 := Vector3(x0, height(x0, z0), z0)
			var p10 := Vector3(x0 + cell, height(x0 + cell, z0), z0)
			var p01 := Vector3(x0, height(x0, z0 + cell), z0 + cell)
			var p11 := Vector3(x0 + cell, height(x0 + cell, z0 + cell), z0 + cell)
			for p in [p00, p10, p01, p10, p11, p01]:       # sentido horario visto desde arriba (cara hacia el cielo)
				st.add_vertex(p)
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = "Terreno"
	mi.mesh = mesh
	var m := ShaderMaterial.new()
	m.shader = SAND_SHADER
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	sb.add_child(cs)
	mi.add_child(sb)


func _stone_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ROCK_SHADER
	m.set_shader_parameter("col_a", Color(0.34, 0.37, 0.47))
	m.set_shader_parameter("col_b", Color(0.78, 0.82, 0.92))
	m.set_shader_parameter("noise_scale", 0.5)
	m.set_shader_parameter("strata", 0.35)
	m.set_shader_parameter("rough", 0.8)
	return m


## Círculo de piedras erguidas, cada una con una veta de runa que mira al centro.
func _build_ring() -> void:
	var stone := _stone_mat()
	var rune := glow_mat(Color(0.62, 0.86, 1.0), 2.4)
	for i in STONES:
		var a := TAU * float(i) / float(STONES) + 0.3
		var x := sin(a) * STONE_RING
		var z := cos(a) * STONE_RING
		var h := 3.4 + 1.6 * fmod(float(i) * 0.61803, 1.0)
		var y := height(x, z)
		var slab := add_box(Vector3(x, y + h * 0.5 - 0.35, z), Vector3(1.5, h, 0.75), stone, true, a + PI)
		slab.rotation.z = (fmod(float(i) * 0.37, 1.0) - 0.5) * 0.12
		var inward := Vector3(-sin(a), 0.0, -cos(a))
		var strip := add_box(Vector3(x, y + h * 0.5 - 0.1, z) + inward * 0.4, Vector3(0.16, h * 0.55, 0.05), rune, false, a + PI)
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Arco de piedra en ruinas al fondo, a medio enterrar en la duna.
func _build_arch() -> void:
	var stone := _stone_mat()
	var cx := 3.0
	var cz := -33.0
	var y := height(cx, cz) - 0.6
	var yaw := 0.12
	var basis := Basis(Vector3.UP, yaw)
	var left := basis * Vector3(-3.6, 0, 0)
	var right := basis * Vector3(3.6, 0, 0)
	add_box(Vector3(cx, y, cz) + left + Vector3(0, 4.6, 0), Vector3(1.7, 9.2, 1.7), stone, true, yaw)
	add_box(Vector3(cx, y, cz) + right + Vector3(0, 3.1, 0), Vector3(1.7, 6.2, 1.7), stone, true, yaw)    # el pilar roto
	add_box(Vector3(cx, y, cz) + basis * Vector3(-1.2, 9.6, 0), Vector3(5.6, 1.4, 1.9), stone, true, yaw)  # dintel partido
	# un bloque caído y otro de lado
	add_box(Vector3(cx + 4.8, height(cx + 4.8, cz + 3.0) + 0.3, cz + 3.0), Vector3(2.8, 1.2, 1.5), stone, true, 0.8)
	add_box(Vector3(cx - 6.5, height(cx - 6.5, cz + 5.0) + 0.5, cz + 5.0), Vector3(1.6, 1.6, 1.6), stone, true, 0.3)


## Motas de luz que suben despacio sobre la arena (un MultiMesh: una sola llamada de dibujo).
func _build_motes() -> void:
	var qm := QuadMesh.new()
	qm.size = Vector2(0.3, 0.3)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = qm
	mm.instance_count = MOTES
	var rng := RandomNumberGenerator.new()
	rng.seed = 7117
	for i in MOTES:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 34.0
		var x := sin(a) * r
		var z := cos(a) * r
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(x, height(x, z) + 0.2, z)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var m := ShaderMaterial.new()
	m.shader = MOTES_SHADER
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-40, -2, -40), Vector3(80, 14, 80))
	add_child(mmi)


## La luna: una esfera enorme y lejana, sin niebla, en la dirección de la que llega la luz.
func _build_moon() -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.93, 0.96, 1.0)
	m.disable_fog = true
	var moon := add_sphere(MOON_DIR.normalized() * 260.0, 10.0, m, false)
	moon.name = "Luna"
	moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
