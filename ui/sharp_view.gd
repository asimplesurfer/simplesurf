class_name SharpView
extends Control
## Una vista 3D (SubViewport) que se dibuja con los píxeles reales de la
## pantalla. Un SubViewportContainer común toma el tamaño "lógico" de la
## interfaz (1280x720 escalado): en una pantalla retina el 3D salía a la mitad
## de resolución y estirado, borroso. Acá el SubViewport tiene el tamaño en
## píxeles reales (con un tope, por el rendimiento en la web), se dibuja achicado
## para que cada píxel caiga en uno de la pantalla, y lo 2D de adentro (el HUD)
## se sigue armando en tamaño lógico. Con antialiasing (MSAA): bordes y
## contornos sin escalones.

## Tope de píxeles que se dibujan en 3D (sumando todas las vistas, se reparte
## por el tamaño de cada una). Unos 1920x1200.
const MAX_PIXELS := 2300000.0

var viewport: SubViewport
var _box: SubViewportContainer


func _init() -> void:
	_box = SubViewportContainer.new()
	_box.stretch = true
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)
	viewport = SubViewport.new()
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.size_2d_override_stretch = true
	_box.add_child(viewport)
	resized.connect(_fit)


func _ready() -> void:
	get_tree().root.size_changed.connect(_fit)
	_fit()


## Cuántos píxeles de la pantalla hay por unidad de la interfaz (con el tope).
func pixel_scale() -> float:
	var f := get_viewport().get_final_transform().get_scale().x * get_global_transform().get_scale().x
	if not is_finite(f) or f <= 0.0:
		f = 1.0
	var screen := get_tree().root.get_visible_rect().size
	var share := clampf(size.x * size.y / maxf(screen.x * screen.y, 1.0), 0.05, 1.0)
	var area := size.x * size.y * f * f
	if area > MAX_PIXELS * share:
		f *= sqrt(MAX_PIXELS * share / area)
	return clampf(f, 0.5, 3.0)


func _fit() -> void:
	if not is_inside_tree() or size.x < 1.0 or size.y < 1.0:
		return
	var f := pixel_scale()
	_box.scale = Vector2.ONE / f
	_box.position = Vector2.ZERO
	_box.size = (size * f).round()
	viewport.size_2d_override = Vector2i(size.round())
