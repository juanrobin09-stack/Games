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

	var bg := ColorRect.new()
	# Simplified flat wash standing in for the source's own top-to-bottom
	# linear gradient (#0b0910 -> #120c10 -> #1a0f0a) — same "gradient ->
	# flattest identity-defining stop" convention as MenuUiKit.make_overlay,
	# picked at the gradient's own middle stop (the tone that dominates
	# most of the frame).
	bg.color = Color("#120c10")
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_build_ember_particles()

	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 8)
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(content)

	content.add_child(_build_title())

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
	var credits_btn := MenuUiKit.make_button(I18n.t("menu.credits", "Credits"), MenuUiKit.ButtonVariant.GHOST)
	credits_btn.pressed.connect(func():
		var callback: Callable = _callbacks.get("on_credits", Callable())
		if callback.is_valid():
			callback.call()
	)
	button_box.add_child(credits_btn)

	_seed_input = LineEdit.new()
	_seed_input.placeholder_text = I18n.t("menu.seedPlaceholder", "Seed (optional)")
	_seed_input.max_length = 12
	_seed_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_seed_input.custom_minimum_size = Vector2(300.0, 0.0)
	_seed_input.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
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
	content.add_child(_seed_input)

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

## Ports .game-title's crisp-text-plus-soft-glow look (`text-shadow: 0 0
## 40px rgba(255,123,61,0.55), 0 4px 14px rgba(0,0,0,0.7)` — a wide blurred
## halo behind solid letterforms, not an outline). A Label's theme shadow
## is a single pass (offset + outline expansion, all one color) with no
## blur, so shadow_outline_size alone can only fake a *hard* ring around
## each glyph — an earlier draft pushed that ring to 18px for more "glow"
## and it read as a thick cartoon outline instead (flagged against a real
## screenshot). Stacking three Labels — two wide, faint, invisible-fill
## "glow" passes at decreasing outline size and increasing alpha, plus a
## crisp, tightly-outlined text pass on top — is a cheap way to approximate
## a blurred falloff out of hard-edged rings without a shader: the same
## "simplify the CSS effect to its identity-defining parts" call this
## project already makes elsewhere (e.g. MenuUiKit.make_overlay's gradient
## -> flattest-stop simplification), applied to a shadow effect instead of
## a fill.
##
## The wrap is a MarginContainer (zero margins), not a plain Control: a
## plain Control doesn't lay out its children at all, so overlapping the
## layers would mean hand-computing the wrap's own minimum size to reserve
## the right row height in the outer VBoxContainer — tried first, and
## wrong, because a Label's `get_minimum_size()` reads back the
## pre-override default (theme changes not yet propagated) when queried
## before the node is inside the live tree, so the reserved row was too
## short and the subtitle below overlapped into it (caught via a real
## screenshot, not a guess). A Container computes and propagates its own
## minimum size — the max of its children's — through the same tree
## machinery every other screen already relies on, and fits every child
## into that same content rect, which is exactly the overlap this needs.
func _build_title() -> Control:
	var wrap := MarginContainer.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Widest/faintest first so the crisp front layer (added last) draws on
	# top of both glow passes.
	wrap.add_child(_make_title_layer(24, 0.14, false, 0))
	wrap.add_child(_make_title_layer(11, 0.26, false, 0))
	wrap.add_child(_make_title_layer(2, 0.55, true, 2))
	return wrap

## One layer of _build_title()'s stacked-Label glow. `filled` false makes
## an invisible-text, shadow-only glow pass; true is the crisp front layer
## (opaque EMBER5 fill, small outline, slight downward offset for a hint
## of the source's separate `0 4px 14px` grounding drop-shadow — Label's
## single shadow pass can't render that as a true second, differently-
## colored shadow layer, so the offset alone stands in for it here).
func _make_title_layer(outline_size: int, shadow_alpha: float, filled: bool, y_offset: int) -> Label:
	var label := Label.new()
	label.text = "EMBERFALL"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 56)
	label.add_theme_color_override("font_color", Color(Palette.EMBER5) if filled else Color(0.0, 0.0, 0.0, 0.0))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", y_offset)
	label.add_theme_color_override("font_shadow_color", Color(Palette.EMBER4, shadow_alpha))
	label.add_theme_constant_override("shadow_outline_size", outline_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

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
