class_name BossCharacter
extends EnemyCharacter
## Ports entities/Boss.ts's field shell for The Ashen Colossus. The real
## phase FSM (chooseNextAttack, meteor rain, phase transitions, the 5
## attack types) is build-order step 4 — these fields exist so step 4 has
## somewhere to land without a second refactor of this file. Boss reuses
## Enemy's physics/collision/placeholder-draw plumbing exactly as the Web
## build's Boss class extends Enemy for the same reason.
##
## Boss.ts's own field list re-declares `comboStep = 0` even though its
## parent `Enemy` already has one (used there for the warden's champion
## combo) — harmless in TypeScript (redeclaring a same-typed field in a
## subclass is a no-op), but GDScript rejects it outright as a duplicate
## member. Not ported here for that reason: `combo_step` below is the one
## inherited from EnemyCharacter, reused as-is for the boss's own phase-3
## Combo attack (2 chained Melee Slams) rather than shadowed.

enum Phase { ONE = 1, TWO = 2, THREE = 3 }
enum BossState {
	INTRO, IDLE, TELEGRAPH_SLAM, TELEGRAPH_COMBO, TELEGRAPH_SHOCKWAVE,
	TELEGRAPH_PROJECTILE, SUMMONING, RECOVER, PHASE_TRANSITION, DYING,
}

## HP-ratio breakpoints for phase 1->2 and 2->3, per Boss.ts.
const PHASE_THRESHOLDS := [0.64, 0.30]

var phase: Phase = Phase.ONE
var boss_state: BossState = BossState.INTRO
var boss_state_timer: float = 0.0
var attack_choice_cooldown: float = 1.4
var invulnerable: bool = true
var meteor_spawn_timer: float = 4.0
var death_animation_done: bool = false
var intro_done: bool = false

func move_speed_for_phase() -> float:
	var factor: float = 1.0 if phase == Phase.ONE else (1.3 if phase == Phase.TWO else 1.55)
	return def.move_speed * factor
