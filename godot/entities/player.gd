class_name PlayerCharacter
extends CharacterBody2D
## Ports entities/Player.ts. Movement is applied through CharacterBody2D's
## own move_and_slide() — the Web build integrates position manually, then
## Game.ts resolves collision separately afterward; move_and_slide() folds
## both into one call, per GODOT_MIGRATION.md §2's own prescription.
##
## Input is read directly via raw Input.is_physical_key_pressed()/
## is_mouse_button_pressed() calls rather than a project.godot InputMap —
## a deliberate build-order-step-3 simplification to avoid hand-authoring
## the InputMap's more complex serialized format with no engine available
## to verify it against. Wiring real named actions later (via the editor,
## which generates that format correctly itself) is a safe, easy follow-up,
## not a redo — nothing here depends on the raw-key approach specifically.
##
## recomputeStats()/addUpgrade()/addBonusModifier()/synergies were deferred
## here until the upgrade-ownership system existed to drive them (see
## build-order step 9's own progression/ additions) — ported below, in the
## same cluster as take_damage()/heal().
##
## Body rendering itself moved off this file's own procedural _draw() and
## onto a real AnimatedSprite2D (see the IDLE_FRAMES/RUN_FRAMES/etc. consts
## and _update_sprite_animation() below) once real character art was
## supplied — _draw() now only draws what was never "the body" (shadow,
## weapon, invulnerability ring).

signal died
signal hp_changed(current: float, max: float)

const STAMINA_REGEN_DELAY := 0.55
const STAMINA_REGEN_RATE := 45.0
const DODGE_STAMINA_COST := 15.0
const BASE_ENERGY_REGEN := 6.0
const DODGE_DURATION := 0.22
const MOVE_ACCEL := 14.0

enum AnimState { IDLE, RUN, ATTACK, HIT, DEAD, DODGE, ABILITY }

## The real character art supplied via GitHub (a style sheet: portrait, 4
## turnaround views, and 5 six-frame animation cycles on a near-black
## background) replaces the old fully-procedural body/cape/head _draw()
## below it in this file. Cropped tight per frame and alpha-matted from
## that background (soft brightness ramp, not a hard cutoff, so the
## silhouette edge stays anti-aliased rather than jagged) — see the
## README's own entry for this change for the extraction methodology.
##
## Only 4 of the reference's 5 animation rows are used: "Marche" (walk)
## has no equivalent in AnimState (IDLE/RUN is a binary switch, no
## walk/run speed split) and was left unused rather than forcing a
## distinction the state machine doesn't make. "Saut" (jump) frames
## became the "dodge" animation instead — this is a top-down game with no
## vertical jump, and a leaping/rolling pose is the closest visual match
## to what a dodge roll actually is. HIT and DEAD have no frames of their
## own; both fall back to "idle" with a modulate tint (hit: a brief red
## flash; dead: fade + fall-over rotation) rather than freezing on a
## random mid-animation frame.
const IDLE_FRAMES: Array[Texture2D] = [
	preload("res://assets/textures/player_idle_0.png"),
	preload("res://assets/textures/player_idle_1.png"),
	preload("res://assets/textures/player_idle_2.png"),
	preload("res://assets/textures/player_idle_3.png"),
	preload("res://assets/textures/player_idle_4.png"),
	preload("res://assets/textures/player_idle_5.png"),
]
## The "idle" *animation* plays only this subset of IDLE_FRAMES, not all six —
## diagnosed directly from a real gameplay recording reported as "the leg
## disappears": idle_2 and idle_5 are genuine, correctly-extracted frames
## (verified pixel-complete, nothing missing or corrupted — see the README's
## own entry for this round), but the reference art draws them as a single
## foot stepping forward, narrowing the silhouette's own base from ~45px
## wide (every other idle frame) to ~20px. Looping all 6 at 6fps flashes
## that narrow pose for one frame out of six, twice a cycle, which reads as
## the leg popping in and out rather than as a weight shift — there's no
## seventh in-between frame this reference sheet provides to smooth it, so
## dropping the two outliers (not retiming or reordering them, which would
## still cut just as abruptly, only later) is what actually removes the
## effect rather than just spacing it out. IDLE_FRAMES itself stays all six,
## matching the source sheet 1:1, since some other frame or feature might
## want idle_2/5 later (a "shift weight" tell on a longer idle timer, say).
const IDLE_LOOP_FRAMES: Array[Texture2D] = [
	IDLE_FRAMES[0], IDLE_FRAMES[1], IDLE_FRAMES[3], IDLE_FRAMES[4],
]
const RUN_FRAMES: Array[Texture2D] = [
	preload("res://assets/textures/player_run_0.png"),
	preload("res://assets/textures/player_run_1.png"),
	preload("res://assets/textures/player_run_2.png"),
	preload("res://assets/textures/player_run_3.png"),
	preload("res://assets/textures/player_run_4.png"),
	preload("res://assets/textures/player_run_5.png"),
]
const ATTACK_FRAMES: Array[Texture2D] = [
	preload("res://assets/textures/player_attack_0.png"),
	preload("res://assets/textures/player_attack_1.png"),
	preload("res://assets/textures/player_attack_2.png"),
	preload("res://assets/textures/player_attack_3.png"),
	preload("res://assets/textures/player_attack_4.png"),
	preload("res://assets/textures/player_attack_5.png"),
]
const DODGE_FRAMES: Array[Texture2D] = [
	preload("res://assets/textures/player_dodge_0.png"),
	preload("res://assets/textures/player_dodge_1.png"),
	preload("res://assets/textures/player_dodge_2.png"),
	preload("res://assets/textures/player_dodge_3.png"),
	preload("res://assets/textures/player_dodge_4.png"),
	preload("res://assets/textures/player_dodge_5.png"),
]

## World-unit scale applied to every frame's own native pixel size (frames
## aren't pre-resized — this one constant is the single tuning knob for
## in-game size, cheaper to retune than re-exporting 24 images). Chosen so
## the idle silhouette (~88px tall natively) reads at ~53 units, a touch
## taller than the old procedural silhouette's ~40-50 units — real
## painted art needs a bit more presence to read as clearly at this
## camera zoom (1.5x, see player.tscn) as a thin vector outline did.
const SPRITE_SCALE := 0.6
## Shifts the sprite's draw origin up from this node's local (0,0) so the
## idle pose's feet land near the shadow (DrawUtils.draw_soft_shadow below
## is centered at local y=20) instead of the sprite's own bounding-box
## center sitting on it — AnimatedSprite2D has no per-frame pivot, so this
## is calibrated once against the idle row specifically; run/attack/dodge
## frames differ in height from idle by a few px each, which reads as
## normal animation weight-shift rather than misalignment.
const SPRITE_Y_OFFSET := -8.0

## Where the weapon's grip is pinned on the body (mirrored in x by
## _draw()'s own facing check, so it's always on the sprite's facing
## side), and how far weapon_angle may swing away from that facing
## direction before being clamped — see _draw()'s own weapon-drawing
## comment for why the clamp exists (it's the actual fix for the weapon
## crossing through the torso, not the hand position by itself). Chosen
## by rendering the idle silhouette and reading its rough edge/hip height
## off the screenshot, then adjusted once more after an initial render
## showed the grip sitting slightly outside the hand: not derived from
## exact pixel measurements the way e.g. the shop-stall collision ratios
## were, since this sprite has no equivalent alpha-channel "where exactly
## is the hand" landmark to measure against.
const HAND_OFFSET := Vector2(11.0, 5.0)
const WEAPON_ANGLE_CLAMP := deg_to_rad(70.0)

## Temporarily disabled while the character sprite itself is still being
## debugged (lower body / silhouette issues reported directly from real
## gameplay) — the weapon attachment is a separate, already-solved problem
## and re-verifying it against a still-changing character silhouette would
## waste effort twice over. Flip back to true once the character is signed
## off; nothing else about the weapon code below needs to change.
const DRAW_WEAPON := false

## Built once in _ready() from the const frame arrays above — programmatic
## rather than a hand-authored SpriteFrames .tres, matching this project's
## existing "build via code, not the editor" convention for anything this
## repetitive (see e.g. hud.gd/menu_ui_kit.gd building their whole node
## trees the same way).
static func _build_sprite_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var specs := [
		{"name": "idle", "textures": IDLE_LOOP_FRAMES, "fps": 6.0, "loop": true},
		{"name": "run", "textures": RUN_FRAMES, "fps": 12.0, "loop": true},
		{"name": "attack", "textures": ATTACK_FRAMES, "fps": 20.0, "loop": false},
		{"name": "dodge", "textures": DODGE_FRAMES, "fps": 27.0, "loop": false},
	]
	for spec in specs:
		var anim_name: String = spec["name"]
		frames.add_animation(anim_name)
		frames.set_animation_speed(anim_name, spec["fps"])
		frames.set_animation_loop(anim_name, spec["loop"])
		for tex in spec["textures"]:
			frames.add_frame(anim_name, tex)
	return frames

## The player's own unmodified stat floor (createBaseStats() in the TS
## source). recompute_stats() always re-derives `stats` from THIS, never
## from the previous `stats` — assign to `stats` directly nowhere else.
var base_stats: StatBlock = StatBlock.fresh()
var stats: StatBlock = StatBlock.fresh()
var upgrades: Array[OwnedUpgrade] = []
var active_synergies: Array[String] = []
## Run-scoped stat bonuses that aren't upgrades (stat-point spends via
## LevelFlow.spend_stat_point, world events like the Spore Mother once
## ported). Folded into every stat recompute alongside owned upgrades.
var bonus_modifiers: Array[StatModifier] = []
var weapon_id: String = "emberBlade"
var ability_id: String = "emberBurst"
var unlocked_weapons: Array[String] = ["emberBlade"]
var unlocked_abilities: Array[String] = ["emberBurst"]

var radius: float = 15.0
var hp: float = 100.0
var shield_charges: int = 0
var energy: float = 100.0
var stamina: float = 100.0
var stamina_regen_delay_timer: float = 0.0
var alive: bool = true
var death_timer: float = 0.0

var invuln_timer: float = 0.0
var hit_flash_timer: float = 0.0

## Set by LevelFlow during the scripted stairwell walk (build-order step 6):
## no input, no regen/status-effect ticking, position driven externally —
## mirrors Game.ts's updatePlaying short-circuiting entirely to
## updateTransition while a stairs transition is in progress.
var is_transitioning: bool = false

var attack_cooldown_timer: float = 0.0
var attack_anim_timer: float = 0.0
var is_attacking: bool = false
var attack_facing_lock: float = 0.0
var attack_swing_id: int = 0

var dodge_cooldown_timer: float = 0.0
var is_dodging: bool = false
var dodge_timer: float = 0.0
var dodge_dir := Vector2.ZERO
var last_dodge_end_time: float = -10.0

var is_channeling_ability: bool = false
var ability_anim_timer: float = 0.0

var anim_state: AnimState = AnimState.IDLE
var anim_time: float = 0.0

var move_input := Vector2.ZERO
var facing: float = 0.0
var run_time: float = 0.0
var perfect_dodge_timer: float = 0.0

## Ports Player.ts's wardingSigilActive — empty Dictionary means inactive,
## matching this codebase's own established convention for an "optional
## struct" field (LevelFlow._transition uses the identical empty-dict-is-
## absent shape). {"pos": Vector2, "timer": float, "duration": float}.
var warding_sigil_active: Dictionary = {}

## Ports Camera.ts's shake state — TS drives a fully manual camera
## (position/renderX/renderY it also uses for worldToScreen); this port
## uses a native Camera2D instead (GODOT_MIGRATION.md's own steer toward
## engine-native equivalents over a byte-exact manual port), so shake
## becomes a perturbation of that node's own `offset` property rather than
## a second coordinate system. The magnitude/duration/decay math itself —
## including the "a new shake only overrides a weaker, still-decaying one"
## rule — is still the exact same port.
var _shake_time: float = 0.0
var _shake_duration: float = 0.0
var _shake_magnitude: float = 0.0

## No status effect currently ever targets the player (only enemies can be
## burned/bled today) — present for symmetry so StatusEffectRuntime can
## treat Player and Enemy identically, not because anything applies one yet.
var status_effects: Array = []

@export var body_color: Color = Color("#e0c9a6")
@onready var camera: Camera2D = $Camera2D

var _sprite: AnimatedSprite2D
## Hysteresis for flip_h: only re-evaluated while the aim direction has a
## meaningful horizontal component, so aiming near-exactly up/down doesn't
## flicker the sprite between left/right on tiny mouse movements the way
## a bare `cos(facing) < 0.0` recomputed every frame would.
var _facing_left: bool = false

## Null-guarded and loud on failure (push_error, once per distinct missing
## id) rather than letting a bad/missing DataRegistry entry silently break
## every gating check that reads weapon()/ability() — diagnosed during
## step-3 testing where a broken lookup here made attack/ability appear
## to do nothing with no visible cause.
var _warned_missing_weapon: String = ""
var _warned_missing_ability: String = ""

func weapon() -> WeaponDefinition:
	var w: WeaponDefinition = DataRegistry.get_weapon(weapon_id)
	if w == null and _warned_missing_weapon != weapon_id:
		_warned_missing_weapon = weapon_id
		push_error("PlayerCharacter: weapon '%s' not found in DataRegistry (loaded: %d) — check resources/weapons/%s.tres exists and its `id` field matches" % [weapon_id, DataRegistry.counts().get("weapons", 0), weapon_id])
	return w

func ability() -> AbilityDefinition:
	var a: AbilityDefinition = DataRegistry.get_ability(ability_id)
	if a == null and _warned_missing_ability != ability_id:
		_warned_missing_ability = ability_id
		push_error("PlayerCharacter: ability '%s' not found in DataRegistry (loaded: %d) — check resources/abilities/%s.tres exists and its `id` field matches" % [ability_id, DataRegistry.counts().get("abilities", 0), ability_id])
	return a

func attack_cooldown_duration() -> float:
	var w := weapon()
	return w.attack_cooldown / stats.attack_speed_mult if w != null else 999.0

func dodge_cooldown_duration() -> float:
	return 0.95 * stats.dodge_cooldown_mult

func is_invulnerable() -> bool:
	return invuln_timer > 0.0 or is_dodging

func can_attack() -> bool:
	return alive and not is_dodging and attack_cooldown_timer <= 0.0 and has_enough_stamina()

## Split out from can_attack() so callers (HUD/input feedback) can tell a
## stamina-blocked swing apart from one that's merely still on cooldown.
func has_enough_stamina() -> bool:
	var w := weapon()
	return w != null and stamina >= w.stamina_cost

func can_dodge() -> bool:
	return alive and not is_dodging and dodge_cooldown_timer <= 0.0 and has_enough_stamina_for_dodge()

func has_enough_stamina_for_dodge() -> bool:
	return stamina >= DODGE_STAMINA_COST

func can_use_ability() -> bool:
	return alive and not is_dodging and energy >= stats.energy_max

func start_attack() -> void:
	var w := weapon()
	if w == null:
		return
	is_attacking = true
	attack_anim_timer = 0.0
	attack_facing_lock = facing
	attack_cooldown_timer = attack_cooldown_duration()
	attack_swing_id += 1
	anim_state = AnimState.ATTACK
	anim_time = 0.0
	stamina = maxf(0.0, stamina - w.stamina_cost)
	stamina_regen_delay_timer = STAMINA_REGEN_DELAY
	# The hit check (melee) or the shot(s) (ranged) fire once, instantly,
	# right as the swing starts — not delayed to when the swing animation
	# completes. Real Strategy dispatch (build-order step 5): which archetype
	# runs is entirely WeaponDefinition.kind's business, not this function's.
	var behavior := WeaponBehavior.for_kind(w.kind)
	if behavior != null:
		behavior.execute(self, w)

func start_dodge(dir: Vector2) -> void:
	is_dodging = true
	dodge_timer = 0.0
	dodge_dir = dir
	dodge_cooldown_timer = dodge_cooldown_duration()
	anim_state = AnimState.DODGE
	anim_time = 0.0
	stamina = maxf(0.0, stamina - DODGE_STAMINA_COST)
	stamina_regen_delay_timer = STAMINA_REGEN_DELAY

## Ports Game.ts's performAbility: startAbility() resets the resource/
## animation state, then the effect fires immediately (not delayed to
## whenever the cast animation finishes) — same "instant effect, cosmetic
## animation plays alongside it" shape as start_attack()'s own weapon-
## behavior dispatch just above.
func start_ability() -> void:
	energy = 0.0
	is_channeling_ability = true
	ability_anim_timer = 0.0
	anim_state = AnimState.ABILITY
	anim_time = 0.0
	match ability_id:
		"emberBurst":
			CombatManager.ember_burst_ability(self)
		"stormstep":
			CombatManager.perform_stormstep(self)
		"wardingSigil":
			warding_sigil_active = {"pos": global_position, "timer": 0.0, "duration": 5.0}
			AudioEngine.play_sfx("abilityWardingSigil")
	CombatManager.ability_cast.emit(self, ability_id)

## Returns {taken, blocked, shield_consumed} — mirrors Player.ts's return
## shape exactly (a Dictionary here, an object literal there).
func take_damage(amount: float) -> Dictionary:
	if is_invulnerable() or not alive:
		return {"taken": 0.0, "blocked": true, "shield_consumed": false}
	var dmg: float = amount * (1.0 - stats.armor)
	if shield_charges > 0:
		shield_charges -= 1
		invuln_timer = 0.4
		hit_flash_timer = 0.25
		return {"taken": 0.0, "blocked": true, "shield_consumed": true}
	dmg = maxf(1.0, dmg)
	hp -= dmg
	hit_flash_timer = 0.28
	invuln_timer = 0.55
	anim_state = AnimState.HIT
	anim_time = 0.0
	if hp <= 0.0:
		hp = 0.0
		alive = false
		anim_state = AnimState.DEAD
		anim_time = 0.0
		died.emit()
	hp_changed.emit(hp, stats.max_hp)
	return {"taken": dmg, "blocked": false, "shield_consumed": false}

func heal(amount: float) -> void:
	hp = clampf(hp + amount, 0.0, stats.max_hp)
	hp_changed.emit(hp, stats.max_hp)

## Ports Player.ts's private recomputeStats(): re-derives `stats` from
## base_stats plus every owned upgrade's modifiers (each repeated once per
## stack) and every bonus_modifier, then re-evaluates which synergies are
## active from the same upgrade list.
func recompute_stats() -> void:
	var all_modifiers: Array[StatModifier] = []
	for owned in upgrades:
		for i in range(owned.stacks):
			for mod in owned.def.modifiers:
				all_modifiers.append(mod)
	for mod in bonus_modifiers:
		all_modifiers.append(mod)
	stats = base_stats.apply_modifiers(all_modifiers)
	recompute_synergies()

## Grants a run-long stat bonus outside the upgrade system (stat-point
## spends, future world events) — keeps current HP/stamina proportional so a
## max-HP/stamina bonus never leaves the bar looking emptier.
func add_bonus_modifier(mod: StatModifier) -> void:
	var hp_ratio: float = hp / maxf(1.0, stats.max_hp)
	var stamina_ratio: float = stamina / maxf(1.0, stats.stamina_max)
	bonus_modifiers.append(mod)
	recompute_stats()
	hp = minf(stats.max_hp, maxf(hp, stats.max_hp * hp_ratio))
	stamina = minf(stats.stamina_max, maxf(stamina, stats.stamina_max * stamina_ratio))

## Ports Player.ts's private recomputeSynergies(): a SynergyDefinition
## activates once its `requires` tags are covered by owned upgrades — two
## distinct tags need one owned upgrade each, but synergy_definition.gd's
## own doc-comment documents the "wrath" synergy's deliberate exception (the
## same tag listed twice means "own 2 upgrades carrying that tag" instead).
func recompute_synergies() -> void:
	var tag_counts: Dictionary = {}
	for owned in upgrades:
		for tag in owned.def.tags:
			tag_counts[tag] = tag_counts.get(tag, 0) + owned.stacks
	active_synergies.clear()
	for syn in DataRegistry.all("synergies"):
		var synergy := syn as SynergyDefinition
		var a: String = synergy.requires[0]
		var b: String = synergy.requires[1]
		var count_a: int = tag_counts.get(a, 0)
		var count_b: int = tag_counts.get(b, 0)
		var active: bool = (count_a >= 2) if a == b else (count_a >= 1 and count_b >= 1)
		if active:
			active_synergies.append(synergy.id)

func has_synergy(id: String) -> bool:
	return active_synergies.has(id)

## Damage multiplier from the Wrath synergy: scales up to +50% as HP drops toward 0.
func wrath_multiplier() -> float:
	if not has_synergy("wrath"):
		return 1.0
	var missing_ratio: float = 1.0 - clampf(hp / maxf(1.0, stats.max_hp), 0.0, 1.0)
	return 1.0 + missing_ratio * 0.5

## Combined damage multiplier from all active synergy/state buffs (wrath,
## perfect dodge) — every weapon/ability damage formula multiplies by this,
## matching Player.ts's own synergyDamageMultiplier getter exactly.
func synergy_damage_multiplier() -> float:
	var mult: float = wrath_multiplier()
	if perfect_dodge_timer > 0.0:
		mult *= 1.35
	return mult

func trigger_perfect_dodge() -> void:
	if has_synergy("shadowDodge"):
		perfect_dodge_timer = 3.0

## Ports Camera.ts's addShake: a new shake only overrides a still-decaying
## one if it's stronger than what that one has decayed to by now — a weak
## shake can't cut a strong one short, but a strong one always wins.
## Gated on the screen_shake setting first — matches Game.ts's own
## `camera.shakeEnabled = s.screenShake` (checked at the call site there;
## checked in here instead, so every one of this port's ~15 call sites
## gets it for free rather than needing its own guard).
func add_camera_shake(magnitude: float, duration: float) -> void:
	if not MetaProgression.settings.get("screen_shake", true):
		return
	_shake_magnitude = maxf(_shake_magnitude * (1.0 - _shake_time / maxf(_shake_duration, 0.001)), magnitude)
	_shake_duration = duration
	_shake_time = 0.0

func _update_camera_shake(dt: float) -> void:
	if camera == null:
		return
	if _shake_time < _shake_duration:
		_shake_time += dt
		var t: float = 1.0 - _shake_time / _shake_duration
		var power: float = _shake_magnitude * maxf(t, 0.0)
		camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * power
	else:
		camera.offset = Vector2.ZERO

## Applies the upgrade (stacking it if already owned, up to its own
## max_stacks — 0 means uncapped here; the zone-based offer cap that
## actually gates what gets OFFERED lives in UpgradePool.is_upgrade_available,
## not here) and returns the ids of any synergy that just became active for
## the first time, so the caller (LevelFlow._grant_upgrade) knows what to
## announce.
func add_upgrade(def: UpgradeDefinition) -> Array[String]:
	var existing: OwnedUpgrade = null
	for owned in upgrades:
		if owned.def.id == def.id:
			existing = owned
			break
	if existing != null:
		if def.max_stacks == 0 or existing.stacks < def.max_stacks:
			existing.stacks += 1
	else:
		var new_owned := OwnedUpgrade.new()
		new_owned.def = def
		new_owned.stacks = 1
		upgrades.append(new_owned)
	var hp_ratio: float = hp / maxf(1.0, stats.max_hp)
	var stamina_ratio: float = stamina / maxf(1.0, stats.stamina_max)
	var before: Array[String] = active_synergies.duplicate()
	recompute_stats()
	hp = minf(stats.max_hp, maxf(hp, stats.max_hp * hp_ratio))
	stamina = minf(stats.stamina_max, maxf(stamina, stats.stamina_max * stamina_ratio))
	var newly_active: Array[String] = []
	for id in active_synergies:
		if not before.has(id):
			newly_active.append(id)
	return newly_active

func _ready() -> void:
	add_to_group("player")
	recompute_stats()
	hp = stats.max_hp
	energy = stats.energy_max
	stamina = stats.stamina_max
	var shape: CollisionShape2D = get_node_or_null("CollisionShape2D")
	if shape and shape.shape is CircleShape2D:
		(shape.shape as CircleShape2D).radius = radius
	# Ports Game.ts's registerLights(): "lighting.add(player.x, player.y, 260,
	# Palette.ember4, 1)" — constant for the run's whole lifetime, so this is
	# the only place it needs setting (unlike the enemy/obstacle lights that
	# change condition every frame).
	var glow: PointLight2D = $Glow
	glow.texture = DrawUtils.glow_texture()
	glow.texture_scale = 260.0 / 128.0
	glow.color = Color(Palette.EMBER4)
	glow.energy = 1.0
	glow.enabled = true

	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = _build_sprite_frames()
	_sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	_sprite.position = Vector2(0.0, SPRITE_Y_OFFSET)
	add_child(_sprite)
	_sprite.play("idle")

func _physics_process(delta: float) -> void:
	if not is_transitioning:
		_read_input()
		_update_state(delta)
		move_and_slide()
		StatusEffectRuntime.process(self, delta)
		if not warding_sigil_active.is_empty():
			CombatManager.warding_sigil_tick(self, delta)
	_update_camera_shake(delta)
	_update_sprite_animation()
	queue_redraw()

## Drives the AnimatedSprite2D from the same anim_state/facing state
## _draw() below used to drive the old procedural body directly — picks
## the animation, flips it left/right instead of rotating it (a raster
## character sprite spun to an arbitrary angle the way the old vector
## silhouette rotated toward the mouse would look wrong; flipping is the
## standard top-down-illustrated-sprite equivalent), and layers the
## hit/death feedback the old code drew as separate procedural overlays
## on as a plain modulate tint instead, now that there's a real
## silhouette to tint precisely rather than an approximating ellipse.
func _update_sprite_animation() -> void:
	if _sprite == null:
		return
	var draw_facing: float = attack_facing_lock if is_attacking else facing
	var h: float = cos(draw_facing)
	if absf(h) > 0.15:
		_facing_left = h < 0.0
	_sprite.flip_h = _facing_left

	var target_anim: String = "idle"
	match anim_state:
		AnimState.ATTACK: target_anim = "attack"
		AnimState.DODGE: target_anim = "dodge"
		AnimState.RUN: target_anim = "run"
		_: target_anim = "idle"
	if _sprite.animation != target_anim:
		_sprite.play(target_anim)

	var tint := Color.WHITE
	if not alive:
		var death_t: float = minf(1.0, death_timer / 0.6)
		tint.a = maxf(0.15, 1.0 - death_t * 0.6)
		_sprite.rotation = (PI / 2.0) * _ease_out_cubic(death_t) * (1.0 if facing > 0.0 else -1.0)
		_sprite.position = Vector2(0.0, SPRITE_Y_OFFSET + _ease_out_cubic(death_t) * 10.0)
		_sprite.pause()
	else:
		_sprite.rotation = 0.0
		_sprite.position = Vector2(0.0, SPRITE_Y_OFFSET)
		if hit_flash_timer > 0.0:
			tint = tint.lerp(Color(Palette.BLOOD_BRIGHT), (hit_flash_timer / 0.28) * 0.75)
	_sprite.modulate = tint

func _read_input() -> void:
	var x := 0.0
	var y := 0.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): y += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): x += 1.0
	move_input = Vector2(x, y)
	if move_input.length_squared() > 1.0:
		move_input = move_input.normalized()
	facing = (get_global_mouse_position() - global_position).angle()

	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and can_attack():
		start_attack()
	if Input.is_physical_key_pressed(KEY_SPACE) and can_dodge():
		# Dodge toward current move input; fall back to facing (aim) if the
		# player isn't holding a direction — exact port of Game.ts's
		# performDodge, including its 0.1 magnitude threshold.
		var dir := move_input
		if dir.length() < 0.1:
			dir = Vector2(cos(facing), sin(facing))
		else:
			dir = dir.normalized()
		start_dodge(dir)
		AudioEngine.play_sfx("dodge")
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and can_use_ability():
		start_ability()

func _update_state(dt: float) -> void:
	run_time += dt
	anim_time += dt
	if not alive:
		death_timer += dt
		return

	if invuln_timer > 0.0: invuln_timer -= dt
	if hit_flash_timer > 0.0: hit_flash_timer -= dt
	if attack_cooldown_timer > 0.0: attack_cooldown_timer -= dt
	if dodge_cooldown_timer > 0.0: dodge_cooldown_timer -= dt
	if stamina_regen_delay_timer > 0.0: stamina_regen_delay_timer -= dt
	if perfect_dodge_timer > 0.0: perfect_dodge_timer -= dt

	if not warding_sigil_active.is_empty():
		warding_sigil_active["timer"] = (warding_sigil_active["timer"] as float) + dt
		if (warding_sigil_active["timer"] as float) >= (warding_sigil_active["duration"] as float):
			warding_sigil_active = {}

	hp = clampf(hp + stats.hp_regen * dt, 0.0, stats.max_hp)
	if stamina_regen_delay_timer <= 0.0:
		stamina = clampf(stamina + STAMINA_REGEN_RATE * dt, 0.0, stats.stamina_max)
	# energyRegen (Second Wind) scales this proportionally to its base value,
	# so the ability always finishes a full 0->100% recharge in exactly its
	# own cooldown duration at the default regen rate, faster with upgrades.
	var current_ability := ability()
	if current_ability != null:
		var ability_regen_rate: float = (stats.energy_max / current_ability.cooldown) * (stats.energy_regen / BASE_ENERGY_REGEN)
		energy = clampf(energy + ability_regen_rate * dt, 0.0, stats.energy_max)

	if is_attacking:
		attack_anim_timer += dt
		var swing_duration: float = minf(0.32, attack_cooldown_duration() * 0.85)
		if attack_anim_timer >= swing_duration:
			is_attacking = false

	if is_dodging:
		dodge_timer += dt
		var t: float = dodge_timer / DODGE_DURATION
		var speed: float = stats.move_speed * 3.1 * (1.0 - t * 0.3)
		velocity = dodge_dir * speed
		# Ports Game.ts's per-frame "if (player.isDodging)
		# spawnDodgeTrail(...)" — one trail particle every physics tick for
		# the dodge's whole (short) duration, same density as the source.
		var vfx_parent := get_parent()
		if vfx_parent != null:
			VfxPresets.dodge_trail(vfx_parent, global_position, facing, Palette.EMBER4)
		if dodge_timer >= DODGE_DURATION:
			is_dodging = false
			last_dodge_end_time = run_time
	else:
		var target_velocity: Vector2 = move_input * stats.move_speed
		velocity += (target_velocity - velocity) * minf(1.0, MOVE_ACCEL * dt)

	var moving: bool = move_input.x != 0.0 or move_input.y != 0.0

	if is_channeling_ability:
		ability_anim_timer += dt
		if ability_anim_timer > 0.35:
			is_channeling_ability = false

	if not is_attacking and not is_dodging and not is_channeling_ability:
		anim_state = AnimState.RUN if moving else AnimState.IDLE

## Ports rendering/draw/drawPlayer.ts, though far less of it directly now:
## the body/cape/head/chest-ember/hit-flash shapes this function used to
## build point-by-point are gone, replaced by the real AnimatedSprite2D
## _update_sprite_animation() (above) drives every physics tick. What's
## left here is everything that was never "the body" to begin with — the
## ground shadow, the weapon+arm (still a small procedural shape rather
## than the reference's own illustrated one: it's a rotating blade/staff,
## which reads fine spun to an arbitrary angle in a way a whole
## illustrated character silhouette does not, so keeping it procedural
## keeps continuous aim-direction feedback the sprite swap can't give
## anymore), and the invulnerability ring (a pulse independent of body
## shape, not worth tying to the new silhouette).
##
## bob/squash — the old idle-breathing/run-bob/dodge-squash the body used
## to get via _body_xf — are dropped from the weapon call entirely now:
## that motion lives in the sprite's own animation frames instead, and
## layering the old separately-computed sine bob on top of it would fight
## the baked-in motion rather than match it.
func _draw() -> void:
	var w: WeaponDefinition = weapon()
	var draw_facing: float = attack_facing_lock if is_attacking else facing
	var is_dead: bool = not alive
	var death_t: float = minf(1.0, death_timer / 0.6)
	var death_angle := 0.0
	var death_alpha := 1.0
	if is_dead:
		death_alpha = maxf(0.15, 1.0 - death_t * 0.6)
		death_angle = (PI / 2.0) * _ease_out_cubic(death_t) * (1.0 if facing > 0.0 else -1.0)

	# Shadow anchors to the ground, same fixed position the sprite's own
	# SPRITE_Y_OFFSET is calibrated against.
	DrawUtils.draw_soft_shadow(self, 0.0, 20.0, 22.0, 9.0, 0.42)

	# --- Arm + Weapon ---
	# (weapon() can return null on a missing/misconfigured DataRegistry
	# entry — see weapon()'s own push_error above. Not something the
	# source's player.weapon getter has to account for, but skipping the
	# arm/weapon silhouette entirely is the safe fallback here rather than
	# guessing at a placeholder weapon.)
	#
	# Skipped entirely while is_attacking: the reference art's own attack
	# frames already carry a dramatic weapon-equivalent energy-slash
	# effect, so drawing this procedural blade on top during the swing
	# read as two overlapping weapons rather than one — reported directly
	# against real gameplay, not caught by this project's own renders
	# (which only ever screenshotted one swing frame at a time, not the
	# full sequence next to the sprite's own effect). Idle/run/dodge still
	# draw it normally: those sprite frames don't carry their own weapon
	# art, so it's the only visual cue for which weapon is equipped
	# outside of combat.
	if DRAW_WEAPON and w != null and not is_attacking:
		# The grip stays pinned to a fixed hand position on the body (mirrored
		# with the sprite's own flip_h so it's always on the facing side, see
		# HAND_OFFSET below), and only the blade's own direction rotates
		# around that fixed point — not, as before, the grip itself orbiting
		# the character's center. That old model was the actual bug behind
		# "the weapon crosses through the body": at an arm_offset of only 10
		# units, the grip end sat close enough to center that swinging
		# weapon_angle through its full continuous range (this still tracks
		# the mouse continuously, unlike the body which only flips) carried
		# the whole weapon — including the hand end — across the torso
		# whenever the player aimed anywhere other than straight left/right.
		# Clamping weapon_angle to a bounded arc around the facing side
		# fixes it structurally: the blade can swing up/down somewhat for
		# aim feedback, but never past pointing "into" the body.
		var base_angle: float = PI if _facing_left else 0.0
		var angle_delta: float = clampf(wrapf(draw_facing - base_angle, -PI, PI), -WEAPON_ANGLE_CLAMP, WEAPON_ANGLE_CLAMP)
		var weapon_angle: float = base_angle + angle_delta
		var hand_pos := Vector2(-HAND_OFFSET.x, HAND_OFFSET.y) if _facing_left else HAND_OFFSET
		# Melee blade length is derived from the weapon's actual (stat-scaled) range so the
		# sprite always reaches exactly as far as the hitbox does — the hand's own distance
		# from center (HAND_OFFSET) and the blade tip's own +4 extension (_draw_weapon's
		# path) are both part of that total reach.
		var melee_length: float = maxf(20.0, w.range * stats.range_mult - HAND_OFFSET.x - 4.0)
		var weapon_length: float = melee_length if w.kind == WeaponDefinition.Kind.MELEE else 40.0
		_draw_weapon(w, weapon_length, weapon_angle, hand_pos, death_angle, death_alpha)

	if is_invulnerable() and alive and not is_dodging:
		var ring_pts := PackedVector2Array()
		for p in _ellipse_points(0.0, 2.0, 17.0, 20.0):
			ring_pts.append(p)
		ring_pts.append(ring_pts[0])
		var ring_pulse: float = 0.5 + sin(run_time * 30.0) * 0.2
		var ring_color := Color(Palette.EMBER5)
		ring_color.a = 0.6 * ring_pulse
		draw_polyline(ring_pts, ring_color, 1.5, true)

## Ports drawPlayer.ts's local drawWeapon() helper, with the grip's own
## anchor point now pinned to a fixed spot on the body (`hand_pos`) instead
## of orbiting the character's center with `weapon_angle`. Every point is
## defined in the weapon's own local space with (0,0) at the middle of the
## grip (see grip_raw below, spanning roughly x=[-6,6]) — rotating around
## that local origin first, then translating the whole already-rotated
## shape out to hand_pos, is what keeps the grip end sitting still in the
## hand while only the blade swings through weapon_angle's arc. (The old
## version translated by arm_offset *before* rotating, which moved the
## grip itself through a wide circle around the body as weapon_angle
## changed — that, not the blade's length, was what let it cross the
## torso.) The on-death fall-over rotation (identity while alive) is
## applied last via _weapon_xf, same as before.
func _draw_weapon(w: WeaponDefinition, length: float, weapon_angle: float, hand_pos: Vector2, death_angle: float, death_alpha: float) -> void:
	if w.kind == WeaponDefinition.Kind.MELEE:
		var width: float = 9.0 if w.id == "voidScythe" else 6.0
		var curve: float = 0.55 if w.id == "voidScythe" else 0.15
		# The base corners below are (6, -3)/(6, 3), the reverse of the more
		# obvious (6, 3)/(6, -3) pairing with each curve's own control-point
		# sign: traced actual rendered point data and found the "obvious"
		# pairing crosses the two curves against each other partway down the
		# blade (this edge starts on the wrong side of the other one near
		# the base, swapping by the tip) — a self-intersecting polygon
		# Godot's triangulator silently drops the fill for entirely
		# (confirmed 1:1 against this project's own "Invalid polygon data,
		# triangulation failed" log spam, one per weapon redraw), unlike the
		# source's Canvas2D fill() this ported from, which fills a bowtie
		# path fine via its own winding rule. Anchoring each curve's start/
		# end to the same side its control point already pulls it toward
		# keeps the two curves apart for the whole span, meeting only at
		# the tip and at this shared base edge.
		var raw := _quad_bezier_points(Vector2(6.0, -3.0), Vector2(length * 0.55, -width - length * curve), Vector2(length, -width * 0.4), 8)
		raw.append(Vector2(length + 4.0, 0.0))
		var raw_seg2 := _quad_bezier_points(Vector2(length + 4.0, 0.0), Vector2(length * 0.55, width * 0.7 + length * curve * 0.6), Vector2(6.0, 3.0), 8)
		for i in range(1, raw_seg2.size()):
			raw.append(raw_seg2[i])
		var blade_pts := PackedVector2Array()
		for p in raw:
			blade_pts.append(_weapon_xf(p.rotated(weapon_angle) + hand_pos, death_angle))
		# 3-stop gradient (bg3 -> weapon color -> near-white) simplified to
		# the weapon's own (middle, most identity-defining) flat color.
		var blade_color := Color(w.color)
		blade_color.a = death_alpha
		draw_colored_polygon(blade_pts, blade_color)

		var grip_raw := PackedVector2Array([Vector2(-6.0, -3.0), Vector2(6.0, -3.0), Vector2(6.0, 3.0), Vector2(-6.0, 3.0)])
		var grip_pts := PackedVector2Array()
		for p in grip_raw:
			grip_pts.append(_weapon_xf(p.rotated(weapon_angle) + hand_pos, death_angle))
		var grip_color := Color(Palette.BG2)
		grip_color.a = death_alpha
		draw_colored_polygon(grip_pts, grip_color)
	else:
		var head_raw := PackedVector2Array([Vector2(4.0, 0.0), Vector2(length - 14.0, -4.0), Vector2(length, 0.0), Vector2(length - 14.0, 4.0)])
		var head_pts := PackedVector2Array()
		for p in head_raw:
			head_pts.append(_weapon_xf(p.rotated(weapon_angle) + hand_pos, death_angle))
		# Gradient (bg3 -> weapon color) simplified to its midpoint tone.
		var head_color: Color = DrawUtils.lerp_color_hex(Palette.BG3, w.color, 0.5)
		head_color.a = death_alpha
		draw_colored_polygon(head_pts, head_color)

		var grip_raw := PackedVector2Array([Vector2(-4.0, -2.5), Vector2(6.0, -2.5), Vector2(6.0, 2.5), Vector2(-4.0, 2.5)])
		var grip_pts := PackedVector2Array()
		for p in grip_raw:
			grip_pts.append(_weapon_xf(p.rotated(weapon_angle) + hand_pos, death_angle))
		var grip_color := Color(Palette.BG2)
		grip_color.a = death_alpha
		draw_colored_polygon(grip_pts, grip_color)

	# Small ember glow at the guard, same light the chest carries reaching
	# out to the hand that bears it. draw_glow_circle takes one plain
	# center point with no per-point transform hook, so — same workaround
	# every other glow center in this file uses — the rotate/translate/
	# _weapon_xf chain above is replayed manually just for this one point.
	var hilt_center := Vector2(-2.0, 0.0).rotated(weapon_angle) + hand_pos
	hilt_center = _weapon_xf(hilt_center, death_angle)
	DrawUtils.draw_glow_circle(self, hilt_center.x, hilt_center.y, 4.0, Palette.EMBER5, 0.85 * death_alpha)

## The weapon's own, much smaller version of the old _body_xf: just the
## on-death fall-over rotation (identity while alive), since bob/squash no
## longer apply to anything drawn in this file (see _draw_weapon's own
## header) and death_offset_y's vertical drop is already carried by the
## sprite's own position — applying it a second time here would double it.
func _weapon_xf(p: Vector2, death_angle: float) -> Vector2:
	return p.rotated(death_angle)

## Filled-ellipse point sampler — Godot's _draw() has no ellipse primitive.
## Mirrors DrawUtils' own internal ellipse loop, kept as a private copy
## here (rather than calling its underscore-prefixed _draw_ellipse) since
## the invulnerability ring, this function's sole remaining caller since
## the body/cape/head moved onto a real sprite, needs the raw points back
## to draw as an open polyline rather than a filled shape.
func _ellipse_points(cx: float, cy: float, rx: float, ry: float, segments: int = 20) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments + 1):
		var angle: float = (float(i) / float(segments)) * TAU
		pts.append(Vector2(cx + cos(angle) * rx, cy + sin(angle) * ry))
	return pts

## Samples a quadratic Bézier curve into straight segments — Canvas2D's
## quadraticCurveTo has no direct Godot draw-API equivalent. Same
## name/signature/formula as obstacle_node.gd's own private helper.
func _quad_bezier_points(p0: Vector2, control: Vector2, p1: Vector2, segments: int = 8) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments + 1):
		var t: float = float(i) / float(segments)
		var mt: float = 1.0 - t
		pts.append(p0 * (mt * mt) + control * (2.0 * mt * t) + p1 * (t * t))
	return pts

## Mirrors MathUtils.ts's easeOutCubic — no shared MathUtils.gd exists yet
## in Godot, so (like level_flow.gd's own private _ease_out_cubic) this
## file keeps its own small private copy of the same formula.
func _ease_out_cubic(t: float) -> float:
	var p := t - 1.0
	return p * p * p + 1.0
