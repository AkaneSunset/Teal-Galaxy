extends RefCounted
## Icons for the sector battle's buttons: every building and unit drawn as a small picture, so the
## build, factory and call-in panels are rows of pictures rather than rows of names. Each icon is
## drawn in a 40 x 40 box with Control draw calls (crisp at any size, no image files).
## `draw(canvas, type, rect)` draws `type` (a tiered "tank_t2" draws the Tank) into `rect`.

const LINE := Color(0.85, 0.96, 0.96)
const DIM := Color(0.55, 0.72, 0.74)
const MASS := Color(0.45, 1.0, 0.45)
const ENERGY := Color(1.0, 0.85, 0.3)
const SHIELD := Color(0.45, 0.75, 1.0)
const DANGER := Color(1.0, 0.55, 0.4)


## Draws the icon for `type` into `rect` on `c` (a CanvasItem, in its _draw).
static func draw(c: CanvasItem, type: String, rect: Rect2, tint := Color.WHITE) -> void:
	var base := type.get_slice("_t", 0)
	var s := minf(rect.size.x, rect.size.y) / 40.0
	var o := rect.position + (rect.size - Vector2(40, 40) * s) * 0.5
	var P := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	var w := maxf(1.5, 2.0 * s)
	var line := LINE * tint
	var dim := DIM * tint
	match base:
		"extractor":
			# A drill rig on a glowing mass point.
			c.draw_circle(P.call(20, 33), 7 * s, (MASS * tint) * Color(1, 1, 1, 0.35))
			c.draw_arc(P.call(20, 33), 7 * s, 0, TAU, 20, MASS * tint, w)
			c.draw_polyline(PackedVector2Array([P.call(10, 33), P.call(20, 6), P.call(30, 33)]), line, w)
			c.draw_line(P.call(14, 22), P.call(26, 22), line, w)
			c.draw_line(P.call(20, 6), P.call(20, 36), MASS * tint, w)
		"generator":
			# A lightning bolt in a ring.
			c.draw_arc(P.call(20, 20), 15 * s, 0, TAU, 28, line, w)
			c.draw_colored_polygon(PackedVector2Array([P.call(23, 6), P.call(12, 22), P.call(19, 22), P.call(16, 34), P.call(28, 17), P.call(21, 17)]), ENERGY * tint)
		"massstorage":
			# A tank, filled green.
			c.draw_rect(Rect2(P.call(11, 10), Vector2(18, 22) * s), (MASS * tint) * Color(1, 1, 1, 0.5))
			c.draw_rect(Rect2(P.call(11, 10), Vector2(18, 22) * s), line, false, w)
			_ellipse(c, P.call(20, 10), Vector2(9, 3) * s, line, w)
			_ellipse(c, P.call(20, 32), Vector2(9, 3) * s, line, w)
			c.draw_line(P.call(11, 21), P.call(29, 21), MASS * tint, w)
		"energystorage":
			# A battery, filled yellow.
			c.draw_rect(Rect2(P.call(8, 13), Vector2(22, 14) * s), line, false, w)
			c.draw_rect(Rect2(P.call(30, 17), Vector2(3, 6) * s), line)
			c.draw_rect(Rect2(P.call(11, 16), Vector2(12, 8) * s), ENERGY * tint)
		"turret":
			# A gun on a square base.
			c.draw_rect(Rect2(P.call(8, 24), Vector2(24, 10) * s), line, false, w)
			c.draw_circle(P.call(20, 22), 7 * s, line)
			c.draw_line(P.call(20, 22), P.call(35, 9), line, 3 * s)
		"aaturret":
			# Twin barrels pointing up at a chevron.
			c.draw_rect(Rect2(P.call(8, 26), Vector2(24, 8) * s), line, false, w)
			c.draw_circle(P.call(20, 24), 6 * s, line)
			c.draw_line(P.call(17, 24), P.call(13, 9), line, 2.5 * s)
			c.draw_line(P.call(23, 24), P.call(27, 9), line, 2.5 * s)
			c.draw_polyline(PackedVector2Array([P.call(14, 8), P.call(20, 3), P.call(26, 8)]), SHIELD * tint, w)
		"shield":
			# A dome over a small base.
			c.draw_arc(P.call(20, 30), 15 * s, PI, TAU, 24, SHIELD * tint, w * 1.2)
			c.draw_colored_polygon(_arc_poly(P.call(20, 30), 15 * s), (SHIELD * tint) * Color(1, 1, 1, 0.25))
			c.draw_rect(Rect2(P.call(16, 24), Vector2(8, 6) * s), line)
			c.draw_line(P.call(4, 31), P.call(36, 31), line, w)
		"factory":
			# A sawtooth-roofed works with a chimney, and a track below.
			c.draw_polyline(PackedVector2Array([P.call(5, 27), P.call(5, 15), P.call(13, 10), P.call(13, 15), P.call(21, 10), P.call(21, 15), P.call(29, 10), P.call(29, 27), P.call(5, 27)]), line, w)
			c.draw_rect(Rect2(P.call(31, 6), Vector2(4, 21) * s), line)
			c.draw_rect(Rect2(P.call(12, 19), Vector2(8, 8) * s), dim)
			_track(c, P.call(6, 31), P.call(34, 31), 4 * s, line, w)
		"airfactory":
			# A hangar arch with a plane in front.
			c.draw_arc(P.call(20, 28), 15 * s, PI, TAU, 24, line, w)
			c.draw_line(P.call(4, 28), P.call(36, 28), line, w)
			_plane(c, P.call(20, 22), 0.55 * s, line)
		"engineer":
			# A wrench.
			c.draw_line(P.call(10, 31), P.call(25, 16), line, 4 * s)
			c.draw_arc(P.call(28, 13), 6 * s, -PI * 0.15, PI * 1.35, 16, line, 3.5 * s)
			c.draw_circle(P.call(10, 31), 2.5 * s, line)
		"acu":
			# A star on a shield crest.
			c.draw_colored_polygon(PackedVector2Array([P.call(8, 7), P.call(32, 7), P.call(32, 20), P.call(20, 35), P.call(8, 20)]), (DANGER * tint) * Color(1, 1, 1, 0.35))
			c.draw_polyline(PackedVector2Array([P.call(8, 7), P.call(32, 7), P.call(32, 20), P.call(20, 35), P.call(8, 20), P.call(8, 7)]), line, w)
			c.draw_colored_polygon(_star(P.call(20, 18), 7 * s), line)
		"scout":
			# An eye.
			c.draw_polyline(PackedVector2Array([P.call(4, 20), P.call(12, 12), P.call(20, 10), P.call(28, 12), P.call(36, 20), P.call(28, 28), P.call(20, 30), P.call(12, 28), P.call(4, 20)]), line, w)
			c.draw_circle(P.call(20, 20), 6 * s, line)
			c.draw_circle(P.call(20, 20), 2.5 * s, Color(0.02, 0.05, 0.08))
		"striker":
			# A light walker: a chevron on two legs.
			c.draw_colored_polygon(PackedVector2Array([P.call(20, 6), P.call(31, 22), P.call(20, 17), P.call(9, 22)]), line)
			c.draw_line(P.call(15, 22), P.call(12, 34), line, w * 1.3)
			c.draw_line(P.call(25, 22), P.call(28, 34), line, w * 1.3)
			c.draw_line(P.call(26, 15), P.call(36, 11), line, w)
		"tank":
			# A hull, turret and long gun.
			c.draw_rect(Rect2(P.call(5, 21), Vector2(26, 8) * s), line)
			c.draw_rect(Rect2(P.call(11, 14), Vector2(12, 7) * s), line)
			c.draw_line(P.call(22, 17), P.call(37, 17), line, 2.5 * s)
			_track(c, P.call(6, 32), P.call(30, 32), 3 * s, line, w)
		"artillery":
			# A long barrel raised high, and the shell's arc.
			c.draw_rect(Rect2(P.call(5, 25), Vector2(20, 6) * s), line)
			c.draw_line(P.call(15, 25), P.call(30, 10), line, 3 * s)
			c.draw_arc(P.call(30, 22), 8 * s, -PI * 0.9, -PI * 0.1, 10, DANGER * tint, w * 0.8)
			_track(c, P.call(6, 34), P.call(24, 34), 2.5 * s, line, w)
		"aa":
			# A hull with twin barrels up.
			c.draw_rect(Rect2(P.call(6, 22), Vector2(28, 8) * s), line)
			c.draw_line(P.call(16, 22), P.call(12, 8), line, 2.5 * s)
			c.draw_line(P.call(24, 22), P.call(28, 8), line, 2.5 * s)
			c.draw_polyline(PackedVector2Array([P.call(14, 6), P.call(20, 1), P.call(26, 6)]), SHIELD * tint, w)
			_track(c, P.call(7, 33), P.call(33, 33), 3 * s, line, w)
		"fighter":
			# A swept-wing fighter.
			_plane(c, P.call(20, 20), 1.0 * s, line)
		"bomber":
			# A broad-winged bomber dropping a bomb.
			c.draw_colored_polygon(PackedVector2Array([P.call(20, 4), P.call(23, 12), P.call(37, 18), P.call(37, 21), P.call(23, 19), P.call(22, 26), P.call(26, 29), P.call(14, 29), P.call(18, 26), P.call(17, 19), P.call(3, 21), P.call(3, 18), P.call(17, 12)]), line)
			c.draw_circle(P.call(20, 35), 3 * s, DANGER * tint)
		"gunship":
			# A rotor over a body.
			c.draw_line(P.call(4, 9), P.call(36, 9), line, w)
			c.draw_line(P.call(20, 9), P.call(20, 15), line, w)
			c.draw_colored_polygon(PackedVector2Array([P.call(9, 18), P.call(27, 15), P.call(31, 22), P.call(26, 28), P.call(12, 28)]), line)
			c.draw_line(P.call(27, 21), P.call(38, 23), line, w)
			c.draw_line(P.call(9, 22), P.call(2, 20), line, w)
		_:
			c.draw_arc(P.call(20, 20), 14 * s, 0, TAU, 24, line, w)
	# The tier of a Mk II or Mk III unit, as pips in the corner.
	var tier := int(type.get_slice("_t", 1)) if type.contains("_t") else 1
	for i in tier - 1:
		c.draw_circle(P.call(36 - i * 5, 4), 2 * s, ENERGY * tint)


static func _ellipse(c: CanvasItem, at: Vector2, r: Vector2, colour: Color, w: float) -> void:
	var pts := PackedVector2Array()
	for i in 17:
		var a := TAU * i / 16.0
		pts.append(at + Vector2(cos(a) * r.x, sin(a) * r.y))
	c.draw_polyline(pts, colour, w)


static func _arc_poly(at: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 17:
		var a := PI + PI * i / 16.0
		pts.append(at + Vector2(cos(a), sin(a)) * r)
	return pts


static func _star(at: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2.0 + TAU * i / 10.0
		pts.append(at + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
	return pts


static func _track(c: CanvasItem, a: Vector2, b: Vector2, h: float, colour: Color, w: float) -> void:
	c.draw_line(a + Vector2(h, -h), b + Vector2(-h, -h), colour, w)
	c.draw_line(a + Vector2(h, h), b + Vector2(-h, h), colour, w)
	c.draw_arc(a + Vector2(h, 0), h, PI * 0.5, PI * 1.5, 8, colour, w)
	c.draw_arc(b - Vector2(h, 0), h, -PI * 0.5, PI * 0.5, 8, colour, w)


## A swept-wing plane, nose up, centred on `at`, about 32 * k across.
static func _plane(c: CanvasItem, at: Vector2, k: float, colour: Color) -> void:
	var pts := PackedVector2Array()
	for p in [Vector2(0, -16), Vector2(3, -6), Vector2(16, 6), Vector2(16, 9), Vector2(3, 4), Vector2(3, 10), Vector2(7, 14), Vector2(-7, 14), Vector2(-3, 10), Vector2(-3, 4), Vector2(-16, 9), Vector2(-16, 6), Vector2(-3, -6)]:
		pts.append(at + p * k)
	c.draw_colored_polygon(pts, colour)
