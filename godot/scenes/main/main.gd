extends Node2D
## Smoke-test scene for the project scaffold (build-order step 1). Proves
## the four Autoloads initialize without error and prints/display their
## state — nothing here is real gameplay yet. Replace as build-order step 3
## (core entities) lands.

@onready var debug_label: Label = $DebugLabel

func _ready() -> void:
	var state_name: String = GameState.State.keys()[GameState.current]
	var lines: Array[String] = [
		"EMBERFALL: LAST LIGHT — Godot scaffold (build-order step 1 of 12)",
		"",
		"GameState  : %s (simulating: %s)" % [state_name, GameState.is_simulating()],
		"RunState   : zone_index=%d, player_level=%d, xp_to_next=%.0f" % [
			RunState.zone_index, RunState.player_level, RunState.xp_required_for_next_level()
		],
		"MetaProgress: Soul Ash=%d, save file loaded: %s" % [
			MetaProgression.soul_ash, str(FileAccess.file_exists(MetaProgression.SAVE_PATH))
		],
		"CombatManager: signal surface wired (%s)" % str(CombatManager.has_signal("hit_landed")),
		"",
		"See /GODOT_MIGRATION.md (repo root) for the full transition plan.",
	]
	var text := "\n".join(lines)
	debug_label.text = text
	print(text)
