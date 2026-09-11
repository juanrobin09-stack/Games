extends Node2D
## Entry point for build-order steps 1-8. Boots a real run through
## LevelFlow.start_new_run() — 3 fully generated zones, real rooms with
## real walls/obstacles/enemies/chests, bidirectional stairs, real
## per-entity rendering and lighting (step 7), and GPUParticles2D VFX
## (step 8) — instead of the fixed one-enemy-per-behavior "playground"
## earlier steps used.
##
## Controls: WASD/arrows move, mouse aims, left click attacks (melee or
## ranged depending on the equipped weapon), space dodges, right click
## channels the ability (still no damage/radius effect resolved — the
## player's actual ability effects are progression-system work, not done
## yet), Q cycles the equipped weapon (debug stand-in for the real loadout
## screen, step 9), **E interacts** (chests, the sanctum circle, resting at
## a brazier, stairs). Shop/event landmarks exist and are walkable-up-to
## but their actual interaction is deferred to step 9 (real UI) — pressing
## E on one just prints why nothing happened.
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
@onready var hud: HudLayer = $UI/Hud

var player: PlayerCharacter
var run_seed: String = ""

## The debug/diagnostic panel (DebugLabel + LiveLabel) starts hidden now
## that Hud carries the player-facing version of the same core info —
## toggle back on with F1 when something needs the fuller picture (data
## registry counts, room/enemy internals, upgrades/synergies) the real HUD
## deliberately doesn't surface.
var _debug_visible: bool = false
var _f1_key_down: bool = false

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
	LevelFlow.ui_root = $UI
	LevelFlow.hud = hud
	LevelFlow.start_new_run(run_seed, player, self)

## Live readout of input/gating/combat/room state, refreshed every frame.
func _process(_delta: float) -> void:
	if player == null:
		return

	if Input.is_physical_key_pressed(KEY_F1):
		if not _f1_key_down:
			_f1_key_down = true
			_debug_visible = not _debug_visible
			debug_label.visible = _debug_visible
			live_label.visible = _debug_visible
	else:
		_f1_key_down = false

	var w := player.weapon()
	var a := player.ability()
	var room := RunState.current_room()
	var interaction = LevelFlow.get_interaction()

	hud.update({
		"player": player,
		"embers": RunState.embers,
		"zone_name": room.zone.name if room != null and room.zone != null else "?",
		"room_label": HudLayer.room_type_label(room.type) if room != null else "?",
		"corruption": RunState.corruption_ratio(),
		"weapon_name": w.name if w != null else "?",
		"ability_name": a.name if a != null else "?",
		"weapon_icon": HudLayer.icon_for_weapon(player.weapon_id),
		"ability_icon": HudLayer.icon_for_ability(player.ability_id),
		"interact_prompt": interaction["label"] if interaction != null else "",
		"elapsed_seconds": RunState.elapsed_time,
		"stamina_denied": Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and player.attack_cooldown_timer <= 0.0 and not player.has_enough_stamina(),
		"player_level": RunState.player_level,
		"xp": RunState.xp,
		"xp_to_next": RunState.xp_required_for_next_level(),
		"stat_points": RunState.stat_points,
		"is_max_level": RunState.player_level >= RunState.LEVEL_CAP,
		"boss": _boss_hud_data(room),
	})

	if not _debug_visible:
		return
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
		"upgrades: %d owned   synergies: %s" % [
			player.upgrades.size(),
			", ".join(player.active_synergies) if not player.active_synergies.is_empty() else "-",
		],
		_room_line(room),
		"interact [E]: %s" % (interaction["label"] if interaction != null else "-"),
		_nearest_enemy_line(),
	])

## Ports Game.ts's updateHud() own boss branch — builds a BossHudInfo-
## shaped Dictionary ({name, hp_ratio, phase, max_phase, invulnerable}) for
## hud.gd's own boss bar, or null outside a boss room. The source also
## reuses this exact same bar for a heart-room champion (max_phase=2) —
## out of scope here, this port's champion fight has its own shield-break
## banner already (level_flow.gd's _on_champion_shield_broken) and no
## comparable phase concept to show dots for.
func _boss_hud_data(room: RoomContainer) -> Variant:
	if room == null or room.type != RoomContainer.Type.BOSS:
		return null
	for e in room.enemies:
		var boss := e as BossCharacter
		if boss != null:
			return {
				"name": boss.def.name if boss.def != null else "?",
				"hp_ratio": boss.hp / maxf(1.0, boss.max_hp),
				"phase": int(boss.phase),
				"max_phase": 3,
				"invulnerable": boss.invulnerable,
			}
	return null

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

## Ports data category counts into one compact line, only naming the ones
## that don't match `expected` — DebugLabel has no font_color override (it
## renders in Godot's default white/light theme color) and no live game
## state to react to sizing, so keeping this short matters: the original
## one-category-per-line layout ran to ~20 lines and reliably overflowed
## DebugLabel's box, spilling white text down into LiveLabel's yellow one
## below it (reported directly — half the board was unreadable where they
## overlapped).
func _data_registry_summary(counts: Dictionary) -> String:
	var expected := {
		"enemies": 11, "weapons": 4, "abilities": 3, "upgrades": 28,
		"zones": 3, "events": 7, "permanent_upgrades": 11, "unlocks": 6,
		"synergies": 5, "status_effects": 2,
	}
	var total_got := 0
	var total_want := 0
	var mismatches: Array[String] = []
	for category in expected.keys():
		var got: int = counts.get(category, 0)
		var want: int = expected[category]
		total_got += got
		total_want += want
		if got != want:
			mismatches.append("%s=%d (expected %d)" % [category, got, want])
	if mismatches.is_empty():
		return "DataRegistry: %d/%d .tres files loaded across %d categories, all match" % [
			total_got, total_want, expected.size()
		]
	return "DataRegistry: %d/%d .tres files loaded — MISMATCH: %s" % [
		total_got, total_want, ", ".join(mismatches)
	]

func _print_diagnostics() -> void:
	var state_name: String = GameState.State.keys()[GameState.current]
	var lines: Array[String] = [
		"EMBERFALL: LAST LIGHT — Godot scaffold (build-order step 8 of 12)",
		"WASD move, mouse aim, LMB attack, Space dodge, RMB ability, Q cycle weapon, E interact, F1 debug overlay",
		"GameState: %s (simulating: %s)   Soul Ash: %d   save loaded: %s" % [
			state_name, GameState.is_simulating(), MetaProgression.soul_ash,
			str(FileAccess.file_exists(MetaProgression.SAVE_PATH)),
		],
		_data_registry_summary(DataRegistry.counts()),
		"See /GODOT_MIGRATION.md (repo root) for the full transition plan.",
	]
	var text := "\n".join(lines)
	debug_label.text = text
	print(text)
