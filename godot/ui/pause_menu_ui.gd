class_name PauseMenuUI
extends Control
## Ports ui/PauseMenu.ts — the in-run pause overlay. True modal like
## ShopUI/EventUI/InventoryUI/UpgradeSelectUI (get_tree().paused + this
## root's own process_mode ALWAYS so it keeps taking clicks while
## everything else freezes) — the one new thing here is that Resume/
## Abandon need to hand back to a CALLER-owned flow (main.gd's own
## GameState pop / _end_run), not just tear themselves down the way a
## shop or an upgrade pick does.
##
## Three views swapped by rebuilding _content_holder's children, mirroring
## the source's own renderMain()/renderConfirmAbandon()/showSettings()
## innerHTML-clearing swaps — same "just requeue the children" convention
## this project already uses for HUD's shield pips and the boss bar's
## phase dots.

## Keys: on_resume, on_abandon, on_open_inventory (all Callable() -> void).
var _callbacks: Dictionary = {}
var _content_holder: Control

static func show_pause(parent: Node, callbacks: Dictionary) -> PauseMenuUI:
	var ui := PauseMenuUI.new()
	ui._callbacks = callbacks
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
	# Translucent, gameplay visible-behind backdrop (.modal-backdrop) —
	# unlike MainMenu/Credits/Victory/Defeat's own opaque .screen-overlay,
	# there IS a real paused game underneath this one.
	add_child(MenuUiKit.make_overlay(false))

	_content_holder = Control.new()
	_content_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_content_holder)

	_render_main()

func _clear_content() -> void:
	for child in _content_holder.get_children():
		child.queue_free()

func _render_main() -> void:
	_clear_content()
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 14)
	content.custom_minimum_size = Vector2(280.0, 0.0)
	content.add_child(MenuUiKit.make_title("Paused"))

	var col := MenuUiKit.make_button_column()
	var resume_btn := MenuUiKit.make_button("Resume", MenuUiKit.ButtonVariant.PRIMARY)
	resume_btn.pressed.connect(func():
		_close()
		var callback: Callable = _callbacks.get("on_resume", Callable())
		if callback.is_valid():
			callback.call()
	)
	col.add_child(resume_btn)

	var build_btn := MenuUiKit.make_button("Your Build", MenuUiKit.ButtonVariant.PLAIN)
	build_btn.pressed.connect(func():
		_close()
		var callback: Callable = _callbacks.get("on_open_inventory", Callable())
		if callback.is_valid():
			callback.call()
	)
	col.add_child(build_btn)

	var settings_btn := MenuUiKit.make_button("Settings", MenuUiKit.ButtonVariant.PLAIN)
	settings_btn.pressed.connect(_render_settings)
	col.add_child(settings_btn)

	var abandon_btn := MenuUiKit.make_button("Abandon Run", MenuUiKit.ButtonVariant.DANGER)
	abandon_btn.pressed.connect(_render_confirm_abandon)
	col.add_child(abandon_btn)
	content.add_child(col)

	_content_holder.add_child(MenuUiKit.make_panel(content, false))

func _render_confirm_abandon() -> void:
	_clear_content()
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 14)
	content.custom_minimum_size = Vector2(360.0, 0.0)
	content.add_child(MenuUiKit.make_title("Abandon this run?"))
	content.add_child(MenuUiKit.make_body_text("The Ember will fall dark here. All progress from this run will be lost — only Soul Ash already banked remains."))

	var row := MenuUiKit.make_button_row()
	var keep_going_btn := MenuUiKit.make_button("Keep Going", MenuUiKit.ButtonVariant.GHOST)
	keep_going_btn.pressed.connect(_render_main)
	row.add_child(keep_going_btn)
	var abandon_btn := MenuUiKit.make_button("Abandon", MenuUiKit.ButtonVariant.DANGER)
	abandon_btn.pressed.connect(func():
		_close()
		var callback: Callable = _callbacks.get("on_abandon", Callable())
		if callback.is_valid():
			callback.call()
	)
	row.add_child(abandon_btn)
	content.add_child(row)

	_content_holder.add_child(MenuUiKit.make_panel(content, false))

func _render_settings() -> void:
	_clear_content()
	SettingsUI.show_settings(_content_holder, true, _render_main)
