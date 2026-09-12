class_name SettingsUI
extends Control
## Ports ui/SettingsMenu.ts. Every control here writes straight to
## MetaProgression.settings (persisted immediately on each change, same
## "every mutation is its own synchronous save" convention
## meta_progression.gd's own header already documents) — but most of what
## it writes has nothing underneath it to actually DO anything with the
## value yet, and that's deliberate, not an oversight:
##
## - **Fullscreen** (DisplayServer.window_set_mode) is the one control
##   with a real, immediate effect — a single engine call, nothing to
##   build.
## - **Master/Music/SFX Volume and Mute All are real** (build-order step
##   10, autoload/audio_engine.gd): each slider/toggle write reaches
##   AudioServer live via MetaProgression's own settings_changed signal —
##   no polling, no "apply on close" step.
## - **Language** (en/fr) now has a real translation system behind it too
##   — autoload/i18n.gd ports i18n/index.ts + i18n/fr.ts's own FR_UI/
##   FR_CONTENT dictionaries verbatim, read through I18n.t()/I18n.tc(). Not
##   reactive, matching the source's own explicit non-goal (it reloads the
##   whole page after a language change rather than retranslating whatever
##   TS already baked into the DOM) — this port's own screens are already
##   rebuilt fresh each time they're shown, so a change takes effect next
##   time each screen reopens, same practical result without needing a
##   reload. Every screen in the project (this one included) now builds
##   its strings through I18n — the full sweep beyond MainMenuUI's own
##   first, verifiable case is complete, not just started. The language
##   row's own hint text is therefore Godot-specific (`settings.
##   languageHintGodot`, no FR_UI entry to reuse): the source's own
##   `settings.languageHint` ("Reloads the game to apply") describes ITS
##   reload-on-change behavior, which would be factually wrong to show
##   here.
## - **screen_shake, particle_quality, and reduced_motion are real now**
##   too (see PlayerCharacter.add_camera_shake()/CombatManager.
##   trigger_hit_stop()/VfxSystem.emit()'s own quality check, and hud.gd's
##   _motion_scale()). **graphics_quality and high_contrast are still
##   inert**, deliberately: this port has no quality-tier render path or
##   alternate UI theme to plug into yet, the same honest, already-
##   documented shape of gap the boss-fight work once carried for camera
##   shake before this session closed it. Storing every value now means
##   the day either of those two lands, it reads a real saved preference
##   instead of needing its own migration.
##
## `embedded` mirrors the source's own SettingsMenu(container, settings,
## callbacks, embedded) 4th parameter exactly: false builds its own full
## overlay+panel (MainMenu's Settings button); true returns just the
## panel's inner content for PauseMenu to place inside its own already-
## open backdrop.

static func show_settings(parent: Node, embedded: bool, on_close: Callable) -> Control:
	var ui := SettingsUI.new()
	parent.add_child(ui)
	ui._build(embedded, on_close)
	return ui

func _build(embedded: bool, on_close: Callable) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	if not embedded:
		add_child(MenuUiKit.make_overlay(true))

	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 14)
	content.custom_minimum_size = Vector2(420.0, 0.0)

	content.add_child(MenuUiKit.make_title(I18n.t("menu.settings", "Settings")))

	var body := VBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", 2)

	var quality_labels: Array[String] = [I18n.t("settings.quality.low", "Low"), I18n.t("settings.quality.medium", "Medium"), I18n.t("settings.quality.high", "High")]
	body.add_child(_build_segmented_row(I18n.t("settings.language", "Language"), I18n.t("settings.languageHintGodot", "Takes effect the next time each screen opens"), ["en", "fr"], ["English", "Français"], "language"))
	body.add_child(_build_slider_row(I18n.t("settings.masterVolume", "Master Volume"), "master_volume", 0.0, 1.0, 0.01))
	body.add_child(_build_slider_row(I18n.t("settings.musicVolume", "Music Volume"), "music_volume", 0.0, 1.0, 0.01))
	body.add_child(_build_slider_row(I18n.t("settings.sfxVolume", "SFX Volume"), "sfx_volume", 0.0, 1.0, 0.01))
	body.add_child(_build_toggle_row(I18n.t("settings.muteAll", "Mute All"), I18n.t("settings.muteAllHint", "Silence all audio output"), "muted"))
	body.add_child(_build_toggle_row(I18n.t("settings.screenShake", "Screen Shake"), I18n.t("settings.screenShakeHint", "Camera shake on heavy impacts"), "screen_shake"))
	body.add_child(_build_segmented_row(I18n.t("settings.particles", "Particles"), "", ["low", "medium", "high"], quality_labels, "particle_quality"))
	body.add_child(_build_segmented_row(I18n.t("settings.graphicsQuality", "Graphics Quality"), "", ["low", "medium", "high"], quality_labels, "graphics_quality"))
	body.add_child(_build_slider_row(I18n.t("settings.textSize", "Text Size"), "text_scale", 0.85, 1.3, 0.05))
	body.add_child(_build_toggle_row(I18n.t("settings.highContrast", "High Contrast"), I18n.t("settings.highContrastHint", "Increase text and UI contrast"), "high_contrast"))
	body.add_child(_build_toggle_row(I18n.t("settings.reducedMotion", "Reduced Motion"), I18n.t("settings.reducedMotionHint", "Minimize UI animation"), "reduced_motion"))
	body.add_child(_build_fullscreen_row())
	content.add_child(body)

	var button_row := MenuUiKit.make_button_row()
	var done_btn := MenuUiKit.make_button(I18n.t("settings.done", "Done"), MenuUiKit.ButtonVariant.PRIMARY)
	done_btn.pressed.connect(func():
		if on_close.is_valid():
			on_close.call()
	)
	button_row.add_child(done_btn)
	content.add_child(button_row)

	add_child(MenuUiKit.make_panel(content, false, not embedded))

## Ports .settings-row: label(+hint) on the left, the control flush right.
func _row_shell(label_text: String, hint_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 16)

	var text_col := VBoxContainer.new()
	text_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation", 1)
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(Palette.TEXT_WARM))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_col.add_child(label)
	if hint_text != "":
		var hint := Label.new()
		hint.text = hint_text
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD
		hint.add_theme_font_size_override("font_size", 10)
		hint.add_theme_color_override("font_color", Color(Palette.TEXT_FAINT))
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text_col.add_child(hint)
	row.add_child(text_col)

	control.size_flags_horizontal = Control.SIZE_SHRINK_END
	row.add_child(control)
	return row

func _build_slider_row(label_text: String, key: String, min_v: float, max_v: float, step: float) -> HBoxContainer:
	var control := HBoxContainer.new()
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control.add_theme_constant_override("separation", 8)

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = float(MetaProgression.settings.get(key, min_v))
	slider.custom_minimum_size = Vector2(130.0, 0.0)

	var value_label := Label.new()
	value_label.text = "%.2f" % slider.value
	value_label.custom_minimum_size = Vector2(36.0, 0.0)
	value_label.add_theme_font_size_override("font_size", 12)
	value_label.add_theme_color_override("font_color", Color(Palette.TEXT_DIM))
	value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	slider.value_changed.connect(func(v: float):
		value_label.text = "%.2f" % v
		MetaProgression.save_settings({key: v})
	)
	control.add_child(slider)
	control.add_child(value_label)
	return _row_shell(label_text, "", control)

func _build_toggle_row(label_text: String, hint_text: String, key: String) -> HBoxContainer:
	var toggle := MenuUiKit.make_toggle(bool(MetaProgression.settings.get(key, false)))
	toggle.toggled.connect(func(v: bool):
		MetaProgression.save_settings({key: v})
	)
	return _row_shell(label_text, hint_text, toggle)

func _build_segmented_row(label_text: String, hint_text: String, options: Array, labels: Array, key: String) -> HBoxContainer:
	var current: String = str(MetaProgression.settings.get(key, options[0]))
	var segmented := MenuUiKit.make_segmented(options, labels, current, func(value: String):
		MetaProgression.save_settings({key: value})
	)
	return _row_shell(label_text, hint_text, segmented)

func _build_fullscreen_row() -> HBoxContainer:
	var btn := MenuUiKit.make_button(I18n.t("settings.toggle", "Toggle"), MenuUiKit.ButtonVariant.PLAIN)
	btn.pressed.connect(func():
		var is_fullscreen: bool = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if is_fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)
	)
	return _row_shell(I18n.t("settings.fullscreen", "Fullscreen"), "", btn)
