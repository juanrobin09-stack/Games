class_name ArmoryUI
extends Control
## Ports ui/MetaProgressionMenu.ts — the between-runs Soul Ash spend
## screen, one panel with two tabs: Upgrades (permanent stat modifiers,
## leveled via PermanentUpgradeDefinition.max_level, gated by `requires`)
## and Armory (one-shot weapon/ability/enemy/upgrade-tier unlocks via
## UnlockDefinition). Meta-shell screen like MainMenu/Settings/Credits
## (opaque MenuUiKit.make_overlay, no tree-pause — opened from MainMenu,
## before any run exists), not an in-run modal like Shop/Inventory.
##
## Row layout mirrors InventoryUI's own _make_meta_row (icon badge + name/
## desc + trailing widget) without sharing it — this project's usual
## per-file builder convention (see e.g. ShopUI/InventoryUI's own near-
## identical _make_button/_button_stylebox, each kept local rather than
## factored out).

enum Mode { UPGRADES, ARMORY }

## Ports the source's own UNLOCK_ICON lookup (MetaProgressionMenu.ts) —
## UnlockDefinition carries no icon of its own (unlike
## PermanentUpgradeDefinition), so the badge is picked from `kind` instead.
const UNLOCK_ICON := {
	UnlockDefinition.Kind.WEAPON: "blade",
	UnlockDefinition.Kind.ABILITY: "ability",
	UnlockDefinition.Kind.ENEMY: "burn",
	UnlockDefinition.Kind.UPGRADE_TIER: "luck",
}

var _mode: Mode = Mode.UPGRADES
var _on_close: Callable
var _title_label: Label
var _subtitle_label: Label
var _balance_label: Label
var _tab_row: HBoxContainer
var _list_col: VBoxContainer

static func show_armory(parent: Node, mode: Mode, on_close: Callable) -> ArmoryUI:
	var ui := ArmoryUI.new()
	ui._mode = mode
	ui._on_close = on_close
	parent.add_child(ui)
	ui._build()
	return ui

func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	add_child(MenuUiKit.make_overlay(true))

	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 12)
	content.custom_minimum_size = Vector2(640.0, 0.0)

	_title_label = MenuUiKit.make_title(_title_text())
	content.add_child(_title_label)
	_subtitle_label = MenuUiKit.make_subtitle(_subtitle_text())
	content.add_child(_subtitle_label)

	var balance_row := HBoxContainer.new()
	balance_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	balance_row.alignment = BoxContainer.ALIGNMENT_CENTER
	balance_row.add_theme_constant_override("separation", 6)
	content.add_child(balance_row)
	var balance_icon := HudIcon.new()
	balance_icon.icon_id = "luck"
	balance_icon.icon_color = Color(Palette.SOUL_BRIGHT)
	balance_icon.custom_minimum_size = Vector2(18.0, 18.0)
	balance_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	balance_row.add_child(balance_icon)
	_balance_label = Label.new()
	_balance_label.add_theme_font_size_override("font_size", 16)
	_balance_label.add_theme_color_override("font_color", Color(Palette.SOUL_BRIGHT))
	_balance_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	balance_row.add_child(_balance_label)

	_tab_row = HBoxContainer.new()
	_tab_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tab_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_tab_row.add_theme_constant_override("separation", 8)
	content.add_child(_tab_row)

	var scroll := ScrollContainer.new()
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0.0, 280.0)
	content.add_child(scroll)
	_list_col = VBoxContainer.new()
	_list_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_col.add_theme_constant_override("separation", 8)
	scroll.add_child(_list_col)

	var button_row := MenuUiKit.make_button_row()
	var back_btn := MenuUiKit.make_button("Back", MenuUiKit.ButtonVariant.PRIMARY)
	back_btn.pressed.connect(func():
		if _on_close.is_valid():
			_on_close.call()
	)
	button_row.add_child(back_btn)
	content.add_child(button_row)

	add_child(MenuUiKit.make_panel(content, true))
	_render_tabs()
	_render_list()

func _title_text() -> String:
	return "Permanent Upgrades" if _mode == Mode.UPGRADES else "Armory"

func _subtitle_text() -> String:
	return ("Spend Soul Ash gathered across fallen runs to strengthen every Warden to come."
		if _mode == Mode.UPGRADES
		else "Unlock new weapons, abilities, and threats that persist across every run.")

func _switch_mode(mode: Mode) -> void:
	if _mode == mode:
		return
	_mode = mode
	AudioEngine.play_sfx("uiClick")
	_title_label.text = _title_text()
	_subtitle_label.text = _subtitle_text()
	_render_tabs()
	_render_list()

## Rebuilds both tab buttons rather than toggling a style override in
## place — the active/inactive look is just MenuUiKit's own PRIMARY vs.
## PLAIN button variant (ports the source's `.tab-row button.active`
## exactly: filled ember vs. plain outline), and a two-button row is cheap
## enough to rebuild on every switch rather than hand-rolling a third
## button "kind".
func _render_tabs() -> void:
	for child in _tab_row.get_children():
		_tab_row.remove_child(child)
		child.queue_free()
	var upgrades_btn := MenuUiKit.make_button("Upgrades", MenuUiKit.ButtonVariant.PRIMARY if _mode == Mode.UPGRADES else MenuUiKit.ButtonVariant.PLAIN)
	upgrades_btn.pressed.connect(func(): _switch_mode(Mode.UPGRADES))
	_tab_row.add_child(upgrades_btn)
	var armory_btn := MenuUiKit.make_button("Armory", MenuUiKit.ButtonVariant.PRIMARY if _mode == Mode.ARMORY else MenuUiKit.ButtonVariant.PLAIN)
	armory_btn.pressed.connect(func(): _switch_mode(Mode.ARMORY))
	_tab_row.add_child(armory_btn)

func _render_list() -> void:
	for child in _list_col.get_children():
		_list_col.remove_child(child)
		child.queue_free()
	_balance_label.text = "%d Soul Ash" % MetaProgression.soul_ash
	if _mode == Mode.UPGRADES:
		for d in DataRegistry.all("permanent_upgrades"):
			_list_col.add_child(_make_upgrade_row(d as PermanentUpgradeDefinition))
	else:
		for d in DataRegistry.all("unlocks"):
			_list_col.add_child(_make_unlock_row(d as UnlockDefinition))

func _make_upgrade_row(def: PermanentUpgradeDefinition) -> Control:
	var level := MetaProgression.get_permanent_level(def.id)
	var cost = MetaProgression.get_permanent_cost(def.id)
	var locked: bool = def.requires != "" and MetaProgression.get_permanent_level(def.requires) == 0
	var can_buy: bool = not locked and MetaProgression.can_purchase_permanent(def.id)

	var buy_label: String
	if locked:
		buy_label = "Locked"
	elif cost == null:
		buy_label = "Max"
	else:
		buy_label = str(cost)

	var desc: String = def.description
	if locked:
		var required_def := DataRegistry.get_permanent_upgrade(def.requires)
		desc = "Requires %s" % (required_def.name if required_def != null else def.requires)

	var pips := HBoxContainer.new()
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pips.add_theme_constant_override("separation", 3)
	for i in range(def.max_level):
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(8.0, 8.0)
		pip.color = Color(Palette.EMBER4) if i < level else Color(Palette.BG3)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pips.add_child(pip)

	var buy_btn := MenuUiKit.make_button(buy_label, MenuUiKit.ButtonVariant.PLAIN)
	buy_btn.disabled = not can_buy
	buy_btn.pressed.connect(func():
		if MetaProgression.purchase_permanent(def.id):
			AudioEngine.play_sfx("shopBuy")
			_render_list()
		else:
			AudioEngine.play_sfx("shopError")
	)

	return _make_row(def.icon, def.name, desc, pips, buy_btn, locked)

func _make_unlock_row(def: UnlockDefinition) -> Control:
	var unlocked := MetaProgression.has_unlock(def.id)
	var can_buy := MetaProgression.can_purchase_unlock(def.id)

	var detail := def.description
	if def.kind == UnlockDefinition.Kind.WEAPON:
		var weapon_def := DataRegistry.get_weapon(def.ref_id)
		if weapon_def != null:
			detail = weapon_def.description
	elif def.kind == UnlockDefinition.Kind.ABILITY:
		var ability_def := DataRegistry.get_ability(def.ref_id)
		if ability_def != null:
			detail = ability_def.description

	var buy_btn := MenuUiKit.make_button("Unlocked" if unlocked else str(def.cost), MenuUiKit.ButtonVariant.PLAIN)
	buy_btn.disabled = unlocked or not can_buy
	buy_btn.pressed.connect(func():
		if MetaProgression.purchase_unlock(def.id):
			AudioEngine.play_sfx("shopBuy")
			_render_list()
		else:
			AudioEngine.play_sfx("shopError")
	)

	return _make_row(UNLOCK_ICON.get(def.kind, "blade"), def.name, detail, null, buy_btn, false)

## Ports `.meta-node`: icon badge | name+desc(+optional `extra`, e.g. the
## Upgrades tab's level pips) | trailing widget (the buy button, here —
## InventoryUI's own near-identical _make_meta_row has no `extra` slot
## since none of its callers need one).
func _make_row(icon_id: String, name_text: String, desc_text: String, extra: Control, trailing: Control, dimmed: bool) -> Control:
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(Palette.BG1)
	style.border_color = Color(Palette.BORDER)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	row.add_theme_stylebox_override("panel", style)
	if dimmed:
		row.modulate = Color(1.0, 1.0, 1.0, 0.55)

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 12)
	row.add_child(hbox)

	var badge := Control.new()
	badge.custom_minimum_size = Vector2(36.0, 36.0)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(badge)
	var badge_bg := ColorRect.new()
	badge_bg.color = Color(Palette.BG2)
	badge_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	badge_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(badge_bg)
	var icon := HudIcon.new()
	icon.icon_id = icon_id
	icon.icon_color = Color(Palette.EMBER5)
	icon.position = Vector2(8.0, 8.0)
	icon.size = Vector2(20.0, 20.0)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(icon)

	var info := VBoxContainer.new()
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 3)
	hbox.add_child(info)
	var name_label := Label.new()
	name_label.text = name_text
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", Color(Palette.TEXT_WARM))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(name_label)
	var desc_label := Label.new()
	desc_label.text = desc_text
	desc_label.add_theme_font_size_override("font_size", 11)
	desc_label.add_theme_color_override("font_color", Color(Palette.TEXT_DIM))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(desc_label)
	if extra != null:
		info.add_child(extra)

	hbox.add_child(trailing)
	return row
