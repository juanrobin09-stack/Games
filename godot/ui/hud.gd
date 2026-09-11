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
## Root cause of the "only top-left renders" bug, for the record — found
## by actually building and running this project headlessly under Xvfb
## and comparing a real screenshot against a full Control-tree dump (see
## _ready()'s own comment): calling set_anchors_preset() on a Control that
## is ALREADY in the scene tree (true of this Control itself — the
## instanced scene root, parented under main.tscn's UI CanvasLayer before
## _ready() runs) computes offsets that PRESERVE its current rect rather
## than resetting to 0, which for a freshly-instanced (0,0)-sized root
## left it (0,0)-sized even inside a real window — every child anchored at
## 0.0 (top-left) is blind to that (0 * anything = 0), every child
## anchored at 1.0 or 0.5 isn't. Calling set_anchors_preset() on a node
## BEFORE parenting it (true of every region's own col/row below, and
## every bar's internal track background) doesn't have this problem —
## there's no prior rect for it to preserve, so it cleanly resets to 0.
## An earlier fix attempt (switching every region from raw anchor_*
## property assignment to set_anchors_preset()) treated a real but
## unrelated Godot gotcha — Control.set_anchor()'s default
## push_opposite_anchor=true silently "pushing" an unset opposite anchor
## when its sibling jumps past it — as the cause; it wasn't, which is
## exactly why that fix alone didn't resolve the symptom.
##
## Deferred to a follow-up commit — NOT full step 9 yet, see godot/README.md:
## the boss bar — its data, BossHudInfo, needs the boss attack-FSM gap
## closed first (the boss currently fights as a generic enemy with no
## boss-specific attacks for a health bar to telegraph against).
##
## The toast/phase-banner/synergy-banner system (below) uses Tween, not
## this file's usual _process()-driven manual interpolation
## (FloatingText's own pattern) — CSS's multi-keyframe opacity+transform
## animations (see show_phase_banner/show_synergy_banner below) chain much
## more directly onto Tween.tween_property()/tween_interval() than onto
## hand-rolled per-frame easing math for two different animations at once.
## Every Tween here is pinned to TWEEN_PAUSE_PROCESS: a modal (Shop, say)
## pausing the tree shouldn't also freeze a banner triggered by something
## that happened to fire while it was open (buying an upgrade that
## completes a synergy, mid-shop) — these are non-interactive feedback
## overlays with nothing for get_tree().paused to protect.

const BAR_TRACK_BG := Color(8.0 / 255.0, 6.0 / 255.0, 10.0 / 255.0, 0.65)
const ABILITY_SLOT_SIZE := 46.0
const BAR_ICON_SIZE := 26.0
const SMALL_ICON_SIZE := 14.0
const SYNERGY_BANNER_REST_TOP := 18.0
## rgb(150,15,10) — the danger vignette's own edge color. No exact Palette
## match (checked); the corruption vignette's rgb(74,61,99) IS an exact
## match for Palette.SHADOW, reused directly in _build_vignettes() instead.
const DANGER_VIGNETTE_COLOR := Color(150.0 / 255.0, 15.0 / 255.0, 10.0 / 255.0, 0.9)
const DANGER_VIGNETTE_STOP := 0.55
const CORRUPTION_VIGNETTE_STOP := 0.45
const CORRUPTION_VIGNETTE_MAX_OPACITY := 0.4
const DANGER_START := 0.35
const CRITICAL_START := 0.15
const DANGER_MAX_OPACITY := 0.55
const DANGER_PULSE_PERIOD := 1.05
const DANGER_PULSE_HIGH := 0.6
const DANGER_PULSE_LOW := 0.32
## 1/sqrt(2) — see _make_vignette()'s own comment for what this reproduces.
const VIGNETTE_RADIUS := 0.70710678

var _danger_vignette: TextureRect
var _corruption_vignette: TextureRect
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
var _minimap: HudMinimap
var _boss_bar: VBoxContainer
var _boss_name_label: Label
var _boss_fill: ColorRect
var _boss_dots_row: HBoxContainer
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
var _toast_area: VBoxContainer
var _phase_banner: Label
var _phase_banner_tween: Tween
var _synergy_banner: PanelContainer
var _synergy_name_label: Label
var _synergy_desc_label: Label
var _synergy_banner_tween: Tween

var _weapon_icon_id: String = ""
var _ability_icon_id: String = ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The 4 explicit offset resets are load-bearing, not redundant with the
	# preset above — see this file's own header comment for why.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	_build_vignettes()
	_build_top_left()
	_build_top_right()
	_build_bottom_left()
	_build_bottom_right()
	_build_interact_prompt()
	_build_banners()
	_build_boss_bar()

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

# ---------------------------------------------------------------- Regions

## Ports HUD.ts's dangerVignette/corruptionVignette — both are `position:
## absolute; inset: 0` full-screen radial gradients (transparent center,
## opaque-colored edge; style.css lines ~796-817), appended to the source's
## own .hud root BEFORE every other element there, so both are built here
## first too — ahead of every other _build_*() call in _ready() — to match
## that same "paints below everything else" stacking. Corruption is added
## before danger (matching the source's own append order: corruption then
## danger) so danger paints on top where the two would ever overlap.
func _build_vignettes() -> void:
	_corruption_vignette = _make_vignette(CORRUPTION_VIGNETTE_STOP, Color(Palette.SHADOW, 0.85))
	add_child(_corruption_vignette)
	_danger_vignette = _make_vignette(DANGER_VIGNETTE_STOP, DANGER_VIGNETTE_COLOR)
	add_child(_danger_vignette)

## Builds one full-rect TextureRect showing a radial gradient from fully
## transparent (out to `stop_offset`, a 0..1 fraction of the ellipse's own
## radius) to `end_color` (opaque) at the ellipse's edge — a real Gradient/
## GradientTexture2D pair rather than a _draw() call: this file's usual
## hand-drawn approach elsewhere in this project has no radial-gradient-
## fill primitive of its own either, so _draw() would buy nothing here that
## GradientTexture2D doesn't already do more directly (this project's own
## header flagged "no cheap radial-gradient-on-a-flat-Control primitive" as
## the very reason this was deferred — GradientTexture2D turned out to BE
## that primitive, just not a flat-Control one).
##
## GradientTexture2D.FILL_RADIAL treats fill_from/fill_to as a CIRCLE in the
## texture's own square UV space (0..1 on both axes); stretching that
## square non-uniformly to fill this control's actual (non-square) box —
## via stretch_mode = STRETCH_SCALE below — is exactly what turns that
## circle into an ELLIPSE matching the box's own aspect ratio, same as the
## source's `ellipse` gradients. VIGNETTE_RADIUS (1/sqrt(2)) is chosen so
## that circle-in-UV-space passes exactly through the UV square's own
## corner, which — worked out on paper, not guessed, since a wrong radius
## here is a full-screen visual bug with no easy tell other than comparing
## very carefully against the source — reproduces the source's own default
## `farthest-corner` sizing keyword exactly: both reduce to the same
## "ellipse scaled by sqrt(2) so it passes through the box's corner" shape.
func _make_vignette(stop_offset: float, end_color: Color) -> TextureRect:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([stop_offset, 1.0])
	gradient.colors = PackedColorArray([
		Color(end_color.r, end_color.g, end_color.b, 0.0), end_color,
	])

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 128
	texture.height = 128
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5 + VIGNETTE_RADIUS, 0.5)

	var rect := TextureRect.new()
	rect.texture = texture
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.modulate.a = 0.0
	return rect

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

	# Not nested inside `col` above (unlike every other top-right element) —
	# HudMinimap positions/sizes itself independently every refresh() (a
	# variable-sized box scaled to fit, anchored to Hud's own top-right
	# corner), which a Container parent would fight over sizing authority
	# with; a plain Control sibling avoids that question entirely.
	_minimap = HudMinimap.new()
	add_child(_minimap)

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
	_interact_label.visible = false
	add_child(_interact_label)

func _build_banners() -> void:
	_toast_area = VBoxContainer.new()
	_toast_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_area.alignment = BoxContainer.ALIGNMENT_CENTER
	_toast_area.add_theme_constant_override("separation", 6)
	_toast_area.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_area.offset_top = 90.0
	_toast_area.offset_left = -210.0
	_toast_area.offset_right = 210.0
	add_child(_toast_area)

	# CSS positions this at top:38% (then transforms -50%/-50% to center ON
	# that point) — a fixed anchor FRACTION, not a fixed pixel offset, so it
	# lands at the same relative spot regardless of viewport size. Godot has
	# no single named preset for "horizontal-center, vertical-at-a-custom-
	# fraction," so anchor_top/anchor_bottom are set directly instead of via
	# set_anchors_preset(); offsets then add a fixed-size box around that
	# anchor point, same as every other region in this file.
	_phase_banner = Label.new()
	_phase_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_phase_banner.add_theme_font_size_override("font_size", 32)
	_phase_banner.add_theme_color_override("font_color", Color(Palette.EMBER5))
	_phase_banner.anchor_left = 0.5
	_phase_banner.anchor_right = 0.5
	_phase_banner.anchor_top = 0.38
	_phase_banner.anchor_bottom = 0.38
	_phase_banner.offset_left = -300.0
	_phase_banner.offset_right = 300.0
	_phase_banner.offset_top = -22.0
	_phase_banner.offset_bottom = 22.0
	_phase_banner.pivot_offset = Vector2(300.0, 22.0)
	_phase_banner.modulate.a = 0.0
	_phase_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_phase_banner)

	_synergy_banner = PanelContainer.new()
	_synergy_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_synergy_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_synergy_banner.offset_top = SYNERGY_BANNER_REST_TOP
	_synergy_banner.offset_bottom = SYNERGY_BANNER_REST_TOP + 90.0
	_synergy_banner.offset_left = -170.0
	_synergy_banner.offset_right = 170.0
	var synergy_style := StyleBoxFlat.new()
	synergy_style.bg_color = Color(Palette.PANEL_SOLID)
	synergy_style.border_color = Color(Palette.SOUL)
	synergy_style.set_border_width_all(1)
	synergy_style.set_corner_radius_all(10)
	synergy_style.content_margin_left = 26.0
	synergy_style.content_margin_right = 26.0
	synergy_style.content_margin_top = 10.0
	synergy_style.content_margin_bottom = 10.0
	synergy_style.shadow_color = Color(Palette.SOUL_DIM)
	synergy_style.shadow_color.a = 0.35
	synergy_style.shadow_size = 14
	_synergy_banner.add_theme_stylebox_override("panel", synergy_style)
	_synergy_banner.modulate.a = 0.0
	add_child(_synergy_banner)

	var synergy_col := VBoxContainer.new()
	synergy_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	synergy_col.alignment = BoxContainer.ALIGNMENT_CENTER
	synergy_col.add_theme_constant_override("separation", 2)
	_synergy_banner.add_child(synergy_col)
	var synergy_label := Label.new()
	synergy_label.text = "Synergy Formed"
	synergy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	synergy_label.add_theme_font_size_override("font_size", 10)
	synergy_label.add_theme_color_override("font_color", Color(Palette.SOUL_BRIGHT))
	synergy_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	synergy_col.add_child(synergy_label)
	_synergy_name_label = Label.new()
	_synergy_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_synergy_name_label.add_theme_font_size_override("font_size", 17)
	_synergy_name_label.add_theme_color_override("font_color", Color(Palette.SOUL_BRIGHT))
	_synergy_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	synergy_col.add_child(_synergy_name_label)
	_synergy_desc_label = Label.new()
	_synergy_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_synergy_desc_label.add_theme_font_size_override("font_size", 11)
	_synergy_desc_label.add_theme_color_override("font_color", Color(Palette.TEXT_DIM))
	_synergy_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_synergy_desc_label.custom_minimum_size = Vector2(280.0, 0.0)
	_synergy_desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	synergy_col.add_child(_synergy_desc_label)

## Ports HUD.ts's bossBar/bossName/bossFill/bossDots — a top-center readout
## shown only while data["boss"] (see update()) is non-null. Built as its
## own top-level child (like the source's own bossBar, a sibling of the
## corner regions, not nested in any of them) rather than folded into
## _build_banners(): it isn't a triggered feedback moment like a toast/
## banner, it's a persistent status readout for as long as a boss room is
## active, closer in kind to the HP/stamina/energy bars.
##
## The fill reuses _set_bar_ratio's own anchor_right convention (every
## other bar in this file already works this way) rather than the source's
## own `transform: scaleX(...)` — same substitution, same reason, as every
## other bar here.
func _build_boss_bar() -> void:
	_boss_bar = VBoxContainer.new()
	_boss_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_bar.add_theme_constant_override("separation", 6)
	_boss_bar.anchor_left = 0.5
	_boss_bar.anchor_right = 0.5
	_boss_bar.offset_left = -280.0
	_boss_bar.offset_right = 280.0
	_boss_bar.offset_top = 18.0
	_boss_bar.offset_bottom = 18.0 + 44.0
	_boss_bar.visible = false
	add_child(_boss_bar)

	_boss_name_label = Label.new()
	_boss_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_name_label.add_theme_font_size_override("font_size", 15)
	_boss_name_label.add_theme_color_override("font_color", Color(Palette.EMBER5))
	_boss_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_bar.add_child(_boss_name_label)

	var track := Control.new()
	track.custom_minimum_size = Vector2(0.0, 16.0)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_bar.add_child(track)
	var bg := ColorRect.new()
	bg.color = BAR_TRACK_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(bg)
	_boss_fill = ColorRect.new()
	_boss_fill.color = Color(Palette.BLOOD_BRIGHT)
	_boss_fill.anchor_left = 0.0
	_boss_fill.anchor_top = 0.0
	_boss_fill.anchor_right = 0.0
	_boss_fill.anchor_bottom = 1.0
	_boss_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(_boss_fill)

	_boss_dots_row = HBoxContainer.new()
	_boss_dots_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_dots_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_boss_dots_row.add_theme_constant_override("separation", 6)
	_boss_bar.add_child(_boss_dots_row)

# ---------------------------------------------------------------- Toasts / banners

## Ports HUD.ts's showToast — appends a new toast (unlike the banners
## below, several can be stacked/visible at once) that holds for
## `duration` seconds then fades over 0.4s and frees itself. No entrance
## animation, matching the source (a toast just appears — only its exit is
## animated there too).
func show_toast(text: String, duration: float = 4.2) -> void:
	var toast := PanelContainer.new()
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(Palette.PANEL_SOLID)
	style.border_color = Color(Palette.BORDER_LIT)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	toast.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(Palette.TEXT_DIM))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.add_child(label)
	_toast_area.add_child(toast)

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_interval(duration)
	tween.tween_property(toast, "modulate:a", 0.0, 0.4).set_trans(Tween.TRANS_LINEAR)
	tween.tween_callback(func():
		_toast_area.remove_child(toast)
		toast.queue_free()
	)

## Ports HUD.ts's showPhaseBanner — one reused element (not stacked); a
## call while a previous banner is still animating kills that tween and
## restarts fresh with the new text, mirroring the source's own remove/
## reflow/re-add-'showing'-class restart trick. Timing/keyframes read off
## style.css's own `phaseBanner` animation (2.6s: 0-15% fade+scale in,
## 15-80% hold, 80-100% fade+drift out) — Tween chaining maps onto CSS
## keyframe percentages directly, which is the whole reason this uses
## Tween rather than this file's usual manual _process() interpolation
## (see this file's own header).
func show_phase_banner(text: String) -> void:
	if _phase_banner_tween != null and _phase_banner_tween.is_valid():
		_phase_banner_tween.kill()
	_phase_banner.text = text
	_phase_banner.modulate.a = 0.0
	_phase_banner.scale = Vector2(0.9, 0.9)
	_phase_banner.offset_top = -22.0
	_phase_banner.offset_bottom = 22.0

	# Animates offset_top/offset_bottom together (not .position) for the
	# exit drift — .position is the Control's ABSOLUTE placement in its
	# parent, computed ONCE from anchors+offsets; overwriting it directly
	# discards that computed (horizontally-centered) placement entirely
	# rather than nudging it, which is what actually happened the first
	# time this was tried (confirmed via a real screenshot: the banner
	# jumped to the parent's literal top-left corner). offset_top/bottom
	# stay relative to the anchor the whole time, so moving both by the
	# same delta shifts the box without fighting the anchor system.
	# `.parallel()` called as its own statement right before a tweener marks
	# ONLY that one tweener as starting alongside the PREVIOUS one — unlike
	# the stickier set_parallel(true)/chain() combination, which turned out
	# NOT to behave as documented here (verified empirically: a tweener
	# added after chain().tween_interval(...) fired at the same time as the
	# FIRST parallel tweener several steps earlier, not after the interval
	# — the "hold" collapsed to ~0s and the banner vanished almost as soon
	# as it appeared). Every entry below with no `.parallel()` before it
	# waits for everything before it, same as plain sequential Tween use.
	_phase_banner_tween = create_tween()
	_phase_banner_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_phase_banner_tween.tween_property(_phase_banner, "modulate:a", 1.0, 0.39).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_phase_banner_tween.parallel()
	_phase_banner_tween.tween_property(_phase_banner, "scale", Vector2.ONE, 0.39).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_phase_banner_tween.tween_interval(1.69)
	_phase_banner_tween.tween_property(_phase_banner, "modulate:a", 0.0, 0.52).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_phase_banner_tween.parallel()
	_phase_banner_tween.tween_property(_phase_banner, "scale", Vector2(1.05, 1.05), 0.52).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_phase_banner_tween.parallel()
	_phase_banner_tween.tween_property(_phase_banner, "offset_top", -32.0, 0.52).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_phase_banner_tween.parallel()
	_phase_banner_tween.tween_property(_phase_banner, "offset_bottom", 12.0, 0.52).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)

## Ports HUD.ts's showSynergyBanner — same single-reused-element restart
## pattern as show_phase_banner, timing read off style.css's own
## `synergyBanner` animation (4.2s: 0-10% fade+slide in, 10-85% hold,
## 85-100% fade+slide out further).
func show_synergy_banner(synergy_name: String, description: String) -> void:
	if _synergy_banner_tween != null and _synergy_banner_tween.is_valid():
		_synergy_banner_tween.kill()
	_synergy_name_label.text = synergy_name
	_synergy_desc_label.text = description
	_synergy_banner.modulate.a = 0.0
	_synergy_banner.offset_top = SYNERGY_BANNER_REST_TOP - 20.0
	_synergy_banner.offset_bottom = SYNERGY_BANNER_REST_TOP - 20.0 + 90.0

	# offset_top/offset_bottom animate together (not .position — see
	# show_phase_banner's own comment on why) so the 90px box height stays
	# fixed while the whole thing slides.
	# See show_phase_banner's own comment: .parallel() called as its own
	# statement before each tweener (not the sticky set_parallel(true)/
	# chain() pair) is what actually gives correct sequential/parallel
	# timing here.
	_synergy_banner_tween = create_tween()
	_synergy_banner_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_synergy_banner_tween.tween_property(_synergy_banner, "modulate:a", 1.0, 0.42).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_synergy_banner_tween.parallel()
	_synergy_banner_tween.tween_property(_synergy_banner, "offset_top", SYNERGY_BANNER_REST_TOP, 0.42).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_synergy_banner_tween.parallel()
	_synergy_banner_tween.tween_property(_synergy_banner, "offset_bottom", SYNERGY_BANNER_REST_TOP + 90.0, 0.42).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_synergy_banner_tween.tween_interval(3.15)
	_synergy_banner_tween.tween_property(_synergy_banner, "modulate:a", 0.0, 0.63).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	_synergy_banner_tween.parallel()
	_synergy_banner_tween.tween_property(_synergy_banner, "offset_top", SYNERGY_BANNER_REST_TOP - 12.0, 0.63).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	_synergy_banner_tween.parallel()
	_synergy_banner_tween.tween_property(_synergy_banner, "offset_bottom", SYNERGY_BANNER_REST_TOP - 12.0 + 90.0, 0.63).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)

## Ports HUD.ts's refreshMinimap — a passthrough to HudMinimap's own
## refresh(), called from LevelFlow whenever room_changed fires (run
## start, any same-zone room entry, or a zone transition landing) rather
## than every frame from update() below — the source calls it from the
## same handful of "the room graph's discovered state actually changed"
## moments, not its own per-frame render loop either.
func refresh_minimap(layout: Dictionary, current_room_key: String) -> void:
	_minimap.refresh(layout, current_room_key)

# ---------------------------------------------------------------- Update

## `data` keys mirror HUD.ts's HudFrameData (staminaDenied/elapsedSeconds
## spelled snake_case): player, embers, zone_name, room_label, corruption,
## weapon_name, ability_name, weapon_icon, ability_icon, interact_prompt
## (String, "" = none), elapsed_seconds, stamina_denied, player_level, xp,
## xp_to_next, stat_points, is_max_level, boss (Dictionary matching
## BossHudInfo's own shape — name/hp_ratio/phase/max_phase/invulnerable —
## or null when the current room isn't a boss room; see main.gd's own
## _boss_hud_data()).
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

	# Danger vignette: opacity climbs as hp_ratio drops below DANGER_START,
	# capped at DANGER_MAX_OPACITY; below CRITICAL_START it pulses instead —
	# a raised cosine standing in for the source's own dangerPulse keyframes
	# (high at 0%/100%, low at 50%, which a raised cosine already is exactly,
	# so there's no real fidelity gap versus porting the keyframes property-
	# by-property) and, matching a CSS animation overriding its element's
	# inline opacity while playing, ignores the plain HP-driven value
	# entirely rather than blending with it. No smoothing on either branch,
	# same as every other bar in this file (_set_bar_ratio has none either)
	# — skips the source's own `transition: opacity` easing as a deliberate,
	# consistent simplification rather than an oversight.
	var danger_opacity: float = 0.0
	if player.alive:
		danger_opacity = clampf((DANGER_START - hp_ratio) / DANGER_START, 0.0, 1.0) * DANGER_MAX_OPACITY
	if player.alive and hp_ratio > 0.0 and hp_ratio <= CRITICAL_START:
		var pulse_t: float = fmod(float(data["elapsed_seconds"]), DANGER_PULSE_PERIOD) / DANGER_PULSE_PERIOD
		var pulse_wave: float = (cos(pulse_t * TAU) + 1.0) / 2.0
		danger_opacity = DANGER_PULSE_LOW + (DANGER_PULSE_HIGH - DANGER_PULSE_LOW) * pulse_wave
	_danger_vignette.modulate.a = danger_opacity
	_corruption_vignette.modulate.a = clampf(float(data["corruption"]), 0.0, 1.0) * CORRUPTION_VIGNETTE_MAX_OPACITY

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
	_timer_label.text = format_time(float(data["elapsed_seconds"]))
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
	else:
		_interact_label.visible = false

	# Dots rebuilt every call rather than diffed — same "just requeue the
	# children" convention as _shield_row/_buff_row above; max_phase never
	# actually changes mid-fight in practice (always 3, the boss's own only
	# caller), so this isn't the hot churn it would be for something that
	# resizes every frame.
	var boss_data = data.get("boss")
	if boss_data != null:
		_boss_bar.visible = true
		_boss_name_label.text = boss_data["name"]
		_set_bar_ratio(_boss_fill, boss_data["hp_ratio"])
		for child in _boss_dots_row.get_children():
			child.queue_free()
		var max_phase: int = boss_data["max_phase"]
		var boss_phase: int = boss_data["phase"]
		for i in range(max_phase):
			var dot := ColorRect.new()
			dot.custom_minimum_size = Vector2(7.0, 7.0)
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			# Dots represent phases REMAINING, depleting left-to-right —
			# ports HUD.ts's own `i < maxPhase - phase + 1` exactly (phase 1
			# lights every dot, phase 3 of 3 lights only the last one).
			var active: bool = i < max_phase - boss_phase + 1
			dot.color = Color(Palette.BLOOD_BRIGHT) if active else Color(Palette.BG3)
			_boss_dots_row.add_child(dot)
	else:
		_boss_bar.visible = false

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
static func format_time(seconds: float) -> String:
	var total: int = int(seconds)
	var m: int = total / 60
	var s: int = total % 60
	return "%d:%02d" % [m, s]
