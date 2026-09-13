class_name MainMenuUI
extends Control
## Ports ui/MainMenu.ts — the title/boot screen. Static factory + callback
## Dictionary, same convention as every other screen this project builds
## (ShopUI.show_shop, UpgradeSelectUI.show_choices, ...); not a modal (no
## get_tree().paused — nothing is running behind it to pause).
##
## The rising ember-mote background (spawnMote/tick in the source, a
## hand-rolled Canvas2D per-frame particle loop) is rewritten against
## GPUParticles2D instead of ported line-for-line — GODOT_MIGRATION.md §4
## is explicit that particles are a "rewrite, don't port" case, and this
## project's own VfxPresets/VfxSystem (step 8) already made that call for
## every triggered gameplay burst. A continuous ambient background is a
## different USAGE than those one-shot bursts (this needs `emitting =
## true` left on indefinitely, not a single emit() call), so it's built
## directly here rather than through VfxSystem's one-shot-oriented API.

const CANVAS_WIDTH := 1152.0
const CANVAS_HEIGHT := 648.0

## A real reference logo (carved-stone/ember-fire "EMBERFALL" wordmark),
## replacing an earlier from-scratch attempt at approximating this look
## out of Label theme shadows — no amount of stacked shadow passes gets
## close to hand-authored stone/fire art. Source came in as an opaque
## RGB render on a solid near-black backdrop (~4-7 out of 255, sampled
## at every corner); keyed to real alpha with a brightness ramp
## (fully transparent at/below 10, fully opaque at/above 34, linear
## between) rather than a hard cutoff, so the art's own soft glow
## bloom fades out naturally instead of ending in a hard-edged ring —
## verified by compositing over both a checkerboard (letter counters
## like B/R punch through to transparent, same as the true background;
## no dark fringe at any edge) and the menu's own #120c10 backdrop
## (seamless, no visible rectangle boundary). Pre-cropped to the keyed
## content's own bounding box so TITLE_LOGO_TEXTURE.get_size() reflects
## real art bounds, not the source frame's empty margins.
const TITLE_LOGO_TEXTURE := preload("res://assets/textures/title_logo.png")
const TITLE_LOGO_WIDTH := 520.0

## Same reference upload as TITLE_LOGO_TEXTURE, one crop further:
## the mockup was a full menu composite (logo + French button labels
## baked as flat pixels over an illustrated dungeon-corridor scene), not
## a directly usable asset on its own — those baked buttons aren't the
## real, functional, i18n'd ones this screen already builds, and would
## sit at the wrong position/size/language under them. What IS reusable
## is the illustration itself: cropped to the region clear of every
## baked letter and button edge (verified visually — a first cut at the
## seam still had stray glyph fragments bleeding in from the left, so
## the crop moved right until a full recheck showed none), all the way
## to the source frame's right edge. Left as a portrait-ish crop rather
## than pre-fit to the canvas's own 16:9 — STRETCH_KEEP_ASPECT_COVERED
## below does that fit at draw time, uniformly scaled with no distortion
## to the architecture, so this file doesn't need updating if the canvas
## size ever changes.
const MAIN_MENU_BG_TEXTURE := preload("res://assets/textures/main_menu_bg.png")

## Keys: on_play (Callable(String) -> void, seed text or "" for random),
## on_upgrades/on_armory/on_settings/on_credits (Callable() -> void).
var _callbacks: Dictionary = {}
var _seed_input: LineEdit

static func show_main_menu(parent: Node, callbacks: Dictionary) -> MainMenuUI:
	var ui := MainMenuUI.new()
	ui._callbacks = callbacks
	parent.add_child(ui)
	ui._build()
	return ui

func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0

	var bg := TextureRect.new()
	bg.texture = MAIN_MENU_BG_TEXTURE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# COVERED, not the plain KEEP_ASPECT this file's other texture (the
	# title logo) uses: that one sizes ITSELF to fit a target width, but
	# this one must fill the whole 1152x648 rect with no gaps, the way a
	# background always has to — COVERED scales up until both dimensions
	# are satisfied and crops the overflow, same idea as CSS's own
	# `background-size: cover`, rather than distorting the art's aspect
	# ratio to force an exact fit.
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# The illustration's own torch flame sits close to screen-center —
	# right behind the "Last Light" subtitle and footer tagline, both
	# plain Labels with no opaque panel behind them (unlike the buttons,
	# which carry their own solid StyleBoxFlat fill regardless of what's
	# under them). Checked directly against a screenshot: text there was
	# still technically legible but noticeably lower-contrast against the
	# bright fire than it ever was against the old flat backdrop. A flat
	# dark scrim over the whole scene — the same fix the reference mockup
	# itself uses (its own baked UI sits on a darkened gradient over the
	# identical art) — restores that contrast everywhere at once rather
	# than patching a panel behind each affected Label individually.
	var scrim := ColorRect.new()
	scrim.color = Color(0.0, 0.0, 0.0, 0.4)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)

	_build_ember_particles()

	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 8)
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(content)

	var title := TextureRect.new()
	title.texture = TITLE_LOGO_TEXTURE
	title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	var logo_size := TITLE_LOGO_TEXTURE.get_size()
	title.custom_minimum_size = Vector2(TITLE_LOGO_WIDTH, TITLE_LOGO_WIDTH * logo_size.y / logo_size.x)
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Last Light"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", Color(Palette.TEXT_DIM))
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 26.0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(spacer)

	var button_box := VBoxContainer.new()
	button_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button_box.custom_minimum_size = Vector2(300.0, 0.0)
	# custom_minimum_size alone sets a MINIMUM, not a fixed width —
	# VBoxContainer still stretches a plain child to fill its own full
	# width (content spans the whole 1152px screen via PRESET_FULL_RECT)
	# unless told not to grow past its minimum.
	button_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button_box.add_theme_constant_override("separation", 10)
	content.add_child(button_box)

	var play_btn := MenuUiKit.make_button(I18n.t("menu.play", "Play"), MenuUiKit.ButtonVariant.PRIMARY)
	play_btn.pressed.connect(func():
		var callback: Callable = _callbacks.get("on_play", Callable())
		if callback.is_valid():
			callback.call(_seed_input.text)
	)
	button_box.add_child(play_btn)
	_add_nav_button(button_box, I18n.t("menu.upgrades", "Upgrades"), "on_upgrades")
	_add_nav_button(button_box, I18n.t("menu.armory", "Armory"), "on_armory")
	_add_nav_button(button_box, I18n.t("menu.settings", "Settings"), "on_settings")

	# Seed now takes Credits' old slot (end of the button column) and
	# Credits takes Seed's old slot (its own row below the column) — a
	# straight swap of the two rows' positions, nothing else about either
	# one changed.
	_seed_input = LineEdit.new()
	_seed_input.placeholder_text = I18n.t("menu.seedPlaceholder", "Seed (optional)")
	_seed_input.max_length = 12
	_seed_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_seed_input.add_theme_font_size_override("font_size", 13)
	_seed_input.add_theme_color_override("font_color", Color(Palette.TEXT_WARM))
	_seed_input.add_theme_color_override("font_placeholder_color", Color(Palette.TEXT_FAINT))
	var field_style := StyleBoxFlat.new()
	field_style.bg_color = Color(Palette.BG1)
	field_style.border_color = Color(Palette.BORDER)
	field_style.set_border_width_all(1)
	field_style.set_corner_radius_all(6)
	field_style.content_margin_left = 10.0
	field_style.content_margin_right = 10.0
	field_style.content_margin_top = 6.0
	field_style.content_margin_bottom = 6.0
	_seed_input.add_theme_stylebox_override("normal", field_style)
	_seed_input.add_theme_stylebox_override("focus", field_style)
	button_box.add_child(_seed_input)

	var credits_btn := MenuUiKit.make_button(I18n.t("menu.credits", "Credits"), MenuUiKit.ButtonVariant.GHOST)
	credits_btn.pressed.connect(func():
		var callback: Callable = _callbacks.get("on_credits", Callable())
		if callback.is_valid():
			callback.call()
	)
	# custom_minimum_size/SHRINK_CENTER: the width constraint button_box
	# itself (its own custom_minimum_size(300, 0)) gave every button for
	# free as a direct child now has to be set explicitly here instead,
	# since content (credits_btn's new direct parent) spans the full
	# 1152px canvas with no such constraint of its own — without this a
	# plain Button's default SIZE_FILL would stretch Credits edge to edge
	# instead of matching the column's own width, the same fixed-width-
	# and-centered treatment the seed field used to need in this exact
	# slot.
	credits_btn.custom_minimum_size = Vector2(300.0, 0.0)
	credits_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(credits_btn)

	var footer := Label.new()
	footer.text = I18n.t("menu.tagline", "The Ember is dying. Someone must carry the last light.")
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 12)
	footer.add_theme_color_override("font_color", Color(Palette.TEXT_FAINT))
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	footer.offset_top = -30.0
	footer.offset_bottom = -12.0
	footer.offset_left = -300.0
	footer.offset_right = 300.0
	add_child(footer)

func _add_nav_button(column: VBoxContainer, text: String, callback_key: String) -> void:
	var btn := MenuUiKit.make_button(text, MenuUiKit.ButtonVariant.PLAIN)
	btn.pressed.connect(func():
		var callback: Callable = _callbacks.get(callback_key, Callable())
		if callback.is_valid():
			callback.call()
	)
	column.add_child(btn)

## Ports the source's 46-mote rising-ember field: spawns at the bottom
## edge (and, once, scattered at random heights so the very first frame
## isn't empty), drifts upward with light horizontal jitter, and loops —
## GPUParticles2D's own lifetime-based emission handles the loop natively,
## no manual respawn-on-reaching-the-top logic needed the way the source's
## hand-rolled tick() has to.
func _build_ember_particles() -> void:
	var particles := GPUParticles2D.new()
	particles.amount = 46
	# Motes need to travel the full CANVAS_HEIGHT + 40 (bottom spawn margin
	# to top despawn margin) before recycling, the way the source's own
	# tick() only respawns a mote once `mote.y < -20` — at the slowest
	# initial_velocity_min (18 px/s) that's (648+40)/18 ≈ 38s. A first cut
	# left this at 5.0 (a copy-paste from an early draft, never tuned
	# against the actual travel distance) — confirmed via a real screenshot
	# showing every ember dying out around a third of the way up, leaving
	# the top ~80% of the screen completely empty. 24s is sized to the
	# *average* of the 18-44 px/s velocity range instead of the slowest
	# case: slow motes now reach comfortably past mid-screen and fast ones
	# reach the very top before recycling — GPUParticles2D has no
	# equivalent to the source's mid-flight "y < -20" cutoff, so a single
	# fixed lifetime can't be exactly right for every speed in the range,
	# and biasing toward the slowest one would just under-fill the top edge
	# instead of the bottom. preprocess == lifetime keeps pre-warming the
	# whole cycle (ages spread 0..lifetime) so frame 1 already shows motes
	# distributed across the full height, matching the source's own
	# `spawnMote(true)` random-Y seeding on init.
	particles.lifetime = 24.0
	particles.preprocess = 24.0
	particles.local_coords = true
	particles.position = Vector2(CANVAS_WIDTH / 2.0, CANVAS_HEIGHT + 20.0)

	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(CANVAS_WIDTH / 2.0, 4.0, 0.0)
	material.direction = Vector3(0.0, -1.0, 0.0)
	material.spread = 12.0
	material.initial_velocity_min = 18.0
	material.initial_velocity_max = 44.0
	material.gravity = Vector3.ZERO
	# DrawUtils.glow_texture() is a 256x256 texture at scale 1.0 (its own
	# native-radius doc comment) — a scale near 1.0, right for a
	# PointLight2D's own 100+px glow radius, would render each ember as a
	# 250+px blown-out circle here; 0.02-0.05 instead targets the small
	# ~5-13px glowing dot the source's own motes actually are.
	material.scale_min = 0.02
	material.scale_max = 0.05
	material.color = Color(Palette.EMBER5)
	var fade := Gradient.new()
	fade.colors = PackedColorArray([Color(Palette.EMBER5, 0.0), Color(Palette.EMBER5, 0.75), Color(Palette.EMBER4, 0.0)])
	fade.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	material.alpha_curve = fade_texture
	particles.process_material = material

	# DrawUtils.glow_texture() — the same soft radial-falloff texture
	# every PointLight2D in this project already reuses (enemy.gd/boss.gd's
	# own Glow child nodes) — is exactly the "small glowing dot" look an
	# ember mote wants, so this reuses it rather than generating a new
	# one-off texture just for this screen.
	particles.texture = DrawUtils.glow_texture()
	var blend := CanvasItemMaterial.new()
	blend.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	particles.material = blend

	# GPUParticles2D is a Node2D, not a Control — no mouse_filter to set
	# (unlike everything else this file builds); it never intercepts input
	# regardless.
	particles.emitting = true
	add_child(particles)
