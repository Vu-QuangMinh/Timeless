# Daily Work — 2026-05-08

**Editor:** Banana
**Project:** Timeless (Godot 4.6, 2D iso with 3D-style normal-mapped lighting)

## Tóm tắt

### Level 1 environment
- Import & sắp xếp `Floor`, `Wall_X`, `Wall_Y` với CanvasTexture (diffuse + normal) ở 1280×934 (scale 0.5307)
- Đặt `Door` (slide intro 1.5s theo iso X+100), `CCTV`, `Painting_3`, `Laser_sensor`, `Hacker` (spawn iso `(1,141,0)`)
- Map start scene: `scenes/main.tscn` (menu) → load `scenes/level_1/level_1.tscn`

### F4 Edit Object Mode
- Toggle bằng phím **F4** — kéo/scale/copy(C)/delete/undo(Ctrl+Z) object trong group `editable`
- Lưới 3D iso (X+ −30°, Y+ +30°, Z+ vertical) với label tọa độ
- Multi-select bằng **Shift+click** trên panel hoặc viewport, drag/scale/mirror/copy/delete áp dụng cho cả nhóm
- Nút **Mirror** (M) flip horizontal selected
- Panel object list bên trái với toggle ON/OFF từng node
- Persistence smart-merge (`user://level_1_edits.json`)

### F5 Lighting Edit Mode
- Toggle bằng **F5** — chọn/sửa Light2D + overlays
- Sliders: Energy / Height / Rotation / Range / Color RGB / Opacity (giá trị hiển thị bên cạnh)
- Add `+ Directional` / `+ Point` light, toggle ON/OFF từng light hoặc overlay
- Drag light trong viewport, rotate qua slider
- Persistence (`user://level_1_lights.json`) bao gồm overlay states

### CCTV system
- Camera body Sprite2D (CCTV.png) + PointLight2D với cone-shape texture custom
- Custom shader `cone_beam.gdshader` (canvas_item, blend_mix) tạo cone outline + scan ripple
- Pan animation (`cctv_pan.gd`) — quay qua lại theo sin
- F5 control: position, rotation (`base_rotation_deg`), color/intensity sync sang shader

### Laser beam
- `Lighting/Laser` PointLight2D + `LaserBeam` Node2D với `laser_glow.gd`
- 3-layer rectangle (outer/inner glow + core) vẽ qua `_draw()`, dày 1px
- Glitch jitter Y ±1.05px @ 4.2 Hz, flicker alpha 0.7-1.0
- Màu `#be0000`, dài 500px

### Hacker character
- Animation Idle_SW (4 frames) + Walk_SE (8 frames) từ GIF source
- Normal map per-frame (Sobel-from-diffuse) + CanvasTexture .tres mỗi frame
- SpriteFrames.tres tham chiếu CanvasTextures → normal-mapped lighting trên animation
- Sprite resize 224×224 (70% × 320), idle speed 4 fps
- Spawn blink effect (modulate.a flicker 1.6s, classic revive style)
- Walk_SE mirror cho hướng SW; placeholder cho hướng khác

### Artifacts
- Import 13 file từ `F:\GAME\Lourve\Artifact` vào `assets/artifacts/` (Box×3, Dino_bone, Painting×5, Statue×4)
- Chỉ có Painting_3 đặt vào level 1; còn lại lưu sẵn để dùng sau

### Normal map pipeline
- Sobel-from-diffuse cho Floor, Door, character frames
- Constant directional RGB cho Wall_X, Wall_Y (calibrated brightest/darkest theo rotation)

### Camera & input
- `camera_zoom.gd` — scroll wheel zoom anchored at cursor, hoạt động mọi mode
- ESC quit, F4/F5 mutually exclusive

## File chi tiết

Xem `changelog.md` để biết file-by-file changes.
