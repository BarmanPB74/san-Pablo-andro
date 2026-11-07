extends Node3D
## Showroom: los 4 tipos de vehículo en fila, vistos a 3/4. Solo para capturas.
## Argumentos opcionales vía metadata "view": "front" (3/4 frontal) o "rear".

@export var view := "front"


func _ready() -> void:
	# Variables de entorno opcionales para capturas: VEH_VIEW=front|rear, VEH_FOCUS=taxi|sedan|...
	if OS.get_environment("VEH_VIEW") != "":
		view = OS.get_environment("VEH_VIEW")
	var focus := OS.get_environment("VEH_FOCUS")
	var focus_pos := Vector3.ZERO
	var env := WorldEnvironment.new()
	var e := Environment.new()
	# Cielo procedural solo para el showroom (reflejos del cromo y la pintura).
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.8
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.3
	add_child(sun)
	if OS.get_environment("VEH_NIGHT") != "":
		sun.light_energy = 0.05
		e.ambient_light_energy = 0.08
		e.background_energy_multiplier = 0.05
		e.glow_enabled = true
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	pm.material = Palette.asphalt()
	ground.mesh = pm
	add_child(ground)
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(80, 1, 80)
	cs.shape = bs
	cs.position.y = -0.5
	sb.add_child(cs)
	add_child(sb)
	var kinds := ["taxi", "sedan", "pickup", "buseta"]
	var x := 9.0
	for k: String in kinds:
		var yaw := deg_to_rad(-35.0) if view == "front" else deg_to_rad(145.0)
		var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(x, 0, 0))
		var v := VehicleFactory.spawn(k, xf, self)
		v.set_lights(true)
		if k == focus:
			focus_pos = xf.origin
		x -= 5.0 if k != "pickup" else 6.6
	var cam := Camera3D.new()
	cam.fov = 50.0
	add_child(cam)
	if focus != "":
		var d := 7.5 if focus != "buseta" else 10.0
		var off := Vector3(-0.35, 0.32, -1.0).normalized() * d
		if view == "rear":
			off = Vector3(0.6, 0.35, -1.0).normalized() * d
		cam.look_at_from_position(focus_pos + off, focus_pos + Vector3(0, 0.8, 0), Vector3.UP)
	else:
		cam.look_at_from_position(Vector3(-0.8, 4.6, -14.5), Vector3(-0.8, 0.8, 0), Vector3.UP)
