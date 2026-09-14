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

	add_child(MenuUiKit.make_overlay(false))

	var panel := VBoxContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_constant_override("separation", 16)

	panel.add_child(MenuUiKit.make_title(I18n.t("upgradeSelect.title", "A Blessing Awaits")))
	panel.add_child(MenuUiKit.make_subtitle(I18n.t("upgradeSelect.subtitle", "Choose one. The Ember remembers every choice.")))

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

	add_child(MenuUiKit.make_panel(panel, true))
