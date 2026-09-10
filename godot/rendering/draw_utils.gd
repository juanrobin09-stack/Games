class_name DrawUtils
extends RefCounted
## Ports rendering/DrawUtils.ts's shared drawing primitives (build-order
## step 7) — the small set every per-entity draw function in this pass
## actually calls. Two of the source's helpers aren't ported: roundedRectPath
## (Godot's immediate-mode _draw() has no rounded-rect primitive; callers
## use a plain draw_rect instead — a deliberate, noted simplification, not
## an oversight) and drawFloatingText (damage numbers/XP popups are a
## feedback/particle concern, step 8-9, not exercised by anything this
## step draws).
##
## Canvas2D's radial gradients (drawSoftShadow, drawGlowCircle) have no
## immediate-mode equivalent in Godot's _draw() — both are approximated
## here with a handful of concentric shapes fading in alpha, which reads
## as "soft" from normal play distance without needing a shader.
##
## Every function takes `canvas: CanvasItem` as the node to draw ON —
## always call these from inside that same node's own _draw(), passing self.

static func draw_soft_shadow(canvas: CanvasItem, x: float, y: float, rx: float, ry: float, alpha: float = 0.45) -> void:
	var steps := 4
	for i in range(steps, 0, -1):
		var t: float = float(i) / float(steps)
		var a: float = alpha * (1.0 - t) * (1.0 - t)
		if a <= 0.004:
			continue
		_draw_ellipse(canvas, Vector2(x, y), rx * t, ry * t, Color(0.0, 0.0, 0.0, a))

static func draw_glow_circle(canvas: CanvasItem, x: float, y: float, radius: float, color: String, core_alpha: float = 0.9) -> void:
	var base := Color(color)
	var steps := 5
	for i in range(steps, 0, -1):
		var t: float = float(i) / float(steps)
		var a: float = core_alpha * pow(1.0 - t, 2.0)
		if a <= 0.004:
			continue
		canvas.draw_circle(Vector2(x, y), radius * t, Color(base.r, base.g, base.b, a))

static func _draw_ellipse(canvas: CanvasItem, center: Vector2, rx: float, ry: float, color: Color) -> void:
	if rx <= 0.01 or ry <= 0.01:
		return
	var points := PackedVector2Array()
	var segments := 20
	for i in range(segments + 1):
		var angle: float = (float(i) / float(segments)) * TAU
		points.append(center + Vector2(cos(angle) * rx, sin(angle) * ry))
	canvas.draw_colored_polygon(points, color)

## Organic blob silhouette via a wobbled polygon — reused for cloaks,
## blobs, ash creatures. Returns points for the caller to pass to
## draw_colored_polygon (or draw_polyline for an outline-only look).
static func blob_points(cx: float, cy: float, radius: float, points: int, wobble: float, seed_offsets: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in range(points + 1):
		var angle: float = (float(i) / float(points)) * TAU
		var r: float = radius * (1.0 + wobble * float(seed_offsets[i % seed_offsets.size()]))
		result.append(Vector2(cx + cos(angle) * r, cy + sin(angle) * r))
	return result

static func lerp_color_hex(a: String, b: String, t: float) -> Color:
	return Color(a).lerp(Color(b), t)

## Cheap deterministic pseudo-random per-entity "seed jitter" for idle
## wobble — same formula as the source, so the same seed/salt pair
## produces the same jitter value here as it would there.
static func hash_jitter(seed_val: float, salt: float) -> float:
	var x: float = sin(seed_val * 127.1 + salt * 311.7) * 43758.5453123
	return x - floor(x)
