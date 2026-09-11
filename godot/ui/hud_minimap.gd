class_name HudMinimap
extends Control
## Ports HUD.ts's refreshMinimap — the "double-resolution" room-graph grid:
## each room's logical (grid_x, grid_y) maps to track (2x, 2y) in a grid
## twice the room graph's own width/height; the ODD tracks in between hold
## door connectors. Built as one direct _draw() (this project's usual
## approach for anything hand-drawn — see hud_icon.gd) rather than as a
## tree of child Controls in a CSS-Grid-equivalent container: the layout
## is sparse (most (col,row) slots are empty — only rooms that exist get a
## cell) and needs alternating track sizes (room-sized, then gap-sized),
## neither of which GridContainer's "N uniform columns" model fits.
##
## Positioned by refresh() itself, not a fixed set_anchors_preset() call —
## anchor FRACTIONS are set once in _ready() (before this control's size
## depends on anything), and every later refresh() only ever reassigns
## offsets/scale/pivot_offset (plain property writes, not set_anchors_
## preset() — confirmed safe to call after parenting, unlike that method,
## by this project's own established bar-fill-ratio code, which reassigns
## anchor_right every frame on an already-parented ColorRect with no issue).

const ROOM_PX := 18.0
const GAP_PX := 8.0
const MAX_PX := 176.0
const PADDING := 7.0
const RIGHT_MARGIN := 14.0
## Below the embers/timer/zone-label/corruption column _build_top_right()
## already builds (that column's own box ends at y=14+90=104).
const TOP_OFFSET := 118.0

var _cols: int = 0
var _rows: int = 0
var _natural_w: float = 0.0
var _natural_h: float = 0.0
## Each: {col, row, shown, dest, current, tint (Color, only meaningful
## when shown and not dest)}.
var _cells: Array = []
## Each: {col, row, horizontal, active}.
var _connectors: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0

## `layout` is one of RunState.layouts' own values ({"zone", "rooms",
## "start_key", "end_key"}); `current_room_key` is RunState.current_room_key.
func refresh(layout: Dictionary, current_room_key: String) -> void:
	var rooms_dict: Dictionary = layout.get("rooms", {})
	var rooms: Array = rooms_dict.values()
	_cells = []
	_connectors = []
	if rooms.is_empty():
		_apply_box(0.0, 0.0)
		queue_redraw()
		return

	var min_x := 0
	var max_x := 0
	var min_y := 0
	var max_y := 0
	for r in rooms:
		var room := r as RoomContainer
		min_x = mini(min_x, room.grid_x)
		max_x = maxi(max_x, room.grid_x)
		min_y = mini(min_y, room.grid_y)
		max_y = maxi(max_y, room.grid_y)
	_cols = max_x - min_x + 1
	_rows = max_y - min_y + 1

	var by_pos: Dictionary = {}
	for r in rooms:
		var room := r as RoomContainer
		by_pos["%d,%d" % [room.grid_x - min_x, room.grid_y - min_y]] = room

	var is_destination := func(room: RoomContainer) -> bool:
		return room.type == RoomContainer.Type.HEART or room.type == RoomContainer.Type.BOSS
	var is_shown := func(room: RoomContainer) -> bool:
		return room.visited or room.key == current_room_key or is_destination.call(room)
	var has_shown_neighbor := func(room: RoomContainer) -> bool:
		for dir in room.doors:
			var d: Vector2i = RoomContainer.DIRECTION_DELTA[dir]
			var n: RoomContainer = by_pos.get("%d,%d" % [room.grid_x - min_x + d.x, room.grid_y - min_y + d.y])
			if n != null and is_shown.call(n):
				return true
		return false

	for y in range(_rows):
		for x in range(_cols):
			var room: RoomContainer = by_pos.get("%d,%d" % [x, y])
			if room == null:
				continue
			var col := x * 2
			var row := y * 2
			var shown: bool = is_shown.call(room)
			var dest: bool = is_destination.call(room)
			var is_current: bool = room.key == current_room_key

			if shown or has_shown_neighbor.call(room):
				_cells.append({
					"col": col, "row": row, "shown": shown, "dest": dest, "current": is_current,
					"tint": _tint_for(room.type) if (shown and not dest) else Color(Palette.BG3),
				})

			# Only E/S are checked so each door pair is drawn once (the
			# neighbor's own W/N is the same connection) — matches the
			# source exactly, including never drawing toward a merely-
			# hinted room (a connector only appears between two SHOWN rooms).
			if room.doors.has(RoomContainer.Direction.E):
				var e_neighbor: RoomContainer = by_pos.get("%d,%d" % [x + 1, y])
				if e_neighbor != null and shown and is_shown.call(e_neighbor):
					var e_active: bool = is_current or e_neighbor.key == current_room_key
					_connectors.append({"col": col + 1, "row": row, "horizontal": true, "active": e_active})
			if room.doors.has(RoomContainer.Direction.S):
				var s_neighbor: RoomContainer = by_pos.get("%d,%d" % [x, y + 1])
				if s_neighbor != null and shown and is_shown.call(s_neighbor):
					var s_active: bool = is_current or s_neighbor.key == current_room_key
					_connectors.append({"col": col, "row": row + 1, "horizontal": false, "active": s_active})

	var natural_w: float = _cols * ROOM_PX + maxf(float(_cols - 1), 0.0) * GAP_PX + PADDING * 2.0
	var natural_h: float = _rows * ROOM_PX + maxf(float(_rows - 1), 0.0) * GAP_PX + PADDING * 2.0
	_apply_box(natural_w, natural_h)
	queue_redraw()

## Sizes/positions this control to a natural_w x natural_h box anchored to
## the HUD's top-right corner, then scales the whole thing down (pivoting
## from that same top-right point, matching the source's own `transform-
## origin: top right`) if it would otherwise exceed MAX_PX — never up, so
## small zones stay at native size, matching the source's own `Math.min(1, ...)`.
func _apply_box(natural_w: float, natural_h: float) -> void:
	_natural_w = natural_w
	_natural_h = natural_h
	offset_right = -RIGHT_MARGIN
	offset_left = -RIGHT_MARGIN - natural_w
	offset_top = TOP_OFFSET
	offset_bottom = TOP_OFFSET + natural_h
	var s: float = minf(1.0, MAX_PX / maxf(maxf(natural_w, natural_h), 1.0))
	scale = Vector2(s, s)
	pivot_offset = Vector2(natural_w, 0.0)

func _draw() -> void:
	if _cells.is_empty() and _connectors.is_empty():
		return
	var box := Rect2(Vector2.ZERO, Vector2(_natural_w, _natural_h))
	draw_rect(box, Color(8.0 / 255.0, 6.0 / 255.0, 12.0 / 255.0, 0.6), true)
	draw_rect(box, Color(Palette.BORDER), false, 1.0)

	for c in _connectors:
		var r: Rect2 = _track_rect(c["col"], c["row"])
		var color: Color = Color(Palette.EMBER4) if c["active"] else Color(1.0, 1.0, 1.0, 0.14)
		if c["horizontal"]:
			draw_rect(Rect2(r.position.x, r.position.y + r.size.y / 2.0 - 1.5, r.size.x, 3.0), color, true)
		else:
			draw_rect(Rect2(r.position.x + r.size.x / 2.0 - 1.5, r.position.y, 3.0, r.size.y), color, true)

	for c in _cells:
		var r: Rect2 = _track_rect(c["col"], c["row"])
		if c["dest"]:
			_draw_destination(r, c["current"])
		elif c["shown"]:
			draw_rect(r, c["tint"], true)
			draw_rect(r, Color(0.0, 0.0, 0.0, 0.35), false, 1.0)
			if c["current"]:
				draw_rect(r.grow(2.0), Color(Palette.EMBER4), false, 2.0)
		else:
			draw_rect(r, Color(1.0, 1.0, 1.0, 0.04), true)
			draw_rect(r.grow(-0.5), Color(1.0, 1.0, 1.0, 0.16), false, 1.0)

## Rooms sit in EVEN tracks (0, 2, 4, ...), each ROOM_PX wide/tall; the
## connector tracks between them (1, 3, 5, ...) are GAP_PX. `col`/`row` are
## 0-indexed track numbers (NOT the source's own 1-indexed CSS grid-column
## values — there's no real CSS grid here to match numbering with, only
## the same alternating-track SHAPE, so this file picks the indexing that
## keeps its own col%2==0 check simplest).
func _track_rect(col: int, row: int) -> Rect2:
	var x := PADDING
	for i in range(col):
		x += ROOM_PX if i % 2 == 0 else GAP_PX
	var y := PADDING
	for i in range(row):
		y += ROOM_PX if i % 2 == 0 else GAP_PX
	var w: float = ROOM_PX if col % 2 == 0 else GAP_PX
	var h: float = ROOM_PX if row % 2 == 0 else GAP_PX
	return Rect2(x, y, w, h)

## The zone's heart/boss room: a rotated (45°) gold diamond, always shown
## regardless of discovery — a stable "this is the destination" landmark
## every run. Flat legendary gold, not the source's own gradient (this
## project's usual "gradient -> its most identity-defining flat stop"
## simplification — no gradient-fill primitive on a plain Control here
## either, see e.g. hud.gd's own header). No pulse animation (the source's
## own `legendaryPulse` keyframes) — a deliberately small polish gap at
## this size, not worth a permanently-running Tween for.
func _draw_destination(r: Rect2, is_current: bool) -> void:
	var center: Vector2 = r.position + r.size / 2.0
	var half: float = r.size.x / 2.0 * 1.15
	var points := PackedVector2Array([
		center + Vector2(0.0, -half), center + Vector2(half, 0.0),
		center + Vector2(0.0, half), center + Vector2(-half, 0.0),
	])
	draw_colored_polygon(points, Color(Palette.RARITY_LEGENDARY))
	draw_polyline(points + PackedVector2Array([points[0]]), Color(Palette.RARITY_LEGENDARY), 1.5, true)
	if is_current:
		draw_polyline(points + PackedVector2Array([points[0]]), Color(Palette.EMBER4), 2.0, true)

## Ports HUD.ts's own MINIMAP_TINT table — every value there is already an
## exact match for an existing Palette token (both ultimately read off the
## same style.css custom properties), so this reuses those directly rather
## than re-typing the same 6 hex strings a second time.
static func _tint_for(type: RoomContainer.Type) -> Color:
	match type:
		RoomContainer.Type.CHEST: return Color(Palette.RARITY_LEGENDARY)
		RoomContainer.Type.SHOP: return Color(Palette.FROST)
		RoomContainer.Type.ELITE: return Color(Palette.BLOOD_BRIGHT)
		RoomContainer.Type.EVENT: return Color(Palette.TOXIC)
		RoomContainer.Type.REST: return Color(Palette.EMBER5)
		RoomContainer.Type.SANCTUM: return Color(Palette.FUNGUS)
		_: return Color(Palette.BG3)
