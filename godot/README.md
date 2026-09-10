# Emberfall: Last Light — Godot rebuild

This is the Godot-side counterpart to the Web prototype in `src/` at the
repo root. Full context — what exists in the Web build, what should be
kept/improved/rebuilt, the recommended architecture, and the complete
12-step build order this project is following — lives in
[`GODOT_MIGRATION.md`](../GODOT_MIGRATION.md) at the repo root. Read that
first; this file only tracks what's actually been built here so far.

## Status: build-order step 3 of 12 — core entities

**Important caveat:** this project was authored without access to the
Godot editor or engine binary — this environment doesn't have Godot
installed, so most of it has not been opened, run, or validated by the
actual engine. **Steps 1-2 have been confirmed working** by the user
running them in their own Godot 4.3 editor — the smoke-test scene's exact
expected output (all 5 Autoloads, every `.tres` count matching) was
reproduced live. **Step 3 below has NOT yet had that same live
confirmation** — written carefully against known-stable Godot 4.3 syntax,
but treat it as unverified until you run it. If anything fails to parse
or run, report the exact error.

### Steps 1-2 — scaffold, Autoloads, data as Resources (confirmed working)

5 Autoloads (`DataRegistry`, `GameState`, `RunState`, `MetaProgression`,
`CombatManager`) and 80 `.tres` Resource files across 10 content
categories (11 enemies, 4 weapons, 3 abilities, 28 upgrades, 3 zones, 7
world events, 11 permanent upgrades, 6 unlocks, 5 synergies, 2 status
effects), all verified against a direct read of `src/data/*.ts` — not
memory. Full detail on what's real vs. stubbed in each Autoload, and the
two new-for-Godot architectures (`StatusEffectDefinition`/
`TriggeredEffect` from `GODOT_MIGRATION.md` §7), is in the git history for
this file — see the step-1 and step-2 commits, or `GODOT_MIGRATION.md`
itself for the architecture.

### Step 3 — core entities (just added, unverified)

`entities/` holds three `CharacterBody2D` scenes:

| File | Ports | State |
|---|---|---|
| `player.gd` + `player.tscn` | `entities/Player.ts` | Movement, stamina/energy/HP resources and their regen formulas, M1/dodge/ability cooldown gating, invulnerability, `take_damage`/`heal` — all ported field-for-field and formula-for-formula from a direct read of the source. Raw mouse+WASD input read directly in-script (see the file's own header comment for why this skips project.godot's InputMap for now — a deliberate, easily-reversed step-3 simplification, not a shortcut that boxes in later steps). **Not** ported yet, on purpose: `recomputeStats()`/`addUpgrade()`/synergies — there are no owned upgrades to recompute from until progression lands (step 6), so `stats` sits at `StatBlock.fresh()`. |
| `enemy.gd` + `enemy.tscn` | `entities/Enemy.ts` | The data shell — HP, knockback, difficulty multipliers, the `setup(def, pos, hp_mult, damage_mult)` constructor-equivalent — reused for all 11 `EnemyDefinition`s exactly like the Web build's one `Enemy` class. `state` exists as a field but nothing transitions it: real AI (the 6 behavior-dispatch functions) is step 4. Burn/status-effect fields are deliberately absent here too — they arrive with the real status-effect runtime in step 4, not half-wired now. |
| `boss.gd` + `boss.tscn` | `entities/Boss.ts` | Extends `enemy.gd` (mirrors the Web class hierarchy). Phase/boss-state fields exist as placeholders; the real phase FSM (5 attack types, meteor rain, phase transitions) is step 4. |

All three currently draw a flat placeholder circle via `_draw()`
(`draw_circle`/`draw_line` — no art, no `AnimatedSprite2D` yet, that's
step 7) sized and colored from real data (`def.radius`/`def.color` for
enemies; a fixed placeholder tone for the player, whose actual radius —
15, from `Player.ts` — is real).

`scenes/main/main.tscn`/`main.gd` now does two things on run: prints the
step-1/2 diagnostic readout (Autoloads + `.tres` counts), and spawns a
playground — one Player at the origin plus 6 representative enemies
(one per behavior family) and the Ashen Colossus placeholder arranged
around it, all built from real `DataRegistry` lookups, not hardcoded
stand-ins. **This is not a real level** — no walls, no Room system (that's
step 6) — just open space to confirm movement/stamina/dodge/cooldown
actually feel right before anything else gets built on top.

**How to test it:** run the project. WASD/arrows move, the mouse aims
(watch the white line on the player circle track it), left click attacks
(cooldown- and stamina-gated — you'll feel it deny a swing under 10
stamina — but deals no real damage yet, that's step 4), space dodges (a
brief fast burst with a short i-frame-equivalent window, though nothing
can hit you yet to prove that), right click channels the ability once
energy is full. Confirm movement has the eased, not-instant accel/decel
feel described in `GODOT_MIGRATION.md`'s Player section, and that stamina
genuinely stops attacks/dodges when it runs out rather than just visually
draining.

### Next steps (not started)

Per `GODOT_MIGRATION.md` §5: the real combat/AI/status-effect runtime
(step 4) — the damage pipeline in `CombatManager`, the 6 enemy behavior
state machines, and the `StatusEffectInstance` runtime component from §7 —
then the weapon-behavior Strategy split from §8 (step 5).
