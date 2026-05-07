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
- `GameManager` — owns global timer (60s budget), phase enum (`PLANNING/PREDICT/COMMIT`), mission active flag
- `TurnManager` — drives phase transitions, emits `phase_changed` and `turn_started` signals
- `ActionQueue` — stores ordered action lists per character, computes time used/remaining, supports undo/reset
- `TimeCalculator` — pure static math with no game-state dependencies; all 9 action-time formulas live here

**Data flow:**
```
Input (main.gd)
  → Pathfinding + cost calculation (pathfinder.gd + TimeCalculator)
  → ActionQueue (stores planned actions per character)
  → TurnManager (PLANNING → PREDICT → COMMIT phase transitions)
  → GameManager (global timer, win/lose)
```

**Key subsystems:**

- **Characters** — `Character` (base stats: STR/INT/AGI, weight) → `PlayerCharacter` (selection, turn time tracking, action visual queue). Three concrete subclasses: Brawler (STR 3), Cat Burglar (AGI 3), Hacker (INT 3).

- **Actions** — `ActionBase` (abstract, with `execute_visual()` / `undo_visual()` Tween hooks) → `ActionMove` (animates along `MovePath`, supports snapback undo).

- **Pathfinding** — `Pathfinder` (visibility graph + A\*, circular obstacles, 0.5m character radius = 8px) → `MovePath` (immutable path record: line + arc segments, computes total distance/angular change/time cost) → `PathSmoother` (raw waypoints → smooth arcs at bends).

- **UI** — All UI is programmatically constructed. `HUD` (global timer top-right, character panel bottom with neon time bar), `ContextMenu` (right-click popup, 270px wide), `PathPreview` (renders planned path in world space). Input handled in `main.gd`: left-click select, right-click menu, Tab cycle, backtick undo, R reset.

## Design constraints

- 1 world unit = 1 pixel; 16 px/m scale
- Turn structure: 6 turns × 10s, global 60s budget
- `TimeCalculator` must remain a pure math module — no autoload or scene dependencies

## Current state

Implemented: project skeleton, character classes, global timer, action queuing (with undo/reset), all 9 time formulas (tested), pathfinding + path smoothing, programmatic UI, character selection, right-click context menu, path visualization.

Not yet implemented: guard spawns/patrol/AI, collision geometry on walls, non-Move actions (Takedown, Hack, Pick Up, Hold Hostage), Predict phase guard simulation, Commit phase action playback, partial actions at turn boundary, neutralization detection, mission fail/success.

See [design.md](design.md) for the full game design specification.
