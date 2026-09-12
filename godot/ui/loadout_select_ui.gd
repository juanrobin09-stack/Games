class_name LoadoutSelectUI
extends Control
## Ports ui/LoadoutSelectUI.ts — the pre-run weapon/ability picker. Only
## ever shown when there's an actual choice to make (main.gd's own
## _begin_run ports Game.ts's startNewRun gate: `weapons.size() > 1 or
## abilities.size() > 1`); otherwise the run begins with the single
## starting kit automatically and this screen never appears.
##
## Meta-shell screen like MainMenu (opaque MenuUiKit.make_overlay, no
## tree-pause) — shown right after the fresh room and HUD already exist
## underneath (mirrors Game.ts's own startNewRun ordering: room/HUD/player
## are all built before the loadout choice is ever asked), so only this
## screen's own opaque backdrop hides them until Begin is pressed.

var _weapon_id: String
var _ability_id: String
var _unlocked_weapons: Array[String]
var _unlocked_abilities: Array[String]
var _weapon_row: HBoxContainer
var _ability_row: HBoxContainer
var _on_confirm: Callable

## `on_confirm` is called once, as on_confirm(weapon_id, ability_id), when
## Begin is pressed — mirrors LoadoutCallbacks.onConfirm exactly. Does not
## tear itself down (matches every other MenuUiKit-family screen here);
## the caller's own on_confirm is expected to close it, same as
## _show_settings/_show_credits already do via main.gd's _current_screen.
static func show_loadout(parent: Node, unlocked_weapons: Array[String], unlocked_abilities: Array[String], on_confirm: Callable) -> LoadoutSelectUI:
	var ui := LoadoutSelectUI.new()
	ui._unlocked_weapons = unlocked_weapons
	ui._unlocked_abilities = unlocked_abilities
	ui._weapon_id = unlocked_weapons[0] if not unlocked_weapons.is_empty() else "emberBlade"
	ui._ability_id = unlocked_abilities[0] if not unlocked_abilities.is_empty() else "emberBurst"
	ui._on_confirm = on_confirm
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

	content.add_child(MenuUiKit.make_title(I18n.t("loadout.title", "Choose Your Loadout")))

	content.add_child(MenuUiKit.make_subtitle(I18n.t("loadout.weapon", "Weapon")))
	_weapon_row = HBoxContainer.new()
	_weapon_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weapon_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_weapon_row.add_theme_constant_override("separation", 12)
	content.add_child(_weapon_row)

	content.add_child(MenuUiKit.make_subtitle(I18n.t("loadout.ability", "Ability")))
	_ability_row = HBoxContainer.new()
	_ability_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ability_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_ability_row.add_theme_constant_override("separation", 12)
	content.add_child(_ability_row)

	var button_row := MenuUiKit.make_button_row()
	var begin_btn := MenuUiKit.make_button(I18n.t("loadout.begin", "Begin"), MenuUiKit.ButtonVariant.PRIMARY)
	begin_btn.pressed.connect(func():
		if _on_confirm.is_valid():
			_on_confirm.call(_weapon_id, _ability_id)
	)
	button_row.add_child(begin_btn)
	content.add_child(button_row)

	add_child(MenuUiKit.make_panel(content, true))
	_render_weapons()
	_render_abilities()

func _render_weapons() -> void:
	for child in _weapon_row.get_children():
		_weapon_row.remove_child(child)
		child.queue_free()
	for id in _unlocked_weapons:
		var def := DataRegistry.get_weapon(id)
		if def == null:
			continue
		var picked_id := id
		_weapon_row.add_child(_make_card("blade", I18n.tc(id, "name", def.name), I18n.tc(id, "description", def.description), id == _weapon_id, func():
			_weapon_id = picked_id
			_render_weapons()
		))

func _render_abilities() -> void:
	for child in _ability_row.get_children():
		_ability_row.remove_child(child)
		child.queue_free()
	for id in _unlocked_abilities:
		var def := DataRegistry.get_ability(id)
		if def == null:
			continue
		var picked_id := id
		_ability_row.add_child(_make_card("ability", I18n.tc(id, "name", def.name), I18n.tc(id, "description", def.description), id == _ability_id, func():
			_ability_id = picked_id
			_render_abilities()
		))

## Ports `.upgrade-card`'s markup for a selectable weapon/ability choice —
## kept local rather than reusing UpgradeCard (that class is typed
## directly to UpgradeDefinition's own rarity/icon/name/description
## fields; Weapon/AbilityDefinition share none of that shape). Background/
## border via a PanelContainer StyleBoxFlat plus a gui_input connection
## for the click, same convention as every other card/row builder in this
## project (ShopUI's offer rows, InventoryUI's meta rows) rather than
## UpgradeCard's own bespoke _draw()+_gui_input override.
func _make_card(icon_id: String, name_text: String, desc_text: String, selected: bool, on_pick: Callable) -> Control:
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.custom_minimum_size = Vector2(220.0, 130.0)
	var accent: Color = Color(Palette.EMBER4) if selected else Color(Palette.BORDER)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(Palette.BG1)
	style.border_color = accent
	style.set_border_width_all(2 if selected else 1)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(14.0)
	if selected:
		style.shadow_color = Color(Palette.EMBER3, 0.35)
		style.shadow_size = 10
	card.add_theme_stylebox_override("panel", style)
	card.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			on_pick.call()
	)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 8)
	card.add_child(col)

	var badge := Control.new()
	badge.custom_minimum_size = Vector2(36.0, 36.0)
	# VBoxContainer stretches a plain child to its own full width along the
	# cross axis by default (the same gotcha MainMenuUI's button column hit
	# earlier — custom_minimum_size alone doesn't prevent it); without this
	# the badge_bg below renders as a wide bar instead of a 36x36 square.
	badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(badge)
	var badge_bg := ColorRect.new()
	badge_bg.color = Color(Palette.BG2)
	badge_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	badge_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(badge_bg)
	var icon := HudIcon.new()
	icon.icon_id = icon_id
	icon.icon_color = accent
	icon.position = Vector2(7.0, 7.0)
	icon.size = Vector2(22.0, 22.0)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(icon)

	var name_label := Label.new()
	name_label.text = name_text
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", accent if selected else Color(Palette.TEXT_WARM))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = desc_text
	desc_label.add_theme_font_size_override("font_size", 11)
	desc_label.add_theme_color_override("font_color", Color(Palette.TEXT_DIM))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(desc_label)

	return card
