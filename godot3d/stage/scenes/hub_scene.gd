class_name HubScene
extends StageScene
## El Umbral: el primer mundo. Una dimensión vacía y hermosa: piso liso y pulido, humo gris que fluye en capas,
## un cielo de colores suaves y esferas de energía enormes y lejanas, como si un planeta estuviera muy cerca.
## No hay objetos: Andro aprenderá a crear lo que necesite (puertas, objetos...). Eso se diseña después.
## El límite jugable (muro invisible) queda dentro de la niebla, así que nunca se ve un borde.

const SKY_SHADER := preload("res://stage/shaders/umbral_sky.gdshader")
const FLOOR_SHADER := preload("res://stage/shaders/umbral_floor.gdshader")

const FOG_COLOR := Color(0.50, 0.50, 0.56)
const PLAY_RADIUS := 34.0          # radio jugable (m)

## Dónde se conjura la puerta por defecto (frente al punto de partida).
var door_spot := Vector3(0, 0, -15)

var sky_orbs: SkyOrbs
var smoke: SmokeFX


func _init() -> void:
	title = "El Umbral"
	spawn_pos = Vector3(0, 0.1, 6)
	spawn_yaw = 0.0


func build() -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	# La luz viene del "planeta" grande: mismo lado que su esfera de energía, con su color
	var to_orb := SkyOrbs.direction(0)
	make_environment(sky_mat, FOG_COLOR, 0.03, 1.0, Color(0.82, 0.9, 1.0), 0.65, -to_orb)
	sun.light_specular = 0.25          # sin brillo de espejo largo sobre el piso
	env.sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.fog_sky_affect = 0.0           # el cielo conserva sus colores; la niebla solo come el piso y el humo
	set_flat_ambient(Color(0.52, 0.50, 0.62), 0.7)

	var floor_mat := ShaderMaterial.new()
	floor_mat.shader = FLOOR_SHADER
	floor_mat.set_shader_parameter("noise_tex", FxTex.noise())
	add_ground(170.0, floor_mat)
	add_bounds_circle(PLAY_RADIUS)

	sky_orbs = SkyOrbs.new()
	add_child(sky_orbs)
	smoke = SmokeFX.new()
	add_child(smoke)


func tick(delta: float, player: Node3D) -> void:
	if sky_orbs:
		sky_orbs.tick(delta, player)
	if smoke:
		smoke.tick(delta, player)
