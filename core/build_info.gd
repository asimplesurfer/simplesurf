class_name BuildInfo
extends RefCounted
## Número de build (lo pone el CI al publicar: el número de la corrida de
## "Web build" en GitHub Actions). Se ve arriba a la derecha en el menú, así se
## sabe si ya se está viendo la última versión. 0 = versión local.

const BUILD := 0


static func label() -> String:
	return "build %d" % BUILD if BUILD > 0 else "build local"
