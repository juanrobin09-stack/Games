class_name VictoryDefeatUI
extends Control
## Ports ui/VictoryScreen.ts's own two exported classes (VictoryScreen +
## DefeatScreen) as two static factories on one file instead — they share
## every bit of layout (stat-grid, seed label, panel chrome) and differ
## only in title/subtitle copy and button count, which doesn't earn two
## separate classes here the way it barely earned two in the source either
## (both constructors are near-identical).

const STATS_PER_ROW := 3

static func show_victory(parent: Node, soul_ash_earned: int, on_continue: Callable) -> VictoryDefeatUI:
	var ui := VictoryDefeatUI.new()
	parent.add_child(ui)
	ui._build(
		I18n.t("victory.title", "The Ember Endures"), I18n.t("victory.subtitle", "The Ashen Colossus falls. For now, the dark recedes."),
		I18n.t("stat.time", "Time"), soul_ash_earned,
		[{"text": I18n.t("victory.continue", "Continue"), "variant": MenuUiKit.ButtonVariant.PRIMARY, "callback": on_continue}]
	)
	return ui

static func show_defeat(parent: Node, soul_ash_earned: int, on_try_again: Callable, on_main_menu: Callable) -> VictoryDefeatUI:
	var ui := VictoryDefeatUI.new()
	parent.add_child(ui)
	var zone_name: String = "?"
	var room := RunState.current_room()
	if room != null and room.zone != null:
		zone_name = I18n.tc(room.zone.id, "name", room.zone.name)
	ui._build(
		I18n.t("defeat.title", "The Light Gutters Out"), I18n.t("defeat.subtitleFormat", "Fallen in {zone}. The Ember dims, but does not die.").format({"zone": zone_name}),
		I18n.t("stat.timeSurvived", "Time Survived"), soul_ash_earned,
		[
			{"text": I18n.t("defeat.tryAgain", "Try Again"), "variant": MenuUiKit.ButtonVariant.PRIMARY, "callback": on_try_again},
			{"text": I18n.t("defeat.mainMenu", "Main Menu"), "variant": MenuUiKit.ButtonVariant.GHOST, "callback": on_main_menu},
		]
	)
	return ui

func _build(title_text: String, subtitle_text: String, time_label: String, soul_ash_earned: int, buttons: Array) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	add_child(MenuUiKit.make_overlay(true))

	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 14)
	content.custom_minimum_size = Vector2(420.0, 0.0)

	content.add_child(MenuUiKit.make_title(title_text))
	content.add_child(MenuUiKit.make_subtitle(subtitle_text))

	var stats: Array = [
		[time_label, HudLayer.format_time(RunState.elapsed_time)],
		[I18n.t("stat.kills", "Kills"), str(RunState.kills)],
		[I18n.t("stat.damageDealt", "Damage Dealt"), str(roundi(RunState.damage_dealt))],
		[I18n.t("stat.embersCollected", "Embers Collected"), str(RunState.embers_collected)],
		[I18n.t("stat.upgradesTaken", "Upgrades Taken"), str(RunState.upgrades_chosen.size())],
		[I18n.t("stat.soulAshEarned", "Soul Ash Earned"), str(soul_ash_earned)],
	]
	content.add_child(_build_stat_grid(stats))

	var seed_label := Label.new()
	seed_label.text = "%s: %s" % [I18n.t("endScreen.seedLabel", "Seed"), MetaProgression.last_seed]
	seed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seed_label.add_theme_font_size_override("font_size", 12)
	seed_label.add_theme_color_override("font_color", Color(Palette.TEXT_FAINT))
	seed_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(seed_label)

	var button_row := MenuUiKit.make_button_row()
	for entry in buttons:
		var btn := MenuUiKit.make_button(entry["text"], entry["variant"])
		var callback: Callable = entry["callback"]
		btn.pressed.connect(func():
			if callback.is_valid():
				callback.call()
		)
		button_row.add_child(btn)
	content.add_child(button_row)

	add_child(MenuUiKit.make_panel(content, false))

## Ports .stat-grid/.stat-tile — a fixed 3-per-row grid of value+label
## tiles (GridContainer's own column count set directly, simpler than
## computing a responsive column count this project's screens never need —
## every stat-grid entry list is always exactly 6).
func _build_stat_grid(stats: Array) -> GridContainer:
	var grid := GridContainer.new()
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.columns = STATS_PER_ROW
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 12)
	for entry in stats:
		var tile := VBoxContainer.new()
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.custom_minimum_size = Vector2(120.0, 0.0)
		var value := Label.new()
		value.text = str(entry[1])
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value.add_theme_font_size_override("font_size", 20)
		value.add_theme_color_override("font_color", Color(Palette.EMBER5))
		value.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(value)
		var label := Label.new()
		label.text = str(entry[0])
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", Color(Palette.TEXT_DIM))
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(label)
		grid.add_child(tile)
	return grid
