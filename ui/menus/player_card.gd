class_name PlayerCard
extends PanelContainer
## Tarjeta de un jugador en el menú: su surfista girando, los íconos de lo que
## se puede cambiar abajo y, al entrar a una categoría, sus opciones.
##
## Cada tarjeta la maneja un solo dispositivo (el teclado o un mando), el que
## se unió en ella. Con el mando / teclado:
##   - izquierda / derecha: moverse entre los íconos;
##   - A / ESPACIO: entrar a la categoría. Adentro, izquierda / derecha cambia
##     la opción y arriba / abajo pasa a la otra fila (por ejemplo, el color);
##   - B / ESC: volver a los íconos;
##   - Start / ENTER: listo (otra vez: no listo);
##   - Y / R: personaje al azar;
##   - Select / C (o el botón): copia el personaje al portapapeles (para
##     pasarlo y guardarlo como estilo armado).

signal ready_changed
## Se tocó "unirse" con el mouse (el menú lo une con el teclado).
signal join_clicked

const YELLOW := Palette.BUTTER
## Categorías en el orden de los íconos. Cada una: [nombre, encuadre de la foto].
const ICONS := [
	["Estilos", ThumbRenderer.Frame.BODY],
	["Cuerpo", ThumbRenderer.Frame.BODY],
	["Piel", ThumbRenderer.Frame.HEAD],
	["Pelo", ThumbRenderer.Frame.HEAD],
	["Cara", ThumbRenderer.Frame.HEAD],
	["Accesorios", ThumbRenderer.Frame.CHEST],
	["Ropa", ThumbRenderer.Frame.HIPS],
	["Tabla", ThumbRenderer.Frame.BOARD],
]
## Paso de las barras (panza, músculos, cabeza).
const SLIDER_STEP := 0.1

## Jugador (0..3) de esta tarjeta.
var index: int = 0
## Dispositivo que la maneja: -1 = libre, InputSetup.KEYBOARD o el id de un mando.
var device: int = -1
## Ícono elegido (índice en ICONS).
var cat_index: int = 0
## true adentro de una categoría (cambiando opciones).
var in_category: bool = false
## Fila dentro de la categoría (por ejemplo: peinado / color de pelo).
var row: int = 0
var is_ready: bool = false
## Estilo armado elegido en "Estilos" (-1 = a gusto).
var preset: int = -1
## Las 3-4 tarjetas van más chicas (íconos en dos filas).
var compact: bool = false
var thumbs: ThumbRenderer

var _view: SubViewportContainer
var _avatar: Avatar
var _pivot: Node3D
var _board: Node3D
var _cam: Camera3D
var _zoom: float = 0.0
var _title: Label
var _status: Label
var _editor: VBoxContainer
var _icons: Array[Button] = []
var _icon_marks: Array[CategoryIcon] = []
var _style: StyleBoxFlat
var _rng := RandomNumberGenerator.new()
var _export_button: Button
## Tiempo que queda del aviso "copiado".
var _copied_time: float = 0.0


func _ready() -> void:
	_rng.randomize()
	_build()


func data() -> CharacterData:
	return GameSettings.character_for(index)


func joined() -> bool:
	return device != -1


# ---------------------------------------------------------------- armado

func _build() -> void:
	_style = StyleBoxFlat.new()
	_style.set_corner_radius_all(16)
	_style.set_border_width_all(4)
	_style.set_content_margin_all(8)
	add_theme_stylebox_override("panel", _style)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)

	_title = _label("", 26, YELLOW)
	box.add_child(_title)

	# Vista previa.
	var view := SubViewportContainer.new()
	_view = view
	view.stretch = true
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.custom_minimum_size = Vector2(160.0, 150.0)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(view)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	view.add_child(vp)
	_pivot = Node3D.new()
	vp.add_child(_pivot)
	_avatar = Avatar.new()
	_avatar.data = data()
	_pivot.add_child(_avatar)
	_board = Node3D.new()
	_pivot.add_child(_board)
	_cam = Camera3D.new()
	_cam.fov = 34.0
	vp.add_child(_cam)
	_cam.current = true
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.9, 1.0)
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.5, 0.0)
	vp.add_child(sun)
	_rebuild_board()

	# Opciones de la categoría (o la ayuda).
	_editor = VBoxContainer.new()
	_editor.add_theme_constant_override("separation", 2)
	_editor.custom_minimum_size.y = 118.0
	box.add_child(_editor)

	# Íconos de lo que se puede cambiar.
	var grid := GridContainer.new()
	grid.columns = 4 if compact else ICONS.size()
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	box.add_child(grid)
	for i in ICONS.size():
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(46.0, 46.0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = ICONS[i][0]
		# Silueta minimalista, sin texto.
		var mark := CategoryIcon.new()
		mark.kind = i as CategoryIcon.Kind
		mark.set_anchors_preset(Control.PRESET_FULL_RECT)
		mark.offset_left = 6.0
		mark.offset_right = -6.0
		mark.offset_top = 6.0
		mark.offset_bottom = -6.0
		b.add_child(mark)
		_icon_marks.append(mark)
		var at := i
		b.pressed.connect(func() -> void: _click_icon(at))
		grid.add_child(b)
		_icons.append(b)

	# Exportar: copia los datos del personaje (para guardarlo como estilo).
	_export_button = Button.new()
	_export_button.text = "Exportar personaje"
	_export_button.focus_mode = Control.FOCUS_NONE
	_export_button.add_theme_font_size_override("font_size", 14)
	_export_button.pressed.connect(export_character)
	box.add_child(_export_button)

	_status = _label("", 16, Color.WHITE)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	# Con el mouse: tocar el texto de abajo une (con el teclado) o marca listo.
	_status.mouse_filter = Control.MOUSE_FILTER_STOP
	_status.gui_input.connect(func(ev: InputEvent) -> void:
		var mb := ev as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if not joined():
				join_clicked.emit()
			elif not in_category:
				toggle_ready()
	)
	refresh()


# ---------------------------------------------------------------- acciones

## Se une el dispositivo `dev` a esta tarjeta.
func join(dev: int) -> void:
	device = dev
	is_ready = false
	in_category = false
	refresh()


func leave() -> void:
	device = -1
	is_ready = false
	in_category = false
	refresh()


## Mueve en la dirección (x: izquierda/derecha, y: arriba/abajo).
func move(dir: Vector2i) -> void:
	if is_ready:
		return
	if not in_category:
		if dir.x != 0:
			cat_index = posmod(cat_index + dir.x, ICONS.size())
		elif dir.y != 0 and compact:
			cat_index = posmod(cat_index + dir.y * 4, ICONS.size())
	else:
		var rows := category_rows()
		if dir.y != 0:
			row = posmod(row + dir.y, rows.size())
		elif dir.x != 0:
			change(rows[row], dir.x)
	refresh()


func accept() -> void:
	if is_ready:
		return
	if not in_category:
		in_category = true
		row = 0
	refresh()


## Vuelve atrás. Devuelve false si ya estaba afuera (el menú decide qué hacer).
func back() -> bool:
	if is_ready:
		toggle_ready()
		return true
	if in_category:
		in_category = false
		refresh()
		return true
	return false


func toggle_ready() -> void:
	if not joined():
		return
	is_ready = not is_ready
	in_category = false
	refresh()
	ready_changed.emit()


func randomize_character() -> void:
	if is_ready:
		return
	var r := CharacterData.random(_rng)
	for prop in CharacterData.SLIDERS.values():
		data().set(prop, r.get(prop))
	for f in CharacterData.FIELDS:
		data().set(CharacterData.FIELDS[f][0], r.get_option(f))
	preset = -1
	_changed()


## Copia los datos del personaje al portapapeles.
func export_character() -> void:
	if not joined():
		return
	var text := data().export_text()
	DisplayServer.clipboard_set(text)
	print("Personaje J%d: %s" % [index + 1, text])
	_copied_time = 2.5
	refresh()


## Filas de la categoría elegida: [título, tipo, campo, encuadre de la foto].
## Las que no tienen sentido con lo elegido (el color del gorro de paja, el del
## estampado si el short es liso) no se muestran.
func category_rows() -> Array:
	var out := []
	for section in CharacterSelect.CATEGORIES[ICONS[cat_index][0]]:
		var field: String = section[2]
		if field != "" and CharacterData.FIELDS.has(field) and not data().field_applies(field):
			continue
		out.append([section[0], section[1], section[2], section[3]])
	return out


## Cambia el valor de la fila `r` un paso (step = -1 o 1).
func change(r: Array, step: int) -> void:
	var kind: String = r[1]
	var field: String = r[2]
	match kind:
		"preset":
			preset = posmod(preset + step, CharacterData.PRESET_NAMES.size()) if preset >= 0 else (0 if step > 0 else CharacterData.PRESET_NAMES.size() - 1)
			data().apply_preset(preset)
		"slider":
			data().set(field, clampf(snappedf(float(data().get(field)) + step * SLIDER_STEP, SLIDER_STEP), 0.0, 1.0))
			preset = -1
		_:
			data().step_option(field, step)
			preset = -1
	# Puede aparecer o desaparecer una fila (el color del gorro, del estampado).
	var count := category_rows().size()
	var at := category_rows().find(r)
	row = at if at >= 0 else clampi(row, 0, count - 1)
	_changed()


# ---------------------------------------------------------------- vista

func _click_icon(i: int) -> void:
	if not joined() or is_ready:
		return
	if in_category and cat_index == i:
		in_category = false
	else:
		cat_index = i
		in_category = true
		row = 0
	refresh()


func _changed() -> void:
	_avatar.rebuild()
	_rebuild_board()
	refresh()


## Actualiza textos, marcos y opciones.
func refresh() -> void:
	if _title == null:
		return
	var who := ""
	if device == InputSetup.KEYBOARD:
		who = " · teclado"
	elif device >= 0:
		who = " · mando"
	_title.text = "J%d%s" % [index + 1, who]
	_style.bg_color = Palette.UI_PANEL if joined() else Color(Palette.UI_PANEL, 0.45)
	_style.border_color = YELLOW if is_ready else (Color.WHITE if joined() else Palette.UI_INK)
	_style.set_border_width_all(6 if is_ready else 4)
	_view.modulate = Color(1, 1, 1, 1.0 if joined() else 0.35)
	_export_button.visible = joined() and not is_ready
	for i in _icons.size():
		var focused := i == cat_index and joined()
		_style_icon(_icons[i], focused, focused and in_category)
		_icon_marks[i].color = YELLOW if focused else Color(1, 1, 1, 0.9 if joined() else 0.5)
		_icon_marks[i].hole = Palette.UI_TILE_ON if focused and in_category else Palette.UI_TILE
	for c in _editor.get_children():
		_editor.remove_child(c)
		c.queue_free()
	if not joined():
		_status.text = "Apretá ESPACIO o A para unirte"
		return
	var pad := device >= 0
	if is_ready:
		_status.text = "¡LISTO!  (%s: cambiar)" % ("B" if pad else "ESC")
		_status.add_theme_color_override("font_color", YELLOW)
		_editor.add_child(_label("Esperando a los demás...", 18, Color.WHITE))
		return
	_status.remove_theme_color_override("font_color")
	_status.add_theme_color_override("font_color", Color.WHITE)
	var cat_name: String = ICONS[cat_index][0]
	if _copied_time > 0.0:
		_status.text = "¡Personaje copiado! Pegalo donde quieras"
		_status.add_theme_color_override("font_color", YELLOW)
		if not in_category:
			_editor.add_child(_label(cat_name, 22, YELLOW))
			return
	if not in_category:
		_editor.add_child(_label(cat_name, 22, YELLOW))
		_editor.add_child(_label("< > elegir · %s entrar" % ("A" if pad else "ESPACIO"), 15, Color.WHITE))
		if _copied_time <= 0.0:
			_status.text = "%s: listo · %s: al azar · %s: exportar" % [
				"Start" if pad else "ENTER", "Y" if pad else "R", "Select" if pad else "C"]
		return
	var rows := category_rows()
	# Fila actual: su nombre y las opciones con su vista previa.
	var r: Array = rows[row]
	var head := _label("%s%s" % [r[0], "   (%d/%d)" % [row + 1, rows.size()] if rows.size() > 1 else ""], 16, YELLOW)
	_editor.add_child(head)
	_editor.add_child(_strip(r))
	if _copied_time <= 0.0:
		_status.text = "< > cambiar · arriba / abajo: fila · %s volver" % ("B" if pad else "ESC")


## Tira de opciones de la fila: la elegida en el medio (marcada) y las de los
## costados, cada una con su foto (o su color). Las barras, como una barra.
func _strip(r: Array) -> Control:
	var kind: String = r[1]
	var field: String = r[2]
	if kind == "slider":
		return _row_view(r, true)
	var line := HBoxContainer.new()
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_theme_constant_override("separation", 6)
	var count: int = CharacterData.PRESET_NAMES.size() if kind == "preset" else (CharacterData.FIELDS[field][1] as Array).size()
	var current: int = preset if kind == "preset" else data().get_option(field)
	var side := 1 if compact else 2
	var shown := mini(count, side * 2 + 1)
	var first := current - (shown - 1) / 2 if current >= 0 else 0
	for k in shown:
		var i := posmod(first + k, count)
		var tile := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Palette.UI_TILE
		sb.set_corner_radius_all(8)
		sb.set_border_width_all(4 if i == current else 2)
		sb.border_color = YELLOW if i == current else Palette.UI_INK
		tile.add_theme_stylebox_override("panel", sb)
		var big := 64.0 if i == current else 50.0
		tile.custom_minimum_size = Vector2(big, big)
		tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if kind == "color":
			var sw := ColorRect.new()
			sw.color = (CharacterSelect.COLOR_LISTS[field] as Array)[i]
			sw.custom_minimum_size = Vector2(big - 16.0, big - 16.0)
			tile.add_child(sw)
		else:
			var pic := TextureRect.new()
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			pic.custom_minimum_size = Vector2(big - 8.0, big - 8.0)
			tile.add_child(pic)
			if thumbs:
				thumbs.request(_variant(field if kind != "preset" else "preset", i), r[3], pic)
		var step := i - current
		tile.gui_input.connect(func(ev: InputEvent) -> void:
			var mb := ev as InputEventMouseButton
			if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and step != 0:
				change(r, step)
		)
		line.add_child(tile)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.add_child(line)
	var value_name := "a tu gusto"
	if kind != "preset":
		value_name = data().option_name(field)
	elif current >= 0:
		value_name = CharacterData.PRESET_NAMES[current]
	box.add_child(_label("<  %s  >" % value_name, 15, Color.WHITE))
	return box


## El personaje con esa opción cambiada (para la foto de la opción).
func _variant(field: String, i: int) -> CharacterData:
	var d := CharacterData.from_dict(data().to_dict())
	if field == "preset":
		d.apply_preset(i)
	else:
		d.set(CharacterData.FIELDS[field][0], i)
		# Para ver los ojos y las cejas, la foto va sin anteojos.
		if field in ["eyes", "extra"]:
			d.glasses_index = 0
	return d


func _row_view(r: Array, current: bool) -> Control:
	var line := HBoxContainer.new()
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_theme_constant_override("separation", 6)
	var kind: String = r[1]
	var field: String = r[2]
	var color := YELLOW if current else Color(1, 1, 1, 0.75)
	var title := _label("%s:" % r[0], 15, color)
	line.add_child(title)
	var value := ""
	match kind:
		"preset":
			value = CharacterData.PRESET_NAMES[preset] if preset >= 0 else "a tu gusto"
		"slider":
			var v := float(data().get(field))
			var ends: Array = CharacterSelect.SLIDER_ENDS[field]
			value = "%s  %d%%  %s" % [ends[0], roundi(v * 100.0), ends[1]]
		_:
			value = data().option_name(field)
	if current:
		value = "<  %s  >" % value
	var val := _label(value, 15, Color.WHITE)
	line.add_child(val)
	if kind == "slider":
		# La barra dibujada (no con símbolos: el navegador puede no tenerlos).
		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.value = float(data().get(field))
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(110.0, 14.0)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0, 0, 0, 0.4)
		bg.set_corner_radius_all(6)
		var fill := StyleBoxFlat.new()
		fill.bg_color = YELLOW
		fill.set_corner_radius_all(6)
		bar.add_theme_stylebox_override("background", bg)
		bar.add_theme_stylebox_override("fill", fill)
		line.add_child(bar)
	if kind == "color":
		var sw := ColorRect.new()
		sw.custom_minimum_size = Vector2(18.0, 18.0)
		sw.color = (CharacterSelect.COLOR_LISTS[field] as Array)[data().get_option(field)]
		line.add_child(sw)
	if current:
		# Con el mouse: tocar a los costados del valor cambia la opción.
		val.mouse_filter = Control.MOUSE_FILTER_STOP
		val.gui_input.connect(func(ev: InputEvent) -> void:
			var mb := ev as InputEventMouseButton
			if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				change(r, -1 if mb.position.x < val.size.x * 0.5 else 1)
		)
	return line


func _style_icon(b: Button, focused: bool, open: bool) -> void:
	for state in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Palette.UI_TILE_ON if open else (Palette.UI_TILE_HOVER if state == "hover" else Palette.UI_TILE)
		sb.set_corner_radius_all(8)
		sb.set_border_width_all(4 if focused else 2)
		sb.border_color = YELLOW if focused else Palette.UI_INK
		b.add_theme_stylebox_override(state, sb)


func _rebuild_board() -> void:
	for c in _board.get_children():
		c.free()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.5
	mesh.height = 3.6
	mesh.material = BoardDesign.material(data(), 3.6, 1.0)
	var body := MeshInstance3D.new()
	body.mesh = mesh
	body.basis = Basis(Vector3.RIGHT, PI / 2.0) * Basis.from_scale(Vector3(1.0, 1.0, 0.18))
	body.position.y = -0.06
	_board.add_child(body)


func _process(delta: float) -> void:
	if _cam == null:
		return
	if _copied_time > 0.0:
		_copied_time -= delta
		if _copied_time <= 0.0:
			refresh()
	var face: bool = in_category and ICONS[cat_index][0] in CharacterSelect.FACE_CATEGORIES
	_zoom = move_toward(_zoom, 1.0 if face else 0.0, delta * 3.0)
	var z := smoothstep(0.0, 1.0, _zoom)
	var head_y := _avatar.head_center().y
	var head_r := _avatar.head_radius()
	var eye := Vector3(0.0, 1.7, 7.4).lerp(Vector3(0.0, head_y + 0.05, 1.6 + head_r * 4.6), z)
	var look := Vector3(0.0, 1.35, 0.0).lerp(Vector3(0.0, head_y - 0.1, 0.0), z)
	_cam.transform = Transform3D(Basis.IDENTITY, eye).looking_at(look, Vector3.UP)
	if face:
		var target := -0.35 + sin(Time.get_ticks_msec() * 0.001) * 0.35
		_pivot.rotation.y = lerp_angle(_pivot.rotation.y, target, 1.0 - exp(-4.0 * delta))
	else:
		_pivot.rotation.y += delta * 0.6


## 0 = lejos ... 1 = encima de la cara (para tests).
func zoom() -> float:
	return _zoom


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", maxi(4, font_size / 5))
	return l
