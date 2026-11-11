extends RefCounted

const BOUNDS := Rect2(-136, -88, 272, 176)
static var height_image: Image

static func sample_ground_height(x: float, z: float) -> float:
	if height_image == null:
		height_image = load("res://render_v10/assets/heightfield.res") as Image
	var uv := (Vector2(x,z) - BOUNDS.position) / BOUNDS.size
	var pixel := uv * Vector2(height_image.get_size()) - Vector2.ONE * .5
	var ix := clampi(floori(pixel.x), 0, height_image.get_width()-2)
	var iz := clampi(floori(pixel.y), 0, height_image.get_height()-2)
	var f := (pixel - Vector2(ix,iz)).clamp(Vector2.ZERO, Vector2.ONE)
	var top := lerpf(height_image.get_pixel(ix,iz).b, height_image.get_pixel(ix+1,iz).b, f.x)
	var bottom := lerpf(height_image.get_pixel(ix,iz+1).b, height_image.get_pixel(ix+1,iz+1).b, f.x)
	return lerpf(top, bottom, f.y) * .5
