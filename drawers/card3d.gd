extends Node3D
## One thing from an opened drawer, as a paper card on the card drum (right side).
## Same look as the calendar's homework cards: coloured stripe, glyph, kind, title, when, a round button.
## Offers the same calls as a cube so the drum (wall.gd) can carry either.

const FS = preload("res://drawers/fsutil.gd")
const Meshes = preload("res://drawers/meshes.gd")
const THUMB_SHADER = preload("res://drawers/thumb.gdshader")

const W := 1.56
const H := 1.0
const T := 0.04

var info: Dictionary
var wall: Node3D
var slot := Transform3D.IDENTITY
var pivot: Node3D
var drawer: Node3D          # the card face (named like the cube's so flights work the same)
var thumb_tex: Texture2D
var is_open := false
var edge_fade := 1.0:
	set(v):
		if absf(v - edge_fade) > 0.01:
			edge_fade = v
			_apply_alpha()
var _labels := []
var _thumb_mat: ShaderMaterial
var _icon_mat: StandardMaterial3D
var _fade := 1.0
var _hover := 0.0
var _hover_target := 0.0
var _press := 0.0


func build(it: Dictionary, ctx: Dictionary, mats: Dictionary) -> void:
	info = it
	pivot = Node3D.new()
	add_child(pivot)
	drawer = Node3D.new()
	pivot.add_child(drawer)
	var kc := FS.kind_color(it.kind)
	var media: bool = it.kind in ["image", "video", "pdf"]
	var zf := T * 0.5 + 0.002

	var face := MeshInstance3D.new()
	face.mesh = Meshes.rounded_box(Vector3(W, H, T), 0.11)
	face.material_override = mats.card
	drawer.add_child(face)
	_part(Meshes.box(Vector3(0.035, H - 0.22, 0.01)), wall.kind_mat(it.kind), Vector3(-W * 0.5 + 0.03, 0, zf))

	var icon: Texture2D = FS.icon_for(it)
	if icon:
		_icon_mat = StandardMaterial3D.new()
		_icon_mat.albedo_texture = icon
		_icon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		_icon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var iq := MeshInstance3D.new()
		iq.mesh = Meshes.quad(Vector2(0.13, 0.13))
		iq.material_override = _icon_mat
		iq.position = Vector3(-0.6, 0.37, zf + 0.001)
		drawer.add_child(iq)

	var kind_txt: String = FS.kind_info(it.kind).label
	if not it.is_dir and it.ext != "":
		kind_txt += " · " + it.ext.to_upper()
	_label(kind_txt, ctx.sans_bold_3d, 0.058, kc.darkened(0.35), Vector3(-0.5, 0.405, zf))
	if it.is_dir:
		var cnt := _label("empty" if it.child_count == 0 else "%d inside" % it.child_count, ctx.sans_3d, 0.05, FS.MUTED, Vector3(0.7, 0.4, zf))
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var x0 := -0.66
	var tw := 1.34
	if media:
		_thumb_mat = ShaderMaterial.new()
		_thumb_mat.shader = THUMB_SHADER
		_thumb_mat.set_shader_parameter("quad_size", Vector2(tw, 0.3))
		_thumb_mat.set_shader_parameter("radius", 0.04)
		if it.kind == "video":
			_thumb_mat.set_shader_parameter("placeholder", FS.FACE_DARK)
		var q := MeshInstance3D.new()
		q.mesh = Meshes.quad(Vector2(tw, 0.3))
		q.material_override = _thumb_mat
		q.position = Vector3(x0 + tw * 0.5, 0.15, zf)
		drawer.add_child(q)
		ctx.thumbs.request(it, _on_thumb)
	var title: String = it.name
	_title(title, ctx.serif_3d, Vector3(x0, -0.04 if media else 0.28, zf), tw, 0.085 if media else 0.1, 1 if media else 2)

	var meta: String
	if it.kind == "more":
		meta = "step inside to see them all"
	elif it.is_dir:
		meta = FS.ago(it.mtime)
	else:
		meta = "%s · %s" % [FS.human_size(it.size), FS.ago(it.mtime)]
	_label(meta, ctx.sans_3d, 0.052, FS.MUTED, Vector3(x0, -0.31, zf))

	# round button: → into a folder, ▶ preview, ↗ open
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.1
	cyl.bottom_radius = 0.1
	cyl.height = 0.012
	disc.mesh = cyl
	disc.material_override = mats.button
	disc.rotation_degrees.x = 90
	disc.position = Vector3(0.6, -0.34, zf + 0.004)
	drawer.add_child(disc)
	var g := "→" if it.is_dir or it.kind == "more" else ("▶" if it.kind in ["image", "video"] else "↗")
	var gl := _label(g, ctx.sans_bold_3d, 0.1, FS.MUTED, Vector3(0.6, -0.34, zf + 0.012))
	gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(W, H, T * 2)
	cs.shape = bs
	body.add_child(cs)
	body.set_meta("cube", self)
	pivot.add_child(body)
	set_process(false)


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


func _title(text: String, font: Font, pos: Vector3, width: float, h: float, max_lines: int) -> void:
	var l := _label(text, font, h, FS.INK, pos)
	var w_px := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x
	if w_px * h / 64.0 <= width:
		return
	if max_lines <= 1:
		var t := text
		while t.length() > 3 and font.get_string_size(t + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x * h / 64.0 > width:
			t = t.left(t.length() - 1)
		l.text = t + "…"
		return
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.width = width / l.pixel_size
	var lines := ceili(w_px * h / 64.0 / width * 1.12)
	if lines > max_lines:
		l.text = text.left(maxi(int(text.length() * float(max_lines) / lines) - 1, 4)) + "…"


func _on_thumb(tex: Texture2D) -> void:
	if tex == null or _thumb_mat == null:
		return
	thumb_tex = tex
	_thumb_mat.set_shader_parameter("tex", tex)
	_thumb_mat.set_shader_parameter("tex_aspect", float(tex.get_width()) / maxf(tex.get_height(), 1))
	_thumb_mat.set_shader_parameter("has_tex", 1.0)


# ---------------------------------------------------------------- the calls the drum and app make

func _process(delta: float) -> void:
	_hover = move_toward(_hover, _hover_target, delta * 6.0)
	_press = move_toward(_press, 0.0, delta * 4.0)
	pivot.position = Vector3(0, 0.03 * _hover, 0.12 * _hover - 0.05 * _press)
	if _hover == _hover_target and _press == 0.0:
		set_process(false)


func set_hover(on: bool) -> void:
	_hover_target = 1.0 if on else 0.0
	set_process(true)


func bounce() -> void:
	_press = 1.0
	set_process(true)


func set_dim(_v: float) -> void:
	pass


func open(_instant := false) -> void:
	pass


func close(_instant := false) -> void:
	pass


func apply_fade(f: float) -> void:
	_fade = f
	_apply_alpha()


func _apply_alpha() -> void:
	var a := _fade * edge_fade
	for pair in _labels:
		var l: Label3D = pair[0]
		l.modulate.a = pair[1] * a
	if _thumb_mat:
		_thumb_mat.set_shader_parameter("fade", _fade)
	if _icon_mat:
		_icon_mat.albedo_color.a = a


func front_point() -> Vector3:
	return drawer.global_transform * Vector3(0, 0, T)
