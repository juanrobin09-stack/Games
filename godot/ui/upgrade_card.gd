class_name UpgradeCard
extends Control
## Ports ui/UpgradeSelectUI.ts's per-card markup (`.upgrade-card`) plus
## ui/RewardPopup.ts's near-identical card — the two only differ in
## `first_tag_text` (a rarity name vs. a reward-source label like "Chest
## Reward") and whether the card is `clickable`, so one class serves both
## rather than duplicating the layout. Background/border drawn directly via
## _draw() (this project's usual "no Theme resource" convention — see
## hud.gd's own header) instead of nested ColorRects, since a card needs an
## unfilled (outline-only) border the ColorRect-stack trick can't give
## without a third nested node.

signal chosen(def: UpgradeDefinition)

const CARD_SIZE := Vector2(220.0, 210.0)
## Same width (InventoryUI's Build-tab grid still wants uniform columns),
## shorter height — without a tags row there's ~55px less content to fit,
## and the full CARD_SIZE would just leave that much dead space at the
## bottom of every card (confirmed via a real screenshot before this).
const CARD_SIZE_NO_TAGS := Vector2(220.0, 155.0)
const PADDING := 12.0
const ICON_BADGE_SIZE := 40.0
const CONTENT_SEPARATION := 8.0

var def: UpgradeDefinition = null
var level: int = 1
var first_tag_text: String = ""
var clickable: bool = true
## InventoryUI's Build tab reuses this card for owned upgrades but, like
## the source's own Build-tab card markup, shows no tags row at all (no
## rarity/level pills) — level is already in the name line there.
var show_tags: bool = true

var _hovering: bool = false

func _ready() -> void:
	var effective_size: Vector2 = CARD_SIZE if show_tags else CARD_SIZE_NO_TAGS
	custom_minimum_size = effective_size
	size = effective_size
	# UpgradeSelectUI lays its 3 cards out in an HBoxContainer, and
	# InventoryUI's Build tab lays owned-upgrade cards out in a GridContainer
	# -- both stretch a plain Control to match the tallest cell in its row by
	# default (size_flags_vertical's default is SIZE_FILL). Without this, a
	# row with one long-description card would silently stretch every OTHER
	# card in it to match, leaving them full of dead space below their own
	# (correctly short) content.
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	mouse_filter = Control.MOUSE_FILTER_STOP if clickable else Control.MOUSE_FILTER_IGNORE
	if clickable:
		mouse_entered.connect(func(): _hovering = true; queue_redraw())
		mouse_exited.connect(func(): _hovering = false; queue_redraw())
	_build_content(effective_size)

func _rarity_color() -> Color:
	return Color(Palette.rarity_color(def.rarity)) if def != null else Color(Palette.BORDER)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(Palette.BG1), true)
	var border_color := _rarity_color()
	if _hovering:
		border_color = border_color.lightened(0.15)
	draw_rect(Rect2(Vector2.ZERO, size), border_color, false, 3.0 if _hovering else 2.0)

func _gui_input(event: InputEvent) -> void:
	if not clickable or def == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		chosen.emit(def)

## Font.get_multiline_string_size() reports the exact size TextServer wraps
## `text` into at `width` -- the same word-break a Label with
## autowrap_mode = AUTOWRAP_WORD uses to draw it. A Label's own
## get_minimum_size() can't be used for this instead: it reflects whatever
## width the Label happened to have on its LAST layout pass, not the width
## it's about to be given, so sizing a container off it under-counts a long
## description's true height every time.
##
## That raw font metric alone still under-counts a multi-line result, though:
## Label inserts its own "line_spacing" theme constant BETWEEN wrapped lines
## on top of the font's own line height, which get_multiline_string_size()
## (a Font-level call with no notion of any particular Label's theme) never
## adds. Invisible for a 1-2 line name/short description; a several-line
## description like Hemorrhage's loses a handful of pixels per extra line,
## which is exactly the gap that let its tags row peek past the card's
## bottom edge even after the base height fix.
static func _wrapped_height(label: Label, text: String, width: float) -> float:
	var font: Font = label.get_theme_font("font")
	var font_size: int = label.get_theme_font_size("font_size")
	var base: float = font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size).y
	var line_height: float = font.get_height(font_size)
	var line_count: float = 1.0 if line_height <= 0.0 else roundf(base / line_height)
	var line_spacing: float = label.get_theme_constant("line_spacing")
	return base + maxf(0.0, line_count - 1.0) * line_spacing

func _build_content(effective_size: Vector2) -> void:
	if def == null:
		return
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", int(CONTENT_SEPARATION))
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = PADDING
	col.offset_top = PADDING
	col.offset_right = -PADDING
	col.offset_bottom = -PADDING
	add_child(col)

	var badge := Control.new()
	badge.custom_minimum_size = Vector2(ICON_BADGE_SIZE, ICON_BADGE_SIZE)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(badge)
	var badge_bg := ColorRect.new()
	badge_bg.color = Color(Palette.BG2)
	badge_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	badge_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(badge_bg)
	var icon := HudIcon.new()
	icon.icon_id = def.icon
	icon.icon_color = _rarity_color()
	icon.position = Vector2(9.0, 9.0)
	icon.size = Vector2(22.0, 22.0)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(icon)

	var name_label := Label.new()
	# The tags row below normally carries "Level N" as its own pill; when
	# it's suppressed (show_tags = false), fold that into the name line
	# instead — matches the source's Build-tab card, whose name text is
	# `${name} — Level ${stacks}` with no separate tags row at all.
	var display_name: String = I18n.tc(def.id, "name", def.name)
	name_label.text = display_name if show_tags else "%s — %s %d" % [display_name, I18n.t("upgrade.level", "Level"), level]
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", _rarity_color())
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = I18n.tc(def.id, "description", def.description)
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.add_theme_color_override("font_color", Color(Palette.TEXT_DIM))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(desc_label)

	var tags_row: HBoxContainer = null
	if show_tags:
		tags_row = HBoxContainer.new()
		tags_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tags_row.add_theme_constant_override("separation", 6)
		col.add_child(tags_row)
		if first_tag_text != "":
			tags_row.add_child(_make_tag(first_tag_text, _rarity_color()))
		tags_row.add_child(_make_tag("%s %d" % [I18n.t("upgrade.level", "Level"), level], Color(Palette.TEXT_DIM)))

	# The description is the one field with genuinely unbounded length; grow
	# the card just enough to fit its wrapped text (and the wrapped name,
	# for symmetry) instead of letting either spill past the frame _draw()
	# paints at `size` -- Controls don't clip their own children by default,
	# so an under-sized box doesn't hide overflow, it lets it bleed onto
	# whatever is behind the card. maxf() is a no-op for every card whose
	# content already fits CARD_SIZE/CARD_SIZE_NO_TAGS, so short
	# descriptions render pixel-identical to before.
	var content_width: float = effective_size.x - PADDING * 2.0
	var gaps: int = 3 if show_tags else 2
	var content_height: float = ICON_BADGE_SIZE + CONTENT_SEPARATION * gaps \
		+ _wrapped_height(name_label, name_label.text, content_width) \
		+ _wrapped_height(desc_label, desc_label.text, content_width)
	if tags_row != null:
		content_height += tags_row.get_combined_minimum_size().y
	var final_size := Vector2(effective_size.x, maxf(effective_size.y, ceil(content_height + PADDING * 2.0)))
	custom_minimum_size = final_size
	size = final_size

func _make_tag(text: String, color: Color) -> Control:
	var wrap := PanelContainer.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(Palette.BG2)
	bg.set_border_width_all(1)
	bg.border_color = color
	bg.set_content_margin_all(4.0)
	bg.content_margin_left = 6.0
	bg.content_margin_right = 6.0
	wrap.add_theme_stylebox_override("panel", bg)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(label)
	return wrap
