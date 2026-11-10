class_name ValleyBackdrop
extends Node3D
## Anillo de montañas low-poly alrededor del barrio (valle de Aburrá).
## El valle corre Norte–Sur: las laderas Este y Oeste son más altas y cercanas,
## Norte y Sur se abren. Sin colisión, sin sombras, 2 draw calls.
## La cámara necesita far >= outer_radius + 400 (Camera3D por defecto: 4000).

@export var inner_radius := 1100.0     # cordillera cercana
@export var outer_radius := 1900.0     # cordillera lejana
@export var segments := 140
@export var seed_value := 4242

var _near: MeshInstance3D
var _far: MeshInstance3D


func _ready() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.fractal_octaves = 4
	noise.frequency = 1.0
	# cercana: verde oscuro teal; lejana: azul grisáceo (perspectiva aérea)
	_far = _make_ring(noise, outer_radius, 380.0, 560.0, Color(0.2, 0.26, 0.3), 0.0)
	_near = _make_ring(noise, inner_radius, 190.0, 300.0, Color(0.1, 0.17, 0.13), 50.0)
	_far.name = "MountainsFar"
	_near.name = "MountainsNear"
	add_child(_far)
	add_child(_near)


## Construye un anillo: por cada ángulo 4 vértices (base, falda, hombro, cresta).
func _make_ring(noise: FastNoiseLite, radius: float, h_min: float, h_max: float,
		tint: Color, noise_z: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := 4
	var grid: Array = []
	for i in segments + 1:
		var a := TAU * float(i) / float(segments)
		var dir := Vector2(cos(a), sin(a))       # x = Este, y = Sur (+Z)
		# valle N-S: más altas al Este/Oeste (|cos|), más bajas al Norte/Sur
		var side := absf(dir.x)
		var n1 := noise.get_noise_3d(dir.x * 1.6, dir.y * 1.6, noise_z) * 0.5 + 0.5
		var n2 := noise.get_noise_3d(dir.x * 6.0, dir.y * 6.0, noise_z + 9.0) * 0.5 + 0.5
		var ridge := lerpf(h_min, h_max, n1) * lerpf(0.45, 1.0, side) + (n2 - 0.5) * 70.0
		var r := radius * lerpf(1.15, 0.85, side)   # Norte/Sur más lejos
		var col_row: Array = []
		for j in rows:
			var t := float(j) / float(rows - 1)
			# perfil cóncavo de ladera: sube rápido al final
			var y := lerpf(-40.0, ridge, pow(t, 0.8))
			var jitter := (noise.get_noise_3d(dir.x * 12.0, dir.y * 12.0, noise_z + j * 3.0)) * 60.0
			var rr := r + t * 380.0 + jitter * (1.0 if j > 0 and j < rows - 1 else 0.0)
			var v := Vector3(dir.x * rr, y, dir.y * rr)
			# color: base más oscura y verde, cresta algo más clara
			var c := tint.darkened(0.35 * (1.0 - t)).lightened(0.08 * t)
			col_row.append([v, c])
		grid.append(col_row)
	for i in segments:
		for j in rows - 1:
			var a0: Array = grid[i][j]
			var a1: Array = grid[i + 1][j]
			var b0: Array = grid[i][j + 1]
			var b1: Array = grid[i + 1][j + 1]
			_tri(st, a0, b0, a1)
			_tri(st, a1, b0, b1)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = Palette.mountain_far()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 200.0
	return mi


func _tri(st: SurfaceTool, a: Array, b: Array, c: Array) -> void:
	for p in [a, b, c]:
		st.set_color(p[1])
		st.add_vertex(p[0])


## Ajusta la neblina y las luces nocturnas del fondo (lo llama StreetLook).
func set_look(haze_color: Color, haze_base: float, haze_top: float, night: float) -> void:
	var m := Palette.mountain_far() as ShaderMaterial
	m.set_shader_parameter("haze_color", haze_color)
	m.set_shader_parameter("haze_amount", haze_base)
	m.set_shader_parameter("haze_top", haze_top)
	m.set_shader_parameter("night", night)
