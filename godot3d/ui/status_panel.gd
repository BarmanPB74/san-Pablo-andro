class_name StatusPanel
extends Control
## Panel de estado estilo GTA San Andreas (arriba a la izquierda): icono del poder activo y, a su lado, la barra de VIDA,
## la barra de MAGIA del poder (con su tope, marcas de costo y el color de su rango) y el NIVEL con su experiencia.
## El icono es también un botón táctil (TouchControls, acción "power_panel") que abre el selector de poderes.

const W := 236.0

var book: SpellBook
var progress: Progress
var vitals: Vitals
var caster: PowerCaster
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(W + 90.0, 100.0)
	size = custom_minimum_size


func setup(b: SpellBook, p: Progress, v: Vitals, c: PowerCaster) -> void:
	book = b
	progress = p
	vitals = v
	caster = c
	b.changed.connect(func(_id: String) -> void: queue_redraw())
	p.xp_changed.connect(func(_a: int, _b: int) -> void: queue_redraw())
	p.points_changed.connect(func(_a: int) -> void: queue_redraw())
	v.changed.connect(func(_a: float, _b: float) -> void: queue_redraw())
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if progress and progress.points > 0:
		queue_redraw()                  # el aviso de mejora palpita


## Centro del icono del poder (para colocar el botón táctil encima), en coordenadas de pantalla.
func icon_center() -> Vector2:
	return global_position + Vector2(38, 40)


func _bar(r: Rect2, frac: float, col: Color, text: String, font: Font) -> void:
	draw_rect(r.grow(2.0), Color(0, 0, 0, 0.6))
	draw_rect(r, Color(0.07, 0.05, 0.06, 0.88))
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(frac, 0.0, 1.0), r.size.y)), col)
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(frac, 0.0, 1.0), r.size.y * 0.4)), Color(1, 1, 1, 0.2))
	draw_rect(r, Color(1.0, 0.72, 0.3, 0.5), false, 1.5)
	draw_string_outline(font, Vector2(r.position.x + 5, r.end.y - 3), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(0, 0, 0, 0.9))
	draw_string(font, Vector2(r.position.x + 5, r.end.y - 3), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.95))


func _draw() -> void:
	if book == null or progress == null or vitals == null:
		return
	var font := ThemeDB.fallback_font
	var amber := Color(1.0, 0.72, 0.3)
	var id := caster.active if caster else "fireball"
	var tier := Abilities.tier(id, book.rank(id))
	# icono del poder activo: disco, aro ámbar y llama del color de su rango
	var c := Vector2(38, 40)
	draw_circle(c, 34, Color(0, 0, 0, 0.6))
	draw_arc(c, 34, 0, TAU, 40, Color(amber, 0.9), 3.0)
	draw_circle(c, 17, Color(tier.glow, 0.25))
	_flame(c, 24.0, tier)
	# vida
	var x0 := 84.0
	_bar(Rect2(x0, 12, W, 16), vitals.fraction(), Color(0.78, 0.12, 0.14), "VIDA %d" % int(ceil(vitals.hp)), font)
	# magia: relleno con el color del rango; sobre el tope, rayas
	var mr := Rect2(x0, 38, W, 16)
	var cap := book.cap(id)
	var v := book.value(id)
	draw_rect(mr.grow(2.0), Color(0, 0, 0, 0.6))
	draw_rect(mr, Color(0.07, 0.05, 0.06, 0.88))
	var lock_x := mr.position.x + W * cap
	var x := lock_x
	while x < mr.end.x:
		var x2 := minf(x + 16.0, mr.end.x)
		draw_line(Vector2(x, mr.end.y), Vector2(x2, mr.end.y - (x2 - x)), Color(0.3, 0.26, 0.26, 0.5), 2.0)
		x += 8.0
	var edge: Color = tier.glow
	var body := edge if v < cap - 0.001 else Color(tier.core).lerp(edge, 0.35)
	draw_rect(Rect2(mr.position, Vector2(W * v, mr.size.y)), body)
	draw_rect(Rect2(mr.position, Vector2(W * v, mr.size.y * 0.4)), Color(1, 1, 1, 0.22))
	var m := book.cost(id)
	while m < 1.0:
		var mx := mr.position.x + W * m
		draw_line(Vector2(mx, mr.position.y), Vector2(mx, mr.end.y), Color(0, 0, 0, 0.55), 1.2)
		m += book.cost(id)
	draw_line(Vector2(lock_x, mr.position.y - 3.0), Vector2(lock_x, mr.end.y + 3.0), Color(amber, 0.95), 2.0)
	draw_rect(mr, Color(amber, 0.5), false, 1.5)
	var tx := "MAGIA %d%%" % int(round(v * 100.0))
	draw_string_outline(font, Vector2(mr.position.x + 5, mr.end.y - 3), tx, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(0, 0, 0, 0.9))
	draw_string(font, Vector2(mr.position.x + 5, mr.end.y - 3), tx, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.95))
	# nivel y experiencia
	var lv := "NIVEL %d" % progress.level
	draw_string_outline(font, Vector2(x0, 76), lv, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 5, Color(0, 0, 0, 0.9))
	draw_string(font, Vector2(x0, 76), lv, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.74, 0.8, 0.95))
	var xr := Rect2(x0 + 84, 66, W - 84, 5)
	draw_rect(xr, Color(0, 0, 0, 0.55))
	if progress.level < Progress.MAX_LEVEL:
		var need := Progress.xp_needed(progress.level)
		draw_rect(Rect2(xr.position, Vector2(xr.size.x * clampf(float(progress.xp) / float(need), 0.0, 1.0), xr.size.y)), Color(0.55, 0.68, 0.95, 0.9))
	else:
		draw_rect(xr, Color(0.74, 0.8, 0.95, 0.9))
	if progress.points > 0:
		var pt := "MEJORA +%d  (PAUSA)" % progress.points
		var a := 0.7 + 0.3 * sin(_t * 5.0)
		draw_string_outline(font, Vector2(x0, 94), pt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 5, Color(0, 0, 0, 0.9))
		draw_string(font, Vector2(x0, 94), pt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(amber, a))


## Llama estilizada (gota) de ancho `s` con el borde y el centro de la etapa.
func _flame(c: Vector2, s: float, tier: Dictionary) -> void:
	var edge: Color = tier.edge
	if tier.get("dark", false):
		edge = Color(0.1, 0.0, 0.18)
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in 24:
		var a := TAU * float(i) / 24.0
		var k := 1.0 + 0.55 * maxf(0.0, -sin(a))          # alarga hacia arriba
		var wob := 1.0 + 0.1 * sin(a * 3.0)
		outer.append(c + Vector2(cos(a) * s * 0.5 * wob, sin(a) * s * 0.5 * k * 0.9 + s * 0.05))
		inner.append(c + Vector2(cos(a) * s * 0.26, sin(a) * s * 0.26 * k * 0.9 + s * 0.12))
	draw_colored_polygon(outer, Color(edge, 0.95))
	draw_colored_polygon(inner, Color(tier.core, 0.98))
