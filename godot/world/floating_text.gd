class_name FloatingText
extends Node2D
## A small floating text popup (e.g. "+15 XP" on a kill) that rises and
## fades over its lifetime, then frees itself. No child nodes, no .tscn —
## drawn directly via draw_string_outline()/draw_string() in _draw(), this
## project's own proven pattern for every other world-space visual (every
## entity's own _draw(), ui_icons.gd) rather than a Label/Control child
## under a Node2D parent, a combination not otherwise used anywhere here.

const LIFETIME := 1.1
const RISE_DISTANCE := 36.0
const FONT_SIZE := 16
## Half-width of the centered draw box — wide enough for a short line like
## "+15 XP" at FONT_SIZE without needing to measure the string first.
const HALF_WIDTH := 70.0

var _age: float = 0.0
var _text: String = ""
var _color: Color = Color.WHITE
var _font_size: int = FONT_SIZE

## Spawns one popup as a child of `parent`, positioned at `world_pos` (a
## global position — `parent` need not be at the origin). Fires and
## forgets: the caller keeps no reference, the node frees itself.
## `font_size` defaults to FONT_SIZE (every existing caller's own size) —
## damage numbers are the one caller that varies it, matching
## DamageNumber.ts's own crit(20)/normal(15)/blocked(12) sizing.
static func spawn(parent: Node, world_pos: Vector2, text: String, color: Color, font_size: int = FONT_SIZE) -> void:
	var ft := FloatingText.new()
	ft._text = text
	ft._color = color
	ft._font_size = font_size
	parent.add_child(ft)
	ft.global_position = world_pos

func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	position.y -= (RISE_DISTANCE / LIFETIME) * delta
	queue_redraw()

func _draw() -> void:
	var alpha: float = 1.0 - clampf(_age / LIFETIME, 0.0, 1.0)
	var font: Font = ThemeDB.fallback_font
	var outline_color := Color(0.0, 0.0, 0.0, alpha * 0.85)
	var fill_color := _color
	fill_color.a = alpha
	var pos := Vector2(-HALF_WIDTH, 0.0)
	draw_string_outline(font, pos, _text, HORIZONTAL_ALIGNMENT_CENTER, HALF_WIDTH * 2.0, _font_size, 3, outline_color)
	draw_string(font, pos, _text, HORIZONTAL_ALIGNMENT_CENTER, HALF_WIDTH * 2.0, _font_size, fill_color)
