class_name CubeScene
extends StageScene
## El Cubo (ref. 83532): un cubo oscuro suspendido sobre una llanura negra de agua baja, con dunas
## lejanas y, detrás, un telón de cascadas de niebla. Al fondo, una figura diminuta.

const SKY_SHADER := preload("res://stage/shaders/star_sky.gdshader")
const MIST_SHADER := preload("res://stage/shaders/mist_falls.gdshader")

const CUBE_EDGE := 26.0
const CUBE_POS := Vector3(0, 36.0, -58.0)

var _cube: MeshInstance3D


func _init() -> void:
	title = "El Cubo"
	spawn_pos = Vector3(0, 0.1, 24)
	spawn_yaw = 0.0
	spawn_pitch = 0.2


func build() -> void:
	var sky := ShaderMaterial.new()
	sky.shader = SKY_SHADER
	sky.set_shader_parameter("zenith_col", Color(0.42, 0.48, 0.54))
	sky.set_shader_parameter("horizon_col", Color(0.72, 0.76, 0.80))
	sky.set_shader_parameter("band_strength", 0.0)
	sky.set_shader_parameter("star_amount", 0.0)
	make_environment(sky, Color(0.62, 0.67, 0.72), 0.0045, 1.0, Color(0.92, 0.95, 1.0), 0.8, Vector3(0.3, -0.7, -0.6))
	set_flat_ambient(Color(0.5, 0.55, 0.6), 0.75)

	# llanura de agua baja: negra y pulida (refleja el cielo claro)
	var wet := mat(Color(0.05, 0.065, 0.085), 0.07, 0.0)
	wet.metallic_specular = 1.0
	add_ground(130.0, wet)
	add_bounds_circle(52.0, 60.0)

	# dunas oscuras en el borde de la llanura (malla de relieve, sin colisión)
	var dune_mat := mat(Color(0.10, 0.115, 0.14), 0.55, 0.0)
	var dunes := MeshInstance3D.new()
	var n := 80
	var extent := 360.0
	var dune_fn := func(i: int, j: int) -> Vector3:
		var x := (float(i) / float(n) - 0.5) * extent
		var z := (float(j) / float(n) - 0.5) * extent
		var r := Vector2(x, z).length()
		var h := Geo.fbm(x * 0.012, z * 0.012, 4, 4) * 16.0 * smoothstep(70.0, 130.0, r)
		return Vector3(x, h - 0.1, z)
	dunes.mesh = Geo.grid_mesh(n, n, dune_fn, false)
	dunes.material_override = dune_mat
	dunes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(dunes)

	# telón de cascadas de niebla (cilindro enorme visto desde dentro)
	var mist_mat := ShaderMaterial.new()
	mist_mat.shader = MIST_SHADER
	var mist := MeshInstance3D.new()
	mist.mesh = Geo.lathe([Vector2(170.0, -4.0), Vector2(170.0, 120.0), Vector2(150.0, 200.0), Vector2(90.0, 300.0), Vector2(2.0, 345.0)], 48, true)
	mist.material_override = mist_mat
	mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mist)

	# el cubo: apoyado en una arista, con un vértice hacia abajo
	var cube_mat := mat(Color(0.02, 0.028, 0.05), 0.45, 0.45)
	_cube = add_box(CUBE_POS, Vector3.ONE * CUBE_EDGE, cube_mat, false)
	_cube.basis = Basis(Vector3(1, 0, 0), deg_to_rad(35.0)) * Basis(Vector3(0, 1, 0), deg_to_rad(38.0))
	_cube.position = CUBE_POS

	# figura lejana (el recuerdo de alguien que mira el cubo)
	var dark := mat(Color(0.02, 0.02, 0.03), 0.9)
	add_cylinder(Vector3(5.0, 0.85, -26.0), 0.22, 1.7, dark, false, 10)
	add_sphere(Vector3(5.0, 1.8, -26.0), 0.16, dark, false)

	add_trigger("orilla_cubo", Vector3(0, 3.0, -22.0), Vector3(18.0, 6.0, 12.0))


func tick(delta: float, _player: Node3D) -> void:
	if _cube:
		_cube.position.y = CUBE_POS.y + sin(_t * 0.35) * 0.6
		_cube.rotate_y(delta * 0.012)
