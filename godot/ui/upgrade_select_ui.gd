class_name UpgradeSelectUI
extends Control
## Ports ui/UpgradeSelectUI.ts — the 3-choice upgrade picker shown on a
## cleared room. A true modal: pauses the whole SceneTree (mirrors the TS
## source's own updatePlaying() early-out while `modalScreen` is set, so
## nothing keeps fighting/moving underneath it) via `get_tree().paused`,
## with this control's own `process_mode` set to ALWAYS so its subtree
## (every child inherits PROCESS_MODE_INHERIT by default) keeps receiving
## clicks while everything else freezes.

signal chosen(def: UpgradeDefinition)

const CARD_SPACING := 16.0
## Sized to fit 3 UpgradeCard.CARD_SIZE-wide cards plus 2 gaps plus the
## panel's own content margin below (3*220 + 2*16 + 2*20 = 732, so 400
## half-width leaves headroom rather than an exact fit).
const PANEL_HALF_WIDTH := 400.0
const PANEL_HALF_HEIGHT := 200.0
const PANEL_CONTENT_MARGIN := 20.0

## Spawns the picker as a child of `parent`, pauses the tree, and calls
## `on_choose(def)` once the player picks a card — after which the picker
## tears itself down and unpauses. `choices`/`levels` are parallel arrays
## (index i's level is choices[i]'s upcoming level).
static func show_choices(parent: Node, choices: Array[UpgradeDefinition], levels: Array[int], on_choose: Callable) -> void:
	var ui := UpgradeSelectUI.new()
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(ui)
	ui.chosen.connect(func(def: UpgradeDefinition):
		AudioEngine.play_sfx("upgradeChoose")
		ui.get_tree().paused = false
		ui.queue_free()
		on_choose.call(def)
	)
	ui._build(choices, levels)
	ui.get_tree().paused = true

func _build(choices: Array[UpgradeDefinition], levels: Array[int]) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.016, 0.03, 0.72)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	# Ports the source's own ".screen-panel.wide.panel" — a real background/
	# border/shadow behind the title+cards, not just the dimmed backdrop
	# above (originally missed when this screen was first built; UpgradeCard's
	# own opaque background made the gap easy to miss without a real panel
	# for comparison, until ShopUI needed the same ".panel" treatment and
	# the source comparison made the gap obvious).
	var panel_bg := PanelContainer.new()
	panel_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel_bg.set_anchors_preset(Control.PRESET_CENTER)
	panel_bg.offset_left = -PANEL_HALF_WIDTH
	panel_bg.offset_right = PANEL_HALF_WIDTH
	panel_bg.offset_top = -PANEL_HALF_HEIGHT
	panel_bg.offset_bottom = PANEL_HALF_HEIGHT
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(Palette.PANEL_SOLID)
	panel_style.border_color = Color(Palette.BORDER)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(16)
	panel_style.set_content_margin_all(PANEL_CONTENT_MARGIN)
	panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	panel_style.shadow_size = 16
	panel_bg.add_theme_stylebox_override("panel", panel_style)
	add_child(panel_bg)

	var panel := VBoxContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_constant_override("separation", 16)
	panel_bg.add_child(panel)

	var title := Label.new()
	title.text = I18n.t("upgradeSelect.title", "A Blessing Awaits")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(Palette.EMBER6))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(title)

	var subtitle := Label.new()
	subtitle.text = I18n.t("upgradeSelect.subtitle", "Choose one. The Ember remembers every choice.")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color(Palette.TEXT_DIM))
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(subtitle)

	var cards_row := HBoxContainer.new()
	cards_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cards_row.add_theme_constant_override("separation", int(CARD_SPACING))
	panel.add_child(cards_row)

	for i in range(choices.size()):
		var card := UpgradeCard.new()
		card.def = choices[i]
		card.level = levels[i]
		var rarity_key: String = UpgradeDefinition.Rarity.keys()[choices[i].rarity].to_lower()
		card.first_tag_text = I18n.t("rarity.%s" % rarity_key, rarity_key)
		card.clickable = true
		cards_row.add_child(card)
		card.chosen.connect(func(def: UpgradeDefinition): chosen.emit(def))
