class_name TextureLoader
extends RefCounted
## Decodes client image files (BMP, TGA, JPG, PNG) to RGBA8 Images.
## RO BMPs use pure magenta as the transparent colour key.


static func load_image(data: PackedByteArray, path: String) -> Image:
	if data.is_empty():
		return null
	var img := Image.new()
	var err: Error
	match path.get_extension().to_lower():
		"bmp": err = img.load_bmp_from_buffer(data)
		"tga": err = img.load_tga_from_buffer(data)
		"jpg", "jpeg": err = img.load_jpg_from_buffer(data)
		"png": err = img.load_png_from_buffer(data)
		_: return null
	if err != OK:
		return null
	img.convert(Image.FORMAT_RGBA8)
	if path.get_extension().to_lower() == "bmp":
		key_magenta(img)
	return img


## Makes near-magenta pixels (R,B >= 0xFE, G <= 0x01) fully transparent.
static func key_magenta(img: Image) -> void:
	var px := img.get_data()
	var keyed := false
	for i in range(0, px.size(), 4):
		if px[i] >= 0xFE and px[i + 1] <= 0x01 and px[i + 2] >= 0xFE:
			px[i] = 0
			px[i + 1] = 0
			px[i + 2] = 0
			px[i + 3] = 0
			keyed = true
	if keyed:
		img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, px)
