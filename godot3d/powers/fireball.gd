class_name Fireball
extends Node3D
## Bola de fuego: sale de una esfera de poder, vuela recta, deja estela y explota al chocar con el mundo o con objetos.
## Empuja los objetos físicos (capa 4) y hace daño en un radio a todo lo que tenga `take_damage(cantidad)`.
## `rank` (0..10, ver Abilities) sube daño, explosión, empuje y tamaño, y cambia el color: naranja, roja, azul, morada,
## morada y negra. Vive como mucho LIFE s. Todo procedural.

const SPEED := 20.0
const LIFE := 2.4
const RADIUS := 0.2
const HIT_MASK := (1 << 0) | (1 << 3)       # mundo | props (nunca al jugador)
const PUSH := 7.0                            # velocidad (m/s) que recibe un objeto liviano (rango 0)
const CORE_SHADER := preload("res://powers/shaders/fireball.gdshader")

signal exploded(at: Vector3, collider: Object)

var rank := 0
var damage := 20.0
var blast_radius := 1.6
var push := PUSH
var tier := {}
var damaged: Array = []                      # a quién le hizo daño al explotar
var velocity := Vector3.ZERO
var _age := 0.0
var _done := false
var _light: OmniLight3D


## Crea y lanza una bola desde `from` hacia `dir` bajo `parent`.
static func launch(parent: Node, from: Vector3, dir: Vector3, p_rank := 0) -> Fireball:
	var f := Fireball.new()
	f.name = "Fireball"
	f.set_rank(p_rank)
	parent.add_child(f)
	f.global_position = from
	f.velocity = dir.normalized() * SPEED
	return f


func set_rank(r: int) -> void:
	rank = clampi(r, 0, Abilities.MAX_RANK)
	damage = Abilities.fireball_damage(rank)
	blast_radius = Abilities.fireball_radius(rank)
	push = Abilities.fireball_push(rank)
	tier = Abilities.tier("fireball", rank)


func _ready() -> void:
	if tier.is_empty():
		set_rank(rank)
	var glow: Color = tier.glow
	var dark: bool = tier.get("dark", false)
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = RADIUS * Abilities.fireball_scale(rank)
	sm.height = sm.radius * 2.0
	sm.radial_segments = 16
	sm.rings = 8
	core.mesh = sm
	var mat := ShaderMaterial.new()
	mat.shader = CORE_SHADER
	mat.set_shader_parameter("core_col", tier.core)
	mat.set_shader_parameter("edge_col", tier.edge)
	core.material_override = mat
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)
	add_child(PowerFx.halo(1.5 * Abilities.fireball_scale(rank), Color(glow, 0.85)))
	add_child(_trail())
	if dark:
		add_child(_smoke())
	_light = OmniLight3D.new()
	_light.light_color = glow
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
	var core: Color = tier.core
	var glow: Color = tier.glow
	g.colors = PackedColorArray([Color(core, 0.9), Color(glow, 0.6), Color(glow.darkened(0.7), 0.0)])
	p.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.5) * Abilities.fireball_scale(rank)
	p.mesh = q
	p.material_override = PowerFx.additive_billboard()
	p.emitting = true
	return p


## Estela de humo negro (solo en la etapa "morada y negra").
func _smoke() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Smoke"
	p.amount = 18
	p.lifetime = 0.7
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.16
	p.spread = 180.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.7
	p.gravity = Vector3(0, 0.6, 0)
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.2
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(0.02, 0.0, 0.05, 0.9), Color(0.03, 0.0, 0.07, 0.6), Color(0.05, 0.0, 0.1, 0.0)])
	p.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2(0.55, 0.55)
	p.mesh = q
	p.material_override = PowerFx.smoke_billboard()
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
	_blast(at, collider)
	var parent := get_parent()
	if parent:
		spawn_burst(parent, global_position, tier, blast_radius)
	exploded.emit(global_position, collider)
	queue_free()


## Daño y empuje en el radio de la explosión. Lo que tenga `take_damage(cantidad)` recibe el daño (menos lejos del centro);
## los cuerpos físicos reciben un empujón hacia afuera. El cuerpo golpeado directamente siempre recibe el daño completo.
func _blast(at: Vector3, direct: Object) -> void:
	var space := get_world_3d().direct_space_state
	var sph := SphereShape3D.new()
	sph.radius = blast_radius
	var qp := PhysicsShapeQueryParameters3D.new()
	qp.shape = sph
	qp.transform = Transform3D(Basis(), at)
	qp.collision_mask = HIT_MASK
	var hits := space.intersect_shape(qp, 24)
	var seen := {}
	if direct != null:
		hits.append({"collider": direct})
	for h in hits:
		var c: Object = h.collider
		if c == null or seen.has(c.get_instance_id()):
			continue
		seen[c.get_instance_id()] = true
		var d := 0.0
		if c is Node3D:
			d = (c as Node3D).global_position.distance_to(at)
		var k := 1.0 if c == direct else clampf(1.0 - d / maxf(blast_radius, 0.1), 0.25, 1.0)
		if c.has_method("take_damage"):
			c.call("take_damage", damage * k)
			damaged.append(c)
		if c is RigidBody3D:
			var rb := c as RigidBody3D
			var out := (rb.global_position - at)
			out = out.normalized() if out.length() > 0.05 else velocity.normalized()
			var dir := (velocity.normalized() * 0.6 + out * 0.4).normalized()
			rb.apply_impulse(dir * push * minf(rb.mass, 3.0) * k, Vector3.ZERO)


## Explosión: chispas, destello y una luz que se apaga. Se borra sola. `radius` escala el efecto.
static func spawn_burst(parent: Node, at: Vector3, t := {}, radius := 1.6) -> Node3D:
	var tier_d: Dictionary = t if not t.is_empty() else Abilities.tier("fireball", 0)
	var kscale := clampf(radius / 1.6, 0.8, 2.6)
	var root := Node3D.new()
	root.name = "FireBurst"
	parent.add_child(root)
	root.global_position = at
	var p := CPUParticles3D.new()
	p.amount = int(40.0 * kscale)
	p.lifetime = 0.7
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.12
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 2.0 * kscale
	p.initial_velocity_max = 6.0 * kscale
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
	var bc: Color = tier_d.core
	var bg: Color = tier_d.glow
	g.colors = PackedColorArray([Color(bc, 1.0), Color(bg, 0.8), Color(bg.darkened(0.75), 0.0)])
	p.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2(0.4, 0.4) * kscale
	p.mesh = q
	p.material_override = PowerFx.additive_billboard()
	root.add_child(p)
	p.emitting = true
	var flash := PowerFx.halo(2.6 * kscale, Color(tier_d.glow, 0.9))
	root.add_child(flash)
	if tier_d.get("dark", false):
		var sm := CPUParticles3D.new()
		sm.amount = 20
		sm.lifetime = 0.9
		sm.one_shot = true
		sm.explosiveness = 1.0
		sm.local_coords = false
		sm.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		sm.emission_sphere_radius = 0.2
		sm.direction = Vector3.UP
		sm.spread = 180.0
		sm.initial_velocity_min = 1.0 * kscale
		sm.initial_velocity_max = 3.0 * kscale
		sm.gravity = Vector3(0, 0.5, 0)
		var sg := Gradient.new()
		sg.colors = PackedColorArray([Color(0.02, 0, 0.05, 0.95), Color(0.04, 0, 0.09, 0.0)])
		sm.color_ramp = sg
		var sq := QuadMesh.new()
		sq.size = Vector2(0.9, 0.9) * kscale
		sm.mesh = sq
		sm.material_override = PowerFx.smoke_billboard()
		root.add_child(sm)
		sm.emitting = true
	var light := OmniLight3D.new()
	light.light_color = tier_d.glow
	light.light_energy = 3.0
	light.omni_range = 7.0 * minf(kscale, 1.6)
	light.shadow_enabled = false
	root.add_child(light)
	var tw := root.create_tween().set_parallel(true)
	tw.tween_property(light, "light_energy", 0.0, 0.45)
	tw.tween_property(flash, "scale", Vector3.ONE * 1.8, 0.3)
	tw.tween_method(func(a: float) -> void:
		(flash.material_override as StandardMaterial3D).albedo_color.a = a, 0.9, 0.0, 0.3)
	tw.chain().tween_callback(root.queue_free).set_delay(0.45)
	return root
