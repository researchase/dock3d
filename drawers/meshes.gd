extends RefCounted
## Rounded boxes (soft paper-cube edges) built once and cached.

static var _cache := {}


static func _coords(h: float, r: float, seg: int) -> PackedFloat32Array:
	# straight middle, `seg` steps around each rounded edge
	var out := PackedFloat32Array()
	for k in seg + 1:
		out.append(-h + r - r * cos(PI * 0.5 * k / seg))
	for k in range(seg, -1, -1):
		out.append(h - r + r * cos(PI * 0.5 * k / seg))
	return out


static func rounded_box(size: Vector3, r: float, seg := 3) -> ArrayMesh:
	var key := "%s|%s|%d" % [size, r, seg]
	if _cache.has(key):
		return _cache[key]
	var h := size * 0.5
	r = minf(r, minf(h.x, minf(h.y, h.z)) - 0.0005)
	var inner := h - Vector3(r, r, r)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for n in 3:
		for sgn in [-1.0, 1.0]:
			var u := (n + 1) % 3
			var v := (n + 2) % 3
			var cu := _coords(h[u], r, seg)
			var cv := _coords(h[v], r, seg)
			var base := verts.size()
			for j in cv.size():
				for i in cu.size():
					var p := Vector3()
					p[n] = sgn * h[n]
					p[u] = cu[i]
					p[v] = cv[j]
					var c := p.clamp(-inner, inner)
					var nn := (p - c).normalized()
					verts.append(c + nn * r)
					norms.append(nn)
					uvs.append(Vector2(cu[i] / size[u] + 0.5, 0.5 - cv[j] / size[v]))
			var w := cu.size()
			for j in cv.size() - 1:
				for i in w - 1:
					var a := base + j * w + i
					_tri(verts, norms, idx, a, a + 1, a + w + 1)
					_tri(verts, norms, idx, a, a + w + 1, a + w)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_cache[key] = m
	return m


static func _tri(verts: PackedVector3Array, norms: PackedVector3Array, idx: PackedInt32Array, a: int, b: int, c: int) -> void:
	var cr := (verts[b] - verts[a]).cross(verts[c] - verts[a])
	if cr.length_squared() < 1e-14:
		return
	# Godot treats clockwise (seen from outside) as the front face
	if cr.dot(norms[a] + norms[b] + norms[c]) > 0.0:
		idx.append_array([a, c, b])
	else:
		idx.append_array([a, b, c])


static func box(size: Vector3) -> BoxMesh:
	var key := "box|%s" % size
	if not _cache.has(key):
		var b := BoxMesh.new()
		b.size = size
		_cache[key] = b
	return _cache[key]


static func quad(size: Vector2) -> QuadMesh:
	var key := "quad|%s" % size
	if not _cache.has(key):
		var q := QuadMesh.new()
		q.size = size
		_cache[key] = q
	return _cache[key]
