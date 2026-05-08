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
```

There is no separate build step — Godot uses its built-in project system.

## Architecture

**Autoloads (global singletons, registered in `project.godot`):**
- `GameManager` — owns global timer (60s budget), phase enum (`PLANNING/PREDICT/COMMIT`), `TURN_DURATION = 10s`, `ANIMATION_SPEED_MULTIPLIER = 5×`; signals `global_timer_changed`, `mission_failed`, `mission_succeeded`; methods `start_mission(duration)`, `advance_timer()`, `set_phase(phase)`
- `TurnManager` — drives phase transitions; emits `phase_changed`, `turn_started`; exposes `start_first_turn()`, `enter_predict()`, `commit_turn()`, `back_to_planning()`
- `ActionQueue` — stores ordered action dicts `{character_id, type, cost, data}` per character; `push_action()`, `undo_last()`, `reset_character()`, `flush_committed_actions()`, `get_time_used()`, `get_time_remaining()`; emits `queue_changed(character_id, actions)`
- `TimeCalculator` — pure static math with no game-state dependencies; all 9 action-time formulas live here

**Turn phases:**
1. **PLANNING** — player queues actions (visually replayed at 5× speed); backtick=undo, R=reset
2. **PREDICT** — guard AI runs as Tweens (not a process loop); "Back" restores pre-predict state via `restore_from_predict()`
3. **COMMIT** — actions locked; `advance_timer()` deducts 10s; returns to PLANNING for next turn

**Data flow:**
```
Input (main.gd)
  → Pathfinding + cost calculation (pathfinder.gd + TimeCalculator)
  → ActionQueue (stores planned action dicts per character)
  → PlayerCharacter.queue_action() → full sequence visually replayed
  → TurnManager (PLANNING → PREDICT → COMMIT phase transitions)
  → GameManager (global timer, win/lose)
```

**Key subsystems:**

- **Characters** — `Character` (base: STR/INT/AGI stats, `carried_kg`, `is_neutralized`) → `PlayerCharacter` (selection, `queue_action(action)`, `queue_actions(actions[])`, `take_down()`, `restore_from_predict()`, `on_new_turn()`; `logical_pos` tracks final queued position for pathfinding/range checks). Three concrete subclasses: Brawler (STR 3, AGI 1), Cat Burglar (AGI 3, INT 1), Hacker (INT 3, STR 1).

- **Actions** — `ActionBase` (abstract; `character_id`, `action_type`, `cost`, `execute_visual()` / `undo_visual()` Tween hooks) → six concrete subclasses: `ActionMove` (path tween along `MovePath`), `ActionTakedown` (enemy_type, target_id), `ActionPickUp` (item_kg, item_value), `ActionHoldHostage` (hold_duration clamped 0–5s, target_id), `ActionHack` (target_type, target_pos), `ActionPickLock` (lock_level 1–3, lock_type: glass/digital/mechanical).

- **Pathfinding** — `Pathfinder` (visibility graph + A\*, circular obstacles, 0.5m char radius = 16px) → `PathSmoother` (raw waypoints → line+arc segments, arc radius 16px) → `MovePath` (immutable; `position_at(t: 0..1)` arc-length interpolation, `time_cost(agi, eff_kg)` calls TimeCalculator).

- **Guard simulation (PREDICT phase)** — `main.gd._run_predict()`: per guard, `_guard_fov_target()` finds closest non-downed player in 120° FOV at up to 20m; then either `_animate_guard_shoot()` (face → fire after 3s → call `take_down()`), `_animate_guard_move()` (move toward target, stop at taser range 0.5m), or `_animate_guard_patrol()` (face nearest wall → walk to boundary → turn by `patrol_turn_angle`). All animation via Tweens; `Guard.facing_angle` and position updated on completion.

- **UI** — All UI is programmatically constructed. `HUD` (CanvasLayer): global timer top-right, phase label top-left, character panel bottom (class dot + name + neon time bar), phase-driven button visibility. `ContextMenu` (right-click popup; items built by `_build_move/chest/guard/hack_items()`). `PathPreview` (world-space line+arc overlay). `TimelinePanel` (`scripts/ui/timeline_panel.gd`, in progress). Input in `main.gd`: left-click select, right-click menu, Tab cycle.

## Design constraints

- 1 world unit = 1 pixel; 32 px/m scale
- Turn structure: 6 turns × 10s = 60s global budget; room is 40×40m (HALF = 640px half-width)
- Guard spawn: 10m (320px) from chest center; 3 guards facing nearest door
- `TimeCalculator` must remain a pure math module — no autoload or scene dependencies

## Current state

Implemented: character classes, global timer (60s), action queuing (undo/reset), all 9 time formulas (tested), pathfinding + path smoothing, all 6 action types, HUD + character panel + phase buttons, right-click context menu, path preview, guard patrol/move/shoot Predict AI, takedown status on guards and players, character selection.

Not yet implemented: collision geometry on walls, partial actions at turn boundary (spillover), neutralization detection during Predict (currently applied instantly during Planning), mission fail/success UI, guard struggle / hold-hostage resolution, `TimelinePanel` (in progress).

See [design.md](design.md) for the full game design specification.
