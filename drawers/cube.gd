extends Node3D
## One file or folder as a paper cube with a drawer (after Diana's calendar):
## a shell, a drawer whose front is the item's face, a tray with papers inside,
## and a warm light that comes on when the drawer slides out.

const FS = preload("res://drawers/fsutil.gd")
const Meshes = preload("res://drawers/meshes.gd")
const THUMB_SHADER = preload("res://drawers/thumb.gdshader")

const S := 1.0
const D := 0.78
const OPEN_Z := 0.5          # the cube comes forward when opened
const OPEN_LIFT := 0.05
const DRAWER_OUT := 0.64     # S * .78 * .82, as in the calendar
const FACE_W := 0.82

var info: Dictionary
var wall: Node3D
var slot := Transform3D.IDENTITY
var pivot: Node3D
var drawer: Node3D
var glow: OmniLight3D
var thumb_tex: Texture2D
var is_open := false

var open_t := 0.0:
	set(v):
		open_t = v
		_pose()
var _hover := 0.0
var _hover_target := 0.0
var _bounce := 0.0
var _labels := []            # [Label3D, base alpha]
var _thumb_mat: ShaderMaterial
var _icon_mat: StandardMaterial3D
var _dim := 0.0
var _fade := 1.0
var edge_fade := 1.0:          # set by the drum: labels fade as the row rolls away
	set(v):
		if absf(v - edge_fade) > 0.01:
			edge_fade = v
			_apply_alpha()
var _open_tw: Tween
var _dim_tw: Tween


func build(it: Dictionary, ctx: Dictionary, mats: Dictionary) -> void:
	info = it
	pivot = Node3D.new()
	add_child(pivot)

	var shell := MeshInstance3D.new()
	shell.mesh = Meshes.rounded_box(Vector3(S, S, D * 0.96), 0.08)
	shell.material_override = mats.shell
	shell.position.z = -D * 0.02
	pivot.add_child(shell)

	drawer = Node3D.new()
	pivot.add_child(drawer)
	_build_tray(mats)

	var media: bool = it.kind in ["image", "video", "pdf"]
	var front := MeshInstance3D.new()
	front.mesh = Meshes.rounded_box(Vector3(S, S, 0.07), 0.11)
	front.material_override = mats.front_dark if it.kind == "video" else mats.front
	front.position.z = D * 0.5
	drawer.add_child(front)

	var zf := D * 0.5 + 0.037
	var dark: bool = it.kind == "video"
	var ink: Color = FS.CARD if dark else FS.INK
	var muted: Color = Color(1, 1, 1, 0.6) if dark else FS.MUTED
	var x0 := -FACE_W * 0.5

	var tag: String
	if it.kind == "folder":
		tag = "FOLDER"
	elif it.kind == "more":
		tag = "MORE"
	else:
		tag = it.ext.to_upper() if it.ext != "" else FS.kind_info(it.kind).label.to_upper()
	_label(tag.left(10), ctx.sans_bold_3d, 0.07, muted, Vector3(x0, 0.43, zf))

	if media:
		_thumb_mat = ShaderMaterial.new()
		_thumb_mat.shader = THUMB_SHADER
		_thumb_mat.set_shader_parameter("quad_size", Vector2(0.84, 0.5))
		if dark:
			_thumb_mat.set_shader_parameter("placeholder", Color(0.3, 0.2, 0.33))
		var q := MeshInstance3D.new()
		q.mesh = Meshes.quad(Vector2(0.84, 0.5))
		q.material_override = _thumb_mat
		q.position = Vector3(0, 0.07, zf)
		drawer.add_child(q)
		ctx.thumbs.request(it, _on_thumb)
		_fit_label(it.name, ctx.serif_3d, Vector3(x0, -0.215, zf), ink, 0.085, 0.085, 1)
		if it.kind == "video":
			var play := _label("▶", ctx.sans_bold_3d, 0.13, Color(1, 1, 1, 0.92), Vector3(0, 0.07, zf + 0.004))
			play.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			play.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			play.outline_size = 10
			play.outline_modulate = Color(0, 0, 0, 0.35)
	else:
		_fit_label(it.name, ctx.serif_3d, Vector3(x0, 0.31, zf), ink, 0.24, 0.1, 3)
		var icon: Texture2D = FS.icon_for(it)
		if icon:
			_icon_mat = StandardMaterial3D.new()
			_icon_mat.albedo_texture = icon
			_icon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
			_icon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_icon_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			var iq := MeshInstance3D.new()
			iq.mesh = Meshes.quad(Vector2(0.2, 0.2))
			iq.material_override = _icon_mat
			iq.position = Vector3(0.31, 0.37, zf + 0.001)
			drawer.add_child(iq)

	var meta: String
	if it.kind == "folder":
		meta = "empty" if it.child_count == 0 else FS.things(it.child_count)
	elif it.kind == "more":
		meta = "open in Files"
	else:
		meta = FS.human_size(it.size)
	_label(meta, ctx.sans_3d, 0.065, muted, Vector3(x0, -0.31 if media else -0.3, zf))
	_build_bar(mats, zf)

	if it.kind != "more" and FS.is_today(it.mtime):
		_pill("Today", ctx, mats)

	glow = OmniLight3D.new()
	glow.light_color = Color(1.0, 0.78, 0.45)
	glow.light_energy = 0.0
	glow.omni_range = 1.9
	glow.omni_attenuation = 1.4
	glow.position = Vector3(0, 0.0, D * 0.5 - 0.15)
	drawer.add_child(glow)

	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(S, S, D)
	cs.shape = bs
	body.add_child(cs)
	body.set_meta("cube", self)
	pivot.add_child(body)
	set_process(false)


func _build_tray(mats: Dictionary) -> void:
	var td := D * 0.9
	var zb := D * 0.5 - td
	var zc := zb + td * 0.5
	_part(Meshes.box(Vector3(0.84, 0.03, td)), mats.tray, Vector3(0, -0.40, zc))
	_part(Meshes.box(Vector3(0.03, 0.42, td)), mats.tray, Vector3(-0.42, -0.2, zc))
	_part(Meshes.box(Vector3(0.03, 0.42, td)), mats.tray, Vector3(0.42, -0.2, zc))
	_part(Meshes.box(Vector3(0.84, 0.42, 0.03)), mats.tray, Vector3(0, -0.2, zb + 0.015))
	# papers standing in the drawer, one per kind of thing inside (largest first)
	var kinds := []
	if info.kind == "folder":
		var ck: Dictionary = info.child_kinds
		kinds = ck.keys()
		kinds.sort_custom(func(a, b): return ck[a] > ck[b])
		kinds = kinds.slice(0, 4)
	elif info.kind != "more":
		kinds = [info.kind]
	for k in kinds.size():
		var p := _part(Meshes.box(Vector3(0.62, 0.5, 0.012)), wall.paper_mat(kinds[k]),
			Vector3(0.03 * (k % 2) - 0.015, -0.16 - 0.02 * k, zb + 0.14 + k * 0.12))
		p.rotation.z = (0.05 if k % 2 else -0.04) * (1 + k * 0.3)


func _build_bar(mats: Dictionary, zf: float) -> void:
	# little segmented bar like the calendar's progress bars: what the folder holds
	if info.kind != "folder" or info.child_count == 0:
		return
	var ck: Dictionary = info.child_kinds
	var segs := []
	var n := mini(info.child_count, 8)
	var keys := ck.keys()
	keys.sort_custom(func(a, b): return ck[a] > ck[b])
	for k in keys:
		var share := maxi(1, roundi(float(ck[k]) / info.child_count * n))
		for i in share:
			if segs.size() < n:
				segs.append(k)
	var gap := 0.02
	var w := (FACE_W - gap * (n - 1)) / n
	for i in segs.size():
		_part(Meshes.box(Vector3(w, 0.028, 0.01)), wall.kind_mat(segs[i]),
			Vector3(-FACE_W * 0.5 + w * 0.5 + i * (w + gap), -0.415, zf))


func _pill(text: String, ctx: Dictionary, mats: Dictionary) -> void:
	var w := 0.12 + text.length() * 0.055
	var p := MeshInstance3D.new()
	p.mesh = Meshes.rounded_box(Vector3(w, 0.13, 0.05), 0.06)
	p.material_override = mats.pill
	p.position = Vector3(0, 0.5, D * 0.5 + 0.02)
	pivot.add_child(p)
	var l := Label3D.new()
	l.text = text
	l.font = ctx.sans_bold_3d
	l.font_size = 64
	l.pixel_size = 0.07 / 64.0
	l.modulate = Color(1, 1, 1)
	l.outline_size = 0
	l.position = Vector3(0, 0.5, D * 0.5 + 0.047)
	l.double_sided = false
	pivot.add_child(l)
	_labels.append([l, 1.0])


func _part(mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	drawer.add_child(m)
	return m


func _label(text: String, font: Font, h: float, color: Color, pos: Vector3) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = font
	l.font_size = 64
	l.pixel_size = h / 64.0
	l.modulate = color
	l.outline_size = 0
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.double_sided = false
	l.render_priority = 1
	l.position = pos
	drawer.add_child(l)
	_labels.append([l, color.a])
	return l


## Name on the face: as big as fits on one line, else wrapped onto up to `max_lines` lines.
func _fit_label(text: String, font: Font, pos: Vector3, color: Color, h_max: float, h_min: float, max_lines: int) -> void:
	var w_px := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x
	var h := clampf(FACE_W / maxf(w_px, 1.0) * 64.0, h_min, h_max)
	var l := _label(text, font, h, color, pos)
	if w_px * h / 64.0 <= FACE_W:
		return
	if max_lines <= 1:
		# one line only: trim with an ellipsis
		var t := text
		while t.length() > 3 and font.get_string_size(t + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x * h / 64.0 > FACE_W:
			t = t.left(t.length() - 1)
		l.text = t + "…"
		return
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.width = FACE_W / l.pixel_size
	var lines := ceili(w_px * h / 64.0 / FACE_W * 1.12)
	if lines > max_lines:
		var keep := int(text.length() * float(max_lines) / lines) - 1
		l.text = text.left(maxi(keep, 4)) + "…"


func _on_thumb(tex: Texture2D) -> void:
	if tex == null or _thumb_mat == null:
		return
	thumb_tex = tex
	_thumb_mat.set_shader_parameter("tex", tex)
	_thumb_mat.set_shader_parameter("tex_aspect", float(tex.get_width()) / maxf(tex.get_height(), 1))
	_thumb_mat.set_shader_parameter("has_tex", 1.0)


# ---------------------------------------------------------------- motion

func _pose() -> void:
	if pivot == null:
		return
	var o := open_t
	pivot.position = Vector3(0, OPEN_LIFT * o + _bounce, OPEN_Z * o + 0.1 * _hover)
	drawer.position.z = DRAWER_OUT * o
	glow.light_energy = 1.3 * o
	glow.visible = o > 0.01


func _process(delta: float) -> void:
	_hover = move_toward(_hover, _hover_target, delta * 6.0)
	_pose()
	if _hover == _hover_target:
		set_process(false)


func set_hover(on: bool) -> void:
	_hover_target = 1.0 if on and not is_open else 0.0
	set_process(true)


func open(instant := false) -> void:
	is_open = true
	_hover_target = 0.0
	_tween_open(1.0, 0.0 if instant else 0.6, [0.2, 0.8, 0.2, 1.0])


func close(instant := false) -> void:
	is_open = false
	_tween_open(0.0, 0.0 if instant else 0.55, [0.2, 0.8, 0.2, 1.0])


func _tween_open(to: float, dur: float, bz: Array) -> void:
	if _open_tw:
		_open_tw.kill()
	if dur <= 0.0:
		open_t = to
		return
	var from := open_t
	_open_tw = create_tween()
	_open_tw.tween_method(func(t): open_t = lerpf(from, to, FS.bezier(t, bz[0], bz[1], bz[2], bz[3])), 0.0, 1.0, dur)


func bounce() -> void:
	var tw := create_tween()
	for h in [0.35, 0.0, 0.15, 0.0]:
		tw.tween_method(_set_bounce, _bounce, h, 0.18) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT if h > 0 else Tween.EASE_IN)


func set_dim(v: float) -> void:
	if _dim_tw:
		_dim_tw.kill()
	_dim_tw = create_tween()
	_dim_tw.tween_method(_set_dim_now, _dim, v, 0.4)


func _set_bounce(v: float) -> void:
	_bounce = v
	_pose()


func _set_dim_now(v: float) -> void:
	_dim = v
	_apply_alpha()


func apply_fade(f: float) -> void:
	_fade = f
	_apply_alpha()


func _apply_alpha() -> void:
	var a := (1.0 - 0.6 * _dim) * _fade * edge_fade
	for pair in _labels:
		var l: Label3D = pair[0]
		l.modulate.a = pair[1] * a
	if _thumb_mat:
		_thumb_mat.set_shader_parameter("dim", _dim)
		_thumb_mat.set_shader_parameter("fade", _fade)
	if _icon_mat:
		_icon_mat.albedo_color.a = a


func front_point() -> Vector3:
	return drawer.global_transform * Vector3(0, 0.12, D * 0.5 + 0.04)
