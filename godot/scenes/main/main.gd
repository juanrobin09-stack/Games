extends Node2D
## Test scene for build-order steps 1-4: the step-1/2 diagnostic readout,
## Player/Enemy/Boss moving and rendering (step 3), and now real combat —
## enemy AI, the damage pipeline, and status effects (step 4). Not a real
## level — no Room/LevelGenerator yet (that's step 6), just an open
## playground with placeholder circles for everything.
##
## Controls: WASD/arrows move, mouse aims (the white line on the player is
## facing), left click attacks (real melee damage now — try it on the
## nearest enemy and watch its HP text drop), space dodges (brief
## invulnerability), right click channels the ability once energy is full
## (still no actual effect — that's step 5, weapon/ability behaviors).
##
## One of each of the 6 AI behavior families is spawned below so every
## dispatch path in combat/enemy_ai.gd gets exercised: watch the state
## name above each enemy's head (chase/windup/attack/cooldown/...) — a
## melee-like enemy (Ash Crawler) will close in and swing, the ranged one
## (Flame Wisp) will hold its distance and fire bolts, the stalker (Shadow
## Stalker) vanishes and repositions, the warden (Hollow Warden) circles
## and bashes then leaves its guard down, the bloat (Blightbloat) plants
## and detonates, the elite (Ember Devourer) does both melee and ranged
## depending on distance.

const PLAYER_SCENE := preload("res://entities/player.tscn")
const ENEMY_SCENE := preload("res://entities/enemy.tscn")
const BOSS_SCENE := preload("res://entities/boss.tscn")

## One enemy per behavior family (chaser/ranged/stalker/warden/bloat/elite)
## rather than all 11 — enough to exercise every dispatch path in
## enemy_ai.gd without the playground turning into a crowd.
const SHOWCASE_ENEMIES := ["ashCrawler", "flameWisp", "shadowStalker", "hollowWarden", "blightbloat", "emberDevourer"]

@onready var debug_label: Label = $DebugLabel
@onready var live_label: Label = $LiveLabel

var player: PlayerCharacter

func _ready() -> void:
	_print_diagnostics()
	_spawn_playground()

## Live readout of input/gating/combat state, refreshed every frame.
func _process(_delta: float) -> void:
	if player == null:
		return
	var w := player.weapon()
	var a := player.ability()
	var nearest_line := _nearest_enemy_line()
	live_label.text = "\n".join([
		"LIVE (updates every frame):",
		"LMB down: %s   RMB down: %s   Space down: %s" % [
			Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT),
			Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT),
			Input.is_physical_key_pressed(KEY_SPACE),
		],
		"weapon() found: %s   ability() found: %s" % [w != null, a != null],
		"stamina: %.1f/%.1f   energy: %.1f/%.1f   hp: %.1f/%.1f" % [
			player.stamina, player.stats.stamina_max,
			player.energy, player.stats.energy_max,
			player.hp, player.stats.max_hp,
		],
		"can_attack(): %s   can_dodge(): %s   can_use_ability(): %s" % [
			player.can_attack(), player.can_dodge(), player.can_use_ability()
		],
		nearest_line,
	])

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
		"EMBERFALL: LAST LIGHT — Godot scaffold (build-order step 4 of 12)",
		"WASD move, mouse aim, LMB attack (real damage), Space dodge, RMB ability",
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
		var pos: Vector2 = Vector2(cos(i * angle_step), sin(i * angle_step)) * 280.0
		enemy.setup(def, pos, 1.0, 1.0)

	var boss_def: EnemyDefinition = DataRegistry.get_enemy("ashenColossus")
	if boss_def != null:
		var boss: BossCharacter = BOSS_SCENE.instantiate()
		add_child(boss)
		boss.setup(boss_def, Vector2(0.0, -480.0), 1.0, 1.0)
	else:
		push_warning("Playground: ashenColossus not found in DataRegistry")
