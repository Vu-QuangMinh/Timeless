# Changelog — 2026-05-12 (F4 patrol routes — Phases 2–6 + unreachable rejection)

**Editor:** Banana
**Scope:** Builds out the F4 guard-patrol feature on top of Phase 1 (commit `1da00d5`, which added the enemy-selection panel and the `_patrol_data` dict). Phases 2–6 land here: P-toggled edit mode with add/delete/drag, pathfinder-routed line previews with `O`-toggle visibility, "Simulate Patrol" ping-pong animation, save-format extension, and help-panel update. One spec extension on top: placement reachability is enforced at edit-time with an `AcceptDialog` popup instead of being a render-only fallback.

## New files

### Tests
- `tests/test_patrol_phase2.gd` — 17 assertions covering P-toggle, add/delete/drag point with undo, status-label refresh, dirty marking, selection-change auto-exit, `_patrol_exit_edit_mode` direct call.
- `tests/test_patrol_phase3.gd` — 12 assertions: per-guard polyline cache (2 segments for 3 points), all-reachable classification in obstacle-free levels, `IsoMath.project`-equivalent endpoint values, cache invalidation on add/drag/undo, `O` key toggle of `_show_all_patrols`, `_force_deactivate` resets flag + cache.
- `tests/test_patrol_phase4.gd` — 15 assertions: `_simulating` state transitions, one `Tween` per ≥2-point guard, `<2`-point guards skipped, pre-position capture/restore, button label flip, guard moves during sim (verified by frame-stepped position comparison), `P` no-op during sim, F4-deactivate auto-stops.
- `tests/test_patrol_phase5.gd` — 11 assertions, full Level1 round-trip: palette-spawn fake_enemy → add patrol → save → JSON shape (`patrols` array, `[[x,y]]` points, `loop_mode`), `0`-point guards filtered out, reload restores `_patrol_data`, palette-spawned guard re-instantiates via `spawned_scenes`. Plus backward-compat (no `patrols` key) and drift (patrol references missing guard) — drift case `push_warning`s and keeps the data in memory.
- `tests/test_patrol_unreachable_rejection.gd` — 8 assertions: `_patrol_is_reachable` helper truthing, first-add bypass, second-add into a circular obstacle rejected (no append, no undo), drag-end into unreachable zone reverts to origin (no undo entry pushed). Geometry note: a closed wall-box doesn't actually create unreachable zones — pathfinder routes through the corners since `_segs_intersect` treats endpoint-touching as non-blocking. A circular obstacle centered on the target is what reliably forces `find_path → []`.

## Modified files

### `scripts/EditMode.gd` — Phases 2–6

**Phase 2 — edit mode + per-point operations:**
- New constants: `PATROL_POINT_PICK_RADIUS_M = 0.3` (right-click / drag pickup radius in world meters), `PATROL_MARKER_RADIUS_PX = 10.0` (screen-pixel circle radius).
- New state: `_patrol_edit_mode: bool`, `_patrol_edit_guard_name: String` (pins the edited guard so mid-flight selection moves don't desync), `_patrol_drag_idx: int = -1`, `_patrol_drag_origin: Vector2` (for revert-on-unreachable).
- Action methods (all directly callable so the headless test can drive them without simulating mouse events): `_patrol_toggle_edit_mode`, `_patrol_exit_edit_mode`, `_patrol_index_near(world_pos)`, `_patrol_add_point_at(world_pos)`, `_patrol_delete_at(world_pos)`, `_patrol_drag_begin/update/end`.
- Undo cases added: `patrol_add` (removes the appended point), `patrol_delete` (re-inserts at original index with original position), `patrol_move` (restores the original position). All flow through the existing `undo_stack` so `Ctrl+Z` cascade behavior matches every other F4 edit and `_discard_changes` rewinds them.
- Input wiring: `KEY_P` in the F4 keyboard handler routes to `_patrol_toggle_edit_mode`; `KEY_ESCAPE` exits patrol-edit before falling through to its existing palette-drag-cancel / quit cascade. While `_patrol_edit_mode` is true, mouse-button and motion handlers short-circuit through patrol routing (left-click → drag-or-add depending on `_patrol_index_near`; right-click → delete; motion → live drag-update). Other F4 mouse handlers (selection, drag-to-move, scale handles, multi-select) are suppressed via the same `_palette_dragging`-style early-return pattern.
- Selection-change auto-exit: `_on_object_button_pressed` checks `_patrol_edit_mode` first and exits before committing the new selection. `_force_deactivate` exits patrol-edit too.
- Marker rendering in `_draw`: red filled circle of radius `10/zoom` screen-px with a darker `1.5/zoom` border, white index number (1, 2, …) centered. Rendered for the currently-selected enemy regardless of edit-mode state — selecting a guard surfaces its route at a glance.
- Phase 1 hint label "Press P to edit (Phase 2)" updated to "Press P to edit".

**Phase 3 — pathfinder-routed line previews:**
- New constants: `PATROL_ARC_STEPS = 16` (matches `PathPreview.ARC_STEPS` for visual consistency), `PATROL_LINE_W = 2.0`, `PATROL_DASH_ON/OFF = 8.0/6.0` (screen pixels), `COLOR_PATROL_REACHABLE = (0.3, 0.9, 1.0, 0.8)` (cyan), `COLOR_PATROL_UNREACHABLE = (1.0, 0.2, 0.2, 0.8)` (red).
- New preload: `WorldObstaclesScript = preload("res://scripts/pathing/world_obstacles.gd")` (no `class_name` to avoid the editor-scan registration cost).
- New state: `_patrol_line_cache: Dictionary` (guard_name → Array of `{reachable: bool, polyline: Array[Vector2] iso-pixel}` or `{reachable: false, p0/p1}`), `_show_all_patrols: bool`.
- New methods:
  - `_build_patrol_path_inputs` — mirrors `main.gd:_build_path` so the F4 preview reflects what the runtime pathfinder will see (hardcoded `level.get_wall_segments()` + `WorldObstacles.collect_wall_segments(level)` + chest obstacle).
  - `_rebuild_patrol_line(guard_name)` — runs `Pathfinder.find_path` + `PathSmoother.smooth` per consecutive pair of points; samples each `MovePath` at 16 sub-steps per arc; projects via `IsoMath.project` and caches as a polyline. Unreachable segments cache the projected endpoints for the dashed-line fallback.
  - `_movepath_to_polyline(mp)` — segment-sampling helper; matches `PathPreview._draw_path`'s fidelity exactly.
  - `_draw_patrol_lines(guard_name, view_zoom)` — lazily rebuilds cache on miss; cyan solid for reachable, red dashed for unreachable.
  - `_draw_dashed_line(p0, p1, col, line_w, z)` — 8 px on / 6 px off pattern with zoom-aware step sizing.
  - `_invalidate_patrol_line(guard_name)` — single-guard cache eviction.
- Cache invalidation strategy: `_persist()` clears the whole cache (covers add/delete/move/undo on patrol AND any other F4 edit that might move walls under existing routes). `_patrol_drag_update` invalidates the specific guard directly so the line follows the cursor in real-time without going through `_persist` (drag doesn't dirty-mark until release).
- `O` key (no Ctrl) toggles `_show_all_patrols`. When `true`, every guard's line draws; when `false`, only the currently-selected enemy's. F4-scoped: `_force_deactivate` resets to `false`.
- `_draw` order: patrol lines drawn first, then markers, so the numbered circles sit on top.

**Phase 4 — Simulate Patrol button:**
- New constants: `PATROL_BASE_SPEED_MPS = 1.25` (design.md guard speed).
- New state: `_simulating: bool`, `_sim_tweens: Array[Tween]`, `_sim_pre_positions: Dictionary` (guard_name → Vector2 iso-pixel), `_sim_button: Button`.
- New methods: `_toggle_simulate_patrol`, `_build_patrol_movepaths_pingpong(guard_name)` (returns `[]` for `<2` points or any unreachable segment — broken patrols refuse to simulate rather than animate through walls), `_find_guard_node(guard_name)`, `_set_guard_at_path_frac(guard, path, frac)` (stale guard refs no-op via `is_instance_valid`), `_start_patrol_simulation`, `_stop_patrol_simulation`, `_update_sim_button_label`.
- One `Tween` per qualifying guard, created on the level root with `set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)` so it survives any game-pause F4 may trigger; `set_loops()` for forever-repeat. Forward (0→…→N-1) then backward (N-1→…→0) MovePaths queued sequentially; setter does `guard.global_position = IsoMath.project(path.position_at(frac))`. Backward paths are recomputed fresh (not reversed) because `PathSmoother`'s arc-choice can differ direction-wise.
- Effective speed: `effective_movespeed` meta if present, else `1.25 m/s × GameManager.ANIMATION_SPEED_MULTIPLIER (5×) = 6.25 m/s`.
- Button placement: appended to the palette panel between the asset scroll and the patrol section. Always visible (independent of selection) — spec: "Other F4 features remain available but tweens keep running." Label flips between "Simulate Patrol" / "Stop Simulation".
- `KEY_P` no-ops while `_simulating` (gated inside `_patrol_toggle_edit_mode`).
- `_force_deactivate` auto-stops sim and restores positions (covers F4 toggle-off, cross-mode switch to F5/F6, exit-confirm Discard).

**Phase 5 unreachable-rejection extension (user-requested, not in original spec):**
- New state: `_patrol_error_dialog: AcceptDialog = null` (lazily built on first error).
- New methods: `_patrol_is_reachable(from, to)` — single-pair pathfinder check sharing inputs with the line-render path; `_show_patrol_unreachable_popup(msg)` — lazy AcceptDialog mounted on the F4 `_ui_layer`.
- `_patrol_add_point_at` now refuses placement (no append, no undo) and pops the error if `pts.size() >= 1` and the new segment is unreachable.
- `_patrol_drag_end` now checks BOTH touching segments (incoming from `pts[idx-1]` and outgoing to `pts[idx+1]`). If either fails, the point snaps back to `_patrol_drag_origin`, the cache is invalidated, and the popup fires — no undo entry. Mid-drag `_patrol_drag_update` is intentionally NOT gated; the red dashed line preview is the in-flight feedback.
- Phase 3's red-dashed render branch isn't dead code: it still triggers when level walls move under previously-reachable points (or, post-Phase 5, when a save loads with points whose surroundings have since changed).

**Phase 6 — help panel + this changelog:**
- `SHORTCUTS` const extended with a `Patrol` category: P (toggle edit), Esc (exit edit), Left Click (add), Right Click (delete near a point), Drag (move), O (toggle all-guards visible). `ShortcutPanel.build` groups by first-seen category order — no rendering changes needed; the new section appears at the bottom and scrolls if the panel overflows its `MAX_HEIGHT_PX = 360`.

### `scenes/level_1/level_1.gd` — patrol save/load

- `save_edits_to(path)` now collects `_patrol_data` from the EditMode child and writes a top-level `patrols` array. Guards with 0 points are filtered out at save time (Phase 1 auto-creates empty entries on first selection; persisting those would bloat the save). Points serialized as `[[x, y], ...]` in world meters; `loop_mode` carried through (`"ping_pong"` default).
- `_apply_saved_edits(path)` now calls `_apply_patrols(parsed.get("patrols", []))` AFTER `_apply_spawned_scenes` so palette-spawned guards exist when the name cross-check runs.
- New method `_apply_patrols(patrols)`:
  - Defensive: skip whole block if EditMode child or `_patrol_data` field is missing.
  - For each entry, hydrate points to `Array[Vector2]`, write `_patrol_data[guard_name] = {points, loop_mode}` even if the guard is missing from `Objects` — spec: "keep it in patrol_data anyway in case the guard reappears, but log that this happened."
  - `push_warning` per missing-guard reference so save drift is visible.
  - Clears `_patrol_line_cache` after the load (the data didn't reach EditMode through `_persist`, so the cache wasn't auto-invalidated).
- Backward compat: missing `patrols` key parses as empty array.

## Save format addition — `user://level_1_edits.json` schema v2 (extended again)

A new top-level `patrols` array alongside `transforms`, `deleted`, `spawned_scenes`. Per-entry shape:

```
{
  "guard_name": "fake_enemy_1",
  "points": [[x, y], [x, y], ...],
  "loop_mode": "ping_pong"
}
```

- `guard_name` matches the node name under `Objects/`.
- `points` are world meters (the same unit Pathfinder operates in).
- `loop_mode` is currently always `"ping_pong"`; reserved for future loop conventions.
- Old saves missing `patrols` load cleanly (treated as empty array).
- The `version` field stays at `2` — patrols are an additive backward-compatible extension, same precedent as `spawned_scenes` (added in the 2026-05-10 entry without bumping version).

## Simulation behavior

- Ping-pong cycle: forward (0→1→…→N-1) then backward (N-1→…→0). The renderer (Phase 3) and the simulation (Phase 4) both refuse to draw / animate a wrap-around segment from N-1 to 0 — that's the ping-pong contract.
- Sim speed: `1.25 m/s` baseline × `GameManager.ANIMATION_SPEED_MULTIPLIER (5×)` = `6.25 m/s` effective. Per-guard override via `effective_movespeed` meta on the guard node.
- Pre-simulate positions captured per guard at sim start and restored on stop OR on F4 deactivate. Sim is strictly F4-scoped — never carries state across mode switches.

## Unreachable-rejection design note

The spec ("Phase 3 — Patrol lines via pathfinder") originally framed unreachable segments as a render-only fallback (red dashed line). The user requested at the Phase 3 → Phase 4 boundary that unreachable placements be rejected outright with a popup. We kept the dashed-line render path because it still fires for the "level walls changed under existing patrol points" case and for Phase 5 saves whose surroundings have since changed.

## Test convention note

Two test gotchas worth recording for future patrol / pathfinder work:

1. Autoloads (`IsoMath`, `GameManager`) are NOT in scope from `extends SceneTree` test scripts at compile time, even though they're registered as autoloads in `project.godot`. They ARE in scope from regular gameplay scripts (like `EditMode.gd`). Workaround in tests: inline the math (`IsoMath.project((0,0)) == Vector2.ZERO` so the assertion just compares against `Vector2.ZERO`).
2. To force a `Pathfinder.find_path → []` (truly unreachable) in test geometry, use a **circular obstacle centered on the target**, not a closed wall box. A wall box doesn't enclose anything tighter than 2×CHAR_RADIUS so pathfinder routes through corners; `_segs_intersect` also treats endpoint-touching as non-blocking, which lets paths slip through wall tips.



**Editor:** Banana
**Scope:** F4 asset palette (panel UI + drag-to-spawn + save round-trip), Ctrl+C/V clipboard refactor, F6 asset-browser UX fix, pathfinder reads spawned-wall geometry from the scene tree.

## New files

### Scripts
- `scripts/pathing/world_obstacles.gd` — extracts pathfinder-format wall segments from any scene subtree. Walks for `CollisionPolygon2D` whose parent is a `CollisionObject2D` with `collision_layer` bit 0 set (StaticBody2D / CharacterBody2D — physics layer). Skips Area2Ds on layer 2 (recognition zones, not movement obstacles). Pulls each polygon vertex through the parent body's `global_transform`, then unprojects iso-pixel → world meters via inline iso math (autoload constants duplicated so the helper is unit-testable in isolation). Returns `Array of {a, b}` matching the existing `wall_segs` schema. No `class_name` — preloaded by callers to avoid the editor-scan-required global registration.

### Tests
- `tests/test_palette_scan.gd` — synthesizes a fake `res://assets/palette/` tree (one Camera scene-only entry, one Wall asset with both `.tscn` and `.tres`, one standalone Artifact `.tres`) and asserts the F4 palette scanner returns 3 entries with the right categories, and that the paired `.tres` is correctly deduped against its `.tscn` sibling. **5/5 pass.**
- `tests/test_palette_spawn.gd` — Phase 2 round-trip: builds a synthetic palette `.tscn`, instantiates Level1 with a scratch save path, programmatically spawns the asset via EditMode → `_spawn_palette_asset`, asserts the node lands in `Objects/test_widget_1` at the right position with `palette_source` metadata, saves to disk, asserts the JSON has the new `spawned_scenes` array (and the spawn is NOT duplicated in `transforms`), tears down, re-instantiates Level1 with the same save, asserts the spawn re-appears at the saved position with metadata restored. Backward compat: a legacy save with no `spawned_scenes` key still loads. Adds regression checks for the bug-fix turn: `_world_bounds(spawned)` non-null, `_hit_test(spawned, center)` true, `Ctrl+C` → `Ctrl+V` smart naming (`test_widget_2`, `_3`, `_4`), stair-stepped paste offset, re-`Ctrl+C` resets the offset, `_smart_copy_name('Floor') == 'Floor_1'`. **20/20 pass.**
- `tests/test_asset_load.gd` — F6 Ctrl+O round-trip: saves an asset with two polygons, wipes editor state, calls `_load_asset` on the saved `borders.json`, asserts `_polygons` is repopulated (count, types, vertex coords) AND `_preview.polygons` AND `_preview.image_size` are correct. **9/9 pass.**
- `tests/test_spawned_collision.gd` — synthesizes a `StaticBody2D` + `CollisionPolygon2D` (4-vert box) at iso-pixel `(200, 0)`, asserts `WorldObstacles.collect_wall_segments(root)` returns 4 edges in world meters (not pixels), seeds a fresh Pathfinder with those segments, asserts `find_path` routes around the box (>2 waypoints), and confirms an Area2D with `collision_layer = 2` is skipped. **4/4 pass.**

## Modified files

### `scripts/EditMode.gd` — F4 asset palette + bug fixes

**Phase 1 — palette panel UI:**
- New constants: `PALETTE_ROOT = "res://assets/palette"`, `PALETTE_CATEGORY_ORDER = [Camera, Enemy, Wall, Door, Lock, Artifact]`.
- New fields: `_palette_panel: PanelContainer`, `_palette_list: VBoxContainer`.
- `_build_ui` now appends `_build_palette_panel()` after the help-panel block. Anchored right-edge full-height with `offset_bottom = -300` to leave room for the bottom-right help panel.
- `_build_palette_panel()` builds: header (title "Assets" + Refresh button) → ScrollContainer → VBoxContainer rows.
- `_refresh_palette()` clears + repopulates from `_scan_palette()`; renders empty-state Label if no entries; groups entries by category in `PALETTE_CATEGORY_ORDER` (unknown categories appended last); each category gets a small uppercase header in blue.
- `_scan_palette()` recursively walks `PALETTE_ROOT`. Collects every `*.tscn` (scene asset) and standalone `*.tres` (sprite asset) — paired `.tres` files in the same folder as a `.tscn` of the same basename are deduped (F6 saves both per asset; the `.tres` is referenced by the `.tscn`'s Sprite2D).
- `_palette_category_for(asset_path)` returns the first folder under `PALETTE_ROOT`.
- `_build_palette_entry(entry)` returns an HBoxContainer: 48×48 thumbnail + name Button (truncating, expand-fill, tooltip = full path).
- `_build_palette_thumbnail(entry)` extracts a Texture2D: scene assets → `_palette_thumb_from_scene` (instantiate, find first Sprite2D, grab texture, `queue_free`), sprite assets → `CanvasTexture.diffuse_texture`. Falls back to a 48×48 gray ColorRect placeholder.
- `_find_first_sprite(node)` DFS helper (used both by thumbnail extraction and Phase 2 ghost rendering).
- Visibility: `_toggle()` activate-branch sets `_palette_panel.visible = true` + calls `_refresh_palette()`; `_force_deactivate()` sets it false.

**Phase 2 — drag-from-palette to spawn:**
- New fields: `_palette_dragging: bool`, `_drag_payload: Dictionary` (type/path/category/name/ghost_scale), `_drag_ghost: Sprite2D`.
- Palette entry buttons fire on `button_down` instead of `pressed` so drag begins on press, not on click-release.
- `_on_palette_entry_button_down(e)` → `_start_palette_drag(e)`: cancels any in-progress F4 drag/scale, builds the ghost (Sprite2D in EditMode's world space, modulate alpha 0.5, `z_index = 4097`), sets cursor to `Input.CURSOR_DRAG`, populates `_drag_payload` and `_palette_dragging = true`.
- For .tscn ghosts: `_palette_scene_visual(path)` instantiates and finds the first Sprite2D, returning its texture + scale. For .tres ghosts: `CanvasTexture.diffuse_texture`.
- `_process_palette_drag()` (called from `_process` while dragging): hides the ghost while cursor is over a panel; updates ghost position to `IsoMath.project(IsoMath.unproject(get_global_mouse_position()))` (round-trip-identity per spec); polls `Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)` for release detection (Button's `button_up` signal isn't reliable for off-button release).
- `_resolve_palette_drag()`: if cursor over panel/outside-window → cancel; else → `_spawn_palette_asset(snapped_world_pos)` and `_finish_palette_drag()`.
- `_spawn_palette_asset(pos)`: scene → `load(path).instantiate()`; sprite → `Sprite2D.new()` with `centered = true` and `texture = CanvasTexture`. Parents under `/Level1/Objects` (via `_objects_node()`), assigns `_unique_palette_name(parent, basename)` (`<basename>_1`, `_2`, ...), adds to `editable` group, sets `set_meta("palette_source", path)` and `set_meta("palette_type", "scene"|"sprite")`, pushes `{action: "create"}` onto `undo_stack`, calls `_persist()` → `_mark_dirty()`.
- `_mouse_over_any_panel()` tests viewport mouse against `_ui_panel` / `_help_panel` / `_palette_panel` rects, plus a viewport-bounds check (cursor outside the window also counts as "over panel" → cancel).
- `_unhandled_input` gates the existing left-click and motion handlers with `if _palette_dragging: return`. New: Esc cancels drag without quitting; right-click during drag cancels.
- `_force_deactivate()` cancels in-flight drag before tearing down.

**Bug fixes:**
- `_world_bounds(node)` extended: if `node` isn't a Sprite2D, finds the first Sprite2D child and computes bounds from its `global_position` / `global_scale` / texture size. Spawned scene roots (StaticBody2D for Wall/Door/Lock, Area2D for Camera, Node2D for Enemy/Artifact) all carry their visual in a child Sprite2D — that's now what selection / scale handles use. Hit-test, scale handles, and the selection rectangle all flow through the new bounds.
- `_apply_scale_drag` rewritten to use a generic anchor-corner restore: after scaling, computes new bounds and shifts `selected.global_position` so the corner *opposite* the grabbed handle stays fixed at `scale_anchor_world`. Replaces the Sprite2D-only re-anchor branch; works for any node `_world_bounds` can compute.

**Ctrl+C / Ctrl+V clipboard:**
- New fields: `_clipboard: Array[Node2D]`, `_clipboard_paste_offset: Vector2`.
- Bare `C` no longer copies. Ctrl+C → `_copy_to_clipboard()` snapshots references from `multi_selected` and resets the per-clipboard offset; Ctrl+V → `_paste_clipboard()` increments the offset by `copy_offset = (32, 32)`, then duplicates each clipboard item with the smart name and stair-stepped position. Repeated Ctrl+V creates a stair (paste 1 = source + 32, paste 2 = source + 64, ...). Re-Ctrl+C resets the offset. Stale clipboard refs (deleted source) are skipped silently via `is_instance_valid`.
- `_smart_copy_name(parent, source_name)`: if source name ends in `_<digits>` (e.g. `test_widget_3`, `Painting_1`), keeps the basename and finds the next unused index after the source's number; otherwise (`CCTV`, `Door`) appends `_1`. Examples: copy of `test_widget_1` → `test_widget_2`; copy of `Painting_3` → `Painting_4`; copy of `CCTV` → `CCTV_1`.
- Replaces the old `_copy_selected` (bare-C handler).
- Old C-key handler removed; M (mirror) keybind unchanged.

**SHORTCUTS const updated:**
- Removed bare `C` entry; added `Ctrl+C → "Copy selection to clipboard"` and `Ctrl+V → "Paste clipboard"`. Help panel reflects the new bindings.

### `scripts/asset_editor.gd`

- F6 asset-browser auto-hide on double-click. ConfirmationDialog auto-hides on `confirmed` (the OK button); `item_activated` (double-click on an ItemList row) doesn't auto-hide. `_on_asset_browser_item_activated` now calls `_asset_browser.hide()` first so loaded polygons aren't obscured by the still-open browser. (Single-click + Load button worked before; double-click was the failure path the user reported as "load doesn't show polygons.")

### `scripts/main.gd`

- Preloads `WorldObstaclesScript` (no `class_name` to avoid Godot's editor-scan registration requirement).
- `_build_path` now combines the level's hardcoded `get_wall_segments()` with `WorldObstacles.collect_wall_segments(_level)` before passing to `Pathfinder.setup`. Spawned wall/door/lock/camera-body assets contribute their `CollisionPolygon2D` edges; the player's path now routes around them. Pathfinder algorithm itself unchanged — same visibility-graph + A*, just with a richer `wall_segs` input.

### `scenes/level_1/level_1.gd`

- `save_edits_to(path)` — schema v2 gains `spawned_scenes` top-level array. Walks `editable` group; nodes with `palette_source` metadata route to `spawned_scenes` (with `palette_type`, position, scale, rotation, z_index) regardless of node type; untagged Sprite2Ds still go to `transforms` (the .tscn-baseline path).
- `_apply_saved_edits(path)` — after the existing transforms pass, calls `_apply_spawned_scenes(spawned)`. Backward compat: missing `spawned_scenes` key = empty array.
- `_apply_spawned_scenes(spawned)` — for each entry, validates `ResourceLoader.exists(palette_source)` (`push_warning` and skip if missing on disk), instantiates as scene or builds Sprite2D for sprite-type, parents under the path stored in the entry (default `Objects`), restores position/scale/rotation/z_index, sets `palette_source` and `palette_type` metadata, adds to `editable` group.

## Save format addition — `user://level_1_edits.json` schema v2 (extended)

`spawned_scenes` is now an additional top-level array alongside `transforms` and `deleted`. Per-entry shape:

```
{
  "name": "test_widget_1",
  "parent": "Objects",
  "palette_source": "res://assets/palette/Test/test_widget/test_widget.tscn",
  "palette_type": "scene",   // "scene" or "sprite"
  "position": [x, y],
  "scale":    [sx, sy],
  "rotation": r,
  "z_index":  z
}
```

- `palette_source` points at the `.tscn` (for `palette_type: "scene"`) or `.tres` (for `palette_type: "sprite"`) under `res://assets/palette/`.
- `transforms` and `deleted` are unchanged. Old saves missing the `spawned_scenes` key load cleanly (treated as empty array).
- F4-spawned items carry `palette_source` and `palette_type` as Node metadata. `Node.duplicate()` preserves metadata, so `Ctrl+V` copies of palette spawns also round-trip through `spawned_scenes` — they're not silently downgraded to `transforms`.

## Pathfinder collision integration

The `Pathfinder` algorithm wasn't refactored. The integration is one-way: `WorldObstacles` extracts physics-layer geometry from the scene tree and appends to the existing `wall_segs` input. The pathfinder still uses pure-math segment intersection for LOS checks — no `PhysicsRayQueryParameters2D` calls. This was the smallest change that achieves the user-visible goal (spawned walls block movement) while keeping the existing pathfinder code and tests untouched. If a future phase wants the pathfinder to literally use Godot's physics for LOS, the data-extraction layer will still be useful (graph node generation needs to know where the walls are).

The collision-layer convention matches what F6's `_save_asset` writes:
- Wall/Door/Lock root: StaticBody2D with default `collision_layer = 1` → recognized as physics
- Camera root: Area2D with `collision_layer = 2` (recognition only) — **skipped** by `WorldObstacles`. Its child `Body` StaticBody2D (default `collision_layer = 1`) IS extracted, so cameras can still block movement.
- Enemy: child `Body` CharacterBody2D (default `collision_layer = 1`) extracted; root Node2D and Recognition Area2D skipped.
- Artifact: root Node2D + Recognition Area2D — no physics body, nothing to extract (artifacts are pickup-only).

Recognition Area2Ds (`collision_layer = 2`) are explicitly skipped by the `(co.collision_layer & COLLISION_LAYER_PHYSICS_BIT) != 0` check — they're for hover/interaction detection, not for blocking movement.

## Notable decisions

- **F4 palette panel cap-bottom instead of moving help panel.** Spec said "anchored right side, full-height" + "don't change... help panel". Made `_palette_panel.offset_bottom = -300` to leave room for the bottom-right help panel rather than relocating help elsewhere. Empty space at the bottom-right when help is shorter; palette scrolls if its content would exceed the available height. If you'd rather have help moved to bottom-left for F4 to free up the full right edge, easy follow-up.
- **`button_down` instead of custom `gui_input`** for palette drag start. Avoided a custom Control subclass — Buttons handle hover visualization for free; drag start is just a different signal. The `pressed` (release-over-button) signal is not connected — drag-start-only semantics.
- **Polling for drag motion / release in `_process`** instead of trying to listen via `_unhandled_input`. Buttons capture the mouse on press and release behavior across off-button drags is fiddly; polling is robust and runs only while `_palette_dragging` is true.
- **Cross-mode activation still force-closes silently** during palette drag (consistent with the earlier 2026-05-10 entry's mutual-exclusion design).
- **No `class_name` on `WorldObstacles`.** Godot's `class_name` global registration depends on the editor scan creating a `.uid` file. In pure headless test runs (no editor scan), the global identifier isn't visible, breaking parse. Preloading the script via `const Foo := preload("...")` works in both editor and headless contexts.
- **Pathfinder unchanged.** The user's "refactor pathfinder to query physics layer" intent is satisfied at the data layer (pathfinder now sees physics-layer geometry from the scene) without refactoring its visibility-graph + A* algorithm. If future work wants true physics raycasts for LOS, that's a follow-up.
- **F4 selection / drag / scale of spawned items.** The bug was `_world_bounds` only handling Sprite2D roots. Fix walks for the first Sprite2D child instead, and `_apply_scale_drag` uses a generic anchor-corner restore (works for any node `_world_bounds` can compute, not just Sprite2D roots).
- **Smart copy naming.** If source name ends in `_<digits>`, increment from there; otherwise append `_1`. Picks the next *unused* number under the parent, so a copy of `test_widget_1` produces `test_widget_2`, then `test_widget_3`, even if the user manually deleted `test_widget_2` between pastes. Avoids Godot's auto-suffix `@N` ugliness.
- **Stair-stepped paste offset.** Per-clipboard `_clipboard_paste_offset` accumulates `copy_offset` on each paste; Re-Ctrl+C resets. Three pastes in a row land at +1×, +2×, +3× offset instead of all overlapping at +1×.

# Changelog — 2026-05-10 (later, restoration retro)

**Editor:** Banana
**Scope:** Restore Objects + Lighting nodes wrongly characterized as "phantom" earlier today; wire up the long-missing F5 lights save layer; add a drift-warning safety net.

## What went wrong earlier today

The earlier 2026-05-10 entry (below) described loader-applied entries from `user://level_1_edits.json` as **"phantom sprites"** and treated them as stale junk to be defended against. That framing was wrong. The entries (`Door`, `CCTV`, `Painting_3`, `Laser_sensor`) — and the entire `Lighting` subtree (`SunY`, `CCTV_Light` + `ConeBeam`, `Laser` + `LaserBeam`) — were **real authored content** that had been removed from `level_1.tscn` in commit `14c6713 "Wipe source for iso-world rewrite"`. The user's save was the last surviving record of where those nodes sat. Defending the .tscn against the save was the inverse of the right move: the save was the source of truth and the .tscn was the regression.

Symptoms the user noticed: walls off-center after F4 saves no longer round-tripped to anything visible, F5 light edits never persisted across launches, no Door / CCTV / Painting / Laser ever appeared in the F4 panel.

Recovery source: `git show 9a83d03:scenes/level_1/level_1.tscn` (the original "Build Level 1 with iso normal-mapped lighting + F4/F5 editor modes" commit) had the full structure and baseline values. Three referenced scripts (`scripts/cctv_pan.gd`, `scripts/cone_beam.gdshader`, `scripts/laser_glow.gd`) had also been deleted in `14c6713` and were also recovered from `9a83d03`.

## Files restored from git

- `scripts/cctv_pan.gd` — `git show 9a83d03:scripts/cctv_pan.gd > scripts/cctv_pan.gd`
- `scripts/cone_beam.gdshader` — same recovery
- `scripts/laser_glow.gd` — same recovery

All three parse-clean and are referenced again by the restored scene tree.

## Files modified

### `scenes/level_1/level_1.tscn` (rewritten)
- `load_steps` raised to 16; new ext_resources for `Door.tres`, `CCTV.png`, `Painting_3.png`, `Laser_sensor.png`, `cctv_cone_light.png`, `cctv_cone_mat.tres`, `cctv_pan.gd`, `laser_glow.gd`.
- `Background/Floor`, `Wall_X`, `Wall_Y` switched from raw `.png` ext_resources back to `.tres` CanvasTexture wrappers (the form needed for normal-mapped lighting to render against the restored Lighting nodes).
- New `Objects` children at the **9a83d03 baseline values** (per user's instruction — keeps a meaningful baseline so F4 "discard all edits" has an escape hatch):
  - `Door` (Door.tres, scale 0.4327)
  - `CCTV` at (200, -200), scale 0.6
  - `Painting_3` at (0, -150), scale 0.5
  - `Laser_sensor` at (-200, -100)
  - All four in the `editable` group so F4 sees them.
- New `Lighting` Node2D between `Objects` and `EditMode` with:
  - `SunY` DirectionalLight2D — energy 1.2, height 1.0, color (1, 0.96, 0.88), rotation -30°
  - `CCTV_Light` PointLight2D at (200, -180), color (1, 0.18, 0.18), energy 1.5, height 0.5, cone_light texture, `cctv_pan.gd` attached (pan_amplitude_deg=30, pan_period_sec=4)
    - `ConeBeam` Polygon2D child with `cctv_cone_mat.tres` ShaderMaterial, polygon (0,0)/(-120,320)/(120,320), z_index 100, light_mask 0
  - `Laser` PointLight2D at (-300, -100), color (1, 0.2, 0.2), energy 1.0
    - `LaserBeam` Node2D child with `laser_glow.gd` attached, z_index 100
- Editor controllers (`EditMode`, `LightMode`, `AssetEditor`) preserved, still last in the children list so cross-mode `_unhandled_input` propagation order is unchanged.

### `scenes/level_1/level_1.gd` (lights save layer + drift warning)
**Phase 2 — port lights save/load layer (the "F5 still has no save plumbing" gap from earlier today):**
- New constants/fields: `DEFAULT_LIGHTS_PATH = "user://level_1_lights.json"`, `current_lights_path: String`, `_baseline_light_keys: Array`.
- `_init_editor_state()` now also calls `_capture_baseline_lights()` and `await _apply_saved_light_edits(current_lights_path)`.
- New `_all_lights() -> Array` — Light2D children of `Lighting` (defensive: empty if `Lighting` doesn't exist).
- New `_capture_baseline_lights()` — captures `_node_key` for each baseline Light2D.
- New `_apply_saved_light_edits(path)` — same defensive pattern as the objects loader: only applies properties to lights in the captured baseline; never instantiates missing entries.
- New `_apply_light_props(node, e)` — position, rotation, energy, color, height, texture_scale (PointLight2D only), `base_rotation_deg` (script-extended), enabled, plus per-overlay props (visible / opacity / cone_color shader param).
- New `save_light_edits_to(path) -> String` — writes Lighting subtree as JSON v1 (lights[] + overlays + deleted[]). `current_lights_path` updates after write.
- New `save_light_edits() -> String` — wraps `save_light_edits_to(current_lights_path)`. **This is the function `light_mode.gd:106` has been calling all along** — it used to silently no-op via the `has_method` guard.

**Phase 3 — drift warning safety net:**
- Added a `push_warning` loop at the top of both `_apply_saved_edits` and `_apply_saved_light_edits` (after the `by_key` map is built). For every save entry whose key isn't in the captured baseline, the warning fires with the entry name and an explanation. The save data is preserved in the JSON file untouched — only the in-scene apply is skipped. This is the safety net the previous session wished it had: scene/save drift is now visible in the console at launch instead of silently losing user content.

### `light_mode.gd`
Not modified. Already calls `owner.call_deferred("save_light_edits")` after every edit; that call resolves to the real function now instead of no-op'ing.

## Files created

- `tests/test_level_1_restore.gd` — headless verification that the restored .tscn loads, all 15 expected nodes exist (Background/Objects/Lighting subtrees + the three editor controllers), the user's save overrides .tscn baseline for both objects (`CCTV` at (196.67, -191.11) from save vs (200, -200) baseline; `Laser_sensor` at (-356.44, -10.23) from save vs (-200, -100) baseline) and lights (`CCTV_Light` at (221.11, -185.56) from save vs (200, -180) baseline), and that `save_light_edits_to(scratch_path)` round-trips a mutated `cctv_light.energy = 7.5` correctly. Cleans up the scratch file. **24/24 pass.**

## Persistence formats

### `user://level_1_lights.json` (now actually used)
The format documented in the 2026-05-08 changelog has been the live shape all along — the user's save file matched it correctly. Only the loader/writer plumbing was missing.

```
{
  "version": 1,
  "lights": [{
    name, parent, type, position, rotation, energy, color, height, texture, texture_scale,
    base_rotation_deg, enabled,
    overlays: [{name, visible, opacity, cone_color}, ...]
  }, ...],
  "deleted": [...]
}
```

## Notable decisions

- **9a83d03 baseline values used in the restored .tscn** (per user choice) — keeps a meaningful "baseline" separate from "current state." F4's discard-and-revert path is therefore still useful; user can always wipe the save to return to authored values.
- **Drift warning is a `push_warning`, not a hard error** — saves with stale entries still load correctly for matched nodes. The warning surfaces the mismatch without blocking the user from working.
- **Lights save layer mirrors the objects layer's API shape** (`save_light_edits_to(path) -> String`, `current_lights_path` field) even though `light_mode.gd` doesn't currently expose Save As — symmetry is cheap and leaves the door open if F5 grows that feature.
- **The earlier 2026-05-10 entry below has not been edited** — it stands as a record of the wrong characterization. This entry is the correction. If you re-read the original entry's "Phantom sprites bug discovered mid-Phase 1" bullet, replace it mentally with: "I deleted real content because I trusted the .tscn over the save, and the save was the actual source of truth. Restored in this entry."

---

# Changelog — 2026-05-10

**Editor:** Banana
**Scope:** F6 Asset Editor (4 phases) + F4 save layer + 3-way F-key mutual exclusion + shared shortcut help panel

## New files

### Scripts
- `scripts/asset_editor.gd` — F6 Asset Editor controller (extends Node). Full-screen overlay UI: top bar (Load PNG / filename / Close), left toolbar (Red Pen / Yellow Pen / Eraser / Cancel), center preview (instance of asset_editor_preview), right panel (zoom slider + polygon list + integrated help), bottom status bar (cursor px / tool / "Vertices placed: N"). Tool state machine, polygon storage, dirty tracking. Save Asset dialog (name + category + Sobel checkbox), Load Asset browser (scans `res://assets/palette/`). Ctrl+S / Ctrl+O / 1/2/3 / Enter / Esc / mouse-wheel zoom keybinds. `SHORTCUTS` const (11 entries, 4 categories).
- `scripts/asset_editor_preview.gd` — F6 center preview Control. Renders dark/checker background, the loaded PNG (centered, scaled by `zoom`), completed polygons (translucent fill + outline + vertex dots), in-progress polygon (lines + dots + dashed rubber-band to cursor). Forwards mouse/zoom intent via signals (`vertex_placed`, `polygon_close_requested`, `eraser_clicked`, `mouse_moved`, `zoom_step`). Documents the image-px ↔ Control-local coordinate conversion (image is centered in the rect and scaled by `zoom`).
- `scripts/util/sobel_normal.gd` — `class_name SobelNormal`, `static generate(image: Image, strength: float = 4.0) -> Image`. 3×3 Sobel kernel on luminance (Rec. 709 luma weights), encodes `(-gx, -gy, +z)` normalized into RGB tangent-space. Per-pixel GDScript — slow on large images, acceptable because saves are infrequent and editor-only. No prior call sites to refactor (the existing normal-map PNGs in `assets/level1/` and `assets/characters/hacker/` were generated by an external tool not in the repo).
- `scripts/util/shortcut_panel.gd` — `class_name ShortcutPanel`, `static build(title: String, shortcuts: Array) -> PanelContainer`. Builds a self-contained PanelContainer with semi-transparent dark `StyleBoxFlat` (alpha 0.7, rounded corners radius 6), title label, two-column key/desc rows grouped by category (subheader per category in blue). 240px wide, ScrollContainer inside for overflow. Caller anchors it.

### Tests
- `tests/test_asset_save.gd` — headless smoke test: loads `res://assets/level1/CCTV.png`, drops two test polygons (one collision, one recognition), calls `_save_asset("smoke_cctv", "Camera", true)`, verifies all 5 expected files exist (png/normal/tres/json/tscn), that `borders.json` round-trips polygon count + image size, and that the `.tscn` instantiates as Area2D with `collision_layer=2` and `recognition_priority=40`. Cleans up after itself. **12/12 pass.** Run: `godot --headless -s tests/test_asset_save.gd`.

## Modified files

### `scripts/EditMode.gd`
**Phase 1 — F4 dirty tracking + save layer plumbing + 3-way mutual exclusion:**
- New fields: `_dirty: bool`, `_clean_undo_size: int` (snapshot at F4 enter or last save), `_suppress_dirty: bool` (gates `_mark_dirty` during Discard).
- `_persist()` no longer hits disk — replaced with `_mark_dirty()` (deferred until explicit Save). Title label gets `*` suffix when dirty.
- New panel UI: path label ("Saving to: …"), `Save` and `Save As…` buttons, `FileDialog` rooted at `user://` with `.json` filter.
- Save: calls owner's `save_edits()`; resets `_clean_undo_size`. Save As: opens FileDialog → `save_edits_to(path)`.
- New `ConfirmationDialog` exit prompt with three buttons: **Discard** (OK button) / **Save** (custom action) / **Cancel**. Discard pops `undo_stack` back down to `_clean_undo_size` via existing `_undo()` (with `_suppress_dirty` set so the cascade doesn't re-mark dirty). Save-and-close calls `_save_to_current_path()` then `_force_deactivate()`.
- New `_force_deactivate()` method bypasses the dirty prompt (used by sibling cross-mode activation).
- `_toggle()` rewritten: on activate, loops `["LightMode", "AssetEditor"]` siblings and force-closes any active one. On deactivate, if `_dirty` shows the prompt; otherwise force-deactivates.
- `_unhandled_input` falls through F6 keys (added KEY_F6 to the existing F5 fall-through) so cross-mode switches reach AssetEditor.

**Phase 4 — Shortcut help panel:**
- New `SHORTCUTS` const (12 entries: Mode/Edit/View categories — F4, Esc, LMB Drag, Handle Drag, Shift+Click, C, M, Delete, Ctrl+Z, Mouse Wheel, Arrows, Middle Drag).
- `_help_panel: PanelContainer` instantiated in `_build_ui` via `ShortcutPanel.build`, anchored bottom-right of the screen, hidden by default; visibility toggles with `active`.

### `scripts/light_mode.gd`
**Phase 1 — 3-way mutual exclusion:**
- `_disable_other_modes()` rewritten to iterate `["EditMode", "AssetEditor"]` siblings instead of hardcoded EditMode lookup. Falls back to `_toggle()` when sibling lacks `_force_deactivate()`.
- `_unhandled_input` early-return list expanded to include KEY_F6 alongside F4 / Esc.

**Phase 4 — Shortcut help panel:**
- New `SHORTCUTS` const (7 entries: Mode/Light/View — F5, LMB select, LMB drag, Delete, Mouse Wheel, Arrows, Middle Drag).
- `_help_panel: PanelContainer` anchored bottom-right; visibility toggles with `active`.

### `scripts/camera_zoom.gd`
**Mid-phase 2 fix — arrow-key panning:**
- New constant `PAN_SPEED_PX_PER_SEC = 600.0` (screen-space at zoom 1.0).
- New `_process(delta)` polls `Input.is_key_pressed(KEY_LEFT/RIGHT/UP/DOWN)`, accumulates direction, normalizes, moves camera at constant on-screen speed (divided by `zoom.x`). Mouse-wheel zoom and middle-mouse drag pan unchanged.

### `scenes/level_1/level_1.gd`
**Phase 1 — F4 save layer port (single-file scope, no lights):**
- New constants: `DEFAULT_EDITS_PATH = "user://level_1_edits.json"`. Field `current_edits_path: String`. `_baseline_keys: Array`.
- `_ready()` defers to `_init_editor_state()` which calls `_capture_baseline()` then `await _apply_saved_edits(current_edits_path)`.
- `_capture_baseline()`, `_node_key()`, `_apply_saved_edits()`, `_apply_transform_to_node()` ported from `level_1_reference.gd`'s objects half (lights branch skipped — F5 still has no save plumbing).
- `save_edits_to(path) -> String` writes the v2 JSON format (transforms + deleted baseline keys); returns `""` on success or an error string. `save_edits()` uses `current_edits_path`. `current_edits_path` updates after a successful Save As.

**Mid-phase 1 fix — phantom-node prevention:**
- `_apply_saved_edits` no longer calls `_create_from_save` for entries that don't match a baseline node. Stale saves from a different scene version (e.g. Door/CCTV/Painting/Laser_sensor entries from the May 7 save) no longer spawn ghost sprites at load. The `deleted` list is also gated on baseline membership.
- `_create_from_save` removed entirely (was the source of the ghost sprites).

### `scenes/level_1/level_1.tscn`
- New `[ext_resource]` for `scripts/asset_editor.gd` (id `7_asset`).
- New `[node name="AssetEditor" type="Node" parent="."]` mounted alongside EditMode and LightMode under Level1.

### `scripts/asset_editor.gd` (across phases)
- **Phase 1**: skeleton with placeholder centered panel, F6 keybind, `_force_deactivate()`, mutual-exclusion against EditMode/LightMode, `ConfirmationDialog` exit prompt.
- **Phase 2**: full editor UI rewrite (top bar / left toolbar / center preview / right panel / bottom status bar), tool state machine (TOOL_NONE/RED/YELLOW/ERASER), polygon storage, dirty tracking, mouse-wheel zoom forwarding, Load PNG with discard prompt. Switching pen tools mid-draw discards the in-progress polygon.
- **Phase 3**: Save Asset dialog (`ConfirmationDialog` with name LineEdit + category OptionButton + Sobel CheckBox + error label), Load Asset browser (`ConfirmationDialog` + `ItemList` of `[category] name` entries from `_scan_palette()`). `_save_asset()`, `_write_borders_json()`, `_write_scene()`, category-specific scene builders, `_assign_owner_recursive` so all children survive `PackedScene.pack()`, name validation (`_is_valid_name` / `_sanitize_name`). Ctrl+S / Ctrl+O keybinds.
- **Phase 4**: SHORTCUTS const updated with Ctrl+S / Ctrl+O entries; help panel mounted at the bottom of the right panel (the only "clear corner" inside F6's full-screen overlay).

## Save format spec — F6 assets

Saved to `res://assets/palette/<category>/<name>/`:

| File | Purpose |
|---|---|
| `<name>.png` | Copy of the source diffuse image |
| `<name>_normal.png` | Sobel-from-diffuse normal map (only if checkbox enabled) |
| `<name>.tres` | `CanvasTexture` resource (`diffuse_texture` + optional `normal_texture` embedded as sub-resources, so no .import is needed for the .tscn to load it) |
| `<name>.borders.json` | Re-editable polygon source (see schema below) |
| `<name>.tscn` | Packed scene; root structure depends on category |

`<name>.borders.json` schema:
```json
{
  "version": 1,
  "image": "<name>.png",
  "image_size": [w, h],
  "polygons": [
    {"type": "collision",   "vertices": [[x, y], ...]},
    {"type": "recognition", "vertices": [[x, y], ...]}
  ]
}
```
Vertices are stored in image-pixel space (top-left origin, +X right, +Y down). On scene compile they're offset by `-image_size/2` to align with a centered Sprite2D.

`<name>.tscn` structure per category:

| Category | Root | Children |
|---|---|---|
| Wall / Door / Lock | `StaticBody2D` named `<Name>` | Sprite + N CollisionPolygon2D + Area2D `Recognition` (collision_layer=2) with yellow polys |
| Camera | `Area2D` named `<Name>` (recognition area itself, collision_layer=2) | Sprite + recognition polys directly + child `Body` StaticBody2D with red polys (cameras can still block movement) |
| Enemy | `Node2D` named `<Name>` | Sprite + `Body` CharacterBody2D with red polys + `Recognition` Area2D (layer 2) with yellow polys |
| Artifact | `Node2D` named `<Name>` | Sprite + `Recognition` Area2D (layer 2) with yellow polys (no red — pickup-only) |

Recognition Area2D layer convention: `collision_layer = 2, collision_mask = 0` (layer 1 = physics, layer 2 = picking).

`recognition_priority` metadata on root (read by future hover-disambiguation gameplay code):
| Floor | Wall | Door | Lock | Artifact | Camera | Enemy |
|---|---|---|---|---|---|---|
| 0 | 10 | 20 | 20 | 30 | 40 | 50 |

Template script attachment: if `res://scripts/templates/<category>.gd` (lowercase) exists, it's `set_script()`-attached on the root before `PackedScene.pack()`. The `templates/` directory is created on first save. No template scripts are auto-generated — user adds them later.

`res://` is read-only in exported builds — F6 is debug/editor-only. The save function carries that comment in-code.

## Mutual exclusion behavior — F4 / F5 / F6

3-way ring. Each mode's `_toggle()` activate-branch loops the other two siblings and force-closes any that's active.

**Cross-mode activation skips dirty prompts.** When pressing F6 while F4 has unsaved edits, F4 is silently force-closed (not prompted). Reasoning: the spec's literal "deactivates the other two if active, then activates the new one" wins over "F4 was dirty, ask first." Adding async signal plumbing to make the prompt block cross-mode activation would have grown Phase 1 substantially.

**Dirty exit prompt fires only on self-toggle.** F4's three-button prompt (Discard / Save / Cancel) and F6's two-button prompt (Discard / Cancel) only appear when the user toggles the mode off via:
- Pressing the same F-key while the mode is active (F4 → F4, F6 → F6)
- Clicking the Close button (F6)

Implementation: each mode that has dirty state implements `_force_deactivate()` (bypass-dirty path). Other modes' `_toggle()` dispatch detects via `s.has_method("_force_deactivate")` and prefers it; falls back to `_toggle` for modes without dirty state (LightMode).

**Key fall-through.** Each mode's `_unhandled_input` early-returns on the *other* F-keys (so they reach their owners) and on Esc (where it makes sense). Order of `_unhandled_input` propagation is reverse tree order — under Level1 the children are EditMode, LightMode, AssetEditor in that scene order, so AssetEditor sees events first.

## Shortcut panel architecture

Single shared builder: `scripts/util/shortcut_panel.gd` with one `static build(title, shortcuts)` function returning a `PanelContainer`. No subclassing, no scene file, no per-mode customization — every mode gets the same look (semi-transparent dark, rounded corners, two-column table, category subheaders).

Each mode declares its own `SHORTCUTS` constant at the top of its script (no central registry — each script owns its own data). Entry shape: `{"category": String, "key": String, "desc": String}`. Categories are emitted in first-seen order.

Per-mode placement decisions (spec allowed picking corners):
- **F4** — bottom-right (existing object panel sits top-left)
- **F5** — bottom-right (existing light panel sits top-right)
- **F6** — integrated as the last child of the right panel below the polygon list. Floating bottom-right would conflict with the F6 status bar; integrating in the right panel keeps it visible without obscuring the preview.

Visibility is gated on each mode's `active` flag — `_help_panel.visible = active` in the toggle paths.

## Persistence formats

### `user://level_1_edits.json` (unchanged from previous session)
```
{
  "version": 2,
  "transforms": [{name, parent, type, texture, position, scale, centered, z_index}, ...],
  "deleted": ["parent_path|name", ...]
}
```
Now actually used: Phase 1 wired up `_apply_saved_edits` on level load and `save_edits` from F4. Loader is now defensive — only restores transforms to nodes already in the captured baseline; never instantiates "missing" entries (prevents stale saves from different scene versions spawning phantom sprites).

## Notable iterations / decisions

- **F4 had no real save layer on the Iso-world branch**: `EditMode._persist()` called `owner.save_edits()` which silently no-op'd because `level_1.gd` had no such method. The orphaned `level_1_reference.gd` had the implementation but was never loaded. Phase 1 ported the objects half of `level_1_reference.gd` into the live `level_1.gd` (lights skipped — F5 still has no save plumbing).
- **Phantom sprites bug discovered mid-Phase 1**: enabling the loader caused 4 ghost sprites (Door/CCTV/Painting/Laser_sensor) to spawn at every launch because the May 7 save referenced them but they no longer existed in the .tscn. Fix: `_apply_saved_edits` only restores transforms to nodes in the captured baseline; the create-from-save path was removed entirely. The orphan position offsets in the user's save (Wall_X / Wall_Y at ~24px shift) were left in place — the user re-centers manually via F4 and saves over.
- **Dirty discard reuses the undo stack**: F4's discard pops `undo_stack` down to a saved snapshot (`_clean_undo_size`) rather than maintaining a separate snapshot. Each `_undo()` call respects `_suppress_dirty` so the cascade doesn't re-mark dirty. Save advances the snapshot mark.
- **Cross-mode activation force-closes silently** (not prompted) — see mutual exclusion section above. Documented in the help text and as comments in each mode's `_toggle()`.
- **CanvasTexture embeds image data inline** in the .tres rather than referencing the .png by path. This sidesteps the .png needing a `.import` companion before the .tscn can load — the .tres is self-contained and immediately usable. The standalone .png is written for human inspection / external tooling.
- **Pen-tool switch discards in-progress polygon**: spec was silent on this, picked the "tool change resets your draft" model so a half-drawn red polygon doesn't suddenly become yellow. Documented in code comment in `_set_tool`.
- **Sobel pipeline written from scratch**: changelog mentioned a Sobel pipeline used for Floor/Door/Hacker frames, but no GDScript or Python implementation exists in the repo. The PNGs were generated by an external tool. New utility lives in `scripts/util/sobel_normal.gd` with `static generate()` per spec, ready for future call sites.
- **Help panel content is keyboard/mouse shortcuts only**, not buttons. The buttons are visible in the mode's existing UI panel and don't need a help table entry.
- **Camera arrow-key panning added mid-Phase 2** at user request. Speed (`PAN_SPEED_PX_PER_SEC`) is divided by camera zoom so on-screen pan rate stays constant when zoomed in/out.

# Changelog — 2026-05-08

**Editor:** Banana

## New files

### Scripts
- `scripts/EditMode.gd` — F4 Edit Object Mode controller (drag/scale/copy/delete/undo, multi-select, mirror, iso 3D grid render, object list panel)
- `scripts/light_mode.gd` — F5 Lighting Edit Mode (Light2D & overlay selection, sliders, add/delete lights, toggle on/off)
- `scripts/camera_zoom.gd` — Camera2D scroll-wheel zoom với cursor anchor, gated bởi `is_current()`
- `scripts/cctv_pan.gd` — CCTV PointLight2D panning script (oscillate rotation), sync `intensity` & `texture_scale` vào ConeBeam shader
- `scripts/laser_glow.gd` — Laser beam pure GDScript (Node2D + `_draw`), 3-layer glow + glitch jitter + flicker
- `scripts/cone_beam.gdshader` — Canvas item shader cho CCTV cone outline (border + scan)

### Scenes
- `scenes/level_1/level_1.tscn` — Level 1 root scene
- `scenes/level_1/level_1.gd` — Level lifecycle: capture baseline, save/load edits cho objects + lights, door slide intro, stub `get_wall_segments()` / `get_chest_obstacle()`
- `scenes/characters/hacker_frames.tres` — SpriteFrames cho Hacker dùng CanvasTexture per-frame

### Resources
- `assets/level1/Floor.tres`, `Wall_X.tres`, `Wall_Y.tres`, `Door.tres` — CanvasTexture wrappers (diffuse + normal)
- `assets/level1/cctv_cone_mat.tres` — ShaderMaterial cho CCTV cone overlay
- `assets/level1/point_light_radial.tres` — GradientTexture2D radial gradient (đã thay thế ở Laser)

### Art assets
- `assets/level1/MapStart.png`, `Floor.png`, `Wall_X.png`, `Wall_Y.png` (2412×1760) + normal maps tương ứng
- `assets/level1/Door.png` + `Door_Normal.png` (Sobel)
- `assets/level1/CCTV.png` (126×120)
- `assets/level1/cctv_cone_light.png` (cone-shape light texture, đã deprecated trong setup hiện tại)
- `assets/security/Laser_sensor.png` (128×128)
- `assets/artifacts/` — 13 file (Box_1/2/3, Dino_bone, Painting_1..5, Statue_1..4)
- `assets/characters/hacker/Idle_SW/0..3.png` + `_Normal` versions + 4 `.tres` CanvasTexture
- `assets/characters/hacker/Walk_SE/0..7.png` + `_Normal` versions + 8 `.tres` CanvasTexture

## Modified files

### `project.godot`
- Display: viewport 1280×720, stretch_mode `canvas_items`
- Rendering: `default_texture_filter = 0` (Nearest pixel art), `2d/snap/snap_2d_transforms_to_pixel`, `snap_2d_vertices_to_pixel`
- Main scene: `res://scenes/main.tscn` (giữ nguyên menu, không đổi sang Level 1)

### `scripts/main.gd`
- `_setup_camera`: attach `camera_zoom.gd` script vào Camera2D
- `_setup_map`: instantiate `level_1.tscn` thay vì `test_map.tscn`
- `_spawn_characters`: override Hacker position bằng `_iso_project(Vector3(1, 141, 0))` (≈screen `(123, -86)`)
- Thêm helper `_iso_project(p: Vector3) -> Vector2` (cos30°/sin30° projection)
- `var _map: Node2D` (thay vì `TestMap` để cho phép Level1 instance)

### `scripts/player_character.gd`
- Thêm `HACKER_FRAMES` const preload
- Const `SPRITE_HEIGHT_PX = 224` (resize sprite per class)
- Const `SPAWN_BLINK_LOOPS = 10`, `SPAWN_BLINK_HALF_PERIOD = 0.08`
- `_setup_animated_sprite()` — load SpriteFrames cho HACKER class, set animation, scale theo SPRITE_HEIGHT_PX
- `_play_spawn_blink()` — Tween modulate.a flicker, `TWEEN_PAUSE_PROCESS` để chạy qua tree pause
- `_process()` — direction tracking từ velocity, switch giữa `Walk_SE` (running) và `Idle_SW` (idle), `flip_h` cho hướng SW (mirror Walk_SE)
- `_set_anim()` helper avoid restarting animation
- `take_down()` — hide AnimatedSprite2D + stop khi character bị ngã
- `_draw()` — early return nếu sprite đang visible (skip circle rendering)

### `scenes/characters/player_character.tscn`
- Thêm `AnimatedSprite2D` child node với `visible = false` (toggle on khi class HACKER spawn)

### `scripts/EditMode.gd` (created → many iterations)
- F4 toggle, ESC quit pre-active gate
- Iso 3D grid drawing với labels cho mỗi 4-cell intersection
- Cursor coord (x, y, 0) theo iso ground plane
- Multi-select: `multi_selected: Array[Node2D]`, Shift+click toggle, drag/mirror/copy/delete áp lên cả group
- Drag: track per-node `_drag_starts`, motion = mouse delta, end = push undo per moved node
- Scale handles: chỉ trên primary, scale all với cùng factor (anchor cố định trên primary)
- Mirror nút (Polygon2D + label) + phím **M**: `selected.scale.x *= -1` mỗi multi-selected
- Object list panel với toggle button per row, refresh sau mỗi action
- Pass-through F5/scroll wheel cho LightMode/Camera2D zoom

### `scripts/light_mode.gd` (created → many iterations)
- F5 toggle, mutual exclusion với F4 (call `EditMode._toggle()` khi F5 bật và F4 đang on)
- Light list panel bên phải: row gồm toggle ●/○ + nút tên light, kèm overlay rows con
- Sliders Energy/Height/Color (R/G/B)/Range/Rotation/Opacity với value label live update
- Rotation slider mở rộng: hỗ trợ DirectionalLight2D (offset −90°), nodes có `base_rotation_deg`, và Node2D thường (rotation trực tiếp)
- Add buttons: `+ Directional`, `+ Point` (PointLight2D với GradientTexture2D radial sinh runtime)
- Delete nút
- Drag light trong viewport
- Helper visualizers: PointLight2D = circle + range arc, DirectionalLight2D = arrow (`(cos, sin)`)
- `_persist()` gọi `owner.save_light_edits()` sau mỗi edit
- Overlay support: Polygon2D/Sprite2D/Node2D children of Light2D đều listed như overlay
- Color callback: cone_color shader_param cho overlay nếu có ShaderMaterial, fallback modulate

### `scenes/level_1/level_1.gd` (created)
- `_init_level` flow: capture baseline objects + lights → apply saved edits → start door intro
- Door slide intro: tween +100 iso X over 1.5s, pause SceneTree (`TWEEN_PAUSE_PROCESS`)
- Smart-merge save/load:
  - Objects (`level_1_edits.json`): transforms, deleted_keys baseline tracking
  - Lights (`level_1_lights.json`): per-light props + overlays (visible/opacity/cone_color/base_rotation_deg)
- Stub `get_wall_segments() -> []`, `get_chest_obstacle() -> {center, radius}` để main.gd không crash

### `scenes/level_1/level_1.tscn`
- Background: Floor, Wall_X, Wall_Y Sprite2D với CanvasTexture (scale 0.5307)
- Objects: Door, CCTV, Painting_3, Laser_sensor (group `editable`)
- Lighting: SunY DirectionalLight2D (rotation −30°, height 1, energy 1.2), CCTV_Light PointLight2D với cone texture + cctv_pan script + ConeBeam Polygon2D child (z_index 100, blend_mix shader), Laser PointLight2D + LaserBeam Node2D với laser_glow.gd
- Camera2D với camera_zoom.gd
- EditMode + LightMode controller nodes

### `scripts/cone_beam.gdshader`
- Canvas item shader, render_mode `blend_mix, unshaded`
- Triangle shape via UV (lateral/along), discard ngoài cone
- Border outline (side + far edge), fill_alpha 0 → cone visible chủ yếu là outline
- Scan ripple animation (sin + TIME)
- Capture `COLOR.a` cho modulate.a (workaround MODULATE không có trong canvas_item fragment)

### `scripts/laser_glow.gd`
- Node2D với `_process` + `_draw` thay shader-based
- 3 stacked rectangles: outer_glow (1px, alpha 0.25) + inner_glow (1px, 0.55) + core (1px, full)
- Glitch step: `seed(int(time * rate))` → `randf_range` jitter Y + flicker alpha
- Default màu `#be0000` (Color(0.745, 0, 0)), beam_length 500px
- Glitch_amount 1.05px, glitch_rate 4.2 Hz

### `scripts/cctv_pan.gd`
- Extends PointLight2D
- `pan_amplitude_deg`, `pan_period_sec`, `pan_enabled`, `base_rotation_deg` @export
- `_process`: nếu `pan_enabled`, oscillate rotation = `_base_rotation + sin(t*2π/T) * amplitude`
- `_sync_overlay`: tìm child "ConeBeam", sync scale = `texture_scale`, intensity = `min(energy*0.6, 1.5)` vào shader_parameter
- Setter `base_rotation_deg` cập nhật `_base_rotation` real-time

## Persistence formats

### `user://level_1_edits.json`
```
{
  "version": 2,
  "transforms": [{name, parent, type, texture, position, scale, centered, z_index}, ...],
  "deleted": ["parent_path|name", ...]
}
```

### `user://level_1_lights.json`
```
{
  "version": 1,
  "lights": [{
    name, parent, type, position, rotation, energy, color, height, texture, texture_scale,
    base_rotation_deg, enabled,
    overlays: [{name, visible, opacity, cone_color}, ...]
  }, ...],
  "deleted": [...]
}
```

## Notable iterations / decisions

- **Normal maps**: source GIFs/PNGs từ Lourve không có proper normal maps (chỉ flat blue). Dùng Sobel-from-diffuse pipeline cho Floor/Door/character; constant directional RGB cho walls (calibrated qua nhiều iterations để Wall_X brightest tại slider rotation 60° và darkest tại −120°).
- **Light direction convention**: Godot 4 `DirectionalLight2D` light_dir = local `+Y` (`(-sin, cos)`). Arrow drawn = local `+X` (`(cos, sin)`) → 90° offset. Slider áp `rot - 90°` để arrow direction = light direction trên screen.
- **Cone overlay vs PointLight2D**: ConeBeam Polygon2D (z=100) phủ lên Wall_Y nhưng không trong suốt với normal-mapped lighting bên dưới. Sau nhiều iteration: ConeBeam = visible decoration only, PointLight2D với cone-shape texture = physical light tương tác normal map. Sau đó user request: chỉ giữ PointLight2D, không overlay → cone bị wall_Y "che" (do normal-mapped wall không favor đỏ) — đó là hành vi đúng.
- **Laser shader fail trên GPU user**: 3 chỗ `smoothstep(edge0, edge1, x)` với `edge0 > edge1` là undefined behavior trong GLSL → shape = 0 → invisible. Fix sang `1.0 - smoothstep(...)` không hoạt động trên user setup → chuyển sang pure GDScript `_draw()` (no shader) cho laser.
- **Multi-select scale**: handles chỉ trên primary, các selected khác scale around own center (không group transform).
- **Save smart-merge**: thay vì wipe-and-recreate, smart-merge giữ original .tscn baseline + apply user transforms/deletes/creates. .tscn changes giữa session vẫn hiệu lực.
