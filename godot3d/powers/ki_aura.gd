class_name KiAura
extends Node3D
## Carga de ki al estilo Dragon Ball: llamas que suben por un cilindro alrededor de Andro, ondas de energía en el piso,
## chispas que ascienden y una luz cálida que palpita. `power` (0..1) crece al cargar y baja al soltar.
## Se coloca en los pies de Andro (hijo de Player); PowerCaster sube su `y` con el flote.

const AURA_SHADER := preload("res://powers/shaders/ki_aura.gdshader")
const RING_SHADER := preload("res://powers/shaders/ki_ring.gdshader")
const HEIGHT := 2.5

var power := 0.0                 # intensidad visible (suavizada)
var _target := 0.0
var _boost := 0.0                # destello breve (barra llena / lanzamiento)
var _layers: Array[ShaderMaterial] = []
var _ring_mat: ShaderMaterial
var _sparks: CPUParticles3D
var _light: OmniLight3D
var _t := 0.0


func _ready() -> void:
	name = "KiAura"
	for k in 2:
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.55 - 0.12 * k
		cyl.bottom_radius = 0.95 - 0.25 * k
		cyl.height = HEIGHT
		cyl.radial_segments = 28
		cyl.rings = 10
		cyl.cap_top = false
		cyl.cap_bottom = false
		var mi := MeshInstance3D.new()
		mi.mesh = cyl
		mi.position = Vector3(0, HEIGHT * 0.5, 0)
		var m := ShaderMaterial.new()
		m.shader = AURA_SHADER
		m.set_shader_parameter("phase", 2.1 * k)
		m.set_shader_parameter("height", HEIGHT)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_layers.append(m)
	var ring := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(3.6, 3.6)
	ring.mesh = pm
	ring.position = Vector3(0, 0.04, 0)
	_ring_mat = ShaderMaterial.new()
	_ring_mat.shader = RING_SHADER
	ring.material_override = _ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	_sparks = CPUParticles3D.new()
	_sparks.amount = 36
	_sparks.lifetime = 1.2
	_sparks.local_coords = false
	_sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_sparks.emission_ring_axis = Vector3.UP
	_sparks.emission_ring_radius = 0.85
	_sparks.emission_ring_inner_radius = 0.35
	_sparks.emission_ring_height = 0.1
	_sparks.direction = Vector3.UP
	_sparks.spread = 12.0
	_sparks.initial_velocity_min = 1.4
	_sparks.initial_velocity_max = 3.2
	_sparks.gravity = Vector3(0, 0.6, 0)
	_sparks.scale_amount_min = 0.35
	_sparks.scale_amount_max = 0.9
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	_sparks.scale_amount_curve = curve
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(1.0, 0.95, 0.65, 0.95), Color(1.0, 0.5, 0.1, 0.7), Color(0.4, 0.05, 0.0, 0.0)])
	_sparks.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2(0.14, 0.14)
	_sparks.mesh = q
	_sparks.material_override = PowerFx.additive_billboard()
	_sparks.emitting = false
	add_child(_sparks)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.6, 0.25)
	_light.omni_range = 5.0
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	_light.position = Vector3(0, 1.1, 0)
	add_child(_light)
	visible = false


## `charging`: ¿se mantiene la carga?; `fill` 0..1: qué tan llena está la barra (la aura crece con ella).
func set_state(charging: bool, fill: float) -> void:
	_target = (0.45 + 0.55 * clampf(fill, 0.0, 1.0)) if charging else 0.0


## Destello breve (barra llena al cargar).
func pulse() -> void:
	_boost = 1.0


func update(delta: float) -> void:
	_t += delta
	power = move_toward(power, _target, delta * (2.6 if _target > power else 3.5))
	_boost = maxf(0.0, _boost - delta * 2.5)
	var p := power * (1.0 + 0.5 * _boost) * (0.92 + 0.08 * sin(_t * 17.0))
	var on := power > 0.01
	visible = on
	_sparks.emitting = _target > 0.0
	if not on:
		return
	for m in _layers:
		m.set_shader_parameter("power", p)
	_ring_mat.set_shader_parameter("power", p)
	_light.light_energy = 1.4 * p
