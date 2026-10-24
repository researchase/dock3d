extends Node
## Drawers: a 3D file browser after Diana's drawer calendar, living inside the dock's transparent window.
## Each folder is a drum: its folders as little cabinets (drawer cubes) and its files as paper cards,
## wrapped round an invisible cylinder. Clicking a folder rolls it to the middle and slides its drawer
## out; then the whole drum glides left into the blurred background and the folder's own contents fly
## out of that drawer to take its place. Pictures and videos preview on the right; other files open.

const FS = preload("res://drawers/fsutil.gd")
const Wall = preload("res://drawers/wall.gd")
const Cube = preload("res://drawers/cube.gd")
const Card3D = preload("res://drawers/card3d.gd")
const AppTile = preload("res://drawers/app3d.gd")
const Apps = preload("res://desktop_apps.gd")
const Thumbs = preload("res://drawers/thumbs.gd")
const SHADOW_CATCHER = preload("res://drawers/shadow_catcher.gdshader")

signal closed   # finished putting everything back into the dock

const MAX_CARDS := 60
const SERIF := ["Bitstream Charter", "Charter", "C059", "Noto Serif", "DejaVu Serif"]
const SANS := ["Lato", "Ubuntu", "Noto Sans", "DejaVu Sans"]
const HINT := "Tap a folder to open it  ·  click the background to go back."
const APPS_HINT := "Click an app to start it  ·  click the background to close."

var world: Node3D
var camera: Camera3D
var thumbs: Node
var ctx := {}
var cur = null        # Wall in the middle
var par = null        # parent Wall at the left edge
var busy := false
var show_hidden := false
var state := "idle"   # idle | folder | preview
var panel_cube = null
var _hover_cube = null

var ui_root: Control
var peek: PanelContainer      # hover preview of a file, on the right
var _peek_v: VBoxContainer
var _peek_token := 0
var _peek_for = null
var _peek_tw: Tween
var _full_cache := {}         # path -> full-size Texture2D for recently peeked pictures
var _full_order := []
var _press := Vector2.ZERO
var _pressing := false
var _dragging := false
var _drag_v := 0.0
var head_card: PanelContainer
var hint_box: PanelContainer
var header: VBoxContainer
var crumbs: HBoxContainer
var title: Label
var hello: Label
var hint: Label
var panel: Control
var pv: VBoxContainer
var toast_box: PanelContainer
var toast_lbl: Label
var _toast_tw: Tween
var _video: VideoStreamPlayer


var is_shown := false
var mode := "files"      # files | apps (the app roller)
var brand: Label
var start_path := ""
var root_path := ""      # where this opening started: clicking the background here closes everything
var back_vp: SubViewport  # renders only the parent wall (layer 2) so the launcher can show it blurred
var _back_cam: Camera3D
const BACK_LAYER := 2
var _hiding := false


func _ready() -> void:
	_setup_fonts()
	_setup_world()
	_setup_ui()
	thumbs = Thumbs.new()
	add_child(thumbs)
	ctx.thumbs = thumbs
	get_viewport().size_changed.connect(_layout)
	start_path = FS.home()


## Called by the dock: the walls rise up out of the dock.
func show_drawers(path := "") -> void:
	if is_shown:
		return
	is_shown = true
	_hiding = false
	mode = "files"
	if path != "" and DirAccess.dir_exists_absolute(path):
		start_path = path.simplify_path()
	root_path = start_path
	ui_root.visible = true
	await get_tree().process_frame
	_layout()
	_go_initial(start_path)
	if OS.has_environment("DRAWERS_SCRIPT"):
		_run_script(OS.get_environment("DRAWERS_SCRIPT"))


## The app roller: every installed app on a drum. Click one to start it.
func show_apps() -> void:
	if is_shown:
		return
	is_shown = true
	_hiding = false
	mode = "apps"
	ui_root.visible = true
	await get_tree().process_frame
	_layout()
	var list := Apps.list_installed()
	for a in list:
		a.is_dir = false
		a.kind = "app"
	var w = Wall.new()
	w.item_script = AppTile
	w.cell_w = 1.0
	w.gap = 0.14
	w.row_h = 1.16
	w.max_items = 600
	w.start_middle = true
	world.add_child(w)
	w.build("apps", list, ctx)
	cur = w
	cur.transform = _apps_xf(cur)
	cur.enter_rise()
	root_path = "apps"
	_header()
	_panel_idle()
	if OS.has_environment("DRAWERS_SCRIPT"):
		_run_script(OS.get_environment("DRAWERS_SCRIPT"))


## Everything goes back down into the dock, then `closed` is emitted.
func hide_drawers() -> void:
	if not is_shown or _hiding:
		return
	_hiding = true
	busy = true
	if state != "idle":
		await _panel_out(true)
	_clear_panel()
	var vs := get_viewport().get_visible_rect().size
	var sink := Transform3D(Basis(), _world_at(Vector2(vs.x * 0.5, vs.y + 200.0)))
	if cur:
		if mode == "files":
			start_path = cur.path
		cur.exit_into(sink)
	if par:
		par.leave(0.5)
	cur = null
	par = null
	var tw := create_tween()
	tw.tween_property(ui_root, "modulate:a", 0.0, 0.3)
	await _wait(0.75)
	ui_root.visible = false
	ui_root.modulate.a = 1.0
	is_shown = false
	_hiding = false
	busy = false
	closed.emit()


# ---------------------------------------------------------------- setup

func _font(names: Array, weight := 400, msdf := false) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(names)
	f.font_weight = weight
	f.multichannel_signed_distance_field = msdf
	var fb := SystemFont.new()
	fb.font_names = PackedStringArray(["DejaVu Sans"])
	fb.multichannel_signed_distance_field = msdf
	f.fallbacks = [fb]
	return f


func _setup_fonts() -> void:
	ctx.serif = _font(SERIF, 400)
	ctx.serif_med = _font(SERIF, 700)
	ctx.sans = _font(SANS, 400)
	ctx.sans_semi = _font(SANS, 600)
	ctx.sans_bold = _font(SANS, 700)
	ctx.serif_3d = _font(SERIF, 400, true)
	ctx.sans_3d = _font(SANS, 400, true)
	ctx.sans_bold_3d = _font(SANS, 700, true)
	ctx.mono = _font(["DejaVu Sans Mono", "Ubuntu Mono", "Noto Sans Mono"], 400)


func _setup_world() -> void:
	world = Node3D.new()
	add_child(world)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.97, 0.92)
	env.ambient_light_energy = 0.62
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.ssao_enabled = true
	env.ssao_radius = 0.7
	env.ssao_intensity = 1.4
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	# soft warm key light from the upper left, like a window
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.97, 0.92)
	sun.light_energy = 0.62
	sun.shadow_enabled = true
	sun.light_angular_distance = 2.5
	sun.shadow_blur = 1.5
	sun.shadow_opacity = 0.6
	sun.directional_shadow_max_distance = 30.0
	world.add_child(sun)
	sun.basis = Basis.looking_at(Vector3(0.42, -0.62, -0.66).normalized(), Vector3.UP)

	camera = Camera3D.new()
	camera.fov = 30.0
	camera.position = Vector3(0, 0.8, 14.0)
	camera.rotation_degrees.x = -3.0
	world.add_child(camera)
	camera.current = true
	camera.cull_mask = 0xFFFFF & ~BACK_LAYER

	back_vp = SubViewport.new()
	back_vp.transparent_bg = true
	back_vp.world_3d = get_viewport().find_world_3d()
	back_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(back_vp)
	_back_cam = Camera3D.new()
	_back_cam.cull_mask = BACK_LAYER
	back_vp.add_child(_back_cam)
	_back_cam.current = true

	var back := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(90, 60)
	plane.orientation = PlaneMesh.FACE_Z
	back.mesh = plane
	var bm := ShaderMaterial.new()
	bm.shader = SHADOW_CATCHER
	back.material_override = bm
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	back.position.z = -1.6
	world.add_child(back)


func _lbl(text: String, font: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _setup_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var ui := Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var th := Theme.new()
	th.default_font = ctx.sans
	th.default_font_size = 16
	ui.theme = th
	ui.visible = false
	layer.add_child(ui)
	ui_root = ui

	head_card = PanelContainer.new()
	head_card.add_theme_stylebox_override("panel", paper_style(22, 22, 16))
	ui.add_child(head_card)
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 18)
	head_card.add_child(hrow)
	header = VBoxContainer.new()
	header.add_theme_constant_override("separation", 2)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hrow.add_child(header)
	var close := _button("×")
	close.add_theme_font_size_override("font_size", 20)
	close.tooltip_text = "Put everything back into the dock (Esc)"
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close.pressed.connect(hide_drawers)
	hrow.add_child(close)
	var user := OS.get_environment("USER")
	brand = _lbl("MY FILES · %s" % user.capitalize(), ctx.sans_bold, 14, FS.GOLD_INK)
	header.add_child(brand)
	crumbs = HBoxContainer.new()
	crumbs.add_theme_constant_override("separation", 2)
	header.add_child(crumbs)
	title = _lbl("", ctx.serif, 42, FS.INK)
	header.add_child(title)
	hello = _lbl("", ctx.serif, 20, FS.INK2)
	hello.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(hello)

	hint_box = PanelContainer.new()
	hint_box.add_theme_stylebox_override("panel", paper_style(16, 16, 6))
	hint_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint = _lbl(HINT, ctx.sans, 15, FS.INK2)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_box.add_child(hint)
	ui.add_child(hint_box)

	panel = Control.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(panel)
	pv = VBoxContainer.new()
	pv.set_anchors_preset(Control.PRESET_FULL_RECT)
	pv.add_theme_constant_override("separation", 10)
	pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(pv)

	peek = PanelContainer.new()
	peek.add_theme_stylebox_override("panel", paper_style(20, 22, 18))
	peek.mouse_filter = Control.MOUSE_FILTER_IGNORE
	peek.visible = false
	_peek_v = VBoxContainer.new()
	_peek_v.add_theme_constant_override("separation", 10)
	_peek_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	peek.add_child(_peek_v)
	ui.add_child(peek)

	toast_box = PanelContainer.new()
	var ts := StyleBoxFlat.new()
	ts.bg_color = FS.CARD
	ts.set_corner_radius_all(22)
	ts.set_border_width_all(1)
	ts.border_color = FS.HAIR
	ts.shadow_color = Color(0.35, 0.24, 0.08, 0.14)
	ts.shadow_size = 14
	ts.content_margin_left = 22
	ts.content_margin_right = 22
	ts.content_margin_top = 10
	ts.content_margin_bottom = 10
	toast_box.add_theme_stylebox_override("panel", ts)
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_lbl = _lbl("", ctx.serif, 18, FS.INK)
	toast_box.add_child(toast_lbl)
	toast_box.modulate.a = 0.0
	ui.add_child(toast_box)


func paper_style(radius: int, mx: int, my: int, alpha := 0.94) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(FS.CARD, alpha)
	s.set_corner_radius_all(radius)
	s.set_border_width_all(1)
	s.border_color = Color(FS.HAIR, alpha)
	s.shadow_color = Color(0.1, 0.07, 0.03, 0.18)
	s.shadow_size = 16
	s.shadow_offset = Vector2(0, 6)
	s.content_margin_left = mx
	s.content_margin_right = mx
	s.content_margin_top = my
	s.content_margin_bottom = my
	return s


func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	back_vp.size = Vector2i(maxi(1, int(vs.x * 0.5)), maxi(1, int(vs.y * 0.5)))
	_back_cam.fov = camera.fov
	_back_cam.global_transform = camera.global_transform
	hello.custom_minimum_size.x = minf(vs.x * 0.42, 680)
	head_card.reset_size()
	head_card.position = Vector2(32, 20)
	hint_box.reset_size()
	hint_box.position = Vector2(vs.x * 0.3475 - hint_box.size.x * 0.5, vs.y * 0.205)
	panel.position = Vector2(vs.x * 0.6, vs.y * 0.2)
	panel.size = Vector2(vs.x * 0.4 - 36, vs.y * 0.8 - 20)
	peek.position = panel.position
	toast_box.reset_size()
	toast_box.position = Vector2((vs.x - toast_box.size.x) * 0.5, vs.y - toast_box.size.y - 26)
	if not busy:
		if cur:
			cur.transform = _apps_xf(cur) if mode == "apps" else _center_xf(cur)
		if par:
			par.transform = _corner_xf(par)


func _set_hint(t: String) -> void:
	hint.text = t
	hint_box.reset_size()
	var vs := get_viewport().get_visible_rect().size
	hint_box.position.x = vs.x * (0.5 if mode == "apps" else 0.3475) - hint_box.size.x * 0.5


## Where a point of the screen lands on the plane z = `z` in the world.
func _world_at(screen: Vector2, z := 0.0) -> Vector3:
	var from := camera.project_ray_origin(screen)
	var dir := camera.project_ray_normal(screen)
	return from + dir * ((z - from.z) / dir.z)


func _center_xf(w) -> Transform3D:
	var vs := get_viewport().get_visible_rect().size
	var l := _world_at(Vector2(vs.x * 0.1, vs.y * 0.5))
	var r := _world_at(Vector2(vs.x * 0.585, vs.y * 0.5))
	var top := _world_at(Vector2(vs.x * 0.3425, vs.y * 0.25))
	var bot := _world_at(Vector2(vs.x * 0.3425, vs.y * 0.99))
	var ww := r.x - l.x
	var hh := top.y - bot.y
	var s := minf(minf(ww / w.width(), hh / w.height()), 0.95)
	w.view_h = hh / s
	w.cull_top = true
	w._cull()
	var pos := Vector3(l.x + ww * 0.5, top.y, 0.0)
	if w.height() * s < hh:
		pos.y -= (hh - w.height() * s) * 0.45
	return Transform3D(Basis.from_scale(Vector3.ONE * s), pos)


## The app roller uses nearly the whole width (no panel on the right).
func _apps_xf(w) -> Transform3D:
	var vs := get_viewport().get_visible_rect().size
	var l := _world_at(Vector2(vs.x * 0.07, vs.y * 0.5))
	var r := _world_at(Vector2(vs.x * 0.93, vs.y * 0.5))
	var top := _world_at(Vector2(vs.x * 0.5, vs.y * 0.24))
	var bot := _world_at(Vector2(vs.x * 0.5, vs.y * 0.99))
	var s := minf(minf((r.x - l.x) / w.width(), (top.y - bot.y) / w.height()), 0.85)
	var pos := Vector3((l.x + r.x) * 0.5, top.y, 0.0)
	if w.height() * s < top.y - bot.y:
		pos.y -= (top.y - bot.y - w.height() * s) * 0.4
	return Transform3D(Basis.from_scale(Vector3.ONE * s), pos)


## The folder you came from: far back behind the new drum, up and to the left, turned a little away.
## Perspective shrinks it; the new drum in front partly covers it.
func _corner_xf(w) -> Transform3D:
	var vs := get_viewport().get_visible_rect().size
	var depth := -7.0
	var s := clampf(6.5 / w.width(), 0.45, 1.0)
	var p := _world_at(Vector2(vs.x * 0.17, vs.y * 0.27), depth)
	w.view_h = 1000.0
	w.cull_top = false
	w._cull()
	return Transform3D(Basis(Vector3.UP, 0.32) * Basis.from_scale(Vector3.ONE * s), p)


func _screen_of(p: Vector3) -> Vector2:
	return camera.unproject_position(p)


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


# ---------------------------------------------------------------- navigation

func _parent_path(p: String) -> String:
	if p == "/":
		return ""
	var b := p.get_base_dir()
	return b if b != "" else "/"


func _make_wall(path: String):
	var w = Wall.new()
	w.item_script = Card3D
	w.folder_script = Cube       # folders stay cabinets, files become cards
	w.cell_w = 1.12
	w.gap = 0.08
	w.card_scale = 0.72
	world.add_child(w)
	w.build(path, FS.list_dir(path, show_hidden), ctx)
	return w


func _make_parent_for(path: String) -> void:
	var pp := _parent_path(path)
	if pp == "":
		par = null
		return
	par = _make_wall(pp)
	par.set_back(true)
	var cx := _corner_xf(par)
	par.transform = cx.translated(Vector3(-2.0, 0.5, -3.0))
	par.set_fade(0.0)
	par.move_to(cx, 0.65, 0.9)
	var me = par.cube_named(path.get_file())
	if me:
		par.scroll_to_cube(me, true)
		par.open_instant(me)


func _go_initial(path: String) -> void:
	cur = _make_wall(path)
	cur.transform = _center_xf(cur)
	cur.enter_rise()
	_make_parent_for(path)
	_header()
	_panel_idle()


func click_cube(c) -> void:
	if busy or c == null:
		return
	_peek_token += 1
	_hide_peek()
	if mode == "apps":
		c.bounce()
		Apps.launch(c.info)
		toast("Starting %s…" % c.info.name)
		busy = true
		await _wait(0.45)
		busy = false
		hide_drawers()
		return
	if c.wall == par:
		go_up()
		return
	if c.wall != cur:
		return
	if cur.open_cube == c:
		await _put_back()
		return
	busy = true
	if cur.open_cube:
		await close_drawer(true)
	# roll the drum so the chosen cube faces you before its drawer opens
	var before: float = cur.scroll_target
	# folders also slide to the middle; pictures only roll, so the preview on the right stays clear
	cur.scroll_to_cube(c, false, c.info.kind == "folder")
	if absf(cur.scroll_target - before) > 0.3:
		await _wait(0.35)
	var k: String = c.info.kind
	if k == "folder":
		cur.open(c)
		_set_hint("Opening %s…" % c.info.name)
		await _wait(0.45)
		busy = false
		await dive(c)
	elif k in ["image", "video"]:
		cur.open(c)
		_set_hint("Click it again to put it back.")
		await _wait(0.3)
		busy = false
		await _panel_preview(c)
	elif k == "more":
		busy = false
		OS.shell_open(cur.path)
	else:
		c.bounce()
		_open_file(c.info)
		busy = false


func close_drawer(quick := false) -> void:
	if cur == null or cur.open_cube == null:
		return
	await _panel_out(quick)
	await _wait(0.06)
	cur.close()
	_set_hint(HINT)
	_panel_idle()


func _put_back() -> void:
	if busy:
		return
	busy = true
	await close_drawer()
	busy = false


## Step into folder cube `c`: the old wall goes to the left edge, the folder's cubes spill out of its drawer.
func dive(c, then_open := "") -> void:
	if busy:
		return
	busy = true
	if state != "idle":
		await _panel_out(true)
	if cur.open_cube != c:
		cur.open(c)
		await _wait(0.35)
	var from_xf: Transform3D = c.drawer.global_transform
	var nw = _make_wall(c.info.path)
	nw.transform = _center_xf(nw)
	if par:
		par.leave()
	par = cur
	par.move_to(_corner_xf(par), 0.65, 0.95)
	# it goes out of focus once it is on its way, so the blur doesn't pop
	get_tree().create_timer(0.35).timeout.connect(par.set_back.bind(true))
	cur = nw
	cur.enter_from(from_xf)
	_header()
	_set_hint(HINT)
	_panel_idle()
	await _wait(0.9)
	busy = false
	if then_open != "":
		var t = cur.cube_named(then_open)
		if t:
			cur.scroll_to_cube(t)
			await _wait(0.25)
			await click_cube(t)


## Back to the parent: this wall's cubes fly back into their drawer, the parent slides back to the middle.
func go_up() -> void:
	if busy or cur == null:
		return
	if mode == "apps":
		hide_drawers()
		return
	var pp := _parent_path(cur.path)
	if pp == "":
		toast("This is as far up as it goes.")
		return
	if cur.path == root_path:
		root_path = pp
	busy = true
	if state != "idle":
		await _panel_out(true)
	if cur.open_cube:
		cur.close()
	if par == null or par.path != pp:
		if par:
			par.leave()
		par = _make_wall(pp)
		par.transform = _corner_xf(par)
		par.set_fade(0.0)
	var tc = par.cube_named(cur.path.get_file())
	var final_xf := _center_xf(par)
	if tc:
		par.scroll_to_cube(tc, true)
		if par.open_cube != tc:
			par.open_instant(tc)
	par.move_to(final_xf, 1.0, 0.95)
	get_tree().create_timer(0.45).timeout.connect(par.set_back.bind(false))
	var to_xf := final_xf
	if tc:
		to_xf = final_xf * par.drum_xf_of(tc) * Transform3D(Basis(), Vector3(0, Cube.OPEN_LIFT, Cube.OPEN_Z + Cube.DRAWER_OUT))
	cur.exit_into(to_xf)
	cur = par
	par = null
	_make_parent_for(cur.path)
	_header()
	await _wait(0.95)
	# the drawer we came back out of slides shut
	cur.close()
	_set_hint(HINT)
	_panel_idle()
	busy = false


func jump(path: String) -> void:
	if busy:
		return
	if cur and path == _parent_path(cur.path):
		go_up()
		return
	busy = true
	root_path = path
	if state != "idle":
		await _panel_out(true)
	if cur:
		cur.leave(0.5)
	if par:
		par.leave(0.5)
	cur = null
	par = null
	await _wait(0.3)
	_go_initial(path)
	await _wait(0.6)
	busy = false


func _open_file(it: Dictionary) -> void:
	if it.special:
		toast("“%s” is a special file, so there is nothing to open." % it.name)
		return
	OS.shell_open(it.path)
	toast("Opening “%s”…" % it.name)


# ---------------------------------------------------------------- header

func _header() -> void:
	for ch in crumbs.get_children():
		ch.queue_free()
	brand.text = ("MY APPS · %s" if mode == "apps" else "MY FILES · %s") % OS.get_environment("USER").capitalize()
	if mode == "apps":
		title.text = "Apps"
		hello.text = "%d apps on the roller. Click one to start it; scroll or drag to roll." % cur.items.size()
		_set_hint(APPS_HINT)
		return
	title.text = FS.display_name(cur.path)
	var segs := []   # [label, path]
	var home: String = FS.home()
	var rel := ""
	if cur.path == home or cur.path.begins_with(home + "/"):
		segs.append(["Home", home])
		rel = cur.path.substr(home.length())
		var acc := home
		for part in rel.split("/", false):
			acc = acc.path_join(part)
			segs.append([part, acc])
	else:
		segs.append(["Computer", "/"])
		var acc := "/"
		for part in cur.path.split("/", false):
			acc = acc.path_join(part)
			segs.append([part, acc])
	for i in segs.size():
		if i > 0:
			crumbs.add_child(_lbl("›", ctx.sans, 15, FS.MUTED))
		var b := Button.new()
		b.text = segs[i][0]
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.add_theme_font_override("font", ctx.sans_semi)
		b.add_theme_font_size_override("font_size", 15)
		var last := i == segs.size() - 1
		b.add_theme_color_override("font_color", FS.INK2 if last else FS.MUTED)
		b.add_theme_color_override("font_hover_color", FS.GOLD_INK)
		b.disabled = last
		b.add_theme_color_override("font_disabled_color", FS.INK2)
		b.pressed.connect(jump.bind(segs[i][1]))
		crumbs.add_child(b)
	var items: Array = cur.items
	if items.is_empty():
		hello.text = "Nothing lives here yet."
		return
	var newest = items[0]
	for it in items:
		if it.mtime > newest.mtime:
			newest = it
	hello.text = "%s live here: %s. The newest is “%s”, changed %s." % [
		FS.things(items.size()), FS.summary(items), newest.name, FS.ago(newest.mtime)]


# ---------------------------------------------------------------- right panel

func _clear_panel() -> void:
	if _video:
		_video.stop()
		_video = null
	for ch in pv.get_children():
		pv.remove_child(ch)
		ch.queue_free()
	pv.position = Vector2.ZERO
	pv.scale = Vector2.ONE
	pv.rotation = 0.0
	pv.modulate.a = 1.0


func _pill(text: String) -> PanelContainer:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = FS.GOLD_SOFT
	s.set_corner_radius_all(14)
	s.set_border_width_all(1)
	s.border_color = FS.GOLD.lerp(FS.GOLD_SOFT, 0.5)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 2
	s.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", s)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_child(_lbl(text, ctx.sans_semi, 14, FS.GOLD_INK))
	return p


func _button(text: String, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", ctx.sans_semi)
	b.add_theme_font_size_override("font_size", 15)
	for st in ["normal", "hover", "pressed", "disabled"]:
		var s := StyleBoxFlat.new()
		s.bg_color = Color("#e9b84a") if primary else FS.CARD
		if st == "pressed":
			s.bg_color = s.bg_color.darkened(0.08)
		s.set_corner_radius_all(20)
		s.set_border_width_all(1)
		s.border_color = Color("#c4901a") if primary else (FS.GOLD if st == "hover" else FS.HAIR)
		s.content_margin_left = 18
		s.content_margin_right = 18
		s.content_margin_top = 8
		s.content_margin_bottom = 9
		s.shadow_color = Color(0.35, 0.24, 0.08, 0.08)
		s.shadow_size = 4
		s.shadow_offset = Vector2(0, 2)
		b.add_theme_stylebox_override(st, s)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(c, FS.INK)
	return b


func _head(name: String, pill: String) -> HBoxContainer:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var t := _lbl(name if name.length() <= 42 else name.left(40) + "…", ctx.serif, 30, FS.INK)
	head.add_child(t)
	head.add_child(_pill(pill))
	return head


## A cream paper card in the right panel; returns the VBox to fill.
func _card_box() -> VBoxContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", paper_style(20, 22, 16))
	card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	pv.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	card.add_child(v)
	return v


func _note(text: String) -> void:
	var v := _card_box()
	v.add_child(_lbl(text, ctx.sans, 15, FS.INK2))


func _panel_idle() -> void:
	_clear_panel()
	state = "idle"
	panel_cube = null
	if cur == null or mode == "apps":
		return
	var n: int = cur.items.size()
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_font_override("normal_font", ctx.serif)
	r.add_theme_font_override("bold_font", ctx.serif_med)
	r.add_theme_font_size_override("normal_font_size", 21)
	r.add_theme_font_size_override("bold_font_size", 21)
	r.add_theme_color_override("default_color", FS.INK)
	if n == 0:
		r.text = "[b]%s[/b] is empty. Click the wall on the left to go back." % FS.display_name(cur.path)
	else:
		r.text = "[b]%s[/b] has [color=#b8862a][b]%d[/b][/color] thing%s. Click a folder to go in, a picture to see it." % [
			FS.display_name(cur.path), n, "" if n == 1 else "s"]
	var box := _card_box()
	r.custom_minimum_size.x = minf(panel.size.x - 60, 620)
	box.add_child(r)
	var tips := _lbl("Scroll or drag to roll the drum  ·  click the background (or Esc) to go back  ·  Ctrl+H shows hidden files",
		ctx.sans, 14, FS.MUTED)
	tips.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tips.custom_minimum_size.x = r.custom_minimum_size.x
	box.add_child(tips)
	pv.modulate.a = 0.0
	create_tween().tween_property(pv, "modulate:a", 1.0, 0.35)


func _panel_preview(c) -> void:
	_clear_panel()
	state = "preview"
	panel_cube = c
	var it: Dictionary = c.info
	var box := _card_box()
	box.add_child(_head(it.name, FS.kind_info(it.kind).label))
	var sub := _lbl("%s · %s · changed %s" % [it.ext.to_upper(), FS.human_size(it.size), FS.ago(it.mtime)], ctx.sans, 16, FS.INK2)
	box.add_child(sub)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 10)
	var open := _button("Open", true)
	open.pressed.connect(_open_file.bind(it))
	btns.add_child(open)
	var show := _button("Show in Files")
	show.pressed.connect(func(): OS.shell_show_in_file_manager(it.path))
	btns.add_child(show)
	var back := _button("Put it back")
	back.pressed.connect(_put_back)
	btns.add_child(back)
	box.add_child(btns)

	var frame := PanelContainer.new()
	var fs := StyleBoxFlat.new()
	fs.bg_color = Color("#1d1420") if it.kind == "video" else Color("#efe6d8")
	fs.set_corner_radius_all(18)
	fs.shadow_color = Color(0.35, 0.24, 0.08, 0.16)
	fs.shadow_size = 18
	fs.shadow_offset = Vector2(0, 8)
	frame.add_theme_stylebox_override("panel", fs)
	frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	frame.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var arc := AspectRatioContainer.new()
	var tex: Texture2D = c.thumb_tex
	arc.ratio = float(tex.get_width()) / tex.get_height() if tex else 16.0 / 9.0
	frame.add_child(arc)
	_fit_frame(frame, arc.ratio)
	var stack := Control.new()
	arc.add_child(stack)
	var rect := TextureRect.new()
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(rect)
	var note := _lbl("", ctx.serif, 19, Color(1, 1, 1, 0.95))
	note.set_anchors_preset(Control.PRESET_FULL_RECT)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	note.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	note.add_theme_constant_override("shadow_offset_y", 2)
	stack.add_child(note)
	pv.add_child(frame)
	var foot := Control.new()
	foot.custom_minimum_size.y = 24
	pv.add_child(foot)

	if it.kind == "image":
		thumbs.load_full(it, _on_full_image.bind(c, rect, arc, sub))
	else:
		note.text = "Making a preview…"
		var sound := _button("Sound off")
		sound.pressed.connect(_toggle_sound.bind(sound))
		btns.add_child(sound)
		thumbs.make_video_preview(it, _on_video_ready.bind(c, stack, note))

	await get_tree().process_frame
	await get_tree().process_frame
	if state == "preview" and panel_cube == c:
		_fly_block(_screen_of(c.front_point()), true)


func _on_full_image(tex: Texture2D, img: Image, c, rect: TextureRect, arc: AspectRatioContainer, sub: Label) -> void:
	if tex == null or panel_cube != c or not is_instance_valid(rect):
		return
	rect.texture = tex
	arc.ratio = float(img.get_width()) / img.get_height()
	_fit_frame(arc.get_parent(), arc.ratio)
	sub.text += " · %d × %d" % [img.get_width(), img.get_height()]


## The preview frame takes the picture's own shape, as large as the panel allows.
func _fit_frame(frame: Control, ratio: float) -> void:
	var h := minf(panel.size.x / ratio, panel.size.y - 170.0)
	frame.custom_minimum_size = Vector2(h * ratio, h)


func _on_video_ready(path: String, c, stack: Control, note: Label) -> void:
	if panel_cube != c or not is_instance_valid(stack):
		return
	if path == "":
		note.text = "No preview for this one. Press Open to watch it."
		return
	var vp := VideoStreamPlayer.new()
	var vs := VideoStreamTheora.new()
	vs.file = path
	vp.stream = vs
	vp.expand = true
	vp.loop = true
	vp.volume_db = -80.0
	vp.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(vp)
	stack.move_child(note, -1)
	vp.play()
	note.text = ""
	_video = vp


func _toggle_sound(b: Button) -> void:
	if _video == null:
		return
	var on := _video.volume_db < -40.0
	_video.volume_db = 0.0 if on else -80.0
	b.text = "Sound on" if on else "Sound off"


## The cards (or the preview) go back into the drawer.
func _panel_out(quick := false) -> void:
	if state == "preview" and panel_cube:
		await _fly_block(_screen_of(panel_cube.front_point()), false, quick).finished
	_clear_panel()
	state = "idle"


func _fly_block(cube_pt: Vector2, coming_in: bool, quick := false) -> Tween:
	var rest := pv.get_global_rect().get_center()
	var sz := pv.size
	var keys: Array
	var knee: float
	var bz: Array
	var dur: float
	if coming_in:
		keys = [[cube_pt, 0.14, 0.0, 0.0], [rest.lerp(cube_pt, 0.78) + Vector2(0, -140), 0.42, deg_to_rad(-4.0), 1.0], [rest, 1.0, 0.0, 1.0]]
		knee = 0.38
		bz = [0.25, 0.8, 0.25, 1.0]
		dur = 0.75
	else:
		keys = [[rest, 1.0, 0.0, 1.0], [rest + (cube_pt - rest) * 0.8 + Vector2(0, -120), 0.4, 0.0, 1.0], [cube_pt, 0.1, 0.0, 0.0]]
		knee = 0.55
		bz = [0.5, 0.0, 0.6, 1.0]
		dur = 0.36 if quick else 0.56
	_block_pose(0.0, keys, knee, rest, bz, sz)
	var tw := create_tween()
	tw.tween_method(_block_pose.bind(keys, knee, rest, bz, sz), 0.0, 1.0, dur)
	return tw


func _block_pose(t: float, keys: Array, knee: float, rest: Vector2, bz: Array, sz: Vector2) -> void:
	var e := FS.bezier(t, bz[0], bz[1], bz[2], bz[3])
	var a: Array = keys[0] if e < knee else keys[1]
	var b: Array = keys[1] if e < knee else keys[2]
	var u := e / knee if e < knee else (e - knee) / (1.0 - knee)
	var s: float = lerpf(a[1], b[1], u)
	pv.pivot_offset = Vector2(sz.x * 0.5, sz.y)
	pv.scale = Vector2(s, s)
	pv.rotation = lerpf(a[2], b[2], u)
	pv.modulate.a = lerpf(a[3], b[3], u)
	var center: Vector2 = a[0].lerp(b[0], u)
	pv.position = center - rest - Vector2(0, sz.y * 0.5 * (1.0 - s))


func toast(text: String) -> void:
	toast_lbl.text = text
	_layout()
	if _toast_tw:
		_toast_tw.kill()
	_toast_tw = create_tween()
	_toast_tw.tween_property(toast_box, "modulate:a", 1.0, 0.25)
	_toast_tw.tween_interval(2.4)
	_toast_tw.tween_property(toast_box, "modulate:a", 0.0, 0.5)


# ---------------------------------------------------------------- input

# ---------------------------------------------------------------- hover preview

func _peek_after(token: int, c) -> void:
	if token == _peek_token and is_instance_valid(c) and state == "idle" and is_shown:
		_show_peek(c)


func _show_peek(c) -> void:
	if c == null or not is_instance_valid(c):
		return
	_peek_for = c
	var it: Dictionary = c.info
	for ch in _peek_v.get_children():
		_peek_v.remove_child(ch)
		ch.queue_free()
	var w := minf(panel.size.x, 640.0)
	peek.custom_minimum_size.x = w
	var t := _lbl(it.name, ctx.serif, 24, FS.INK)
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.custom_minimum_size.x = w - 44
	t.clip_text = true
	_peek_v.add_child(t)
	var kind: String = FS.kind_info(it.kind).label
	_peek_v.add_child(_lbl("%s%s · %s · changed %s" % [kind, (" · " + it.ext.to_upper()) if it.ext != "" else "",
		FS.human_size(it.size), FS.ago(it.mtime)], ctx.sans, 15, FS.INK2))

	if it.kind in ["image", "video", "pdf"]:
		var tex: Texture2D = _full_cache.get(it.path, c.thumb_tex)
		var ratio := float(tex.get_width()) / tex.get_height() if tex else 1.5
		var h := minf((w - 44) / ratio, panel.size.y * 0.62)
		var frame := Panel.new()
		var fs := StyleBoxFlat.new()
		fs.bg_color = Color("#1d1420") if it.kind == "video" else Color("#efe6d8")
		fs.set_corner_radius_all(14)
		frame.add_theme_stylebox_override("panel", fs)
		frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		frame.custom_minimum_size = Vector2(h * ratio, h)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rect := TextureRect.new()
		rect.texture = tex
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		frame.add_child(rect)
		_peek_v.add_child(frame)
		if it.kind == "image" and not _full_cache.has(it.path):
			thumbs.load_full(it, _peek_full.bind(c, rect))
		_peek_v.add_child(_lbl("Click to play it" if it.kind == "video" else "Click to see it bigger" if it.kind == "image" else "Click to open it",
			ctx.sans, 14, FS.MUTED))
	elif it.kind in ["text", "code"] and not it.special:
		var lines := _first_lines(it.path, 26, 92)
		var well := PanelContainer.new()
		var ws := StyleBoxFlat.new()
		ws.bg_color = Color("#f4ede1")
		ws.set_corner_radius_all(10)
		ws.content_margin_left = 14
		ws.content_margin_right = 14
		ws.content_margin_top = 10
		ws.content_margin_bottom = 10
		well.add_theme_stylebox_override("panel", ws)
		well.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var code := _lbl(lines if lines != "" else "(this file looks empty)", ctx.mono, 13, FS.INK2)
		code.custom_minimum_size.x = w - 72
		code.clip_text = true
		well.add_child(code)
		_peek_v.add_child(well)
		_peek_v.add_child(_lbl("Click to open it", ctx.sans, 14, FS.MUTED))
	else:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var ic := TextureRect.new()
		ic.texture = FS.icon_for(it)
		ic.custom_minimum_size = Vector2(72, 72)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(ic)
		row.add_child(_lbl("Click to open it in its app.", ctx.serif, 18, FS.INK2))
		_peek_v.add_child(row)

	peek.reset_size()
	peek.visible = true
	if _peek_tw:
		_peek_tw.kill()
	_peek_tw = create_tween().set_parallel()
	_peek_tw.tween_property(peek, "modulate:a", 1.0, 0.2)
	_peek_tw.tween_property(pv, "modulate:a", 0.0, 0.2)


func _peek_full(tex: Texture2D, _img: Image, c, rect: TextureRect) -> void:
	if tex == null:
		return
	_full_cache[c.info.path] = tex
	_full_order.append(c.info.path)
	if _full_order.size() > 24:
		_full_cache.erase(_full_order.pop_front())
	if _peek_for == c and is_instance_valid(rect):
		rect.texture = tex


func _hide_peek() -> void:
	_peek_for = null
	if not peek.visible:
		return
	if _peek_tw:
		_peek_tw.kill()
	_peek_tw = create_tween().set_parallel()
	_peek_tw.tween_property(peek, "modulate:a", 0.0, 0.18)
	_peek_tw.tween_property(pv, "modulate:a", 1.0, 0.25)
	_peek_tw.chain().tween_callback(func(): peek.visible = peek.modulate.a > 0.01)


## The start of a text file, for the hover preview (binary files give "").
func _first_lines(path: String, n: int, width: int) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var buf := f.get_buffer(6000)
	if buf.find(0) != -1:
		return ""
	var out := []
	for line in buf.get_string_from_utf8().split("\n"):
		if out.size() >= n:
			break
		line = line.replace("\t", "    ")
		out.append(line if line.length() <= width else line.left(width - 1) + "…")
	return "\n".join(out)


## Clicking the blurred desktop: back to the parent, and from where you started, close everything.
func _background_click() -> void:
	if busy or not is_shown or cur == null:
		return
	if mode == "apps":
		hide_drawers()
		return
	if cur.path != root_path:
		go_up()
	elif cur.open_cube:
		_put_back()
	else:
		hide_drawers()


func _pick(pos: Vector2):
	var from := camera.project_ray_origin(pos)
	var q := PhysicsRayQueryParameters3D.create(from, from + camera.project_ray_normal(pos) * 200.0)
	var hit := world.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or not hit.collider.has_meta("cube"):
		return null
	var c = hit.collider.get_meta("cube")
	if is_instance_valid(c) and (c.wall == cur or c.wall == par):
		return c
	return null


func _drum_at(_pos: Vector2):
	return cur


func _update_hover(pos: Vector2) -> void:
	var c = _pick(pos)
	if c == _hover_cube:
		return
	# resting on a file for a moment shows a preview on the right
	_peek_token += 1
	if c and mode == "files" and c.wall == cur and not c.info.is_dir and c.info.kind != "more" and state == "idle":
		get_tree().create_timer(0.3).timeout.connect(_peek_after.bind(_peek_token, c))
	else:
		_hide_peek()
	if _hover_cube and is_instance_valid(_hover_cube):
		_hover_cube.set_hover(false)
	_hover_cube = c
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if c else Input.CURSOR_ARROW)
	if c == null:
		_set_hint(APPS_HINT if mode == "apps" else HINT)
	elif c.wall == par:
		_set_hint("Back to %s" % FS.display_name(par.path))
	elif mode == "apps":
		c.set_hover(true)
		_set_hint(c.info.name + ("  ·  " + c.info.comment if c.info.comment != "" else ""))
	else:
		c.set_hover(true)
		_set_hint("%s  ·  %s" % [c.info.name, FS.item_meta(c.info)])


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _pressing and _drum_at(_press) and event.position.distance_to(_press) > 7.0:
			_dragging = true
		if _dragging:
			var dr = _drum_at(_press)
			if dr:
				var d: float = -event.relative.y * 0.022
				dr.scroll_by(d)
				_drag_v = lerpf(_drag_v, d, 0.5)
			return
		_update_hover(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if _pressing and not _dragging:
			var c = _pick(event.position)
			if c:
				click_cube(c)
			else:
				_background_click()
		elif _dragging and _drum_at(_press):
			var dr = _drum_at(_press)
			dr.scroll_by(_drag_v * 9.0)   # spin on
		_pressing = false
		_dragging = false
		_drag_v = 0.0
	elif event is InputEventMouseButton and event.pressed:
		var vs := get_viewport().get_visible_rect().size
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if not event.double_click:
					_press = event.position
					_pressing = true
					_dragging = false
			MOUSE_BUTTON_WHEEL_UP:
				if _drum_at(event.position):
					_drum_at(event.position).scroll_by(-0.6)
			MOUSE_BUTTON_WHEEL_DOWN:
				if _drum_at(event.position):
					_drum_at(event.position).scroll_by(0.6)
			MOUSE_BUTTON_XBUTTON1:
				go_up()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_BACKSPACE or (event.keycode == KEY_LEFT and event.alt_pressed):
			go_up()
		elif event.keycode == KEY_ESCAPE:
			_background_click()
		elif mode == "apps":
			pass
		elif event.keycode == KEY_H and event.ctrl_pressed:
			show_hidden = not show_hidden
			toast("Showing hidden files" if show_hidden else "Hiding hidden files")
			if cur:
				var p: String = cur.path
				busy = false
				jump(p)
		elif event.keycode == KEY_F5 and cur:
			jump(cur.path)


# ---------------------------------------------------------------- scripted runs (for testing)
# DRAWERS_SCRIPT="wait 2; open Documents; wait 2; snap /tmp/a.png; card Notes; wait 2; up; quit"

func _run_script(src: String) -> void:
	for raw in src.split(";", false):
		var cmd := raw.strip_edges()
		var op := cmd.get_slice(" ", 0)
		var arg := cmd.substr(op.length()).strip_edges()
		print("[drawers] ", cmd)
		match op:
			"wait":
				await _wait(arg.to_float())
			"open":
				await click_cube(cur.cube_named(arg))
			"go":
				click_cube(cur.cube_named(arg))
			"hover":
				_show_peek(cur.cube_named(arg))
			"dive":
				await dive(cur.open_cube)
			"up":
				await go_up()
			"cd":
				await jump(arg)
			"snap":
				get_tree().root.get_texture().get_image().save_png(arg)
			"close":
				await hide_drawers()
			"back":
				_background_click()
			"scroll":
				cur.scroll_target = clampf(arg.to_float(), 0.0, cur.max_scroll())
			"quit":
				get_tree().quit()
