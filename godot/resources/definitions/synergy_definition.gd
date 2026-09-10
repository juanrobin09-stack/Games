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
## Exactly 2 SynergyTag strings, e.g. ["ash", "fire"].
@export var requires: Array[String] = []
@export var icon: String = ""
