class_name ShortcutPanel
extends RefCounted

# Builds a self-contained PanelContainer that lists shortcuts as a two-column
# table grouped by category. Caller is responsible for anchoring/positioning
# the returned Control inside its own UI layer. Each F-key mode (F4/F5/F6)
# instantiates one with its own SHORTCUTS array and title.
#
# Each shortcut entry: {"category": String, "key": String, "desc": String}
#
# Long lists are scrollable: the panel caps at MAX_HEIGHT_PX and a vertical
# scrollbar appears if content overflows.

const PANEL_WIDTH_PX := 240
const MAX_HEIGHT_PX := 360
const KEY_COLUMN_WIDTH_PX := 88

const BG_COLOR := Color(0.05, 0.05, 0.08, 0.7)
const TITLE_COLOR := Color(1.0, 1.0, 1.0)
const CATEGORY_COLOR := Color(0.65, 0.85, 1.0)
const KEY_COLOR := Color(1.0, 0.95, 0.55)
const DESC_COLOR := Color(0.9, 0.9, 0.92)
const TITLE_SIZE := 13
const ENTRY_SIZE := 10
const CORNER_RADIUS := 6


static func build(title: String, shortcuts: Array) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH_PX, 0)
	panel.add_theme_stylebox_override("panel", _make_stylebox())

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Forces the scroll view to cap at MAX_HEIGHT_PX; content above that scrolls.
	# (Setting it on the ScrollContainer itself works because ScrollContainer
	# only honors its child's minimum height up to its own custom size.)
	scroll.size_flags_vertical = Control.SIZE_SHRINK_END
	panel.add_child(scroll)

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
	scroll.add_child(v)

	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.add_theme_font_size_override("font_size", TITLE_SIZE)
	title_lbl.add_theme_color_override("font_color", TITLE_COLOR)
	v.add_child(title_lbl)

	var sep := HSeparator.new()
	v.add_child(sep)

	# Group entries by category, preserving first-seen order.
	var groups := {}
	var order: Array = []
	for s in shortcuts:
		var cat: String = s.get("category", "")
		if not groups.has(cat):
			groups[cat] = []
			order.append(cat)
		(groups[cat] as Array).append(s)

	for cat in order:
		var cat_lbl := Label.new()
		cat_lbl.text = String(cat)
		cat_lbl.add_theme_font_size_override("font_size", ENTRY_SIZE)
		cat_lbl.add_theme_color_override("font_color", CATEGORY_COLOR)
		v.add_child(cat_lbl)
		for entry in groups[cat]:
			v.add_child(_make_entry_row(entry))

	return panel


static func _make_stylebox() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_COLOR
	sb.corner_radius_top_left = CORNER_RADIUS
	sb.corner_radius_top_right = CORNER_RADIUS
	sb.corner_radius_bottom_left = CORNER_RADIUS
	sb.corner_radius_bottom_right = CORNER_RADIUS
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


static func _make_entry_row(entry: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var key_lbl := Label.new()
	key_lbl.text = String(entry.get("key", ""))
	key_lbl.add_theme_font_size_override("font_size", ENTRY_SIZE)
	key_lbl.add_theme_color_override("font_color", KEY_COLOR)
	key_lbl.custom_minimum_size = Vector2(KEY_COLUMN_WIDTH_PX, 0)
	key_lbl.clip_text = true
	row.add_child(key_lbl)
	var desc_lbl := Label.new()
	desc_lbl.text = String(entry.get("desc", ""))
	desc_lbl.add_theme_font_size_override("font_size", ENTRY_SIZE)
	desc_lbl.add_theme_color_override("font_color", DESC_COLOR)
	desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(desc_lbl)
	return row
