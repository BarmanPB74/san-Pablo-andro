class_name UiLock
extends RefCounted
## Bandera global sin dependencias: mientras es true (rueda de mapas abierta), Andro y la cámara no reciben movimiento
## ni botones. Vive en una clase propia para que el autoload Inputs, Story, TouchControls y MapWheel la lean sin ciclos.

static var blocked := false
