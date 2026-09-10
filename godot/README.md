# Emberfall: Last Light — Godot rebuild

This is the Godot-side counterpart to the Web prototype in `src/` at the
repo root. Full context — what exists in the Web build, what should be
kept/improved/rebuilt, the recommended architecture, and the complete
12-step build order this project is following — lives in
[`GODOT_MIGRATION.md`](../GODOT_MIGRATION.md) at the repo root. Read that
first; this file only tracks what's actually been built here so far.

## Status: build-order step 4 of 12 — combat, AI, status effects

**Important caveat:** this project was authored without access to the
Godot editor or engine binary — this environment doesn't have Godot
installed, so most of it has not been opened, run, or validated by the
actual engine. **Steps 1-3 have been confirmed working** by the user
running them in their own Godot 4.3 editor, including live debugging of
two real issues this session surfaced and fixed (a null-guard gap in
`weapon()`/`ability()`, and a debug-label layout overlap). **Step 4 below
has NOT yet had that same live confirmation** — treat it as unverified
until you run it and report back. If anything fails to parse or run,
report the exact error; this is by far the largest single step so far, so
expect a real chance of something needing a fix.

### Steps 1-3 — scaffold, data as Resources, core entities (confirmed working)

5 Autoloads, 80 `.tres` Resource files across 10 content categories, and
Player/Enemy/Boss as `CharacterBody2D` entities with real movement/
stamina/dodge/cooldown gating. Full detail in git history — see the
step-1/2/3 commits, or `GODOT_MIGRATION.md` for the architecture.

### Step 4 — combat pipeline, enemy AI, status-effect runtime (just added, unverified)

The biggest step yet. Every number below was read directly from
`CombatSystem.ts`/`EnemyAI.ts`/`Enemy.ts`/`Projectile.ts` this session —
not approximated.

| File | Ports | State |
|---|---|---|
| `autoload/combat_manager.gd` | `combat/CombatSystem.ts` | The real damage pipeline: `damage_player_to_enemy`/`damage_enemy_to_player` (crit rolls, the warden frontal-shield block, knockback, lifesteal, crit-interrupt-to-stagger), `perform_melee_attack` (the player's own M1, instant-arc hit check), contact damage, warden bash hits, Bloat detonation, the champion shield-break beat (spawns its 2 Blightbloat reinforcements) |
| `combat/enemy_ai.gd` | `ai/EnemyAI.ts` | All 6 behavior state machines verbatim — melee-like (chaser/tank/heavy), ranged, stalker, elite (hybrid melee/ranged by distance), bloat, and the full warden (shield/bash/exposed-window, plus the champion's flat-50%-HP phase break and faster double-bash) |
| `combat/status_effect_instance.gd` + `status_effect_runtime.gd` | New for Godot, §7 | The real runtime this session's architecture work was building toward: `apply()`/`process()` shared by both Player and Enemy, ticking damage through `CombatManager`. Burn now genuinely procs off player hits (`burn_chance` roll → applies the real `StatusEffectDefinition`) |
| `entities/projectile.gd` + `.tscn` | `entities/Projectile.ts` | Self-contained `Area2D` — checks its own overlap against the `enemies`/`player` groups every physics tick, pierce-dedups via `register_hit`, expires on lifetime or first non-piercing hit |
| `entities/player.gd`, `enemy.gd` | — | Wired to the above: `start_attack()` now calls `perform_melee_attack`; `EnemyCharacter` gained `ai_velocity` (kept deliberately separate from `knockback_velocity` — see the file's own header comment for why merging them would be a real bug), the warden/bloat/champion state fields, and a debug HP/state-name label drawn above each enemy |

**Deferred this pass, on purpose** (see `combat_manager.gd`'s and
`enemy_ai.gd`'s own header comments for the full list): synergies
(depend on the upgrade-ownership system, step 6), abilities' actual
effects and ranged/projectile weapon firing (weapon-behavior execution,
step 5), damage numbers/particles/camera shake/SFX (step 8/9), hazards —
lingering spore clouds (Bloat and the champion still deal their direct-hit
damage, just not the cloud that's supposed to follow), and enemy-crowd
separation (`applyEnemySeparation` — cosmetic, wants a spatial grid this
project doesn't have yet). One function, `resolve_melee_land`, is *not* a
byte-exact port — the Web build's own callback body wasn't in the portion
of `Game.ts` read this session, so it's implemented from the same
"did-you-stay-in-the-blast" principle every other telegraphed-hit check
here already uses verbatim; flagged in its own comment.

`scenes/main/`'s playground now spawns one enemy per behavior family
(Ash Crawler/Flame Wisp/Shadow Stalker/Hollow Warden/Blightbloat/Ember
Devourer) instead of a less-representative sample, so every dispatch path
in `enemy_ai.gd` actually gets exercised. The live debug panel now also
shows the nearest enemy's name/distance/state/HP.

**How to test it:** run the project. Approach the Ash Crawler and left-click
— its HP text (drawn above its head) should drop, and its state should
cycle chase → windup → attack → cooldown → chase. Watch the Hollow Warden:
it should circle to face you before bashing, then sit exposed (guard
down, a visible arc no longer drawn) for a beat afterward — hit it during
that window versus while the arc is showing and compare the damage
(should be ~15% while shielded). The Flame Wisp should hold distance and
fire bolts rather than closing in. The Blightbloat should walk up, plant,
swell, and detonate — check its HP hits 0 and it disappears. Take a few
hits and confirm your own HP in the live panel actually drops (contact
damage, bolts, bashes). None of this has been confirmed working yet —
report exactly what you see, including anything that looks wrong or any
error text in the Output panel.

### Next steps (not started)

Per `GODOT_MIGRATION.md` §5: the weapon-behavior Strategy split from §8
(step 5) — `WeaponBehavior` per attack archetype (`MeleeArc`,
`ProjectileShot`), so the Bow/Solar Spear can actually fire, replacing
`player.gd`'s current "melee only" shortcut — then progression (step 6):
XP/Level, the in-run upgrade pool, and the permanent Soul Ash tree, which
is also when synergies and the deferred ability effects become meaningful
to wire up.
