extends Node3D
## A drum: things wrapped on an invisible cylinder. Columns sit on a gentle arc (as in the calendar)
## and rows go round a horizontal drum, so you see them curve over the top and roll away underneath.
## Scrolling rolls the drum; rows away from the front go out of focus (the blurred back layer), and
## rows carry on round the back, faintly, so you can tell there is more.
## Carries drawer cubes (a folder) or paper cards (an opened drawer's contents).

const FS = preload("res://drawers/fsutil.gd")
const Cube = preload("res://drawers/cube.gd")

const MAX_CUBES := 240
const GAP := 0.1
const STEP_DEG := 7.0
const ROW_H := 1.0 + 0.1 + 0.2      # cube + gap + room for a "Today" pill
const HIDE_PHI := 3.0                # rows carry on round the back until nearly a full turn

# what this drum carries and how it is spaced (set before build)
var item_script: Script = Cube
var folder_script: Script = null     # card drums show folders as little cabinets (drawer cubes)
var start_middle := true             # open with the middle rows facing you
var card_scale := 1.0                # file cards are drawn this much smaller than their cell
var cell_w := 1.0
var gap := GAP
var row_h := ROW_H
var step_deg := 0.0                  # 0 = straight across (a true cylinder); >0 bends columns too
var fixed_cols := 0
var max_items := MAX_CUBES
var drum_r := 4.4                    # about six sharp rows round the front, a few soft ones beyond
var top_phi := 0.85                  # where the first row sits when scrolled to the top
var sharp_phi := 0.92                # rows further round than this are out of focus

var path := ""
var items: Array = []
var cubes: Array = []
var cols := 1
var rows := 1
var grid: Node3D
var scroll := 0.0
var scroll_target := 0.0
var pan := 0.0                       # sideways slide that brings the selected one to the middle
var pan_target := 0.0
var view_h := 5.0
var is_back := false                 # whole drum is the blurred parent at the left
var _dirty := true
var _flying := {}                    # things mid-flight are left alone by the drum
var open_cube = null
var mats := {}
var fade := 1.0
var _transparent := false
var _move_tw: Tween


func build(p: String, list: Array, ctx: Dictionary) -> void:
	path = p
	items = list
	grid = Node3D.new()
	add_child(grid)
	_make_mats()
	var shown := list.slice(0, max_items)
	if list.size() > max_items:
		shown = list.slice(0, max_items - 1)
		shown.append({"name": "+%d more" % (list.size() - max_items + 1), "path": p, "is_dir": false,
			"kind": "more", "ext": "", "size": 0, "mtime": 0.0, "special": false,
			"child_count": 0, "child_kinds": {}})
	var n := maxi(shown.size(), 1)
	cols = fixed_cols if fixed_cols > 0 else clampi(ceili(sqrt(n * 2.4)), mini(n, 3), 10)
	cols = mini(cols, n)
	rows = ceili(float(n) / cols)
	if start_middle and rows > 1:
		scroll = clampf((rows - 1) * 0.5 * row_h - _top() * drum_r, 0.0, max_scroll())
		scroll_target = scroll
	for i in shown.size():
		var scr: Script = folder_script if (folder_script and shown[i].is_dir) else item_script
		var c = scr.new()
		c.wall = self
		grid.add_child(c)
		c.build(shown[i], ctx, mats)
		if scr == item_script and folder_script != null:
			c.set_meta("cell_scale", card_scale)
		c.slot = slot_xf(i)
		c.transform = _item_xf(i, c)
		cubes.append(c)


## Column arc only (the drum adds the row's place round the cylinder).
func slot_xf(i: int) -> Transform3D:
	var c := i % cols
	var p := cell_w + gap
	if step_deg < 0.01:
		return Transform3D(Basis(), Vector3((c - (cols - 1) * 0.5) * p, 0.0, 0.0))
	var step := deg_to_rad(step_deg)
	var radius := p / step
	var th := (c - (cols - 1) * 0.5) * step
	return Transform3D(Basis(Vector3.UP, -th), Vector3(radius * sin(th), 0.0, radius * (1.0 - cos(th))))


## Where item `i` (object `c`) sits now, including its own size in the cell.
func _item_xf(i: int, c) -> Transform3D:
	var xf := drum_xf(i)
	var k: float = c.get_meta("cell_scale", 1.0)
	return xf if k == 1.0 else xf.scaled_local(Vector3.ONE * k)


func drum_xf_of(c) -> Transform3D:
	return drum_xf(cubes.find(c))


## Item `i` on the drum for scroll `sc`: the column arc, then turned round the drum's axis.
## The drum hangs below the wall's top edge (y = 0), its front face at y = yc.
func drum_xf(i: int, sc := scroll) -> Transform3D:
	var col := slot_xf(i)
	var yc := _yc()
	col.origin.y = yc
	var center := Vector3(0, yc, -drum_r)
	return Transform3D(Basis(), center) * Transform3D(Basis(Vector3.RIGHT, -_phi(i, sc)), Vector3.ZERO) \
		* Transform3D(Basis(), -center) * col


func _yc() -> float:
	return -(drum_r * sin(minf(_top(), 1.3)) + row_h * 0.5)


## A few rows sit centred on the front of the drum; more start with the first row tipped back a little.
func _top() -> float:
	if (rows - 1) * row_h / drum_r <= top_phi * 2.0:
		return (rows - 1) * row_h / drum_r * 0.5
	return top_phi


## Angle round the drum (0 = facing you, + = rolled up and away).
func _phi(i: int, sc := scroll) -> float:
	var s: float = (i / cols) * row_h - sc
	return _top() - s / drum_r


func width() -> float:
	return cols * (cell_w + gap)


## Height of the drum as seen from the front: from the top row down to where rows roll under.
func height() -> float:
	var below := minf((rows - 1) * row_h / drum_r - _top(), top_phi)
	return -_yc() + drum_r * sin(maxf(below, 0.0)) + row_h * 0.5


# ---------------------------------------------------------------- materials

func _mat(color: Color, rough := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m


func _make_mats() -> void:
	mats.card = _mat(FS.CARD, 0.75)
	mats.button = _mat(FS.PAPER, 0.8)
	mats.shell = _mat(FS.FACE_SIDE, 0.85)
	mats.front = _mat(FS.FACE, 0.7)
	mats.front_dark = _mat(FS.FACE_DARK, 0.55)
	mats.tray = _mat(FS.DRAWER_IN, 0.9)
	mats.pill = _mat(FS.GOLD, 0.4)
	mats.pill.emission_enabled = true
	mats.pill.emission = FS.GOLD * 0.35
	mats.paper = {}
	mats.kind = {}


func paper_mat(kind: String) -> StandardMaterial3D:
	if not mats.paper.has(kind):
		mats.paper[kind] = _mat(FS.CARD.lerp(FS.kind_color(kind), 0.3), 0.9)
	return mats.paper[kind]


func kind_mat(kind: String) -> StandardMaterial3D:
	if not mats.kind.has(kind):
		mats.kind[kind] = _mat(FS.kind_color(kind), 0.6)
	return mats.kind[kind]


func _all_mats() -> Array:
	var out := [mats.card, mats.button, mats.shell, mats.front, mats.front_dark, mats.tray, mats.pill]
	out.append_array(mats.paper.values())
	out.append_array(mats.kind.values())
	return out


## Back walls render on their own layer, which the launcher shows out of focus.
func set_back(on: bool) -> void:
	is_back = on
	for c in cubes:
		c.set_meta("layer", -1)
	_dirty = true


func _set_layers(n: Node, layer: int) -> void:
	if n is VisualInstance3D:
		n.layers = layer
	for ch in n.get_children():
		_set_layers(ch, layer)


func set_fade(f: float) -> void:
	fade = f
	var want := f < 0.995
	if want != _transparent:
		_transparent = want
		for m in _all_mats():
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS if want else BaseMaterial3D.TRANSPARENCY_DISABLED
	for m in _all_mats():
		m.albedo_color.a = f
	for c in cubes:
		c.apply_fade(f)


# ---------------------------------------------------------------- drawers

func open(c) -> void:
	if open_cube and open_cube != c:
		open_cube.close()
	open_cube = c
	c.open()
	for o in cubes:
		o.set_dim(0.0 if o == c else 1.0)


func open_instant(c) -> void:
	open_cube = c
	c.open(true)
	for o in cubes:
		o.set_dim(0.0 if o == c else 1.0)


func close() -> void:
	if open_cube:
		open_cube.close()
	open_cube = null
	pan_target = 0.0
	for o in cubes:
		o.set_dim(0.0)


func cube_named(n: String):
	for c in cubes:
		if c.info.name == n:
			return c
	return null


# ---------------------------------------------------------------- scrolling

var cull_top := true   # kept for the app; the drum handles what is in view
var _last_scroll := -1.0


func _process(delta: float) -> void:
	scroll = lerpf(scroll, scroll_target, 1.0 - exp(-delta * 10.0))
	pan = lerpf(pan, pan_target, 1.0 - exp(-delta * 8.0))
	grid.position.x = pan
	if absf(scroll - _last_scroll) > 0.0002 or _dirty:
		_last_scroll = scroll
		_dirty = false
		_roll()


func _roll() -> void:
	for i in cubes.size():
		var c = cubes[i]
		var phi := _phi(i)
		if not _flying.has(c):
			c.transform = _item_xf(i, c)
		# far round the drum: shrink away and hide; past the sharp band: out of focus
		var k := clampf((HIDE_PHI - absf(phi)) / 0.35, 0.0, 1.0)
		c.pivot.scale = Vector3.ONE * maxf(k * k * (3.0 - 2.0 * k), 0.001)
		c.visible = k > 0.01
		c.edge_fade = clampf(1.0 - (absf(phi) - sharp_phi) / 0.9, 0.3, 1.0)
		var layer := 2 if (is_back or absf(phi) > sharp_phi) else 1
		if c.get_meta("layer", 1) != layer:
			c.set_meta("layer", layer)
			_set_layers(c, layer)


func _cull(_delta := -1.0) -> void:
	_dirty = true


func max_scroll() -> float:
	# the last row can come round to the front of the drum
	return maxf(0.0, (rows - 1) * row_h - _top() * drum_r)


func scroll_by(d: float) -> void:
	scroll_target = clampf(scroll_target + d, minf(0.0, scroll_target), max_scroll())


func scroll_to_cube(c, instant := false, slide := true) -> void:
	# roll its row to the front and slide its column to the middle
	var i: int = cubes.find(c)
	var r: int = i / cols
	scroll_target = clampf(r * row_h - _top() * drum_r, -_top() * drum_r, maxf(max_scroll(), 0.0))
	if slide:
		pan_target = -slot_xf(i).origin.x
	if instant:
		scroll = scroll_target
		pan = pan_target
		grid.position.x = pan
		_roll()


# ---------------------------------------------------------------- flights

## Glide the whole wall (to the corner or back to the centre) while fading.
func move_to(xf: Transform3D, fade_to: float, dur := 0.8) -> void:
	if _move_tw:
		_move_tw.kill()
	var a := transform
	var f0 := fade
	_move_tw = create_tween()
	_move_tw.tween_method(_move_step.bind(a, xf, f0, fade_to), 0.0, 1.0, dur)


func _move_step(t: float, a: Transform3D, b: Transform3D, f0: float, f1: float) -> void:
	var e := FS.bezier(t, 0.65, 0.0, 0.25, 1.0)
	transform = a.interpolate_with(b, e)
	set_fade(lerpf(f0, f1, e))


## Fly off to the left, fading out, then go away.
func leave(dur := 0.7) -> void:
	var to := transform.translated(Vector3(-5.0, 0.4, -1.0))
	move_to(to, 0.0, dur)
	_move_tw.finished.connect(queue_free)


## New folder: its cubes come out of the drawer they live in (global_from) and spread to their slots.
func enter_from(global_from: Transform3D) -> void:
	var local_from := grid.global_transform.affine_inverse() * global_from
	local_from.basis = local_from.basis.scaled(Vector3.ONE * 0.12)
	var n := cubes.size()
	for i in n:
		var c = cubes[i]
		c.transform = local_from
		_arc(c, local_from, _item_xf(i, c), 0.75, minf(i * 0.03, 0.55), [0.2, 0.8, 0.2, 1.0], 0.9)


## First appearance: cubes rise from below, row by row.
func enter_rise() -> void:
	for i in cubes.size():
		var c = cubes[i]
		var to := _item_xf(i, c)
		var from: Transform3D = to.translated(Vector3(0, -3.0, 1.5))
		from.basis = from.basis.scaled(Vector3.ONE * 0.6)
		c.transform = from
		_arc(c, from, to, 0.8, minf((i / cols) * 0.08 + (i % cols) * 0.035, 0.7), [0.2, 0.8, 0.2, 1.0], 0.0)


## Going back up: every cube flies back into its drawer in the parent, then the wall is freed.
func exit_into(global_to: Transform3D) -> void:
	var local_to := grid.global_transform.affine_inverse() * global_to
	local_to.basis = local_to.basis.scaled(Vector3.ONE * 0.08)
	var n := cubes.size()
	var last: Tween = null
	for i in n:
		var c = cubes[i]
		var tw := _arc(c, c.transform, local_to, 0.55, minf((n - 1 - i) * 0.02, 0.4), [0.5, 0.0, 0.6, 1.0], 0.6)
		if i == 0:
			last = tw   # starts last, so it lands last
	if last:
		last.finished.connect(queue_free)
	else:
		queue_free()


func _arc(c: Node3D, a: Transform3D, b: Transform3D, dur: float, delay: float, bz: Array, lift: float) -> Tween:
	var tw := c.create_tween()
	_flying[c] = true
	tw.tween_method(_arc_step.bind(c, a, b, bz, lift), 0.0, 1.0, dur).set_delay(delay)
	tw.finished.connect(_landed.bind(c))
	return tw


func _landed(c) -> void:
	_flying.erase(c)
	_dirty = true


func _arc_step(t: float, c: Node3D, a: Transform3D, b: Transform3D, bz: Array, lift: float) -> void:
	var e := FS.bezier(t, bz[0], bz[1], bz[2], bz[3])
	var xf := a.interpolate_with(b, e)
	xf.origin.y += sin(PI * e) * lift
	c.transform = xf
