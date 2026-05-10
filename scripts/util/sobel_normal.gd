class_name SobelNormal
extends RefCounted

# Sobel-from-diffuse normal-map generation. Treats the input as a heightmap
# (using luminance), runs a 3x3 Sobel kernel for X and Y gradients, then
# encodes the (-gx, -gy, strength) normal into RGB. Output uses Godot's
# default normal-map convention (R=X+, G=Y-, B=Z+; tangent space).
#
# Usage:
#   var normal_img := SobelNormal.generate(diffuse_image)
#
# Per-pixel GDScript is slow on large textures (the F6 editor accepts the
# tradeoff because saves are infrequent and editor-only).

const DEFAULT_STRENGTH := 4.0


static func generate(image: Image, strength: float = DEFAULT_STRENGTH) -> Image:
	var w := image.get_width()
	var h := image.get_height()
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	if w == 0 or h == 0:
		return out

	for y in range(h):
		for x in range(w):
			var l_x_minus := _luminance(image, x - 1, y, w, h)
			var l_x_plus  := _luminance(image, x + 1, y, w, h)
			var l_y_minus := _luminance(image, x, y - 1, w, h)
			var l_y_plus  := _luminance(image, x, y + 1, w, h)
			var l_xm_ym := _luminance(image, x - 1, y - 1, w, h)
			var l_xp_ym := _luminance(image, x + 1, y - 1, w, h)
			var l_xm_yp := _luminance(image, x - 1, y + 1, w, h)
			var l_xp_yp := _luminance(image, x + 1, y + 1, w, h)

			# Sobel kernel:
			#   gx = (xp_ym + 2*xp + xp_yp) - (xm_ym + 2*xm + xm_yp)
			#   gy = (xm_yp + 2*yp + xp_yp) - (xm_ym + 2*ym + xp_ym)
			var gx := (l_xp_ym + 2.0 * l_x_plus + l_xp_yp) - (l_xm_ym + 2.0 * l_x_minus + l_xm_yp)
			var gy := (l_xm_yp + 2.0 * l_y_plus + l_xp_yp) - (l_xm_ym + 2.0 * l_y_minus + l_xp_ym)

			var nx := -gx * strength
			var ny := -gy * strength
			var nz := 1.0
			var inv_len := 1.0 / sqrt(nx * nx + ny * ny + nz * nz)
			nx *= inv_len
			ny *= inv_len
			nz *= inv_len

			var alpha := image.get_pixel(x, y).a
			out.set_pixel(x, y, Color(
				nx * 0.5 + 0.5,
				ny * 0.5 + 0.5,
				nz * 0.5 + 0.5,
				alpha,
			))
	return out


static func _luminance(image: Image, x: int, y: int, w: int, h: int) -> float:
	var cx := clampi(x, 0, w - 1)
	var cy := clampi(y, 0, h - 1)
	var c := image.get_pixel(cx, cy)
	# Rec. 709 luma weights.
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
