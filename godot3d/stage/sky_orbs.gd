class_name SkyOrbs
extends Node3D
## Esferas de energía que flotan en el fondo del cielo, tan grandes y tan cerca que parecen planetas. Están a una
## distancia fija y siguen al jugador, así que se comportan como cielo (no hay forma de acercarse a ellas).
## Cada una: impostor de esfera con plasma (energy_orb.gdshader, un círculo perfecto en cualquier parte de la
## pantalla) + resplandor (orb_halo.gdshader). Todo procedural.

const ENERGY_SHADER := preload("res://stage/shaders/energy_orb.gdshader")
const HALO_SHADER := preload("res://stage/shaders/orb_halo.gdshader")

const DIST := 240.0
## [azimut° (0 = -Z, + = derecha), elevación°, radio angular°, color A, color B]
const SPECS := [
	[-34.0, 15.0, 10.0, Color(0.30, 0.85, 0.90), Color(0.55, 0.35, 0.95)],    # el "planeta" cercano: cian y violeta
	[38.0, 11.0, 3.6, Color(1.00, 0.72, 0.45), Color(0.95, 0.40, 0.55)],      # ámbar y rosa
	[118.0, 20.0, 6.5, Color(0.65, 0.55, 1.00), Color(0.35, 0.75, 1.00)],     # lila y azul
	[-125.0, 10.0, 4.5, Color(0.50, 0.95, 0.80), Color(0.95, 0.90, 0.55)],    # menta y dorado
	[175.0, 30.0, 2.8, Color(1.00, 0.85, 0.55), Color(1.00, 0.55, 0.35)],
	[78.0, 35.0, 3.4, Color(0.95, 0.55, 0.80), Color(0.60, 0.50, 1.00)],
]

var _orbs: Array[Node3D] = []
var _t := 0.0


## Dirección (unitaria) hacia el centro de la esfera i.
static func direction(i: int) -> Vector3:
	var az := deg_to_rad(float(SPECS[i][0]))
	var el := deg_to_rad(float(SPECS[i][1]))
	return Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))


func _ready() -> void:
	name = "SkyOrbs"
	var noise := FxTex.noise()
	for i in SPECS.size():
		var sp: Array = SPECS[i]
		var rad := DIST * tan(deg_to_rad(float(sp[2])))
		var holder := Node3D.new()
		holder.name = "Orb%d" % i
		holder.position = direction(i) * DIST
		add_child(holder)
		var body := MeshInstance3D.new()
		var bq := QuadMesh.new()
		bq.size = Vector2.ONE * rad * 2.0
		body.mesh = bq
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := ShaderMaterial.new()
		m.shader = ENERGY_SHADER
		m.set_shader_parameter("noise_tex", noise)
		m.set_shader_parameter("col_a", sp[3])
		m.set_shader_parameter("col_b", sp[4])
		m.set_shader_parameter("speed", 0.012 + 0.006 * float(i % 3))
		m.set_shader_parameter("seed", Vector2(0.37 * float(i), 0.61 * float(i)))
		body.material_override = m
		holder.add_child(body)
		var halo := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2.ONE * rad * 5.0
		halo.mesh = qm
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var hm := ShaderMaterial.new()
		hm.shader = HALO_SHADER
		hm.set_shader_parameter("col", (sp[3] as Color).lerp(sp[4], 0.4))
		hm.set_shader_parameter("intensity", 0.45 if i == 0 else 0.6)
		hm.render_priority = -1
		halo.material_override = hm
		holder.add_child(halo)
		_orbs.append(holder)


## Cada frame: se queda centrado en el jugador (como un cielo) y respira suavemente.
func tick(delta: float, target: Node3D) -> void:
	_t += delta
	if is_instance_valid(target):
		global_position = target.global_position
	for i in _orbs.size():
		var base := direction(i) * DIST
		var bob := sin(_t * 0.18 + float(i) * 1.7) * 0.012
		_orbs[i].position = base + Vector3.UP * (bob * DIST)
		_orbs[i].scale = Vector3.ONE * (1.0 + 0.012 * sin(_t * 0.31 + float(i) * 2.3))
