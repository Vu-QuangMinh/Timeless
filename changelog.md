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
