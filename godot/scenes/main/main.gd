extends Node2D
## Entry point + top-level screen orchestrator — the Godot counterpart to
## core/Game.ts's own role as "the single per-frame orchestrator"
## (GODOT_MIGRATION.md §1's architecture diagram). Boots to the main menu;
## Play routes through LevelFlow.start_new_run() for a real run — 3 fully
## generated zones, real rooms with real walls/obstacles/enemies/chests,
## bidirectional stairs, real per-entity rendering/lighting (step 7),
## GPUParticles2D VFX (step 8), and now the full meta-shell (step 9's own
## "Phase B": MainMenu/PauseMenu/Settings/Victory/Defeat/Credits/Armory).
##
## Controls once a run is live: WASD/arrows move, mouse aims, left click
## attacks (melee or ranged depending on the equipped weapon), space
## dodges, right click channels the equipped ability (Ember Burst radial
## burst, Stormstep dash, or Warding Sigil's healing/damage zone — see
## CombatManager's own "Ability" section), **E interacts** (chests, the sanctum circle,
## resting at a brazier, stairs, shop/event landmarks). Which weapon/
## ability a run starts with is chosen once, before EXPLORATION begins —
## LoadoutSelectUI when there's a real choice (more than the single
## starting kit unlocked), an automatic start otherwise; there's no
## in-run switching, matching the source (Game.ts has none either).
##
## A run seed is generated fresh each Play unless the MainMenu's seed field
## is filled in — same seed always regenerates the same 3 zone layouts in
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

var player: PlayerCharacter = null
var run_seed: String = ""
## Guards _end_run() against firing twice for the same run (e.g. a status-
## effect tick killing the player the same frame the boss's own death
## animation finishes) — mirrors Boss.ts/BossSystem.ts's own
## deathHandled-style single-fire guards used throughout this port already.
var _run_ending: bool = false

## The debug/diagnostic panel (DebugLabel + LiveLabel) starts hidden now
## that Hud carries the player-facing version of the same core info —
## toggle back on with F1 when something needs the fuller picture (data
## registry counts, room/enemy internals, upgrades/synergies) the real HUD
## deliberately doesn't surface.
var _debug_visible: bool = false
var _f1_key_down: bool = false
var _escape_key_down: bool = false
## F2 opens AdminMenuUI, a personal dev/testing tool — not a shipped
## feature; safe to remove once no longer needed for that.
var _f2_key_down: bool = false

## Whichever meta-shell screen is currently on top (MainMenu, Credits,
## Victory/Defeat — later PauseMenu/Settings/Armory too), so the next
## transition can close it first. Mirrors Game.ts's own closeModal()/
## modalScreen slot — one screen up at a time, the caller's job to tear
## the old one down before showing the next, not each screen's own.
var _current_screen: Control = null

func _close_current_screen() -> void:
	if _current_screen != null and is_instance_valid(_current_screen):
		_current_screen.queue_free()
	_current_screen = null

func _ready() -> void:
	_print_diagnostics()
	LevelFlow.ui_root = $UI
	LevelFlow.hud = hud
	CombatManager.boss_defeated.connect(func(_boss): _end_run(true))
	CombatManager.player_died.connect(func(): _end_run(false))
	hud.visible = false
	# Game.ts's own textScale setting scales the whole UI by rewriting one
	# CSS custom property the entire DOM's font-sizes cascade from
	# (style.css's own `font-size: calc(16px * var(--ui-scale))` on body).
	# This port's UI has no such single cascade point — every label sets
	# its own explicit font size — so CanvasLayer.scale on $UI itself is
	# the nearest equivalent: one property, applied once, scales
	# everything under it uniformly, same "one knob" shape as the source.
	_apply_ui_scale()
	MetaProgression.settings_changed.connect(func(_patch): _apply_ui_scale())
	# The window itself, not the canvas scale _apply_ui_scale() above
	# handles — window/stretch/mode="canvas_items" (project.godot) means
	# resizing the actual OS window just scales the rendered 1152x648
	# canvas to fit, so every existing screen's pixel-space layout code
	# needs no changes for this to work. Exists because a user reported
	# blur that turned out to be their OS upscaling a small, DPI-unaware
	# window — a bigger real window (or fullscreen, already wired below)
	# renders at genuinely more pixels instead of relying on the OS to
	# stretch fewer of them.
	_apply_window_scale()
	MetaProgression.settings_changed.connect(func(_patch): _apply_window_scale())
	_apply_fullscreen()
	MetaProgression.settings_changed.connect(func(_patch): _apply_fullscreen())
	# Game.ts only calls music.start() lazily, from the FIRST pointerdown/
	# keydown handler — a one-shot gate that exists purely to satisfy
	# browser autoplay policy (an AudioContext starts suspended until a
	# user gesture resumes it). Godot's AudioStreamGenerator has no such
	# restriction, so the gate itself has no equivalent here; starting the
	# score unconditionally on boot is the faithful port of "the score
	# plays for the whole session," not of the workaround around it.
	MusicEngine.start()
	_show_main_menu()

func _apply_ui_scale() -> void:
	var text_scale: float = MetaProgression.settings.get("text_scale", 1.0)
	($UI as CanvasLayer).scale = Vector2.ONE * text_scale

## Skipped while fullscreen: window_set_size() on a fullscreen window would
## just resize the window Godot's own fullscreen mode ignores anyway, and
## read back the wrong size next time this runs. _apply_fullscreen() below
## re-calls this itself right after switching back to windowed, which is
## what actually restores the chosen scale the moment fullscreen turns off.
func _apply_window_scale() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		return
	var scale: float = float(MetaProgression.settings.get("window_scale", "1.0"))
	DisplayServer.window_set_size(Vector2i(1152, 648) * scale)

## Fullscreen is a real, persisted setting (not just a live DisplayServer
## call the old settings_ui.gd toggle button made and forgot) so it
## survives a relaunch like every other preference here — settings_ui.gd's
## fullscreen row is now a plain _build_toggle_row like screen_shake's own,
## reacting through the same settings_changed signal _apply_ui_scale/
## _apply_window_scale already use rather than calling into main.gd
## directly, matching this project's own "UI screens call back into
## main.gd" shape without needing a new callback wired through it.
func _apply_fullscreen() -> void:
	var fullscreen: bool = MetaProgression.settings.get("fullscreen", false)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	if not fullscreen:
		_apply_window_scale()

func _show_main_menu() -> void:
	_close_current_screen()
	GameState.change_state(GameState.State.MAIN_MENU)
	_current_screen = MainMenuUI.show_main_menu($UI, {
		"on_play": func(seed_text: String): _begin_run(seed_text),
		"on_upgrades": func(): _show_armory(ArmoryUI.Mode.UPGRADES),
		"on_armory": func(): _show_armory(ArmoryUI.Mode.ARMORY),
		"on_settings": _show_settings,
		"on_credits": _show_credits,
	})

func _show_credits() -> void:
	_close_current_screen()
	_current_screen = CreditsUI.show_credits($UI, _show_main_menu)

func _show_settings() -> void:
	_close_current_screen()
	_current_screen = SettingsUI.show_settings($UI, false, _show_main_menu)

func _show_armory(mode: ArmoryUI.Mode) -> void:
	_close_current_screen()
	_current_screen = ArmoryUI.show_armory($UI, mode, _show_main_menu)

## Ports Game.ts's startNewRun. Frees the PREVIOUS run's room nodes (see
## LevelFlow.start_new_run's own new cleanup block) and player instance
## before building fresh ones — the first-ever call has nothing to free
## (RunState.layouts starts empty, `player` starts null), so this is safe
## to call exactly once (first boot's own eventual Play click) or
## repeatedly (Defeat's Try Again, or Play again after a prior run ended).
func _begin_run(seed_text: String) -> void:
	_close_current_screen()
	GameState.change_state(GameState.State.RUN_START)
	_run_ending = false
	if player != null and is_instance_valid(player):
		player.queue_free()
	run_seed = seed_text if seed_text != "" else (str(Time.get_unix_time_from_system()) + ":" + str(randi()))
	MetaProgression.last_seed = run_seed
	MusicEngine.set_mood(0)
	player = PLAYER_SCENE.instantiate()
	# Permanent-upgrade modifiers are baked into base_stats BEFORE this
	# node enters the tree, so _ready()'s own recompute_stats() (which
	# reads base_stats) picks them up on its first pass rather than
	# needing a second manual recompute after add_child().
	player.base_stats = StatBlock.fresh().apply_modifiers(MetaProgression.get_permanent_stat_modifiers())
	player.unlocked_weapons.append_array(MetaProgression.get_unlocked_weapon_ids())
	player.unlocked_abilities.append_array(MetaProgression.get_unlocked_ability_ids())
	add_child(player)
	hud.visible = true
	LevelFlow.start_new_run(run_seed, player, self)

	# Ports Game.ts's own startNewRun gate exactly (`weapons.length > 1 ||
	# abilities.length > 1`): only ask when there's an actual choice,
	# otherwise begin immediately with the single starting kit.
	if player.unlocked_weapons.size() > 1 or player.unlocked_abilities.size() > 1:
		_current_screen = LoadoutSelectUI.show_loadout($UI, player.unlocked_weapons, player.unlocked_abilities, _confirm_loadout)
	else:
		_confirm_loadout(player.unlocked_weapons[0], player.unlocked_abilities[0])

func _confirm_loadout(weapon_id: String, ability_id: String) -> void:
	player.weapon_id = weapon_id
	player.ability_id = ability_id
	_close_current_screen()
	GameState.change_state(GameState.State.EXPLORATION)
	MusicEngine.set_intensity(0)

## Ports Game.ts's endRun: banks Soul Ash via the same formula
## (kills*0.6 + eliteKills*4 + (victory?70:0) + embers*0.08), records the
## lifetime stats, then hands off to the matching end screen.
func _end_run(victory: bool) -> void:
	if _run_ending:
		return
	_run_ending = true
	var formula_ash: int = floori(RunState.kills * 0.6 + RunState.elite_kills * 4.0 + (70.0 if victory else 0.0) + RunState.embers * 0.08)
	RunState.soul_ash_earned += formula_ash
	MetaProgression.add_soul_ash(formula_ash)
	MetaProgression.record_run_end(RunState.kills, not victory, victory, RunState.elapsed_time, RunState.embers_collected)
	hud.visible = false
	GameState.change_state(GameState.State.VICTORY if victory else GameState.State.DEFEAT)
	MusicEngine.set_intensity(0)
	MusicEngine.set_mood(0)
	if victory:
		_current_screen = VictoryDefeatUI.show_victory($UI, RunState.soul_ash_earned, _show_main_menu)
	else:
		_current_screen = VictoryDefeatUI.show_defeat($UI, RunState.soul_ash_earned, func(): _begin_run(""), _show_main_menu)

## Ports Game.ts's own pauseGame() guard exactly: only while a run is
## actually live (EXPLORATION/COMBAT/BOSS) AND nothing else is already
## modal — get_tree().paused doubles as that second check, since every
## existing modal here (Shop/Event/Inventory/UpgradeSelectUI) already sets
## it themselves. Split out from the Escape-key handler in _process() so
## it's callable directly (real Escape-key-state simulation isn't
## reliable to script under Xvfb; this is what real testing calls instead).
func _try_open_pause() -> void:
	if not GameState.is_in([GameState.State.EXPLORATION, GameState.State.COMBAT, GameState.State.BOSS]) or get_tree().paused:
		return
	AudioEngine.play_sfx("uiClick")
	GameState.push_state(GameState.State.PAUSED)
	var on_resume := func(): GameState.pop_state()
	var on_open_inventory := func():
		GameState.pop_state()
		LevelFlow.open_inventory_ui()
	var on_abandon := func():
		GameState.pop_state()
		_end_run(false)
	PauseMenuUI.show_pause($UI, {
		"on_resume": on_resume,
		"on_open_inventory": on_open_inventory,
		"on_abandon": on_abandon,
	})

func _try_open_admin_menu() -> void:
	if RunState.layouts.is_empty() or get_tree().paused:
		return
	AdminMenuUI.show_menu($UI, _admin_teleport_to_room)

## AdminMenuUI's own on_teleport callback — the UI screen only ever picks a
## (room, zone_index) pair from data RunState.layouts already has; this is
## where that choice actually mutates game state, same "UI calls back into
## main.gd" split as _begin_run()/_confirm_loadout() already use.
##
## Points RunState.zone_index/current_room_key at the target BEFORE calling
## LevelFlow.enter_room() — enter_room()'s own non-boss branch reads
## RunState.current_layout() to populate content, so those need to already
## agree with the room being entered. from_dir is passed null rather than
## a real Direction: enter_room() only uses it to place the player at
## room.spawn_point_from(opposite(from_dir)), which makes sense for a real
## door-crossing and not for a teleport, so positioning is done here
## instead, after enter_room() has already spawned the room's real content
## (including the one-time boss-spawn branch a hand-rolled populate-only
## call would skip entirely).
func _admin_teleport_to_room(room: RoomContainer, zone_index: int) -> void:
	if not is_instance_valid(room) or not is_instance_valid(player):
		return
	var rooms: Dictionary = RunState.layouts[zone_index]["rooms"]
	var room_key = rooms.find_key(room)
	if room_key == null:
		return
	RunState.zone_index = zone_index
	RunState.current_room_key = room_key
	LevelFlow.enter_room(room, null)
	var target_pos: Vector2 = room.global_position + Vector2(RoomContainer.ROOM_WIDTH / 2.0, RoomContainer.ROOM_HEIGHT / 2.0)
	for o in room.obstacles:
		if o.visual in [ObstacleNode.Visual.MERCHANT_STALL, ObstacleNode.Visual.SHRINE, ObstacleNode.Visual.BRAZIER, ObstacleNode.Visual.SARCOPHAGUS]:
			target_pos = o.global_position + Vector2(0.0, 90.0)
			break
	player.global_position = target_pos
	player.camera.reset_smoothing()

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

	if Input.is_physical_key_pressed(KEY_F2):
		if not _f2_key_down:
			_f2_key_down = true
			_try_open_admin_menu()
	else:
		_f2_key_down = false

	# Ports Game.ts's own pause input handling — polls the physical key
	# directly (no project.godot input-map action needed), same convention
	# as F1 above. This whole block simply stops running once paused (this
	# node's own default PROCESS_MODE_PAUSABLE), so there's no need to
	# separately guard against Escape re-opening Pause while Pause's own
	# already-ALWAYS-mode UI is up.
	if Input.is_physical_key_pressed(KEY_ESCAPE):
		if not _escape_key_down:
			_escape_key_down = true
			_try_open_pause()
	else:
		_escape_key_down = false

	var w := player.weapon()
	var a := player.ability()
	var room := RunState.current_room()
	var interaction = LevelFlow.get_interaction()

	hud.update({
		"player": player,
		"embers": RunState.embers,
		"zone_name": I18n.tc(room.zone.id, "name", room.zone.name) if room != null and room.zone != null else "?",
		"room_label": HudLayer.room_type_label(room.type) if room != null else "?",
		"corruption": RunState.corruption_ratio(),
		"weapon_name": I18n.tc(player.weapon_id, "name", w.name) if w != null else "?",
		"ability_name": I18n.tc(player.ability_id, "name", a.name) if a != null else "?",
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
				"name": I18n.tc(boss.def.id, "name", boss.def.name) if boss.def != null else "?",
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
		"EMBERFALL: LAST LIGHT — Godot scaffold (build-order step 12 of 12)",
		"WASD move, mouse aim, LMB attack, Space dodge, RMB ability, E interact, F1 debug overlay",
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
