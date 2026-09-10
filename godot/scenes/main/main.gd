extends Node2D
## Smoke-test scene for the project scaffold (build-order steps 1-2). Proves
## the five Autoloads initialize without error, and that DataRegistry
## actually loaded every .tres file on disk — nothing here is real gameplay
## yet. Replace as build-order step 3 (core entities) lands.

@onready var debug_label: Label = $DebugLabel

func _ready() -> void:
	var state_name: String = GameState.State.keys()[GameState.current]
	var counts := DataRegistry.counts()
	var expected := {
		"enemies": 11, "weapons": 4, "abilities": 3, "upgrades": 28,
		"zones": 3, "events": 7, "permanent_upgrades": 11, "unlocks": 6,
		"synergies": 5, "status_effects": 2,
	}
	var data_lines: Array[String] = []
	for category in expected.keys():
		var got: int = counts.get(category, 0)
		var want: int = expected[category]
		var flag := "" if got == want else "  <-- expected %d" % want
		data_lines.append("  %-18s %d%s" % [category, got, flag])

	var lines: Array[String] = [
		"EMBERFALL: LAST LIGHT — Godot scaffold (build-order step 2 of 12)",
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
		"DataRegistry (.tres files actually loaded from disk):",
	]
	lines.append_array(data_lines)
	lines.append("")
	lines.append("See /GODOT_MIGRATION.md (repo root) for the full transition plan.")

	var text := "\n".join(lines)
	debug_label.text = text
	print(text)
