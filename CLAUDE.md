# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Timeless** is a tactical isometric 2D roguelite stealth-heist game built in **Godot 4.6** (GDScript). The core mechanic: a crew of 3 mercenaries infiltrate vaults with a 60-second global time budget where every action costs real seconds.

## Commands

```bash
# Run the game
godot --path . scenes/main.tscn

# Run headless tests (exit 0 = pass, 1 = fail)
godot --headless -s tests/test_time_calculator.gd
godot --headless -s tests/test_pathing.gd
godot --headless -s tests/test_actions.gd
godot --headless -s tests/test_commit.gd
```

There is no separate build step — Godot uses its built-in project system.

## Architecture

**Autoloads (global singletons, registered in `project.godot`):**
- `IsoMath` — isometric projection helpers; `project(world: Vector2) → Vector2` and `unproject(screen: Vector2) → Vector2`; constant `PPM = 32.0` (pixels per meter)
- `GameManager` — owns global timer, phase enum (`PLANNING/PREDICT/COMMIT`); constants `TURN_BUDGET_S = 10.0`, `TOTAL_TURNS = 4`, `ANIMATION_SPEED_MULTIPLIER = 5.0`; signal `mission_ended()`; methods `start_mission(duration)`, `advance_timer(seconds)` (clamps to 0, emits `mission_ended` at 0)
- `TurnManager` — drives phase transitions; signals `phase_changed(phase)`, `turn_started(turn_index)`, `turn_ended(turn_index)`; methods `start_predict()`, `back_to_planning()`, `commit()`, `start_next_turn()`
- `ActionQueue` — stores ordered action dicts `{start_time, cost, type, ...}` per character; `add_action(char_id, dict)`, `get_next_available_time(char_id)`, `undo_last(char_id)`, `reset(char_id)`, `erase_from_time(char_id, t)`, `clear_all()`
- `TimeCalculator` — uses `class_name` (not a registered autoload); pure static math, all 9 action-time formulas; no scene or autoload dependencies

**Turn phases (PREDICT not yet implemented):**
1. **PLANNING** — player queues actions; backtick=undo last, R=reset selected character
2. **PREDICT** — planned but not yet implemented; reserved for guard AI Tween simulation
3. **COMMIT** — `commit_actions()` runs all character tweens in parallel; `advance_timer(TURN_BUDGET_S)` deducts 10s; returns to PLANNING

**Data flow:**
```
Input (main.gd)
  → Pathfinding + cost calculation (pathfinder.gd + TimeCalculator)
  → ActionQueue (stores planned action dicts per character)
  → PlayerCharacter.queue_action() stores action object + dict
  → Commit: all 3 characters animate in parallel via Tweens
  → TurnManager.start_next_turn() + GameManager.advance_timer()
```

**Key subsystems:**

- **Characters** — `Character` (`class_name`, extends RefCounted: STR/INT/AGI stats, `carried_kg`, `is_neutralized`, `effective_weight()`) → `PlayerCharacter` (Node2D: `setup(id, char)`, `queue_action(action)`, `undo_last_action()`, `reset_actions()`, `commit_actions(scene_root) → Tween`, `clear_queue_after_commit()`, `get_move_paths()`; `logical_pos` tracks final queued position). Three classes: Brawler (STR 3, INT 1, AGI 1), Cat Burglar (STR 1, INT 1, AGI 3), Hacker (STR 1, INT 3, AGI 1).

- **Actions** — `ActionBase` (abstract RefCounted; `char_id`, `action_type`, `cost`, `on_complete: Callable`, `execute_visual(char, tween)`, `to_dict()`) → three implemented subclasses: `ActionMove` (path tween along `MovePath`), `ActionPickUp` (squash-stretch tween, item_kg/item_value), `ActionPickLock` (oscillating scale tween, lock_level/lock_type). `ActionTakedown`, `ActionHoldHostage`, `ActionHack` are designed but not yet implemented.

- **Pathfinding** — `Pathfinder` (`class_name`; visibility graph + A*, circular obstacles, 0.5m char radius; `setup(wall_segs, obstacles)`, `find_path(from, to) → Array[Vector2]`) → `PathSmoother` (raw waypoints → line+arc segments, `ARC_RADIUS = 0.5m`) → `MovePath` (`class_name`; immutable; `position_at(t: 0..1)` arc-length interpolation, `total_length()`).

- **UI** — All UI is programmatically constructed. `HUD` (CanvasLayer): global timer top-right, phase label top-left, character panels bottom (class dot + name + time bar + progress bar); signals `commit_pressed()`. `ContextMenu` (right-click popup; `show_at(pos, items)`, `close()`, `is_open()`; signals `item_selected(index)`). `PathPreview` (world-space line+arc overlay; `set_paths(char_id, paths)`, `clear_all()`). Input in `main.gd`: left-click select, right-click cascade (other char → chest → floor), Tab cycle.

- **Level** — `level_1.gd`: hardcoded wall segments (world meters), chest obstacle (`center`, `radius = 0.75m` when locked); methods `get_wall_segments()`, `get_chest_obstacle()`, `get_room_bounds() → Rect2`, `unlock_chest()`, `pickup_chest()`. Chest state: `chest_locked`, `chest_picked_up`.

- **Editor tools** (not part of gameplay) — `EditMode.gd` (F4: drag/scale/copy/delete scene objects), `light_mode.gd` (F5: Light2D editor with sliders), `camera_zoom.gd` (scroll wheel zoom with cursor anchor).

## Design constraints

- 1 world unit = 1 pixel; 32 px/m scale (`IsoMath.PPM`)
- Turn budget: `TURN_BUDGET_S = 10s`; game started with 60s (`start_mission(60.0)` in `main.gd`)
- Character footprint: 0.5m radius; pathfinder inflates all obstacles by this amount
- Animation speed: 5× real-time (10s turn animates in 2s real time)
- `TimeCalculator` must remain a pure math module — no autoload, scene, or Node dependencies

## Current state

Implemented: character classes (3), global timer, action queuing (undo/reset), all 9 time formulas (tested), pathfinding + path smoothing, ActionMove + ActionPickUp + ActionPickLock with visual tweens, HUD + character panels + Commit button, right-click context menu with move/chest actions, path preview, commit phase (parallel character animation), takedown status on players, character selection, isometric rendering with normal-mapped lighting (Hacker animated; others as colored circles), in-editor tools (EditMode, LightMode).

Not yet implemented: PREDICT phase + guard AI, ActionTakedown / ActionHoldHostage / ActionHack, collision geometry on walls, partial actions at turn boundary (spillover), mission fail/success UI, guard struggle/hold-hostage resolution, TimelinePanel, guard nodes on the map.

See [design.md](design.md) for the full game design specification.
