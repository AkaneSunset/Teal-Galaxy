extends Control
## What a sector battle draws over the 3D view in screen space: strategic icons once the camera is
## high enough (by type and side, like Supreme Commander's), health and build bars, the names of
## the defender's structures, the selection box, the queued orders of the selected units as lines
## and the reticle while driving a unit. Reads everything from the battle view (`view`).

const Units := preload("res://battle/battle_units.gd")

const ICONS_FROM := 500.0 # camera height (metres) past which units are drawn as icons

var view: Node # battle_view.gd
## How long drawing takes a frame (ms, smoothed), for the performance checks.
var draw_ms := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if view == null or view.camera == null:
		return
	var t0 := Time.get_ticks_usec()
	_draw_all()
	draw_ms = lerpf(draw_ms, (Time.get_ticks_usec() - t0) / 1000.0, 0.1)


func _draw_all() -> void:
	var cam: Camera3D = view.camera
	var strategic: bool = view.strategic()
	var font := get_theme_default_font()
	var rect := get_viewport_rect()
	if not view.driving():
		_draw_orders(cam)
	for u: Units.Unit in view.units.values():
		var top := u.pos + Vector3(0, _height_of(u), 0)
		if cam.is_position_behind(top):
			continue
		var s := cam.unproject_position(u.pos if not strategic else u.pos)
		if s.x < -40 or s.y < -40 or s.x > rect.size.x + 40 or s.y > rect.size.y + 40:
			continue
		var sel: bool = view.selected.has(u.id)
		if strategic:
			_icon(u, s, sel)
			continue
		var t := cam.unproject_position(top)
		var dist := cam.global_position.distance_to(u.pos)
		var w := clampf(1400.0 / dist, 14.0, 46.0) * (1.6 if u.kind == "structure" else 1.0)
		if u.kind == "structure" and u.progress < 1.0:
			_bar(t + Vector2(0, -6), w, u.progress, Color(0.4, 0.75, 1.0))
		elif sel or u.hp < u.max_hp - 0.5:
			if not u.dropping():
				_bar(t + Vector2(0, -6), w, u.hp / u.max_hp, _hp_colour(u.hp / u.max_hp))
		if u.name != "" and dist < 900.0:
			var label := u.name
			var size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, 13)
			draw_string(font, t + Vector2(-size.x * 0.5, -14), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.85))
	_draw_mass_points(cam, strategic)
	if view.box_from != null:
		var a: Vector2 = view.box_from
		var b: Vector2 = view.mouse
		var r := Rect2(a, b - a).abs()
		draw_rect(r, Color(0.4, 1.0, 0.5, 0.1), true)
		draw_rect(r, Color(0.4, 1.0, 0.5, 0.8), false, 1.0)
	if view.driving():
		var c := rect.size * 0.5
		var col := Color(1.0, 0.5, 0.35, 0.95)
		draw_arc(c, 14, 0, TAU, 32, col, 2.0)
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			draw_line(c + d * 8.0, c + d * 22.0, col, 2.0)


func _height_of(u: Units.Unit) -> float:
	match u.kind:
		"structure":
			return 12.0 if u.type != "node" else 38.0
		"air":
			return 3.0
	return 6.0 if u.type != "tank" else 6.5


func _hp_colour(f: float) -> Color:
	if f > 0.6:
		return Color(0.35, 0.95, 0.4)
	if f > 0.3:
		return Color(1.0, 0.85, 0.25)
	return Color(1.0, 0.3, 0.25)


func _bar(at: Vector2, w: float, f: float, colour: Color) -> void:
	var r := Rect2(at - Vector2(w * 0.5, 0), Vector2(w, 4))
	draw_rect(r.grow(1), Color(0, 0, 0, 0.75), true)
	draw_rect(Rect2(r.position, Vector2(w * clampf(f, 0.0, 1.0), 4)), colour, true)


## A strategic icon: a land unit is a square, an air unit a chevron, a structure a bigger square,
## the Command Node a diamond; a mark inside says which type. Filled in the side's colour.
func _icon(u: Units.Unit, s: Vector2, sel: bool) -> void:
	var c: Color = view.side_colour(u.side)
	var fill := c.darkened(0.35)
	var line := c.lightened(0.35) if not sel else Color.WHITE
	var mark := Color(1, 1, 1, 0.9)
	var r := 6.0
	if u.dropping():
		draw_circle(s, 4.0, Color(c.r, c.g, c.b, 0.5))
		return
	match u.kind:
		"air":
			var pts := PackedVector2Array([s + Vector2(0, -8), s + Vector2(8, 6), s + Vector2(0, 2), s + Vector2(-8, 6)])
			draw_colored_polygon(pts, fill)
			pts.append(pts[0])
			draw_polyline(pts, line, 1.5 if not sel else 2.5)
			return
		"structure":
			r = 9.0
			if u.type == "node":
				var d := PackedVector2Array([s + Vector2(0, -14), s + Vector2(14, 0), s + Vector2(0, 14), s + Vector2(-14, 0)])
				draw_colored_polygon(d, fill)
				d.append(d[0])
				draw_polyline(d, line, 2.0)
				draw_circle(s, 4.0, mark)
				return
	var box := Rect2(s - Vector2(r, r), Vector2(r, r) * 2.0)
	if u.type == "factory":
		box = Rect2(s - Vector2(12, 8), Vector2(24, 16))
	draw_rect(box, fill, true)
	draw_rect(box, line, false, 1.5 if not sel else 2.5)
	match u.type:
		"engineer":
			draw_line(s + Vector2(-4, 0), s + Vector2(4, 0), mark, 2.0)
			draw_line(s + Vector2(0, -4), s + Vector2(0, 4), mark, 2.0)
		"scout":
			draw_circle(s, 2.0, mark)
		"striker":
			draw_line(s + Vector2(0, -4), s + Vector2(0, 4), mark, 2.0)
		"tank":
			draw_line(s + Vector2(-2, -4), s + Vector2(-2, 4), mark, 2.0)
			draw_line(s + Vector2(2, -4), s + Vector2(2, 4), mark, 2.0)
		"artillery":
			draw_arc(s + Vector2(0, 3), 4.0, PI, TAU, 8, mark, 2.0)
		"aa":
			draw_polyline(PackedVector2Array([s + Vector2(-4, 3), s + Vector2(0, -3), s + Vector2(4, 3)]), mark, 2.0)
		"extractor":
			draw_circle(s, 3.5, Color(0.4, 1.0, 0.4))
		"turret":
			draw_line(s + Vector2(-4, -4), s + Vector2(4, 4), mark, 2.0)
			draw_line(s + Vector2(-4, 4), s + Vector2(4, -4), mark, 2.0)
		"factory":
			draw_rect(Rect2(s - Vector2(5, 3), Vector2(10, 6)), mark, false, 1.5)
		"outpost":
			draw_arc(s, 4.0, 0, TAU, 12, mark, 2.0)


func _draw_mass_points(cam: Camera3D, strategic: bool) -> void:
	if not strategic:
		return
	for p in view.mass_points:
		var at := Vector3(p.x, view.terrain.height(p.x, p.z), p.z)
		if cam.is_position_behind(at):
			continue
		var s := cam.unproject_position(at)
		var d := PackedVector2Array([s + Vector2(0, -5), s + Vector2(5, 0), s + Vector2(0, 5), s + Vector2(-5, 0), s + Vector2(0, -5)])
		draw_polyline(d, Color(0.45, 1.0, 0.45, 0.8), 1.5)


## The orders the pilot gave the selected units: a line from each unit through its waypoints, a dot
## at each (green: move, red: attack-move or attack, amber: build).
func _draw_orders(cam: Camera3D) -> void:
	for id in view.selected:
		var u: Units.Unit = view.units.get(id)
		if u == null or u.orders.is_empty():
			continue
		var from := u.pos
		for o in u.orders:
			var p: Vector2 = o.p
			var to := Vector3(p.x, view.terrain.height(p.x, p.y) + 0.5, p.y)
			if o.order == "attack" and view.units.has(o.get("target", -1)):
				to = view.units[o.target].pos
			var colour := Color(0.4, 1.0, 0.45, 0.55)
			if o.order == "amove" or o.order == "attack":
				colour = Color(1.0, 0.4, 0.3, 0.6)
			elif o.order == "build":
				colour = Color(1.0, 0.8, 0.3, 0.6)
			if not cam.is_position_behind(from) and not cam.is_position_behind(to):
				var a := cam.unproject_position(from)
				var b := cam.unproject_position(to)
				draw_line(a, b, colour, 1.5)
				draw_circle(b, 3.0, colour)
			from = to
