class_name BorderPanel
extends MarginContainer

const _CORNER_PATH := "res://assets/ui/context/corner.png"
const _EDGE_PATH   := "res://assets/ui/context/edge.png"

const BG_COLOR   := Color("3F414E")
const DRAW_SCALE := 0.2   # max scale; corners shrink automatically for small panels

var _corner: Texture2D
var _edge:   Texture2D
var _raw_cw: float = 0.0  # corner natural width
var _raw_ch: float = 0.0  # corner natural height


func _ready() -> void:
	_corner = load(_CORNER_PATH) as Texture2D
	_edge   = load(_EDGE_PATH)   as Texture2D
	if _corner:
		_raw_cw = float(_corner.get_width())
		_raw_ch = float(_corner.get_height())

	# Content inset = corner height at max scale (edge thickness matches corner height)
	var m := int(ceil(_raw_ch * DRAW_SCALE))
	add_theme_constant_override("margin_left",   m)
	add_theme_constant_override("margin_right",  m)
	add_theme_constant_override("margin_top",    m)
	add_theme_constant_override("margin_bottom", m)


func _draw() -> void:
	var W := size.x
	var H := size.y

	draw_rect(Rect2(0.0, 0.0, W, H), BG_COLOR)

	if _corner == null or _edge == null or _raw_cw == 0.0 or _raw_ch == 0.0:
		return

	# Dynamic scale so corners always fit
	var s := DRAW_SCALE
	s = minf(s, W / (2.0 * _raw_cw + 1.0))
	s = minf(s, H / (2.0 * _raw_ch + 1.0))
	s = maxf(s, 0.01)

	var cw := _raw_cw * s
	var ch := _raw_ch * s  # edge thickness on all 4 sides = corner height

	var h_span := maxf(W - 2.0 * cw, 0.0)
	var v_span := maxf(H - 2.0 * ch, 0.0)

	# ── Edges (drawn first so corners render on top) ───────────────────────────

	# Top: rotate CW 90°, strip height = ch
	# Origin (cw+h_span, 0) + θ=+π/2: world = (origin.x - ly, lx)
	#   lx ∈ [0, ch]     → world y ∈ [0, ch]
	#   ly ∈ [0, h_span] → world x ∈ [cw+h_span, cw]
	if h_span > 0.0:
		draw_set_transform(Vector2(cw + h_span, 0.0), PI * 0.5)
		draw_texture_rect(_edge, Rect2(0.0, 0.0, ch, h_span), false)
		draw_set_transform(Vector2.ZERO, 0.0)

	# Bottom: rotate CCW 90°, strip height = ch
	# Origin (cw, H) + θ=-π/2: world = (cw+ly, H-lx)
	#   lx ∈ [0, ch]     → world y ∈ [H, H-ch]
	#   ly ∈ [0, h_span] → world x ∈ [cw, cw+h_span]
	if h_span > 0.0:
		draw_set_transform(Vector2(cw, H), -PI * 0.5)
		draw_texture_rect(_edge, Rect2(0.0, 0.0, ch, h_span), false)
		draw_set_transform(Vector2.ZERO, 0.0)

	# Left: rotate CW 90° (same direction as right), strip width = cw
	# Origin (cw, ch) + θ=+π/2: world = (cw-ly, ch+lx)
	#   lx ∈ [0, v_span]  → world y ∈ [ch, H-ch]   (top→bottom, same as right)
	#   local_y ∈ [cw→0]  → world x ∈ [0, cw]       (outer→inner)
	# Rect y-flip (cw, -cw) so texture outer face (y=0) lands at world x=0.
	if v_span > 0.0:
		draw_set_transform(Vector2(cw, ch), PI * 0.5)
		draw_texture_rect(_edge, Rect2(0.0, cw, v_span, -cw), false)
		draw_set_transform(Vector2.ZERO, 0.0)

	# Right: rotate CW 90°, strip width = cw (corner width)
	# Origin (W, ch) + θ=+π/2: world = (W-ly, ch+lx)
	#   lx ∈ [0, v_span] → world y ∈ [ch, H-ch]
	#   ly ∈ [0, cw]     → world x ∈ [W, W-cw]
	if v_span > 0.0:
		draw_set_transform(Vector2(W, ch), PI * 0.5)
		draw_texture_rect(_edge, Rect2(0.0, 0.0, v_span, cw), false)
		draw_set_transform(Vector2.ZERO, 0.0)

	# ── Corners (on top of edges) ──────────────────────────────────────────────
	draw_texture_rect(_corner, Rect2(0.0, 0.0,  cw,  ch), false)  # TL: normal
	draw_texture_rect(_corner, Rect2(W,   0.0, -cw,  ch), false)  # TR: flip H
	draw_texture_rect(_corner, Rect2(W,   H,   -cw, -ch), false)  # BR: 180°
	draw_texture_rect(_corner, Rect2(0.0, H,    cw, -ch), false)  # BL: flip V
