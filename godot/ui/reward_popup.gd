class_name RewardPopup
extends Control
## Ports ui/RewardPopup.ts — a brief, auto-dismissing reveal for a granted
## upgrade (chest rewards, event boons). Non-modal — doesn't pause, doesn't
## block input, mirrors the source's own pointer-events:none — positioned
## top-center so it doesn't sit over the HUD's own top-left/top-right bars.
##
## The single card inside is left at its own default (0,0,0,0) anchors
## (plain top-left position (0,0), the size its own _ready() sets
## directly) rather than re-anchored to fill this control, since this
## control's own box is already sized to exactly match — one less place
## for an anchor/offset interaction to go wrong.

const LIFETIME := 2.8
const PANEL_TOP_OFFSET := 90.0

var _age: float = 0.0

static func show_reward(parent: Node, def: UpgradeDefinition, source_label: String, level: int = 1) -> void:
	var popup := RewardPopup.new()
	parent.add_child(popup)
	popup._build(def, source_label, level)

func _build(def: UpgradeDefinition, source_label: String, level: int) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	offset_left = -UpgradeCard.CARD_SIZE.x / 2.0
	offset_right = UpgradeCard.CARD_SIZE.x / 2.0
	offset_top = PANEL_TOP_OFFSET
	offset_bottom = PANEL_TOP_OFFSET + UpgradeCard.CARD_SIZE.y

	var card := UpgradeCard.new()
	card.def = def
	card.level = level
	card.first_tag_text = source_label
	card.clickable = false
	add_child(card)

func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
