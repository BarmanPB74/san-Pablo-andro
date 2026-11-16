class_name HubScene
extends StageScene
## El Umbral: el primer mundo. Un suelo divino de mármol negro con incrustaciones de oro (rosa de los vientos, estrella de
## 12 puntas, rosetón, arcos y una franja de signos) bajo un cielo azul de amanecer con nubes. No hay sol visible, ni niebla,
## ni objetos: Andro aprenderá a crear lo que necesite (puertas, objetos...). Eso se diseña después.
## El límite jugable (muro invisible, radio PLAY_RADIUS) queda justo dentro del borde dorado del piso.

const SKY_SHADER := preload("res://stage/shaders/umbral_sky.gdshader")
const FLOOR_SHADER := preload("res://stage/shaders/divine_floor.gdshader")

const PLAY_RADIUS := 34.0          # radio jugable (m)
## Hacia dónde amanece (dirección al resplandor). La luz principal viene de ahí; el disco del sol no se dibuja.
const DAWN_DIR := Vector3(-0.55, 0.21, -0.80)

## Dónde se conjura la puerta por defecto (frente al punto de partida).
var door_spot := Vector3(0, 0, -15)


func _init() -> void:
	title = "El Umbral"
	spawn_pos = Vector3(0, 0.1, 6)
	spawn_yaw = 0.0


func build() -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sky_mat.set_shader_parameter("glow_dir", DAWN_DIR)
	make_environment(sky_mat, Color(0.70, 0.78, 0.94), 0.0, 1.0, Color(1.0, 0.84, 0.70), 1.0, -DAWN_DIR.normalized())
	env.fog_enabled = false            # sin niebla: el suelo dorado se ve nítido hasta el horizonte
	env.sky.radiance_size = Sky.RADIANCE_SIZE_256
	sun.light_energy = 0.0             # el sol no se ve y no hace destello en el piso pulido: la luz viene del cielo (ambiente)

	var floor_mat := ShaderMaterial.new()
	floor_mat.shader = FLOOR_SHADER
	floor_mat.set_shader_parameter("noise_tex", FxTex.noise())
	floor_mat.set_shader_parameter("glow_dir", DAWN_DIR)
	add_ground(4000.0, floor_mat)      # tan grande que su borde queda a ~2 km, bajo el horizonte
	add_bounds_circle(PLAY_RADIUS)
