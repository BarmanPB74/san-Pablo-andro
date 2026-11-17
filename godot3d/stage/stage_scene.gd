class_name StageScene
extends Node3D
## Base de cada escena del juego (el umbral y los recuerdos). Cada escena es dueña de su propio
## cielo, niebla y luces: al cambiar de escena el Stage la libera completa y construye la siguiente.
## Todo por código (sin assets). Las escenas heredan y rellenan `build()`.

signal portal_entered(target: String)
signal objective_reached(objective: String)

var id := ""
var title := ""
## Dónde aparece Andro (y hacia dónde mira; yaw 0 = mira a -Z).
var spawn_pos := Vector3(0, 0.1, 0)
var spawn_yaw := 0.0
## Inclinación inicial de la cámara (rad; positivo = mira hacia arriba, negativo = hacia abajo).
var spawn_pitch := -0.16
## Portales que conjura Andro en esta escena: a qué distancia máxima aparecen delante de él (m) y de qué tamaño
## (ancho × alto de la abertura). En espacios cerrados (la casa) se achican para que quepan bajo el techo.
var portal_distance := 7.5
var portal_size := Vector2(2.6, 5.6)
## Techo del vuelo libre: altura máxima (m) del origen de Andro. Donde hay techo real (la casa) manda la colisión.
var fly_ceiling := 1000.0
var env: Environment
var sun: DirectionalLight3D
var portals: Array[Portal] = []
var _t := 0.0


func _ready() -> void:
	build()


func build() -> void:
	pass


## Se llama cada frame con el jugador (para animar cosas de la escena que dependen de él).
func tick(_delta: float, _player: Node3D) -> void:
	pass


func _process(delta: float) -> void:
	_t += delta


# ------------------------------------------------------------------ materiales

static func mat(color: Color, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m


static func glow_mat(color: Color, energy := 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


# ------------------------------------------------------------------ entorno

## Crea el WorldEnvironment (cielo, niebla, ambiente, tonemap) y la luz principal.
func make_environment(sky_material: Material, fog_color: Color, fog_density: float, ambient_energy := 0.8,
		sun_color := Color(0.75, 0.82, 1.0), sun_energy := 0.9, sun_dir := Vector3(-0.5, -0.8, -0.35)) -> void:
	env = Environment.new()
	var sky := Sky.new()
	sky.sky_material = sky_material
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = ambient_energy
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_light_color = fog_color
	env.fog_density = fog_density
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.08
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.05
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = sun_color
	sun.light_energy = sun_energy
	sun.shadow_enabled = true
	sun.shadow_bias = 0.05
	sun.shadow_blur = 1.6
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 38.0
	add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, sun_dir, Vector3.UP)


## Ambiente de color fijo (en vez del cielo): útil cuando el cielo es negro pero la escena debe leerse.
func set_flat_ambient(color: Color, energy := 1.0) -> void:
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = color
	env.ambient_light_energy = energy


# ------------------------------------------------------------------ geometría

## Caja con colisión opcional (capa 1 = mundo). Devuelve la malla.
func add_box(pos: Vector3, size: Vector3, material: Material, collide := true, yaw := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = material
	mi.position = pos
	mi.rotation.y = yaw
	add_child(mi)
	if collide:
		_add_collider_box(mi, size)
	return mi


func add_cylinder(pos: Vector3, radius: float, height: float, material: Material, collide := true, segments := 20) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = segments
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = material
	mi.position = pos
	add_child(mi)
	if collide:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = radius
		sh.height = height
		cs.shape = sh
		sb.add_child(cs)
		mi.add_child(sb)
	return mi


func add_sphere(pos: Vector3, radius: float, material: Material, collide := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 28
	sm.rings = 14
	mi.mesh = sm
	mi.material_override = material
	mi.position = pos
	add_child(mi)
	if collide:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = radius
		cs.shape = sh
		sb.add_child(cs)
		mi.add_child(sb)
	return mi


func _add_collider_box(parent: Node3D, size: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	sb.add_child(cs)
	parent.add_child(sb)


## Piso grande con colisión (superficie en y = 0).
func add_ground(extent: float, material: Material, y := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(extent, extent)
	mi.mesh = pm
	mi.material_override = material
	mi.position = Vector3(0, y, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(extent, 2.0, extent)
	cs.shape = sh
	cs.position = Vector3(0, -1.0, 0)
	sb.add_child(cs)
	mi.add_child(sb)
	return mi


## Muro invisible alrededor de un área circular (para que no se salga del escenario).
func add_bounds_circle(radius: float, height := 30.0, segments := 16) -> void:
	for i in segments:
		var a := TAU * float(i) / float(segments)
		var seg := TAU * radius / float(segments) * 1.08
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(seg, height, 1.0)
		cs.shape = sh
		sb.add_child(cs)
		sb.position = Vector3(sin(a) * (radius + 0.5), height * 0.5, cos(a) * (radius + 0.5))
		sb.rotation.y = a
		add_child(sb)


# ------------------------------------------------------------------ portales y objetivos

## Conjura una puerta-portal hacia `target`. `yaw` orienta la cara de la galaxia (0 = mira a +Z).
func conjure_portal(target: String, pos: Vector3, yaw := 0.0, open_time := 1.8) -> Portal:
	var p := Portal.new(target, portal_size)
	p.position = pos
	p.rotation.y = yaw
	portal_parent().add_child(p)
	p.entered.connect(func(_p): portal_entered.emit(target))
	p.open(open_time)
	portals.append(p)
	return p


## Dónde cuelgan los portales conjurados (la casa los cuelga del cuarto actual para liberarlos con él).
func portal_parent() -> Node:
	return self


func clear_portals() -> void:
	for p in portals:
		if is_instance_valid(p):
			p.close(0.6)
			get_tree().create_timer(0.7).timeout.connect(p.queue_free)
	portals.clear()


## Zona invisible que avisa (objective_reached) cuando Andro entra.
func add_trigger(objective: String, pos: Vector3, size: Vector3) -> Area3D:
	var a := Area3D.new()
	a.name = "Trigger_" + objective
	a.collision_layer = 0
	a.collision_mask = 1 << 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	a.add_child(cs)
	a.position = pos
	add_child(a)
	a.body_entered.connect(func(body):
		if body.is_in_group("player"):
			objective_reached.emit(objective))
	return a
