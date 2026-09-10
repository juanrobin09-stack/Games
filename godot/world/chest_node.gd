class_name ChestNode
extends Node2D
## Ports entities/Chest.ts. No physics body — like the source, a chest never
## blocks movement, it's purely a proximity-interaction landmark (see
## LevelFlow's interaction-range checks, ported from Game.ts's
## getRoomInteraction). Reuses UpgradeDefinition.Rarity for `tier` rather
## than a parallel enum, since it's the exact same rarity scale.
##
## Reward-granting (rolling and applying the actual upgrade) needs the
## upgrade-ownership system, which doesn't exist yet (see GODOT_MIGRATION.md
## §5 — that's UI, step 9). Opening a chest here plays out the same
## closed -> opening -> opened state machine as the source, just without a
## real reward at the end yet — LevelFlow.open_chest() logs what tier would
## have been rolled so the gap is visible, not silent.

enum State { CLOSED, OPENING, OPENED }

const OPEN_DURATION := 0.55

var radius: float = 22.0
var tier: UpgradeDefinition.Rarity = UpgradeDefinition.Rarity.COMMON
var state: State = State.CLOSED
var state_timer: float = 0.0
var glow_phase: float = 0.0

func setup(pos: Vector2, p_tier: UpgradeDefinition.Rarity) -> void:
	position = pos
	tier = p_tier

func can_interact() -> bool:
	return state == State.CLOSED

func open() -> void:
	if state != State.CLOSED:
		return
	state = State.OPENING
	state_timer = 0.0

func _process(dt: float) -> void:
	state_timer += dt
	glow_phase += dt
	if state == State.OPENING and state_timer > OPEN_DURATION:
		state = State.OPENED
		state_timer = 0.0
	queue_redraw()

func _tier_color() -> Color:
	match tier:
		UpgradeDefinition.Rarity.COMMON: return Color("#b7b2a9")
		UpgradeDefinition.Rarity.UNCOMMON: return Color("#6fbf5a")
		UpgradeDefinition.Rarity.RARE: return Color("#5aa9e6")
		UpgradeDefinition.Rarity.EPIC: return Color("#b98fd9")
		UpgradeDefinition.Rarity.LEGENDARY: return Color("#ffbf47")
		_: return Color.WHITE

func _draw() -> void:
	var color := _tier_color()
	var lid_open: bool = state != State.CLOSED
	draw_rect(Rect2(-radius, -radius * 0.6, radius * 2.0, radius * 1.2), color * 0.6, true)
	if lid_open:
		var pulse: float = 0.5 + 0.5 * sin(glow_phase * 4.0)
		draw_circle(Vector2(0.0, -radius * 0.6), radius * 0.5, Color(color.r, color.g, color.b, 0.5 + 0.3 * pulse))
	draw_rect(Rect2(-radius, -radius * 0.6, radius * 2.0, radius * 1.2), color, false, 2.0)
