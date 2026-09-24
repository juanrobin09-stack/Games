class_name ChestNode
extends Node2D
## Ports entities/Chest.ts. No physics body — like the source, a chest never
## blocks movement, it's purely a proximity-interaction landmark (see
## LevelFlow's interaction-range checks, ported from Game.ts's
## getRoomInteraction). Reuses UpgradeDefinition.Rarity for `tier` rather
## than a parallel enum, since it's the exact same rarity scale.
##
## Reward-granting itself (rolling and applying the actual upgrade) lives in
## LevelFlow.open_chest() — this node only plays out the closed -> opened
## state machine and its own visuals; a chest has no player-choice step
## (unlike a room-clear reward or a shop offer), so it needed no real UI to
## wire for real (see GODOT_MIGRATION.md §5, build-order step 9). The switch
## is instant: LevelFlow.open_chest()/open_classified_chest() already grant
## and show the reward the instant they call open() below, so the chest's
## own sprite swap and burst VFX fire in that same call rather than lagging
## behind on a timer the player has no way to perceive.
enum State { CLOSED, OPENED }

## User-supplied art (closed/open lid states), background removed --
## replaces the earlier procedural body-rect + animated lid-swing silhouette.
## Sized off their own aspect ratio at draw time rather than a hardcoded
## height, same convention as _draw_merchant_stall's STALL_TEXTURE.
const CLOSED_TEXTURE := preload("res://assets/textures/chest_closed.png")
const OPEN_TEXTURE := preload("res://assets/textures/chest_open.png")
const SPRITE_W := 42.0
## Both textures draw bottom-anchored to this fixed offset from `position`
## instead of vertically centered, so opening (which grows the sprite
## upward for the raised lid) doesn't also sink the chest's own floor
## contact point down -- the base stays put, only the lid rises.
const FLOOR_CONTACT_Y := 14.0

var radius: float = 22.0
var tier: UpgradeDefinition.Rarity = UpgradeDefinition.Rarity.COMMON
var state: State = State.CLOSED
var glow_phase: float = 0.0

## Loot-system pass: a SECOND, independent kind of chest this same node/
## scene now also renders — the classified C/B/A/S/SS chests, locked
## behind a matching key rather than the existing tier system above. Kept
## as extra fields on the one ChestNode rather than a second scene/script:
## the interaction range-check, open/close state machine, and glow VFX
## below are identical for both kinds, only the color lookup and the
## reward differ (see _tier_color() and LevelFlow.open_classified_chest()).
var is_classified: bool = false
var chest_tier: LootRarity.Tier = LootRarity.Tier.C
## An ItemDefinition.id (ItemType.KEY) and a LootTableDefinition.id,
## resolved once at spawn time from DungeonChestConfig/ChestClassDefinition
## for the zone the chest spawned in — the chest itself doesn't need to
## remember which zone that was.
var required_key_item_id: String = ""
var loot_table_id: String = ""

func _ready() -> void:
	# Counters RoomContainer's own z_index = -10 (see its own comment) so
	# the chest doesn't inherit that and vanish behind the room's floor.
	z_as_relative = false
	($Glow as PointLight2D).texture = DrawUtils.glow_texture()

func setup(pos: Vector2, p_tier: UpgradeDefinition.Rarity) -> void:
	position = pos
	tier = p_tier

func setup_classified(pos: Vector2, p_tier: LootRarity.Tier, key_item_id: String, table_id: String) -> void:
	position = pos
	is_classified = true
	chest_tier = p_tier
	required_key_item_id = key_item_id
	loot_table_id = table_id

func can_interact() -> bool:
	return state == State.CLOSED

## Ports Game.ts's spawnChestOpenBurst — fired there once a resolved reward
## is shown, which happens synchronously in the same LevelFlow call that
## invokes this, so the burst fires right here rather than on a delay.
func open() -> void:
	if state != State.CLOSED:
		return
	state = State.OPENED
	var parent := get_parent()
	if parent != null:
		VfxPresets.chest_open_burst(parent, global_position, _tier_color())
	queue_redraw()
	_update_light()

func _process(dt: float) -> void:
	glow_phase += dt
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
	if is_classified:
		return Palette.loot_rarity_color(chest_tier)
	match tier:
		UpgradeDefinition.Rarity.COMMON: return "#b9b3a6"
		UpgradeDefinition.Rarity.UNCOMMON: return "#6fd17a"
		UpgradeDefinition.Rarity.RARE: return "#5aa9e6"
		UpgradeDefinition.Rarity.EPIC: return "#b06de0"
		UpgradeDefinition.Rarity.LEGENDARY: return "#f2b53d"
		_: return "#ffffff"

func _draw() -> void:
	var color_hex := _tier_color()
	var color := Color(color_hex)
	var glow_pulse: float = 0.6 + sin(glow_phase * 2.0) * 0.25

	var opened := state == State.OPENED
	var tex: Texture2D = OPEN_TEXTURE if opened else CLOSED_TEXTURE
	var w := SPRITE_W
	var h := w * (tex.get_height() / float(tex.get_width()))

	DrawUtils.draw_soft_shadow(self, 0.0, FLOOR_CONTACT_Y - 2.0, w * 0.6, w * 0.22, 0.45)

	var glow_center_y: float = FLOOR_CONTACT_Y - h * 0.5
	var glow_radius: float = w * (1.5 if opened else 1.05) * glow_pulse
	var glow_alpha: float = 0.55 if opened else 0.4
	DrawUtils.draw_glow_circle(self, 0.0, glow_center_y, glow_radius, color_hex, glow_alpha)

	draw_texture_rect(tex, Rect2(-w / 2.0, FLOOR_CONTACT_Y - h, w, h), false)

	if opened:
		var sparkle_alpha: float = 0.5 + sin(glow_phase * 4.0) * 0.3
		draw_circle(Vector2(0.0, FLOOR_CONTACT_Y - h - 6.0), 2.0, Color(color.r, color.g, color.b, sparkle_alpha))
