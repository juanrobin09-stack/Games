class_name CreditsUI
extends Control
## Ports ui/CreditsScreen.ts. The "tech" line is adapted, not translated
## verbatim — the source's own line ("Built with TypeScript, Vite, Canvas
## 2D, and the Web Audio API") describes the Web build specifically and
## would be factually wrong here.

static func show_credits(parent: Node, on_close: Callable) -> CreditsUI:
	var ui := CreditsUI.new()
	parent.add_child(ui)
	ui._build(on_close)
	return ui

func _build(on_close: Callable) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	add_child(MenuUiKit.make_overlay(true))

	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 16)
	content.custom_minimum_size = Vector2(380.0, 0.0)

	content.add_child(MenuUiKit.make_title("Credits"))

	var body := VBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", 10)
	body.add_child(MenuUiKit.make_body_text("EMBERFALL: LAST LIGHT"))
	body.add_child(MenuUiKit.make_body_text("A self-contained dark fantasy action roguelite. Every sprite, particle, and light in this game is generated procedurally at runtime — no external art or audio files."))
	body.add_child(MenuUiKit.make_body_text("Built with Godot Engine and GDScript."))
	body.add_child(MenuUiKit.make_body_text("Thank you for guarding the last light."))
	content.add_child(body)

	var button_row := MenuUiKit.make_button_row()
	var back_btn := MenuUiKit.make_button("Back", MenuUiKit.ButtonVariant.PRIMARY)
	back_btn.pressed.connect(func():
		if on_close.is_valid():
			on_close.call()
	)
	button_row.add_child(back_btn)
	content.add_child(button_row)

	add_child(MenuUiKit.make_panel(content, false))
