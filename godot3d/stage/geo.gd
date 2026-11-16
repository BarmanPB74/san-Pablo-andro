class_name Geo
extends RefCounted
## Utilidades de geometría procedural para las escenas (sin assets): ruido, mallas de rejilla
## con normales suaves, columnas acanaladas, riscos y rocas.

# ------------------------------------------------------------------ ruido determinista

static func _h(ix: int, iy: int, seed_v: int) -> float:
	var n := ix * 374761393 + iy * 668265263 + seed_v * 1442695041
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	return float(n & 0xFFFF) / 65535.0


static func vnoise(x: float, y: float, seed_v := 0) -> float:
	var ix := floori(x)
	var iy := floori(y)
	var fx := x - float(ix)
	var fy := y - float(iy)
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var a := _h(ix, iy, seed_v)
	var b := _h(ix + 1, iy, seed_v)
	var c := _h(ix, iy + 1, seed_v)
	var d := _h(ix + 1, iy + 1, seed_v)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


static func fbm(x: float, y: float, seed_v := 0, octaves := 4) -> float:
	var v := 0.0
	var a := 0.5
	var f := 1.0
	for i in octaves:
		v += a * vnoise(x * f, y * f, seed_v + i * 17)
		f *= 2.03
		a *= 0.5
	return v


# ------------------------------------------------------------------ mallas

## Malla de rejilla (nx × nz celdas). `fn(i, j) -> Vector3` da la posición de cada vértice.
## Las normales se promedian entre caras vecinas. `flip` invierte el lado visible.
static func grid_mesh(nx: int, nz: int, fn: Callable, flip := false) -> ArrayMesh:
	var w := nx + 1
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(w * (nz + 1))
	uvs.resize(w * (nz + 1))
	for j in nz + 1:
		for i in nx + 1:
			verts[j * w + i] = fn.call(i, j)
			uvs[j * w + i] = Vector2(float(i) / float(nx), float(j) / float(nz))
	var idx := PackedInt32Array()
	for j in nz:
		for i in nx:
			var a := j * w + i
			var b := a + 1
			var c := a + w
			var d := c + 1
			if flip:
				idx.append_array([a, b, c, b, d, c])
			else:
				idx.append_array([a, c, b, b, c, d])
	return _finish(verts, uvs, idx)


static func _finish(verts: PackedVector3Array, uvs: PackedVector2Array, idx: PackedInt32Array) -> ArrayMesh:
	var nrm := PackedVector3Array()
	nrm.resize(verts.size())
	for k in range(0, idx.size(), 3):
		var p0 := verts[idx[k]]
		var p1 := verts[idx[k + 1]]
		var p2 := verts[idx[k + 2]]
		var fn := (p2 - p0).cross(p1 - p0)      # los triángulos van en sentido horario (cara visible de Godot)
		nrm[idx[k]] += fn
		nrm[idx[k + 1]] += fn
		nrm[idx[k + 2]] += fn
	for v in nrm.size():
		nrm[v] = nrm[v].normalized() if nrm[v].length_squared() > 1e-14 else Vector3.UP
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


## Columna acanalada: fuste con estrías, ensanche en el capitel y en la base.
static func column(radius: float, height: float, flutes := 16, segs := 48) -> ArrayMesh:
	var rows := 14
	var fn := func(i: int, j: int) -> Vector3:
		var th := TAU * float(i) / float(segs)
		var t := float(j) / float(rows)             # 0 abajo, 1 arriba
		var y := t * height
		var r := radius
		r *= 1.0 + 0.30 * pow(maxf(0.0, 1.0 - t / 0.04), 2.0)      # base
		r *= 1.0 + 0.35 * pow(maxf(0.0, (t - 0.94) / 0.06), 1.5)   # capitel
		r *= 1.0 - 0.08 * t                                          # entasis suave
		var groove := 1.0 - 0.035 * (0.5 + 0.5 * cos(th * float(flutes)))
		if t > 0.05 and t < 0.94:
			r *= groove
		return Vector3(sin(th) * r, y, cos(th) * r)
	return grid_mesh(segs, rows, fn, false)


## Pared de risco mirando hacia +Z (el lado del camino). Largo en X, alto en Y, relieve en Z.
static func cliff(length: float, height: float, relief: float, seed_v: int, cols := 72, rows := 26) -> ArrayMesh:
	var fn := func(i: int, j: int) -> Vector3:
		var u := float(i) / float(cols)
		var v := float(j) / float(rows)
		var top := height * (0.72 + 0.5 * fbm(u * 9.0, 3.0, seed_v, 3))
		var y := v * top
		var strata := floorf(v * 9.0) / 9.0                  # escalones de estrato
		var z := (fbm(u * 7.0, v * 3.5 + 20.0, seed_v + 5, 4) - 0.35) * relief
		z += (strata - v) * relief * 0.25
		z += sin(u * 55.0 + fbm(u * 5.0, v * 2.0, seed_v) * 6.0) * 0.18 * relief * v
		z -= v * v * relief * 0.55                           # se aleja hacia arriba (talud)
		return Vector3((u - 0.5) * length, y, z)
	return grid_mesh(cols, rows, fn, false)


## Roca: esfera deformada con ruido (para cantos rodados y escombros).
static func boulder(radius: float, seed_v: int, segs := 18, rings := 12) -> ArrayMesh:
	var fn := func(i: int, j: int) -> Vector3:
		var th := TAU * float(i) / float(segs)
		var ph := PI * float(j) / float(rings)
		var d := 0.72 + 0.55 * fbm(float(i) * 0.6 + 3.0, float(j) * 0.9, seed_v, 3)
		var r := radius * d
		return Vector3(sin(ph) * sin(th) * r, -cos(ph) * r * 0.8, sin(ph) * cos(th) * r)
	return grid_mesh(segs, rings, fn, false)


## Superficie de revolución. `profile`: Array de Vector2(radio, altura) de abajo hacia arriba.
## `inside`: true si se mira desde dentro (cámaras, cúpulas); false desde fuera.
static func lathe(profile: Array, segs: int, inside := false) -> ArrayMesh:
	var rows := profile.size() - 1
	var fn := func(i: int, j: int) -> Vector3:
		var th := TAU * float(i) / float(segs)
		var pr: Vector2 = profile[j]
		return Vector3(sin(th) * pr.x, pr.y, cos(th) * pr.x)
	return grid_mesh(segs, rows, fn, inside)
