class_name EventUI
extends Control
## Ports ui/EventUI.ts — the shrine/sanctuary encounter screen. Modal like
## UpgradeSelectUI/ShopUI (get_tree().paused + this root's own process_mode
## ALWAYS). Unlike either, there's no Leave/Cancel — mirrors the source
## having no such button either; an encounter, once opened, must be
## engaged with by picking one of its (affordable) options.
##
## Each option is a PanelContainer, not a Button — same reasoning as
## ShopUI's own offer rows: PanelContainer auto-sizes to its label/detail/
## cost text (which varies per event/option), where a Button's own
## minimum-size model doesn't account for manually-added rich child
## content. Clicks come from Control's own `gui_input` signal (every
## Control has it, no subclassing needed), same as a real Button would
## emit `pressed` — just wired by hand since this isn't one.

signal chosen(option: EventOption)

## Spawns the screen as a child of `parent`, pauses the tree, and calls
## `on_choose(option)` once the player picks an affordable option — after
## which the screen tears itself down and unpauses.
static func show_event(parent: Node, def: WorldEventDefinition, on_choose: Callable) -> void:
	var ui := EventUI.new()
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(ui)
	ui.chosen.connect(func(option: EventOption):
		AudioEngine.play_sfx("eventChoice")
		ui.get_tree().paused = false
		ui.queue_free()
		on_choose.call(option)
	)
	ui._build(def)
	ui.get_tree().paused = true

func _build(def: WorldEventDefinition) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0

	add_child(MenuUiKit.make_overlay(false))

	# Panels size to content now (make_panel(), not a fixed PANEL_HALF_HEIGHT
	# box) so the old `content.alignment = ALIGNMENT_CENTER` trick — which
	# existed only to distribute a fixed box's leftover slack evenly above/
	# below a variable 2-3-option list instead of leaving it all as dead
	# space underneath — has nothing left to do: there is no slack to
	# distribute when the panel just sizes to fit.
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 14)

	var title := Label.new()
	title.text = I18n.tc(def.id, "title", def.title)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(Palette.EMBER6))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(title)

	var description := Label.new()
	description.text = I18n.tc(def.id, "description", def.description)
	description.add_theme_font_size_override("font_size", 14)
	description.add_theme_color_override("font_color", Color(Palette.TEXT_DIM))
	description.autowrap_mode = TextServer.AUTOWRAP_WORD
	description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(description)

	var options_col := VBoxContainer.new()
	options_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	options_col.add_theme_constant_override("separation", 10)
	content.add_child(options_col)

	for option in def.options:
		options_col.add_child(_make_option_row(option))

	add_child(MenuUiKit.make_panel(content, false))

func _make_option_row(option: EventOption) -> Control:
	var affordable: bool = option.cost <= 0.0 or RunState.embers >= int(option.cost)

	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_STOP if affordable else Control.MOUSE_FILTER_IGNORE
	var row_style := StyleBoxFlat.new()
	row_style.bg_color = Color(Palette.BG1) if affordable else Color(Palette.BG0)
	row_style.border_color = Color(Palette.BORDER)
	row_style.set_border_width_all(1)
	row_style.set_corner_radius_all(10)
	row_style.content_margin_left = 16.0
	row_style.content_margin_right = 16.0
	row_style.content_margin_top = 14.0
	row_style.content_margin_bottom = 14.0
	row.add_theme_stylebox_override("panel", row_style)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)

	var label := Label.new()
	label.text = I18n.tc(option.id, "label", option.label)
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(Palette.EMBER5) if affordable else Color(Palette.TEXT_FAINT))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(label)

	var detail := Label.new()
	detail.text = I18n.tc(option.id, "detail", option.detail)
	detail.add_theme_font_size_override("font_size", 12)
	detail.add_theme_color_override("font_color", Color(Palette.TEXT_DIM) if affordable else Color(Palette.TEXT_FAINT))
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(detail)

	if option.cost > 0.0:
		var cost_label := Label.new()
		cost_label.text = "%s %d %s" % [I18n.t("event.costsPrefix", "Costs"), int(option.cost), I18n.t("currency.embers", "Embers")]
		cost_label.add_theme_font_size_override("font_size", 11)
		cost_label.add_theme_color_override("font_color", Color(Palette.SOUL_BRIGHT) if affordable else Color(Palette.TEXT_FAINT))
		cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(cost_label)

	row.gui_input.connect(func(event: InputEvent):
		if not affordable:
			return
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			chosen.emit(option)
	)
	return row
