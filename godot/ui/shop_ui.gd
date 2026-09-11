class_name ShopUI
extends Control
## Ports ui/ShopUI.ts — the merchant's wares screen opened from a shop
## room's landmark. True modal, same mechanism as UpgradeSelectUI
## (get_tree().paused + this root's own process_mode ALWAYS so its subtree
## keeps taking clicks while everything else freezes).
##
## Unlike UpgradeSelectUI (one choice, then tear down), a shop stays open
## across multiple purchases/rerolls until Leave is clicked — matching the
## TS source's own render()/renderList() split, every state-changing
## action here just rebuilds the offer list instead of closing.

const PANEL_HALF_WIDTH := 450.0
const PANEL_HALF_HEIGHT := 270.0
const ICON_BADGE_SIZE := 38.0

var offers: Array[ShopOffer] = []
var _on_buy_upgrade: Callable
var _on_buy_heal: Callable
var _on_reroll: Callable

var _list_col: VBoxContainer
var _embers_label: Label
var _reroll_button: Button

## Spawns the shop as a child of `parent` and pauses the tree.
## `on_buy_upgrade`/`on_buy_heal` take a ShopOffer and return whether the
## purchase succeeded (mirrors ShopCallbacks.onBuyUpgrade/onBuyHeal);
## `on_reroll` takes nothing and returns the fresh Array[ShopOffer], or an
## empty array if the reroll couldn't be afforded (mirrors onReroll).
static func show_shop(parent: Node, offers: Array[ShopOffer], on_buy_upgrade: Callable, on_buy_heal: Callable, on_reroll: Callable) -> void:
	var ui := ShopUI.new()
	ui.offers = offers
	ui._on_buy_upgrade = on_buy_upgrade
	ui._on_buy_heal = on_buy_heal
	ui._on_reroll = on_reroll
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(ui)
	ui._build()
	ui.get_tree().paused = true

func _close() -> void:
	get_tree().paused = false
	queue_free()

func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.016, 0.031, 0.72)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var panel_bg := PanelContainer.new()
	panel_bg.mouse_filter = Control.MOUSE_FILTER_STOP
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
	panel_style.set_content_margin_all(28.0)
	panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	panel_style.shadow_size = 16
	panel_bg.add_theme_stylebox_override("panel", panel_style)
	add_child(panel_bg)

	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 14)
	panel_bg.add_child(content)

	var title := Label.new()
	title.text = "The Forgotten Merchant"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(Palette.EMBER6))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "\"Everything has a price, Warden. Choose wisely.\""
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color(Palette.TEXT_DIM))
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(subtitle)

	var embers_row := HBoxContainer.new()
	embers_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	embers_row.alignment = BoxContainer.ALIGNMENT_CENTER
	embers_row.add_theme_constant_override("separation", 6)
	content.add_child(embers_row)
	var embers_icon := HudIcon.new()
	embers_icon.icon_id = "ember"
	embers_icon.icon_color = Color(Palette.EMBER5)
	embers_icon.custom_minimum_size = Vector2(16.0, 16.0)
	embers_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	embers_row.add_child(embers_icon)
	_embers_label = Label.new()
	_embers_label.add_theme_font_size_override("font_size", 16)
	_embers_label.add_theme_color_override("font_color", Color(Palette.EMBER5))
	_embers_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	embers_row.add_child(_embers_label)

	_list_col = VBoxContainer.new()
	_list_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list_col.add_theme_constant_override("separation", 8)
	content.add_child(_list_col)

	var button_row := HBoxContainer.new()
	button_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 10)
	content.add_child(button_row)
	_reroll_button = _make_button("Reroll (%d)" % Shop.REROLL_COST, false, true)
	_reroll_button.pressed.connect(_on_reroll_pressed)
	button_row.add_child(_reroll_button)
	var leave_button := _make_button("Leave", true, false)
	leave_button.pressed.connect(_close)
	button_row.add_child(leave_button)

	_render_list()

func _render_list() -> void:
	for child in _list_col.get_children():
		_list_col.remove_child(child)
		child.queue_free()
	for offer in offers:
		_list_col.add_child(_make_offer_row(offer))
	_embers_label.text = str(RunState.embers)
	_reroll_button.disabled = RunState.embers < Shop.REROLL_COST

func _make_offer_row(offer: ShopOffer) -> Control:
	var is_upgrade: bool = offer.kind == ShopOffer.Kind.UPGRADE
	var accent: Color = Color(Palette.rarity_color(offer.upgrade.rarity)) if is_upgrade else Color(Palette.TEXT_WARM)

	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row_style := StyleBoxFlat.new()
	row_style.bg_color = Color(Palette.BG1)
	row_style.border_color = Color(Palette.BORDER)
	row_style.set_border_width_all(1)
	row_style.set_corner_radius_all(10)
	row_style.set_content_margin_all(12.0)
	row.add_theme_stylebox_override("panel", row_style)

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 12)
	row.add_child(hbox)

	var badge := Control.new()
	badge.custom_minimum_size = Vector2(ICON_BADGE_SIZE, ICON_BADGE_SIZE)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(badge)
	var badge_bg := ColorRect.new()
	badge_bg.color = Color(Palette.BG2)
	badge_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	badge_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(badge_bg)
	var icon := HudIcon.new()
	icon.icon_id = offer.upgrade.icon if is_upgrade else "heart"
	icon.icon_color = accent
	icon.position = Vector2(9.0, 9.0)
	icon.size = Vector2(20.0, 20.0)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(icon)

	var info := VBoxContainer.new()
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	hbox.add_child(info)
	var name_label := Label.new()
	name_label.text = ("%s — Level %d" % [offer.upgrade.name, offer.upgrade_level]) if is_upgrade else "Mend Your Wounds"
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", accent)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(name_label)
	var desc_label := Label.new()
	desc_label.text = offer.upgrade.description if is_upgrade else "Restore a portion of your health."
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.add_theme_color_override("font_color", Color(Palette.TEXT_DIM))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(desc_label)

	var cost_row := HBoxContainer.new()
	cost_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_row.add_theme_constant_override("separation", 4)
	hbox.add_child(cost_row)
	var cost_icon := HudIcon.new()
	cost_icon.icon_id = "ember"
	cost_icon.icon_color = Color(Palette.EMBER5)
	cost_icon.custom_minimum_size = Vector2(14.0, 14.0)
	cost_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_row.add_child(cost_icon)
	var cost_label := Label.new()
	cost_label.text = str(offer.cost)
	cost_label.add_theme_font_size_override("font_size", 13)
	cost_label.add_theme_color_override("font_color", Color(Palette.EMBER5))
	cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_row.add_child(cost_label)

	var affordable: bool = RunState.embers >= offer.cost and not offer.purchased
	var buy_btn := _make_button("Sold" if offer.purchased else "Buy", false, true)
	buy_btn.disabled = not affordable
	buy_btn.pressed.connect(func(): _buy(offer))
	hbox.add_child(buy_btn)

	return row

func _buy(offer: ShopOffer) -> void:
	var success: bool = _on_buy_upgrade.call(offer) if offer.kind == ShopOffer.Kind.UPGRADE else _on_buy_heal.call(offer)
	if success:
		offer.purchased = true
	_render_list()

func _on_reroll_pressed() -> void:
	var fresh: Array[ShopOffer] = _on_reroll.call()
	if fresh.is_empty():
		return
	offers = fresh
	_render_list()

func _button_stylebox(bg: Color, border: Color, small: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10.0 if small else 18.0
	sb.content_margin_right = sb.content_margin_left
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	return sb

## `primary` mirrors .btn.primary (the Leave button); every other button
## (Buy/Sold, Reroll) is the plain/`small` .btn.small look.
func _make_button(label_text: String, primary: bool, small: bool) -> Button:
	var btn := Button.new()
	btn.text = label_text.to_upper()
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 12 if small else 14)
	if primary:
		btn.add_theme_stylebox_override("normal", _button_stylebox(Color(Palette.EMBER3), Color(Palette.EMBER4), small))
		btn.add_theme_stylebox_override("hover", _button_stylebox(Color(Palette.EMBER4), Color(Palette.EMBER5), small))
		btn.add_theme_stylebox_override("pressed", _button_stylebox(Color(Palette.EMBER2), Color(Palette.EMBER4), small))
		btn.add_theme_stylebox_override("disabled", _button_stylebox(Color(Palette.EMBER1), Color(Palette.BORDER), small))
		btn.add_theme_color_override("font_color", Color("#180a04"))
		btn.add_theme_color_override("font_hover_color", Color("#180a04"))
		btn.add_theme_color_override("font_pressed_color", Color("#180a04"))
	else:
		btn.add_theme_stylebox_override("normal", _button_stylebox(Color(Palette.BG2), Color(Palette.BORDER), small))
		btn.add_theme_stylebox_override("hover", _button_stylebox(Color(Palette.BG3), Color(Palette.BORDER_LIT), small))
		btn.add_theme_stylebox_override("pressed", _button_stylebox(Color(Palette.BG1), Color(Palette.BORDER_LIT), small))
		btn.add_theme_stylebox_override("disabled", _button_stylebox(Color(Palette.BG1), Color(Palette.BORDER), small))
		btn.add_theme_color_override("font_color", Color(Palette.TEXT_WARM))
		btn.add_theme_color_override("font_hover_color", Color(Palette.EMBER6))
		btn.add_theme_color_override("font_pressed_color", Color(Palette.EMBER5))
	btn.add_theme_color_override("font_disabled_color", Color(Palette.TEXT_FAINT))
	return btn
