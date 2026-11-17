class_name MagicBar
extends Control
## Barra de magia del hechizo activo (bola de fuego) + nivel de Andro y puntos de mejora.
## La parte de la barra por encima del tope actual se ve oscura y rayada (aún bloqueada); las marcas indican lo que cuesta
## cada lanzamiento. Con puntos disponibles aparece "MEJORA +N" (botón táctil o tecla U).

const SPELL := "fireball"
const W := 270.0
const H := 20.0

var book: SpellBook
var progress: Progress
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(W + 8.0, 78.0)
	size = custom_minimum_size


func setup(b: SpellBook, p: Progress) -> void:
	book = b
	progress = p
	b.changed.connect(func(_id: String) -> void: queue_redraw())
	p.xp_changed.connect(func(_a: int, _b: int) -> void: queue_redraw())
	p.points_changed.connect(func(_a: int) -> void: queue_redraw())
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if book and progress and progress.points > 0:
		queue_redraw()                  # el aviso de mejora palpita


func _draw() -> void:
	if book == null or progress == null:
		return
	var font := ThemeDB.fallback_font
	var amber := Color(1.0, 0.72, 0.3)
	# título: nombre del hechizo y nivel
	var title := "%s" % book.spell_name(SPELL)
	draw_string_outline(font, Vector2(0, 14), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 5, Color(0, 0, 0, 0.9))
	draw_string(font, Vector2(0, 14), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.96, 0.84, 0.56))
	var lv := "NIVEL %d" % progress.level
	var lw := font.get_string_size(lv, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	draw_string_outline(font, Vector2(W - lw, 14), lv, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 5, Color(0, 0, 0, 0.9))
	draw_string(font, Vector2(W - lw, 14), lv, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.74, 0.8, 0.95))
	# barra
	var r := Rect2(0, 22, W, H)
	draw_rect(r.grow(2.0), Color(0, 0, 0, 0.6))
	draw_rect(r, Color(0.07, 0.05, 0.05, 0.85))
	var cap := book.cap(SPELL)
	var v := book.value(SPELL)
	# zona aún bloqueada (sobre el tope): rayas oscuras
	var lock_x := r.position.x + W * cap
	var x := lock_x
	while x < r.end.x:
		var x2 := minf(x + H, r.end.x)
		draw_line(Vector2(x, r.end.y), Vector2(x2, r.end.y - (x2 - x)), Color(0.3, 0.26, 0.26, 0.5), 2.0)
		x += 9.0
	# relleno: ámbar con brillo arriba; blanco-dorado si está llena
	var fw := W * v
	var full := v >= cap - 0.001
	var body := Color(1.0, 0.55, 0.14) if not full else Color(1.0, 0.8, 0.38)
	draw_rect(Rect2(r.position, Vector2(fw, H)), body)
	draw_rect(Rect2(r.position, Vector2(fw, H * 0.4)), Color(1, 1, 1, 0.22))
	# marcas de costo cada lanzamiento
	var cost := book.cost(SPELL)
	var m := cost
	while m < 1.0:
		var mx := r.position.x + W * m
		draw_line(Vector2(mx, r.position.y), Vector2(mx, r.end.y), Color(0, 0, 0, 0.55), 1.5)
		m += cost
	# tope actual
	draw_line(Vector2(lock_x, r.position.y - 3.0), Vector2(lock_x, r.end.y + 3.0), Color(amber, 0.95), 2.0)
	draw_rect(r, Color(amber, 0.55), false, 2.0)
	var pct := "%d%%" % int(round(v * 100.0))
	draw_string_outline(font, Vector2(6, r.end.y - 4), pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.9))
	draw_string(font, Vector2(6, r.end.y - 4), pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.95))
	# experiencia hasta el siguiente nivel
	var need := Progress.xp_needed(mini(progress.level, Progress.MAX_LEVEL - 1))
	var xr := Rect2(0, r.end.y + 8.0, W, 5.0)
	draw_rect(xr, Color(0, 0, 0, 0.55))
	if progress.level < Progress.MAX_LEVEL:
		draw_rect(Rect2(xr.position, Vector2(W * clampf(float(progress.xp) / float(need), 0.0, 1.0), xr.size.y)), Color(0.55, 0.68, 0.95, 0.9))
	else:
		draw_rect(xr, Color(0.74, 0.8, 0.95, 0.9))
	# puntos de mejora
	if progress.points > 0:
		var tx := "MEJORA +%d  (U / botón)" % progress.points
		var a := 0.7 + 0.3 * sin(_t * 5.0)
		draw_string_outline(font, Vector2(0, xr.end.y + 18.0), tx, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 5, Color(0, 0, 0, 0.9))
		draw_string(font, Vector2(0, xr.end.y + 18.0), tx, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(amber, a))
