# Emberfall: Last Light — Godot rebuild

This is the Godot-side counterpart to the Web prototype in `src/` at the
repo root. Full context — what exists in the Web build, what should be
kept/improved/rebuilt, the recommended architecture, and the complete
12-step build order this scaffold is starting — lives in
[`GODOT_MIGRATION.md`](../GODOT_MIGRATION.md) at the repo root. Read that
first; this file only tracks what's actually been built here so far.

## Status: build-order step 1 of 12 — project scaffold + Autoloads

**Important caveat:** this scaffold was authored without access to the
Godot editor or engine binary — this environment doesn't have Godot
installed, so none of it has been opened, run, or validated by the actual
engine. The GDScript and `.tscn`/`project.godot` syntax below was written
carefully against known-stable Godot 4.3 APIs, but **you should open this
in your own Godot 4.3+ editor and confirm it runs before building on top
of it.** If anything fails to parse or run, that's expected risk for
hand-authored engine files with zero editor validation — report the exact
error and it can be fixed directly.

### What's here

| File | Ports | State |
|---|---|---|
| `project.godot` | — | Godot 4.3 project file, 4 Autoloads registered, `scenes/main/main.tscn` as the run scene |
| `autoload/game_state.gd` | `core/GameState.ts` | Complete — stack-based state machine (11 states), `is_simulating()` gives EVENT/SHOP real exclusive states instead of the Web build's implicit modal-flag gap (see GODOT_MIGRATION.md "GameState granularity") |
| `autoload/run_state.gd` | `progression/RunState.ts` | Partial — seed/zone/room fields, and the Player-Level/XP math (`grant_xp`, the rolling XP-to-next-level curve, `corruption_ratio`) are real and working. `advance_zone`/`retreat_zone`/`spend_stat_point`'s lock-checking are stubs — they need Room/LevelGenerator (step 6) and weapon/zone-unlock state (step 3+) respectively |
| `autoload/meta_progression.gd` | `progression/MetaProgression.ts` + `SaveSystem.ts` | **Complete and functional** — real `user://save.json` read/write with the same per-field validate-and-fall-back-to-default pattern as the Web build. No dependency on anything else being built, so this one isn't a stub |
| `autoload/combat_manager.gd` | `combat/CombatSystem.ts` | Stub — signal surface (`hit_landed`, `crit_landed`, `dodge_perfected`, `ability_cast`, `enemy_died`, `player_died`) is wired and ready for other systems to connect to, plus one working formula (`difficulty_factors`, ported from `world/Difficulty.ts`). The actual damage pipeline needs Player/Enemy nodes (step 4) |
| `scenes/main/main.tscn` + `main.gd` | — | A smoke-test scene, not real gameplay: on run, it prints each Autoload's live state to the output console and an on-screen label, so opening the project and hitting Play is an immediate "did the scaffold actually load" check |

### Next steps (not started)

Per `GODOT_MIGRATION.md` §5, in order: convert `data/*.ts` into `Resource`
scripts + `.tres` files (step 2) — including `StatusEffectDefinition` /
`TriggeredEffect` from §7 and `WeaponDefinition` + the `WeaponBehavior`
strategy split from §8, both designed but not implemented anywhere yet —
then placeholder-visual core entities (step 3), then the real combat/AI/
status-effect runtime (step 4).
