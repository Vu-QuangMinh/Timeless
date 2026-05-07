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
