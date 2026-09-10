class_name SynergyDefinition
extends Resource
## Ports data/types.ts's SynergyDefinition + data/synergies.ts's 5 entries.
## Activates when the player owns at least one upgrade carrying EACH of the
## two tags in `requires` — announced with a banner + chime the moment a
## pair activates (Web build), and folds into synergy-specific damage/
## behavior modifiers (e.g. Ash & Fire's +40% burning-target damage,
## Shadow & Dodge's perfect-dodge window) resolved in the combat pipeline,
## not stored on this definition itself.

@export var id: String = ""
@export var name: String = ""
@export_multiline var description: String = ""
## Exactly 2 SynergyTag strings, e.g. ["ash", "fire"] — EXCEPT the "wrath"
## synergy, which deliberately repeats the same tag twice (["wrath",
## "wrath"]), reusing this same 2-slot shape to express a different rule.
## Port Player.ts's recomputeStats() check verbatim when this activation
## logic lands (not yet — no entity exists to own it):
##   need = (requires[0] == requires[1]) ? 2 : 1
##   active = (requires[0] == requires[1])
##       ? count(requires[0]) >= need
##       : count(requires[0]) >= 1 and count(requires[1]) >= 1
## i.e. same-tag-twice means "own 2 upgrades carrying that tag," not the
## normal "own 1 upgrade of each of 2 different tags." Confirmed against
## source directly — not a data bug, don't "fix" the wrath.tres data.
@export var requires: Array[String] = []
@export var icon: String = ""
