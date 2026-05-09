"""
analyze_walls.py — extract iso-room geometry from sprite alpha channels.

Usage:
    python scripts/tools/analyze_walls.py

Outputs JSON with pixel coordinates and approximate world-meter coordinates for:
  - floor diamond corners
  - wall_x base segments (with door gap)
  - wall_y base segment
"""

import json
import sys
from pathlib import Path

try:
    from PIL import Image
    import numpy as np
except ImportError:
    print("ERROR: Pillow and numpy are required. Run: pip install Pillow numpy", file=sys.stderr)
    sys.exit(1)

ASSETS = Path(__file__).parents[2] / "assets" / "level1"
ALPHA_THRESHOLD = 200
DOOR_RISE_THRESHOLD = 40
DOOR_MIN_WIDTH = 20

# IsoMath constants (must match autoloads/iso_math.gd)
PPM    = 32.0
COS30  = 0.8660254
SIN30  = 0.5
SCALE  = 0.5307
TEX_W  = 2412
TEX_H  = 1760


def load_alpha(name: str) -> np.ndarray:
    img = Image.open(ASSETS / name).convert("RGBA")
    return np.array(img)[:, :, 3]


def tex_to_world(tx: float, ty: float) -> tuple[float, float]:
    """Convert texture pixel → world meters (matches _texture_pixel_to_world in GDScript)."""
    sx = (tx - TEX_W * 0.5) * SCALE
    sy = (ty - TEX_H * 0.5) * SCALE
    u = sx / (COS30 * PPM)
    v = sy / (SIN30 * PPM)
    return round((u + v) * 0.5, 2), round((u - v) * 0.5, 2)



def wall_base_segments(alpha: np.ndarray, name: str) -> dict:
    H, W = alpha.shape
    bottom_y = np.full(W, -1, dtype=int)
    for col in range(W):
        opaque = np.where(alpha[:, col] > ALPHA_THRESHOLD)[0]
        if len(opaque):
            bottom_y[col] = int(opaque.max())

    active = np.where(bottom_y >= 0)[0]
    if len(active) == 0:
        return {"segments": [], "door_gap": None}

    x0, x1 = int(active.min()), int(active.max())
    y0_trend, y1_trend = bottom_y[x0], bottom_y[x1]

    door_cols = []
    for col in range(x0, x1 + 1):
        if bottom_y[col] < 0:
            door_cols.append(col)
            continue
        t = (col - x0) / max(x1 - x0, 1)
        trend_y = y0_trend + t * (y1_trend - y0_trend)
        rise = trend_y - bottom_y[col]
        if rise > DOOR_RISE_THRESHOLD:
            door_cols.append(col)

    door_gap = None
    if len(door_cols) >= DOOR_MIN_WIDTH:
        dc = sorted(set(door_cols))
        runs = []
        run_start = dc[0]; prev = dc[0]
        for c in dc[1:]:
            if c - prev > 5:
                runs.append((run_start, prev))
                run_start = c
            prev = c
        runs.append((run_start, prev))
        best = max(runs, key=lambda r: r[1] - r[0])
        gap_x0, gap_x1 = best
        door_gap = {"x_start": gap_x0, "x_end": gap_x1}

    if door_gap:
        segs = []
        gx0, gx1 = door_gap["x_start"], door_gap["x_end"]
        if gx0 - 1 >= x0:
            segs.append({"x_start": x0,      "x_end": gx0 - 1,
                          "y_at_x_start": int(bottom_y[x0]),
                          "y_at_x_end":   int(bottom_y[gx0 - 1])})
        if gx1 + 1 <= x1:
            segs.append({"x_start": gx1 + 1, "x_end": x1,
                          "y_at_x_start": int(bottom_y[gx1 + 1]),
                          "y_at_x_end":   int(bottom_y[x1])})
    else:
        segs = [{"x_start": x0, "x_end": x1,
                 "y_at_x_start": int(bottom_y[x0]),
                 "y_at_x_end":   int(bottom_y[x1])}]

    return {"segments": segs, "door_gap": door_gap}


def world_seg(seg: dict) -> dict:
    a = tex_to_world(seg["x_start"], seg["y_at_x_start"])
    b = tex_to_world(seg["x_end"],   seg["y_at_x_end"])
    return {"a_world_m": list(a), "b_world_m": list(b)}


def derive_floor_from_walls(wx: dict, wy: dict) -> dict:
    """
    Approach #2: derive floor rectangle from wall endpoints, ignoring Floor.png alpha.

    Wall_X (constant-y wall): its left endpoint gives the room's back-left corner,
    its right endpoint gives x_max.  Wall_Y (constant-x wall): its bottom endpoint
    gives y_min.  The rectangle is axis-aligned in world space.

    iso corner names (based on screen position):
      top    = (x_min, y_max)  ← highest on screen (back-left corner)
      right  = (x_max, y_max)  ← rightmost on screen
      bottom = (x_max, y_min)  ← lowest on screen (front-right corner)
      left   = (x_min, y_min)  ← leftmost on screen
    """
    # Wall junction: Wall_X left endpoint ≈ Wall_Y right endpoint
    wx_left  = wx["segments"][0]
    wy_right = wy["segments"][-1]
    corner_a = tex_to_world(wx_left["x_start"], wx_left["y_at_x_start"])
    corner_b = tex_to_world(wy_right["x_end"],  wy_right["y_at_x_end"])
    x_min = round((corner_a[0] + corner_b[0]) / 2, 2)
    y_max = round((corner_a[1] + corner_b[1]) / 2, 2)

    # x_max: Wall_X right endpoint world_x
    wx_right = wx["segments"][-1]
    x_max = tex_to_world(wx_right["x_end"], wx_right["y_at_x_end"])[0]

    # y_min: Wall_Y left endpoint world_y
    wy_left = wy["segments"][0]
    y_min = tex_to_world(wy_left["x_start"], wy_left["y_at_x_start"])[1]

    centroid = (round((x_min + x_max) / 2, 2), round((y_min + y_max) / 2, 2))

    return {
        "top":    [x_min, y_max],   # (x_min, y_max)
        "right":  [x_max, y_max],
        "bottom": [x_max, y_min],
        "left":   [x_min, y_min],
        "centroid": list(centroid),
        "room_size_m": [round(x_max - x_min, 2), round(y_max - y_min, 2)],
    }


def main():
    print("Loading…", file=sys.stderr)
    wallx_a = load_alpha("Wall_X.png")
    wally_a = load_alpha("Wall_Y.png")

    wx = wall_base_segments(wallx_a, "Wall_X.png")
    wy = wall_base_segments(wally_a, "Wall_Y.png")

    # Door gap world extent
    wx_door_world = None
    if wx["door_gap"]:
        seg_left  = wx["segments"][0] if wx["segments"] else None
        seg_right = wx["segments"][1] if len(wx["segments"]) > 1 else None
        y_left  = seg_left["y_at_x_end"]    if seg_left  else 0
        y_right = seg_right["y_at_x_start"] if seg_right else 0
        gx0, gx1 = wx["door_gap"]["x_start"], wx["door_gap"]["x_end"]
        a_w = tex_to_world(gx0, y_left)
        b_w = tex_to_world(gx1, y_right)
        wx_door_world = {
            "a_world_m":   list(a_w),
            "b_world_m":   list(b_w),
            "mid_world_m": [round((a_w[0]+b_w[0])/2, 2), round((a_w[1]+b_w[1])/2, 2)],
        }

    floor = derive_floor_from_walls(wx, wy)

    result = {
        "texture_size": {"w": TEX_W, "h": TEX_H},

        "wall_x_base_segments_px":    wx["segments"],
        "wall_x_base_segments_world": [world_seg(s) for s in wx["segments"]],
        "wall_x_door_gap_px":         wx["door_gap"],
        "wall_x_door_gap_world":      wx_door_world,

        "wall_y_base_segments_px":    wy["segments"],
        "wall_y_base_segments_world": [world_seg(s) for s in wy["segments"]],
        "wall_y_door_gap_px":         wy["door_gap"],

        "floor_corners_world_m":   floor,
        "NOTE": (
            "Floor corners derived from wall endpoints (approach #2). "
            "top=(x_min,y_max), right=(x_max,y_max), bottom=(x_max,y_min), left=(x_min,y_min). "
            "Check: top.x==left.x, top.y==right.y, bottom.x==right.x, bottom.y==left.y."
        ),
    }
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
