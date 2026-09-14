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

	add_child(MenuUiKit.make_overlay(false))

	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 14)

	content.add_child(MenuUiKit.make_title(I18n.t("shop.title", "The Forgotten Merchant")))
	content.add_child(MenuUiKit.make_subtitle(I18n.t("shop.subtitle", "\"Everything has a price, Warden. Choose wisely.\"")))

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

	var button_row := MenuUiKit.make_button_row()
	content.add_child(button_row)
	_reroll_button = MenuUiKit.make_button("%s (%d)" % [I18n.t("shop.reroll", "Reroll"), Shop.REROLL_COST], MenuUiKit.ButtonVariant.PLAIN)
	_reroll_button.pressed.connect(_on_reroll_pressed)
	button_row.add_child(_reroll_button)
	var leave_button := MenuUiKit.make_button(I18n.t("shop.leave", "Leave"), MenuUiKit.ButtonVariant.PRIMARY)
	leave_button.pressed.connect(_close)
	button_row.add_child(leave_button)

	add_child(MenuUiKit.make_panel(content, true))
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
	var base_name: String = I18n.tc(offer.upgrade.id, "name", offer.upgrade.name) if is_upgrade else I18n.t("shop.healName", "Mend Your Wounds")
	name_label.text = ("%s — %s %d" % [base_name, I18n.t("upgrade.level", "Level"), offer.upgrade_level]) if is_upgrade else base_name
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", accent)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(name_label)
	var desc_label := Label.new()
	desc_label.text = I18n.tc(offer.upgrade.id, "description", offer.upgrade.description) if is_upgrade else I18n.t("shop.healDesc", "Restore a portion of your health.")
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
	var buy_btn := MenuUiKit.make_button(I18n.t("shop.sold", "Sold") if offer.purchased else I18n.t("shop.buy", "Buy"), MenuUiKit.ButtonVariant.PLAIN)
	buy_btn.disabled = not affordable
	buy_btn.pressed.connect(func(): _buy(offer))
	hbox.add_child(buy_btn)

	return row

func _buy(offer: ShopOffer) -> void:
	var success: bool = _on_buy_upgrade.call(offer) if offer.kind == ShopOffer.Kind.UPGRADE else _on_buy_heal.call(offer)
	if success:
		offer.purchased = true
		AudioEngine.play_sfx("shopBuy")
	else:
		AudioEngine.play_sfx("shopError")
	_render_list()

func _on_reroll_pressed() -> void:
	var fresh: Array[ShopOffer] = _on_reroll.call()
	if fresh.is_empty():
		AudioEngine.play_sfx("shopError")
		return
	offers = fresh
	AudioEngine.play_sfx("uiClick")
	_render_list()

