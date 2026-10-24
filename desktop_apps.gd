extends RefCounted
## Installed apps: reading .desktop files, finding their theme icons, launching them.
## Shared by the dock and the app roller.

const DESKTOP_DIRS := [
	"~/.local/share/applications",
	"~/.local/share/flatpak/exports/share/applications",
	"/var/lib/flatpak/exports/share/applications",
	"/var/lib/snapd/desktop/applications",
	"/usr/local/share/applications",
	"/usr/share/applications",
]
const ICON_BASES := [
	"~/.local/share/icons", "~/.icons",
	"~/.local/share/flatpak/exports/share/icons",
	"/var/lib/flatpak/exports/share/icons",
	"/usr/share/icons",
]
const ICON_THEMES := ["hicolor", "Yaru", "Adwaita"]
const ICON_SIZES := ["512x512", "256x256", "scalable", "192x192", "128x128", "96x96", "64x64", "48x48"]
const ICON_PX := 256


static func expand(p: String) -> String:
	return p.replace("~", OS.get_environment("HOME")) if p.begins_with("~") else p


## An installed app by id (file name without .desktop), or a .desktop file anywhere by absolute path.
static func read_desktop(id: String) -> Dictionary:
	if id.is_absolute_path():
		if not FileAccess.file_exists(id):
			return {}
		var e := parse_desktop(id, id.get_file().get_basename())
		e.direct = true    # not in an applications folder, so gtk-launch can't find it
		return e
	for d in DESKTOP_DIRS:
		var candidate: String = expand(d).path_join(id + ".desktop")
		if FileAccess.file_exists(candidate):
			return parse_desktop(candidate, id)
	return {}


static func parse_desktop(path: String, id: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	var info := {"id": id, "path": path, "name": id, "icon_name": "", "exec": "", "wmclass": "",
		"type": "", "hidden": false, "comment": "", "categories": ""}
	if f == null:
		return {}
	var in_main := false
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.begins_with("["):
			in_main = line == "[Desktop Entry]"
			continue
		if not in_main or not "=" in line:
			continue
		var key := line.get_slice("=", 0)
		var val := line.substr(key.length() + 1)
		match key:
			"Name": info.name = val
			"Icon": info.icon_name = val
			"Exec": info.exec = val
			"StartupWMClass": info.wmclass = val
			"Type": info.type = val
			"Comment": info.comment = val
			"Categories": info.categories = val
			"NoDisplay", "Hidden":
				if val.to_lower() == "true":
					info.hidden = true
			"OnlyShowIn":
				if not "GNOME" in val and not "Unity" in val:
					info.hidden = true
			"NotShowIn":
				if "GNOME" in val:
					info.hidden = true
	# names used to detect running windows (WM_CLASS)
	var keys := {}
	for k in [info.wmclass, id, id.get_slice(".", id.get_slice_count(".") - 1),
			info.exec.get_slice(" ", 0).get_file(), info.icon_name]:
		if k != "":
			keys[k.to_lower()] = true
	info.match_keys = keys.keys()
	return info


## Every app that would show in the app grid, by name. User copies win over system ones with the same id.
static func list_installed() -> Array:
	var seen := {}
	var out := []
	for d in DESKTOP_DIRS:
		var dir := DirAccess.open(expand(d))
		if dir == null:
			continue
		for fname in dir.get_files():
			if not fname.ends_with(".desktop"):
				continue
			var id := fname.get_basename()
			if seen.has(id):
				continue
			seen[id] = true
			var e := parse_desktop(expand(d).path_join(fname), id)
			if e.is_empty() or e.hidden or e.type != "Application" or e.exec == "":
				continue
			out.append(e)
	out.sort_custom(func(a, b): return a.name.naturalnocasecmp_to(b.name) < 0)
	return out


static func find_icon_file(icon_name: String) -> String:
	if icon_name == "":
		return ""
	if icon_name.is_absolute_path():
		return icon_name if FileAccess.file_exists(icon_name) else ""
	var exts := ["png", "svg"]
	for base in ICON_BASES:
		for theme in ICON_THEMES:
			for size in ICON_SIZES:
				for ext in exts:
					var p: String = "%s/%s/%s/apps/%s.%s" % [expand(base), theme, size, icon_name, ext]
					if FileAccess.file_exists(p):
						return p
	for dir in ["/usr/share/pixmaps", "/var/lib/snapd/desktop/icons"]:
		for ext in exts:
			var p: String = "%s/%s.%s" % [dir, icon_name, ext]
			if FileAccess.file_exists(p):
				return p
	return ""


## The app's icon as a square image with mipmaps (safe to call from a worker thread).
static func icon_image(icon_name: String, app_name: String, px := ICON_PX) -> Image:
	var path := find_icon_file(icon_name)
	var img: Image = null
	if path != "":
		img = Image.new()
		var err := OK
		if path.ends_with(".svg"):
			var buf := FileAccess.get_file_as_bytes(path)
			err = img.load_svg_from_buffer(buf, 1.0)
			if err == OK and img.get_width() > 0:
				err = img.load_svg_from_buffer(buf, float(px) / img.get_width())
		else:
			err = img.load(path)
		if err != OK or img.is_empty():
			img = null
	if img == null:
		img = fallback_icon(app_name, px)
	img.convert(Image.FORMAT_RGBA8)
	if img.get_width() != px:
		img.resize(px, px, Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps()
	return img


static func fallback_icon(app_name: String, px := ICON_PX) -> Image:
	# rounded gradient tile, hue derived from the name
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var hue := float(hash(app_name) % 360) / 360.0
	var r := px * 0.22
	for y in px:
		for x in px:
			var dx := maxf(absf(x - px * 0.5) - (px * 0.5 - r - 8), 0.0)
			var dy := maxf(absf(y - px * 0.5) - (px * 0.5 - r - 8), 0.0)
			var d := sqrt(dx * dx + dy * dy)
			var a := clampf(r - d, 0.0, 1.0)
			img.set_pixel(x, y, Color.from_hsv(hue, 0.6, lerpf(0.95, 0.6, float(y) / px), a))
	return img


## Start an app: gtk-launch for installed ones (handles field codes, Terminal=true, D-Bus activation),
## or straight from its Exec line for .desktop files that live elsewhere.
static func launch(a: Dictionary) -> void:
	var pid := -1
	if not a.get("direct", false):
		pid = OS.create_process("gtk-launch", [a.id])
	if pid <= 0:
		var cmd: String = a.exec
		for code in ["%U", "%u", "%F", "%f", "%i", "%c", "%k"]:
			cmd = cmd.replace(code, "")
		OS.create_process("sh", ["-c", "setsid " + cmd + " >/dev/null 2>&1 &"])
