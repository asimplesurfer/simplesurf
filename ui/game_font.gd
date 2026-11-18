extends Node
## La letra del juego (assets/fonts/simplesurf-Regular.ttf) para todos los
## textos: menús, HUD, carteles. Se pone como letra por defecto de todo, así
## cualquier Label o botón la usa sin tocar nada. Los signos que esa letra no
## tiene (º, ×...) salen con la letra de antes (la de Godot), no como cajitas.

const PATH := "res://assets/fonts/simplesurf-Regular.ttf"
## Esta letra dibuja más chico que la de antes con el mismo tamaño: se agranda
## así para que los textos ocupen lo mismo que antes (sin tocar los tamaños de
## cada texto).
const SCALE := 1.6


func _enter_tree() -> void:
	apply()


static func apply() -> void:
	var src := load(PATH) as FontFile
	if src == null:
		return
	var font := scaled(src, SCALE)
	var old := ThemeDB.fallback_font
	if old != null:
		font.fallbacks = [old]
	ThemeDB.fallback_font = font
	ThemeDB.get_default_theme().default_font = font


## Una copia de la letra `src` que dibuja `scale` veces más grande: achica las
## "unidades por em" de la tabla head del archivo (todo lo demás de la letra se
## mide en esas unidades, así crece parejo: letras, espacios y renglones).
static func scaled(src: FontFile, scale: float) -> FontFile:
	var data := src.data.duplicate()
	var tables := data.decode_u8(4) << 8 | data.decode_u8(5)
	for i in tables:
		var rec := 12 + i * 16
		if data.slice(rec, rec + 4).get_string_from_ascii() != "head":
			continue
		var at := (data.decode_u8(rec + 8) << 24 | data.decode_u8(rec + 9) << 16
			| data.decode_u8(rec + 10) << 8 | data.decode_u8(rec + 11)) + 18
		var upem := data.decode_u8(at) << 8 | data.decode_u8(at + 1)
		var smaller := clampi(roundi(upem / scale), 16, 16384)
		data.encode_u8(at, smaller >> 8)
		data.encode_u8(at + 1, smaller & 0xFF)
	var out := FontFile.new()
	out.data = data
	return out
