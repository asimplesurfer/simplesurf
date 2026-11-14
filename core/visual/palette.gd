class_name Palette
extends RefCounted
## Paleta del juego: tonos pastel de playa y verano (suaves, claros, que se
## lleven bien entre sí). Todo lo que tiene color propio lo toma de acá, así
## se ajusta en un solo lugar. (La tormenta usa sus propios tonos grises: ver
## storm.gd.)

# Playa e islas
const SAND := Color(0.98, 0.83, 0.64)
const GRASS := Color(0.6, 0.87, 0.62)
const LEAVES := Color(0.42, 0.78, 0.56)
const TRUNK := Color(0.84, 0.66, 0.52)
const ROCK := Color(0.62, 0.63, 0.74)
const VOLCANO := Color(0.66, 0.56, 0.58)
const LAVA := Color(1.0, 0.6, 0.45)
const STONE := Color(0.76, 0.7, 0.72)
const MOSS := Color(0.55, 0.8, 0.6)
const WOOD := Color(0.72, 0.55, 0.45)
const SAIL := Color(1.0, 0.96, 0.9)

# Colores vivos pero suaves (boyas, círculos, carteles)
const WHITE := Color(1.0, 0.98, 0.96)
const CORAL := Color(1.0, 0.56, 0.55)
const BUTTER := Color(1.0, 0.88, 0.48)
const AQUA := Color(0.42, 0.9, 0.92)
const PEACH := Color(1.0, 0.72, 0.52)
const LILAC := Color(0.76, 0.68, 0.98)
const PINK := Color(1.0, 0.66, 0.82)
const MINT := Color(0.58, 0.95, 0.74)

# Interfaz (menú, HUD)
const UI_SKY := Color(0.62, 0.84, 0.96)
const UI_PANEL := Color(0.25, 0.3, 0.52, 0.86)
const UI_TILE := Color(0.36, 0.43, 0.68)
const UI_TILE_HOVER := Color(0.45, 0.53, 0.8)
const UI_TILE_ON := Color(0.54, 0.62, 0.9)
const UI_INK := Color(0.13, 0.12, 0.22)
const UI_SOFT_TEXT := Color(0.92, 0.94, 1.0)
