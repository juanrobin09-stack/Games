extends Node
## Autoload: LevelFlow
##
## Ports the room/zone navigation half of core/Game.ts: enterRoom,
## checkDoorCrossing, getRoomInteraction, the scripted stairs transition
## (begin/completeDescent/Ascent), the sanctum rite, chest/rest
## interactions, and room-clear detection. Combat itself (damage, AI,
## status effects) already lives in CombatManager/EnemyAI/each entity's own
## _physics_process (build-order steps 4-5) — this is everything about
## WHERE the player is and how they get somewhere else, wired in as its own
## autoload with its own _physics_process rather than something player.gd
## reaches into, since door-crossing/room-clear are environment concerns no
## single entity owns.
##
## Reward-granting (the 3-choice upgrade pick on room clear, a chest's
## single upgrade) needs the upgrade-ownership system, which doesn't exist
## yet (real UI, build-order step 9). Every reward BEAT still plays out
## exactly as it should (stairs open, chest opens, the rite heals and pays
## out embers) — only the actual upgrade choice is missing, and a print()
## stands in for it so the gap is visible, not silent.

signal room_changed(room: RoomContainer)

const BOSS_SCENE := preload("res://entities/boss.tscn")
const PICKUP_SCENE := preload("res://world/pickup_node.tscn")

const DESCENT_OUT_SECONDS := 1.15
const DESCENT_IN_SECONDS := 1.35

## Ports data/playerProgression.ts's getEnemyXpValue formula.
const XP_PER_WEIGHT := 5.0
const XP_ZONE_BONUS_PER_INDEX := 0.25

## The Canvas2D "darken the whole frame, then re-brighten with additive
## lights" hack (LightingSystem.ts) has no per-shape equivalent in Godot —
## CanvasModulate is the engine-native way to tint everything under it at
## once, so this ports the *mood* (a dark scene PointLight2D sources punch
## back through) rather than the exact compositing technique. See
## _update_ambient() for how zone.darkness maps onto its color.
var _ambient: CanvasModulate = null
## LightingSystem.ts's per-frame `lighting.add(tr.stairs.x, tr.stairs.y, ...)`
## during a stairs transition — the one light in registerLights() that isn't
## owned by a persistent entity node, so LevelFlow (which already owns the
## whole transition state machine) owns this one PointLight2D directly
## instead, reusing it across every future transition rather than
## creating/freeing one each time.
var _transition_light: PointLight2D = null

var player: PlayerCharacter = null
## Set by main.gd before start_new_run() — the screen-space CanvasLayer
## every modal/popup (UpgradeSelectUI, RewardPopup, and step 9's still-
## coming ShopUI/EventUI) parents itself under, mirrors Game.ts's own
## uiRoot field. Deliberately NOT the same `parent` start_new_run() takes
## (that one's the world-space Node2D rooms/entities live under) — a
## Control parented under a Node2D like a room would render in WORLD
## space, following the camera, instead of as a screen overlay.
var ui_root: Node = null
var _active_room: RoomContainer = null
var _transition: Dictionary = {}
var _interact_key_down: bool = false

func _ready() -> void:
	CombatManager.enemy_died.connect(_on_enemy_died)
	RunState.player_leveled_up.connect(_on_player_leveled_up)

## Ports Game.ts's grantKillXp: "if (levelsGained > 0) { ...
## spawnLevelUpBurst(...) }" — RunState.grant_xp() (called from
## _on_enemy_died below) already resolves every level a single XP grant
## crosses in one synchronous loop and fires this signal once at the end,
## so one burst per grant here matches the source exactly regardless of
## how many levels it actually crossed.
func _on_player_leveled_up(_new_level: int, _stat_points_awarded: int) -> void:
	if player != null and is_instance_valid(player):
		var parent := player.get_parent()
		if parent != null:
			VfxPresets.level_up_burst(parent, player.global_position)

func _physics_process(delta: float) -> void:
	# RunState.elapsed_time backs both corruption_ratio() and the HUD timer,
	# but nothing ever incremented it before now — corruption_ratio() has
	# been silently returning 0 for the whole run since build-order step 6
	# wired it in. A real, if minor, pre-existing gap, not something this
	# pass introduced; fixed here since the HUD timer needed it wired
	# anyway. Ticks through a stairs transition too (a monotonic run clock,
	# not gameplay-time — matches elapsedSeconds()'s own semantics).
	RunState.elapsed_time += delta
	if not _transition.is_empty():
		_update_transition(delta)
		return
	if player == null or not is_instance_valid(player):
		return
	_check_door_crossing()
	_check_interact_key()
	_update_room_clear(delta)

# ---------------------------------------------------------------- Run bootstrap

## Generates all 3 zones' layouts up front (mirrors RunState.ts's own
## constructor — every zone exists from minute one, so retreating into an
## earlier zone is never a special case) and places the player in zone 0's
## start room, bare of any scattered content — mirrors Game.ts's
## startNewRun marking that one room spawnedContent=true directly instead
## of routing it through populate_room_content like every other room.
func start_new_run(seed_string: String, p_player: PlayerCharacter, parent: Node) -> void:
	RunState.reset_for_new_run(seed_string)
	player = p_player
	_transition.clear()
	_active_room = null

	# Recreated only if missing/freed (a fresh scene tree on a brand-new
	# run) — reused across zone/room changes otherwise, same as every
	# per-entity Glow light is reused rather than rebuilt every frame.
	if _ambient == null or not is_instance_valid(_ambient):
		_ambient = CanvasModulate.new()
		_ambient.name = "AmbientDarkness"
		parent.add_child(_ambient)
	if _transition_light == null or not is_instance_valid(_transition_light):
		_transition_light = PointLight2D.new()
		_transition_light.name = "TransitionGlow"
		_transition_light.texture = DrawUtils.glow_texture()
		_transition_light.enabled = false
		add_child(_transition_light)

	for zone_def in _sorted_zones():
		var rng := LevelGenerator.rng_from("%s:zonegen:%s" % [seed_string, zone_def.id])
		RunState.layouts[zone_def.index] = LevelGenerator.generate_zone_layout(zone_def, rng, parent)

	var start_layout: Dictionary = RunState.layouts[0]
	RunState.current_room_key = start_layout["start_key"]
	var start_room: RoomContainer = (start_layout["rooms"] as Dictionary)[start_layout["start_key"]]
	start_room.visited = true
	start_room.spawned_content = true
	player.global_position = Vector2(RoomContainer.ROOM_WIDTH / 2.0, RoomContainer.ROOM_HEIGHT / 2.0)
	_sync_active_room(start_room)
	room_changed.emit(start_room)

func _sorted_zones() -> Array:
	var zones: Array = DataRegistry.all("zones").duplicate()
	zones.sort_custom(func(a, b): return a.index < b.index)
	return zones

func _spawn_options() -> Dictionary:
	return {
		"unlocked_enemy_ids": MetaProgression.unlocks,
		"corruption_ratio": RunState.corruption_ratio(),
		"rarity_luck": player.stats.rarity_luck if player != null else 0.0,
		"run_seed": RunState.seed_value,
	}

## Mirrors Game.ts's private currentGateIds(): every id that can satisfy an
## UpgradeDefinition's own requires_unlock gate — permanent Soul Ash
## unlocks, every weapon the player has ever picked up this run, plus a
## "zone1"/"zone2" id once the run has reached that depth. Used set-like
## (id -> true), same convention as MetaProgression.unlocks itself.
func current_gate_ids() -> Dictionary:
	var ids: Dictionary = {}
	for id in MetaProgression.get_unlocked_gate_ids():
		ids[id] = true
	for id in player.unlocked_weapons:
		ids[id] = true
	if RunState.zone_index >= 1:
		ids["zone1"] = true
	if RunState.zone_index >= 2:
		ids["zone2"] = true
	return ids

# ---------------------------------------------------------------- Room flow

## Only ever the room the player is actually standing in is visible or
## simulating (see RoomContainer.set_active's own header). Tracked here
## rather than derived from RunState.current_room_key, since by the time
## enter_room() runs, whichever RunState call got us here (move_through_door/
## advance_zone/retreat_zone) has already pointed that key at the NEW room.
func _sync_active_room(new_room: RoomContainer) -> void:
	if _active_room != null and _active_room != new_room and is_instance_valid(_active_room):
		_active_room.set_active(false)
	new_room.set_active(true)
	_active_room = new_room
	_update_ambient(new_room)

## Ports Game.ts's registerLights(): "this.lighting.ambientDarkness =
## zone.darkness ?? 0.4" — recomputed there every single frame, but the
## value only actually changes when the active room's zone changes, so
## driving it from _sync_active_room (called on every room AND zone change)
## reaches the same result without a redundant per-frame write. CanvasModulate
## multiplies the whole scene's colors, unlike the source's darken-then-
## additive-gradient overlay, so this maps darkness onto a multiply tint
## toward the source's own overlay color (rgba(4, 3, 8, ...)) rather than
## reproducing that exact compositing — the PointLight2D sources placed
## everywhere else are what actually punch back through it.
func _update_ambient(room: RoomContainer) -> void:
	if _ambient == null:
		return
	var darkness: float = room.zone.darkness if room.zone != null else 0.4
	var dark_tint := Color(4.0 / 255.0, 3.0 / 255.0, 8.0 / 255.0)
	_ambient.color = Color(1.0, 1.0, 1.0).lerp(dark_tint, darkness)

func enter_room(room: RoomContainer, from_dir) -> void:
	room.visited = true

	if room.type == RoomContainer.Type.BOSS:
		if not room.spawned_content:
			room.spawned_content = true
			var factors: Dictionary = CombatManager.difficulty_factors(2, RunState.corruption_ratio())
			var boss_def: EnemyDefinition = DataRegistry.get_enemy("ashenColossus")
			if boss_def != null:
				var boss: BossCharacter = BOSS_SCENE.instantiate()
				room.add_enemy(boss)
				boss.setup(boss_def, Vector2(RoomContainer.ROOM_WIDTH / 2.0, RoomContainer.ROOM_HEIGHT * 0.32), factors["hp_mult"], factors["damage_mult"])
	elif not room.spawned_content:
		LevelGenerator.populate_room_content(room, RunState.current_layout()["zone"], _spawn_options())

	if from_dir != null:
		player.global_position = room.spawn_point_from(RoomContainer.OPPOSITE[from_dir])

	# Coming back into an already-cleared heart room: the stairwell stays open.
	if room.type == RoomContainer.Type.HEART and room.cleared:
		open_stairs(room, false)

	_sync_active_room(room)
	room_changed.emit(room)

func _check_door_crossing() -> void:
	var room := RunState.current_room()
	if room == null or room.is_locked():
		return
	var p := player.global_position
	var dir: int = -1
	if p.y < -2.0 and room.has_door(RoomContainer.Direction.N):
		dir = RoomContainer.Direction.N
	elif p.y > RoomContainer.ROOM_HEIGHT + 2.0 and room.has_door(RoomContainer.Direction.S):
		dir = RoomContainer.Direction.S
	elif p.x < -2.0 and room.has_door(RoomContainer.Direction.W):
		dir = RoomContainer.Direction.W
	elif p.x > RoomContainer.ROOM_WIDTH + 2.0 and room.has_door(RoomContainer.Direction.E):
		dir = RoomContainer.Direction.E
	if dir == -1:
		return
	var neighbor := RunState.move_through_door(dir)
	if neighbor != null:
		enter_room(neighbor, dir)
	else:
		# Shouldn't happen (has_door(dir) implies a neighbor was generated
		# there) — clamp rather than let the player wander into the void.
		player.global_position.x = clampf(player.global_position.x, -40.0, RoomContainer.ROOM_WIDTH + 40.0)
		player.global_position.y = clampf(player.global_position.y, -40.0, RoomContainer.ROOM_HEIGHT + 40.0)

func _find_obstacle(room: RoomContainer, visual: ObstacleNode.Visual) -> ObstacleNode:
	for o in room.obstacles:
		if o.visual == visual:
			return o
	return null

# ---------------------------------------------------------------- Interaction

## Returns {"label": String, "action": Callable} for whatever's in range to
## interact with, or null. Mirrors Game.ts's getRoomInteraction.
func get_interaction() -> Variant:
	if not _transition.is_empty() or player == null:
		return null
	var room := RunState.current_room()
	if room == null:
		return null
	var p := player.global_position
	var center := Vector2(RoomContainer.ROOM_WIDTH / 2.0, RoomContainer.ROOM_HEIGHT / 2.0)
	var center_dist: float = p.distance_to(center)

	if room.type == RoomContainer.Type.CHEST and room.chest != null and room.chest.can_interact():
		if p.distance_to(room.chest.position) < 75.0:
			return {"label": "Open Chest", "action": func(): open_chest(room)}
	if room.type == RoomContainer.Type.SHOP:
		var stall := _find_obstacle(room, ObstacleNode.Visual.MERCHANT_STALL)
		if stall != null and p.distance_to(stall.position) < 110.0:
			return {"label": "Browse Wares", "action": func(): open_shop_room(room)}
	if room.type == RoomContainer.Type.EVENT and not room.event_resolved:
		var shrine := _find_obstacle(room, ObstacleNode.Visual.SHRINE)
		if shrine != null and p.distance_to(shrine.position) < 110.0:
			return {"label": "Investigate", "action": func(): open_event_room(room)}
	if room.type == RoomContainer.Type.REST and not room.rest_used:
		var brazier := _find_obstacle(room, ObstacleNode.Visual.BRAZIER)
		if brazier != null and p.distance_to(brazier.position) < 110.0:
			return {"label": "Rest at the Brazier", "action": func(): use_rest(room)}
	if room.type == RoomContainer.Type.SANCTUM and not room.ritual_active and not room.cleared:
		if center_dist < LevelGenerator.SANCTUM_RING_RADIUS * 0.65:
			return {"label": "Kneel at the Circle", "action": func(): begin_rite(room)}
	if room.type == RoomContainer.Type.START and RunState.zone_index > 0:
		var stairs_up := _find_obstacle(room, ObstacleNode.Visual.STAIRS_UP)
		if stairs_up != null and p.distance_to(stairs_up.position) < stairs_up.radius + 72.0:
			return {"label": "Ascend", "action": func(): begin_ascent(stairs_up)}
	if room.type == RoomContainer.Type.HEART and room.cleared and not RunState.is_final_zone():
		var stairs_down := _find_obstacle(room, ObstacleNode.Visual.STAIRS_DOWN)
		if stairs_down != null and stairs_down.activated and p.distance_to(stairs_down.position) < stairs_down.radius + 72.0:
			return {"label": "Descend", "action": func(): begin_descent(stairs_down)}
	return null

func _check_interact_key() -> void:
	if not Input.is_physical_key_pressed(KEY_E):
		_interact_key_down = false
		return
	if _interact_key_down:
		return
	_interact_key_down = true
	var interaction = get_interaction()
	if interaction != null:
		(interaction["action"] as Callable).call()

# ---------------------------------------------------------------- Room clearing

func _update_room_clear(delta: float) -> void:
	var room := RunState.current_room()
	if room == null:
		return
	if room.type == RoomContainer.Type.SANCTUM:
		_update_rite(room, delta)
	elif room.type != RoomContainer.Type.BOSS and room.requires_clearing() and not room.reward_granted:
		room.check_cleared()
		if room.cleared:
			_grant_room_clear_reward(room)

## Ports Game.ts's private grantRoomClearReward. An elite den cleared in
## Zone 2 (zone_index 2, the Ember Citadel) hands the Bow over directly, on
## top of (not instead of) the room's normal upgrade-choice reward below —
## the dungeon's one guaranteed ranged-weapon unlock. A heart room's stairs
## only unseal once a reward exists AND is resolved: immediately if no
## upgrade could be rolled at all, otherwise only after the player actually
## picks one — matches the source's own two separate openStairs call sites
## exactly (not a single unconditional one).
func _grant_room_clear_reward(room: RoomContainer) -> void:
	if room.reward_granted:
		return
	room.reward_granted = true

	if room.type == RoomContainer.Type.ELITE and RunState.zone_index == 2 and not player.unlocked_weapons.has("bow"):
		player.unlocked_weapons.append("bow")
		player.weapon_id = "bow"
		VfxPresets.level_up_burst(room, player.global_position)
		print("LevelFlow: elite den cleared in the Ember Citadel — the Warden's Bow is yours")

	var bonus_luck: float = 0.0
	if room.type == RoomContainer.Type.ELITE or room.type == RoomContainer.Type.HEART:
		bonus_luck = 0.15
	elif room.type == RoomContainer.Type.SANCTUM:
		bonus_luck = 0.3
	var min_rarity: UpgradeDefinition.Rarity = UpgradeDefinition.Rarity.RARE if room.type == RoomContainer.Type.SANCTUM else UpgradeDefinition.Rarity.COMMON
	var luck: float = clampf(player.stats.rarity_luck + bonus_luck, 0.0, 1.0)
	var rng := LevelGenerator.rng_from("%s:reward:%s" % [RunState.seed_value, room.key])
	var choices: Array[UpgradeDefinition] = UpgradePool.roll_upgrade_choices(rng, 3, luck, current_gate_ids(), player.upgrades, RunState.zone_index, min_rarity)
	if choices.is_empty():
		if room.type == RoomContainer.Type.HEART:
			open_stairs(room, true)
		return

	var levels: Array[int] = []
	for c in choices:
		levels.append(UpgradePool.upcoming_upgrade_level(c.id, player.upgrades))
	UpgradeSelectUI.show_choices(ui_root, choices, levels, func(def: UpgradeDefinition):
		_grant_upgrade(def)
		VfxPresets.level_up_burst(room, player.global_position)
		if room.type == RoomContainer.Type.HEART:
			open_stairs(room, true)
	)

# ---------------------------------------------------------------- Stairs & descent

## Ports Game.ts's openStairs: "if (!stairs || stairs.activated) return;
## ... if (!animate) return; ... spawnStoneChips(...); for (i<10)
## spawnSporeMote(...)" — the animate=false path (re-entering an
## already-open heart room) skips the VFX entirely, same as the source.
## ObstacleNode.activate() already no-ops internally on a second call, but
## checking `stairs.activated` here too (rather than relying on that alone)
## is what actually gates the VFX to the true first activation only.
func open_stairs(room: RoomContainer, animate: bool) -> void:
	var stairs := _find_obstacle(room, ObstacleNode.Visual.STAIRS_DOWN)
	if stairs == null or stairs.activated:
		return
	stairs.activate()
	if not animate:
		return
	VfxPresets.stone_chips(room, stairs.global_position, 14)
	for i in range(10):
		var jitter := Vector2(randf_range(-30.0, 30.0), randf_range(-20.0, 20.0))
		VfxPresets.spore_mote(room, stairs.global_position + jitter)

func begin_descent(stairs: ObstacleNode) -> void:
	if not _transition.is_empty():
		return
	_start_transition("descend", stairs, player.global_position, LevelGenerator.stairs_mouth_position(stairs))

## Mirrors begin_descent: walks the player INTO a zone's arrival stairwell
## (stairsUp) to retreat to zoneIndex-1. Only ever offered where a
## stairsUp obstacle exists, i.e. zoneIndex > 0 (see place_stairs_up).
func begin_ascent(stairs: ObstacleNode) -> void:
	if not _transition.is_empty():
		return
	_start_transition("ascend", stairs, player.global_position, LevelGenerator.stairs_mouth_position(stairs))

func _start_transition(kind: String, stairs: ObstacleNode, from: Vector2, to: Vector2) -> void:
	_transition = {
		"phase": "out", "kind": kind, "t": 0.0, "duration": DESCENT_OUT_SECONDS,
		"from": from, "to": to, "stairs": stairs, "spore_timer": 0.0,
	}
	player.is_transitioning = true
	player.velocity = Vector2.ZERO
	if _transition_light != null:
		_transition_light.enabled = true

func _ease_in_out_sine(t: float) -> float:
	return -(cos(PI * t) - 1.0) / 2.0

func _ease_out_cubic(t: float) -> float:
	var p := t - 1.0
	return p * p * p + 1.0

func _update_transition(delta: float) -> void:
	_transition["t"] = (_transition["t"] as float) + delta
	var k: float = clampf((_transition["t"] as float) / (_transition["duration"] as float), 0.0, 1.0)
	var out_phase: bool = _transition["phase"] == "out"
	var walk: float = _ease_in_out_sine(k) if out_phase else _ease_out_cubic(k)
	var from: Vector2 = _transition["from"]
	var to: Vector2 = _transition["to"]
	player.global_position = from.lerp(to, walk)
	if from.distance_squared_to(to) > 0.0001:
		player.facing = (to - from).angle()

	# Ports Game.ts's updateTransition: "tr.sporeTimer -= dt; if (<= 0) {
	# sporeTimer = phase==='out' ? 0.05 : 0.12; spawnSporeMote(...) }" — the
	# well breathes spore motes the whole time the player is walking through it.
	var stairs_for_motes: ObstacleNode = _transition.get("stairs")
	if stairs_for_motes != null and is_instance_valid(stairs_for_motes):
		_transition["spore_timer"] = (_transition["spore_timer"] as float) - delta
		if (_transition["spore_timer"] as float) <= 0.0:
			_transition["spore_timer"] = 0.05 if out_phase else 0.12
			var jitter := Vector2(randf_range(-35.0, 35.0), randf_range(-25.0, 25.0))
			VfxPresets.spore_mote(_active_room, stairs_for_motes.global_position + jitter)

	# Ports Game.ts's registerLights(): "lighting.add(tr.stairs.x,
	# tr.stairs.y, 170*strength + 40, phase==='out' ? fungal : ember3,
	# 0.4*strength)" — strength rises 0->1 walking into the well ('out') and
	# falls 1->0 walking off it on the other side ('in'), same shape as the
	# player's own walk progress k/1-k just above.
	var stairs: ObstacleNode = _transition.get("stairs")
	if _transition_light != null and stairs != null and is_instance_valid(stairs):
		var strength: float = k if out_phase else 1.0 - k
		_transition_light.global_position = stairs.global_position
		_transition_light.texture_scale = (170.0 * strength + 40.0) / 128.0
		_transition_light.color = Color(Palette.FUNGUS if out_phase else Palette.EMBER3)
		_transition_light.energy = 0.4 * strength

	if k >= 1.0:
		if out_phase:
			if _transition["kind"] == "ascend":
				_complete_ascent()
			else:
				_complete_descent()
		else:
			_transition.clear()
			player.is_transitioning = false
			if _transition_light != null:
				_transition_light.enabled = false

## The zone switch itself, at the bottom of the fade: new layout, player
## placed in the mouth of the arrival stairwell, then the 'in' half of the
## transition walks them off it.
func _complete_descent() -> void:
	var next_room: RoomContainer = RunState.advance_zone()
	var zone: ZoneDefinition = RunState.current_layout()["zone"]
	if not next_room.spawned_content:
		LevelGenerator.populate_room_content(next_room, zone, _spawn_options())
	var arrival := _find_obstacle(next_room, ObstacleNode.Visual.STAIRS_UP)
	_land_after_transition(next_room, arrival, "descend")

## Mirrors _complete_descent: lands the player back in the previous zone's
## heart/boss room, at the mouth of ITS stairsDown, then walks them out to
## its foot — the same physical stairwell, in reverse.
func _complete_ascent() -> void:
	var prev_room: RoomContainer = RunState.retreat_zone()
	var zone: ZoneDefinition = RunState.current_layout()["zone"]
	if not prev_room.spawned_content:
		LevelGenerator.populate_room_content(prev_room, zone, _spawn_options())
	var arrival := _find_obstacle(prev_room, ObstacleNode.Visual.STAIRS_DOWN)
	_land_after_transition(prev_room, arrival, "ascend")

func _land_after_transition(room: RoomContainer, arrival: ObstacleNode, kind: String) -> void:
	var fallback_mouth := Vector2(RoomContainer.ROOM_WIDTH / 2.0, RoomContainer.ROOM_HEIGHT / 2.0)
	var fallback_foot := Vector2(RoomContainer.ROOM_WIDTH / 2.0, RoomContainer.ROOM_HEIGHT / 2.0 + 40.0)
	var mouth: Vector2 = LevelGenerator.stairs_mouth_position(arrival) if arrival != null else fallback_mouth
	var foot: Vector2 = LevelGenerator.stairs_foot_position(arrival) if arrival != null else fallback_foot
	player.global_position = mouth
	_sync_active_room(room)
	_transition = {
		"phase": "in", "kind": kind, "t": 0.0, "duration": DESCENT_IN_SECONDS,
		"from": mouth, "to": foot, "stairs": arrival, "spore_timer": 0.0,
	}
	room_changed.emit(room)

# ---------------------------------------------------------------- Sanctum rite

func begin_rite(room: RoomContainer) -> void:
	if room.ritual_active or room.cleared:
		return
	room.ritual_active = true
	room.ritual_wave = 0
	room.ritual_wave_timer = 1.1
	room.refresh_walls()

func _update_rite(room: RoomContainer, delta: float) -> void:
	if not room.ritual_active or room.cleared:
		return
	for e in room.enemies:
		if e.alive:
			return
	room.ritual_wave_timer -= delta
	if room.ritual_wave_timer > 0.0:
		return
	if room.ritual_wave >= LevelGenerator.SANCTUM_WAVE_COUNT:
		_complete_rite(room)
		return
	# Confirms the wave gate really did wait for a clear, not cascade — by
	# construction the loop above already found 0 alive among whatever was
	# in room.enemies up to this point (or this line wouldn't run at all),
	# but room.enemies never shrinks (dead enemies stay for their fade
	# animation), so its size alone looks alarming out of context — e.g. a
	# debug panel reading "enemies=14" after 3 waves (5+4+5) that each fully
	# died before the next spawned, not 14 live enemies at once.
	print("LevelFlow: sanctum wave %d/%d gate passed (0/%d previously-tracked enemies alive) — spawning next wave" % [
		room.ritual_wave + 1, LevelGenerator.SANCTUM_WAVE_COUNT, room.enemies.size()
	])
	var spawned: Array[EnemyCharacter] = LevelGenerator.spawn_sanctum_wave(room, RunState.current_layout()["zone"], room.ritual_wave, _spawn_options())
	for e in spawned:
		VfxPresets.spore_burst_vfx(room, e.global_position, 26.0)
	room.ritual_wave += 1
	room.ritual_wave_timer = 1.6
	# Ports Game.ts's updateRite: two more candles catch per wave survived
	# (indices (wave-1)*2 and (wave-1)*2+1, using the just-incremented wave).
	for idx in [(room.ritual_wave - 1) * 2, (room.ritual_wave - 1) * 2 + 1]:
		if idx >= LevelGenerator.SANCTUM_CANDLE_COUNT:
			continue
		VfxPresets.ritual_ignite(room, LevelGenerator.sanctum_candle_position(idx))

func _complete_rite(room: RoomContainer) -> void:
	room.cleared = true
	room.ritual_active = false
	room.refresh_walls()
	for i in range(LevelGenerator.SANCTUM_CANDLE_COUNT):
		VfxPresets.ritual_ignite(room, LevelGenerator.sanctum_candle_position(i))
	player.heal(player.stats.max_hp * 0.3)
	VfxPresets.heal_sparkle(room, player.global_position)
	RunState.embers += 35
	print("LevelFlow: sanctum rite complete at %s — 35 embers + 30%% heal granted" % room.key)
	_grant_room_clear_reward(room)

# ---------------------------------------------------------------- Upgrade rewards

## Single funnel for granting an upgrade to the player so newly-formed
## synergies are always announced, wherever the upgrade came from. Mirrors
## Game.ts's private grantUpgrade — the HUD synergy banner it stages via
## setTimeout (staggered 900ms apart, for when several form from one grant)
## doesn't exist yet, so a print stands in for each, same convention as
## every other reward-feedback gap this build documents until step 9's UI
## proper lands.
func _grant_upgrade(def: UpgradeDefinition) -> void:
	var new_synergies: Array[String] = player.add_upgrade(def)
	for syn_id in new_synergies:
		var syn: SynergyDefinition = DataRegistry.get_synergy(syn_id)
		if syn != null:
			print("LevelFlow: synergy formed -> %s (%s)" % [syn.name, syn.description])

# ---------------------------------------------------------------- Rest / Chest

func use_rest(room: RoomContainer) -> void:
	if room.rest_used:
		return
	room.rest_used = true
	room.cleared = true
	var heal_amount: float = (player.stats.max_hp - player.hp) * 0.55
	player.heal(heal_amount)
	VfxPresets.heal_sparkle(room, player.global_position)

## Ports Game.ts's private openChest: a chest grants exactly one upgrade, at
## or above its own tier — no player choice involved, unlike a room-clear
## reward or a shop offer, so (unlike those) this needed no new UI to wire
## for real. The RNG seed string matches the source exactly so the same run
## seed always rolls the same chest reward.
func open_chest(room: RoomContainer) -> void:
	var chest := room.chest
	if chest == null or not chest.can_interact():
		return
	chest.open()
	var rng := LevelGenerator.rng_from("%s:chestreward:%s" % [RunState.seed_value, room.key])
	var def := UpgradePool.pick_upgrade_at_least_rarity(rng, chest.tier, current_gate_ids(), player.upgrades, RunState.zone_index)
	if def == null:
		return
	var level: int = UpgradePool.upcoming_upgrade_level(def.id, player.upgrades)
	_grant_upgrade(def)
	RewardPopup.show_reward(ui_root, def, "Chest Reward", level)

## Ports Game.ts's private openShopRoom. reroll_count is boxed in a 1-
## element Array, not a plain int — GDScript lambdas capture locals BY
## VALUE at creation time (a plain int captured by make_offers/on_reroll
## would desync: on_reroll's `+= 1` would only ever mutate ITS OWN
## snapshot, so every reroll would reseed with the same count and hand
## back identical offers). An Array is captured by value too, but that
## value is a reference to the same underlying data — mutating its
## CONTENTS (reroll_count[0] += 1), never reassigning the variable itself,
## stays visible to every closure below that captured it.
func open_shop_room(room: RoomContainer) -> void:
	var reroll_count := [0]
	var make_offers := func() -> Array[ShopOffer]:
		return Shop.generate_shop_offers(
			Shop.make_shop_rng(RunState.seed_value, room.key, reroll_count[0]),
			player.stats.rarity_luck, current_gate_ids(), player.upgrades, RunState.zone_index)
	var on_buy_upgrade := func(offer: ShopOffer) -> bool:
		if offer.upgrade == null or offer.purchased or not RunState.spend_embers(offer.cost):
			return false
		_grant_upgrade(offer.upgrade)
		return true
	var on_buy_heal := func(offer: ShopOffer) -> bool:
		if offer.purchased or not RunState.spend_embers(offer.cost):
			return false
		player.heal(player.stats.max_hp * Shop.HEAL_AMOUNT_RATIO)
		VfxPresets.heal_sparkle(room, player.global_position)
		return true
	var on_reroll := func() -> Array[ShopOffer]:
		if not RunState.spend_embers(Shop.REROLL_COST):
			return []
		reroll_count[0] += 1
		return make_offers.call()
	ShopUI.show_shop(ui_root, make_offers.call(), on_buy_upgrade, on_buy_heal, on_reroll)

## Ports Game.ts's private openEvent. An event room keeps whichever id it
## first rolled (room.event_id) for the rest of the run — picked once,
## here, the first time it's opened — same as the source's own
## `if (!room.eventId)` guard. Zone-bound events (WorldEventDefinition's
## own zone_id) only ever appear in their own zone and are preferred there
## while unused, matching the source's own "the ruins should feel like
## they have their own stories" comment.
func open_event_room(room: RoomContainer) -> void:
	if room.event_resolved:
		return
	if room.event_id == "":
		var zone_id: String = (RunState.current_layout()["zone"] as ZoneDefinition).id
		var eligible: Array = []
		for e in DataRegistry.all("events"):
			if (e as WorldEventDefinition).zone_id == "" or (e as WorldEventDefinition).zone_id == zone_id:
				eligible.append(e)
		var available: Array = []
		for e in eligible:
			if not RunState.used_event_ids.has((e as WorldEventDefinition).id):
				available.append(e)
		var zone_own: Array = []
		for e in available:
			if (e as WorldEventDefinition).zone_id == zone_id:
				zone_own.append(e)
		if not zone_own.is_empty():
			available = zone_own
		if available.is_empty():
			available = eligible
		var rng := LevelGenerator.rng_from("%s:event:%s" % [RunState.seed_value, room.key])
		room.event_id = (available[rng.randi_range(0, available.size() - 1)] as WorldEventDefinition).id
	var def: WorldEventDefinition = DataRegistry.get_event(room.event_id)
	RunState.used_event_ids.append(def.id)
	EventUI.show_event(ui_root, def, func(option: EventOption):
		_apply_event_effect(option, room)
		room.event_resolved = true
		room.cleared = true
	)

## Ports Game.ts's private applyEventEffect. `option.cost`/`option.value`
## default to 0.0 the same way whether an EventOption's .tres explicitly
## writes 0 or omits the field entirely (Godot Resources have no separate
## "unset" state for a plain @export float) — so, same as the source's own
## `?? default` only ever meaningfully firing for a genuinely-absent value,
## every `> 0.0 else <default>` fallback below is the faithful reading:
## no shipped event option actually wants "grant exactly zero" as an
## effect, so the two cases were never distinguishable in practice either.
func _apply_event_effect(option: EventOption, room: RoomContainer) -> void:
	if option.cost > 0.0 and not RunState.spend_embers(int(option.cost)):
		return
	match option.apply:
		EventOption.EffectKind.NOTHING:
			pass
		EventOption.EffectKind.GAIN_EMBERS:
			RunState.embers += int(option.value)
		EventOption.EffectKind.GAIN_HP:
			player.heal(option.value)
			VfxPresets.heal_sparkle(room, player.global_position)
		EventOption.EffectKind.GAIN_RANDOM_UPGRADE:
			var min_rarity: UpgradeDefinition.Rarity = int(option.value)
			var rng := LevelGenerator.rng_from("%s:eventupgrade:%s:%s" % [RunState.seed_value, room.key, option.id])
			var def := UpgradePool.pick_upgrade_at_least_rarity(rng, min_rarity, current_gate_ids(), player.upgrades, RunState.zone_index)
			var level: int = UpgradePool.upcoming_upgrade_level(def.id, player.upgrades)
			_grant_upgrade(def)
			RewardPopup.show_reward(ui_root, def, "The Merchant", level)
		EventOption.EffectKind.LOSE_HP_FOR_RARE_UPGRADE:
			var loss: float = player.stats.max_hp * (option.value if option.value > 0.0 else 0.25)
			player.hp = maxf(1.0, player.hp - loss)
			var rng2 := LevelGenerator.rng_from("%s:eventupgrade:%s:%s" % [RunState.seed_value, room.key, option.id])
			var def2 := UpgradePool.pick_upgrade_at_least_rarity(rng2, UpgradeDefinition.Rarity.RARE, current_gate_ids(), player.upgrades, RunState.zone_index)
			var level2: int = UpgradePool.upcoming_upgrade_level(def2.id, player.upgrades)
			_grant_upgrade(def2)
			RewardPopup.show_reward(ui_root, def2, "The Dying Flame", level2)
		EventOption.EffectKind.GAMBLE_EMBERS:
			if randf() < 0.5:
				RunState.embers += RunState.embers
			else:
				var loss: int = int(floor(RunState.embers * 0.5))
				RunState.embers = maxi(0, RunState.embers - loss)
		EventOption.EffectKind.GAIN_SOUL_ASH_NOW:
			MetaProgression.add_soul_ash(int(option.value))
		EventOption.EffectKind.GAIN_SHIELD_CHARGE:
			player.shield_charges += int(option.value) if option.value > 0.0 else 1
		EventOption.EffectKind.GAIN_MAX_HP:
			var amount: float = option.value if option.value > 0.0 else 15.0
			var mod := StatModifier.new()
			mod.stat = "max_hp"
			mod.mode = StatModifier.Mode.FLAT
			mod.value = amount
			player.add_bonus_modifier(mod)
			player.heal(amount)
			VfxPresets.heal_sparkle(room, player.global_position)
		EventOption.EffectKind.LOSE_HP_FOR_EMBERS:
			player.hp = maxf(1.0, player.hp - player.stats.max_hp * 0.15)
			RunState.embers += int(option.value) if option.value > 0.0 else 50

# ---------------------------------------------------------------- Kill rewards

## Mirrors Game.ts's 'enemyKilled' handler: XP via the already-working
## RunState.grant_xp, and up to 5 Ember pickups scattered from the corpse.
func _on_enemy_died(enemy: Node) -> void:
	var e := enemy as EnemyCharacter
	if e == null or e.def == null:
		return
	var xp_gained: int = maxi(1, int(round(XP_PER_WEIGHT * e.def.xp_weight * (1.0 + RunState.zone_index * XP_ZONE_BONUS_PER_INDEX))))
	RunState.grant_xp(xp_gained)

	var room := e.get_parent() as RoomContainer
	if room == null:
		return
	# The only in-game (not Output-panel) feedback for a kill's XP until a
	# real HUD popup/toast system exists — RunState.grant_xp() above already
	# prints the same number, this just makes it visible without the console.
	FloatingText.spawn(room, e.global_position + Vector2(0.0, -20.0), "+%d XP" % xp_gained, Color(Palette.GOLD_BRIGHT))

	var ember_total: int = int(round(e.def.ember_value * (0.85 + randf() * 0.3)))
	if ember_total <= 0:
		return
	var count: int = clampi(int(round(ember_total / 3.0)), 1, 5)
	var per: int = maxi(1, int(round(float(ember_total) / count)))
	for i in range(count):
		var pickup: PickupNode = PICKUP_SCENE.instantiate()
		room.add_pickup(pickup)
		pickup.setup(PickupNode.Kind.EMBER, e.global_position, float(per))

# ---------------------------------------------------------------- Stat points

## Ports Game.ts's spendStatPoint — the real gate on spending a stat point;
## RunState.spend_stat_point stays pure bookkeeping (no lock check, exactly
## like the TS source keeps run.statPoints/statLevels as plain data) and
## this is the actual entry point UI should call once InventoryUI's
## Character tab exists. Looks up the stat def and checks the lock BEFORE
## touching RunState, so an unknown or locked stat_id never leaves a point
## spent with nothing applied.
func spend_stat_point(stat_id: String) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	var def := PlayerProgression.get_player_stat_def(stat_id)
	if def == null:
		return false
	if PlayerProgression.is_player_stat_locked(stat_id, player.unlocked_weapons.has("bow"), RunState.zone_index):
		return false
	if not RunState.spend_stat_point(stat_id):
		return false
	var mod := StatModifier.new()
	mod.stat = def.stat
	mod.mode = def.mode
	mod.value = def.value_per_level
	player.add_bonus_modifier(mod)
	return true
