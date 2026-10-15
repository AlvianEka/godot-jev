class_name JevImage
extends RefCounted
## Image asset wrapper for System One evaluations.[br]
## Warning: Image support is Dreamer-ready (preview). Requests with images automatically include
## the TypeSafe-Danger-Zone-Images header.

const MIN_SIDE: int = 256
const MAX_SIDE: int = 1568
const MIN_TOTAL_PIXELS: int = 78400
const MAX_TOTAL_PIXELS: int = 2458624
const MAX_FILE_BYTES: int = 16 * 1024 * 1024
const _JPG_QUALITY: float = 0.95

static var _tracked: Dictionary = { }
static var _crypto: Crypto = Crypto.new()

var _reference: String = ""
var _image: Image = null
var _bytes: PackedByteArray = PackedByteArray()
var _path: String = ""
var _resource_path: String = ""
var _init_error: String = ""
var _resize_to_fit: bool = false
var _is_resolved: bool = false
var _resolved_bytes: PackedByteArray = PackedByteArray()
var _resolved_content_type: String = ""
var _resolved_error: String = ""


func _init() -> void:
	_reference = "<image:%s>" % _crypto.generate_random_bytes(16).hex_encode()
	_tracked[_reference] = weakref(self)


## Creates a JevImage from a Godot Image.
static func from_image(image: Image) -> JevImage:
	var instance := JevImage.new()
	if image == null:
		instance._init_error = "Image cannot be null."
		return instance
	instance._image = image
	instance._resource_path = image.resource_path
	return instance


## Creates a JevImage from a Godot Texture2D.
static func from_texture(texture: Texture2D) -> JevImage:
	var instance := JevImage.new()
	if texture == null:
		instance._init_error = "Texture2D cannot be null."
		return instance
	var image := texture.get_image()
	if image == null:
		instance._init_error = "Could not extract Image from Texture2D."
		return instance
	instance._image = image
	instance._resource_path = texture.resource_path
	return instance


## Creates a JevImage from a file path (supports res://, user://, and filesystem paths).
static func from_path(path: String) -> JevImage:
	var instance := JevImage.new()
	var trimmed := path.strip_edges()
	if trimmed.is_empty():
		instance._init_error = "Image path cannot be empty."
		return instance
	instance._path = trimmed
	instance._resource_path = trimmed
	return instance


## Creates a JevImage from raw PNG or JPEG file bytes.
static func from_bytes(bytes: PackedByteArray) -> JevImage:
	var instance := JevImage.new()
	if bytes.is_empty():
		instance._init_error = "Image byte buffer is empty."
		return instance
	instance._bytes = bytes
	return instance


## Creates a JevImage from a base64-encoded PNG or JPEG string.
static func from_base64(base64: String) -> JevImage:
	var instance := JevImage.new()
	var cleaned := base64 \
			.strip_edges() \
			.replace("\n", "") \
			.replace("\r", "") \
			.replace(" ", "") \
			.replace("\t", "")
	if cleaned.is_empty():
		instance._init_error = "Base64 image data cannot be empty."
		return instance
	var decoded := Marshalls.base64_to_raw(cleaned)
	if decoded.is_empty():
		instance._init_error = "Invalid base64 image data."
		return instance
	instance._bytes = decoded
	return instance


## Returns a duplicate Image resized (and decompressed if needed) to fit TypeSafe pixel limits.
static func fit_limits(image: Image) -> Image:
	if image == null or image.is_empty():
		return image
	var out: Image = image.duplicate()
	if out.is_compressed():
		out.decompress()
	var w := float(out.get_width())
	var h := float(out.get_height())
	if w <= 0.0 or h <= 0.0:
		return out

	var min_scale := maxf(
		maxf(float(MIN_SIDE) / w, float(MIN_SIDE) / h),
		sqrt(float(MIN_TOTAL_PIXELS) / (w * h)),
	)
	var max_scale := minf(
		minf(float(MAX_SIDE) / w, float(MAX_SIDE) / h),
		sqrt(float(MAX_TOTAL_PIXELS) / (w * h)),
	)
	if min_scale > max_scale:
		return out

	var scale := clampf(1.0, min_scale, max_scale)
	var target_w := clampi(roundi(w * scale), MIN_SIDE, MAX_SIDE)
	var target_h := clampi(roundi(h * scale), MIN_SIDE, MAX_SIDE)
	if target_w * target_h < MIN_TOTAL_PIXELS:
		if target_w <= target_h:
			target_w = clampi(ceili(float(MIN_TOTAL_PIXELS) / float(target_h)), MIN_SIDE, MAX_SIDE)
		else:
			target_h = clampi(ceili(float(MIN_TOTAL_PIXELS) / float(target_w)), MIN_SIDE, MAX_SIDE)
	elif target_w * target_h > MAX_TOTAL_PIXELS:
		if target_w >= target_h:
			target_w = clampi(floori(float(MAX_TOTAL_PIXELS) / float(target_h)), MIN_SIDE, MAX_SIDE)
		else:
			target_h = clampi(floori(float(MAX_TOTAL_PIXELS) / float(target_w)), MIN_SIDE, MAX_SIDE)

	if target_w != out.get_width() or target_h != out.get_height():
		out.resize(target_w, target_h, Image.INTERPOLATE_LANCZOS)
	return out


## Enables automatic resizing to TypeSafe pixel limits before encoding and returns self.
func resized() -> JevImage:
	_resize_to_fit = true
	_is_resolved = false
	return self


## Returns the unique asset reference token for this image.
func get_reference() -> String:
	return _reference


func _to_string() -> String:
	return _reference


static func _find_tracked(reference: String) -> JevImage:
	var ref: Variant = _tracked.get(reference, null)
	if ref is WeakRef:
		var obj: Variant = (ref as WeakRef).get_ref()
		if obj is JevImage:
			return obj
		_tracked.erase(reference)
	return null


static func _is_jpeg_extension(path: String) -> bool:
	var ext := path.get_extension().to_lower()
	return ext == "jpg" or ext == "jpeg"


static func _detect_content_type(data: PackedByteArray) -> String:
	if data.size() >= 8:
		if (
			data[0] == 0x89 and data[1] == 0x50 and data[2] == 0x4E and data[3] == 0x47
			and data[4] == 0x0D and data[5] == 0x0A and data[6] == 0x1A and data[7] == 0x0A
		):
			return "image/png"
	if data.size() >= 3:
		if data[0] == 0xFF and data[1] == 0xD8 and data[2] == 0xFF:
			return "image/jpeg"
	return ""


static func _validate_dimensions(width: int, height: int) -> String:
	if width < MIN_SIDE or width > MAX_SIDE or height < MIN_SIDE or height > MAX_SIDE:
		return (
			"Image dimensions %dx%d are outside TypeSafe limits (%d..%d px per side)."
			% [width, height, MIN_SIDE, MAX_SIDE]
		)
	var total_pixels := width * height
	if total_pixels < MIN_TOTAL_PIXELS or total_pixels > MAX_TOTAL_PIXELS:
		return (
			"Image area %d pixels (%dx%d) is outside TypeSafe limits (%d..%d total pixels)."
			% [total_pixels, width, height, MIN_TOTAL_PIXELS, MAX_TOTAL_PIXELS]
		)
	return ""


func _resolve() -> bool:
	if _is_resolved:
		return _resolved_error.is_empty()
	_is_resolved = true

	if not _init_error.is_empty():
		_resolved_error = _init_error
		return false

	var work_image: Image = _image
	var raw_bytes: PackedByteArray = _bytes

	if not _path.is_empty():
		var file_bytes := FileAccess.get_file_as_bytes(_path)
		if not file_bytes.is_empty() and not _detect_content_type(file_bytes).is_empty():
			raw_bytes = file_bytes
		elif ResourceLoader.exists(_path):
			var res := ResourceLoader.load(_path)
			if res is Texture2D:
				work_image = (res as Texture2D).get_image()
			elif res is Image:
				work_image = res as Image
			else:
				_resolved_error = "Resource at '%s' is not an Image or Texture2D." % _path
				return false
		else:
			_resolved_error = "Could not read image file at '%s'." % _path
			return false

	if work_image != null:
		return _encode_image(work_image, _is_jpeg_extension(_resource_path))

	if raw_bytes.is_empty():
		_resolved_error = "Image data is empty."
		return false

	var detected_type := _detect_content_type(raw_bytes)
	if detected_type.is_empty():
		_resolved_error = "Image bytes must be valid PNG or JPEG format."
		return false

	if not _resize_to_fit:
		if raw_bytes.size() > MAX_FILE_BYTES:
			_resolved_error = "Image file exceeds 16 MiB size limit."
			return false
		_resolved_bytes = raw_bytes
		_resolved_content_type = detected_type
		return true

	var decoded_img := Image.new()
	var load_err: Error = (
		decoded_img.load_png_from_buffer(raw_bytes)
		if detected_type == "image/png"
		else decoded_img.load_jpg_from_buffer(raw_bytes)
	)
	if load_err != OK or decoded_img.is_empty():
		_resolved_error = "Failed to decode PNG/JPEG image bytes."
		return false

	return _encode_image(decoded_img, detected_type == "image/jpeg")


func _encode_image(source_image: Image, prefer_jpeg: bool) -> bool:
	if source_image.is_empty():
		_resolved_error = "Image is empty."
		return false

	var prepared: Image = source_image
	if _resize_to_fit:
		prepared = fit_limits(source_image)
	elif prepared.is_compressed():
		prepared = prepared.duplicate()
		prepared.decompress()

	var dim_error := _validate_dimensions(prepared.get_width(), prepared.get_height())
	if not dim_error.is_empty():
		_resolved_error = dim_error
		return false

	var use_jpeg := prefer_jpeg and prepared.detect_alpha() == Image.ALPHA_NONE
	if use_jpeg:
		_resolved_bytes = prepared.save_jpg_to_buffer(_JPG_QUALITY)
		_resolved_content_type = "image/jpeg"
	else:
		_resolved_bytes = prepared.save_png_to_buffer()
		_resolved_content_type = "image/png"

	if _resolved_bytes.is_empty():
		_resolved_error = "Failed to encode Image."
		return false
	if _resolved_bytes.size() > MAX_FILE_BYTES:
		_resolved_error = "Encoded image exceeds 16 MiB file size limit."
		return false
	return true
