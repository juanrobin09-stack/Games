class_name AdminMenuUI
extends Control
## Personal dev/testing tool (F2 in main.gd), not a shipped feature — unlike
## every other screen in this project it deliberately skips I18n for its
## own chrome (title, room-type labels, buttons): it only ever needs to
## make sense to the one person using it. Zone names still route through
## I18n.tc() since the run's own zone data is already there and it's free.
##
## Lists every room the current run has already generated (RunState.layouts
## — all 3 zones exist up front from LevelFlow.start_new_run(), so this
## works from the very first room of a run) grouped by zone then room
## type, and hands the chosen (room, zone_index) pair back to main.gd's
## own on_teleport callback rather than touching RunState/LevelFlow
## directly — the same "UI screens call back into main.gd, main.gd owns
## game-state mutation" shape every other screen here already uses.

const TYPE_LABELS := {
	RoomContainer.Type.START: "Départ",
	RoomContainer.Type.COMBAT: "Combat",
	RoomContainer.Type.ELITE: "Élite",
	RoomContainer.Type.HEART: "Cœur de zone",
	RoomContainer.Type.BOSS: "Boss",
	RoomContainer.Type.CHEST: "Coffre",
	RoomContainer.Type.SHOP: "Boutique",
	RoomContainer.Type.EVENT: "Événement",
	RoomContainer.Type.REST: "Repos",
	RoomContainer.Type.SANCTUM: "Sanctuaire",
}

var _zone_index: int = 0
var _on_teleport: Callable
var _zone_row: HBoxContainer
var _list_col: VBoxContainer

static func show_menu(parent: Node, on_teleport: Callable) -> AdminMenuUI:
	var ui := AdminMenuUI.new()
	ui._on_teleport = on_teleport
	ui._zone_index = mini(RunState.zone_index, RunState.layouts.size() - 1)
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(ui)
	ui._build()
	ui.get_tree().paused = true
	return ui

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
	content.custom_minimum_size = Vector2(440.0, 0.0)
	content.add_child(MenuUiKit.make_title("Menu Admin"))
	content.add_child(MenuUiKit.make_subtitle("Téléportation debug — outil perso, F2 pour rouvrir"))

	_zone_row = HBoxContainer.new()
	_zone_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zone_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_zone_row.add_theme_constant_override("separation", 8)
	content.add_child(_zone_row)

	var scroll := ScrollContainer.new()
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0.0, 300.0)
	content.add_child(scroll)
	_list_col = VBoxContainer.new()
	_list_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_col.add_theme_constant_override("separation", 8)
	scroll.add_child(_list_col)

	var button_row := MenuUiKit.make_button_row()
	var close_btn := MenuUiKit.make_button("Fermer", MenuUiKit.ButtonVariant.GHOST)
	close_btn.pressed.connect(_close)
	button_row.add_child(close_btn)
	content.add_child(button_row)

	add_child(MenuUiKit.make_panel(content, false))
	_render_zone_row()
	_render_room_list()

## Rebuilds rather than restyles in place — same convention as armory_ui.gd's
## own _render_tabs(): a handful-of-buttons row is cheap enough to rebuild
## on every switch, so the active/inactive look stays MenuUiKit's own
## PRIMARY vs PLAIN variant rather than a hand-rolled style toggle.
func _render_zone_row() -> void:
	for child in _zone_row.get_children():
		_zone_row.remove_child(child)
		child.queue_free()
	for zi in range(RunState.layouts.size()):
		var zone_def: ZoneDefinition = RunState.layouts[zi]["zone"]
		var label_text: String = I18n.tc(zone_def.id, "name", zone_def.name)
		var btn := MenuUiKit.make_button(label_text, MenuUiKit.ButtonVariant.PRIMARY if zi == _zone_index else MenuUiKit.ButtonVariant.PLAIN)
		btn.pressed.connect(func():
			_zone_index = zi
			_render_zone_row()
			_render_room_list()
		)
		_zone_row.add_child(btn)

## Groups the selected zone's rooms by type (in the enum's own declared
## order via TYPE_LABELS.keys(), not raw dictionary-iteration order, so the
## list reads the same every time) and lists each individually — most
## rooms are COMBAT and there's more than one per zone, so a bare type name
## would otherwise hide which physical room a click actually reaches.
func _render_room_list() -> void:
	for child in _list_col.get_children():
		_list_col.remove_child(child)
		child.queue_free()
	var zone_layout: Dictionary = RunState.layouts[_zone_index]
	var rooms: Dictionary = zone_layout["rooms"]
	var by_type: Dictionary = {}
	for key in rooms.keys():
		var room: RoomContainer = rooms[key]
		var list: Array = by_type.get(room.type, [])
		list.append(room)
		by_type[room.type] = list
	var zi := _zone_index
	for type_value in TYPE_LABELS.keys():
		if not by_type.has(type_value):
			continue
		var rooms_of_type: Array = by_type[type_value]
		for i in range(rooms_of_type.size()):
			var room: RoomContainer = rooms_of_type[i]
			var suffix: String = (" #%d" % (i + 1)) if rooms_of_type.size() > 1 else ""
			var label_text: String = TYPE_LABELS[type_value] + suffix + (" (visitée)" if room.visited else "")
			var btn := MenuUiKit.make_button(label_text, MenuUiKit.ButtonVariant.PLAIN)
			btn.pressed.connect(func():
				_on_teleport.call(room, zi)
				_close()
			)
			_list_col.add_child(btn)
