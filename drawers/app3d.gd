extends Node3D
## One installed app on the app roller: a rounded paper tile with the app's icon and name.
## Offers the same calls as a cube so the drum (wall.gd) can carry it.

const FS = preload("res://drawers/fsutil.gd")
const Meshes = preload("res://drawers/meshes.gd")
const Apps = preload("res://desktop_apps.gd")

const S := 1.0
static var _icons := {}          # icon name -> Texture2D, shared by every tile

var info: Dictionary
var wall: Node3D
var slot := Transform3D.IDENTITY
var pivot: Node3D
var drawer: Node3D
var is_open := false
var edge_fade := 1.0:
	set(v):
		if absf(v - edge_fade) > 0.01:
			edge_fade = v
			_apply_alpha()
var _icon_mat: StandardMaterial3D
var _name: Label3D
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
	var tile := MeshInstance3D.new()
	tile.mesh = Meshes.rounded_box(Vector3(S, S, 0.1), 0.2)
	tile.material_override = mats.card
	drawer.add_child(tile)

	_icon_mat = StandardMaterial3D.new()
	_icon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	_icon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_icon_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var q := MeshInstance3D.new()
	q.mesh = Meshes.quad(Vector2(0.6, 0.6))
	q.material_override = _icon_mat
	q.position = Vector3(0, 0.1, 0.052)
	drawer.add_child(q)
	var key: String = it.icon_name if it.icon_name != "" else it.name
	if _icons.has(key):
		_icon_mat.albedo_texture = _icons[key]
	else:
		WorkerThreadPool.add_task(_load_icon.bind(it.icon_name, it.name, key))

	_name = Label3D.new()
	_name.font = ctx.sans_3d
	_name.font_size = 64
	_name.pixel_size = 0.075 / 64.0
	_name.modulate = FS.INK
	_name.outline_size = 0
	_name.double_sided = false
	_name.render_priority = 1
	_name.position = Vector3(0, -0.34, 0.052)
	var t: String = it.name
	while t.length() > 3 and ctx.sans_3d.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x * _name.pixel_size > 0.88:
		t = t.left(t.length() - 1)
	_name.text = t if t == it.name else t + "…"
	drawer.add_child(_name)

	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(S, S, 0.12)
	cs.shape = bs
	body.add_child(cs)
	body.set_meta("cube", self)
	pivot.add_child(body)
	set_process(false)


func _load_icon(icon_name: String, app_name: String, key: String) -> void:
	var img := Apps.icon_image(icon_name, app_name, 128)
	_icon_ready.call_deferred(key, img)


func _icon_ready(key: String, img: Image) -> void:
	if not _icons.has(key):
		_icons[key] = ImageTexture.create_from_image(img)
	if is_instance_valid(self) and _icon_mat:
		_icon_mat.albedo_texture = _icons[key]


func _process(delta: float) -> void:
	_hover = move_toward(_hover, _hover_target, delta * 6.0)
	_press = move_toward(_press, 0.0, delta * 3.0)
	pivot.position = Vector3(0, 0.04 * _hover, 0.18 * _hover - 0.08 * _press)
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
	if _name:
		_name.modulate.a = a
	if _icon_mat:
		_icon_mat.albedo_color.a = a


func front_point() -> Vector3:
	return drawer.global_transform * Vector3(0, 0, 0.06)
