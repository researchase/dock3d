extends Node
## Background thumbnails (images, video frames, PDF first pages) and short Theora video previews.
## Reuses GNOME's thumbnail cache when it has one; otherwise makes its own under ~/.cache/drawers3d.

const MAX_ACTIVE := 4
const THUMB_PX := 320

var cache_dir := OS.get_environment("HOME") + "/.cache/drawers3d"
var _cache := {}      # path -> Texture2D (or null when it failed)
var _pending := {}    # path -> Array[Callable]
var _queue := []
var _active := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(cache_dir + "/thumbs")
	DirAccess.make_dir_recursive_absolute(cache_dir + "/previews")


func request(item: Dictionary, cb: Callable) -> void:
	var key: String = item.path
	if _cache.has(key):
		cb.call(_cache[key])
		return
	if _pending.has(key):
		_pending[key].append(cb)
		return
	_pending[key] = [cb]
	_queue.append(item)
	_pump()


func _pump() -> void:
	while _active < MAX_ACTIVE and not _queue.is_empty():
		var it: Dictionary = _queue.pop_front()
		# nobody is waiting any more (that wall was closed): skip it
		var alive := false
		for cb in _pending.get(it.path, []):
			if cb.is_valid():
				alive = true
		if not alive:
			_pending.erase(it.path)
			continue
		_active += 1
		WorkerThreadPool.add_task(_work.bind(it))


func _work(it: Dictionary) -> void:
	var img: Image = null
	if not it.get("special", false):
		img = _make(it)
	_done.call_deferred(it.path, img)


func _done(path: String, img: Image) -> void:
	_active -= 1
	var tex: Texture2D = ImageTexture.create_from_image(img) if img else null
	_cache[path] = tex
	for cb in _pending.get(path, []):
		if cb.is_valid():
			cb.call(tex)
	_pending.erase(path)
	_pump()


func _key(it: Dictionary) -> String:
	return ("%s|%s" % [it.path, it.mtime]).md5_text()


func _gnome_thumb(path: String) -> String:
	var segs := []
	for s in path.split("/"):
		segs.append(s.uri_encode())
	var md5 := ("file://" + "/".join(segs)).md5_text()
	for d in ["x-large", "large", "normal"]:
		var p := "%s/.cache/thumbnails/%s/%s.png" % [OS.get_environment("HOME"), d, md5]
		if FileAccess.file_exists(p):
			return p
	return ""


func _make(it: Dictionary) -> Image:
	var own := "%s/thumbs/%s.png" % [cache_dir, _key(it)]
	for p in [_gnome_thumb(it.path), own]:
		if p != "" and FileAccess.file_exists(p):
			var cached := Image.load_from_file(p)
			if cached and not cached.is_empty():
				return _finish(cached)
	var img: Image = null
	match it.kind:
		"image":
			if it.ext in ["png", "jpg", "jpeg", "webp", "bmp", "svg", "tga"]:
				img = Image.load_from_file(it.path)
			if img == null or img.is_empty():
				img = _ffmpeg_frame(it.path, own, 0.0)
		"video":
			img = _ffmpeg_frame(it.path, own, 3.0)
			if img == null:
				img = _ffmpeg_frame(it.path, own, 0.0)
		"pdf":
			var prefix := own.get_basename()
			OS.execute("pdftoppm", ["-png", "-f", "1", "-singlefile", "-scale-to", str(THUMB_PX), it.path, prefix])
			if FileAccess.file_exists(own):
				img = Image.load_from_file(own)
	if img == null or img.is_empty():
		return null
	img = _finish(img)
	img.save_png(own)
	return img


func _ffmpeg_frame(src: String, dst: String, at: float) -> Image:
	OS.execute("ffmpeg", ["-v", "error", "-y", "-ss", str(at), "-i", src, "-frames:v", "1",
		"-vf", "scale=%d:-2" % THUMB_PX, dst])
	if FileAccess.file_exists(dst):
		var img := Image.load_from_file(dst)
		if img and not img.is_empty():
			return img
	return null


func _finish(img: Image) -> Image:
	img.convert(Image.FORMAT_RGBA8)
	var m := maxi(img.get_width(), img.get_height())
	if m > THUMB_PX:
		var k := float(THUMB_PX) / m
		img.resize(maxi(1, int(img.get_width() * k)), maxi(1, int(img.get_height() * k)), Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps()
	return img


## Full-size image for the big preview (capped at 2048 px), loaded off the main thread.
func load_full(item: Dictionary, cb: Callable) -> void:
	WorkerThreadPool.add_task(_load_full_work.bind(item, cb))


func _load_full_work(item: Dictionary, cb: Callable) -> void:
	var img: Image = null
	if item.ext in ["png", "jpg", "jpeg", "webp", "bmp", "svg", "tga"]:
		img = Image.load_from_file(item.path)
	if img == null or img.is_empty():
		var tmp := "%s/thumbs/%s_full.png" % [cache_dir, _key(item)]
		OS.execute("ffmpeg", ["-v", "error", "-y", "-i", item.path, "-frames:v", "1", "-vf", "scale='min(2048,iw)':-2", tmp])
		if FileAccess.file_exists(tmp):
			img = Image.load_from_file(tmp)
	if img and not img.is_empty():
		var m := maxi(img.get_width(), img.get_height())
		if m > 2048:
			var k := 2048.0 / m
			img.resize(int(img.get_width() * k), int(img.get_height() * k), Image.INTERPOLATE_LANCZOS)
		img.generate_mipmaps()
	else:
		img = null
	_deliver.call_deferred(cb, img)


func _deliver(cb: Callable, img: Image) -> void:
	if cb.is_valid():
		cb.call(ImageTexture.create_from_image(img) if img else null, img)


## Godot only plays Ogg Theora, so a ~20 s clip is converted once and cached.
func make_video_preview(item: Dictionary, cb: Callable) -> void:
	var out := "%s/previews/%s.ogv" % [cache_dir, _key(item)]
	if FileAccess.file_exists(out) and FileAccess.get_file_as_bytes(out).size() > 1024:
		cb.call(out)
		return
	WorkerThreadPool.add_task(_preview_work.bind(item, out, cb))


func _preview_work(item: Dictionary, out: String, cb: Callable) -> void:
	var probe := []
	OS.execute("ffprobe", ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", item.path], probe)
	var dur := "".join(probe).strip_edges().to_float()
	var start := dur * 0.1 if dur > 40.0 else 0.0
	var tmp := out + ".part.ogv"
	OS.execute("ffmpeg", ["-v", "error", "-y", "-ss", str(start), "-t", "20", "-i", item.path,
		"-vf", "scale='min(960,iw)':-2", "-c:v", "libtheora", "-q:v", "7",
		"-c:a", "libvorbis", "-q:a", "4", "-ac", "2", tmp])
	var ok := FileAccess.file_exists(tmp) and DirAccess.rename_absolute(tmp, out) == OK
	_deliver_path.call_deferred(cb, out if ok else "")


func _deliver_path(cb: Callable, path: String) -> void:
	if cb.is_valid():
		cb.call(path)
