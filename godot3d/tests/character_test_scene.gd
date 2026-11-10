extends Node3D
## Escena de prueba del personaje: piso grande, escalones (0.15 / 0.30 / 0.35 m),
## rampa, pared, luz, CameraRig, Player y (si existe) un auto real de VehicleFactory.
## Uso manual: abrir tests/scenes/character_test.tscn y correr (F6).

@export var spawn_vehicle := true

var player: Player
var rig: CameraRig
var vehicle: VehicleBody3D


func _ready() -> void:
	_env()
	# Piso
	_block(Vector3(0, -0.5, 0), Vector3(240, 1, 240), Palette.sidewalk())
	# Escalones hacia el este (x = 6..): 0.15, 0.30 m y un sardinel de 0.35 m al oeste
	_block(Vector3(8, 0.075, -6), Vector3(4, 0.15, 3), Palette.curb())
	_block(Vector3(24.5, 0.15, 0), Vector3(3, 0.3, 6), Palette.curb())      # escalón 0.30 (test)
	_block(Vector3(-8, 0.175, -6), Vector3(4, 0.35, 3), Palette.curb())     # sardinel 0.35
	# Escalera de 4 peldaños de 0.17 m
	for i in 4:
		var d := 0.35 if i < 3 else 1.5
		var h := 0.17 * (i + 1)
		_block(Vector3(0, h * 0.5, -14.4 - 0.35 * i - d * 0.5), Vector3(3, h, d), Palette.stone())
	# Rampa 14°
	var ramp := _block(Vector3(8, 0.6, -14), Vector3(3, 0.2, 6), Palette.concrete())
	ramp.rotation.x = deg_to_rad(14.0)
	# Pared
	_block(Vector3(-6, 1.5, -18), Vector3(6, 3, 0.4), Palette.brick())
	# Cámara y jugador
	rig = CameraRig.new()
	rig.name = "CameraRig"
	add_child(rig)
	player = Player.new()
	player.name = "Player"
	add_child(player)
	player.global_position = Vector3(0, 0.05, 0)
	if spawn_vehicle and ResourceLoader.exists("res://vehicles/vehicle_factory.gd"):
		var vf: Script = load("res://vehicles/vehicle_factory.gd")
		if vf and vf.can_instantiate():
			var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), Vector3(-20, 0.4, 10))
			vehicle = vf.call("spawn", "sedan", xf, self)


func _block(center: Vector3, size: Vector3, mat: Material) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	sb.position = center
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	sb.add_child(mi)
	add_child(sb)
	return sb


func _env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.3, 0.38, 0.5)
	psm.sky_horizon_color = Color(0.58, 0.6, 0.64)
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.9
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.2
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-45.0), deg_to_rad(-35.0), 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)
