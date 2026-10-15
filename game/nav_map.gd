extends Control
## Navigation map with three levels: Local, System and Galactic.
## Shows landmarks, saved waypoints and other pilots, each of which can be filtered out.
## Click a place to fly there; shift-click to add it to the route queue; right-click a waypoint
## to delete it. Seen from above, with the ship's heading drawn as a line.

const System := preload("res://teal_prime.gd")

signal route_changed(route: Array)
signal waypoint_added
signal waypoint_removed(id: String)

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

	var title := Label.new()
	title.text = "Navigation"
	title.add_theme_font_size_override("font_size", 24)
	side_panel.add_child(title)
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
		var c := _area.size * 0.5
		_area.draw_circle(c, 8, Color(1.0, 0.85, 0.55))
		_area.draw_string(font, c + Vector2(14, 5), "Teal Prime (you are here)", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, colour)
		_area.draw_string(font, c + Vector2(-160, 60), "No other systems charted yet.", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.5))
		return

	# Range rings.
	var ring_step := 5_000.0 if level == Level.LOCAL else 0.25 * System.AU
	var mpp := _metres_per_pixel()
	var c0 := _to_screen(_centre())
	for i in range(1, 9):
		_area.draw_arc(c0, ring_step * i / mpp, 0, TAU, 96, Color(colour, 0.12), 1.0)
	_area.draw_string(font, c0 + Vector2(ring_step / mpp + 4, -4), System.format_distance(ring_step), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(colour, 0.5))

	if level == Level.SYSTEM:
		for body in System.PLANETS:
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
		_area.draw_string(font, p + Vector2(r + 6, 5), it.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)

	# The ship, with a line along its heading.
	var s := _to_screen(ship_pos)
	var h := Vector2(ship_heading.x, ship_heading.z).normalized()
	_area.draw_line(s, s + h * 28.0, Color.WHITE, 2.0)
	_area.draw_circle(s, 5, Color.WHITE)
	_area.draw_string(font, s + Vector2(10, -8), "You", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)


func _on_map_input(event: InputEvent) -> void:
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
