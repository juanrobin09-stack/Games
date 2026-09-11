class_name MenuUiKit
extends RefCounted
## Shared construction helpers for the "meta-shell" screens (MainMenu,
## PauseMenu, SettingsUI, VictoryDefeatUI, CreditsUI, ArmoryUI) — every one
## of them needs the same overlay background, centered card, title/body
## typography, and button look CSS's shared .screen-overlay/.screen-panel/
## .screen-title/.btn* primitives give the source. Every other screen this
## project has built so far (ShopUI, UpgradeSelectUI, EventUI...) keeps its
## own small private copy of this kind of helper instead of sharing one —
## fine when at most 2-3 files need it, but 7 screens all wanting the exact
## same overlay/panel/button chrome is a different scale of duplication,
## so this one case gets a shared module instead (the same reasoning this
## project already applies to DrawUtils/VfxPresets/VfxSystem for their own
## cross-cutting concerns).

enum ButtonVariant { PRIMARY, PLAIN, GHOST, DANGER }

## Ports .screen-overlay (opaque := true — MainMenu, Credits, standalone
## Settings, Victory/Defeat, Armory: nothing needs to show through) vs
## .screen-overlay.modal-backdrop (opaque := false — PauseMenu and its
## embedded Settings: gameplay is still visible, paused, behind it).
## The opaque color is style.css's own radial-gradient simplified to its
## outer, most-of-the-area stop (#07060a) — an exact match for
## Palette.VOID — per this project's usual "gradient -> flattest
## identity-defining stop" convention (no gradient-fill primitive on a
## plain Control here either; see e.g. hud.gd's own header).
static func make_overlay(opaque: bool) -> ColorRect:
	var overlay := ColorRect.new()
	overlay.color = Color(Palette.VOID) if opaque else Color(0.02, 0.016, 0.031, 0.72)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	return overlay

## Ports .screen-panel/.screen-panel.wide — the centered card every screen
## built on this kit sits inside. `content` becomes the panel's single
## child (a VBoxContainer the caller fills); returns the PanelContainer so
## the caller can add_child() it wherever the screen roots itself.
static func make_panel(content: Control, wide: bool = false) -> PanelContainer:
	var half_w: float = 450.0 if wide else 310.0
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -half_w
	panel.offset_right = half_w
	# Panels size to content vertically (no fixed half-height) — unlike
	# ShopUI/UpgradeSelectUI's own fixed-box panels, these screens'
	# content heights vary a lot screen-to-screen (Credits' 4 paragraphs
	# vs MainMenu's 5 buttons vs Armory's scroll list), so a fixed box
	# would either clip or float in dead space for most of them.
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	var style := StyleBoxFlat.new()
	style.bg_color = Color(Palette.PANEL_SOLID)
	style.border_color = Color(Palette.BORDER)
	style.set_border_width_all(1)
	style.set_corner_radius_all(16)
	style.set_content_margin_all(28.0)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	style.shadow_size = 16
	panel.add_theme_stylebox_override("panel", style)
	panel.add_child(content)
	return panel

static func make_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color(Palette.EMBER6))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

static func make_subtitle(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(Palette.TEXT_DIM))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

static func make_body_text(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.custom_minimum_size = Vector2(320.0, 0.0)
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(Palette.TEXT_WARM))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

static func _button_stylebox(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	return sb

## Ports .btn/.btn.primary/.btn.ghost/.btn.danger. PRIMARY/PLAIN colors
## copy ShopUI._make_button's own established palette exactly (ember-gold
## filled vs. dark bordered); GHOST (a borderless, dim, low-emphasis pick —
## Credits' Back, MainMenu's own Credits button) and DANGER (Abandon Run)
## are new variants this kit adds, since no earlier screen needed them.
static func make_button(text: String, variant: ButtonVariant = ButtonVariant.PLAIN) -> Button:
	var btn := Button.new()
	btn.text = text.to_upper()
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 14)
	match variant:
		ButtonVariant.PRIMARY:
			btn.add_theme_stylebox_override("normal", _button_stylebox(Color(Palette.EMBER3), Color(Palette.EMBER4)))
			btn.add_theme_stylebox_override("hover", _button_stylebox(Color(Palette.EMBER4), Color(Palette.EMBER5)))
			btn.add_theme_stylebox_override("pressed", _button_stylebox(Color(Palette.EMBER2), Color(Palette.EMBER4)))
			btn.add_theme_stylebox_override("disabled", _button_stylebox(Color(Palette.EMBER1), Color(Palette.BORDER)))
			btn.add_theme_color_override("font_color", Color("#180a04"))
			btn.add_theme_color_override("font_hover_color", Color("#180a04"))
			btn.add_theme_color_override("font_pressed_color", Color("#180a04"))
		ButtonVariant.DANGER:
			btn.add_theme_stylebox_override("normal", _button_stylebox(Color(Palette.BG2), Color(Palette.BLOOD)))
			btn.add_theme_stylebox_override("hover", _button_stylebox(Color(Palette.BLOOD), Color(Palette.BLOOD_BRIGHT)))
			btn.add_theme_stylebox_override("pressed", _button_stylebox(Color(Palette.BG1), Color(Palette.BLOOD)))
			btn.add_theme_stylebox_override("disabled", _button_stylebox(Color(Palette.BG1), Color(Palette.BORDER)))
			btn.add_theme_color_override("font_color", Color(Palette.BLOOD_BRIGHT))
			btn.add_theme_color_override("font_hover_color", Color("#180a04"))
			btn.add_theme_color_override("font_pressed_color", Color(Palette.BLOOD_BRIGHT))
		ButtonVariant.GHOST:
			var empty := StyleBoxEmpty.new()
			btn.add_theme_stylebox_override("normal", empty)
			btn.add_theme_stylebox_override("hover", empty)
			btn.add_theme_stylebox_override("pressed", empty)
			btn.add_theme_stylebox_override("disabled", empty)
			btn.add_theme_color_override("font_color", Color(Palette.TEXT_DIM))
			btn.add_theme_color_override("font_hover_color", Color(Palette.TEXT_WARM))
			btn.add_theme_color_override("font_pressed_color", Color(Palette.EMBER5))
		_:
			btn.add_theme_stylebox_override("normal", _button_stylebox(Color(Palette.BG2), Color(Palette.BORDER)))
			btn.add_theme_stylebox_override("hover", _button_stylebox(Color(Palette.BG3), Color(Palette.BORDER_LIT)))
			btn.add_theme_stylebox_override("pressed", _button_stylebox(Color(Palette.BG1), Color(Palette.BORDER_LIT)))
			btn.add_theme_stylebox_override("disabled", _button_stylebox(Color(Palette.BG1), Color(Palette.BORDER)))
			btn.add_theme_color_override("font_color", Color(Palette.TEXT_WARM))
			btn.add_theme_color_override("font_hover_color", Color(Palette.EMBER6))
			btn.add_theme_color_override("font_pressed_color", Color(Palette.EMBER5))
	btn.add_theme_color_override("font_disabled_color", Color(Palette.TEXT_FAINT))
	return btn

## Ports .button-column — a vertically stacked full-width button list
## (MainMenu, PauseMenu's main view).
static func make_button_column() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 10)
	return col

## Ports .button-row — a centered horizontal button pair/single (end
## screens' Continue/Try-Again/Main-Menu, Credits' Back, dialog confirms).
static func make_button_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	return row
