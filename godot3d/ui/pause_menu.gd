class_name PauseMenu
extends CanvasLayer
## Panel de pausa: congela el juego (get_tree().paused) y deja gastar puntos de mejora en cada habilidad.
## Pestaña HABILIDADES: lista (bola de fuego, ki), rango, las 5 etapas de color, números de ahora → siguiente rango y el botón
## MEJORAR (1 punto). Pestaña PRUEBAS: atajos temporales para ver niveles, vida y los portales de cada etapa de la historia.
## Se abre con el botón PAUSA / MEJORA (táctil), P, Esc o Start; UiLock.blocked mientras está abierto.

signal opened
signal closed

const AMBER := Color(1.0, 0.72, 0.3)
const GOLD := Color(0.96, 0.84, 0.56)
const STAGE_NAMES := ["Piedra", "Celestial", "Dorado"]

var book: SpellBook
var progress: Progress
var vitals: Vitals
var touch: TouchControls
var is_open := false
var tab := 0
var selected := "fireball"

var _root: Control
var _title_right: Label
var _tab_btns: Array[Button] = []
var _list_btns := {}
var _detail: VBoxContainer
var _tests: VBoxContainer
var _upgrade_btn: Button
var _tier_row: TierRow
var _grid: GridContainer
var _head: Label
var _hint: Label
var _stage_btn: Button


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false


func setup(b: SpellBook, p: Progress, v: Vitals, t: TouchControls) -> void:
	book = b
	progress = p
	vitals = v
	touch = t


func _style(bg: Color, border: Color, bw := 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(8)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


func _button(text: String, font_size := 20, min_h := 60.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, min_h)
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", Color(0.95, 0.93, 0.9))
	b.add_theme_color_override("font_disabled_color", Color(0.5, 0.48, 0.46))
	b.add_theme_stylebox_override("normal", _style(Color(0.1, 0.09, 0.12, 0.95), Color(AMBER, 0.5)))
	b.add_theme_stylebox_override("hover", _style(Color(0.16, 0.13, 0.12, 0.95), AMBER))
	b.add_theme_stylebox_override("pressed", _style(Color(0.25, 0.18, 0.1, 0.95), AMBER))
	b.add_theme_stylebox_override("disabled", _style(Color(0.07, 0.07, 0.08, 0.9), Color(0.3, 0.28, 0.26, 0.5)))
	b.focus_mode = Control.FOCUS_NONE
	return b


## Marca un botón como "seleccionado": relleno dorado y texto claro (no parece desactivado).
func _marcar(b: Button, activo: bool) -> void:
	b.disabled = false
	if activo:
		var st := _style(Color(0.34, 0.24, 0.1, 0.98), GOLD, 3)
		b.add_theme_stylebox_override("normal", st)
		b.add_theme_stylebox_override("hover", st)
		b.add_theme_stylebox_override("pressed", st)
		b.add_theme_color_override("font_color", GOLD)
	else:
		b.add_theme_stylebox_override("normal", _style(Color(0.1, 0.09, 0.12, 0.95), Color(AMBER, 0.5)))
		b.add_theme_stylebox_override("hover", _style(Color(0.16, 0.13, 0.12, 0.95), AMBER))
		b.add_theme_stylebox_override("pressed", _style(Color(0.25, 0.18, 0.1, 0.95), AMBER))
		b.add_theme_color_override("font_color", Color(0.95, 0.93, 0.9))


func _label(text: String, size := 18, col := Color(0.92, 0.9, 0.88)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.01, 0.03, 0.95)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	_root.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	var head := HBoxContainer.new()
	col.add_child(head)
	head.add_child(_label("PAUSA", 34, GOLD))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	_title_right = _label("", 22, Color(0.74, 0.8, 0.95))
	head.add_child(_title_right)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	col.add_child(tabs)
	for i in 2:
		var tb := _button(["HABILIDADES", "PRUEBAS"][i], 20, 52.0)
		tb.custom_minimum_size.x = 230
		tb.pressed.connect(show_tab.bind(i))
		tabs.add_child(tb)
		_tab_btns.append(tb)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 22)
	col.add_child(body)
	# lista de habilidades (izquierda)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	list.custom_minimum_size.x = 290
	body.add_child(list)
	for id in Abilities.IDS:
		var b := _button(Abilities.ability_name(id), 22, 74.0)
		b.pressed.connect(select.bind(id))
		list.add_child(b)
		_list_btns[id] = b
	# detalle (derecha)
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 10)
	body.add_child(_detail)
	_head = _label("", 28, GOLD)
	_detail.add_child(_head)
	_tier_row = TierRow.new()
	_tier_row.custom_minimum_size = Vector2(0, 92)
	_detail.add_child(_tier_row)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 34)
	_grid.add_theme_constant_override("v_separation", 6)
	_detail.add_child(_grid)
	_hint = _label("", 17, Color(0.7, 0.68, 0.66))
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(_hint)
	_upgrade_btn = _button("MEJORAR", 24, 70.0)
	_upgrade_btn.pressed.connect(_on_upgrade)
	_detail.add_child(_upgrade_btn)
	# pruebas
	_tests = VBoxContainer.new()
	_tests.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tests.add_theme_constant_override("separation", 8)
	body.add_child(_tests)
	_tests.add_child(_label("Atajos de prueba (se quitarán al terminar el juego)", 17, Color(0.7, 0.68, 0.66)))
	var rows := [
		["Nivel +1", func() -> void: progress.set_level(progress.level + 1)],
		["Nivel −1", func() -> void: progress.set_level(progress.level - 1)],
		["+1 punto de mejora", func() -> void: progress.add_points(1)],
		["Vida −20", func() -> void: vitals.take_damage(20.0)],
		["Curar toda la vida", func() -> void: vitals.heal(vitals.max_hp)],
	]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	_tests.add_child(grid)
	for r in rows:
		var tb := _button(r[0], 19, 56.0)
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.pressed.connect(func() -> void:
			(r[1] as Callable).call()
			refresh())
		grid.add_child(tb)
	_stage_btn = _button("", 19, 56.0)
	_stage_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage_btn.pressed.connect(_cycle_stage)
	grid.add_child(_stage_btn)
	_tests.add_child(_label("El portal nuevo (PUERTA o la rueda) usa la etapa elegida: piedra, celestial o dorado.", 16, Color(0.6, 0.58, 0.56)))

	var foot := HBoxContainer.new()
	col.add_child(foot)
	var cont := _button("CONTINUAR", 24, 64.0)
	cont.custom_minimum_size.x = 300
	cont.pressed.connect(close)
	foot.add_child(cont)


func show_tab(i: int) -> void:
	tab = i
	refresh()


func select(id: String) -> void:
	selected = id
	refresh()


func _cycle_stage() -> void:
	var st: Node = get_tree().get_first_node_in_group("story")
	var n := (Portal.style_index + 1) % 3
	if st and st.has_method("set_stage"):
		st.call("set_stage", n)
	else:
		Portal.style_index = n
	refresh()


func _on_upgrade() -> void:
	if book and book.upgrade(selected):
		refresh()


func refresh() -> void:
	if progress == null:
		return
	_title_right.text = "NIVEL %d    ·    PUNTOS %d" % [progress.level, progress.points]
	for i in _tab_btns.size():
		_marcar(_tab_btns[i], i == tab)
	for id in _list_btns:
		_marcar(_list_btns[id] as Button, tab == 0 and id == selected)
		(_list_btns[id] as Button).visible = tab == 0
	_detail.visible = tab == 0
	_tests.visible = tab == 1
	_stage_btn.text = "Portal: %s" % STAGE_NAMES[Portal.style_index]
	if tab != 0:
		return
	var rank := book.rank(selected)
	_head.text = "%s     rango %d / %d" % [Abilities.ability_name(selected), rank, Abilities.MAX_RANK]
	_tier_row.set_data(selected, rank)
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	var now := Abilities.stat_rows(selected, rank)
	var nxt := Abilities.stat_rows(selected, mini(rank + 1, Abilities.MAX_RANK))
	for i in now.size():
		_grid.add_child(_label(String(now[i][0]), 19, Color(0.75, 0.73, 0.7)))
		_grid.add_child(_label(String(now[i][1]), 19))
		var better: bool = rank < Abilities.MAX_RANK and nxt[i][1] != now[i][1]
		_grid.add_child(_label(("→  " + String(nxt[i][1])) if better else "", 19, Color(0.55, 0.9, 0.55)))
	match selected:
		"fireball":
			_hint.text = "Más rango: más daño, explosión y empuje, y la barra de magia llega más alto. Cada 2 rangos cambia el color de las llamas: naranja, roja, azul, morada y, al final, morada con negro."
		_:
			_hint.text = "Más rango: la carga de ki es más rápida y el aura crece. Cada 2 rangos cambia el color: blanco, amarillo, rojo, morado y, al final, morado con negro."
	if rank >= Abilities.MAX_RANK:
		_upgrade_btn.text = "RANGO MÁXIMO"
		_upgrade_btn.disabled = true
	else:
		_upgrade_btn.text = "MEJORAR  (%d punto)" % Abilities.POINT_COST if progress.points >= Abilities.POINT_COST else "SIN PUNTOS  (sube de nivel)"
		_upgrade_btn.disabled = progress.points < Abilities.POINT_COST


func open(first_tab := 0) -> bool:
	if is_open or UiLock.blocked or book == null:
		return false
	is_open = true
	UiLock.blocked = true
	tab = first_tab
	if touch:
		touch.cancel_all()
	visible = true
	get_tree().paused = true
	refresh()
	opened.emit()
	return true


func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	UiLock.blocked = false
	get_tree().paused = false
	closed.emit()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not event.is_echo():
		if is_open:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()


## Fila con las 5 etapas de color de una habilidad: la actual resaltada, las siguientes apagadas.
class TierRow extends Control:
	var _id := "fireball"
	var _rank := 0

	func set_data(id: String, rank: int) -> void:
		_id = id
		_rank = rank
		queue_redraw()

	func _draw() -> void:
		var n := Abilities.tier_count(_id)
		var font := ThemeDB.fallback_font
		var cur := Abilities.tier_of_rank(_rank)
		var cw := size.x / float(n)
		for i in n:
			var t := Abilities.tier(_id, i * 2)
			var c := Vector2(cw * (float(i) + 0.5), 32)
			var on := i <= cur
			var a := 1.0 if on else 0.28
			draw_circle(c, 27, Color(0, 0, 0, 0.6))
			var edge: Color = t.edge
			if t.get("dark", false):
				edge = Color(0.1, 0.0, 0.18)
			draw_circle(c, 24, Color(t.glow, 0.35 * a))
			draw_circle(c, 18, Color(edge, a))
			draw_circle(c, 9, Color(t.core, a))
			if i == cur:
				draw_arc(c, 28, 0, TAU, 32, Color(1.0, 0.72, 0.3), 3.0)
			var w := font.get_string_size(String(t.name), HORIZONTAL_ALIGNMENT_CENTER, -1, 15).x
			draw_string(font, Vector2(c.x - w * 0.5, 80), String(t.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.95 if i == cur else (0.6 if on else 0.3)))
