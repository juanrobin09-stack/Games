# Emberfall: Last Light — Godot rebuild

This is the Godot-side counterpart to the Web prototype in `src/` at the
repo root. Full context — what exists in the Web build, what should be
kept/improved/rebuilt, the recommended architecture, and the complete
12-step build order this scaffold is following — lives in
[`GODOT_MIGRATION.md`](../GODOT_MIGRATION.md) at the repo root. Read that
first; this file only tracks what's actually been built here so far.

## Status: build-order step 2 of 12 — data as Resources

**Important caveat:** this project was authored without access to the
Godot editor or engine binary — this environment doesn't have Godot
installed, so most of it has not been opened, run, or validated by the
actual engine. **Step 1 (the scaffold + 4 core Autoloads) has been
confirmed working** by the user running it in their own Godot 4.3 editor —
the smoke-test scene's exact expected output was reproduced live. **Step
2's new content below has NOT yet had that same live confirmation** — it
was written carefully against known-stable Godot 4.3 syntax and
cross-checked internally (see below), but treat it as unverified until you
run it. If anything fails to parse or run, report the exact error.

### Step 1 — project scaffold + Autoloads (confirmed working)

| File | Ports | State |
|---|---|---|
| `project.godot` | — | Godot 4.3 project file, 5 Autoloads registered, `scenes/main/main.tscn` as the run scene |
| `autoload/game_state.gd` | `core/GameState.ts` | Complete — stack-based state machine (11 states), `is_simulating()` gives EVENT/SHOP real exclusive states instead of the Web build's implicit modal-flag gap |
| `autoload/run_state.gd` | `progression/RunState.ts` | Partial — seed/zone/room fields, and the Player-Level/XP math (`grant_xp`, the rolling XP-to-next-level curve, `corruption_ratio`) are real and working. `advance_zone`/`retreat_zone`/`spend_stat_point`'s lock-checking are stubs — they need Room/LevelGenerator (step 6) and weapon/zone-unlock state (step 3+) respectively |
| `autoload/meta_progression.gd` | `progression/MetaProgression.ts` + `SaveSystem.ts` | **Complete and functional** — real `user://save.json` read/write with the same per-field validate-and-fall-back-to-default pattern as the Web build |
| `autoload/combat_manager.gd` | `combat/CombatSystem.ts` | Stub — signal surface is wired, plus one working formula (`difficulty_factors`). The actual damage pipeline needs Player/Enemy nodes (step 4) |

### Step 2 — data as Resources (just added, unverified)

`resources/definitions/` holds 15 Resource class scripts: the 9 content
types from `data/types.ts` (`EnemyDefinition`, `WeaponDefinition`,
`AbilityDefinition`, `UpgradeDefinition`, `ZoneDefinition` + `ZoneMaterial`,
`WorldEventDefinition` + `EventOption`, `PermanentUpgradeDefinition`,
`UnlockDefinition`, `SynergyDefinition`), `StatBlock`/`StatModifier` (with
`apply_modifiers`/`clamp_stats` ported from `data/stats.ts`), and the two
new-for-Godot architectures from `GODOT_MIGRATION.md` §7 —
`StatusEffectDefinition` and `TriggeredEffect`. **One design note:**
`TriggeredEffect` is implemented as a `Resource` here, not the "plain
struct" GODOT_MIGRATION.md's prose first sketched — it needs to be a
`Resource` to nest inside another Resource's exported array. Treat the doc
as superseded by the code on this point.

`autoload/data_registry.gd` (5th Autoload) scans `resources/<category>/`
at boot and exposes id-keyed lookups — the Godot equivalent of
`data/enemies.ts`'s `getEnemyDefinition(id)` and its siblings. The
smoke-test scene now prints how many `.tres` files it actually loaded per
category, so a bad file shows up immediately as a count mismatch rather
than a silent gap.

Every piece of real game content has been converted, verified against a
direct read of the current `src/data/*.ts` source (not memory, not the
earlier session documentation — which undercounted world events at 6; it's
actually 7, corrected here):

| Category | Count | Directory |
|---|--:|---|
| Enemies | 11 | `resources/enemies/` |
| Weapons | 4 | `resources/weapons/` |
| Abilities | 3 | `resources/abilities/` |
| In-run upgrades | 28 | `resources/upgrades/` |
| Zones | 3 | `resources/zones/` |
| World events | 7 | `resources/events/` |
| Permanent (Soul Ash) upgrades | 11 | `resources/permanent_upgrades/` |
| Armory unlocks | 6 | `resources/unlocks/` |
| Synergies | 5 | `resources/synergies/` |
| Status effects | 2 | `resources/status_effects/` |

The last row is the one category with no Web equivalent to convert:
**Burn** is the real, faithfully-ported effect (including a documented
approximation — see `status_effect_definition.gd`'s `stack_rule` comment —
of its "a new application only wins if at least as strong" nuance, which a
plain REFRESH rule doesn't fully capture); **Bleed** is the worked example
from `GODOT_MIGRATION.md` §7/§12, proving the architecture handles a
brand-new non-Burn effect. Bleed is inert data — nothing triggers it, by
design, since the brief was to prepare the architecture, not ship the
mechanic.

One data nuance worth knowing before it trips anyone up later: the
`wrath` synergy's `requires` array is `["wrath", "wrath"]` — the same tag
twice, on purpose. This isn't a typo; `Player.ts`'s `recomputeStats()`
special-cases a repeated tag to mean "own 2 upgrades carrying it" rather
than the normal "own 1 upgrade of each of 2 different tags." Documented
directly on `synergy_definition.gd` so it isn't mistaken for a data bug
when the real synergy-activation logic ports later.

### Next steps (not started)

Per `GODOT_MIGRATION.md` §5: placeholder-visual core entities — Player,
Enemy (one scene reused for all 11 definitions), Boss (step 3) — then the
real combat/AI/status-effect runtime (step 4), then the weapon-behavior
Strategy split from §8 (step 5).
