# Emberfall: Last Light — Godot rebuild

This is the Godot-side counterpart to the Web prototype in `src/` at the
repo root. Full context — what exists in the Web build, what should be
kept/improved/rebuilt, the recommended architecture, and the complete
12-step build order this project is following — lives in
[`GODOT_MIGRATION.md`](../GODOT_MIGRATION.md) at the repo root. Read that
first; this file only tracks what's actually been built here so far.

## Status: build-order step 5 of 12 — weapon behaviors

**Important caveat:** this project was authored without access to the
Godot editor or engine binary — this environment doesn't have Godot
installed, so most of it has not been opened, run, or validated by the
actual engine. **Steps 1-4 have been confirmed working** by the user
running them in their own Godot editor, including live debugging of three
real issues this session surfaced and fixed (a null-guard gap in
`weapon()`/`ability()`, a debug-label layout overlap, and a duplicate
`combo_step` field GDScript rejects that TypeScript silently allows).
**Step 5 below has NOT yet had that same live confirmation** — treat it as
unverified until you run it and report back. If anything fails to parse or
run, report the exact error.

### Steps 1-4 — scaffold, data as Resources, core entities, combat+AI (confirmed working)

5 Autoloads, 80 `.tres` Resource files across 10 content categories,
Player/Enemy/Boss as `CharacterBody2D` entities with real movement/
stamina/dodge/cooldown gating, the full damage pipeline (melee arc,
projectiles, contact damage, warden bash, bloat detonation), all 6 enemy
AI behavior families, and the generic status-effect runtime (Burn procs
for real off player hits). Full detail in git history — see the
step-1/2/3/4 commits, or `GODOT_MIGRATION.md` for the architecture.

### Step 5 — weapon behaviors: the Strategy split (just added, unverified)

`GODOT_MIGRATION.md` §8's whole point: `CombatSystem.ts` executes every
weapon through one function per `kind`, so a third archetype means a third
branch in that same function. Godot instead gets one `WeaponBehavior`
subclass per attack archetype — adding a new attack shape later means one
new subclass file, never a wider `if/else` anywhere.

| File | Ports | State |
|---|---|---|
| `combat/weapon_behavior.gd` | §8's `WeaponBehavior` concept | The base Strategy class + `for_kind(kind)`, the one place a `WeaponDefinition.Kind` maps to its behavior instance |
| `combat/melee_arc_behavior.gd` | `CombatSystem.ts`'s melee branch | Thin entry point into `CombatManager.perform_melee_attack` (step 4, already confirmed working) — no logic duplicated |
| `combat/projectile_shot_behavior.gd` + `CombatManager.fire_player_projectile` | `fireProjectileWeapon` | New: the player can now actually fire projectiles — shot count from `stats.projectile_count`, fanned across a spread when >1, every stat (crit chance, pierce, knockback, lifesteal, burn chance) baked into the bolt at fire time exactly like the Web build |
| `entities/player.gd` | — | `start_attack()` now dispatches through `WeaponBehavior.for_kind(w.kind).execute(self, w)` instead of the old melee-only shortcut. Also gained a **debug-only** weapon-cycle: press **Q** to cycle Ember Blade → Void Scythe → Solar Spear → Bow (a stand-in for `LoadoutSelectUI.ts`'s real screen, still step 9) |

**Deferred this pass, on purpose:** abilities' actual effects and synergies
still depend on the upgrade-ownership system (step 6) — right-click still
just drains/refills energy with no effect. Weapon *art* (a sprite per
weapon on a hand marker, per §8) is step 7; SFX is step 10.

`scenes/main/`'s playground now seeds the player's `unlocked_weapons` with
all 4 weapons (debug-only — the real Armory unlock flow is steps 6/9) so
Q-cycling can actually reach the ranged weapons. The live debug panel now
also shows the currently-equipped weapon's name and kind.

**How to test it:** run the project — steps 1-4 should behave exactly as
before (see the confirmed-working summary above; if any of that regressed,
that's a real bug to report). Then press **Q** a couple of times to cycle
to the Solar Spear or Bow (the live panel's `weapon:` line should read
`RANGED`), aim at an enemy, and left-click: a small bolt should actually
fly out and travel toward your cursor direction, landing on the first
enemy it touches (their HP text should drop, same as melee) and either
disappearing (Bow, pierce 1) or continuing through up to 2 enemies (Solar
Spear). Cycle back to a melee weapon and confirm swings still work as
before. None of step 5 has been confirmed working yet — report exactly
what you see, including anything that looks wrong or any error text in the
Output panel.

### Next steps (not started)

Per `GODOT_MIGRATION.md` §5, step 6: level generation — port
`LevelGenerator.ts` and build the *bidirectional* room-transition flow
from day one (retreat-to-previous-zone is the current design, not a later
add-on), get a full run navigable start-to-boss-and-back with placeholder
visuals. This is also when the upgrade-ownership system goes in, which is
what unlocks synergies and abilities' actual effects.
