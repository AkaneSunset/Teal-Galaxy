extends Button
## A square button with the picture of a building or unit (battle_icons.gd) and its price under it,
## mass over energy; the name and what it does are in the tooltip.

const Icons := preload("res://battle/battle_icons.gd")
const MASS := Color(0.45, 1.0, 0.45)
const ENERGY := Color(1.0, 0.85, 0.3)

var type := ""
var mass := -1 # the price; -1 shows none
var energy := 0
var badge := "" # a corner note, such as "x5"


func _init(t := "") -> void:
	type = t
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(60, 74)
	clip_contents = true


func set_price(m: int, e: int) -> void:
	if m != mass or e != energy:
		mass = m
		energy = e
		queue_redraw()


func _draw() -> void:
	var a := 0.35 if disabled else 1.0
	var font := get_theme_default_font()
	var lines := 0 if mass < 0 else (2 if energy > 0 else 1)
	var icon_h := size.y - 6 - lines * 12
	Icons.draw(self, type, Rect2(Vector2(8, 4), Vector2(size.x - 16, icon_h - 2)), Color(1, 1, 1, a))
	if mass >= 0:
		draw_string(font, Vector2(0, size.y - 5 - (12 if energy > 0 else 0)), "%dm" % mass, HORIZONTAL_ALIGNMENT_CENTER, size.x, 11, MASS * Color(1, 1, 1, a))
	if mass >= 0 and energy > 0:
		draw_string(font, Vector2(0, size.y - 5), "%de" % energy, HORIZONTAL_ALIGNMENT_CENTER, size.x, 11, ENERGY * Color(1, 1, 1, a))
	if badge != "":
		draw_string(font, Vector2(3, 11), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.75, 0.85, 0.88, a))
