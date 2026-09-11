class_name HudIcon
extends Control
## A Control whose entire content is one UiIcons glyph — the one spot the
## HUD needs a real _draw() rather than plain Label/ColorRect children,
## since there's no texture to hand a TextureRect. `icon_id`/`icon_color`
## are plain fields, not @export (nothing here is ever tuned from the
## editor — every instance is built and driven from hud.gd) — set them,
## then call queue_redraw() same as any other CanvasItem.

var icon_id: String = "blade"
var icon_color: Color = Color.WHITE

func _draw() -> void:
	UiIcons.draw(self, icon_id, size.x, icon_color)
