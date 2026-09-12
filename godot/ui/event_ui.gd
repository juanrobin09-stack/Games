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

const PANEL_HALF_WIDTH := 310.0
const PANEL_HALF_HEIGHT := 240.0

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

	# `alignment` (not just gap/separation) also governs a VBoxContainer's
	# own primary (vertical) axis: CENTER distributes any slack the fixed
	# panel height leaves beyond this content's natural size evenly above
	# and below, rather than the default top-packed stack leaving it all
	# as dead space underneath the last option row (events range from 2 to
	# 3 options with descriptions of very different lengths, so there's
	# often real slack — this is what makes it degrade gracefully instead
	# of looking unfinished).
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 14)
	panel_bg.add_child(content)

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
