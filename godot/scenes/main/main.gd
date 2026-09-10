extends Node2D
## Entry point for build-order steps 1-6. Boots a real run through
## LevelFlow.start_new_run() — 3 fully generated zones, real rooms with
## real walls/obstacles/enemies/chests, bidirectional stairs — instead of
## the fixed one-enemy-per-behavior "playground" earlier steps used. Real
## rendering (sprites, tilesets) is still step 7; every room/obstacle/
## enemy/pickup below is still a flat-colored placeholder shape.
##
## Controls: WASD/arrows move, mouse aims, left click attacks (melee or
## ranged depending on the equipped weapon), space dodges, right click
## channels the ability (still no effect — step 6, progression UI), Q
## cycles the equipped weapon (debug stand-in for the real loadout screen,
## step 9), **E interacts** (chests, the sanctum circle, resting at a
## brazier, stairs) — new this step. Shop/event landmarks exist and are
## walkable-up-to but their actual interaction is deferred to step 9 (real
## UI) — pressing E on one just prints why nothing happened.
##
## A run seed is generated fresh each time this scene loads (shown in the
## debug panel) — same seed always regenerates the same 3 zone layouts in
## this engine (GODOT_MIGRATION.md §6: seeds are engine-local, not expected
## to match the Web build's own layouts for the same seed string).

const PLAYER_SCENE := preload("res://entities/player.tscn")

## Both labels sit under a CanvasLayer ("UI") rather than directly under
## Main — LevelFlow's ambient CanvasModulate (build-order step 7's
## lighting pass) tints the whole base canvas to mimic the dungeon's
## darkness, and debug/diagnostic text should stay legible regardless.
@onready var debug_label: Label = $UI/DebugLabel
@onready var live_label: Label = $UI/LiveLabel

var player: PlayerCharacter
var run_seed: String = ""

func _ready() -> void:
	_print_diagnostics()
	_start_run()

func _start_run() -> void:
	run_seed = str(Time.get_unix_time_from_system()) + ":" + str(randi())
	player = PLAYER_SCENE.instantiate()
	add_child(player)
	# Debug-only: the real Armory/loadout unlock flow is steps 6/9. Seeding
	# all 4 here is what makes the Q weapon-cycle (player.gd) able to reach
	# the ranged weapons at all before that screen exists.
	player.unlocked_weapons = ["emberBlade", "voidScythe", "solarSpear", "bow"]
	LevelFlow.start_new_run(run_seed, player, self)

## Live readout of input/gating/combat/room state, refreshed every frame.
func _process(_delta: float) -> void:
	if player == null:
		return
	var w := player.weapon()
	var a := player.ability()
	var room := RunState.current_room()
	var interaction = LevelFlow.get_interaction()
	live_label.text = "\n".join([
		"LIVE (updates every frame):",
		"LMB down: %s   RMB down: %s   Space down: %s" % [
			Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT),
			Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT),
			Input.is_physical_key_pressed(KEY_SPACE),
		],
		"weapon: %s (%s)   ability() found: %s   [Q cycle weapon]" % [
			w.name if w != null else "<none>",
			WeaponDefinition.Kind.keys()[w.kind] if w != null else "?",
			a != null,
		],
		"stamina: %.1f/%.1f   energy: %.1f/%.1f   hp: %.1f/%.1f" % [
			player.stamina, player.stats.stamina_max,
			player.energy, player.stats.energy_max,
			player.hp, player.stats.max_hp,
		],
		"can_attack(): %s   can_dodge(): %s   can_use_ability(): %s" % [
			player.can_attack(), player.can_dodge(), player.can_use_ability()
		],
		"zone: %d/3   embers: %d   level: %d   xp: %.0f/%.0f" % [
			RunState.zone_index + 1, RunState.embers, RunState.player_level,
			RunState.xp, RunState.xp_required_for_next_level(),
		],
		_room_line(room),
		"interact [E]: %s" % (interaction["label"] if interaction != null else "-"),
		_nearest_enemy_line(),
	])

func _room_line(room: RoomContainer) -> String:
	if room == null:
		return "room: <none>"
	return "room: %s type=%s locked=%s cleared=%s doors=%d enemies=%d" % [
		room.key, RoomContainer.Type.keys()[room.type], room.is_locked(), room.cleared,
		room.doors.size(), room.enemies.size(),
	]

func _nearest_enemy_line() -> String:
	var nearest: EnemyCharacter = null
	var nearest_dist := INF
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as EnemyCharacter
		if enemy == null or not enemy.alive:
			continue
		var d: float = enemy.global_position.distance_to(player.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = enemy
	if nearest == null:
		return "nearest enemy: none alive"
	return "nearest enemy: %s  dist=%.0f  state=%s  hp=%.0f/%.0f" % [
		nearest.def.name, nearest_dist, EnemyCharacter.State.keys()[nearest.state], nearest.hp, nearest.max_hp
	]

func _print_diagnostics() -> void:
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
		"EMBERFALL: LAST LIGHT — Godot scaffold (build-order step 6 of 12)",
		"WASD move, mouse aim, LMB attack, Space dodge, RMB ability, Q cycle weapon, E interact",
		"",
		"GameState  : %s (simulating: %s)" % [state_name, GameState.is_simulating()],
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
