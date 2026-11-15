extends Control
## What a sector battle draws over the 3D view in screen space: strategic icons once the camera is
## high enough (by type and side, like Supreme Commander's), health and build bars, the names of
## the defender's structures, the selection box, the queued orders of the selected units as lines
## and the reticle while driving a unit. Reads everything from the battle view (`view`).

const Units := preload("res://battle/battle_units.gd")

const ICONS_FROM := 500.0 # camera height (metres) past which units are drawn as icons
const COVER_REACH := 3.0 # how near cover a squad has to be to use it (the server's COVER_REACH)
## The colours of cover, by the server's codes and by name.
const COVER_COLOURS := {
	"h": Color(0.35, 0.95, 0.4), "heavy": Color(0.35, 0.95, 0.4),
	"l": Color(1.0, 0.85, 0.25), "light": Color(1.0, 0.85, 0.25),
	"n": Color(0.75, 0.78, 0.8), "none": Color(0.75, 0.78, 0.8),
	"x": Color(1.0, 0.3, 0.25), "negative": Color(1.0, 0.3, 0.25),
}

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
		if u.vet > 0 and not u.dropping(): # veterancy: a gold pip per star over the health bar
			for i in u.vet:
				draw_circle(t + Vector2(-w / 2.0 + 3.0 + i * 6.0, -13), 2.2, Color(1.0, 0.82, 0.25))
		if u.squad > 0 and not u.dropping():
			_squad_marks(u, t, w, font)
		if u.name != "" and dist < 900.0:
			var label := u.name
			var size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, 13)
			draw_string(font, t + Vector2(-size.x * 0.5, -14), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.85))
	_draw_mass_points(cam, strategic)
	if not strategic and not view.driving() and not view.my_squads().is_empty():
		_draw_cover_preview(cam, font)
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
			if u.type == "airtransport": # the troops it carries: a dot under its chevron
				draw_circle(s + Vector2(0, 9), 2.0, mark)
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
		"acu":
			draw_rect(Rect2(s - Vector2(5, 5), Vector2(10, 10)), mark, false, 2.0)
			draw_circle(s, 2.5, mark)
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
		"transport":
			draw_rect(Rect2(s - Vector2(4, 2.5), Vector2(8, 5)), mark, false, 1.5)
		"infantry":
			for dx in [-3.0, 0.0, 3.0]:
				draw_circle(s + Vector2(dx, 0), 1.2, mark)
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



## A squad's state over its health bar, as Company of Heroes shows it: a shield in the colour of
## its cover (green heavy, yellow light, grey none, red negative) at the bar's left, a pip per
## soldier under it (hollow for the ones it has lost), its suppression filling amber under that,
## and a word when it's pinned, retreating or reinforcing.
func _squad_marks(u: Units.Unit, t: Vector2, w: float, font: Font) -> void:
	var at := t + Vector2(-w * 0.5 - 9.0, -4.0)
	_shield(at, 5.0, COVER_COLOURS.get(u.cover, COVER_COLOURS.n))
	var n := u.soldiers()
	var step := minf(6.0, w / maxf(u.squad, 1))
	var x0 := t.x - w * 0.5 + step * 0.5
	for i in u.squad:
		var p := Vector2(x0 + i * step, t.y + 2.0)
		if i < n:
			draw_rect(Rect2(p - Vector2(1.6, 1.6), Vector2(3.2, 3.2)), Color(0.9, 0.95, 1.0, 0.95), true)
		else:
			draw_rect(Rect2(p - Vector2(1.6, 1.6), Vector2(3.2, 3.2)), Color(0.9, 0.95, 1.0, 0.5), false, 1.0)
	if u.supp > 0.02 and not u.retreating:
		var r := Rect2(t + Vector2(-w * 0.5, 6.0), Vector2(w, 2.5))
		draw_rect(r.grow(1), Color(0, 0, 0, 0.6), true)
		draw_rect(Rect2(r.position, Vector2(w * clampf(u.supp, 0.0, 1.0), 2.5)), Color(1.0, 0.3, 0.25) if u.pinned else Color(1.0, 0.65, 0.2), true)
	var word := ""
	var colour := Color(1.0, 0.65, 0.2)
	if u.retreating:
		word = "Retreating"
		colour = Color(1.0, 0.8, 0.45)
	elif u.pinned:
		word = "Pinned"
		colour = Color(1.0, 0.35, 0.3)
	elif u.reinforcing:
		word = "Reinforcing"
		colour = Color(0.45, 0.95, 0.88)
	elif u.supp >= 0.2:
		word = "Suppressed"
	if word != "":
		var size := font.get_string_size(word, HORIZONTAL_ALIGNMENT_CENTER, -1, 11)
		draw_string(font, t + Vector2(-size.x * 0.5, 20.0), word, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, colour)


## A small shield: flat across the top, pointed at the bottom.
func _shield(c: Vector2, r: float, colour: Color) -> void:
	var pts := PackedVector2Array([c + Vector2(-r, -r), c + Vector2(r, -r), c + Vector2(r, r * 0.2), c + Vector2(0, r * 1.2), c + Vector2(-r, r * 0.2)])
	draw_colored_polygon(pts, Color(colour.r, colour.g, colour.b, 0.85))
	pts.append(pts[0])
	draw_polyline(pts, Color(0, 0, 0, 0.7), 1.0)


## With squads selected, the cover round the cursor shows as dots round each piece in its colour
## (where a squad has to stand to use it), and a shield at the cursor says the cover there.
func _draw_cover_preview(cam: Camera3D, font: Font) -> void:
	var g: Vector3 = view._ground_at(view.mouse)
	if g.x < 0.0:
		return
	var m := Vector2(g.x, g.z)
	for list in [view.cover, view.craters.values()]:
		for c in list:
			var at := Vector2(float(c.x), float(c.z))
			var r := float(c.r)
			if at.distance_to(m) - r > 45.0:
				continue
			var kind := str(c.kind)
			var edge := r if kind == "negative" or c.get("crater", false) else r + COVER_REACH
			var col: Color = COVER_COLOURS.get(kind, COVER_COLOURS.n)
			var dots := clampi(int(edge * 1.6), 10, 48)
			for k in dots:
				var a := TAU * k / dots
				var px := at.x + cos(a) * edge
				var pz := at.y + sin(a) * edge
				var p3 := Vector3(px, view.terrain.height(px, pz) + 0.3, pz)
				if cam.is_position_behind(p3):
					continue
				draw_circle(cam.unproject_position(p3), 2.0, Color(col.r, col.g, col.b, 0.75))
	var here: String = view.cover_at(m)
	_shield(view.mouse + Vector2(16, 18), 6.0, COVER_COLOURS.get(here, COVER_COLOURS.n))
	draw_string(font, view.mouse + Vector2(26, 24), {"heavy": "Heavy cover", "light": "Light cover", "negative": "Negative cover"}.get(here, "No cover"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.85))
