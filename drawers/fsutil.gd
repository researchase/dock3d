extends RefCounted
## Shared helpers: palette, folder listing, file kinds, theme icons, formatting, easing.

# ---------------------------------------------------------------- palette (Diana's calendar, light)
const PAPER := Color("#f5eee3")
const INK := Color("#2b241d")
const INK2 := Color("#5b5046")
const MUTED := Color("#8c8076")
const GOLD := Color("#d9a21f")
const GOLD_INK := Color("#8a5a12")
const GOLD_SOFT := Color("#f7e9c6")
const CARD := Color("#fffdf9")
const HAIR := Color("#e8ddcc")
const FACE := Color("#fbf6ec")
const FACE_SIDE := Color("#e9dcc5")
const DRAWER_IN := Color("#cfb388")
const FACE_DARK := Color("#3a2440")

const KINDS := {
	"folder": {"label": "Folder", "color": Color("#d29a2e"), "icon": "folder"},
	"image": {"label": "Image", "color": Color("#3f9e6e"), "icon": "image-x-generic"},
	"video": {"label": "Video", "color": Color("#8a5cc7"), "icon": "video-x-generic"},
	"audio": {"label": "Audio", "color": Color("#c9558a"), "icon": "audio-x-generic"},
	"pdf": {"label": "PDF", "color": Color("#cf5a3c"), "icon": "application-pdf"},
	"doc": {"label": "Document", "color": Color("#4f7fd1"), "icon": "x-office-document"},
	"sheet": {"label": "Spreadsheet", "color": Color("#2f9a5a"), "icon": "x-office-spreadsheet"},
	"slides": {"label": "Slides", "color": Color("#d9822b"), "icon": "x-office-presentation"},
	"code": {"label": "Code", "color": Color("#2f8fa6"), "icon": "text-x-script"},
	"text": {"label": "Text", "color": Color("#6b7fa8"), "icon": "text-x-generic"},
	"archive": {"label": "Archive", "color": Color("#a87a44"), "icon": "package-x-generic"},
	"model": {"label": "3D model", "color": Color("#c4703a"), "icon": "model"},
	"app": {"label": "Program", "color": Color("#5b6b7a"), "icon": "application-x-executable"},
	"other": {"label": "File", "color": Color("#9a9088"), "icon": "text-x-generic"},
	"more": {"label": "More", "color": Color("#9a9088"), "icon": "folder"},
}

const EXT_KIND := {
	"png": "image", "jpg": "image", "jpeg": "image", "webp": "image", "gif": "image", "bmp": "image",
	"svg": "image", "tga": "image", "heic": "image", "avif": "image", "tif": "image", "tiff": "image",
	"mp4": "video", "mkv": "video", "webm": "video", "mov": "video", "avi": "video", "m4v": "video",
	"ogv": "video", "wmv": "video", "flv": "video", "mpg": "video", "mpeg": "video",
	"mp3": "audio", "wav": "audio", "flac": "audio", "ogg": "audio", "m4a": "audio", "opus": "audio", "aac": "audio",
	"pdf": "pdf",
	"doc": "doc", "docx": "doc", "odt": "doc", "rtf": "doc", "epub": "doc", "tex": "doc",
	"xls": "sheet", "xlsx": "sheet", "ods": "sheet", "csv": "sheet",
	"ppt": "slides", "pptx": "slides", "odp": "slides", "key": "slides",
	"py": "code", "gd": "code", "js": "code", "ts": "code", "tsx": "code", "jsx": "code", "c": "code",
	"cpp": "code", "h": "code", "hpp": "code", "rs": "code", "go": "code", "java": "code", "kt": "code",
	"cs": "code", "rb": "code", "php": "code", "sh": "code", "html": "code", "css": "code", "json": "code",
	"yaml": "code", "yml": "code", "toml": "code", "xml": "code", "ipynb": "code", "gdshader": "code",
	"glsl": "code", "tscn": "code", "godot": "code", "r": "code", "sql": "code",
	"txt": "text", "md": "text", "log": "text", "cfg": "text", "ini": "text", "conf": "text",
	"zip": "archive", "tar": "archive", "gz": "archive", "tgz": "archive", "xz": "archive",
	"bz2": "archive", "7z": "archive", "rar": "archive", "deb": "archive", "rpm": "archive",
	"blend": "model", "fbx": "model", "obj": "model", "glb": "model", "gltf": "model", "stl": "model",
	"usd": "model", "usdz": "model", "3mf": "model",
	"appimage": "app", "x86_64": "app", "exe": "app",
}

const EXT_ICON := {
	"py": "text-x-python", "html": "text-html", "json": "application-json", "js": "application-javascript",
	"md": "text-markdown", "deb": "application-vnd.debian.binary-package", "zip": "application-archive-zip",
	"blend": "application-x-blender", "c": "text-x-csrc", "sh": "application-x-shellscript",
}

const SPECIAL_FOLDERS := {
	"Desktop": "user-desktop", "Documents": "folder-documents", "Downloads": "folder-download",
	"Music": "folder-music", "Pictures": "folder-pictures", "Videos": "folder-videos",
	"Templates": "folder-templates", "Public": "folder-publicshare", "Dropbox": "folder-dropbox",
}

const ICON_DIRS := [
	"/usr/share/icons/Yaru/256x256", "/usr/share/icons/Yaru/256x256@2x",
	"/usr/share/icons/Adwaita/256x256", "/usr/share/icons/hicolor/256x256",
]
const ICON_CATS := ["places", "mimetypes", "apps", "legacy"]

static var _icon_cache := {}


static func home() -> String:
	return OS.get_environment("HOME")


static func kind_info(kind: String) -> Dictionary:
	return KINDS.get(kind, KINDS["other"])


static func kind_color(kind: String) -> Color:
	return kind_info(kind)["color"]


static func icon_for(item: Dictionary) -> Texture2D:
	var names := []
	if item.kind == "folder":
		if item.path == home():
			names.append("user-home")
		elif item.path.get_base_dir() == home() and SPECIAL_FOLDERS.has(item.name):
			names.append(SPECIAL_FOLDERS[item.name])
	elif EXT_ICON.has(item.ext):
		names.append(EXT_ICON[item.ext])
	names.append(kind_info(item.kind)["icon"])
	names.append("text-x-generic")
	for n in names:
		var t := theme_icon(n)
		if t:
			return t
	return null


static func theme_icon(icon_name: String) -> Texture2D:
	if _icon_cache.has(icon_name):
		return _icon_cache[icon_name]
	var tex: Texture2D = null
	for d in ICON_DIRS:
		for c in ICON_CATS:
			var p: String = "%s/%s/%s.png" % [d, c, icon_name]
			if FileAccess.file_exists(p):
				var img := Image.load_from_file(p)
				if img:
					img.generate_mipmaps()
					tex = ImageTexture.create_from_image(img)
				break
		if tex:
			break
	_icon_cache[icon_name] = tex
	return tex


# ---------------------------------------------------------------- listing

static func _kind_for(name: String, is_dir: bool, mode: int) -> Array:
	if is_dir:
		return ["folder", ""]
	var ext := name.get_extension().to_lower() if "." in name.substr(1) else ""
	var kind: String = EXT_KIND.get(ext, "")
	if kind == "":
		kind = "app" if (mode & 73) != 0 and ext == "" else ("text" if ext == "" else "other")
	return [kind, ext]


## One `find` call for the entries, one for the grandchildren (to count what is inside each folder).
static func list_dir(path: String, show_hidden := false) -> Array:
	var out := []
	var res := []
	var q := shell_quote(path)
	OS.execute("sh", ["-c",
		"find %s -mindepth 1 -maxdepth 1 -printf '%%Y\\t%%s\\t%%T@\\t%%m\\t%%f\\n' 2>/dev/null | head -n 5000" % q], res)
	var counts := {}   # child folder name -> {n, kinds}
	var sub := []
	OS.execute("sh", ["-c",
		"find %s -mindepth 2 -maxdepth 2 -printf '%%h\\t%%Y\\t%%f\\n' 2>/dev/null | head -n 40000" % q], sub)
	var plen := path.length() + (0 if path.ends_with("/") else 1)
	for line in "".join(sub).split("\n", false):
		var f := line.split("\t")
		if f.size() < 3:
			continue
		var parent := f[0].substr(plen)
		if not show_hidden and (parent.begins_with(".") or f[2].begins_with(".")):
			continue
		if not counts.has(parent):
			counts[parent] = {"n": 0, "kinds": {}}
		var c: Dictionary = counts[parent]
		c.n += 1
		var k: String = _kind_for(f[2], f[1] == "d", 0)[0]
		c.kinds[k] = c.kinds.get(k, 0) + 1
	for line in "".join(res).split("\n", false):
		var f := line.split("\t")
		if f.size() < 5:
			continue
		var name := f[4]
		if not show_hidden and name.begins_with("."):
			continue
		var is_dir := f[0] == "d"
		var kx := _kind_for(name, is_dir, _octal(f[3]))
		var it := {
			"name": name, "path": path.path_join(name), "is_dir": is_dir,
			"kind": kx[0], "ext": kx[1], "size": f[1].to_int(), "mtime": f[2].to_float(),
			"special": not is_dir and f[0] != "f",   # fifo, socket, device, broken link
			"child_count": 0, "child_kinds": {},
		}
		if is_dir and counts.has(name):
			it.child_count = counts[name].n
			it.child_kinds = counts[name].kinds
		out.append(it)
	out.sort_custom(func(a, b):
		if a.is_dir != b.is_dir:
			return a.is_dir
		return a.name.naturalnocasecmp_to(b.name) < 0)
	return out


static func shell_quote(s: String) -> String:
	return "'" + s.replace("'", "'\\''") + "'"


static func _octal(s: String) -> int:
	var v := 0
	for ch in s:
		v = v * 8 + (ch.unicode_at(0) - 48)
	return v


static func folder_item(path: String) -> Dictionary:
	return {"name": display_name(path), "path": path, "is_dir": true, "kind": "folder", "ext": "",
		"size": 0, "mtime": FileAccess.get_modified_time(path), "special": false,
		"child_count": 0, "child_kinds": {}}


static func display_name(path: String) -> String:
	if path == home():
		return "Home"
	if path == "/":
		return "Computer"
	return path.get_file()


# ---------------------------------------------------------------- words

static func human_size(b: int) -> String:
	if b < 1024:
		return "%d B" % b
	var units := ["KB", "MB", "GB", "TB"]
	var v := float(b)
	var i := -1
	while v >= 1024.0 and i < units.size() - 1:
		v /= 1024.0
		i += 1
	return ("%.0f %s" if v >= 10.0 else "%.1f %s") % [v, units[i]]


static func ago(t: float) -> String:
	var now := Time.get_unix_time_from_system()
	var d := now - t
	if d < 60:
		return "just now"
	if d < 3600:
		return "%d min ago" % int(d / 60)
	if is_today(t):
		return "%d h ago" % int(d / 3600)
	var days := int(d / 86400.0) + 1
	if days <= 1:
		return "yesterday"
	if days < 7:
		return "%d days ago" % days
	var bias: int = Time.get_time_zone_from_system().bias * 60
	var dt := Time.get_datetime_dict_from_unix_time(int(t) + bias)
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var nowdt := Time.get_datetime_dict_from_unix_time(int(now) + bias)
	if dt.year == nowdt.year:
		return "%d %s" % [dt.day, months[dt.month - 1]]
	return "%s %d" % [months[dt.month - 1], dt.year]


static func is_today(t: float) -> bool:
	var bias: int = Time.get_time_zone_from_system().bias * 60
	var now := int(Time.get_unix_time_from_system())
	return Time.get_date_string_from_unix_time(int(t) + bias) == Time.get_date_string_from_unix_time(now + bias)


static func things(n: int) -> String:
	return "%d thing%s" % [n, "" if n == 1 else "s"]


static func summary(items: Array) -> String:
	var folders := 0
	for it in items:
		if it.is_dir:
			folders += 1
	var files := items.size() - folders
	var parts := []
	if folders:
		parts.append("%d folder%s" % [folders, "" if folders == 1 else "s"])
	if files:
		parts.append("%d file%s" % [files, "" if files == 1 else "s"])
	return " and ".join(parts) if parts.size() else "nothing yet"


static func item_meta(it: Dictionary) -> String:
	if it.kind == "more":
		return "open in Files"
	if it.is_dir:
		return "%s · %s" % [("empty" if it.child_count == 0 else "%d inside" % it.child_count), ago(it.mtime)]
	return "%s · %s" % [human_size(it.size), ago(it.mtime)]


# ---------------------------------------------------------------- easing

## CSS cubic-bezier(x1, y1, x2, y2) evaluated at t (0..1).
static func bezier(t: float, x1: float, y1: float, x2: float, y2: float) -> float:
	t = clampf(t, 0.0, 1.0)
	var u := t
	for i in 8:
		var x := _bz(u, x1, x2) - t
		var dx := _bzd(u, x1, x2)
		if absf(x) < 1e-5 or absf(dx) < 1e-6:
			break
		u = clampf(u - x / dx, 0.0, 1.0)
	return _bz(u, y1, y2)


static func _bz(u: float, a: float, b: float) -> float:
	var v := 1.0 - u
	return 3.0 * v * v * u * a + 3.0 * v * u * u * b + u * u * u


static func _bzd(u: float, a: float, b: float) -> float:
	var v := 1.0 - u
	return 3.0 * v * v * a + 6.0 * v * u * (b - a) + 3.0 * u * u * (1.0 - b)
