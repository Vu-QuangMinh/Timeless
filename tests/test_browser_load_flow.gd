extends SceneTree

# Mirrors the EXACT live F6 flow: instantiate AssetEditor, open the browser via
# Ctrl+O path, programmatically select the laser_sensor entry, trigger
# `_on_asset_browser_confirmed` (after the auto-hide fix), and verify _polygons
# is populated. If this test passes but the live game shows empty polygons,
# the divergence is somewhere else (Godot scene tree side-effect).
# Run: godot --headless -s tests/test_browser_load_flow.gd

const TARGET_NAME := "laser_sensor"


func _initialize() -> void:
	var fail := 0
	var pass_ := 0

	var script := load("res://scripts/asset_editor.gd")
	var editor: Node = script.new()
	root.add_child(editor)
	await process_frame
	await process_frame

	# Open the asset browser the same way Ctrl+O would.
	editor.call("_open_asset_browser")
	await process_frame

	var browser = editor.get("_asset_browser")
	var browser_list = editor.get("_asset_browser_list")
	var entries: Array = editor.get("_asset_browser_entries")

	if entries.size() > 0:
		pass_ += 1
		print("PASS  browser scanned %d entries from disk" % entries.size())
	else:
		fail += 1
		printerr("FAIL  browser scan returned 0 entries — _scan_palette can't see assets")

	# Find an Artifact/laser_sensor entry in the scan.
	var target_idx := -1
	for i in range(entries.size()):
		var e: Dictionary = entries[i]
		if e.get("name", "") == TARGET_NAME:
			target_idx = i
			break
	if target_idx >= 0:
		pass_ += 1
		print("PASS  found '%s' at index %d → %s" % [TARGET_NAME, target_idx, entries[target_idx]["json_path"]])
	else:
		fail += 1
		printerr("FAIL  no entry named '%s' in scan" % TARGET_NAME)
		quit(1)
		return

	# Select it in the list (mimics single-click) and dispatch confirmed.
	browser_list.select(target_idx)
	if browser_list.is_selected(target_idx):
		pass_ += 1
		print("PASS  ItemList.select(%d) registered" % target_idx)
	else:
		fail += 1
		printerr("FAIL  ItemList.select did not register")

	# This is the path the OK button takes.
	editor.call("_on_asset_browser_confirmed")
	await process_frame

	var polys: Array = editor.get("_polygons")
	if polys.size() == 2:
		pass_ += 1
		print("PASS  after confirmed: _polygons.size = 2")
	else:
		fail += 1
		printerr("FAIL  after confirmed: _polygons.size = %d (expected 2)" % polys.size())

	# Now repeat via the double-click path (item_activated → hide + confirmed).
	# Reset _polygons first.
	editor.set("_polygons", [])
	browser.popup_centered()
	await process_frame
	browser_list.select(target_idx)
	editor.call("_on_asset_browser_item_activated", target_idx)
	await process_frame

	var polys2: Array = editor.get("_polygons")
	if polys2.size() == 2:
		pass_ += 1
		print("PASS  after item_activated (double-click path): _polygons.size = 2")
	else:
		fail += 1
		printerr("FAIL  after item_activated: _polygons.size = %d (expected 2)" % polys2.size())

	# Verify list selection survived the hide() call inside item_activated.
	# (If hide() clears selection, get_selected_items() returns [], and
	# _on_asset_browser_confirmed early-returns without loading.)
	editor.set("_polygons", [])
	browser.popup_centered()
	await process_frame
	browser_list.select(target_idx)
	browser.hide()
	await process_frame
	var sel_after_hide: PackedInt32Array = browser_list.get_selected_items()
	if sel_after_hide.size() > 0 and sel_after_hide[0] == target_idx:
		pass_ += 1
		print("PASS  ItemList selection survived browser.hide()")
	else:
		fail += 1
		printerr("FAIL  ItemList selection lost after hide() (sel = %s) — this would make confirmed early-return" % sel_after_hide)

	editor.queue_free()
	print("---")
	print("Total: %d passed, %d failed" % [pass_, fail])
	quit(0 if fail == 0 else 1)
