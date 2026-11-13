extends SceneTree
## Chequeo rápido antes de publicar: que todos los scripts compilen y que las
## escenas principales carguen. Si algo falla, no se publica (queda la versión
## anterior). Uso: godot --headless --path . --script res://tests/compile_check.gd

var _errors: int = 0


func _init() -> void:
	_check_dir("res://")
	for scene in ["res://main.tscn", "res://sandbox.tscn", "res://ui/menus/character_select.tscn"]:
		if ResourceLoader.load(scene) == null:
			print("NO CARGA: %s" % scene)
			_errors += 1
	if _errors == 0:
		print("COMPILA OK")
		quit(0)
	else:
		print("ERRORES DE COMPILACIÓN: %d" % _errors)
		quit(1)


func _check_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		if sub.begins_with(".") or sub == "addons":
			continue
		_check_dir(path.path_join(sub))
	for file in dir.get_files():
		if not file.ends_with(".gd"):
			continue
		var full := path.path_join(file)
		var script := ResourceLoader.load(full) as GDScript
		if script == null or not script.can_instantiate():
			print("NO COMPILA: %s" % full)
			_errors += 1
