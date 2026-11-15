extends SceneTree
## Retrato de Andro con el preset "plastilina" real (StreetLook + ClayStyle). Uso:
## godot --path <proyecto> -s <este.gd> -- <vista: face|close|full|side|back> <salida.png> [modo: preset|estudio|neutro]
## modo "estudio" (F1): luna morada tenue + farol ámbar sin sombra + niebla de profundidad (solo aquí, no toca el preset global).
## modo "neutro" (P1): fondo gris y luz blanca suave, como la hoja 68107. Sirve para calibrar color y brillo de la ropa sin la luz morada.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var view: String = args[0] if args.size() > 0 else "face"
	var out: String = args[1] if args.size() > 1 else "/tmp/shot.png"
	var mode: String = args[2] if args.size() > 2 else "preset"
	ClayStyle.enabled = true
	var look := StreetLook.new()
	look.enable_backdrop = false
	look.enable_rain = false
	look.enable_post_fx = false
	look.follow_reflection_probe = false
	look.initial_preset = "plastilina"
	root.add_child(look)
	if mode == "estudio":
		await process_frame   # StreetLook arma su ambiente en _ready()
		_studio(look)
	elif mode == "neutro":
		await process_frame
		_neutral(look)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	floor_mi.mesh = pm
	if mode == "neutro":
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color(0.5, 0.5, 0.51)
		gm.roughness = 1.0
		floor_mi.material_override = gm
	else:
		floor_mi.material_override = Palette.sidewalk()
	root.add_child(floor_mi)
	var m := PlayerModel.new()
	root.add_child(m)
	var yaw := 0.0
	match view:
		"side", "hperfil", "mano_perfil": yaw = -PI * 0.5
		"hperfil2": yaw = PI * 0.5
		"hback": yaw = PI
		"h34": yaw = deg_to_rad(-45.0)
		"back": yaw = PI
		"bufanda", "torso": yaw = deg_to_rad(20.0)
		"torso_back": yaw = PI + deg_to_rad(20.0)
		_: yaw = deg_to_rad(20.0) if view == "face" or view == "close" else 0.0
	m.rotation.y = yaw + PI
	# Pose: ANDRO_POSE="estado,velocidad,fase" (p. ej. "run,5.0,1.2"); por defecto idle
	await process_frame     # _ready de PlayerModel (construye pivotes) antes de posar
	var ps := OS.get_environment("ANDRO_POSE").split(",")
	if ps.size() == 3:
		m.snap_pose(ps[0], float(ps[1]), float(ps[2]))
	else:
		m.snap_pose("idle", 0.0, 0.0)
	root.add_child(ClayStyle.new())
	var cam := Camera3D.new()
	cam.far = 2400.0
	root.add_child(cam)
	match view:
		"torso", "torso_back":
			cam.fov = 34.0
			cam.position = Vector3(0, 1.3, 2.3)
			cam.look_at(Vector3(0, 1.22, 0))
		"bufanda":
			cam.fov = 30.0
			cam.position = Vector3(0, 1.5, 1.7)
			cam.look_at(Vector3(0, 1.47, 0))
		"mano", "mano_perfil":     # F1.1: primer plano de la mano izquierda (frente o perfil)
			var hc: Vector3 = (m._joints["hand_l"] as Node3D).global_position + Vector3(0, -0.09, 0)
			cam.fov = 24.0
			cam.position = hc + Vector3(0, 0.02, 1.35)
			cam.look_at(hc)
		"hback":
			cam.fov = 30.0
			cam.position = Vector3(0, 1.9, 1.5)
			cam.look_at(Vector3(0, 1.86, 0))
		"hperfil", "hperfil2", "h34":
			cam.fov = 30.0
			cam.position = Vector3(0, 1.84, 1.5)
			cam.look_at(Vector3(0, 1.84, 0))
		"face":
			cam.fov = 35.0
			cam.position = Vector3(0, 1.80, 1.5)
			cam.look_at(Vector3(0, 1.78, 0))
		"close":
			cam.fov = 40.0
			cam.position = Vector3(0, 1.1, 3.2)
			cam.look_at(Vector3(0, 0.92, 0))
		_:
			cam.fov = 40.0
			cam.position = Vector3(0, 1.1, 5.0)
			cam.look_at(Vector3(0, 1.0, 0))
	cam.make_current()
	for i in 8:
		await process_frame
	# Cara por pasos para las capturas: ANDRO_BLINK=0|1|2, ANDRO_GAZE="x,y" (rad), ANDRO_BROW="izq,der" (-1..1)
	var gz := OS.get_environment("ANDRO_GAZE").split(",")
	var br := OS.get_environment("ANDRO_BROW").split(",")
	m.set_face(int(OS.get_environment("ANDRO_BLINK")),
		Vector2(float(gz[0]), float(gz[1])) if gz.size() == 2 else Vector2.ZERO,
		float(br[0]) if br.size() == 2 else 0.0, float(br[1]) if br.size() == 2 else 0.0)
	if OS.get_environment("ANDRO_SCARF") != "":
		m.set_scarf_variant(int(OS.get_environment("ANDRO_SCARF")))
	if OS.get_environment("ANDRO_HAIR") != "":
		m.set_hair_variant(int(OS.get_environment("ANDRO_HAIR")))
	m.set_mouth(int(OS.get_environment("ANDRO_MOUTH")) if OS.get_environment("ANDRO_MOUTH") != "" else 1)
	for i in 52:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	print("SHOT_OK ", out)
	quit()


## F1: luz de noche barata. Valores de partida (ajustar mirando la captura).
func _studio(look: StreetLook) -> void:
	look.sun.light_color = Color(0.66, 0.60, 0.95)      # luna morada tenue
	look.sun.light_energy = 0.55
	var lamp := OmniLight3D.new()                       # farol ámbar: sin sombra (regla de CONTRACT.md)
	lamp.position = Vector3(1.6, 2.4, 1.4)
	lamp.light_color = Color(1.0, 0.68, 0.38)
	lamp.light_energy = 1.2
	lamp.omni_range = 7.0
	lamp.shadow_enabled = false
	root.add_child(lamp)
	var env := look.environment                         # niebla de profundidad simple (sin volumétrica)
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.17, 0.13, 0.25)
	env.fog_depth_begin = 6.0
	env.fog_depth_end = 40.0
	env.fog_depth_curve = 1.0
	env.fog_density = 0.7
	env.fog_height_density = 0.0
	env.volumetric_fog_enabled = false


## P1: luz de estudio neutra (gris/blanco) para comparar con la hoja 68107. Solo en las capturas.
func _neutral(look: StreetLook) -> void:
	look.sun.light_color = Color(1.0, 0.98, 0.95)
	look.sun.light_energy = 1.0
	look.sun.rotation_degrees = Vector3(-38.0, 35.0, 0.0)
	var fill := OmniLight3D.new()                       # relleno suave desde el otro lado, sin sombra
	fill.position = Vector3(-2.0, 1.8, 2.4)
	fill.light_color = Color(0.9, 0.93, 1.0)
	fill.light_energy = 0.9
	fill.omni_range = 9.0
	fill.shadow_enabled = false
	root.add_child(fill)
	var env := look.environment
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.5, 0.5, 0.51)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.78, 0.8)
	env.ambient_light_energy = 0.8
	env.fog_enabled = false
	env.volumetric_fog_enabled = false
	env.tonemap_exposure = 1.0
	env.adjustment_enabled = false          # sin LUT ni contraste del preset (llevan sombras moradas)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.ambient_light_sky_contribution = 0.0
	env.glow_enabled = false
