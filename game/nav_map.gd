extends Control
## Navigation map with three levels: Local, System and Galactic.
## Shows landmarks, saved waypoints and other pilots, each of which can be filtered out.
## Click a place to fly there; shift-click to add it to the route queue; right-click a waypoint
## to delete it. Seen from above, with the ship's heading drawn as a line.
## The System level marks the contested worlds with who holds them and how hard they're fought
## over. The Galactic level is the war map: the systems and their lanes, every contested planet
## in its owner's colour, locks, the fleets and Coma armadas in orbit or under way, and your
## faction's ground highlighted. Click a planet there to open the War terminal on it.

const System := preload("res://teal_prime.gd")
const WarInfo := preload("res://war_info.gd")
const PILOT_ICON := preload("res://ui/hud_icons/pilot.png")
const TITLE_ICON := preload("res://ui/hud_icons/nav_map.png")

signal route_changed(route: Array)
signal waypoint_added
signal waypoint_removed(id: String)
signal war_planet_picked(id: String)

enum Level { LOCAL, SYSTEM, GALACTIC }

var level := Level.LOCAL
var filters := {"landmark": true, "waypoint": true, "pilot": true}
var colour := Color(0.35, 0.95, 0.88)
var items: Array = [] # {"id", "name", "kind", "pos": Array, "radius"?}
var ship_pos: Array = [0.0, 0.0, 0.0]
var ship_heading := Vector3.FORWARD
var route: Array = []

var _zoom := {Level.LOCAL: 1.0, Level.SYSTEM: 1.0}
var _area: Control
var _route_label: Label
var _level_buttons := []
var _war_hits := [] # [Rect2, planet id] on the war map, from the last draw


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.02, 0.05, 0.88)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	margin.add_child(row)

	var side_panel := VBoxContainer.new()
	side_panel.custom_minimum_size = Vector2(250, 0)
	side_panel.add_theme_constant_override("separation", 8)
	row.add_child(side_panel)
	_area = Control.new()
	_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_area.clip_contents = true
	_area.mouse_filter = Control.MOUSE_FILTER_PASS
	_area.draw.connect(_draw_map)
	_area.gui_input.connect(_on_map_input)
	row.add_child(_area)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 10)
	side_panel.add_child(title_row)
	var pic := TextureRect.new()
	pic.texture = TITLE_ICON
	pic.custom_minimum_size = Vector2(32, 32)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.modulate = colour
	title_row.add_child(pic)
	var title := Label.new()
	title.text = "Navigation"
	title.add_theme_font_size_override("font_size", 24)
	title_row.add_child(title)
	var levels := HBoxContainer.new()
	side_panel.add_child(levels)
	for l in [["Local", Level.LOCAL], ["System", Level.SYSTEM], ["Galactic", Level.GALACTIC]]:
		var b := Button.new()
		b.text = l[0]
		b.toggle_mode = true
		b.pressed.connect(set_level.bind(l[1]))
		levels.add_child(b)
		_level_buttons.append(b)

	side_panel.add_child(_heading("Show"))
	for f in [["landmark", "Landmarks"], ["waypoint", "Waypoints"], ["pilot", "Other pilots"]]:
		var c := CheckBox.new()
		c.text = f[1]
		c.button_pressed = true
		c.toggled.connect(func(on): filters[f[0]] = on; _area.queue_redraw())
		side_panel.add_child(c)

	side_panel.add_child(_heading("Route"))
	_route_label = Label.new()
	_route_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side_panel.add_child(_route_label)
	var mark := Button.new()
	mark.text = "Save waypoint here"
	mark.pressed.connect(func(): waypoint_added.emit())
	side_panel.add_child(mark)
	var clear := Button.new()
	clear.text = "Clear route"
	clear.pressed.connect(func(): set_route([]))
	side_panel.add_child(clear)

	var help := Label.new()
	help.text = "Click: fly there\nShift-click: add to route\nRight-click a waypoint: delete\nWheel: zoom\nM or Esc: close"
	help.modulate = Color(1, 1, 1, 0.6)
	side_panel.add_child(help)
	set_level(Level.LOCAL)


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	return l


func set_level(l: Level) -> void:
	level = l
	for i in _level_buttons.size():
		_level_buttons[i].button_pressed = i == l
	_area.queue_redraw()


func set_route(r: Array) -> void:
	route = r
	_update_route_label()
	route_changed.emit(route)
	_area.queue_redraw()


func refresh(new_items: Array, pos: Array, heading: Vector3) -> void:
	items = new_items
	ship_pos = pos
	ship_heading = heading
	_update_route_label()
	if visible:
		_area.queue_redraw()


func _update_route_label() -> void:
	if route.is_empty():
		_route_label.text = "No destination. Click a place on the map."
		return
	var lines := []
	for i in route.size():
		lines.append("%d. %s  %s" % [i + 1, route[i].name, System.format_distance(System.distance(route[i].pos, ship_pos))])
	_route_label.text = "\n".join(lines)


# --- Drawing -------------------------------------------------------------------

func _centre() -> Array:
	return ship_pos if level == Level.LOCAL else System.STAR.pos


func _metres_per_pixel() -> float:
	var half := minf(_area.size.x, _area.size.y) * 0.5
	var span := 25_000.0 if level == Level.LOCAL else 1.6 * System.AU
	return span / maxf(half, 1.0) / _zoom.get(level, 1.0)


func _to_screen(pos: Array) -> Vector2:
	var rel := System.diff(pos, _centre()) # fine for drawing: pixels can't show the lost precision
	return _area.size * 0.5 + Vector2(rel.x, rel.z) / _metres_per_pixel()


func _visible_items() -> Array:
	var out := []
	for it in items:
		if filters.get(it.kind, true) and not (level == Level.SYSTEM and it.get("local", false)):
			out.append(it)
	return out


func _draw_map() -> void:
	var font := get_theme_default_font()
	if level == Level.GALACTIC:
		if WarInfo.war().is_empty():
			var c := _area.size * 0.5
			_area.draw_circle(c, 8, Color(1.0, 0.85, 0.55))
			_area.draw_string(font, c + Vector2(14, 5), "Teal Prime (you are here)", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, colour)
			_area.draw_string(font, c + Vector2(-160, 60), "No other systems charted yet.", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.5))
		else:
			_draw_war_map(font)
		return

	# Range rings.
	var ring_step := 5_000.0 if level == Level.LOCAL else 0.25 * System.AU
	var mpp := _metres_per_pixel()
	var c0 := _to_screen(_centre())
	for i in range(1, 9):
		_area.draw_arc(c0, ring_step * i / mpp, 0, TAU, 96, Color(colour, 0.12), 1.0)
	_area.draw_string(font, c0 + Vector2(ring_step / mpp + 4, -4), System.format_distance(ring_step), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(colour, 0.5))

	if level == Level.SYSTEM:
		for body in System.PLANETS + System.homes:
			_area.draw_arc(c0, System.distance(body.pos, System.STAR.pos) / mpp, 0, TAU, 128, Color(colour, 0.2), 1.0)

	# Route.
	var last := _to_screen(ship_pos)
	for stop in route:
		var p := _to_screen(stop.pos)
		_area.draw_dashed_line(last, p, Color(colour, 0.8), 2.0, 8.0)
		last = p

	for it in _visible_items():
		var p := _to_screen(it.pos)
		var col: Color = {"landmark": colour, "waypoint": Color(1.0, 0.75, 0.3), "pilot": Color(0.95, 0.45, 0.65), "facility": Color(1.0, 0.45, 0.35)}.get(it.kind, colour)
		var r := 5.0
		if it.has("radius") and level == Level.SYSTEM:
			r = clampf(it.radius / mpp, 4.0, 40.0)
		if it.kind == "waypoint":
			_area.draw_rect(Rect2(p - Vector2(5, 5), Vector2(10, 10)), col, false, 2.0)
		else:
			_area.draw_circle(p, r, col)
		var label_at := p + Vector2(r + 6, 5)
		var wp := WarInfo.planet(it.id) if level == Level.SYSTEM else {}
		if not wp.is_empty():
			# A contested world: a ring in its owner's colour, and who holds it under the name.
			var owner_col := WarInfo.faction_color(wp.owner)
			_area.draw_arc(p, r + 4.0, 0, TAU, 32, owner_col, 2.0)
			var lock := WarInfo.lock_left(wp)
			var line := "%s · %s" % [WarInfo.faction_name(wp.owner), WarInfo.contention(wp)]
			var at := p + Vector2(r + 6, 21)
			if lock != "":
				_padlock(at + Vector2(4, -9), owner_col)
				at.x += 14
			_area.draw_string(font, at, line, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, owner_col)
		elif it.has("near") and level == Level.SYSTEM:
			# A station: its name under its planet's lines, since at this scale they're one dot.
			label_at.y += 32 if not WarInfo.planet(it.near).is_empty() else 16
		_area.draw_string(font, label_at, it.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)

	# The ship: an arrow pointing along its heading.
	var s := _to_screen(ship_pos)
	var h := Vector2(ship_heading.x, ship_heading.z)
	var angle := h.angle() + PI / 2 if h.length() > 0.001 else 0.0
	_area.draw_set_transform(s, angle)
	_area.draw_texture_rect(PILOT_ICON, Rect2(-12, -12, 24, 24), false, Color.WHITE)
	_area.draw_set_transform(Vector2.ZERO)
	_area.draw_string(font, s + Vector2(16, -8), "You", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)


## The war map: systems at their places, lanes between them, each contested planet as a dot in its
## owner's colour on a ring round its system, and under each system its planets, who holds them
## and how hard they're fought over, its orbital control and the fleets over it. Fleets in orbit
## sit beside their system, fleets under way move along the lanes: a triangle for a Builder's
## fleet, a diamond for a Coma armada. Your faction's systems glow in its colour.
func _draw_war_map(font: Font) -> void:
	_war_hits.clear()
	var war := WarInfo.war()
	var mine := WarInfo.my_faction()
	var size := _area.size
	var uy := maxf(40.0, (size.y - 190.0) / 4.0)
	var ux := minf(size.x / 3.4, uy * 2.6)
	# A little right of centre, to leave the key room in the top left.
	var c := Vector2(size.x * 0.5 + (50.0 if size.x > 800.0 else 0.0), size.y * 0.5 - 40.0)
	var at := {}
	for s in war.systems:
		at[s.id] = c + Vector2(float(s.pos[0]) * ux, float(s.pos[1]) * uy)
	for s in war.systems:
		for id in s.lanes:
			if str(id) > str(s.id) and at.has(id):
				_area.draw_line(at[s.id], at[id], Color(colour, 0.35), 2.0)
	for s in war.systems:
		var p: Vector2 = at[s.id]
		var planets := WarInfo.planets_in(s.id)
		var cap = s.get("capitalOf")
		var ring := WarInfo.faction_color(cap) if cap != null else colour
		if mine != "" and (cap == mine or planets.any(func(wp): return wp.owner == mine)):
			_area.draw_circle(p, 34.0, Color(WarInfo.faction_color(mine), 0.16))
		_area.draw_circle(p, 18.0, Color(0.02, 0.05, 0.08))
		_area.draw_arc(p, 18.0, 0, TAU, 48, ring, 2.5)
		if s.get("home", false):
			_area.draw_circle(p, 6.0, System.STAR.color)
		# The planets ride on the upper half of a ring round the system; its name goes underneath.
		for i in planets.size():
			var wp: Dictionary = planets[i]
			var a := PI + PI * (i + 1) / (planets.size() + 1)
			var q := p + Vector2(cos(a), sin(a)) * 27.0
			_area.draw_circle(q, 6.0, WarInfo.faction_color(wp.owner))
			if mine != "" and wp.owner == mine:
				_area.draw_arc(q, 8.5, 0, TAU, 20, Color.WHITE, 1.5)
			_war_hits.append([Rect2(q - Vector2(9, 9), Vector2(18, 18)), wp.id])
		# Under the system: its name, what it is, a line per planet, then orbital control and
		# the fleets over it, each part in its faction's colour.
		var lines := [[s.name, 16, ring if cap != null else Color.WHITE, ""]]
		var what := "capital of %s" % WarInfo.the(cap) if cap != null else "neutral space"
		if s.get("home", false):
			what = "the Builders' home system · you are here"
		if cap != null and cap == mine:
			what += " · your capital"
		lines.append([what, 12, Color(1, 1, 1, 0.6), ""])
		for wp in planets:
			var state := "capital world" if wp.get("capital", false) else WarInfo.contention(wp)
			lines.append(["%s · %s · %s" % [wp.name, WarInfo.faction_name(wp.owner), state], 13, WarInfo.faction_color(wp.owner), wp.id if WarInfo.lock_left(wp) == "" else "lock:" + wp.id])
		var orbit := [["orbit: ", Color(1, 1, 1, 0.6)]]
		for f in WarInfo.faction_ids():
			var share := WarInfo.orbital(s.id, f)
			if share > 0.0:
				orbit.append(["%s%s %d%%" % [", " if orbit.size() > 1 else "", str(f).capitalize(), roundi(share * 100.0)], WarInfo.faction_color(f).lightened(0.2)])
		if orbit.size() > 1:
			lines.append(_segments_line(orbit, 12))
		var groups := _fleet_groups(s.id)
		if not groups.is_empty():
			var segs := []
			for g in groups:
				var bit := "%s: %s" % [g.name, _ships_word(g.ships)] if g.ships > 0 else "%s: %s on the way" % [g.name, _ships_word(g.coming)]
				if g.ships > 0 and g.coming > 0:
					bit += ", %d on the way" % g.coming
				segs.append([(" · " if not segs.is_empty() else "") + bit, WarInfo.faction_color(g.faction).lightened(0.2)])
			lines.append(_segments_line(segs, 12))
			# The fleets in orbit, beside the system.
			var k := 0
			for g in groups:
				if g.ships > 0:
					_fleet_mark(p + Vector2(30.0 + k * 15.0, 0.0), WarInfo.faction_color(g.faction), g.armada)
					k += 1
		var widest := 0.0
		for l in lines:
			widest = maxf(widest, font.get_string_size(l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, l[1]).x + (14.0 if str(l[3]).begins_with("lock:") else 0.0))
		var y := p.y + 38.0
		_area.draw_rect(Rect2(p.x - widest / 2.0 - 6.0, y - 14.0, widest + 12.0, lines.size() * 16.0 + 6.0), Color(0.0, 0.02, 0.05, 0.8))
		for l in lines:
			var text: String = l[0]
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, l[1]).x
			var x := p.x - w / 2.0
			var tag := str(l[3])
			if tag.begins_with("lock:"):
				x += 7.0
				_padlock(Vector2(x - 12.0, y - 9.0), l[2])
				tag = tag.substr(5)
			if l.size() > 4:
				for seg in l[4]:
					_area.draw_string(font, Vector2(x, y), seg[0], HORIZONTAL_ALIGNMENT_LEFT, -1, l[1], seg[1])
					x += font.get_string_size(seg[0], HORIZONTAL_ALIGNMENT_LEFT, -1, l[1]).x
			else:
				_area.draw_string(font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, l[1], l[2])
			if tag != "":
				_war_hits.append([Rect2(x - 14.0, y - 13.0, w + 16.0, 16.0), tag])
			y += 16.0
	_draw_fleets_under_way(at) # over the systems' labels, so none is hidden
	# The key, top left.
	var key := []
	for f in WarInfo.faction_ids() + [null]:
		key.append(["dot", WarInfo.faction_color(f), WarInfo.faction_name(f) + (" (your side)" if f != null and f == mine else "")])
	key.append(["lock", Color(1, 1, 1, 0.8), "locked a week after a change"])
	key.append(["fleet", Color(1, 1, 1, 0.8), "a Builder's fleet"])
	key.append(["armada", Color(1, 1, 1, 0.8), "a Coma armada"])
	var key_w := 0.0
	for k in key:
		key_w = maxf(key_w, font.get_string_size(k[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x)
	_area.draw_rect(Rect2(0, 0, key_w + 30.0, key.size() * 16.0 + 28.0), Color(0.0, 0.02, 0.05, 0.8))
	var ky := 16.0
	for k in key:
		match k[0]:
			"dot":
				_area.draw_circle(Vector2(11, ky - 4), 5, k[1])
			"lock":
				_padlock(Vector2(6, ky - 9), k[1])
			_:
				_fleet_mark(Vector2(11, ky - 4), k[1], k[0] == "armada")
		_area.draw_string(font, Vector2(22, ky), k[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.8))
		ky += 16.0
	_area.draw_string(font, Vector2(6, ky + 4), "Click a planet: War terminal", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(colour, 0.8))


func _ships_word(n: int) -> String:
	return "%d ship%s" % [n, "" if n == 1 else "s"]


## A line of the war map drawn in coloured parts: [[text, colour], ...].
func _segments_line(segs: Array, font_size: int) -> Array:
	var text := ""
	for seg in segs:
		text += seg[0]
	return [text, font_size, Color.WHITE, "", segs]


## The fleets over a system or on their way there, one group per side: a Builder faction's fleets
## together, the Coma armadas together. [{"faction", "name", "armada", "ships", "coming"}]
func _fleet_groups(system_id: String) -> Array:
	var by := {}
	var order := []
	for fl in WarInfo.fleets_at(system_id):
		var armada := WarInfo.is_armada(fl)
		var key := "%s:%s" % [fl.faction, armada]
		if not by.has(key):
			by[key] = {"faction": str(fl.faction), "armada": armada, "ships": 0, "coming": 0,
				"name": WarInfo.fleet_name(fl) if armada else str(fl.faction).capitalize()}
			order.append(key)
		var n := WarInfo.ship_count(fl.ships)
		if fl.status == "stationed":
			by[key].ships += n
		else:
			by[key].coming += n
	return order.map(func(k): return by[k])


## Fleets flying out or heading home, along the lanes between their home and where they're bound.
func _draw_fleets_under_way(at: Dictionary) -> void:
	var now := Net.now_ms()
	for fl in WarInfo.war().get("fleets", []):
		if fl.status == "stationed":
			continue
		var path := WarInfo.route(WarInfo.fleet_home(fl), str(fl.system))
		if path.size() < 2:
			continue # a fleet that stays in its home system
		var leg := maxf(1.0, float(fl.get("leg", 1)))
		var t := 1.0 - (float(fl.arriveAt) - now) / leg if fl.status == "flying" else (float(fl.get("returnAt", 0)) - now) / leg
		t = clampf(t, 0.0, 1.0) * (path.size() - 1)
		var i := mini(int(t), path.size() - 2)
		var a: Vector2 = at.get(path[i], Vector2.ZERO)
		var b: Vector2 = at.get(path[i + 1], Vector2.ZERO)
		var q := a.lerp(b, t - i)
		var col := WarInfo.faction_color(fl.faction)
		_fleet_mark(q, col, WarInfo.is_armada(fl), (b - a).angle() + (0.0 if fl.status == "flying" else PI))


## A fleet's marker: a triangle pointing the way it flies, or a diamond for a Coma armada.
func _fleet_mark(at: Vector2, col: Color, armada: bool, heading := -PI / 2.0) -> void:
	var pts: PackedVector2Array
	if armada:
		pts = PackedVector2Array([at + Vector2(0, -7), at + Vector2(6, 0), at + Vector2(0, 7), at + Vector2(-6, 0)])
	else:
		pts = PackedVector2Array([at + Vector2(7, 0).rotated(heading), at + Vector2(-5, -5).rotated(heading), at + Vector2(-5, 5).rotated(heading)])
	_area.draw_colored_polygon(pts, col)
	pts.append(pts[0])
	_area.draw_polyline(pts, Color(0, 0, 0, 0.7), 1.0)


## A small padlock with its top left at `at`.
func _padlock(at: Vector2, col: Color) -> void:
	_area.draw_arc(at + Vector2(5, 4), 3.0, PI, TAU, 10, col, 1.5)
	_area.draw_rect(Rect2(at + Vector2(1, 4), Vector2(8, 6)), col)


func _war_planet_at(point: Vector2) -> String:
	for hit in _war_hits:
		if (hit[0] as Rect2).has_point(point):
			return hit[1]
	return ""


func _on_map_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and level == Level.GALACTIC:
		if event.button_index == MOUSE_BUTTON_LEFT and _war_planet_at(event.position) != "":
			war_planet_picked.emit(_war_planet_at(event.position))
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_zoom[level] = minf(_zoom.get(level, 1.0) * 1.25, 400.0)
				_area.queue_redraw()
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom[level] = maxf(_zoom.get(level, 1.0) / 1.25, 0.05)
				_area.queue_redraw()
			MOUSE_BUTTON_LEFT:
				var it := _item_at(event.position)
				if it.is_empty():
					return
				if event.shift_pressed:
					set_route(route + [it])
				else:
					set_route([it])
			MOUSE_BUTTON_RIGHT:
				var it := _item_at(event.position)
				if it.get("kind", "") == "waypoint":
					waypoint_removed.emit(it.id)


func _item_at(point: Vector2) -> Dictionary:
	if level == Level.GALACTIC:
		return {}
	var best := {}
	var best_d := 16.0
	for it in _visible_items():
		var d := _to_screen(it.pos).distance_to(point)
		if d < best_d:
			best_d = d
			best = it
	return best
