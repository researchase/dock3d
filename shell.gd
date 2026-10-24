extends Control
## The launcher: one transparent, borderless, always-on-top window over the whole screen.
## The dock sits at the bottom. Its Drawers icon raises the 3D file drawers over a blurred
## picture of the desktop; with the drawers closed, only the dock catches the mouse.

const Dock = preload("res://dock.gd")
const Drawers = preload("res://drawers/drawers.gd")
const BLUR = preload("res://blur.gdshader")
const SOFT = preload("res://soft.gdshader")

const DOCK_W := 1800
const DOCK_H := 330
const DOCK_DROP := 40        # the dock's picture has room under the shelf; push that off the bottom edge
const HIDE_SLIDE := 190.0    # how far the dock slides down when it hides

var dock
var drawers
var dock_box: SubViewportContainer
var drawers_box: SubViewportContainer
var blur: TextureRect
var blur_mat: ShaderMaterial
var back_layer: TextureRect
var is_open := false
var _open_what := ""        # drawers | apps
var _queued := ""           # open this next, once the current view has gone back down
var _last_pass := PackedVector2Array()
var _blur_tw: Tween

# auto-hide: a thread watches where other windows are; the dock slides away when one covers it
var _watch: Thread
var _watch_quit := false
var _watch_mutex := Mutex.new()
var _dock_screen_rect := Rect2()   # where the dock shelf is on screen (written by main, read by thread)
var _covered := false              # a window overlaps the dock (written by thread)
var _hide := 0.0                   # 0 shown .. 1 hidden
var _hide_hold := 0.0              # seconds to wait before hiding again after the mouse leaves


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	get_viewport().transparent_bg = true
	var scr := DisplayServer.get_primary_screen()
	# the work area: below GNOME's top bar and beside its own dock, which stay on top anyway
	var srect := DisplayServer.screen_get_usable_rect(scr)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	# one pixel short, so the compositor never treats it as a fullscreen game
	DisplayServer.window_set_size(srect.size - Vector2i(0, 1))
	DisplayServer.window_set_position(srect.position)

	blur = TextureRect.new()
	blur.set_anchors_preset(PRESET_FULL_RECT)
	blur.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	blur.stretch_mode = TextureRect.STRETCH_SCALE
	blur.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	blur.mouse_filter = MOUSE_FILTER_IGNORE
	blur_mat = ShaderMaterial.new()
	blur_mat.shader = BLUR
	blur_mat.set_shader_parameter("amount", 0.0)
	blur.material = blur_mat
	blur.visible = false
	add_child(blur)

	drawers_box = _view(Rect2(Vector2.ZERO, Vector2(100, 100)))
	drawers = Drawers.new()
	drawers_box.get_child(0).add_child(drawers)
	# the parent folder's wall, out of focus, between the blurred desktop and the drawers
	back_layer = TextureRect.new()
	back_layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back_layer.stretch_mode = TextureRect.STRETCH_SCALE
	back_layer.mouse_filter = MOUSE_FILTER_IGNORE
	back_layer.texture = drawers.back_vp.get_texture()
	var sm := ShaderMaterial.new()
	sm.shader = SOFT
	back_layer.material = sm
	add_child(back_layer)
	move_child(back_layer, drawers_box.get_index())
	drawers.closed.connect(_on_drawers_closed)
	_set_drawers_live(false)

	dock_box = _view(Rect2(Vector2.ZERO, Vector2(DOCK_W, DOCK_H)))
	dock = Dock.new()
	dock.embedded = true
	dock.mouse_in = false
	dock_box.get_child(0).add_child(dock)
	dock.builtin.connect(_on_builtin)
	get_window().files_dropped.connect(_on_files_dropped)
	dock_box.mouse_entered.connect(func(): dock.mouse_in = true)
	dock_box.mouse_exited.connect(func(): dock.mouse_in = false)

	get_viewport().size_changed.connect(_layout)
	_layout()
	_watch = Thread.new()
	_watch.start(_watch_windows)
	# _NET_WM_WINDOW_TYPE_DOCK: no taskbar / alt-tab entry, stays above windows
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() == "X11":
		var wid := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE)
		OS.execute("xprop", ["-id", str(wid), "-f", "_NET_WM_WINDOW_TYPE", "32a",
			"-set", "_NET_WM_WINDOW_TYPE", "_NET_WM_WINDOW_TYPE_DOCK"])
		DisplayServer.window_set_position(srect.position)
	if OS.has_environment("DOCK_DROP"):   # tests: pretend these files were dropped on the dock
		_on_files_dropped(OS.get_environment("DOCK_DROP").split(":"))
	if OS.has_environment("DRAWERS_SCRIPT"):
		open_drawers("", OS.get_environment("DRAWERS_MODE") if OS.has_environment("DRAWERS_MODE") else "drawers")


## GNOME keeps the window inside the work area (below the top bar, beside its own dock),
## so everything is laid out from the window's real size, not the screen's.
func _layout() -> void:
	var ws := get_viewport().get_visible_rect().size
	var dw := minf(ws.x, DOCK_W)
	dock_box.position = Vector2((ws.x - dw) * 0.5, ws.y - DOCK_H + DOCK_DROP + _hide * HIDE_SLIDE)
	dock_box.size = Vector2(dw, DOCK_H)
	drawers_box.position = Vector2.ZERO
	drawers_box.size = Vector2(ws.x, ws.y - DOCK_H)
	back_layer.position = drawers_box.position
	back_layer.size = drawers_box.size
	_last_pass = PackedVector2Array()


func _exit_tree() -> void:
	_watch_quit = true
	if _watch and _watch.is_started():
		_watch.wait_to_finish()


## Every ~0.6 s: is any normal, visible window on this workspace overlapping the dock?
func _watch_windows() -> void:
	# a script file, not "sh -c": Godot's execute() would swallow the $variables
	var script := ProjectSettings.globalize_path("res://scripts/visible_windows.sh")
	while not _watch_quit:
		var out := []
		OS.execute("sh", [script], out)
		_watch_mutex.lock()
		var dock_r := _dock_screen_rect
		_watch_mutex.unlock()
		var hit := false
		for line in "".join(out).split("\n", false):
			var f := line.split(" ", false)
			if f.size() == 4 and dock_r.size.x > 0.0:
				if Rect2(f[0].to_float(), f[1].to_float(), f[2].to_float(), f[3].to_float()).intersects(dock_r):
					hit = true
					break
		_covered = hit
		for i in 6:
			if _watch_quit:
				return
			OS.delay_msec(100)


func _view(r: Rect2) -> SubViewportContainer:
	var box := SubViewportContainer.new()
	box.position = r.position
	box.size = r.size
	box.stretch = true
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_2X
	box.add_child(vp)
	add_child(box)
	return box


func _set_drawers_live(on: bool) -> void:
	drawers_box.visible = on
	back_layer.visible = on
	drawers.back_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	var vp: SubViewport = drawers_box.get_child(0)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	drawers.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


## .desktop files dragged onto the dock become dock apps.
func _on_files_dropped(files: PackedStringArray) -> void:
	for f in files:
		if f.ends_with(".desktop"):
			dock.add_dropped(f)


## Slide the dock away while a window covers it; bring it back when the mouse touches the bottom edge.
func _auto_hide(delta: float) -> void:
	var ws := get_viewport().get_visible_rect().size
	var base_y := ws.y - DOCK_H + DOCK_DROP
	var shelf: Rect2 = dock.interactive_rect
	shelf.position += Vector2(dock_box.position.x, base_y)
	var win := Vector2(DisplayServer.window_get_position())
	_watch_mutex.lock()
	_dock_screen_rect = Rect2(shelf.position + win, shelf.size)
	_watch_mutex.unlock()

	var m := Vector2(DisplayServer.mouse_get_position()) - win
	var over_dock := shelf.grow(24).has_point(m) and _hide < 0.5
	var at_edge := m.y >= ws.y - 3.0 and m.x >= shelf.position.x and m.x <= shelf.end.x
	if over_dock or at_edge or is_open or not _covered:
		_hide_hold = 0.7 if _covered else 0.0
	else:
		_hide_hold -= delta
	var want := 1.0 if (_covered and _hide_hold <= 0.0 and not is_open) else 0.0
	if not is_equal_approx(_hide, want):
		_hide = move_toward(_hide, want, delta / 0.28)
		var e := _hide * _hide * (3.0 - 2.0 * _hide)
		dock_box.position.y = base_y + e * HIDE_SLIDE
		dock.mouse_in = dock.mouse_in and _hide < 0.5


func _on_builtin(what: String) -> void:
	if what != "drawers" and what != "apps":
		return
	if is_open:
		# same icon closes; the other one swaps over once this view has gone
		_queued = "" if what == _open_what else what
		drawers.hide_drawers()
	else:
		open_drawers("", what)


func open_drawers(path := "", what := "drawers") -> void:
	if is_open:
		return
	is_open = true
	_open_what = what
	# a picture of the desktop as it is right now, before anything appears over it
	var img: Image
	if OS.has_environment("DRAWERS_FAKE_DESKTOP"):   # tests: a stand-in wallpaper instead of the real screen
		img = Image.load_from_file(OS.get_environment("DRAWERS_FAKE_DESKTOP"))
	else:
		var scr := DisplayServer.get_primary_screen()
		img = DisplayServer.screen_get_image(scr)
		if img:
			# just the part of the screen under our window
			var off := DisplayServer.window_get_position() - DisplayServer.screen_get_position(scr)
			var r := Rect2i(off, DisplayServer.window_get_size()).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
			if r.size.x > 0 and r.size.y > 0:
				img = img.get_region(r)
	if img:
		img.generate_mipmaps()
		blur.texture = ImageTexture.create_from_image(img)
	blur.visible = img != null
	_tween_blur(1.0, 0.45)
	DisplayServer.window_set_mouse_passthrough(PackedVector2Array())   # the whole screen is ours now
	_last_pass = PackedVector2Array()
	_set_drawers_live(true)
	dock.forced_running["Apps" if what == "apps" else "Drawers"] = true
	DisplayServer.window_move_to_foreground()
	if what == "apps":
		drawers.show_apps()
	else:
		drawers.show_drawers(path)


func _on_drawers_closed() -> void:
	is_open = false
	dock.forced_running.erase("Drawers")
	dock.forced_running.erase("Apps")
	if _queued != "":
		var next := _queued
		_queued = ""
		open_drawers("", next)
		return
	_tween_blur(0.0, 0.35)
	await _blur_tw.finished
	if not is_open:
		blur.visible = false
		blur.texture = null
		_set_drawers_live(false)


func _tween_blur(to: float, dur: float) -> void:
	if _blur_tw:
		_blur_tw.kill()
	_blur_tw = create_tween()
	_blur_tw.tween_property(blur_mat, "shader_parameter/amount", to, dur) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_auto_hide(delta)
	Engine.max_fps = 60 if (is_open or dock.hovering or dock.animating or (_hide > 0.0 and _hide < 1.0)) else 15
	if is_open:
		return
	# drawers closed: only the dock catches the mouse (nothing at all while it is hidden)
	var r: Rect2 = dock.interactive_rect
	r.position += dock_box.position
	r = r.intersection(Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size))
	if _hide > 0.98 or r.size.x < 1.0 or r.size.y < 1.0:
		r = Rect2(0, 0, 1, 1)
	var poly := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	if poly != _last_pass:
		_last_pass = poly
		DisplayServer.window_set_mouse_passthrough(poly)
