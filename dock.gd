extends Node3D
## A transparent, borderless, always-on-top 3D dock for Linux (X11).
## Reads app ids from apps.cfg, resolves real .desktop files + theme icons,
## magnifies under the cursor, and launches the real app with gtk-launch.

const ICON_SIZE := 1.0
const GAP := 0.2
const MAX_SCALE := 1.85        # magnification at the cursor
const INFLUENCE := 2.6         # how far (world units) magnification spreads
const SHELF_DEPTH := 2.2
const SHELF_THICK := 0.1
const WINDOW_H := 330
const MARK_AS_X11_DOCK := true # sets _NET_WM_WINDOW_TYPE_DOCK: no taskbar / alt-tab entry
const WATERCOLOR := false      # true = painted watercolor style instead of Mac-like glass
const Apps = preload("res://desktop_apps.gd")


var apps: Array = []         # Array of Dictionary
var camera: Camera3D
var shelf: MeshInstance3D
var shelf_edge: MeshInstance3D
var tooltip: Label3D
var hovering := false
var mouse_world_x := 0.0
var hovered_idx := -1
var shelf_width := 0.0

var _running_classes: Dictionary = {}
var _running_mutex := Mutex.new()
var _poll_thread: Thread
var _quit := false

var _style := "res://watercolor/" if WATERCOLOR else "res://"
var icon_shader: Shader = load(_style + ("icon.gdshader" if WATERCOLOR else "icon_glass.gdshader"))
var shelf_shader: Shader = load(_style + ("shelf.gdshader" if WATERCOLOR else "shelf_glass.gdshader"))
var dot_shader: Shader = load(_style + ("dot.gdshader" if WATERCOLOR else "dot_glass.gdshader"))
var edge_shader: Shader = load(_style + ("edge.gdshader" if WATERCOLOR else "edge_glass.gdshader"))
var _fake_hover_x = null   # DOCK_FAKE_HOVER=<world x> for testing without a mouse

signal builtin(what: String)   # an "@name" launcher in apps.cfg was clicked (e.g. @drawers)
var embedded := false          # true inside the launcher shell, which owns the window
var mouse_in := true           # the shell tells us when the mouse leaves our area
var forced_running := {}       # app name -> true: show the running light (built-ins)
var interactive_rect := Rect2()
var animating := false


func _ready() -> void:
	if not embedded:
		_setup_window()
	_setup_scene()
	_load_apps()
	_build_icons()
	shelf_width = _layout_width(_target_scales()) + 0.8
	_poll_thread = Thread.new()
	_poll_thread.start(_poll_running)
	if OS.has_environment("DOCK_FAKE_HOVER"):
		_fake_hover_x = OS.get_environment("DOCK_FAKE_HOVER").to_float()
	if OS.has_environment("DOCK_SNAPSHOT"):
		_snapshot(OS.get_environment("DOCK_SNAPSHOT"))
	# X11 window properties must be set once the window is mapped
	await get_tree().process_frame
	await get_tree().process_frame
	if MARK_AS_X11_DOCK and not embedded and DisplayServer.get_name() == "X11":
		var wid := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE)
		OS.execute("xprop", ["-id", str(wid), "-f", "_NET_WM_WINDOW_TYPE", "32a",
			"-set", "_NET_WM_WINDOW_TYPE", "_NET_WM_WINDOW_TYPE_DOCK"])
		_place_window()


func _exit_tree() -> void:
	_quit = true
	if _poll_thread and _poll_thread.is_started():
		_poll_thread.wait_to_finish()


# ---------------------------------------------------------------- window

func _setup_window() -> void:
	get_viewport().transparent_bg = true
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	_place_window()


func _place_window() -> void:
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var w := mini(usable.size.x, 1800)
	DisplayServer.window_set_size(Vector2i(w, WINDOW_H))
	DisplayServer.window_set_position(Vector2i(
		usable.position.x + (usable.size.x - w) / 2,
		usable.position.y + usable.size.y - WINDOW_H))


func _update_passthrough() -> void:
	# Only the shelf + icons capture the mouse; everything else clicks through.
	var half := shelf_width * 0.5
	var top_y := 0.0
	for a in apps:
		top_y = maxf(top_y, a.bounce + ICON_SIZE * a.scale)
	if hovering:
		top_y += 0.15
	var pts := [
		Vector3(-half, -SHELF_THICK, SHELF_DEPTH * 0.5),
		Vector3(half, -SHELF_THICK, SHELF_DEPTH * 0.5),
		Vector3(-half, top_y, 0.0),
		Vector3(half, top_y, 0.0),
	]
	var r := Rect2(camera.unproject_position(pts[0]), Vector2.ZERO)
	for p in pts:
		r = r.expand(camera.unproject_position(p))
	r = r.grow(4)
	var vp_size := get_viewport().get_visible_rect().size
	r.end.y = vp_size.y
	interactive_rect = r
	if embedded:
		return
	var win_size := Vector2(DisplayServer.window_get_size())
	var k := win_size / vp_size
	DisplayServer.window_set_mouse_passthrough(PackedVector2Array([
		r.position * k, Vector2(r.end.x, r.position.y) * k,
		r.end * k, Vector2(r.position.x, r.end.y) * k]))


# ---------------------------------------------------------------- scene

func _setup_scene() -> void:
	camera = Camera3D.new()
	camera.fov = 30.0
	camera.position = Vector3(0, 6.2, 9.6)
	add_child(camera)
	camera.look_at(Vector3(0, 1.55, 0))

	var mat := ShaderMaterial.new()
	mat.shader = shelf_shader
	mat.render_priority = -1
	shelf = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1, SHELF_THICK, SHELF_DEPTH)
	shelf.mesh = box
	shelf.material_override = mat
	shelf.position = Vector3(0, -SHELF_THICK * 0.5, 0)
	add_child(shelf)

	# highlight along the front top edge
	var edge_mat := ShaderMaterial.new()
	edge_mat.shader = edge_shader
	edge_mat.render_priority = 0
	shelf_edge = MeshInstance3D.new()
	var edge := BoxMesh.new()
	edge.size = Vector3(1, 0.03, 0.03)
	shelf_edge.mesh = edge
	shelf_edge.material_override = edge_mat
	shelf_edge.position = Vector3(0, 0.0, SHELF_DEPTH * 0.5)
	add_child(shelf_edge)

	tooltip = Label3D.new()
	tooltip.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tooltip.font_size = 44
	tooltip.pixel_size = 0.0055
	tooltip.outline_size = 18
	tooltip.modulate = Color(0.2, 0.17, 0.32) if WATERCOLOR else Color(1, 1, 1)
	tooltip.outline_modulate = Color(0.98, 0.95, 0.88, 0.8) if WATERCOLOR else Color(0.05, 0.05, 0.08, 0.85)
	tooltip.no_depth_test = true
	tooltip.render_priority = 10
	tooltip.visible = false
	add_child(tooltip)


func _build_icons() -> void:
	for idx in apps.size():
		_build_icon(apps[idx], idx)


func _build_icon(a: Dictionary, idx: int) -> void:
		var seed := float(idx) * 1.37 + 0.5
		var holder := Node3D.new()
		add_child(holder)

		var quad := QuadMesh.new()
		quad.size = Vector2(ICON_SIZE, ICON_SIZE)
		quad.center_offset = Vector3(0, ICON_SIZE * 0.5, 0)

		var m := ShaderMaterial.new()
		m.shader = icon_shader
		m.set_shader_parameter("tex", a.texture)
		m.set_shader_parameter("seed", seed)
		m.set_shader_parameter("wet", 0.0)
		m.render_priority = 2
		var icon := MeshInstance3D.new()
		icon.mesh = quad
		icon.material_override = m
		holder.add_child(icon)

		var rquad := QuadMesh.new()
		rquad.size = Vector2(ICON_SIZE, ICON_SIZE)
		rquad.center_offset = Vector3(0, -ICON_SIZE * 0.5, 0)
		var rm := ShaderMaterial.new()
		rm.shader = icon_shader
		rm.set_shader_parameter("tex", a.texture)
		rm.set_shader_parameter("reflection", 1.0)
		rm.set_shader_parameter("seed", seed)
		rm.render_priority = 1
		var refl := MeshInstance3D.new()
		refl.mesh = rquad
		refl.material_override = rm
		# lie flat on the glass, extending toward the viewer
		refl.rotation_degrees = Vector3(-90, 0, 0)
		refl.position = Vector3(0, 0.003, 0)
		holder.add_child(refl)

		var dm := ShaderMaterial.new()
		dm.shader = dot_shader
		dm.set_shader_parameter("seed", seed)
		dm.set_shader_parameter("strength", 0.0)
		dm.render_priority = 3
		var dquad := QuadMesh.new()
		dquad.size = Vector2(0.26, 0.26)
		var dot := MeshInstance3D.new()
		dot.mesh = dquad
		dot.material_override = dm
		dot.rotation_degrees = Vector3(-90, 0, 0)
		holder.add_child(dot)

		a.node = holder
		a.icon = icon
		a.refl = refl
		a.dot = dot
		a.dot_mat = dm
		a.icon_mat = m


# ---------------------------------------------------------------- apps

func _load_apps() -> void:
	var f := FileAccess.open(_cfg_path(), FileAccess.READ)
	if f == null:
		push_error("apps.cfg not found at " + _cfg_path())
		return
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var entry := _entry_for(line)
		if entry.is_empty():
			print("[dock] skipping missing app: ", line)
			continue
		entry.scale = 1.0
		entry.x = 0.0
		entry.bounce = 0.0
		entry.running = false
		apps.append(entry)
	print("[dock] loaded %d apps" % apps.size())


func _entry_for(line: String) -> Dictionary:
	var entry := _custom_entry(line) if "|" in line else Apps.read_desktop(line)
	if not entry.is_empty():
		entry.texture = ImageTexture.create_from_image(Apps.icon_image(entry.icon_name, entry.name))
	return entry


## A .desktop file dropped on the dock: add it (and remember it in apps.cfg).
func add_dropped(file: String) -> bool:
	if not file.ends_with(".desktop") or not FileAccess.file_exists(file):
		return false
	var line := file
	for d in Apps.DESKTOP_DIRS:
		if file.get_base_dir() == Apps.expand(d):
			line = file.get_file().get_basename()   # a normal installed app: store just its id
	for a in apps:
		if a.id == line or a.get("path", "") == file:
			_bounce(a)
			return true
	var entry := _entry_for(line)
	if entry.is_empty():
		return false
	entry.scale = 0.2
	entry.x = 0.0
	entry.bounce = 0.0
	entry.running = false
	apps.append(entry)
	_build_icon(entry, apps.size() - 1)
	var f := FileAccess.open(_cfg_path(), FileAccess.READ_WRITE)
	if f:
		f.seek_end()
		f.store_string("\n" + line + "\n")
		f.close()
	_bounce(entry)
	print("[dock] added ", entry.name)
	return true


## "Name | icon | command": a launcher that isn't a .desktop app (e.g. ../Drawers3D/run.sh).
## Relative icon and command paths are resolved next to apps.cfg.
func _custom_entry(line: String) -> Dictionary:
	var parts := line.split("|")
	if parts.size() < 3:
		return {}
	var base := _cfg_path().get_base_dir()
	var icon := parts[1].strip_edges()
	if ("/" in icon or icon.get_extension() in ["png", "svg"]) and not icon.is_absolute_path():
		icon = base.path_join(icon).simplify_path()
	var cmd := parts[2].strip_edges()
	var exe := cmd.get_slice(" ", 0)
	if "/" in exe and not exe.is_absolute_path():
		var full := base.path_join(exe).simplify_path()
		cmd = "'" + full.replace("'", "'\\''") + "'" + cmd.substr(exe.length())
	var name := parts[0].strip_edges()
	var keys := [name.to_lower()]
	if parts.size() > 3:
		keys.append(parts[3].strip_edges().to_lower())
	return {"id": name, "name": name, "icon_name": icon, "exec": cmd, "custom": true,
		"wmclass": "", "match_keys": keys}


func _cfg_path() -> String:
	# next to the exported binary, or the project folder when run from the editor
	if OS.has_feature("editor") or not OS.has_feature("template"):
		return ProjectSettings.globalize_path("res://apps.cfg")
	return OS.get_executable_path().get_base_dir().path_join("apps.cfg")


func _launch(a: Dictionary) -> void:
	if a.exec.begins_with("@"):
		builtin.emit(a.exec.substr(1))
	elif a.get("custom", false):
		OS.create_process("sh", ["-c", "setsid " + a.exec + " >/dev/null 2>&1 &"])
	else:
		Apps.launch(a)
	_bounce(a)


func _bounce(a: Dictionary) -> void:
	var t := create_tween()
	for h in [0.7, 0.0, 0.35, 0.0]:
		t.tween_property(a.node, "position:y", h, 0.22) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT if h > 0 else Tween.EASE_IN)


func _poll_running() -> void:
	# a script file, not "sh -c": Godot's execute() would swallow the $variables
	var script := ProjectSettings.globalize_path("res://scripts/window_classes.sh")
	while not _quit:
		var out := []
		OS.execute("sh", [script], out)
		var found := {}
		var rx := RegEx.create_from_string("\"([^\"]+)\"")
		for m in rx.search_all("".join(out)):
			found[m.get_string(1).to_lower()] = true
		_running_mutex.lock()
		_running_classes = found
		_running_mutex.unlock()
		for i in 25:
			if _quit:
				return
			OS.delay_msec(100)


# ---------------------------------------------------------------- per frame

func _layout_width(scales: Array) -> float:
	var w := 0.0
	for s in scales:
		w += ICON_SIZE * s
	return w + GAP * maxi(scales.size() - 1, 0)


func _base_x(i: int) -> float:
	var step := ICON_SIZE + GAP
	return (i - (apps.size() - 1) * 0.5) * step


func _target_scales() -> Array:
	var out := []
	for i in apps.size():
		var s := 1.0
		if hovering:
			var d := absf(mouse_world_x - _base_x(i))
			if d < INFLUENCE:
				s = 1.0 + (MAX_SCALE - 1.0) * (cos(PI * d / INFLUENCE) + 1.0) * 0.5
		out.append(s)
	return out


func _process(delta: float) -> void:
	if apps.is_empty():
		return
	var mp := get_viewport().get_mouse_position()
	var inside := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).has_point(mp)
	var origin := camera.project_ray_origin(mp)
	var dir := camera.project_ray_normal(mp)
	var hit := origin + dir * (-origin.z / dir.z) if absf(dir.z) > 1e-5 else Vector3.ZERO
	hovering = inside and mouse_in and _hover_zone(hit)
	mouse_world_x = hit.x
	if _fake_hover_x != null:
		hovering = true
		mouse_world_x = _fake_hover_x
		hit = Vector3(_fake_hover_x, 0.5, 0)

	var targets := _target_scales()
	var k := 1.0 - exp(-delta * 14.0)
	animating = false
	for i in apps.size():
		var a: Dictionary = apps[i]
		var ns: float = lerpf(a.scale, targets[i], k)
		if absf(ns - a.scale) > 0.001:
			animating = true
		a.scale = ns

	var scales := []
	for a in apps:
		scales.append(a.scale)
	var total := _layout_width(scales)
	var x := -total * 0.5
	_running_mutex.lock()
	var running := _running_classes
	_running_mutex.unlock()
	hovered_idx = -1
	for i in apps.size():
		var a: Dictionary = apps[i]
		var w: float = ICON_SIZE * a.scale
		a.x = x + w * 0.5
		x += w + GAP
		a.bounce = a.node.position.y
		a.node.position.x = a.x
		a.icon.scale = Vector3(a.scale, a.scale, 1)
		a.icon.rotation.x = camera.rotation.x  # tilt back to face the viewer, like the Mac dock
		a.refl.scale = Vector3(a.scale, a.scale, 1)
		a.dot.position = Vector3(0, 0.004 - a.bounce, SHELF_DEPTH * 0.5 - 0.17)
		var is_running: bool = forced_running.has(a.name)
		for key in a.match_keys:
			if running.has(key):
				is_running = true
				break
		var ds: float = a.dot_mat.get_shader_parameter("strength")
		a.dot_mat.set_shader_parameter("strength", lerpf(ds, 1.0 if is_running else 0.0, k))
		if hovering and absf(hit.x - a.x) <= w * 0.5 + GAP * 0.5 and hit.y > -0.3 \
				and hit.y < a.bounce + w + 0.1:
			hovered_idx = i
		var wet: float = a.icon_mat.get_shader_parameter("wet")
		a.icon_mat.set_shader_parameter("wet", lerpf(wet, a.scale - 1.0, k))

	var want_w := total + 0.8
	shelf_width = lerpf(shelf_width, want_w, k)
	shelf.scale.x = shelf_width
	shelf_edge.scale.x = shelf_width
	shelf.material_override.set_shader_parameter("width", shelf_width)
	shelf.material_override.set_shader_parameter("depth", SHELF_DEPTH)
	shelf_edge.material_override.set_shader_parameter("width", shelf_width)

	if hovered_idx >= 0:
		var a: Dictionary = apps[hovered_idx]
		tooltip.text = a.name
		tooltip.position = Vector3(a.x, a.bounce + ICON_SIZE * a.scale + 0.32, 0)
		tooltip.visible = true
	else:
		tooltip.visible = false

	_update_passthrough()
	if not embedded:
		Engine.max_fps = 60 if (hovering or animating) else 15


func _snapshot(path: String) -> void:
	await get_tree().create_timer(1.5).timeout
	get_viewport().get_texture().get_image().save_png(path)
	print("[dock] snapshot saved: ", path)
	get_tree().quit()


func _hover_zone(hit: Vector3) -> bool:
	if absf(hit.x) > shelf_width * 0.5 + 0.1:
		return false
	var top := 0.0
	for a in apps:
		top = maxf(top, a.bounce + ICON_SIZE * a.scale)
	return hit.y > -1.0 and hit.y < top + 0.1


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and hovered_idx >= 0:
			_launch(apps[hovered_idx])
		elif event.button_index == MOUSE_BUTTON_RIGHT and hovered_idx < 0 and hovering:
			get_tree().quit()   # right-click empty shelf space to quit the dock
