class_name Fireball
extends Node3D
## Bola de fuego: sale de una esfera de poder, vuela recta, deja estela y explota al chocar con el mundo o con objetos.
## Empuja los objetos físicos (capa 4). Vive como mucho LIFE s. Todo procedural.

const SPEED := 20.0
const LIFE := 2.4
const RADIUS := 0.2
const HIT_MASK := (1 << 0) | (1 << 3)       # mundo | props (nunca al jugador)
const PUSH := 7.0                            # velocidad (m/s) que recibe un objeto liviano
const CORE_SHADER := preload("res://powers/shaders/fireball.gdshader")

signal exploded(at: Vector3, collider: Object)

var velocity := Vector3.ZERO
var _age := 0.0
var _done := false
var _light: OmniLight3D


## Crea y lanza una bola desde `from` hacia `dir` bajo `parent`.
static func launch(parent: Node, from: Vector3, dir: Vector3) -> Fireball:
	var f := Fireball.new()
	f.name = "Fireball"
	parent.add_child(f)
	f.global_position = from
	f.velocity = dir.normalized() * SPEED
	return f


func _ready() -> void:
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = RADIUS
	sm.height = RADIUS * 2.0
	sm.radial_segments = 16
	sm.rings = 8
	core.mesh = sm
	var mat := ShaderMaterial.new()
	mat.shader = CORE_SHADER
	core.material_override = mat
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)
	add_child(PowerFx.halo(1.5, Color(1.0, 0.5, 0.12, 0.85)))
	add_child(_trail())
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.2)
	_light.light_energy = 1.8
	_light.omni_range = 6.0
	_light.shadow_enabled = false
	_light.light_specular = 0.2
	add_child(_light)


func _trail() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Trail"
	p.amount = 26
	p.lifetime = 0.5
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.1
	p.direction = Vector3.ZERO
	p.spread = 180.0
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.5
	p.gravity = Vector3(0, 1.3, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 0.8
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	g.colors = PackedColorArray([Color(1.0, 0.85, 0.45, 0.9), Color(1.0, 0.35, 0.05, 0.6), Color(0.3, 0.02, 0.0, 0.0)])
	p.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.5)
	p.mesh = q
	p.material_override = PowerFx.additive_billboard()
	p.emitting = true
	return p


func _physics_process(delta: float) -> void:
	if _done:
		return
	_age += delta
	if _age >= LIFE:
		_explode(Vector3.UP, null, global_position)
		return
	var next := global_position + velocity * delta
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position, next + velocity.normalized() * RADIUS, HIT_MASK)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		global_position = next
	else:
		_explode(hit.normal, hit.collider, hit.position)


func _explode(normal: Vector3, collider: Object, at: Vector3) -> void:
	_done = true
	global_position = at + normal * 0.1
	if collider is RigidBody3D:
		var rb := collider as RigidBody3D
		rb.apply_impulse(velocity.normalized() * PUSH * minf(rb.mass, 3.0), at - rb.global_position)
	var parent := get_parent()
	if parent:
		spawn_burst(parent, global_position)
	exploded.emit(global_position, collider)
	queue_free()


## Explosión: chispas, destello y una luz que se apaga. Se borra sola.
static func spawn_burst(parent: Node, at: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "FireBurst"
	parent.add_child(root)
	root.global_position = at
	var p := CPUParticles3D.new()
	p.amount = 40
	p.lifetime = 0.7
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.12
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 6.0
	p.gravity = Vector3(0, -3.0, 0)
	p.damping_min = 2.0
	p.damping_max = 4.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	g.colors = PackedColorArray([Color(1.0, 0.95, 0.6, 1.0), Color(1.0, 0.4, 0.06, 0.8), Color(0.25, 0.02, 0.0, 0.0)])
	p.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2(0.4, 0.4)
	p.mesh = q
	p.material_override = PowerFx.additive_billboard()
	root.add_child(p)
	p.emitting = true
	var flash := PowerFx.halo(2.6, Color(1.0, 0.6, 0.2, 0.9))
	root.add_child(flash)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.2)
	light.light_energy = 3.0
	light.omni_range = 7.0
	light.shadow_enabled = false
	root.add_child(light)
	var tw := root.create_tween().set_parallel(true)
	tw.tween_property(light, "light_energy", 0.0, 0.45)
	tw.tween_property(flash, "scale", Vector3.ONE * 1.8, 0.3)
	tw.tween_method(func(a: float) -> void:
		(flash.material_override as StandardMaterial3D).albedo_color.a = a, 0.9, 0.0, 0.3)
	tw.chain().tween_callback(root.queue_free).set_delay(0.45)
	return root
