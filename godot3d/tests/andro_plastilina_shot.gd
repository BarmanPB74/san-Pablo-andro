extends SceneTree
## Retrato de Andro con el preset "plastilina" real (StreetLook + ClayStyle). Uso:
## godot --path <proyecto> -s <este.gd> -- <vista: face|close|full|side|back> <salida.png> [modo: preset|estudio]
## modo "estudio" (F1): luna morada tenue + farol ámbar sin sombra + niebla de profundidad (solo aquí, no toca el preset global).

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
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	floor_mi.mesh = pm
	floor_mi.material_override = Palette.sidewalk()
	root.add_child(floor_mi)
	var m := PlayerModel.new()
	root.add_child(m)
	var yaw := 0.0
	match view:
		"side": yaw = -PI * 0.5
		"back": yaw = PI
		_: yaw = deg_to_rad(20.0) if view == "face" or view == "close" else 0.0
	m.rotation.y = yaw + PI
	m.snap_pose("idle", 0.0, 0.0)
	root.add_child(ClayStyle.new())
	var cam := Camera3D.new()
	cam.far = 2400.0
	root.add_child(cam)
	match view:
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
	for i in 60:
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
