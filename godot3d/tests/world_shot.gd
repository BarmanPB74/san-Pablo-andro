extends SceneTree
## Captura del mundo con cámara configurable.
## Uso: ... -s res://tests/world_shot.gd -- <escena> <salida.png> <frames> cx cy cz tx ty tz [day|night] [fov]

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var packed: PackedScene = load(a[0])
	var scene := packed.instantiate()
	root.add_child(scene)
	var cam: Camera3D = scene.get_node("Camera3D")
	var pos := Vector3(float(a[3]), float(a[4]), float(a[5]))
	var tgt := Vector3(float(a[6]), float(a[7]), float(a[8]))
	cam.transform = Transform3D(Basis.looking_at(tgt - pos), pos)
	if a.size() > 10:
		cam.fov = float(a[10])
	if a.size() > 9 and a[9] == "night":
		var env: Environment = scene.get_node("Env").environment
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.03, 0.035, 0.07)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.2, 0.22, 0.35)
		env.ambient_light_energy = 0.5
		env.fog_light_color = Color(0.05, 0.06, 0.1)
		env.fog_density = 0.006
		env.glow_intensity = 1.2
		env.glow_bloom = 0.1
		var sun: DirectionalLight3D = scene.get_node("Sun")
		sun.light_energy = 0.12
		sun.light_color = Color(0.5, 0.6, 1.0)
	if a.size() > 11 and a[11] == "noshadow":
		(scene.get_node("Sun") as DirectionalLight3D).shadow_enabled = false
	for i in int(a[2]):
		await process_frame
	var dc := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var objs := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	print("RENDER_INFO draw_calls=%d primitives=%d objects=%d" % [dc, prims, objs])
	root.get_viewport().get_texture().get_image().save_png(a[1])
	print("SCREENSHOT_OK ", a[1])
	quit()
