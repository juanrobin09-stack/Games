class_name UiIcons
extends RefCounted
## Ports ui/icons.ts's 19 stroke SVG icons (build-order step 9) as direct
## Godot draw calls — the same "procedurally drawn, no external assets"
## approach this whole project already uses for every entity silhouette
## (build-order step 7), rather than importing 19 .svg files through an
## asset pipeline this environment has no editor to verify against.
##
## Every icon's source path lives in a 24x24 SVG viewBox; draw() maps that
## space onto whatever size/center the caller wants, centered on (12, 12).
## Most paths (blade, crit, critDamage, ability, projectile, area,
## lifesteal's checkmark, armor's checkmark, regen, luck, stamina, range,
## haste) are straight lines/circles/arcs already and are ported exactly.
## A handful (boots, heart, ember/burn's flame, dodge, magnet, shield,
## bow) use cubic/quadratic Bézier curves or elliptical arcs in the source
## that a 14-22px glyph doesn't need bit-for-bit — those are drawn as a
## close, recognizable straight-line/arc approximation of the same
## silhouette instead of sampling exact Bézier control points for a shape
## this small. Called from a Control's own _draw() with `canvas = self`.

const VIEWBOX_CENTER := 12.0

static func _p(x: float, y: float, s: float) -> Vector2:
	return Vector2((x - VIEWBOX_CENTER) * s, (y - VIEWBOX_CENTER) * s)

static func _line(canvas: CanvasItem, pts: Array, s: float, color: Color, width: float) -> void:
	var mapped := PackedVector2Array()
	for pt in pts:
		mapped.append(_p(pt.x, pt.y, s))
	canvas.draw_polyline(mapped, color, width, true)

static func _circle_outline(canvas: CanvasItem, cx: float, cy: float, r: float, s: float, color: Color, width: float) -> void:
	canvas.draw_arc(_p(cx, cy, s), r * s, 0.0, TAU, 32, color, width, true)

## Ports the source's stroke-dasharray="3 3" outer ring (the 'area' icon) —
## same alternating-arc-segments technique enemy.gd's own
## _draw_dashed_circle (build-order step 7) already uses for telegraph rings.
static func _dashed_circle(canvas: CanvasItem, cx: float, cy: float, r: float, s: float, color: Color, width: float) -> void:
	var center := _p(cx, cy, s)
	var radius := r * s
	var circumference: float = TAU * radius
	var dash_count: int = maxi(6, int(circumference / (3.0 * s * 1.4)))
	var step: float = TAU / float(dash_count)
	for i in range(dash_count):
		if i % 2 != 0:
			continue
		var a0: float = i * step
		var a1: float = a0 + step
		canvas.draw_arc(center, radius, a0, a1, 4, color, width, true)

static func draw(canvas: CanvasItem, icon_id: String, size: float, color: Color) -> void:
	var s: float = size / 24.0
	var w: float = maxf(1.0, 1.7 * s)
	match icon_id:
		"blade": _draw_blade(canvas, s, color, w)
		"boots": _draw_boots(canvas, s, color, w)
		"heart", "lifesteal": _draw_heart(canvas, s, color, w, icon_id == "lifesteal")
		"crit": _draw_star(canvas, s, color, w)
		"critDamage": _draw_crit_damage(canvas, s, color, w)
		"dodge": _draw_dodge(canvas, s, color, w)
		"ability": _draw_ability(canvas, s, color, w)
		"ember", "burn": _draw_flame(canvas, s, color, w, icon_id == "burn")
		"magnet": _draw_magnet(canvas, s, color, w)
		"projectile": _draw_projectile(canvas, s, color, w)
		"area": _draw_area(canvas, s, color, w)
		"shield", "armor": _draw_shield(canvas, s, color, w, icon_id == "armor")
		"regen": _draw_regen(canvas, s, color, w)
		"luck": _draw_luck(canvas, s, color, w)
		"stamina": _draw_stamina(canvas, s, color, w)
		"range": _draw_range(canvas, s, color, w)
		"haste": _draw_haste(canvas, s, color, w)
		"bow": _draw_bow(canvas, s, color, w)
		_: _draw_blade(canvas, s, color, w)

static func _draw_blade(canvas: CanvasItem, s: float, color: Color, w: float) -> void:
	_line(canvas, [Vector2(5, 19), Vector2(16, 8)], s, color, w)
	_line(canvas, [Vector2(16, 8), Vector2(19, 5), Vector2(21, 7), Vector2(18, 10)], s, color, w)
	_line(canvas, [Vector2(16, 8), Vector2(13, 5), Vector2(11, 7), Vector2(14, 10)], s, color, w)
	_line(canvas, [Vector2(5, 19), Vector2(3, 21)], s, color, w)
	_line(canvas, [Vector2(5, 19), Vector2(7, 21)], s, color, w)

## Approximated: source's cubic-bezier heel + elliptical toe arc become a
## straight-lined boot silhouette plus one arc for the toe curve.
static func _draw_boots(canvas: CanvasItem, s: float, color: Color, w: float) -> void:
	_line(canvas, [
		Vector2(6, 3), Vector2(6, 12), Vector2(3, 16), Vector2(3, 19), Vector2(11, 19),
		Vector2(11, 15), Vector2(16, 15),
	], s, color, w)
	canvas.draw_arc(_p(16, 12, s), 3.0 * s, deg_to_rad(0.0), deg_to_rad(120.0), 8, color, w, true)
	_line(canvas, [Vector2(19, 11), Vector2(19, 8), Vector2(15, 8), Vector2(13, 8), Vector2(13, 3), Vector2(6, 3)], s, color, w)

## Approximated with the classic "two circles + a V" heart construction
## instead of the source's exact cubic-bezier lobes.
static func _draw_heart(canvas: CanvasItem, s: float, color: Color, w: float, with_check: bool) -> void:
	var lobe_r: float = 3.6
	canvas.draw_arc(_p(8.7, 7.2, s), lobe_r * s, deg_to_rad(150.0), deg_to_rad(470.0), 16, color, w, true)
	canvas.draw_arc(_p(15.3, 7.2, s), lobe_r * s, deg_to_rad(70.0), deg_to_rad(390.0), 16, color, w, true)
	_line(canvas, [Vector2(3.3, 9.5), Vector2(12, 20), Vector2(20.7, 9.5)], s, color, w)
	if with_check:
		_line(canvas, [Vector2(9, 11), Vector2(10.5, 12.5), Vector2(15, 8)], s, color, w)

static func _draw_star(canvas: CanvasItem, s: float, color: Color, w: float) -> void:
	_line(canvas, [
		Vector2(12, 2), Vector2(14.2, 8.8), Vector2(21, 8.8), Vector2(15.4, 12.9), Vector2(17.5, 19.8),
		Vector2(12, 15.8), Vector2(6.5, 19.8), Vector2(8.6, 12.9), Vector2(3, 8.8), Vector2(9.2, 8.8), Vector2(12, 2),
	], s, color, w)

static func _draw_crit_damage(canvas: CanvasItem, s: float, color: Color, w: float) -> void:
	_line(canvas, [Vector2(13, 2), Vector2(4, 14), Vector2(10, 14), Vector2(9, 22), Vector2(18, 10), Vector2(12, 10), Vector2(13, 2)], s, color, w)

## Approximated: the source's two swoosh cubic-beziers become plain arcs.
static func _draw_dodge(canvas: CanvasItem, s: float, color: Color, w: float) -> void:
	canvas.draw_arc(_p(9.5, 17.0, s), 6.5 * s, deg_to_rad(215.0), deg_to_rad(280.0), 10, color, w, true)
	_line(canvas, [Vector2(11, 5), Vector2(14, 8), Vector2(11, 11)], s, color, w)
	canvas.draw_arc(_p(20.0, 12.0, s), 6.0 * s, deg_to_rad(-65.0), deg_to_rad(65.0), 10, color, w, true)

static func _draw_ability(canvas: CanvasItem, s: float, color: Color, w: float) -> void:
	_circle_outline(canvas, 12, 12, 3.2, s, color, w)
	for pt_pair in [[Vector2(12, 3), Vector2(12, 6)], [Vector2(12, 18), Vector2(12, 21)], [Vector2(3, 12), Vector2(6, 12)], [Vector2(18, 12), Vector2(21, 12)]]:
		_line(canvas, pt_pair, s, color, w)
	for pt_pair in [[Vector2(6, 6), Vector2(8, 8)], [Vector2(16, 16), Vector2(18, 18)], [Vector2(18, 6), Vector2(16, 8)], [Vector2(8, 16), Vector2(6, 18)]]:
		_line(canvas, pt_pair, s, color, w)

## Approximated: the source's flame is one continuous cubic-bezier blob;
## this walks the same rough silhouette (narrow top, bulge, tapered base)
## as a closed straight-line polygon instead.
static func _draw_flame(canvas: CanvasItem, s: float, color: Color, w: float, with_curl: bool) -> void:
	_line(canvas, [
		Vector2(12, 2), Vector2(10.3, 6), Vector2(10, 8.3), Vector2(11.2, 10.8), Vector2(13.6, 10.8),
		Vector2(14.6, 8.6), Vector2(15, 10.5), Vector2(14.5, 14), Vector2(12, 17), Vector2(8.5, 14.5),
		Vector2(6.5, 11), Vector2(7.5, 6.5), Vector2(12, 2),
	], s, color, w)
	if with_curl:
		_line(canvas, [Vector2(12, 12), Vector2(12.6, 13), Vector2(12.3, 14.8)], s, color, w)

## Approximated: the source's rounded-bottom U becomes straight sides with
## a single bottom arc instead of two small elliptical corner arcs.
static func _draw_magnet(canvas: CanvasItem, s: float, color: Color, w: float) -> void:
	_line(canvas, [Vector2(6, 4), Vector2(6, 13)], s, color, w)
	_line(canvas, [Vector2(10, 4), Vector2(10, 13)], s, color, w)
	_line(canvas, [Vector2(14, 4), Vector2(14, 13)], s, color, w)
	_line(canvas, [Vector2(18, 4), Vector2(18, 13)], s, color, w)
	canvas.draw_arc(_p(12, 13, s), 6.0 * s, deg_to_rad(0.0), deg_to_rad(180.0), 12, color, w, true)
	for pt_pair in [[Vector2(6, 4), Vector2(10, 4)], [Vector2(14, 4), Vector2(18, 4)]]:
		_line(canvas, pt_pair, s, color, w)

static func _draw_projectile(canvas: CanvasItem, s: float, color: Color, w: float) -> void:
	_line(canvas, [Vector2(3, 12), Vector2(16, 12)], s, color, w)
	_line(canvas, [Vector2(12, 6), Vector2(18, 12), Vector2(12, 18)], s, color, w)

static func _draw_area(canvas: CanvasItem, s: float, color: Color, w: float) -> void:
	_circle_outline(canvas, 12, 12, 3.0, s, color, w)
	_dashed_circle(canvas, 12, 12, 8.0, s, color, w)

## Approximated: the source's flat-bottom curve (one cubic bezier) becomes
## two straight diagonals meeting at a point.
static func _draw_shield(canvas: CanvasItem, s: float, color: Color, w: float, with_check: bool) -> void:
	_line(canvas, [
		Vector2(12, 3), Vector2(19, 6), Vector2(19, 12), Vector2(12, 18),
		Vector2(5, 12), Vector2(5, 6), Vector2(12, 3),
	], s, color, w)
	if with_check:
		_line(canvas, [Vector2(9, 11), Vector2(11, 13), Vector2(15, 9)], s, color, w)

static func _draw_regen(canvas: CanvasItem, s: float, color: Color, w: float) -> void:
	canvas.draw_arc(_p(12, 12, s), 8.0 * s, deg_to_rad(-60.0), deg_to_rad(230.0), 24, color, w, true)
	_line(canvas, [Vector2(16, 4), Vector2(20, 4), Vector2(20, 8)], s, color, w)

static func _draw_luck(canvas: CanvasItem, s: float, color: Color, w: float) -> void:
	_draw_star(canvas, s, color, w)
	_line(canvas, [Vector2(4, 4), Vector2(5, 5)], s, color, w)
	_line(canvas, [Vector2(20, 4), Vector2(19, 5)], s, color, w)

static func _draw_stamina(canvas: CanvasItem, s: float, color: Color, w: float) -> void:
	_line(canvas, [Vector2(6, 16), Vector2(12, 11), Vector2(18, 16)], s, color, w)
	_line(canvas, [Vector2(6, 10), Vector2(12, 5), Vector2(18, 10)], s, color, w)

static func _draw_range(canvas: CanvasItem, s: float, color: Color, w: float) -> void:
	_circle_outline(canvas, 12, 12, 7.0, s, color, w)
	canvas.draw_circle(_p(12, 12, s), 1.4 * s, color)
	for pt_pair in [[Vector2(12, 2), Vector2(12, 5)], [Vector2(12, 19), Vector2(12, 22)], [Vector2(2, 12), Vector2(5, 12)], [Vector2(19, 12), Vector2(22, 12)]]:
		_line(canvas, pt_pair, s, color, w)

static func _draw_haste(canvas: CanvasItem, s: float, color: Color, w: float) -> void:
	_line(canvas, [Vector2(4, 6), Vector2(10, 12), Vector2(4, 18)], s, color, w)
	_line(canvas, [Vector2(12, 6), Vector2(18, 12), Vector2(12, 18)], s, color, w)

## Approximated: the source's bow stave is one cubic bezier; a matching
## circular arc reads the same at icon scale.
static func _draw_bow(canvas: CanvasItem, s: float, color: Color, w: float) -> void:
	canvas.draw_arc(_p(11.0, 12.0, s), 9.2 * s, deg_to_rad(-58.0), deg_to_rad(58.0), 16, color, w, true)
	_line(canvas, [Vector2(6, 3), Vector2(20, 12), Vector2(6, 21)], s, color, w)
	_line(canvas, [Vector2(6, 12), Vector2(19, 12)], s, color, w)
