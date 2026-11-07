class_name RainFX
extends Node3D
## Lluvia que sigue a la cámara activa: gotas (streaks) + salpicaduras en el piso.
## GPUParticles3D (funciona en Mobile y Compatibility). La intensidad usa
## amount_ratio, así cambiarla no reinicia el sistema de partículas.

@export var max_drops := 3500
@export var max_splashes := 500
@export var area := Vector3(34.0, 20.0, 34.0)   # caja de emisión alrededor de la cámara
@export var fall_speed := 17.0
@export var wind := Vector3(1.5, 0.0, 0.6)
@export var splashes_enabled := true
@export var splash_radius := 12.0
@export var ground_mask := 1                    # capa "world"

var intensity := 0.0
var drops: GPUParticles3D
var splashes: GPUParticles3D
var _ground_y := 0.0
var _ray_timer := 0.0


func _ready() -> void:
	top_level = true
	drops = _make_drops()
	add_child(drops)
	splashes = _make_splashes()
	add_child(splashes)
	set_intensity(intensity)


## v: 0 (apagada) .. 1 (aguacero). Valores intermedios = llovizna.
func set_intensity(v: float) -> void:
	intensity = clampf(v, 0.0, 1.0)
	if drops == null:
		return
	var on := intensity > 0.001
	visible = on
	set_process(on)
	drops.emitting = on
	drops.amount_ratio = maxf(intensity, 0.01)
	splashes.emitting = on and splashes_enabled
	splashes.amount_ratio = maxf(intensity, 0.01)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	if fwd.length_squared() > 0.001:
		fwd = fwd.normalized()
	# el centro va un poco por delante de la cámara: más gotas en pantalla
	var center := cp + fwd * area.z * 0.25
	drops.global_position = Vector3(center.x, cp.y + area.y * 0.45, center.z) - wind * 0.4
	_ray_timer -= delta
	if _ray_timer <= 0.0:
		_ray_timer = 0.25
		_probe_ground(cp)
	splashes.global_position = Vector3(cp.x + fwd.x * splash_radius * 0.5, _ground_y + 0.04,
		cp.z + fwd.z * splash_radius * 0.5)


func _probe_ground(from: Vector3) -> void:
	var w := get_world_3d()
	if w == null:
		return
	var q := PhysicsRayQueryParameters3D.create(from + Vector3.UP, from + Vector3.DOWN * 50.0, ground_mask)
	var hit := w.direct_space_state.intersect_ray(q)
	if hit.has("position"):
		_ground_y = (hit["position"] as Vector3).y


func _make_drops() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Drops"
	p.amount = max_drops
	p.lifetime = area.y / fall_speed
	p.preprocess = p.lifetime
	p.local_coords = false
	p.fixed_fps = 30
	p.interpolate = true
	p.visibility_aabb = AABB(-area * 0.75, area * 1.5)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(area.x * 0.5, 1.0, area.z * 0.5)
	var dir := (Vector3.DOWN * fall_speed + wind).normalized()
	pm.direction = dir
	pm.spread = 2.0
	pm.initial_velocity_min = fall_speed * 0.9
	pm.initial_velocity_max = fall_speed * 1.1
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.012, 0.5)
	q.material = Palette.rain_drop()
	p.draw_pass_1 = q
	return p


func _make_splashes() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Splashes"
	p.amount = max_splashes
	p.lifetime = 0.3
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-splash_radius, -1, -splash_radius), Vector3(splash_radius * 2, 2, splash_radius * 2))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(splash_radius, 0.01, splash_radius)
	pm.direction = Vector3.UP
	pm.spread = 25.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.0
	pm.gravity = Vector3(0, -9.8, 0)
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.25))
	sc.add_point(Vector2(1.0, 1.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.8))
	g.set_color(1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.06)
	q.material = Palette.rain_splash()
	p.draw_pass_1 = q
	return p
