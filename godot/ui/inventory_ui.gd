class_name InventoryUI
extends Control
## Ports ui/InventoryUI.ts — the character sheet (Character tab: Level/XP
## and the 7 stat-point rows) plus the run's Build tab (active synergies +
## every owned upgrade), opened directly with the I key from anywhere
## during exploration/combat/boss states. Modal like every other screen
## this step (get_tree().paused + this root's own process_mode ALWAYS).
##
## By far the most content of any step-9 screen so far and the first to
## need a ScrollContainer — the Character tab's 7 rows and the Build tab's
## upgrade-card grid (0 to 25+ owned) are both open-ended, unlike every
## previous screen's small fixed content, so the panel's chrome (title,
## tabs, Back button) stays fixed-size while only the tab body scrolls.
## Switching tabs, or a successful stat-point spend, fully clears and
## rebuilds that body — mirrors the source's own render()-on-every-change
## pattern (ShopUI's renderList() did the same for a smaller case).

enum Tab { CHARACTER, BUILD }

var _tab: Tab = Tab.CHARACTER
var _on_spend: Callable
var _tab_body: VBoxContainer
## The only screen so far whose tab builders need live Player/RunState
## access rather than pre-baked-in data (every other screen's content is
## fixed at build time) — set by the static factory below, read by both
## _build_character_tab and _build_build_tab.
var player: PlayerCharacter = null

## Spawns the sheet as a child of `parent`, pauses the tree. `on_spend`
## takes a stat id (String, e.g. "hp") and returns whether the spend
## succeeded — mirrors InventoryCallbacks.onSpend (LevelFlow.spend_stat_point
## already has exactly this shape).
static func show_inventory(parent: Node, player: PlayerCharacter, on_spend: Callable, initial_tab: Tab = Tab.CHARACTER) -> void:
	var ui := InventoryUI.new()
	ui._tab = initial_tab
	ui._on_spend = on_spend
	ui.player = player
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
	content.add_theme_constant_override("separation", 12)

	content.add_child(MenuUiKit.make_title(I18n.t("inventory.title", "Character")))

	# make_segmented() (Tab.CHARACTER/BUILD as its two options) replaces this
	# screen's own former _make_tab_button()/_update_tab_button_styles()
	# pair — a plain rectangular 2-way toggle sharing the same shared
	# component ArmoryUI's own Upgrades/Armory tab switch could use too,
	# rather than a second, pill-shaped, private reimplementation of
	# "exactly one of these buttons is active" with its own bespoke
	# corner_radius=999 styling.
	var tab_row := MenuUiKit.make_segmented(
		["character", "build"],
		[I18n.t("inventory.tabCharacter", "Character"), I18n.t("inventory.tabBuild", "Build")],
		"character" if _tab == Tab.CHARACTER else "build",
		func(value: String):
			_tab = Tab.CHARACTER if value == "character" else Tab.BUILD
			AudioEngine.play_sfx("uiClick")
			_render_tab()
	)
	content.add_child(tab_row)

	# Fixed-height scroll region, not size_flags_vertical = EXPAND_FILL — that
	# relied on the panel's own now-removed fixed PANEL_HALF_HEIGHT box to
	# have any leftover space to expand into; make_panel()'s auto-height
	# panel has none, so an EXPAND_FILL scroll body would just report its
	# own full natural content size (up to 25+ upgrade cards on the Build
	# tab) and grow the whole panel past the viewport, same failure mode
	# LoadoutSelectUI's wrapped card rows hit.
	var scroll := ScrollContainer.new()
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0.0, 320.0)
	content.add_child(scroll)
	_tab_body = VBoxContainer.new()
	_tab_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tab_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_body.add_theme_constant_override("separation", 10)
	scroll.add_child(_tab_body)

	var button_row := MenuUiKit.make_button_row()
	content.add_child(button_row)
	var back_button := MenuUiKit.make_button(I18n.t("pause.back", "Back"), MenuUiKit.ButtonVariant.PRIMARY)
	back_button.pressed.connect(_close)
	button_row.add_child(back_button)

	add_child(MenuUiKit.make_panel(content, true))
	_render_tab()

func _render_tab() -> void:
	for child in _tab_body.get_children():
		_tab_body.remove_child(child)
		child.queue_free()
	if _tab == Tab.CHARACTER:
		_build_character_tab(_tab_body)
	else:
		_build_build_tab(_tab_body)

# ---------------------------------------------------------------- Character tab

func _build_character_tab(container: VBoxContainer) -> void:
	var header := VBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_theme_constant_override("separation", 6)
	container.add_child(header)

	var level_label := Label.new()
	level_label.text = "%s — %s" % [I18n.t("inventory.player", "PLAYER"), I18n.t("inventory.levelFormat", "Level {n}").format({"n": RunState.player_level})]
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.add_theme_font_size_override("font_size", 16)
	level_label.add_theme_color_override("font_color", Color(Palette.GOLD_BRIGHT))
	level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(level_label)

	# Same track/fill/label recipe as hud.gd's own _make_bar_row, rebuilt
	# locally rather than shared — this project's usual "small per-file
	# builder" convention (see e.g. upgrade_card.gd's own _make_tag).
	var xp_track := Control.new()
	xp_track.custom_minimum_size = Vector2(360.0, 14.0)
	xp_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(xp_track)
	var xp_bg := ColorRect.new()
	xp_bg.color = Color(8.0 / 255.0, 6.0 / 255.0, 10.0 / 255.0, 0.65)
	xp_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	xp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xp_track.add_child(xp_bg)
	var is_max: bool = RunState.player_level >= RunState.LEVEL_CAP
	var xp_needed: float = RunState.xp_required_for_next_level()
	var xp_ratio: float = 1.0 if is_max else clampf(RunState.xp / maxf(1.0, xp_needed), 0.0, 1.0)
	var xp_fill := ColorRect.new()
	xp_fill.color = Color(Palette.GOLD_BRIGHT)
	xp_fill.anchor_left = 0.0
	xp_fill.anchor_top = 0.0
	xp_fill.anchor_right = xp_ratio
	xp_fill.anchor_bottom = 1.0
	xp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xp_track.add_child(xp_fill)
	var xp_label := Label.new()
	xp_label.text = I18n.t("hud.levelMax", "MAX") if is_max else "%d / %d XP" % [int(RunState.xp), int(xp_needed)]
	xp_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	xp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	xp_label.add_theme_font_size_override("font_size", 11)
	xp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xp_track.add_child(xp_label)

	if RunState.stat_points > 0:
		var points_label := Label.new()
		points_label.text = I18n.t("inventory.pointsAvailableFormat", "{count} stat point(s) available").format({"count": RunState.stat_points})
		points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		points_label.add_theme_font_size_override("font_size", 12)
		points_label.add_theme_color_override("font_color", Color(Palette.GOLD_BRIGHT))
		points_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		header.add_child(points_label)

	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override("separation", 8)
	container.add_child(rows)

	var has_bow: bool = player.unlocked_weapons.has("bow") if player != null else false
	for def in PlayerProgression.player_stats():
		var level: int = RunState.stat_levels.get(def.id, 0)
		var unit_text: String = I18n.t("stat.unit.%s" % def.id, "")
		var per_level_text: String = ("+%s %s" % [_format_num(def.value_per_level), unit_text]).strip_edges() if def.mode == StatModifier.Mode.FLAT else ("+%d%%" % roundi(def.value_per_level * 100.0))
		var locked: bool = PlayerProgression.is_player_stat_locked(def.id, has_bow, RunState.zone_index)
		var lock_reason: String = ""
		if locked:
			lock_reason = I18n.t("stat.lockedReason.attackSpeed", "Locked — recover the Warden's Bow to unlock.") if def.id == "attackSpeed" else I18n.t("stat.lockedReason.abilityDamage", "Locked — reach the Hollow Ruins (Level 2) to unlock.")
		var can_spend: bool = RunState.stat_points > 0 and not locked
		var stat_id: String = def.id
		var right_widget: Control = _make_locked_badge() if locked else _make_plus_button(can_spend, func(): _on_spend_pressed(stat_id))
		var desc: String = lock_reason if locked else I18n.t("inventory.perLevelFormat", "{value} per level").format({"value": per_level_text})
		var stat_name: String = I18n.t("stat.%s" % def.id, _stat_display_name(def.id))
		rows.add_child(_make_meta_row(def.icon, "%s — %s %d" % [stat_name, I18n.t("upgrade.level", "Level"), level], Color(Palette.TEXT_WARM), desc, right_widget, locked))
		# Ability Range isn't a stat-point row (driven entirely by in-run
		# range upgrades) — shown read-only right after Ability Damage,
		# same placement as the source.
		if def.id == "abilityDamage" and player != null:
			var range_value: float = PlayerProgression.get_ability_range_display(player.stats.area_damage_mult)
			rows.add_child(_make_meta_row("range", I18n.t("stat.abilityRange", "Ability Range"), Color(Palette.TEXT_WARM), I18n.t("inventory.abilityRangeDesc", "Base 10 — grows with range upgrades found this run."), _make_value_badge(_format_num(range_value)), false))

func _on_spend_pressed(stat_id: String) -> void:
	if _on_spend.call(stat_id):
		AudioEngine.play_sfx("shopBuy")
		_render_tab()

static func _format_num(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(round(value)))
	return str(value)

static func _stat_display_name(stat_id: String) -> String:
	match stat_id:
		"hp": return "Max HP"
		"stamina": return "Stamina"
		"abilityDamage": return "Ability Damage"
		"range": return "Range"
		"moveSpeed": return "Move Speed"
		"attackSpeed": return "Attack Speed"
		_: return stat_id

# ---------------------------------------------------------------- Build tab

func _build_build_tab(container: VBoxContainer) -> void:
	var active_synergies: Array = []
	if player != null:
		for s in DataRegistry.all("synergies"):
			if player.has_synergy((s as SynergyDefinition).id):
				active_synergies.append(s)

	var subtitle1 := Label.new()
	subtitle1.text = I18n.t("pause.activeSynergies", "Active synergies") if not active_synergies.is_empty() else I18n.t("pause.noSynergies", "No synergies active yet — some upgrade pairs unlock a bonus effect.")
	subtitle1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle1.add_theme_font_size_override("font_size", 13)
	subtitle1.add_theme_color_override("font_color", Color(Palette.TEXT_DIM))
	subtitle1.autowrap_mode = TextServer.AUTOWRAP_WORD
	subtitle1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(subtitle1)

	if not active_synergies.is_empty():
		var syn_rows := VBoxContainer.new()
		syn_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
		syn_rows.add_theme_constant_override("separation", 8)
		container.add_child(syn_rows)
		for s in active_synergies:
			var syn := s as SynergyDefinition
			syn_rows.add_child(_make_meta_row(syn.icon, I18n.tc(syn.id, "name", syn.name), Color(Palette.SOUL_BRIGHT), I18n.tc(syn.id, "description", syn.description), null, false))

	var divider := ColorRect.new()
	divider.color = Color(Palette.BORDER)
	divider.custom_minimum_size = Vector2(0.0, 1.0)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(divider)

	var owned: Array[OwnedUpgrade] = player.upgrades if player != null else []
	var count: int = owned.size()
	var subtitle2 := Label.new()
	var count_key: String = "pause.upgradeCountOne" if count == 1 else "pause.upgradeCountMany"
	var count_fallback: String = "{count} upgrade collected this run" if count == 1 else "{count} upgrades collected this run"
	subtitle2.text = I18n.t(count_key, count_fallback).format({"count": count})
	subtitle2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle2.add_theme_font_size_override("font_size", 13)
	subtitle2.add_theme_color_override("font_color", Color(Palette.TEXT_DIM))
	subtitle2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(subtitle2)

	if owned.is_empty():
		var empty_label := Label.new()
		empty_label.text = I18n.t("pause.noUpgrades", "No upgrades yet — clear a room, open a chest, or visit a shop.")
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.add_theme_font_size_override("font_size", 13)
		empty_label.add_theme_color_override("font_color", Color(Palette.TEXT_DIM))
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		empty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(empty_label)
		return

	var grid := GridContainer.new()
	grid.columns = 3
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	container.add_child(grid)
	for owned_upgrade in owned:
		var card := UpgradeCard.new()
		card.def = owned_upgrade.def
		card.level = owned_upgrade.stacks
		card.clickable = false
		card.show_tags = false
		grid.add_child(card)

# ---------------------------------------------------------------- Shared row/button builders

func _make_meta_row(icon_id: String, name_text: String, name_color: Color, desc_text: String, right_widget: Control, dimmed: bool) -> Control:
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
	icon.position = Vector2(7.0, 7.0)
	icon.size = Vector2(22.0, 22.0)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(icon)

	var info := VBoxContainer.new()
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	hbox.add_child(info)
	var name_label := Label.new()
	name_label.text = name_text
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", name_color)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(name_label)
	var desc_label := Label.new()
	desc_label.text = desc_text
	desc_label.add_theme_font_size_override("font_size", 11)
	desc_label.add_theme_color_override("font_color", Color(Palette.TEXT_DIM))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(desc_label)

	if right_widget != null:
		hbox.add_child(right_widget)

	return row

func _make_badge_pill(text: String, text_color: Color) -> Control:
	var wrap := PanelContainer.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(Palette.BG2)
	bg.set_border_width_all(1)
	bg.border_color = Color(Palette.BORDER)
	bg.set_corner_radius_all(6)
	bg.content_margin_left = 10.0
	bg.content_margin_right = 10.0
	bg.content_margin_top = 5.0
	bg.content_margin_bottom = 5.0
	wrap.add_theme_stylebox_override("panel", bg)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", text_color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(label)
	return wrap

func _make_locked_badge() -> Control:
	return _make_badge_pill(I18n.t("stat.locked", "Locked"), Color(Palette.TEXT_DIM))

func _make_value_badge(text: String) -> Control:
	return _make_badge_pill(text, Color(Palette.EMBER4))

func _make_plus_button(enabled: bool, on_press: Callable) -> Button:
	var btn := MenuUiKit.make_button("+", MenuUiKit.ButtonVariant.PLAIN)
	btn.disabled = not enabled
	btn.pressed.connect(on_press)
	return btn
