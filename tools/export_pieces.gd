extends SceneTree
## Imprime el catálogo de piezas para el editor de mapas (lo usa
## tools/map_editor/build.py; ver MapPiece.editor_catalog):
##
##   godot --headless --path . --script res://tools/export_pieces.gd
##
## Sale en una sola línea que empieza con "PIECES_JSON ".


func _initialize() -> void:
	print("PIECES_JSON " + JSON.stringify(MapPiece.editor_catalog()))
	quit()
