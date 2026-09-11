class_name HudLayer
extends Control
## Ports ui/HUD.ts — build-order step 9. Built entirely in code (_ready())
## rather than as a hand-authored .tscn node tree: with no editor available
## to lay out and verify ~25 nested Controls visually, plain GDScript
## construction is easier to get right by reading straight-line code than
## cross-referencing a hand-typed .tscn against @onready $Path lookups, and
## it fits this project's existing "procedural over hand-placed" bias
## anyway (see ui_icons.gd, every entity's _draw()).
##
## Colors/pixel sizes below are read directly off style.css's .hud-* rules
## (the Web build's own source of truth) rather than guessed. Gradient
## fills simplify to their brighter/rightmost stop — a flat ColorRect, not
## a texture — same "gradient -> its most identity-defining flat stop"
## convention player.gd/chest_node.gd already use throughout for the same
## reason (no cheap gradient-fill primitive on a plain Control here either).
##
## Root cause of the first version's "only top-left renders" bug, for
## the record: every region here is positioned via anchors set through
## plain property assignment (`col.anchor_left = 1.0`), which goes through
## Control.set_anchor()'s default push_opposite_anchor=true. On a freshly
## created Control (every anchor still at its default 0.0), setting e.g.
## anchor_left to 1.0 BEFORE anchor_right has been touched makes the new
## value cross the still-default opposite anchor (1.0 > 0.0) — Godot then
## silently "pushes" the opposite anchor to resolve the now-invalid rect,
## corrupting the offsets any later explicit assignment doesn't fully
## undo. top_left was the one region that happened to need every anchor
## left at 0.0 (a no-op, never crossing anything), which is exactly why it
## was the only one that ever rendered. Every region below now goes
## through set_anchors_preset() instead — the same single atomic call the
## root Hud control's own PRESET_FULL_RECT already used successfully —
## then sets custom offsets afterward, which is safe since offsets are
## plain pixel deltas with no "opposite side" to cross.
##
## Deferred to a follow-up commit — NOT full step 9 yet, see godot/README.md:
## the minimap (refreshMinimap's double-resolution grid algorithm), the
## toast/phase-banner/synergy-banner system, the boss bar (its data,
## BossHudInfo, needs the boss attack-FSM gap closed first), and both
## vignettes (danger/corruption) — Godot has no cheap radial-gradient-on-a-
## flat-Control primitive, and a botched full-screen overlay risks making
## the game unreadable with no way for me to catch it before it ships, so
## that waits for its own carefully-tested pass instead of a guess.

const BAR_TRACK_BG := Color(8.0 / 255.0, 6.0 / 255.0, 10.0 / 255.0, 0.65)
const ABILITY_SLOT_SIZE := 46.0
const BAR_ICON_SIZE := 26.0
const SMALL_ICON_SIZE := 14.0

var _hp_fill: ColorRect
var _hp_label: Label
var _shield_row: HBoxContainer
var _buff_row: HBoxContainer
var _stamina_fill: ColorRect
var _stamina_label: Label
var _stamina_track_bg: ColorRect
var _energy_fill: ColorRect
var _energy_label: Label
var _embers_label: Label
var _timer_label: Label
var _zone_label: Label
var _corruption_fill: ColorRect
var _ability_slot: Control
var _ability_icon: HudIcon
var _ability_sweep: ColorRect
var _weapon_icon: HudIcon
var _weapon_name_label: Label
var _ability_name_label: Label
var _interact_label: Label
var _level_label: Label
var _xp_fill: ColorRect
var _xp_label: Label
var _points_hint: Label

var _weapon_icon_id: String = ""
var _ability_icon_id: String = ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_top_left()
	_build_top_right()
	_build_bottom_left()
	_build_bottom_right()
	_build_interact_prompt()

# ---------------------------------------------------------------- Bar helper

## Builds one icon+track(+fill+label) row inside `col` (a VBoxContainer) and
## returns {"row": HBoxContainer, "fill": ColorRect, "label": Label} so the
## caller can keep the pieces it needs to update later, or (HP's shield
## pips) append another sibling into the returned row. icon_id == "" skips
## the icon entirely (the corruption bar has none).
func _make_bar_row(col: Control, icon_id: String, icon_color: Color, fill_color: Color, show_label: bool = true) -> Dictionary:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)

	if icon_id != "":
		var icon := HudIcon.new()
		icon.icon_id = icon_id
		icon.icon_color = icon_color
		icon.custom_minimum_size = Vector2(BAR_ICON_SIZE, BAR_ICON_SIZE)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)

	var track := Control.new()
	track.custom_minimum_size = Vector2(90.0, 16.0)
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(track)

	var bg := ColorRect.new()
	bg.color = BAR_TRACK_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(bg)

	var fill := ColorRect.new()
	fill.color = fill_color
	fill.anchor_left = 0.0
	fill.anchor_top = 0.0
	fill.anchor_right = 0.0
	fill.anchor_bottom = 1.0
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(fill)

	var label: Label = null
	if show_label:
		label = Label.new()
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 11)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		track.add_child(label)

	return {"row": row, "bg": bg, "fill": fill, "label": label}

static func _set_bar_ratio(fill: ColorRect, ratio: float) -> void:
	fill.anchor_right = clampf(ratio, 0.0, 1.0)

func _make_small_icon(icon_id: String, color: Color) -> HudIcon:
	var icon := HudIcon.new()
	icon.icon_id = icon_id
	icon.icon_color = color
	icon.custom_minimum_size = Vector2(SMALL_ICON_SIZE, SMALL_ICON_SIZE)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon

## TEMPORARY diagnostic (remove once the "regions besides top-left don't
## render" bug is confirmed fixed): a loud, impossible-to-miss flat-color
## background as the first child of a region container, so a screenshot
## alone shows whether that container is actually positioned/visible on
## screen at all — regardless of whether ITS OWN children (icons/labels/
## fills) separately fail to render. Isolates "container never appears"
## from "container appears but is empty."
func _debug_marker(parent: Control, color: Color) -> void:
	var marker := ColorRect.new()
	marker.color = color
	marker.set_anchors_preset(Control.PRESET_FULL_RECT)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(marker)

# ---------------------------------------------------------------- Regions

func _build_top_left() -> void:
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 6)
	col.set_anchors_preset(Control.PRESET_TOP_LEFT)
	col.offset_left = 14.0
	col.offset_top = 14.0
	col.offset_right = 14.0 + 260.0
	col.offset_bottom = 14.0 + 170.0
	add_child(col)

	var hp := _make_bar_row(col, "heart", Color(Palette.EMBER5), Color(Palette.BLOOD_BRIGHT))
	_hp_fill = hp["fill"]
	_hp_label = hp["label"]
	_shield_row = HBoxContainer.new()
	_shield_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shield_row.add_theme_constant_override("separation", 3)
	(hp["row"] as HBoxContainer).add_child(_shield_row)

	var stamina := _make_bar_row(col, "stamina", Color(Palette.TOXIC), Color(Palette.TOXIC))
	_stamina_track_bg = stamina["bg"]
	_stamina_fill = stamina["fill"]
	_stamina_label = stamina["label"]

	var energy := _make_bar_row(col, "ability", Color(Palette.EMBER5), Color(Palette.EMBER4))
	_energy_fill = energy["fill"]
	_energy_label = energy["label"]

	_buff_row = HBoxContainer.new()
	_buff_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buff_row.add_theme_constant_override("separation", 4)
	col.add_child(_buff_row)

func _build_top_right() -> void:
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 4)
	col.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	col.offset_left = -14.0 - 200.0
	col.offset_top = 14.0
	col.offset_right = -14.0
	col.offset_bottom = 14.0 + 90.0
	add_child(col)
	_debug_marker(col, Color.MAGENTA)

	var embers_row := HBoxContainer.new()
	embers_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	embers_row.alignment = BoxContainer.ALIGNMENT_END
	embers_row.add_theme_constant_override("separation", 6)
	col.add_child(embers_row)
	embers_row.add_child(_make_small_icon("ember", Color(Palette.EMBER4)))
	_embers_label = Label.new()
	_embers_label.add_theme_font_size_override("font_size", 15)
	_embers_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	embers_row.add_child(_embers_label)

	_timer_label = Label.new()
	_timer_label.add_theme_font_size_override("font_size", 12)
	_timer_label.add_theme_color_override("font_color", Color(Palette.TEXT_DIM))
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_timer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_timer_label)

	_zone_label = Label.new()
	_zone_label.add_theme_font_size_override("font_size", 13)
	_zone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_zone_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_zone_label)

	var corruption_track := Control.new()
	corruption_track.custom_minimum_size = Vector2(140.0, 6.0)
	corruption_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(corruption_track)
	var corruption_bg := ColorRect.new()
	corruption_bg.color = BAR_TRACK_BG
	corruption_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	corruption_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	corruption_track.add_child(corruption_bg)
	_corruption_fill = ColorRect.new()
	_corruption_fill.color = Color(Palette.BLOOD_BRIGHT)
	_corruption_fill.anchor_left = 0.0
	_corruption_fill.anchor_top = 0.0
	_corruption_fill.anchor_right = 0.0
	_corruption_fill.anchor_bottom = 1.0
	_corruption_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	corruption_track.add_child(_corruption_fill)

func _build_bottom_left() -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	row.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	row.offset_left = 14.0
	row.offset_top = -16.0 - ABILITY_SLOT_SIZE
	row.offset_right = 14.0 + 260.0
	row.offset_bottom = -16.0
	add_child(row)
	_debug_marker(row, Color.CYAN)

	_ability_slot = Control.new()
	_ability_slot.custom_minimum_size = Vector2(ABILITY_SLOT_SIZE, ABILITY_SLOT_SIZE)
	_ability_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_ability_slot)

	var slot_bg := ColorRect.new()
	slot_bg.color = Color(Palette.BG1)
	slot_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	slot_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ability_slot.add_child(slot_bg)

	_ability_icon = HudIcon.new()
	_ability_icon.icon_id = "ember"
	_ability_icon.icon_color = Color(Palette.EMBER5)
	_ability_icon.position = Vector2(ABILITY_SLOT_SIZE / 2.0 - 11.0, ABILITY_SLOT_SIZE / 2.0 - 11.0)
	_ability_icon.size = Vector2(22.0, 22.0)
	_ability_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ability_slot.add_child(_ability_icon)

	# Covers the icon while charging, uncovering top-down as ready_ratio (see
	# update()) climbs to 1 — anchor_bottom stays pinned at 1.0 always;
	# anchor_top is the only thing update() ever changes on this node.
	_ability_sweep = ColorRect.new()
	_ability_sweep.color = Color(0.016, 0.012, 0.024, 0.72)
	_ability_sweep.anchor_left = 0.0
	_ability_sweep.anchor_right = 1.0
	_ability_sweep.anchor_top = 0.0
	_ability_sweep.anchor_bottom = 1.0
	_ability_sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ability_slot.add_child(_ability_sweep)

	var key_hint := Label.new()
	key_hint.text = "RMB"
	key_hint.position = Vector2(ABILITY_SLOT_SIZE - 30.0, ABILITY_SLOT_SIZE - 16.0)
	key_hint.size = Vector2(28.0, 14.0)
	key_hint.add_theme_font_size_override("font_size", 9)
	key_hint.add_theme_color_override("font_color", Color(Palette.TEXT_DIM))
	key_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ability_slot.add_child(key_hint)

	var names_col := VBoxContainer.new()
	names_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	names_col.add_theme_constant_override("separation", 4)
	row.add_child(names_col)

	var weapon_row := HBoxContainer.new()
	weapon_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weapon_row.add_theme_constant_override("separation", 6)
	names_col.add_child(weapon_row)
	_weapon_icon = _make_small_icon("blade", Color(Palette.TEXT_WARM))
	weapon_row.add_child(_weapon_icon)
	_weapon_name_label = Label.new()
	_weapon_name_label.add_theme_font_size_override("font_size", 13)
	_weapon_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weapon_row.add_child(_weapon_name_label)

	var ability_row := HBoxContainer.new()
	ability_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ability_row.add_theme_constant_override("separation", 6)
	names_col.add_child(ability_row)
	ability_row.add_child(_make_small_icon("ember", Color(Palette.TEXT_WARM)))
	_ability_name_label = Label.new()
	_ability_name_label.add_theme_font_size_override("font_size", 13)
	_ability_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ability_row.add_child(_ability_name_label)

## Reuses _make_bar_row for the XP track rather than a bespoke inline
## track/fill/label construction — kept from the anchor-bug investigation
## (see this file's own header) even after finding the real cause, since
## it's the same proven code path as HP/stamina/energy and one less
## variant of the same logic to maintain.
func _build_bottom_right() -> void:
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 4)
	col.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	col.offset_left = -14.0 - 220.0
	col.offset_top = -14.0 - 44.0
	col.offset_right = -14.0
	col.offset_bottom = -14.0
	add_child(col)
	_debug_marker(col, Color.YELLOW)

	var xp := _make_bar_row(col, "", Color.WHITE, Color(Palette.GOLD_BRIGHT))
	_xp_fill = xp["fill"]
	_xp_label = xp["label"]
	_level_label = Label.new()
	_level_label.text = "Lv.1"
	_level_label.add_theme_font_size_override("font_size", 13)
	_level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var xp_row := xp["row"] as HBoxContainer
	xp_row.add_child(_level_label)
	xp_row.move_child(_level_label, 0)

	_points_hint = Label.new()
	_points_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_points_hint.add_theme_font_size_override("font_size", 12)
	_points_hint.add_theme_color_override("font_color", Color(Palette.GOLD_BRIGHT))
	_points_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_points_hint.visible = false
	col.add_child(_points_hint)

func _build_interact_prompt() -> void:
	_interact_label = Label.new()
	_interact_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_interact_label.offset_top = -130.0
	_interact_label.offset_bottom = -108.0
	_interact_label.offset_left = -220.0
	_interact_label.offset_right = 220.0
	_interact_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_interact_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_interact_label.add_theme_font_size_override("font_size", 15)
	_interact_label.add_theme_color_override("font_color", Color(Palette.TEXT_WARM))
	_interact_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_interact_label.text = "[E] (diagnostic — always shown for now)"
	_interact_label.visible = true # TEMPORARY: forced on so this region is visible in a screenshot regardless of interaction state; update() still overwrites visible/text every frame once a real interaction exists.
	add_child(_interact_label)
	_debug_marker(_interact_label, Color.ORANGE)

# ---------------------------------------------------------------- Update

## `data` keys mirror HUD.ts's HudFrameData minus what this pass defers
## (boss, and staminaDenied/elapsedSeconds spelled snake_case): player,
## embers, zone_name, room_label, corruption, weapon_name, ability_name,
## weapon_icon, ability_icon, interact_prompt (String, "" = none),
## elapsed_seconds, stamina_denied, player_level, xp, xp_to_next,
## stat_points, is_max_level.
func update(data: Dictionary) -> void:
	var player: PlayerCharacter = data["player"]

	_level_label.text = "Lv.%d" % int(data["player_level"])
	var is_max: bool = data["is_max_level"]
	var xp_ratio: float = 1.0 if is_max else clampf(float(data["xp"]) / maxf(1.0, float(data["xp_to_next"])), 0.0, 1.0)
	_set_bar_ratio(_xp_fill, xp_ratio)
	_xp_label.text = "MAX" if is_max else "%d/%d" % [int(data["xp"]), int(data["xp_to_next"])]
	var stat_points: int = data["stat_points"]
	if stat_points > 0:
		_points_hint.text = "+%d  [I]" % stat_points
		_points_hint.visible = true
	else:
		_points_hint.visible = false

	var hp_ratio: float = clampf(player.hp / maxf(1.0, player.stats.max_hp), 0.0, 1.0)
	_set_bar_ratio(_hp_fill, hp_ratio)
	_hp_label.text = "%d / %d" % [ceili(player.hp), ceili(player.stats.max_hp)]

	for child in _shield_row.get_children():
		child.queue_free()
	for i in range(player.shield_charges):
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(8.0, 16.0)
		pip.color = Color(Palette.FROST)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_shield_row.add_child(pip)

	var energy_ratio: float = clampf(player.energy / maxf(1.0, player.stats.energy_max), 0.0, 1.0)
	_set_bar_ratio(_energy_fill, energy_ratio)
	_energy_label.text = "%d" % floori(player.energy)

	var stamina_ratio: float = clampf(player.stamina / maxf(1.0, player.stats.stamina_max), 0.0, 1.0)
	_set_bar_ratio(_stamina_fill, stamina_ratio)
	_stamina_label.text = "%d" % floori(player.stamina)
	var denied: bool = data.get("stamina_denied", false)
	_stamina_track_bg.color = Color(0.75, 0.23, 0.17, 0.55) if denied else BAR_TRACK_BG

	for child in _buff_row.get_children():
		child.queue_free()
	if player.perfect_dodge_timer > 0.0:
		_buff_row.add_child(_make_small_icon("dodge", Color(Palette.SOUL_BRIGHT)))
	if player.has_synergy("wrath") and player.hp / maxf(1.0, player.stats.max_hp) < 0.4:
		_buff_row.add_child(_make_small_icon("critDamage", Color(Palette.BLOOD_BRIGHT)))

	_embers_label.text = _format_number(int(data["embers"]))
	_zone_label.text = "%s · %s" % [data["zone_name"], data["room_label"]]
	_timer_label.text = _format_time(float(data["elapsed_seconds"]))
	_set_bar_ratio(_corruption_fill, float(data["corruption"]))

	# Sweep covers the icon while charging and clears as `energy` (the
	# ability's single-charge resource) fills back to max — see the
	# sweep's own construction comment in _build_bottom_left() for why
	# anchor_top (not scale) is what moves here.
	var ability_ready_ratio: float = clampf(player.energy / maxf(1.0, player.stats.energy_max), 0.0, 1.0)
	_ability_sweep.anchor_top = ability_ready_ratio

	var new_ability_icon: String = data["ability_icon"]
	if new_ability_icon != _ability_icon_id:
		_ability_icon_id = new_ability_icon
		_ability_icon.icon_id = new_ability_icon
		_ability_icon.queue_redraw()
	var new_weapon_icon: String = data["weapon_icon"]
	if new_weapon_icon != _weapon_icon_id:
		_weapon_icon_id = new_weapon_icon
		_weapon_icon.icon_id = new_weapon_icon
		_weapon_icon.queue_redraw()
	_weapon_name_label.text = data["weapon_name"]
	_ability_name_label.text = data["ability_name"]

	var prompt: String = data.get("interact_prompt", "")
	if prompt != "":
		_interact_label.text = "[E] %s" % prompt
		_interact_label.visible = true
	# TEMPORARY: the "else: _interact_label.visible = false" branch is
	# disabled while diagnosing the missing-regions bug, so the forced-on
	# marker from _build_interact_prompt() stays visible through every
	# update() call for the next screenshot. Restore it once that's fixed.

## Mirrors Game.ts's private roomTypeLabel.
static func room_type_label(type: RoomContainer.Type) -> String:
	match type:
		RoomContainer.Type.START: return "Entrance"
		RoomContainer.Type.COMBAT: return "Combat"
		RoomContainer.Type.ELITE: return "Elite Den"
		RoomContainer.Type.CHEST: return "Vault"
		RoomContainer.Type.SHOP: return "Merchant"
		RoomContainer.Type.EVENT: return "Unknown"
		RoomContainer.Type.REST: return "Respite"
		RoomContainer.Type.HEART: return "Zone Heart"
		RoomContainer.Type.BOSS: return "The Colossus"
		RoomContainer.Type.SANCTUM: return "Drowned Sanctum"
		_: return "?"

## Mirrors Game.ts's iconForWeapon/iconForAbility.
static func icon_for_weapon(weapon_id: String) -> String:
	return "bow" if weapon_id == "bow" else "blade"

static func icon_for_ability(ability_id: String) -> String:
	if ability_id == "stormstep": return "dodge"
	if ability_id == "wardingSigil": return "shield"
	return "ember"

## Mirrors MathUtils.ts's formatNumber.
static func _format_number(n: int) -> String:
	if n >= 1000000:
		return "%.1fM" % (n / 1000000.0)
	if n >= 10000:
		return "%dk" % int(n / 1000.0)
	return str(n)

## Mirrors MathUtils.ts's formatTime.
static func _format_time(seconds: float) -> String:
	var total: int = int(seconds)
	var m: int = total / 60
	var s: int = total % 60
	return "%d:%02d" % [m, s]
