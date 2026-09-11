class_name ChestNode
extends Node2D
## Ports entities/Chest.ts. No physics body — like the source, a chest never
## blocks movement, it's purely a proximity-interaction landmark (see
## LevelFlow's interaction-range checks, ported from Game.ts's
## getRoomInteraction). Reuses UpgradeDefinition.Rarity for `tier` rather
## than a parallel enum, since it's the exact same rarity scale.
##
## Reward-granting itself (rolling and applying the actual upgrade) lives in
## LevelFlow.open_chest() — this node only plays out the closed -> opening
## -> opened state machine and its own visuals; a chest has no player-choice
## step (unlike a room-clear reward or a shop offer), so it needed no real
## UI to wire for real (see GODOT_MIGRATION.md §5, build-order step 9).

enum State { CLOSED, OPENING, OPENED }

const OPEN_DURATION := 0.55

var radius: float = 22.0
var tier: UpgradeDefinition.Rarity = UpgradeDefinition.Rarity.COMMON
var state: State = State.CLOSED
var state_timer: float = 0.0
var glow_phase: float = 0.0

func _ready() -> void:
	# Counters RoomContainer's own z_index = -10 (see its own comment) so
	# the chest doesn't inherit that and vanish behind the room's floor.
	z_as_relative = false
	($Glow as PointLight2D).texture = DrawUtils.glow_texture()

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
		# Ports Game.ts's spawnChestOpenBurst — fired there once a resolved
		# reward is shown, which needs the upgrade-ownership system (step 9,
		# not built yet). Firing on the chest's own OPENING -> OPENED
		# transition instead ties it to something that already exists and
		# happens right when the lid visually finishes opening anyway.
		var parent := get_parent()
		if parent != null:
			VfxPresets.chest_open_burst(parent, global_position, _tier_color())
	queue_redraw()
	_update_light()

## Ports Game.ts's registerLights(): "if (room.chest && room.chest.state ===
## 'opened') lighting.add(room.chest.x, room.chest.y, 100,
## RARITY_COLORS[room.chest.tier], 0.7)" — reuses _tier_color() below rather
## than a second RARITY_COLORS table, since it's the exact same lookup the
## chest's own opened-lid glow already draws.
func _update_light() -> void:
	var glow: PointLight2D = $Glow
	if state != State.OPENED:
		glow.enabled = false
		return
	glow.enabled = true
	glow.texture_scale = 100.0 / 128.0
	glow.color = Color(_tier_color())
	glow.energy = 0.7

## Matches data/types.ts's RARITY_COLORS exactly (kept as a hex String, not
## Color, so it can feed DrawUtils.draw_glow_circle directly — see Palette's
## own "wrap in Color(...) at the point of use" convention).
func _tier_color() -> String:
	match tier:
		UpgradeDefinition.Rarity.COMMON: return "#b9b3a6"
		UpgradeDefinition.Rarity.UNCOMMON: return "#6fd17a"
		UpgradeDefinition.Rarity.RARE: return "#5aa9e6"
		UpgradeDefinition.Rarity.EPIC: return "#b06de0"
		UpgradeDefinition.Rarity.LEGENDARY: return "#f2b53d"
		_: return "#ffffff"

## Ports MathUtils.ts's easeOutBack exactly (drawChest.ts uses it for the
## lid's opening swing) — kept local since this is the only draw function
## in this pass that needs it.
static func _ease_out_back(t: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(t - 1.0, 3.0) + c1 * pow(t - 1.0, 2.0)

func _draw() -> void:
	# Ports drawChest.ts. Silhouette size is fixed like the source (not
	# derived from `radius`, which is interaction range only there too).
	var color_hex := _tier_color()
	var color := Color(color_hex)
	var w := 34.0
	var h := 24.0
	var glow_pulse: float = 0.6 + sin(glow_phase * 2.0) * 0.25

	DrawUtils.draw_soft_shadow(self, 0.0, h * 0.55, w * 0.7, h * 0.3, 0.45)

	var glow_radius: float = w * (1.6 if state == State.OPENED else 1.1) * glow_pulse
	var glow_alpha: float = 0.55 if state == State.OPENED else 0.4
	DrawUtils.draw_glow_circle(self, 0.0, -4.0, glow_radius, color_hex, glow_alpha)

	var lid_open: float = 0.0
	if state == State.OPENING:
		lid_open = _ease_out_back(minf(1.0, state_timer / 0.5))
	elif state == State.OPENED:
		lid_open = 1.0

	# Body. roundedRectPath's rounded corners simplify to a plain rect —
	# Godot's immediate-mode API has no rounded-rect primitive.
	draw_rect(Rect2(-w / 2.0, -h / 2.0, w, h), Color("#241a12"), true)
	draw_rect(Rect2(-w / 2.0, -h / 2.0, w, h), color, false, 2.0)

	# Lid, hinged at the body's back-top-left corner, swinging open up to
	# -75deg as lid_open -> 1. Points are computed already-rotated (project
	# convention) instead of using draw_set_transform.
	var lid_pivot := Vector2(-w / 2.0, -h / 2.0)
	var lid_angle: float = (-lid_open * PI) / 2.4
	var lid_points := PackedVector2Array()
	lid_points.append(lid_pivot + Vector2(0.0, -8.0).rotated(lid_angle))
	lid_points.append(lid_pivot + Vector2(w, -8.0).rotated(lid_angle))
	lid_points.append(lid_pivot + Vector2(w, 2.0).rotated(lid_angle))
	lid_points.append(lid_pivot + Vector2(0.0, 2.0).rotated(lid_angle))
	draw_colored_polygon(lid_points, Color("#2e2118"))
	var lid_outline := lid_points.duplicate()
	lid_outline.append(lid_points[0])
	draw_polyline(lid_outline, color, 2.0, true)

	# Latch dot.
	draw_circle(Vector2(0.0, -h * 0.1), 2.4, color)

	if state == State.OPENED:
		var sparkle_alpha: float = 0.5 + sin(glow_phase * 4.0) * 0.3
		draw_circle(Vector2(0.0, -h * 0.6 - 6.0), 2.0, Color(color.r, color.g, color.b, sparkle_alpha))
