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
