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

## Shared dark-fantasy frame every chrome=true panel below renders with —
## a single reference image (bronze/copper gothic border, corner + top/
## bottom-center diamond ornaments, tattered banners) applied as a
## StyleBoxTexture so it 9-slices instead of stretching as one flat image:
## the four TEXTURE_MARGIN_* below mark where the ornate border art ends
## and the plain, low-contrast, safely-stretchable interior begins, in the
## source texture's own pixels. Godot's 9-slice then keeps the 4 corner
## cells completely unstretched (this is what actually satisfies "corners
## must never be deformed" — not a visual approximation of it), stretches
## the 4 edge cells along their one long axis, and stretches the center
## cell both ways to fill whatever panel size make_panel() is asked for.
## The one accepted tradeoff of the technique: the top/bottom-center
## diamond ornaments sit inside the top/bottom edge cells, so they do
## stretch horizontally along with that edge when a panel's width departs
## from the source texture's 812px — kept mild in practice since every
## real chrome=true panel width (620px narrow / 900px wide) is within
## ~30% of that source width, and the ornament itself is a soft,
## symmetric glyph rather than a hard-edged pattern that would show it.
##
## Margins were measured directly off the source image (menu_frame.png,
## downscaled 50% from the 1624x969 original supplied via GitHub) by
## cropping and visually inspecting each corner/banner at 3x zoom, not
## guessed: the corner diamonds bottom out around y=75-80px from the
## top/bottom edge, the top-center diamond's spike around y=60-70px, and
## the solid banner cloth (the widest element on the left/right sides,
## wider than the corner diamonds alone) reaches to about x=115-120px —
## a first attempt at these margins via an automated brightness-threshold
## scan failed silently (the image is dark enough everywhere, including
## the faint center watermark, that no clean "safe" threshold existed)
## and was abandoned in favor of this direct visual measurement.
const PANEL_FRAME_TEXTURE := preload("res://assets/textures/menu_frame.png")
const TEXTURE_MARGIN_LEFT := 120.0
const TEXTURE_MARGIN_RIGHT := 120.0
const TEXTURE_MARGIN_TOP := 85.0
const TEXTURE_MARGIN_BOTTOM := 80.0

static func _panel_frame_stylebox() -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = PANEL_FRAME_TEXTURE
	style.texture_margin_left = TEXTURE_MARGIN_LEFT
	style.texture_margin_right = TEXTURE_MARGIN_RIGHT
	style.texture_margin_top = TEXTURE_MARGIN_TOP
	style.texture_margin_bottom = TEXTURE_MARGIN_BOTTOM
	# content_margin_* left at its default (-1 == "same as texture_margin"):
	# child content starts exactly where the plain, stretchable interior
	# starts, no extra buffer — every chrome=true panel already lost a lot
	# of raw content width to this frame's fairly wide ornate border versus
	# the old flat 28px margin, so this avoids shrinking it further.
	return style

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
##
## `chrome = false` ports the embedded-mode half of CSS's own
## `screen-panel${embedded ? '' : ' panel pop-in'}` (SettingsMenu.ts) —
## centering (`.screen-panel` itself) always applies; only the background/
## border/shadow (the separate `panel` class) is conditional. A first
## draft skipped the whole make_panel() call when embedded and lost the
## centering along with the chrome — caught via a real screenshot showing
## PauseMenu's embedded Settings pinned to the top-left corner, behind the
## HUD, instead of centered over the translucent backdrop.
static func make_panel(content: Control, wide: bool = false, chrome: bool = true) -> PanelContainer:
	# wide's 450 -> 480 bump is part of this same frame change: the new
	# ornate border's margins (120px each side, vs. the old flat panel's
	# 28px) eat much more into a fixed-width panel's usable content width
	# than before, so every wide=true screen gets a little more room back.
	var half_w: float = 480.0 if wide else 310.0
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
	if chrome:
		panel.add_theme_stylebox_override("panel", _panel_frame_stylebox())
	else:
		# No visible chrome, but content still needs the same breathing
		# room the styled panel's content_margin gives it — an empty
		# stylebox with matching margins, rather than no override at all
		# (which would fall back to the default theme's own PanelContainer
		# margin, likely 0).
		var empty := StyleBoxEmpty.new()
		empty.content_margin_left = 28.0
		empty.content_margin_right = 28.0
		empty.content_margin_top = 28.0
		empty.content_margin_bottom = 28.0
		panel.add_theme_stylebox_override("panel", empty)
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

## Ports .toggle-switch — as a toggle-mode Button (own on/off StyleBoxFlat
## pair) rather than Godot's built-in CheckButton: this project's whole
## visual language so far is custom StyleBoxFlat chrome (every button,
## every bar, every card), and CheckButton's default theme would be the
## one control on this screen not sharing it. SettingsUI owns wiring
## `toggled` to whatever the row actually controls.
##
## The pill alone (a flat color rect, on/off told apart only by a subtle
## background tint) read as an unstyled placeholder box rather than a
## switch — reported directly against a real screenshot, not a guess — so
## a round knob is layered on top as a child Panel, sliding between the
## pill's two ends, the actual "something is here to grab" cue a plain
## color swap didn't give. Instant position swap when reduced_motion is
## on (matching every other motion-gated effect this project already has
## — see settings_ui.gd's own header for the full list); a short Tween
## otherwise, since a toggle this small warrants a slide, not a jump cut.
static func make_toggle(initial: bool) -> Button:
	var btn := Button.new()
	btn.toggle_mode = true
	btn.button_pressed = initial
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(42.0, 22.0)
	btn.text = ""
	var off_style := _button_stylebox(Color(Palette.BG3), Color(Palette.BORDER))
	off_style.set_corner_radius_all(11)
	var on_style := _button_stylebox(Color(Palette.EMBER3, 0.35), Color(Palette.EMBER4))
	on_style.set_corner_radius_all(11)
	btn.add_theme_stylebox_override("normal", off_style)
	btn.add_theme_stylebox_override("hover", off_style)
	btn.add_theme_stylebox_override("pressed", on_style)
	btn.add_theme_stylebox_override("hover_pressed", on_style)

	const KNOB_SIZE := 16.0
	const KNOB_MARGIN := 3.0
	const KNOB_X_ON := 42.0 - KNOB_SIZE - KNOB_MARGIN
	var knob := Panel.new()
	knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	knob.size = Vector2(KNOB_SIZE, KNOB_SIZE)
	knob.position = Vector2(KNOB_X_ON if initial else KNOB_MARGIN, KNOB_MARGIN)
	var knob_style := StyleBoxFlat.new()
	knob_style.bg_color = Color(Palette.EMBER4 if initial else Palette.TEXT_FAINT)
	knob_style.set_corner_radius_all(int(KNOB_SIZE / 2.0))
	knob.add_theme_stylebox_override("panel", knob_style)
	btn.add_child(knob)
	btn.toggled.connect(func(pressed: bool):
		var target_x: float = KNOB_X_ON if pressed else KNOB_MARGIN
		knob_style.bg_color = Color(Palette.EMBER4 if pressed else Palette.TEXT_FAINT)
		if MetaProgression.settings.get("reduced_motion", false):
			knob.position.x = target_x
		else:
			knob.create_tween().tween_property(knob, "position:x", target_x, 0.12).set_trans(Tween.TRANS_CUBIC)
	)
	return btn

## Ports .segmented — a row of small buttons where exactly one is active;
## `options` are the raw values (e.g. "low"/"medium"/"high"), `labels` the
## matching display text. Returns the built HBoxContainer; the caller
## reads which one is active by checking each child Button's own
## `button_pressed` (a ButtonGroup guarantees exactly one stays true).
static func make_segmented(options: Array, labels: Array, selected: String, on_pick: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 0)
	var group := ButtonGroup.new()
	for i in range(options.size()):
		var value: String = options[i]
		var btn := Button.new()
		btn.text = str(labels[i])
		btn.toggle_mode = true
		btn.button_group = group
		btn.button_pressed = value == selected
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 12)
		var off_style := _button_stylebox(Color(Palette.BG1), Color(Palette.BORDER))
		var on_style := _button_stylebox(Color(Palette.EMBER3), Color(Palette.EMBER4))
		btn.add_theme_stylebox_override("normal", off_style)
		btn.add_theme_stylebox_override("hover", off_style)
		btn.add_theme_stylebox_override("pressed", on_style)
		btn.add_theme_stylebox_override("hover_pressed", on_style)
		btn.add_theme_color_override("font_color", Color(Palette.TEXT_DIM))
		btn.add_theme_color_override("font_pressed_color", Color("#180a04"))
		btn.add_theme_color_override("font_hover_pressed_color", Color("#180a04"))
		btn.toggled.connect(func(pressed: bool):
			if pressed and on_pick.is_valid():
				on_pick.call(value)
		)
		row.add_child(btn)
	return row
