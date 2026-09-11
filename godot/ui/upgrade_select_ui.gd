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
const PANEL_HALF_WIDTH := 370.0
const PANEL_HALF_HEIGHT := 190.0

## Spawns the picker as a child of `parent`, pauses the tree, and calls
## `on_choose(def)` once the player picks a card — after which the picker
## tears itself down and unpauses. `choices`/`levels` are parallel arrays
## (index i's level is choices[i]'s upcoming level).
static func show_choices(parent: Node, choices: Array[UpgradeDefinition], levels: Array[int], on_choose: Callable) -> void:
	var ui := UpgradeSelectUI.new()
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(ui)
	ui.chosen.connect(func(def: UpgradeDefinition):
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

	var panel := VBoxContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_constant_override("separation", 16)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -PANEL_HALF_WIDTH
	panel.offset_right = PANEL_HALF_WIDTH
	panel.offset_top = -PANEL_HALF_HEIGHT
	panel.offset_bottom = PANEL_HALF_HEIGHT
	add_child(panel)

	var title := Label.new()
	title.text = "A Blessing Awaits"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(Palette.EMBER6))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Choose one. The Ember remembers every choice."
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
		card.first_tag_text = UpgradeDefinition.Rarity.keys()[choices[i].rarity].to_lower()
		card.clickable = true
		cards_row.add_child(card)
		card.chosen.connect(func(def: UpgradeDefinition): chosen.emit(def))
