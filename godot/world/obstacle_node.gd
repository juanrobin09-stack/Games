class_name ObstacleNode
extends StaticBody2D
## Ports entities/Obstacle.ts. Unlike the Web version (a plain data class —
## Game.ts resolves collision against room.obstacles manually every frame),
## this is a real StaticBody2D: move_and_slide() already resolves Player/
## EnemyCharacter movement against any collider on the shared default
## layer/mask (confirmed live in steps 3-5, before any obstacle existed),
## so letting the engine block movement here needs no manual push-out math
## at all. blocksProjectiles stays a plain per-instance flag exactly like
## the source — ProjectileEntity checks it directly (see projectile.gd)
## rather than through physics, since a piercing bolt still needs custom
## per-hit bookkeeping physics collision doesn't give for free.

enum Visual {
	TREE, ROCK, PILLAR, RUBBLE, BRAZIER, CRYSTAL, STATUE, MERCHANT_STALL,
	SHRINE, FUNGUS, SARCOPHAGUS, STAIRS_DOWN, STAIRS_UP,
}

## Wobble seeds for the tree/rock blob silhouettes — matches drawObstacle.ts's
## module-level `SEEDS` constant (a plain literal array, no cross-script
## enum reference, so unlike zone/visual tables this is safe as a top-level
## const — see level_generator.gd's own RUINS_ENCOUNTERS_DATA for precedent).
const BLOB_WOBBLE_SEEDS := [0.1, -0.06, 0.12, -0.09, 0.07, -0.11]

## Ports rendering/ShopAsset.ts's getStallSprite() — the one painted prop in
## the whole project, everything else here being pure `_draw()` procedural
## generation. `assets/textures/shop_stall.png` is a one-time, offline crop
## of the source's own `assets/textures/shop-props.png` sprite sheet, region
## x=948,y=45,w=473,h=385 — deliberately *wider* than ShopAsset.ts's own
## STALL_STONE rect (w=465,h=340): that tighter rect cuts directly through
## the counter's own painted drop shadow at the bottom (confirmed by sampling
## luminance there — it never fades to background within STALL_STONE's own
## bounds), since this sheet packs its props close together with little
## clean margin anywhere. Two things applied to the crop, matching the
## source's own chromaKey() first, this port's own addition second: (1) the
## same luminance chroma-key (pixels with luminance in [10,19] ramp linearly
## to transparent); (2) a 16px alpha feather inward from every crop edge,
## which the source has no equivalent for — this sheet's cramped layout
## means no crop rect can guarantee a fully-faded natural edge on all four
## sides, so the feather forces one, rather than trusting content position
## the way a rect with real breathing room could. Godot's `preload()` is
## synchronous, so there's no load-order reason to redo any of this
## processing on every launch the way the source's lazy `<img>` decode +
## canvas readback effectively forces in a browser.
##
## One more step past the source, added after real in-game screenshots
## (not just the crop fix) still read as "pasted on": the source's own
## sheet is a soft, painterly reference image, but every other visual in
## this entire project is flat-shaded straight `Palette` colors with no
## soft photographic gradients anywhere. Cleaning up the alpha edges wasn't
## enough to close that gap — a technically-clean sprite in the wrong
## rendering register still reads as foreign next to that flat style. RGB
## (never alpha) is pushed toward that same register: +35% contrast, +45%
## saturation, -8% brightness, then posterized to 5 levels/channel to
## flatten lingering soft gradient banding — closer to graphic/flat-shaded
## than photo-painted, without discarding the source's own shading
## structure entirely.
const STALL_TEXTURE := preload("res://assets/textures/shop_stall.png")

var radius: float = 16.0
var visual: Visual = Visual.ROCK
var seed_value: float = 0.0
var blocks_projectiles: bool = false
var lit: bool = false
## World-space orientation (radians). Stairs: the direction they descend/ascend in.
var facing: float = 0.0
## Stateful landmarks (the sealed stairwell) flip this once their condition
## is met — LevelFlow.open_stairs() sets it true when a heart/boss room clears.
var activated: bool = false
var activated_at: float = -1.0

func setup(pos: Vector2, p_radius: float, p_visual: Visual, opts: Dictionary = {}) -> void:
	position = pos
	radius = p_radius
	visual = p_visual
	facing = opts.get("facing", 0.0)
	seed_value = randf() * 1000.0
	var default_blocks: bool = (
		visual == Visual.PILLAR or visual == Visual.STATUE
		or visual == Visual.ROCK or visual == Visual.SARCOPHAGUS
	)
	blocks_projectiles = opts.get("blocks_projectiles", default_blocks)
	var default_lit: bool = (
		visual == Visual.BRAZIER or visual == Visual.CRYSTAL or visual == Visual.MERCHANT_STALL
		or visual == Visual.SHRINE or visual == Visual.FUNGUS
		or visual == Visual.STAIRS_DOWN or visual == Visual.STAIRS_UP
	)
	lit = opts.get("lit", default_lit)
	_apply_shape()

func _ready() -> void:
	# Counters RoomContainer's own z_index = -10 (its floor rect needs to sit
	# behind the player; obstacles shouldn't inherit that and vanish behind it).
	z_as_relative = false
	_apply_shape()
	($Glow as PointLight2D).texture = DrawUtils.glow_texture()

func _apply_shape() -> void:
	var shape: CollisionShape2D = get_node_or_null("CollisionShape2D")
	if shape and shape.shape is CircleShape2D:
		(shape.shape as CircleShape2D).radius = radius

## Every flicker/pulse/sway in _draw() below is driven by Time.get_ticks_msec(),
## not a per-instance elapsed-time field — nothing else here needs a per-frame
## update, so this exists purely to keep asking for a new frame. Only ever
## runs for the active room's obstacles (process_mode is disabled the rest of
## the time — see RoomContainer.set_active()), so this is a handful of
## obstacles at most, not every one that's ever been generated.
func _process(_delta: float) -> void:
	queue_redraw()
	_update_light()

func activate() -> void:
	if activated:
		return
	activated = true
	activated_at = Time.get_ticks_msec() / 1000.0
	queue_redraw()

## Ports Game.ts's registerLights() obstacle loop exactly, including its
## early-continue shape: an unlit obstacle (most visuals — see setup()'s
## default_lit) gets no light at all, stairsDown only lights once activated
## and fades in over the same 1.2s the source uses (a different, deliberate
## constant from the well's own _draw() reveal, which fades over 1.1s), and
## stairsUp lights unconditionally at a fixed warm glow the moment it's
## lit — which for stairsUp is always, from the moment it's placed.
func _update_light() -> void:
	var glow: PointLight2D = $Glow
	if not lit:
		glow.enabled = false
		return
	if visual == Visual.STAIRS_DOWN:
		if not activated:
			glow.enabled = false
			return
		var now: float = Time.get_ticks_msec() / 1000.0
		var reveal: float = clampf((now - activated_at) / 1.2, 0.0, 1.0)
		_set_light(glow, Vector2(cos(facing) * 22.0, sin(facing) * 22.0), 150.0 * reveal, Palette.FUNGUS, 0.6 * reveal)
		return
	if visual == Visual.STAIRS_UP:
		_set_light(glow, Vector2(cos(facing) * 34.0, sin(facing) * 34.0), 120.0, Palette.EMBER3, 0.35)
		return
	var color_hex: String = Palette.SOUL if visual == Visual.CRYSTAL else (Palette.FUNGUS if visual == Visual.FUNGUS else Palette.EMBER4)
	var light_radius: float = 175.0 if visual == Visual.MERCHANT_STALL else (105.0 if visual == Visual.FUNGUS else 120.0)
	var intensity: float = 0.85 if visual == Visual.MERCHANT_STALL else (0.6 if visual == Visual.FUNGUS else 0.75)
	_set_light(glow, Vector2(0.0, -8.0), light_radius, color_hex, intensity)

func _set_light(glow: PointLight2D, offset: Vector2, light_radius: float, color_hex: String, intensity: float) -> void:
	glow.enabled = true
	glow.position = offset
	glow.texture_scale = light_radius / 128.0
	glow.color = Color(color_hex)
	glow.energy = intensity

## Ports drawObstacle.ts's dispatch: a shared contact shadow under every
## grounded obstacle (stairs are a hole in the floor, not a body standing on
## one, so they skip it), then a per-visual silhouette. The source has no
## generic "lit" overlay — each lit visual (brazier, crystal, merchant
## stall, shrine, fungus, both stairs) draws its own real glow as part of
## its own shape below, so `lit` itself is never read here.
func _draw() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	if visual != Visual.STAIRS_DOWN and visual != Visual.STAIRS_UP:
		DrawUtils.draw_soft_shadow(self, 0.0, radius * 0.6, radius * 1.1, radius * 0.4, 0.4)
	match visual:
		Visual.TREE:
			_draw_tree()
		Visual.ROCK:
			_draw_rock()
		Visual.PILLAR:
			_draw_pillar()
		Visual.RUBBLE:
			_draw_rubble()
		Visual.BRAZIER:
			_draw_brazier(now)
		Visual.CRYSTAL:
			_draw_crystal(now)
		Visual.STATUE:
			_draw_statue()
		Visual.MERCHANT_STALL:
			_draw_merchant_stall(now)
		Visual.SHRINE:
			_draw_shrine(now)
		Visual.FUNGUS:
			_draw_fungus(now)
		Visual.SARCOPHAGUS:
			_draw_sarcophagus()
		Visual.STAIRS_DOWN:
			_draw_stairwell(now, true)
		Visual.STAIRS_UP:
			_draw_stairwell(now, false)

# --- Shared geometry helpers for the per-shape functions below. Godot's ---
# --- draw API has no rotated-rect, ellipse or Bézier-curve primitive.   ---

## Rotates a point (in a shape's own unrotated local space) by `angle`
## radians. Used instead of `draw_set_transform`, which would leak its
## transform into any draw call made after it in the same `_draw()`.
func _rot_point(x: float, y: float, angle: float) -> Vector2:
	return Vector2(x, y).rotated(angle)

## A `Rect2(x, y, w, h)` footprint rotated by `angle`, as a 4-point polygon
## for `draw_colored_polygon` (Godot's `Rect2` itself is always axis-aligned).
func _rot_rect_poly(x: float, y: float, w: float, h: float, angle: float) -> PackedVector2Array:
	return PackedVector2Array([
		_rot_point(x, y, angle),
		_rot_point(x + w, y, angle),
		_rot_point(x + w, y + h, angle),
		_rot_point(x, y + h, angle),
	])

## Same rectangle, closed for `draw_polyline` (an outline needs the first
## point repeated at the end).
func _rot_rect_outline(x: float, y: float, w: float, h: float, angle: float) -> PackedVector2Array:
	var pts := _rot_rect_poly(x, y, w, h, angle)
	pts.append(pts[0])
	return pts

## Filled ellipse approximated as a many-sided polygon, optionally spun by
## `rotation` radians (mirrors the optional rotation argument Canvas2D's
## `ctx.ellipse()` takes).
func _draw_filled_ellipse(center: Vector2, rx: float, ry: float, color: Color, rotation: float = 0.0) -> void:
	if rx <= 0.01 or ry <= 0.01:
		return
	var segments := 20
	var pts := PackedVector2Array()
	for i in range(segments + 1):
		var angle: float = (float(i) / float(segments)) * TAU
		var p := Vector2(cos(angle) * rx, sin(angle) * ry)
		if rotation != 0.0:
			p = p.rotated(rotation)
		pts.append(center + p)
	draw_colored_polygon(pts, color)

## Samples a quadratic Bézier curve into straight segments — Canvas2D's
## `quadraticCurveTo` has no direct Godot draw-API equivalent.
func _quad_bezier_points(p0: Vector2, control: Vector2, p1: Vector2, segments: int = 8) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments + 1):
		var t: float = float(i) / float(segments)
		var mt: float = 1.0 - t
		pts.append(p0 * (mt * mt) + control * (2.0 * mt * t) + p1 * (t * t))
	return pts

# --- Per-visual-type silhouettes, one function per Visual enum value. ---
# --- Ports drawObstacle.ts's `switch (o.visual)` case bodies 1:1.      ---

func _draw_tree() -> void:
	# Trunk first so the canopy blob on top of it hides all but a sliver.
	_draw_filled_ellipse(Vector2(0.0, radius * 0.3), radius * 0.35, radius * 0.7, Color("#120f0a"))
	# Radial gradient (upper-left highlight to dark edge) simplified to its midpoint tone.
	var canopy_color := DrawUtils.lerp_color_hex("#232b1a", "#0e130a", 0.5)
	var pts := DrawUtils.blob_points(0.0, -radius * 0.5, radius, 7, 0.18, BLOB_WOBBLE_SEEDS)
	draw_colored_polygon(pts, canopy_color)

func _draw_rock() -> void:
	# Linear gradient (top-left highlight to dark edge) simplified to its midpoint tone.
	var rock_color := DrawUtils.lerp_color_hex("#3a352f", "#171410", 0.5)
	var pts := DrawUtils.blob_points(0.0, 0.0, radius, 6, 0.12, BLOB_WOBBLE_SEEDS)
	draw_colored_polygon(pts, rock_color)

func _draw_pillar() -> void:
	# Source draws a plain 3-piece column (shaft + capital + base) — no
	# crack detail actually appears in drawObstacle.ts's `pillar` case.
	draw_rect(Rect2(-radius * 0.5, -radius * 2.2, radius, radius * 2.6), Color("#1b1720"), true)
	draw_rect(Rect2(-radius * 0.6, -radius * 2.3, radius * 1.2, radius * 0.3), Color("#2c2734"), true)
	draw_rect(Rect2(-radius * 0.6, radius * 0.15, radius * 1.2, radius * 0.3), Color("#2c2734"), true)

func _draw_rubble() -> void:
	var color := Color("#221e1a")
	for i in range(3):
		var a: float = (float(i) / 3.0) * TAU + seed_value
		_draw_filled_ellipse(Vector2(cos(a) * radius * 0.4, sin(a) * radius * 0.3), radius * 0.4, radius * 0.28, color, a)

func _draw_brazier(now: float) -> void:
	draw_colored_polygon(PackedVector2Array([
		Vector2(-radius * 0.5, radius * 0.6),
		Vector2(-radius * 0.3, -radius * 0.2),
		Vector2(radius * 0.3, -radius * 0.2),
		Vector2(radius * 0.5, radius * 0.6),
	]), Color("#2a241c"))
	var flick: float = 0.85 + sin(now * 8.0 + seed_value) * 0.15
	DrawUtils.draw_glow_circle(self, 0.0, -radius * 0.5, radius * 1.8 * flick, Palette.EMBER4, 0.6)
	# Flame silhouette: two quadratic Bézier arcs between the same top/bottom points.
	var flame_top := Vector2(0.0, -radius * 1.1 * flick)
	var flame_bottom := Vector2(0.0, -radius * 0.1)
	var side_a := _quad_bezier_points(flame_top, Vector2(radius * 0.3, -radius * 0.4), flame_bottom, 8)
	var side_b := _quad_bezier_points(flame_bottom, Vector2(-radius * 0.3, -radius * 0.4), flame_top, 8)
	var flame_pts := side_a
	for i in range(1, side_b.size()):
		flame_pts.append(side_b[i])
	draw_colored_polygon(flame_pts, Color(Palette.EMBER5))

func _draw_crystal(now: float) -> void:
	var flick: float = 0.8 + sin(now * 2.0 + seed_value) * 0.2
	DrawUtils.draw_glow_circle(self, 0.0, 0.0, radius * 2.2 * flick, Palette.SOUL, 0.5)
	draw_colored_polygon(PackedVector2Array([
		Vector2(0.0, -radius * 1.4),
		Vector2(radius * 0.5, 0.0),
		Vector2(0.0, radius * 0.6),
		Vector2(-radius * 0.5, 0.0),
	]), Color(Palette.SOUL_BRIGHT))

func _draw_statue() -> void:
	_draw_filled_ellipse(Vector2(0.0, -radius * 0.4), radius * 0.6, radius * 1.3, Color("#211d29"))
	draw_circle(Vector2(0.0, -radius * 1.5), radius * 0.4, Color("#211d29"))
	var eye := Color(Palette.SOUL)
	eye.a = 0.6
	draw_circle(Vector2(0.0, -radius * 1.5), 1.6, eye)

## Ports drawObstacle.ts's 'merchantStall' sprite branch (the source also
## keeps a procedural branch for the one frame before its async image
## decode resolves — no equivalent needed here, since STALL_TEXTURE is
## already fully loaded by the time any node can call _draw()). Sized off
## the sprite's own aspect ratio rather than a hardcoded height so a future
## re-crop of shop_stall.png doesn't need a matching constant update here;
## `spriteW = r * 7.2` is the source's own tuned value. The vertical anchor
## is `-spriteH * 0.53`, not the source's own `0.6` — STALL_TEXTURE's crop
## is taller than ShopAsset.ts's STALL_STONE rect (see the const's own
## comment above), and 0.6 was tuned to THAT shorter crop, where the
## counter sat 60% of the way down; re-deriving it for the new, taller crop
## (0.6 * old_height/new_height = 0.6 * 340/385) keeps the counter anchored
## at the same real position — near the obstacle's own origin, where
## interaction distance is measured from, canopy above it — instead of
## drifting as a side effect of the crop getting taller. No extra
## candle-glow drawn on top: the sprite already paints its own lit candle.
func _draw_merchant_stall(_now: float) -> void:
	var sprite_w: float = radius * 7.2
	var sprite_h: float = sprite_w * (STALL_TEXTURE.get_height() / float(STALL_TEXTURE.get_width()))
	draw_texture_rect(STALL_TEXTURE, Rect2(-sprite_w / 2.0, -sprite_h * 0.53, sprite_w, sprite_h), false)

func _draw_shrine(now: float) -> void:
	var r := radius
	# 3-stop symmetric gradient (dark/light/dark) simplified to its literal middle stop.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-r * 0.9, r * 0.6),
		Vector2(-r * 0.55, -r * 0.15),
		Vector2(r * 0.55, -r * 0.15),
		Vector2(r * 0.9, r * 0.6),
	]), Color("#332b3d"))
	draw_rect(Rect2(-r * 0.65, -r * 0.25, r * 1.3, r * 0.16), Color("#3d3448"), true)
	var rune_color := Color(Palette.SOUL_DIM)
	rune_color.a = 0.55
	var rune_width: float = maxf(1.0, r * 0.05)
	draw_line(Vector2(-r * 0.35, r * 0.15), Vector2(-r * 0.1, r * 0.4), rune_color, rune_width)
	draw_line(Vector2(r * 0.1, r * 0.15), Vector2(r * 0.35, r * 0.4), rune_color, rune_width)
	# Slow, unresolved pulse — this landmark stays ambiguous until the event triggers.
	var pulse: float = 0.7 + sin(now * 1.6 + seed_value) * 0.3
	DrawUtils.draw_glow_circle(self, 0.0, -r * 0.75, r * 1.9 * pulse, Palette.SOUL, 0.45)
	draw_circle(Vector2(0.0, -r * 0.75), r * 0.22 * pulse, Color(Palette.SOUL_BRIGHT))

func _draw_fungus(now: float) -> void:
	# A cluster of bioluminescent caps — non-blocking, and the zone's light source
	# (the actual dynamic light is registered elsewhere; this is just the visual).
	var r := radius
	var glow: float = 0.75 + sin(now * 1.8 + seed_value) * 0.2
	DrawUtils.draw_glow_circle(self, 0.0, -r * 0.2, r * 2.4 * glow, Palette.FUNGUS, 0.32)
	var caps := [
		[-0.55, 0.25, 0.6],
		[0.5, 0.3, 0.7],
		[0.15, -0.5, 0.5],
		[-0.3, -0.35, 0.42],
		[0.0, 0.0, 1.0],
	]
	var highlight_dir := Vector2(-0.3, -0.35).normalized()
	for cap in caps:
		var cx: float = cap[0]
		var cy: float = cap[1]
		var s: float = cap[2]
		var cap_r: float = r * 0.55 * s
		var px: float = cx * r
		var py: float = cy * r
		draw_rect(Rect2(px - cap_r * 0.18, py - cap_r * 0.2, cap_r * 0.36, cap_r * 0.9), Color("#a9b8b0"), true)
		# Cap: radial gradient (bright highlight -> base -> dim edge) approximated
		# as three concentric ellipses shifted toward the highlight corner.
		var cap_center := Vector2(px, py - cap_r * 0.4)
		_draw_filled_ellipse(cap_center, cap_r, cap_r * 0.7, Color(Palette.FUNGUS_DIM))
		_draw_filled_ellipse(cap_center + highlight_dir * cap_r * 0.18, cap_r * 0.75, cap_r * 0.52, Color(Palette.FUNGUS))
		_draw_filled_ellipse(cap_center + highlight_dir * cap_r * 0.32, cap_r * 0.4, cap_r * 0.28, Color(Palette.FUNGUS_BRIGHT))
		draw_circle(Vector2(px - cap_r * 0.3, py - cap_r * 0.6), cap_r * 0.16, Color(1.0, 1.0, 1.0, 0.35))
		draw_circle(Vector2(px + cap_r * 0.35, py - cap_r * 0.42), cap_r * 0.12, Color(1.0, 1.0, 1.0, 0.35))

func _draw_sarcophagus() -> void:
	# The whole coffin sits askew — a fixed per-instance tilt derived from
	# seed (matches source: `(o.seed % 1) * 0.6 - 0.3`), not the `facing` field.
	var tilt: float = fmod(seed_value, 1.0) * 0.6 - 0.3
	var r := radius
	var w := r * 2.7
	var h := r * 1.35
	draw_colored_polygon(_rot_rect_poly(-w / 2 - 3.0, -h / 2 + 3.0, w + 6.0, h + 5.0, tilt), Color("#17141f"))
	# Linear gradient (lid shading, top to bottom) simplified to its midpoint tone.
	var body_color := DrawUtils.lerp_color_hex("#4d4664", "#2a2638", 0.5)
	draw_colored_polygon(_rot_rect_poly(-w / 2, -h / 2 - 6.0, w, h, tilt), body_color)
	draw_polyline(_rot_rect_outline(-w / 2 + 4.0, -h / 2 - 3.0, w - 8.0, h - 7.0, tilt), Color(1.0, 1.0, 1.0, 0.12), 1.5, true)
	# The carved effigy: a long line for the body, a circle for the face.
	draw_line(_rot_point(-w * 0.3, -2.0, tilt), _rot_point(w * 0.28, -2.0, tilt), Color(0.0, 0.0, 0.0, 0.5), 1.4)
	draw_arc(_rot_point(-w * 0.34, -2.0, tilt), r * 0.16, 0.0, TAU, 16, Color(0.0, 0.0, 0.0, 0.5), 1.4, true)
	var chest_color := Color(Palette.FUNGUS_DIM)
	chest_color.a = 0.55
	_draw_filled_ellipse(_rot_point(w * 0.32, h * 0.22 - 6.0, tilt), r * 0.42, r * 0.22, chest_color, tilt + 0.4)

func _ease_in_out_sine(t: float) -> float:
	return -(cos(PI * t) - 1.0) / 2.0

## A stairwell seen from above: a stone-framed rectangular well, six steps
## along `facing`, ending in darkness (going down) or a faint warm light
## from the world above (going up). The descent stairwell starts sealed
## under a rune-carved lid that slides aside once its heart room clears.
## Ports drawObstacle.ts's `drawStairwell` — every point is computed in the
## well's own unrotated local space, then rotated by `facing` on the way
## into a draw call (see _rot_point/_rot_rect_poly) rather than reaching for
## `draw_set_transform`, which would leak into whatever draws next.
func _draw_stairwell(now: float, is_down: bool) -> void:
	var r := radius
	var well_len := r * 2.5
	var well_wid := r * 1.7

	# Worked stone frame (rounded rects simplified to plain rects; both
	# gradients used for the rim are simplified to their literal middle stop).
	draw_colored_polygon(
		_rot_rect_poly(-well_len / 2 - 10.0, -well_wid / 2 - 10.0, well_len + 20.0, well_wid + 20.0, facing),
		Color("#332e44")
	)
	draw_colored_polygon(
		_rot_rect_poly(-well_len / 2 - 7.0, -well_wid / 2 - 7.0, well_len + 14.0, well_wid + 14.0, facing),
		Color("#4f4866")
	)
	draw_polyline(
		_rot_rect_outline(-well_len / 2 - 7.0, -well_wid / 2 - 7.0, well_len + 14.0, well_wid + 14.0, facing),
		Color(0.0, 0.0, 0.0, 0.55), 1.5, true
	)
	# Rim joints.
	for jx in [-well_len * 0.3, 0.0, well_len * 0.3]:
		draw_line(_rot_point(jx, -well_wid / 2 - 7.0, facing), _rot_point(jx, -well_wid / 2, facing), Color(0.0, 0.0, 0.0, 0.35), 1.0)
		draw_line(_rot_point(jx, well_wid / 2, facing), _rot_point(jx, well_wid / 2 + 7.0, facing), Color(0.0, 0.0, 0.0, 0.35), 1.0)

	# The well: six steps along +x, darkening toward the far end when
	# descending, brightening toward it when ascending.
	var steps := 6
	var step_len: float = well_len / float(steps)
	for i in range(steps):
		var t: float = float(i) / float(steps - 1)
		var lum: float = (1.0 - t) if is_down else t
		var shade: float = round(16.0 + lum * 72.0)
		var step_color := Color((shade - 3.0) / 255.0, (shade - 5.0) / 255.0, (shade + 8.0) / 255.0)
		draw_colored_polygon(_rot_rect_poly(-well_len / 2 + i * step_len, -well_wid / 2, step_len + 0.6, well_wid, facing), step_color)
		draw_colored_polygon(
			_rot_rect_poly(-well_len / 2 + i * step_len, -well_wid / 2, 1.6, well_wid, facing),
			Color(1.0, 1.0, 1.0, 0.04 + lum * 0.1)
		)
		draw_colored_polygon(
			_rot_rect_poly(-well_len / 2 + (i + 1) * step_len - 2.2, -well_wid / 2, 2.2, well_wid, facing),
			Color(0.0, 0.0, 0.0, 0.5)
		)

	# Inner side shadows so the well reads as sunken, not painted on (linear
	# fade simplified to a flat translucent strip at roughly its average alpha).
	for side in [-1.0, 1.0]:
		var strip_y: float = (-well_wid / 2) if side < 0.0 else (well_wid / 2 - 12.0)
		draw_colored_polygon(_rot_rect_poly(-well_len / 2, strip_y, well_len, 12.0, facing), Color(0.0, 0.0, 0.0, 0.28))

	# Far end: swallowed by dark (down) or touched by the light above (up).
	# The source uses a linear gradient here; approximated with the same
	# soft-falloff circle already used for every other glow in this file,
	# tinted dark instead of bright for the descent.
	var far_center := _rot_point(well_len / 2, 0.0, facing)
	if is_down:
		DrawUtils.draw_glow_circle(self, far_center.x, far_center.y, well_len * 0.42, Palette.VOID, 0.9)
	else:
		DrawUtils.draw_glow_circle(self, far_center.x, far_center.y, well_len * 0.42, Palette.EMBER3, 0.3)

	if is_down:
		var reveal: float = clampf((now - activated_at) / 1.1, 0.0, 1.0) if activated else 0.0
		if reveal > 0.0:
			var pulse: float = 0.8 + sin(now * 2.2 + seed_value) * 0.2
			var glow_center := _rot_point(well_len * 0.28, 0.0, facing)
			DrawUtils.draw_glow_circle(self, glow_center.x, glow_center.y, well_wid * 0.95 * reveal * pulse, Palette.FUNGUS, 0.42 * reveal)
		# The seal: a carved lid that grinds sideways out of the well and stays
		# lying beside it — a slab that was moved, not one that vanished.
		var slide: float = _ease_in_out_sine(reveal) * (well_wid + 18.0)
		if reveal >= 1.0:
			draw_colored_polygon(
				_rot_rect_poly(-well_len / 2 + 2.0, -well_wid / 2 + 3.0 + slide, well_len + 4.0, well_wid + 4.0, facing),
				Color(0.0, 0.0, 0.0, 0.35)
			)
		# Lid gradient simplified to its literal middle stop.
		draw_colored_polygon(
			_rot_rect_poly(-well_len / 2 - 2.0, -well_wid / 2 - 2.0 + slide, well_len + 4.0, well_wid + 4.0, facing),
			Color("#5c5674")
		)
		draw_polyline(
			_rot_rect_outline(-well_len / 2 - 2.0, -well_wid / 2 - 2.0 + slide, well_len + 4.0, well_wid + 4.0, facing),
			Color(0.0, 0.0, 0.0, 0.55), 2.0, true
		)
		var crack_pts := PackedVector2Array([
			_rot_point(-well_len * 0.42, -well_wid * 0.3 + slide, facing),
			_rot_point(-well_len * 0.2, -well_wid * 0.05 + slide, facing),
			_rot_point(-well_len * 0.3, well_wid * 0.25 + slide, facing),
		])
		draw_polyline(crack_pts, Color(0.0, 0.0, 0.0, 0.3), 1.0, true)
		# The binding rune, pulsing while the seal holds.
		var seam: float = (0.45 + sin(now * 1.5 + seed_value) * 0.2) * (1.0 - reveal)
		var rune_color := Color(Palette.SOUL)
		rune_color.a = seam
		var rune_pts := PackedVector2Array([
			_rot_point(-well_len * 0.36, slide, facing),
			_rot_point(-well_len * 0.12, -well_wid * 0.26 + slide, facing),
			_rot_point(well_len * 0.12, well_wid * 0.26 + slide, facing),
			_rot_point(well_len * 0.36, slide, facing),
		])
		draw_polyline(rune_pts, rune_color, 1.6, true)
		draw_arc(_rot_point(0.0, slide, facing), well_wid * 0.2, 0.0, TAU, 24, rune_color, 1.6, true)
	else:
		var ember_center := _rot_point(well_len * 0.42, 0.0, facing)
		DrawUtils.draw_glow_circle(self, ember_center.x, ember_center.y, well_wid * 0.75, Palette.EMBER3, 0.2 + sin(now * 1.3 + seed_value) * 0.05)

	# Two broken column stubs framing the far end (round tops: rotation-safe).
	for side in [-1.0, 1.0]:
		var px: float = well_len / 2 + 6.0
		var py: float = side * (well_wid / 2 + 8.0)
		draw_circle(_rot_point(px + 2.0, py + 2.0, facing), 9.5, Color(0.0, 0.0, 0.0, 0.35))
		var base_center := _rot_point(px, py, facing)
		draw_circle(base_center, 9.0, Color("#3d374f"))
		draw_circle(base_center, 6.5, Color("#5d5775"))
		draw_line(_rot_point(px - 3.0, py - 4.0, facing), _rot_point(px + 2.0, py + 3.0, facing), Color(0.0, 0.0, 0.0, 0.4), 1.0)
