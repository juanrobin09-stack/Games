class_name VfxSystem
extends RefCounted
## Ports rendering/ParticleSystem.ts's engine half onto GPUParticles2D
## (build-order step 8). Per GODOT_MIGRATION.md §4/§6: "rewrite, don't
## port — trigger built-in particle nodes/presets instead of hand-rolled
## particle math." ParticleSystem.ts's fixed-capacity pool with its own
## update()/render() only exists because Canvas2D has no native particle
## system; Godot's GPUParticles2D already does everything that hand-rolled
## loop did, so there's nothing to preserve about ITS implementation, only
## the visual result each ParticlePresets.ts function produces.
##
## emit() takes a Dictionary shaped like TS's ParticleOptions (same
## concepts, snake_case names) and builds ONE one-shot GPUParticles2D that
## reproduces it, freeing itself via the `finished` signal once its
## particles are done. Where TS's burst() calls a maker closure once per
## particle to roll fresh random values by hand, `count` here just widens
## size/speed/life to a min/max range and lets GPUParticles2D's own native
## per-particle randomization do the rest — one node emits the whole burst
## at once (explosiveness = 1.0), not `count` separate calls.
##
## Every emission uses a simple direction+spread+speed cone rather than
## trying to reproduce each preset's exact per-particle vx/vy formula —
## close enough to read as the same effect, and exactly the granularity
## GODOT_MIGRATION.md's "rewrite" framing allows. Two recurring TS patterns
## don't have a direct cone equivalent and are approximated where used
## (documented at each VfxPresets call, not here): a constant extra
## vertical bias added on top of a radial burst (spawnSporeBurstVfx,
## spawnStoneChips) is dropped — folded into the cone's own randomness
## rather than modeled separately; and independent vx/vy jitter ranges
## (spawnSporeMote, spawnHealSparkle, spawnRitualIgnite's burst half) become
## a narrow upward cone instead.
##
## Rotation: every preset this step ports leaves TS's rotation/spin at
## their default of 0 (verified against every ParticlePresets.ts call site
## in scope — none set either field), which is also Godot's
## angle_min/max/angular_velocity_min/max default, so this never sets them.

## Native reference size baked into each shape texture, i.e. what
## texture_scale = 1.0 renders at. "circle"/"spark" share DrawUtils'
## existing glow_texture() (256px wide -> 128px native radius); "ring" and
## "square" are built locally just below. Circle/spark/ring are sized by
## radius (matching Canvas2D's ctx.arc-based originals); square is sized
## by full width (matching the source's ctx.fillRect(-size/2, -size/2,
## size, size)) — _texture_scale_for() below applies whichever convention
## the shape actually uses.
const CIRCLE_NATIVE_RADIUS := 128.0
const RING_NATIVE_RADIUS := 64.0
const SQUARE_NATIVE_WIDTH := 64.0

static var _ring_texture: GradientTexture2D = null
static var _square_texture: GradientTexture2D = null

## A soft annulus: transparent core, a feathered band of full opacity,
## transparent again past the edge — the closest a radial gradient fill
## can get to Canvas2D's stroked-circle-outline "ring" shape. Godot has no
## true stroke-only draw primitive to lean on here any more than DrawUtils
## did for _draw() shapes.
static func ring_texture() -> GradientTexture2D:
	if _ring_texture == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.55, 0.63, 0.77, 0.85, 1.0])
		gradient.colors = PackedColorArray([
			Color(1.0, 1.0, 1.0, 0.0),
			Color(1.0, 1.0, 1.0, 0.0),
			Color(1.0, 1.0, 1.0, 1.0),
			Color(1.0, 1.0, 1.0, 1.0),
			Color(1.0, 1.0, 1.0, 0.0),
			Color(1.0, 1.0, 1.0, 0.0),
		])
		var tex := GradientTexture2D.new()
		tex.gradient = gradient
		tex.width = 128
		tex.height = 128
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		_ring_texture = tex
	return _ring_texture

## A flat, fully opaque square — two identical gradient stops produce a
## uniform fill regardless of fill mode, so this needs no Image/pixel work
## at all (that API's exact Godot-version signature isn't something this
## project can verify against a live editor — see DrawUtils.glow_texture()'s
## own header for the same reasoning).
static func square_texture() -> GradientTexture2D:
	if _square_texture == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 1.0])
		gradient.colors = PackedColorArray([Color(1.0, 1.0, 1.0, 1.0), Color(1.0, 1.0, 1.0, 1.0)])
		var tex := GradientTexture2D.new()
		tex.gradient = gradient
		tex.width = 64
		tex.height = 64
		_square_texture = tex
	return _square_texture

static func _texture_for(shape: String) -> Texture2D:
	match shape:
		"ring":
			return ring_texture()
		"square":
			return square_texture()
		_:
			return DrawUtils.glow_texture()

static func _native_reference_for(shape: String) -> float:
	match shape:
		"ring":
			return RING_NATIVE_RADIUS
		"square":
			return SQUARE_NATIVE_WIDTH
		_:
			return CIRCLE_NATIVE_RADIUS

## opts keys (all optional except position/size_min/color/life_min):
##   position: Vector2, count: int (default 1)
##   direction_deg: float (default 0.0), spread_deg: float (default 180.0 — full circle)
##   speed_min/speed_max: float (default 0.0)
##   gravity: float (default 0.0, +Y is down, matches Canvas2D/TS convention)
##   drag: float (default 0.0)
##   size_min: float (required), size_max: float (default size_min)
##   end_size_ratio: float (default 0.3, matches ParticleOptions.endSize's own default of size*0.3)
##   color: String hex (required), end_color: String hex (default color — no color shift, alpha-only fade)
##   alpha: float (default 1.0), end_alpha: float (default 0.0)
##   life_min: float (required), life_max: float (default life_min)
##   glow: bool (default false), shape: String (default "circle")
static func emit(parent: Node, opts: Dictionary) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var shape: String = opts.get("shape", "circle")
	var size_min: float = opts["size_min"]
	var size_max: float = opts.get("size_max", size_min)
	var life_min: float = opts["life_min"]
	var life_max: float = opts.get("life_max", life_min)
	var color_hex: String = opts["color"]
	var end_color_hex: String = opts.get("end_color", color_hex)
	var native_ref: float = _native_reference_for(shape)

	var mat := ParticleProcessMaterial.new()
	var dir_rad: float = deg_to_rad(opts.get("direction_deg", 0.0))
	mat.direction = Vector3(cos(dir_rad), sin(dir_rad), 0.0)
	mat.spread = opts.get("spread_deg", 180.0)
	mat.initial_velocity_min = opts.get("speed_min", 0.0)
	mat.initial_velocity_max = opts.get("speed_max", 0.0)
	mat.gravity = Vector3(0.0, opts.get("gravity", 0.0), 0.0)
	var drag: float = opts.get("drag", 0.0)
	mat.damping_min = drag
	mat.damping_max = drag
	mat.scale_min = size_min / native_ref
	mat.scale_max = size_max / native_ref

	var end_ratio: float = opts.get("end_size_ratio", 0.3)
	var scale_curve := Curve.new()
	scale_curve.min_value = 0.0
	scale_curve.max_value = 10.0
	scale_curve.add_point(Vector2(0.0, 1.0))
	scale_curve.add_point(Vector2(1.0, end_ratio))
	var scale_curve_tex := CurveTexture.new()
	scale_curve_tex.curve = scale_curve
	mat.scale_curve = scale_curve_tex

	var alpha: float = opts.get("alpha", 1.0)
	var end_alpha: float = opts.get("end_alpha", 0.0)
	var color_gradient := Gradient.new()
	color_gradient.offsets = PackedFloat32Array([0.0, 1.0])
	var start_c := Color(color_hex)
	start_c.a = alpha
	var end_c := Color(end_color_hex)
	end_c.a = end_alpha
	color_gradient.colors = PackedColorArray([start_c, end_c])
	var color_ramp_tex := GradientTexture1D.new()
	color_ramp_tex.gradient = color_gradient
	mat.color_ramp = color_ramp_tex

	var particles := GPUParticles2D.new()
	particles.position = opts.get("position", Vector2.ZERO)
	particles.amount = maxi(1, opts.get("count", 1))
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.local_coords = false
	particles.lifetime = (life_min + life_max) * 0.5
	var life_span: float = life_max - life_min
	var life_mid: float = maxf(0.0001, (life_min + life_max) * 0.5)
	particles.randomness = clampf(life_span / life_mid, 0.0, 1.0)
	particles.process_material = mat
	particles.texture = _texture_for(shape)
	if opts.get("glow", false):
		var canvas_mat := CanvasItemMaterial.new()
		canvas_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		particles.material = canvas_mat

	parent.add_child(particles)
	particles.emitting = true
	particles.finished.connect(particles.queue_free)
