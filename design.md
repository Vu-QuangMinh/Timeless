# Timeless — Game Design Document

## Overview

**Timeless** is a tactical isometric 2D roguelite. The player controls a crew of 3 mercenaries who infiltrate vaults and museums to steal artifacts. Every mission runs on a strict global time budget (e.g., 60 seconds), and every action — moving, picking up loot, taking down guards, hacking — costs real seconds. Success means getting in, grabbing the loot, and getting out before the clock runs dry.

The core fantasy: precise, clockwork heists where milliseconds matter.

---

## Core Loop

A mission is structured around a global timer (e.g., 60s), spent in 10-second turns. Each turn, every character has 10 seconds of personal action time, and the global timer drops by 10 when the turn is committed.

For example, in a 60-second mission with 3 characters: 6 turns × 10s = 60s of global time, and each character gets 6 turns × 10s = 60 character-seconds, for **180 character-seconds total** across the crew.

If a mission has 55 seconds, the final turn gives each character only 5 seconds of action time. (apply for both our crew an the enemies)

---

## Turn Phases

Each turn cycles through three phases:

### 1. Planning
The player queues actions for their characters. Actions play out visually at normal speed as they're planned, but they are **theoretical** — everything can be undone.

- **Right-click on ground** → "Move here (x.x seconds)"
- **Right-click on a target within action range** → action options appear (e.g., "Takedown – 3.2 seconds")
- **Right-click on a target outside range** → both options appear: "Move here (x.x s) and Take down (y.y seconds)" and the action option (y.y s), where movement time is auto-pathed

If multiple actions are valid on a single target, all are listed.

**Controls:**
- `` ` `` (backtick) — Undo last action, one at a time
- `R` — Reset all actions this turn
- `Tab` — Cycle to next character (does not skip characters with 0s remaining)

If an action takes longer than the character's remaining turn time, it is performed **partially**, consuming all remaining time. On the next turn, selecting that character pops up: *"Continue the current action?"* — Yes consumes the rest of the action's time; No resets the action's progress to zero. Stopping an action can itself be undone.

### 2. Predict
Once the player commits to their plan, they click **Predict**. Player characters freeze in place — their actions are already played out. The guards then take their 10 seconds of action, choosing the best course of action to minimize the time to catch the player. Player and guard time **do not overlap**.

### 3. Commit / Back to Planning
After watching the guards' predicted actions, the player either:
- **Commit** — locks in everything (player + guard actions), advances global timer by 10s, starts the next turn.
- **Back to Planning** — undoes guard actions and returns to Planning, where Undo and Reset are still available.

---

## Character Stats

Every playable character has three stats:

- **Agility (AGI)** — speed of movement
- **Strength (STR)** — mitigates weight, speeds takedowns, helps break locks
- **Intelligence (INT)** — speeds hacking, item use, pickup, helps with digital locks

All "+0.1 per point" effects are linear and stack multiplicatively with their base time.

---

## Actions

Each turn, a character can perform any combination of these actions, limited only by their 10s of available time:

### Move
- Base movespeed: **5 m/s**
- `Effective_movespeed = Base_movespeed × (1 + 0.1 × AGI)`
- At 10 AGI, the character moves at 10 m/s.
- **Weight penalty:** every kg of carried weight slows the character down by 1%, mitigated by STR.
  - `Effective_weight = weight / (1 + 0.1 × STR)`
  - `Effective_time = time × (1 + 0.01 × Effective_weight)`
- **Direction changes** cost time: 1 second per full 360° of cumulative angular change, integrated along the path. Sharper turns cost more; gentle arcs cost less. The character slows through curves rather than paying a separate cost.
- **Pathing:** continuous coordinates. Each character has a **0.5m radius circular footprint**, used for both rendering and pathing. Characters cannot pass through walls, objects, or each other.
- Paths must be smooth curves — no sharp bends.

### Pick Up
- Adds the object's weight to the character (which slows future movement).
- The pickup action itself costs time, mitigated by INT:
  - `Effective_pickup_time = base_time × (1 + 0.01 × Effective_weight) / (1 + 0.1 × INT)` *(weight slows everything; INT speeds the action itself)*
- Picking up a **locked** object adds the lock's weight on top.
- The object's monetary value is stored on the carrying character.
- Range: target must be within **0.5m**.

### Takedown
- Range: target must be within **0.5m**.
- Base time depends on enemy type:
  - Guard — 5s
  - Clerk — 3s
- `Effective_takedown_time = Base_time / (1 + 0.1 × STR)`

### Hold Hostage
- Range: within **0.5m** of an enemy.
- When chosen, a popup asks: *"For how long?"* — defaults to **5.0s** (the maximum), adjustable from 0.0 to 5.0.
- During the hold, the character is **stationary** at the hostage's location and consumes that many seconds of turn time.
- While anyone holds a hostage, **no guard will shoot** (abstract rule — geometry doesn't matter).
- The hostage-holder is **vulnerable to melee** (taser range) from other guards, and to cameras / guard FoV.
- After the hold ends, the enemy returns to being an active threat. (Use Takedown for permanent neutralization.)

### Hack
- Range: **5 × (1 + 0.1 × INT)** meters — uniquely long compared to other actions.
- Base time by target:
  - Camera — 4s
  - Trip wire — 4s
  - Red button — 6s
  - Closed window — 5s
  - Closed door — 6s
- `Effective_hacking_time = Base_time / (1 + 0.1 × INT)`

### Use Item
- `Effective_item_time = Base_item_time / (1 + 0.1 × INT)`
- (No items defined yet for the test build.)

### Pick Lock
Locks come in 3 types and 3 levels:

| Lock Type | Stats Used |
|---|---|
| Glass (smash) | AGI + STR |
| Digital | AGI + INT |
| Mechanical | AGI + AGI (×2) |

| Level | Base Time |
|---|---|
| 1 | 5s |
| 2 | 10s |
| 3 | 20s |

`Effective_lock_time = Base_time / (1 + 0.05 × stat1 + 0.05 × stat2)`

### Escape
- Instant.
- Must be within **0.5m** of an exit (door or open window).

### Carry a Downed Ally
A neutralized character can be picked up by a teammate. Their full body weight transfers to the carrier.

- Base body weight: **60–70 kg** (random per character)
- **+2 kg per STR point**, **−2 kg per AGI point** (heavier brutes, lighter cat burglars)

---

## Classes

A character spawns as one of four classes:

| Class | STR | INT | AGI | Bonus |
|---|---|---|---|---|
| Brawler | 3 | 0 | 1 | — |
| Cat Burglar | 0 | 1 | 3 | +1 random |
| Hacker | 1 | 3 | 0 | +1 random Hacker quirk |
| Apprentice | 1 | 1 | 1 | +1 unassigned point, +1 unpicked quirk |

On level-up, characters gain an unassigned stat point and pick from 3 random quirks. Quirks can be rerolled once with money. **Quirks and leveling are out of scope for the current build.**

---

## Guards

Guards are scripted enemies that pursue and neutralize the crew.

### Movement
- Flat **5 m/s** movespeed (direction change cost similar to the players).

### Perception
- **120° field of vision**, oriented in the direction they're facing.
- Guards always know the position of every player character, but **targets in FoV take priority** in reaction.
- Among priority targets, they react to the **closest** one.
- Line of sight is blocked by **everything** — walls, objects, and characters.

### Combat
- **Gun:** can shoot a target within 20m (but more than 0.5m), 3s to fire.
- **Taser:** within 0.5m, 2s to use.
- **Weapon swap:** 3s.

### Decision Logic
Guards always pick the course of action that minimizes time-to-neutralize a target:
1. If they have clear LoS, a target is within 20m and >0.5m away, and **no one is holding a hostage** — they shoot.
2. If LoS is blocked, the target is too close, or someone is holding a hostage — they move closer and swap to taser. Once within 0.5m, they tase (2s).
3. If the situation changes mid-action (LoS opens up, hostage drops), they re-evaluate and may swap back to gun. The optimization is global — they minimize total expected time-to-kill.

### Neutralizing the Player
A single successful shot or tase neutralizes a player character.

---

## Test Map

A square isometric room with **40m edges**.

- **4 doors**, one centered on each wall.
- **8 windows**, two evenly spaced on each side of every door. All closed.
  - Windows are **escape routes only** in the current build (cannot be moved through normally; not LoS-passable).
- **Locked chest in the center**, containing a **painting** (10 kg, worth $3).
  - Lock: **Glass, Level 1**, weighs **50 kg**.
  - Picking up the chest while locked means carrying both the chest contents and the 50 kg lock; the painting's value is stored on the character once picked up.
- **3 guards** spawned randomly 10m from the chest, each facing the **nearest door**.
- **3 player characters** spawn at the **bottom-left door**, one each of: Brawler, Cat Burglar, Hacker (no Apprentice in the test build).
- Global timer starts at **60 seconds**.

---

## UI

### Selected Character Avatar (Bottom of Screen)
- Avatar with a **green neon time-left bar** representing 10.0s.
- The bar drains as actions are queued and refills when actions are undone.
- Inside the bar, a **black number** shows the time remaining this turn.
- **Hover the avatar** → popup shows speed-affecting status. Currently just `Weight: −x%`. Also shows total **money carried** (sum of held item values).

### Global Timer
- **Top-right corner.** Starts at 60s, drops by 10 per Commit, if there are less than 10s, drop to 0. When this hit zero, all doors are permanently closed.

### Right-Click Context
- On ground: `Move here (x.x seconds)`
- On target in range: `<Action Name> – x.x seconds` for every valid action.
- On target out of range: both `Move here (x.x s)` and `<Action Name> (y.y s)` (auto-pathed).

### Character Switching
- `Tab` cycles to the next character. Does not skip characters with 0s remaining.

---

## Open / Out-of-Scope for Current Build

- Quirks and leveling
- Items (the Use Item action exists but no items defined)
- Money economy beyond display
- Camera and trip wire objects (defined for hacking, not yet placed in test map)
- Guard patrol behavior when no targets are visible
- Multiple missions / mission generation

## Progress

### Session 1 — 2026-05-06

**Scope:** Project skeleton, test map, character classes, time formulas, basic selection, global timer.

#### Done

| Area | Files | Notes |
|---|---|---|
| Project setup | `project.godot` | Godot 4.6, 1280×720, D3D12/Jolt. Autoloads registered. |
| Autoload — game state | `autoloads/game_manager.gd` | Global 60s timer, Phase enum (PLANNING/PREDICT/COMMIT), `start_mission()`, `advance_timer()`. Emits `global_timer_changed`, `mission_failed`, `mission_succeeded`. |
| Autoload — turn flow | `autoloads/turn_manager.gd` | Phase transitions: Planning → Predict → Commit → Planning. Calls `GameManager.advance_timer()` on commit. Stub only — no guard actions yet. |
| Autoload — action queue | `autoloads/action_queue.gd` | Per-character ordered action arrays. `push_action`, `undo_last` (pop_back), `reset_character`, `flush_committed_actions`. |
| Autoload — math | `autoloads/time_calculator.gd` | Pure static functions for every formula in the design doc: movespeed, effective weight, weight multiplier, move time (with angular cost), pickup time, takedown time, hack time, hack range, lock time, body weight, hold duration clamp. No node references. |
| Character base class | `scripts/character.gd` | Stats (STR/INT/AGI), 4 class definitions with stat tables, body weight calculation, carried weight/value tracking. |
| Player character | `scripts/player_character.gd` | Extends Character. Turn budget (10s), selection state, `_draw()` circle with class color + selection ring + name tag. Connects to ActionQueue signals to drive time bar updates. |
| Test map | `scenes/test_map/test_map.gd` | Full 40m × 40m room drawn via `_draw()`. 4 walls with door gaps (3m wide), 8 windows (2 per half-wall, evenly spaced), gold chest with red lock indicator at center. 16 px/m scale. Visual only — no collision shapes yet. |
| HUD | `scenes/ui/hud.gd` | Global timer label (top-right, green). Selected character panel (bottom): class-color dot, character name, green neon time bar (drains as actions queue), numeric time remaining. Phase label (top-left). All built programmatically — no art assets. |
| Main scene | `scripts/main.gd` | Spawns Camera2D, TestMap, 3 PlayerCharacters (Brawler/Cat Burglar/Hacker) at south door, HUD. Click-to-select (12px hit radius), Tab to cycle, `` ` `` to undo last action, `R` to reset turn. |
| Unit tests | `tests/test_time_calculator.gd` | 30 assertions covering all 9 formula groups. Headless runner (`godot --headless -s tests/test_time_calculator.gd`), exits 0/1. Uses `preload` to avoid autoload init-order issues. |

#### Coordinate system
- 1 world unit = 1 pixel, 16 px = 1 m.
- Room interior: 640 × 640 px, centered at world origin (0, 0).
- Characters: 8 px radius (0.5 m).
- South door is the player spawn wall; "bottom-left door" from the design doc maps to this in top-down view.

#### Known gaps / next session
- Guard spawns (3 guards, 10 m from chest, facing nearest door) — visual placeholders only.
- Collision walls (StaticBody2D) so characters can't walk through them.
- Right-click context menu for Move / Takedown / Pick Up / Hack / Escape actions.
- Pathfinding (NavigationRegion2D or custom).
- Predict phase: guard AI decision logic.
- Commit phase: action resolution and animation playback.
- Partial actions (action overflows turn boundary).
 
 Milestone 2 — Action system, UI, three characters
M1 + M1.5 are done: iso world coordinates work, walls are real barriers, one character can pathfind by left-click. Now we add the planning-phase gameplay loop: three characters, the action queue, undo/reset, the right-click context menu, and a HUD time bar.
Out of scope for M2: guards, CCTVs, Predict phase, Commit phase animations, win/lose. M2 ends in Planning phase with a working time budget.
Reference: the old code on main branch
Most of M2's structure already existed on the main branch before the rewrite. Read these files for behavioral spec — adapt to the new iso world conventions, do not blindly copy:

git show main:scripts/main.gd — selection, Tab cycle, ` undo, R reset, right-click context menu cascade, action execution dispatch
git show main:scripts/player_character.gd — selection state, action queue per character, turn time accounting
git show main:scripts/character.gd — class definitions and stat blocks (already partially ported)
git show main:scripts/actions/action_base.gd and the action_*.gd files — port verbatim, they're coordinate-agnostic
git show main:scenes/ui/hud.gd and hud.tscn — port near-verbatim, the HUD doesn't care about coord space
git show main:scripts/ui/context_menu.gd and context_menu.tscn — port verbatim
git show main:scripts/ui/path_preview.gd and path_preview.tscn — port; needs a small change to project from world to screen for drawing

Files to NOT touch:

Anything in autoloads/ (already correct from M1)
scripts/pathing/* (already correct from M1.5)
scenes/level_1/* (already correct from M1.5)
scripts/EditMode.gd, scripts/light_mode.gd, scripts/camera_zoom.gd

Locked design decisions

Character spawn positions in main.gd: three characters spawn just inside the door at world (1.44, 3.56), slightly spread out. Suggested: Brawler at (0.6, 3.0), Cat Burglar at (1.44, 3.0), Hacker at (2.3, 3.0). Each ~0.7m apart, none overlapping the door.
Selection: click a character with left mouse to select. Tab cycles through characters in order. Selected character renders with a white ring around it.
Right-click priority cascade at the clicked world position (in this order, first match wins):

Self / other character: ignore (return without opening menu).
Chest (within CHEST_CLICK_R of _level.get_chest_obstacle().center): show "Pick Lock" / "Pick Up" / "Move + Pick Lock" / "Move + Pick Up" depending on range.
Floor (anywhere else): show "Move here" with cost.
Out of bounds (outside room): no menu opens.

Hack-Door, Hack-CCTV, Takedown, Hold-Hostage menus are M3/M4 — skip in M2.
Click radii in world meters (not pixels):

CHEST_CLICK_R = 1.5 (m) — generous click target around the 0.75m chest
ACTION_REACH_PX from old code becomes ACTION_REACH = 0.5 (m)
Character self-click hit radius = 0.4 (m)


Per-turn time budget: each character has 10 seconds per turn (GameManager.TURN_DURATION = 10.0). Actions that exceed remaining budget are shown disabled in the menu (greyed out, with cost in the label).
The mission timer runs from the moment the game starts. GameManager.start_mission(60.0) was called in M1; M2 keeps it. The HUD shows total time remaining.
Compound actions: "Move + Pick Lock" queues two actions back-to-back: an ActionMove to an approach position near the chest, then an ActionPickLock. Same for "Move + Pick Up". The approach position is along the line from character to chest, at distance chest_radius + CHAR_RADIUS + 0.05m from the chest center.
Action queue is the source of truth. When a character has queued actions, their logical_pos is still their pre-queue position; the queue stores actions with their costs. Time spent is the sum of cost across queued actions for that character. The character only physically moves during Commit phase (which is M3 — for M2 actions just sit in the queue).
For M2, "Commit" button is disabled-ish. Add the button to HUD but pressing it does nothing (or prints a message). M3 wires it up.
Predict button is disabled in M2. Add it but it does nothing.
Undo (`) removes the last action from the currently selected character's queue. Reset (R) clears all queues for all characters.

What to build
Action classes
Port verbatim from main branch (they're coordinate-agnostic):

scripts/actions/action_base.gd (class ActionBase)
scripts/actions/action_move.gd (class ActionMove) — the path field is now MovePath in world meters, no other change
scripts/actions/action_pick_lock.gd (class ActionPickLock)
scripts/actions/action_pickup.gd (class ActionPickUp)

Skip these for M2 (they go in M3/M4): action_hack.gd, action_takedown.gd, action_hold_hostage.gd. Don't create them yet.
PlayerCharacter additions
Update scripts/player_character.gd:

Add character_id: int, character_class: Character.CharacterClass, selected: bool.
Add stat fields read from class: stat_str, stat_int, stat_agi, base_weight_kg, carried_weight_kg. Initialize from Character.get_stats(character_class) (port from main:scripts/character.gd).
Add effective_weight() -> float returning base_weight_kg + carried_weight_kg.
Add action queue methods: queue_action(a), queue_actions(arr), undo_last_action(), reset_turn_actions(), get_queued_actions(), get_turn_time_used() -> float, get_turn_time_remaining() -> float. The queue itself is delegated to the ActionQueue autoload, keyed by character_id.
Add select(), deselect() that flip selected and queue_redraw().
In _draw(), draw a white ring around the character if selected (1px wider than the class circle).
Class color: Brawler red #dc4444, Cat Burglar dark grey #2c2c34, Hacker green #5acb5d. Adjust the existing draw_circle to use class color instead of hardcoded blue.
Add a small name label drawn above the character (text = Character.class_name(character_class) or just "Brawler"/"Cat Burglar"/"Hacker"). Use ThemeDB.fallback_font at size 10.

Selection and input — main.gd
Replace M1's single-character main.gd with the three-character version. Reference git show main:scripts/main.gd for the selection logic and right-click cascade structure. Adapt to iso world coords:

Spawn three characters at the positions in design decision #1.
Track _selected_index: int, _characters: Array[PlayerCharacter].
Left-click in empty space: do nothing (M1's "click-to-move" is replaced by the right-click menu).
Left-click on a character: select it.
Tab: cycle selection.
Backtick (KEY_QUOTELEFT): undo selected character's last action.
R: reset all character queues.
Right-click anywhere: run the priority cascade, build action items, show the context menu.
Mouse positions: always go through IsoMath.unproject() to get world meters.

Hit-testing for character self-click uses world distance: world_pos.distance_to(ch.logical_pos) <= 0.4.
Context menu — port and adapt
Port scripts/ui/context_menu.gd and scenes/ui/context_menu.tscn verbatim. The menu is a Control on a CanvasLayer — works in screen space, no iso conversion needed.
Item builders in main.gd:

_build_move_items(world_pos, sel) — pathfind from sel.logical_pos to world_pos, return one menu item with cost = path.time_cost(sel.stat_agi, sel.effective_weight()). Disabled if cost > remaining.
_build_chest_items(sel) — chest center from _level.get_chest_obstacle().center. If chest locked: show pick lock cost. Show pickup cost. If sel.logical_pos within action range, item is a single action; else compound "Move + X" item that pathfinds first.

Skip _build_guard_items, _build_hack_items — those are M3/M4.
Action execution in main.gd::_on_action_selected(action_type, data):

"move" — instantiate ActionMove, set character_id, cost, path from data, call sel.queue_action(action).
"pick_lock" — instantiate ActionPickLock, queue.
"pickup" — instantiate ActionPickUp, queue.
"move_pick_lock" — queue [ActionMove, ActionPickLock] together via queue_actions(...).
"move_pickup" — queue [ActionMove, ActionPickUp] together.

Path preview
Port scripts/ui/path_preview.gd and scenes/ui/path_preview.tscn. The preview was screen-space; in iso world it needs to project waypoints to screen for drawing. In path_preview.gd::_draw(), where it draws the path, replace seg_a / seg_b with IsoMath.project(seg_a) / IsoMath.project(seg_b) before draw_line.
The preview is shown when a context menu is open with a move-containing item enabled, hidden when the menu closes.
Chest as a real obstacle
The chest is at world (3.22, -4.19) per M1.5. Add chest state to level_1.gd:

chest_locked: bool = true
chest_picked_up: bool = false
Methods: unlock_chest(), pickup_chest() (sets picked_up flag).

Update get_chest_obstacle() to return {center: (3.22, -4.19), radius: 0.0} if chest_picked_up, else {center: (3.22, -4.19), radius: 0.75}.
Note: the chest stays an obstacle for pathfinding even after pickup is queued (since queueing is planning, not committing). M2 doesn't actually execute the pickup; that's M3.
Update level_1.gd::_draw() to render the chest indicator as gold if locked, grey if unlocked, hidden if picked up. Sets the visual signal during planning.
HUD
Port scenes/ui/hud.gd and scenes/ui/hud.tscn. Adaptations:

Time bar shows mission time remaining (GameManager.time_remaining).
Per-character panel shows: name, class color square, time used / total per turn, list of queued actions (just labels, e.g., "Move (3.2s)", "Pick Lock (6.0s)").
Predict button: present, disabled.
Commit button: present, disabled.
Selected character is highlighted in the HUD.
HUD updates whenever queue changes (call _hud.update_selected_character(sel) after action add/undo/reset).

Approach-position helper
In main.gd, helper:
func _approach_pos(target: Vector2, obs_radius: float, char_pos: Vector2) -> Vector2:
    var dir := char_pos - target
    if dir.length_squared() < 0.01:
        dir = Vector2(0.0, 1.0)
    return target + dir.normalized() * (obs_radius + Pathfinder.CHAR_RADIUS + 0.05)
Used by _build_chest_items to find where to stop on the way to the chest.
TimeCalculator usage
All cost computations call into TimeCalculator:

Move: path.time_cost(sel.stat_agi, sel.effective_weight()) (which internally uses TimeCalculator.move_time per segment).
Pick lock: TimeCalculator.lock_time(1, sel.stat_agi, sel.stat_str) (lock level 1, glass type — M2 keeps the chest as a single lock level).
Pick up: TimeCalculator.pickup_time(item_kg, sel.stat_str, sel.stat_int) where item_kg = 60.0 if locked, 10.0 if unlocked (chest is heavy because of the lock weight per old code; you'll see this in _build_chest_items on main).

Constraints

Don't touch the iso math, the pathfinder, or the level walls. Those are correct.
The character's position field stays driven by IsoMath.project(logical_pos) as established in M1. Don't add direct position writes anywhere except via set_logical_pos().
Don't implement Predict, Commit, guards, CCTVs, or any action playback. That's M3+.
Don't modify EditMode or LightMode. They still work as-is.
All click radii and ranges in world meters. No *_PX constants in main.gd or level_1.gd. (EditMode and LightMode keep their internal pixel math, that's fine.)
Keep the M1.5 chest centroid (3.22, -4.19). Don't move it.

Tests
Add a new test file tests/test_actions.gd with these cases:

Queueing one move action: queue size becomes 1, get_turn_time_used() matches the action's cost.
Queueing two actions: queue size 2, time used = sum.
undo_last_action() removes the last entry, time used decreases.
reset_turn_actions() empties the queue.
get_turn_time_remaining() returns TURN_DURATION - used.

Don't add UI tests — the menu/HUD aren't unit-testable headlessly.
Update tests/run_tests.bat to run the new test file in addition to existing two.
Before you start
Read the reference files from main (listed above), then propose your implementation plan in 10–15 bullets, in order of file creation. Wait for me to approve before writing files. After approval, implement in one pass and run all tests headlessly.
Done criteria (what we'll verify)
When you stop, the running game should:

Show three characters near the door: red Brawler, dark Cat Burglar, green Hacker, each labeled.
Click a character → white ring appears (selected). Click another → ring moves.
Tab → cycles selection through all three.
Right-click on the floor far from any object → menu shows "Move here, X.X s". Click → action queues, HUD updates.
Right-click on the chest (gold circle) → menu shows "Pick Lock" and "Pick Up" or "Move + Pick Lock" / "Move + Pick Up" depending on whether the selected character is in range.
Backtick (`) → last queued action removed, HUD updates.
R → all queues reset, HUD shows empty queues for all three.
HUD shows mission time counting down (or static at 60s — depending on whether GameManager.advance_timer runs in planning; M1 had it set up).
Predict and Commit buttons visible but do nothing on press.
F4 / F5 still toggle EditMode / LightMode.
All three test files pass.

Stop and report when done. List files created/modified. Don't proceed to M3.


Send that to Claude Code.
A few notes on what to expect:

The reference files on main have a lot of code, especially main.gd (800 lines) and hud.gd (240 lines). Claude Code will probably want to copy chunks rather than write fresh — that's fine for HUD and context menu, less fine for main.gd because the new one needs iso-coord adaptations throughout. Watch for that in the plan.
The action queue logic on main was tightly coupled to the old screen-space pathfinder. The hardest part of M2 is making sure the cost calculations all flow through world-meter distances cleanly. If Claude Code's plan has any * 32 or / 32 floating around, push back.
The plan should include "implement test_actions.gd" as one of the bullets. If it doesn't, push back.

Milestone 3a Prompt for Claude Code

Milestone 3a — Commit phase: characters execute queued actions
M2 is done: planning loop works, three characters can queue moves, pick lock, pick up actions; HUD shows costs; undo / reset work; chained actions plan from _get_planned_end_pos. The Commit and Predict buttons exist but do nothing.
M3a wires up the Commit button so queued actions actually execute. Press Commit → all three characters animate through their queues in parallel over the 10-second turn budget → mission timer advances by 10 seconds → next planning turn begins.
Out of scope for M3a: Predict phase, guards, CCTVs, win/lose detection, partial actions at turn boundary.
Reference: the old code on main branch
Read these for behavioral spec — the patterns are correct, the coordinate space and constants are wrong:

git show main:scripts/actions/action_move.gd — execute_visual(character) tweens character along path
git show main:scripts/actions/action_pick_lock.gd — squash-stretch tween animation while lockpicking
git show main:scripts/actions/action_pickup.gd — squash-stretch + carries weight
git show main:scripts/player_character.gd — commit_actions(), finalize_for_predict(), _run_action_visuals()
git show main:scripts/main.gd — _on_commit_pressed, _on_turn_started baseline snapshots
git show main:autoloads/turn_manager.gd — phase transitions

Locked design decisions

Commit phase advances the mission timer by TURN_DURATION (10s) regardless of whether characters used the full budget. A character with only 4s of queued actions still consumes 10s of mission time — the unused 4s is wasted. This matches the design doc.
Animations run at ANIMATION_SPEED_MULTIPLIER (currently 5×) of real-time. A 10-second turn animates over 2 real seconds. This is so players don't sit through 10s of waiting per turn.
All three characters' queues animate in parallel. They start at t=0 and animate forward; each character's actions chain back-to-back along their personal timeline. If Brawler has [Move 3s, Pick Lock 6s] and Hacker has [Move 5s], at animation t=4s, Brawler is mid-pick-lock and Hacker is done with his move standing still.
Action timing within a character's queue is sequential. Each action's start_time is the cumulative sum of previous action costs. The action executes from t=start_time to t=start_time + cost.
Commit is irreversible. Once the animation completes, queues are cleared, character logical positions are updated to their final positions, chest state changes (locked → unlocked, picked up flag) persist into the next turn. Backtick / R do not work during commit.
A new turn starts after commit completes. TurnManager transitions PLANNING → COMMIT → PLANNING. Characters get a fresh 10s budget. The mission timer continues counting down (now 50s left if we started at 60s).
Mission ends when timer hits 0. No win/lose logic in M3a — when the timer reaches 0, freeze the game state, show "TIME UP" or similar in the HUD, disable the Commit button. Win/lose is M4.
Inputs locked during Commit. Right-click does nothing. Left-click does nothing. Tab/backtick/R do nothing. F4/F5 still work (editor toggles).
No partial actions across turn boundaries in M3a. If a character's queue sums to more than 10s, that's a planning bug we should have prevented with the disabled-menu logic from M2. Don't try to handle "action runs into next turn" in M3a.

What to build
TurnManager: COMMIT phase
autoloads/turn_manager.gd already has phase transitions from earlier. Add a COMMIT phase to the enum if not already there. Phase order: PLANNING → COMMIT → PLANNING → COMMIT → .... (Predict is M3b — leave it as-is for now.)
Add:

commit_turn() — emits phase_changed(COMMIT), then awaits a signal indicating commit complete, then advances mission timer by TURN_DURATION, then transitions to PLANNING for the next turn.
Signal commit_finished() — emitted by main.gd once all character animations finish.
start_first_turn() from M2 stays the same.

GameManager: timer advance
autoloads/game_manager.gd should already have the mission timer (time_remaining, set by start_mission(60.0)). Add:

advance_timer(seconds: float) -> void — subtracts seconds from time_remaining, clamps at 0, emits a time_changed signal. If timer hits 0, also emit mission_ended().

Action visual execution — port action_*.gd
Each action class needs an execute_visual(character: PlayerCharacter, scene_root: Node) -> Tween method that:

Creates a tween.
Animates whatever the action does (move along path / squash for pick lock / squash for pickup).
Returns the tween for the caller to await.

Reference the old code's patterns:
action_move.gd:
gdscriptfunc execute_visual(character: PlayerCharacter, scene_root: Node) -> Tween:
    var tween := scene_root.create_tween()
    var anim_dur := cost / GameManager.ANIMATION_SPEED_MULTIPLIER
    tween.tween_method(
        func(t: float) -> void: character.set_logical_pos(path.position_at(t)),
        0.0, 1.0, anim_dur
    )
    return tween
action_pick_lock.gd:
Squash-stretch the character (scale x by 0.85, then back to 1.0) while the lock animation runs. At the end, call level.unlock_chest(). Reference old code for exact tween shape — keep the visual identical.
action_pickup.gd:
Similar squash-stretch, plus character.carried_kg += action.item_kg at the end. The chest sprite should hide on completion (level.pickup_chest()).
Action visual execution does NOT update logical_pos directly except via the move tween. Pick lock / pickup happen in place.
PlayerCharacter: commit_actions
Add to scripts/player_character.gd:
gdscriptfunc commit_actions(scene_root: Node) -> Tween:
    var queue: Array = ActionQueue.get_queue(char_id)
    if queue.is_empty():
        return null
    var master := scene_root.create_tween()
    for action_obj in _action_objects:
        var sub_tween: Tween = action_obj.execute_visual(self, scene_root)
        if sub_tween:
            master.tween_subtween(sub_tween)
    return master
The tween_subtween chains tweens sequentially — action 1 finishes, then action 2 starts. Each character runs its own master tween. The three master tweens (one per character) run in parallel because each is independent.
Add clear_queue_after_commit():

Clears _action_objects.
Calls ActionQueue.clear(char_id).
Resets _carried_kg only if pickup didn't happen (pickup persists carried weight to next turn — that's M4 design).

main.gd: commit pressed
Wire the Commit button:
gdscriptfunc _on_commit_pressed() -> void:
    if GameManager.current_phase != GameManager.Phase.PLANNING:
        return
    _context_menu.close()
    for ch in _characters:
        ch._path_preview_for_self_clear()  # or however path preview is cleared
    _path_preview.clear_all()
    _input_locked = true
    _hud.set_phase("COMMIT")
    await _run_commit()
    _input_locked = false
    _hud.set_phase("PLANNING")

func _run_commit() -> void:
    # Start each character's master tween in parallel
    var character_tweens: Array[Tween] = []
    for ch in _characters:
        var t := ch.commit_actions(self)
        if t:
            character_tweens.append(t)
    # Wait for all to finish
    for t in character_tweens:
        await t.finished
    # Clear queues, advance turn
    for ch in _characters:
        ch.clear_queue_after_commit()
    GameManager.advance_timer(GameManager.TURN_DURATION)
    TurnManager.start_next_turn()
    _update_hud()
Add an _input_locked: bool field. In _unhandled_input, early-return if _input_locked. The whole input cascade (left-click, right-click, Tab, R, backtick) is gated by this flag.
TurnManager.start_next_turn
Advances turn counter, emits turn_started(turn_number). Resets per-turn state on each character (whatever needs resetting — for M3a, just verify queues are clear and time-used resets to 0).
HUD: phase indicator
Add a phase label to the HUD: "PLANNING" in green during planning, "COMMITTING..." in orange during commit. Method _hud.set_phase(name: String).
The Commit button is enabled only during PLANNING with at least one character having queued actions. Disabled otherwise.
Bug to fix while you're in there: M2 left the Commit button visually enabled but with no signal. Now it has a signal — confirm the button's pressed signal connects to _on_commit_pressed exactly once.
Path preview clears on commit
When commit starts, the path preview (those colored lines showing planned moves) clear immediately so the player sees the actual movement, not the plan.
Mission ended state
When GameManager.time_remaining hits 0:

HUD shows "TIME UP" or similar.
Commit button greys out permanently.
Right-click cascade returns immediately (no menu).
Tab still works (player can look around).

Don't add restart logic. The game just freezes at game-over. That's M4.
Constraints

Don't touch Pathfinder, MovePath, PathSmoother, IsoMath, level geometry. Those are correct.
Don't add anything Predict-related. No guards, no CCTVs, no FOV. M3b.
Don't change tests/test_pathing.gd or test_time_calculator.gd.
Action animations should NOT teleport the character at the start. The character is at logical_pos; the move tween starts there and ends at the path's last waypoint, smoothly. If you see characters jump, the tween is being constructed wrong.
logical_pos is the source of truth during commit. Each set_logical_pos(p) call updates both the world position and triggers _draw redraws via queue_redraw(). Tweens drive set_logical_pos, not position directly.
EditMode and LightMode keep working during planning. They don't open during commit (input locked).

Tests
Add tests/test_commit.gd:

commit_advances_timer: queue an action, simulate commit (without actually running tweens — just call clear_queue_after_commit and advance_timer), assert time_remaining decreased by 10s.
commit_clears_queue: queue 2 actions, call clear_queue_after_commit, assert queue size is 0.
mission_ends_at_zero: set time_remaining to 5, advance_timer(10), assert time_remaining is 0 and mission_ended was emitted.
commit_disabled_during_commit_phase: set phase to COMMIT, call _on_commit_pressed, assert nothing happened (queue still has actions, timer didn't change).

Update tests/run_tests.bat to include test_commit.gd.
Before you start
Read the reference files from main, then propose your plan in 8–12 bullets. Two things to specifically address in your plan:

How tween chaining works for parallel-character / sequential-actions-per-character. Explain the data flow: 3 master tweens (one per character) running in parallel, each containing N subtweens (one per queued action) running sequentially.
How await t.finished works in your design. Confirm _run_commit correctly waits for the slowest character to finish before advancing the turn.

Wait for my approval before writing files. After approval, implement in one pass and run all tests.
Done criteria
When you stop, the running game should:

Queue actions on multiple characters.
Click Commit. Path previews clear. Phase label shows "COMMITTING…". All characters animate in parallel: movers move along paths, lockpickers squash-stretch in place, pickup-ers squash and chest disappears.
After ~2 real seconds (10s × ANIMATION_SPEED_MULTIPLIER), animation ends.
Mission timer drops by 10s.
Phase returns to "PLANNING". Characters' queues are empty. Time-used resets to 0 per character. Action queues in HUD are blank.
Players can right-click and queue new actions — second turn works identically.
After 6 turns, timer hits 0, "TIME UP" shows, Commit button greyed permanently.
EditMode (F4) / LightMode (F5) still work.
All test files pass.

Stop and report. Don't proceed to M3b.