extends Node2D
## Test scene for build-order steps 1-3: proves the five Autoloads and
## DataRegistry work (the diagnostic readout from steps 1-2), AND that
## Player/Enemy/Boss actually move and render (step 3) — not a real level,
## no Room/LevelGenerator yet (that's step 6), just an open playground.
##
## Controls: WASD/arrows move, mouse aims (the white line on the player is
## facing), left click attacks (cooldown/stamina-gated, no real damage
## yet — that's step 4), space dodges, right click channels the ability.

const PLAYER_SCENE := preload("res://entities/player.tscn")
const ENEMY_SCENE := preload("res://entities/enemy.tscn")
const BOSS_SCENE := preload("res://entities/boss.tscn")

## A representative slice of the roster, not all 11 — enough to see every
## placeholder color/size/behavior-family at a glance without clutter.
const SHOWCASE_ENEMIES := ["ashCrawler", "hollow", "gravebound", "shadowStalker", "hollowWarden", "emberDevourer"]

@onready var debug_label: Label = $DebugLabel
@onready var live_label: Label = $LiveLabel

var player: PlayerCharacter

func _ready() -> void:
	_print_diagnostics()
	_spawn_playground()

## Live readout of input + gating state, refreshed every frame — added
## while diagnosing a step-3 report of "movement works, attack/ability
## don't": this panel shows within one glance whether the mouse buttons
## are even being detected (LMB/RMB down: true/false) versus whether
## can_attack()/can_use_ability() are the ones refusing, and why (stamina/
## energy/cooldown values, and whether weapon()/ability() resolved at all).
func _process(_delta: float) -> void:
	if player == null:
		return
	var w := player.weapon()
	var a := player.ability()
	live_label.text = "\n".join([
		"LIVE INPUT/GATING (updates every frame):",
		"LMB down: %s   RMB down: %s   Space down: %s" % [
			Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT),
			Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT),
			Input.is_physical_key_pressed(KEY_SPACE),
		],
		"weapon() found: %s   ability() found: %s" % [w != null, a != null],
		"stamina: %.1f / %.1f   energy: %.1f / %.1f   hp: %.1f / %.1f" % [
			player.stamina, player.stats.stamina_max,
			player.energy, player.stats.energy_max,
			player.hp, player.stats.max_hp,
		],
		"can_attack(): %s   can_dodge(): %s   can_use_ability(): %s" % [
			player.can_attack(), player.can_dodge(), player.can_use_ability()
		],
		"attack_cooldown_timer: %.2f   is_dodging: %s   alive: %s" % [
			player.attack_cooldown_timer, player.is_dodging, player.alive
		],
	])

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
		"EMBERFALL: LAST LIGHT — Godot scaffold (build-order step 3 of 12)",
		"WASD move, mouse aim, LMB attack, Space dodge, RMB ability",
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

func _spawn_playground() -> void:
	player = PLAYER_SCENE.instantiate()
	add_child(player)
	player.global_position = Vector2.ZERO

	var angle_step: float = TAU / SHOWCASE_ENEMIES.size()
	for i in range(SHOWCASE_ENEMIES.size()):
		var def: EnemyDefinition = DataRegistry.get_enemy(SHOWCASE_ENEMIES[i])
		if def == null:
			push_warning("Playground: enemy id not found in DataRegistry: %s" % SHOWCASE_ENEMIES[i])
			continue
		var enemy: EnemyCharacter = ENEMY_SCENE.instantiate()
		add_child(enemy)
		var pos: Vector2 = Vector2(cos(i * angle_step), sin(i * angle_step)) * 240.0
		enemy.setup(def, pos, 1.0, 1.0)

	var boss_def: EnemyDefinition = DataRegistry.get_enemy("ashenColossus")
	if boss_def != null:
		var boss: BossCharacter = BOSS_SCENE.instantiate()
		add_child(boss)
		boss.setup(boss_def, Vector2(0.0, -420.0), 1.0, 1.0)
	else:
		push_warning("Playground: ashenColossus not found in DataRegistry")
