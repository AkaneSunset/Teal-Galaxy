extends Control
## The War terminal: the contested planets of the war, and a sector view of one of them.
## Opened from a High Port or orbital station (the War terminals in the Terminal Hall), the ship's
## menu, or a planet on the nav map's Galactic level.
##
## Left: every planet of the war map by system (owner, contention, lock), and orbital control over
## the chosen planet's system with the 25% a faction needs before it can attack. Right: the planet
## as a globe you drag to turn, its sectors as dots in their owners' colours, links between
## neighbours, the capital sector ringed, outposts as small squares. Click a sector for its
## details. On a demo server (the catalog's `demo`), a sector your side can take has a
## "Take sector (demo)" button, which sends `demo_capture`.
## On a server with sector battles (game/battle/ in the build), "Sector Battles" opens that screen
## for the planet shown (`wants_battles`): attack a sector or join a battle running there.
## For the galaxy's admins (Net.admin) it has two more things: "Take for Coma" on sectors the Coma
## Conglomerate can take (`admin_capture`, every rule applies), and the Coma director page
## (director_panel.gd), swapped in for the sectors with the buttons at the top.

const WarInfo := preload("res://war_info.gd")
const DirectorPanel := preload("res://director_panel.gd")

signal closed
signal wants_faction # the pilot has no side yet and asked to pick one
signal wants_battles(planet_id: String) # the Sector Battles screen for this planet

var colour := Color(0.35, 0.95, 0.88)
var planet_id := "cinder"

var _selected := "" # sector id
var _yaw := 0.0
var _tilt := deg_to_rad(28.0)
var _drag := false
var _dragged := 0.0
var _planet_buttons := {} # planet id -> Button
var _list: VBoxContainer
var _side: Label
var _pick_side: Button
var _title: Label
var _sub: Label
var _counts: HBoxContainer
var _globe: Control
var _orbital: Control
var _orbital_title: Label
var _info: Label
var _take: Button
var _status: Label
var _taking := "" # the sector a demo capture was sent for, until the state shows it taken
var _taking_for := "" # and for which faction
var _take_coma: Button
var _battles: Button
var _fleets: Label
var _pages: HBoxContainer # admins: Sectors | Coma director
var _sectors_page: Button
var _director_page: Button
var _row: HBoxContainer # the sectors page
var _director: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.02, 0.05, 0.97)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	margin.add_child(page)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	page.add_child(top)
	var heading := Label.new()
	heading.text = "War terminal"
	heading.add_theme_font_size_override("font_size", 26)
	top.add_child(heading)
	_side = Label.new()
	_side.add_theme_font_size_override("font_size", 18)
	_side.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_side)
	_pick_side = Button.new()
	_pick_side.text = "Choose a faction"
	_pick_side.pressed.connect(func(): wants_faction.emit())
	top.add_child(_pick_side)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(gap)
	_pages = HBoxContainer.new()
	_pages.add_theme_constant_override("separation", 4)
	top.add_child(_pages)
	var group := ButtonGroup.new()
	_sectors_page = Button.new()
	_sectors_page.text = "Sectors"
	_director_page = Button.new()
	_director_page.text = "Coma director (admin)"
	for b in [_sectors_page, _director_page]:
		b.toggle_mode = true
		b.button_group = group
		b.pressed.connect(_show_page.bind(b == _director_page))
		_pages.add_child(b)
	_sectors_page.button_pressed = true
	var close := Button.new()
	close.text = "Close (Esc)"
	close.pressed.connect(func(): closed.emit())
	top.add_child(close)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(row)
	_row = row
	_director = DirectorPanel.new()
	_director.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_director.visible = false
	page.add_child(_director)

	# Left: the planets of the war, then orbital control.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(330, 0)
	left.add_theme_constant_override("separation", 8)
	row.add_child(left)
	left.add_child(_heading("Contested worlds"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_list)
	_orbital_title = _heading("Orbital control")
	left.add_child(_orbital_title)
	_orbital = Control.new()
	_orbital.custom_minimum_size = Vector2(0, 4 * 24 + 22)
	_orbital.draw.connect(_draw_orbital)
	left.add_child(_orbital)
	_fleets = Label.new()
	_fleets.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fleets.custom_minimum_size = Vector2(330, 0)
	_fleets.add_theme_font_size_override("font_size", 14)
	left.add_child(_fleets)

	# Right: the chosen planet.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	row.add_child(right)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 24)
	right.add_child(_title)
	_sub = Label.new()
	right.add_child(_sub)
	_counts = HBoxContainer.new()
	_counts.add_theme_constant_override("separation", 18)
	right.add_child(_counts)
	_globe = Control.new()
	_globe.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_globe.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_globe.clip_contents = true
	_globe.mouse_filter = Control.MOUSE_FILTER_STOP
	_globe.draw.connect(_draw_globe)
	_globe.gui_input.connect(_on_globe_input)
	right.add_child(_globe)
	var info_row := HBoxContainer.new()
	info_row.add_theme_constant_override("separation", 16)
	right.add_child(info_row)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info.custom_minimum_size = Vector2(0, 92)
	info_row.add_child(_info)
	var takes := VBoxContainer.new()
	takes.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info_row.add_child(takes)
	_take = Button.new()
	_take.text = "Take sector (demo)"
	_take.pressed.connect(_take_sector)
	takes.add_child(_take)
	_battles = Button.new()
	_battles.text = "Sector Battles"
	_battles.tooltip_text = "Attack a sector from a carrier in this orbit, or join a battle running here"
	_battles.pressed.connect(func(): wants_battles.emit(planet_id))
	takes.add_child(_battles)
	_take_coma = Button.new()
	_take_coma.text = "Take for Coma"
	_take_coma.add_theme_color_override("font_color", WarInfo.faction_color("coma").lightened(0.3))
	_take_coma.pressed.connect(_take_for_coma)
	takes.add_child(_take_coma)
	_status = Label.new()
	_status.modulate = Color(1, 1, 1, 0.7)
	right.add_child(_status)
	Net.server_error.connect(func(reason):
		_taking = ""
		if visible and not _director.visible:
			_status.text = "Server: " + reason)
	refresh()


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	return l


## Shows a planet, facing its capital sector (or the pilot's front line there).
func open(id: String) -> void:
	if not WarInfo.planet(id).is_empty():
		planet_id = id
	_selected = ""
	_status.text = ""
	var wp := WarInfo.planet(planet_id)
	if not wp.get("sectors", []).is_empty():
		_face(wp.sectors[0])
	refresh()


## Turns the globe so a sector faces you.
func _face(sec: Dictionary) -> void:
	_yaw = deg_to_rad(float(sec.lon)) - PI / 2.0
	_tilt = clampf(deg_to_rad(float(sec.lat)) * 0.6, -1.2, 1.2)


func refresh() -> void:
	if not is_node_ready() or WarInfo.war().is_empty():
		return
	var mine := WarInfo.my_faction()
	_side.text = "Your side: %s" % WarInfo.faction_name(mine) if mine != "" else "You haven't picked a side yet"
	_side.add_theme_color_override("font_color", WarInfo.faction_color(mine) if mine != "" else Color(1, 1, 1, 0.6))
	_pick_side.visible = mine == ""
	_pages.visible = Net.admin
	if not Net.admin and _director.visible:
		_show_page(false)
	if _director.visible:
		_director.colour = colour
		_director.refresh()
	_refresh_list()
	var wp := WarInfo.planet(planet_id)
	if wp.is_empty():
		return
	var sys := WarInfo.system(wp.system)
	_title.text = "%s · %s" % [wp.name, sys.get("name", wp.system)]
	var bits := ["held by %s" % WarInfo.the(wp.owner) if wp.owner != null else "nobody holds it"]
	if wp.get("capital", false):
		bits.append("a capital world: it can't be attacked")
	else:
		bits.append(WarInfo.contention(wp))
	var lock := WarInfo.lock_left(wp)
	if lock != "":
		bits.append("locked for " + lock)
	bits.append("%d sectors: the capital sector and %d%% win it" % [wp.sectors.size(), roundi(float(Net.catalog.get("war", {}).get("planetShare", 0.75)) * 100.0)])
	var line := ", ".join(bits)
	_sub.text = line.substr(0, 1).to_upper() + line.substr(1)
	for child in _counts.get_children():
		child.queue_free()
	for f in WarInfo.faction_ids() + [null]:
		var n := WarInfo.held(wp, f)
		if n == 0:
			continue
		var l := Label.new()
		l.text = "%s %d" % [WarInfo.faction_name(f), n]
		l.add_theme_color_override("font_color", WarInfo.faction_color(f))
		_counts.add_child(l)
	_orbital_title.text = "Orbital control over %s" % sys.get("name", wp.system)
	_orbital.queue_redraw()
	_fleets.text = _fleets_text(wp.system)
	_globe.queue_redraw()
	_refresh_info(wp)


func _refresh_list() -> void:
	if _planet_buttons.is_empty():
		for s in WarInfo.war().get("systems", []):
			var head := Label.new()
			var cap = s.get("capitalOf")
			head.text = s.name + ("  (capital of %s)" % WarInfo.the(cap) if cap != null else ("  (the Builders' home system)" if s.get("home", false) else ""))
			head.modulate = Color(1, 1, 1, 0.55)
			_list.add_child(head)
			for wp in WarInfo.planets_in(s.id):
				var b := Button.new()
				b.toggle_mode = true
				b.alignment = HORIZONTAL_ALIGNMENT_LEFT
				b.pressed.connect(open.bind(wp.id))
				_list.add_child(b)
				_planet_buttons[wp.id] = b
	for id in _planet_buttons:
		var wp := WarInfo.planet(id)
		var b: Button = _planet_buttons[id]
		var what := "capital world" if wp.get("capital", false) else WarInfo.contention(wp)
		b.text = "  %s   %s · %s%s" % [wp.name, WarInfo.faction_name(wp.owner), what, " · locked" if WarInfo.lock_left(wp) != "" else ""]
		b.add_theme_color_override("font_color", WarInfo.faction_color(wp.owner))
		b.add_theme_color_override("font_pressed_color", WarInfo.faction_color(wp.owner).lightened(0.3))
		b.button_pressed = id == planet_id


func _refresh_info(wp: Dictionary) -> void:
	var sec := WarInfo.sector(wp, _selected)
	_take.visible = false
	_take_coma.visible = false
	_battles.visible = ResourceLoader.exists("res://battle/battle_menu.gd") and not wp.is_empty()
	if sec.is_empty():
		_info.text = "Click a sector for its details. Drag the globe to turn it."
		return
	var lines := ["%s: %s%s" % [sec.name, "held by " + WarInfo.the(sec.owner) if sec.owner != null else "nobody holds it", ", the capital sector" if sec.get("capital", false) else ""]]
	var near := []
	for id in sec.get("links", []):
		near.append(WarInfo.sector(wp, id).get("name", id))
	lines.append("Next to " + ", ".join(near))
	var here := []
	for site in WarInfo.outposts_on(wp.id):
		if site.get("sector", "") == sec.id:
			here.append("%s (%s, %s%s)" % [WarInfo.short_site_name(site), site.owner, WarInfo.faction_name(site.get("faction")), ", dormant" if site.get("dormant", false) else ""])
	lines.append("Outposts: " + (", ".join(here) if not here.is_empty() else "none"))
	var mine := WarInfo.my_faction()
	if _taking == sec.id and _taking_for != "" and sec.owner == _taking_for:
		_taking = ""
		_status.text = "%s is %s's now." % [sec.name, WarInfo.the(_taking_for)]
	if Net.catalog.get("demo", false):
		var why := WarInfo.take_problem(mine, wp, sec)
		_take.visible = why == ""
		if why != "" and (mine == "" or sec.owner != mine):
			lines.append("Can't take it: " + why)
	elif not Net.admin:
		lines.append("Sectors change hands in sector battles: Sector Battles, from a carrier in this planet's orbit.")
	if Net.admin and not (Net.catalog.get("demo", false) and mine == "coma"):
		# An admin plays the Coma Conglomerate by hand: every rule of a capture applies.
		var why := WarInfo.take_problem("coma", wp, sec)
		_take_coma.visible = why == ""
		if why != "" and sec.owner != "coma":
			lines.append("Coma can't take it: " + why)
	_info.text = "\n".join(lines)


func _take_sector() -> void:
	var sec := WarInfo.sector(WarInfo.planet(planet_id), _selected)
	if sec.is_empty():
		return
	_taking = sec.id
	_taking_for = WarInfo.my_faction()
	_status.text = "Taking %s for %s..." % [sec.name, WarInfo.the(_taking_for)]
	Net.send({"type": "demo_capture", "planet": planet_id, "sector": _selected})


## Admins: flips the chosen sector to the Coma Conglomerate, as if Coma had won a battle there.
func _take_for_coma() -> void:
	var sec := WarInfo.sector(WarInfo.planet(planet_id), _selected)
	if sec.is_empty():
		return
	_taking = sec.id
	_taking_for = "coma"
	_status.text = "Taking %s for %s..." % [sec.name, WarInfo.the("coma")]
	Net.send({"type": "admin_capture", "planet": planet_id, "sector": _selected})


## Admins: the sectors, or the Coma director in their place.
func _show_page(director: bool) -> void:
	_director.visible = director
	_row.visible = not director
	(_director_page if director else _sectors_page).set_pressed_no_signal(true)
	(_sectors_page if director else _director_page).set_pressed_no_signal(false)
	_status.text = ""
	refresh()


## The fleets over a system and on their way there: "Coma armada (2 Destroyers, 3 Frigates), in
## orbit". Armadas are the Coma Conglomerate's fleets, which no Builder owns.
func _fleets_text(system_id: String) -> String:
	var fleets := WarInfo.fleets_at(system_id)
	if fleets.is_empty():
		return "No fleets over %s." % WarInfo.system(system_id).get("name", system_id)
	var lines := []
	for fl in fleets.slice(0, 6):
		lines.append("%s (%s%s), %s" % [WarInfo.fleet_name(fl), WarInfo.ships_text(fl.ships),
			"" if WarInfo.is_armada(fl) else ", " + WarInfo.faction_name(fl.faction), "in orbit" if fl.status == "stationed" else "on the way"])
	if fleets.size() > 6:
		lines.append("and %d more" % (fleets.size() - 6))
	return "\n".join(lines)


# --- The globe -------------------------------------------------------------------------------

func _radius() -> float:
	return minf(_globe.size.x, _globe.size.y) * 0.44


## A spot on the planet as [screen point, depth]: depth > 0 is the side facing you.
func _project(lat: float, lon: float) -> Array:
	var la := deg_to_rad(lat)
	var lo := deg_to_rad(lon)
	var v := Vector3(cos(la) * cos(lo), sin(la), cos(la) * sin(lo))
	v = v.rotated(Vector3.UP, _yaw).rotated(Vector3.RIGHT, _tilt)
	return [_globe.size * 0.5 + Vector2(v.x, -v.y) * _radius(), v.z]


func _draw_globe() -> void:
	var wp := WarInfo.planet(planet_id)
	if wp.is_empty():
		return
	var font := get_theme_default_font()
	var c := _globe.size * 0.5
	var r := _radius()
	_globe.draw_circle(c, r, Color(0.03, 0.07, 0.1))
	_globe.draw_arc(c, r, 0, TAU, 128, Color(colour, 0.45), 2.0)
	# Latitude and longitude lines, on the near side.
	for lat in [-60.0, -30.0, 0.0, 30.0, 60.0]:
		_globe_line(func(t): return [lat, t * 360.0], Color(colour, 0.08 if lat != 0.0 else 0.16))
	for lon in range(0, 360, 30):
		_globe_line(func(t): return [-90.0 + t * 180.0, float(lon)], Color(colour, 0.08))

	var sectors: Array = wp.sectors
	var at := {}
	for s in sectors:
		at[s.id] = _project(float(s.lat), float(s.lon))
	# Links between neighbours, each once.
	for s in sectors:
		for id in s.get("links", []):
			if str(id) <= str(s.id) or not at.has(id):
				continue
			var a: Array = at[s.id]
			var b: Array = at[id]
			var depth := minf(a[1], b[1])
			if depth > -0.15:
				_globe.draw_line(a[0], b[0], Color(1, 1, 1, clampf(0.12 + depth * 0.4, 0.05, 0.45)), 1.5)
	var mine := WarInfo.my_faction()
	var demo: bool = Net.catalog.get("demo", false)
	# Far side first, dim, then the near side over it.
	for pass_near in [false, true]:
		for s in sectors:
			var p: Array = at[s.id]
			if (p[1] > 0.0) != pass_near:
				continue
			var col := WarInfo.faction_color(s.owner)
			var dot := 10.0 if s.get("capital", false) else 7.0
			if not pass_near:
				_globe.draw_circle(p[0], dot * 0.6, Color(col, 0.25))
				continue
			if demo and mine != "" and WarInfo.take_problem(mine, wp, s) == "":
				_globe.draw_arc(p[0], dot + 5.0, 0, TAU, 24, Color(WarInfo.faction_color(mine), 0.6 + 0.4 * sin(Time.get_ticks_msec() / 250.0)), 2.0)
			elif Net.admin and mine != "coma" and WarInfo.take_problem("coma", wp, s) == "":
				_globe.draw_arc(p[0], dot + 5.0, 0, TAU, 24, Color(WarInfo.faction_color("coma"), 0.6 + 0.4 * sin(Time.get_ticks_msec() / 250.0)), 2.0)
			_globe.draw_circle(p[0], dot, col)
			if s.get("capital", false):
				_globe.draw_arc(p[0], dot + 3.0, 0, TAU, 24, Color.WHITE, 2.0)
				_globe.draw_string(font, p[0] + Vector2(dot + 6, -8), "capital", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.8))
			if s.id == _selected:
				_globe.draw_arc(p[0], dot + 8.0, 0, TAU, 32, Color.WHITE, 2.5)
			_globe.draw_string(font, p[0] + Vector2(dot + 4, 5), str(s.id).get_slice("-", str(s.id).get_slice_count("-") - 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.85))
	# Outposts: small squares, dim when dormant.
	for site in WarInfo.outposts_on(planet_id):
		var spot = site.get("surface")
		if not spot is Array or spot.size() != 2:
			continue
		var p := _project(float(spot[0]), float(spot[1]))
		if p[1] <= 0.0:
			continue
		var col := WarInfo.faction_color(site.get("faction"))
		if site.get("dormant", false):
			col = Color(col.darkened(0.4), 0.6)
		var q: Vector2 = p[0] + Vector2(0, 14)
		_globe.draw_rect(Rect2(q - Vector2(4, 4), Vector2(8, 8)), col)
		_globe.draw_rect(Rect2(q - Vector2(4, 4), Vector2(8, 8)), Color(0, 0, 0, 0.6), false, 1.0)
	# The key.
	var y := 18.0
	for f in WarInfo.faction_ids() + [null]:
		_globe.draw_circle(Vector2(14, y - 4), 5, WarInfo.faction_color(f))
		_globe.draw_string(font, Vector2(26, y), WarInfo.faction_name(f) + (" (you)" if f != null and f == mine else ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.8))
		y += 18.0
	_globe.draw_rect(Rect2(Vector2(10, y - 8), Vector2(8, 8)), Color(1, 1, 1, 0.8))
	_globe.draw_string(font, Vector2(26, y), "Outpost", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.8))
	if demo and mine != "":
		y += 18.0
		_globe.draw_arc(Vector2(14, y - 4), 6, 0, TAU, 16, WarInfo.faction_color(mine), 2.0)
		_globe.draw_string(font, Vector2(26, y), "Your side can take it", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.8))
	if Net.admin and mine != "coma":
		y += 18.0
		_globe.draw_arc(Vector2(14, y - 4), 6, 0, TAU, 16, WarInfo.faction_color("coma"), 2.0)
		_globe.draw_string(font, Vector2(26, y), "Coma can take it", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.8))


## A line over the globe's near side, from `at(0)` to `at(1)` ([lat, lon] for t in 0..1).
func _globe_line(at: Callable, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 49:
		var ll: Array = at.call(i / 48.0)
		var p := _project(ll[0], ll[1])
		if p[1] > 0.0:
			pts.append(p[0])
		else:
			if pts.size() > 1:
				_globe.draw_polyline(pts, col, 1.0)
			pts = PackedVector2Array()
	if pts.size() > 1:
		_globe.draw_polyline(pts, col, 1.0)


func _on_globe_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag = true
			_dragged = 0.0
		else:
			_drag = false
			if _dragged < 5.0:
				_pick(event.position)
	elif event is InputEventMouseMotion and _drag:
		_dragged += event.relative.length()
		_yaw += event.relative.x * 0.008
		_tilt = clampf(_tilt + event.relative.y * 0.008, -1.4, 1.4)
		_globe.queue_redraw()


func _pick(point: Vector2) -> void:
	var wp := WarInfo.planet(planet_id)
	var best := ""
	var best_d := 16.0
	for s in wp.get("sectors", []):
		var p := _project(float(s.lat), float(s.lon))
		var d: float = (p[0] as Vector2).distance_to(point)
		if p[1] > 0.0 and d < best_d:
			best_d = d
			best = s.id
	_selected = best
	_status.text = ""
	_refresh_info(wp)
	_globe.queue_redraw()


## For tests and screenshots: pick a sector by id and turn the globe to it.
func select(sector_id: String) -> void:
	var sec := WarInfo.sector(WarInfo.planet(planet_id), sector_id)
	if sec.is_empty():
		return
	_selected = sector_id
	_face(sec)
	refresh()


func _process(_delta: float) -> void:
	# The rings round sectors you can take pulse.
	if visible and (Net.catalog.get("demo", false) or Net.admin) and _row.visible:
		_globe.queue_redraw()


# --- Orbital control ------------------------------------------------------------------------

func _draw_orbital() -> void:
	var wp := WarInfo.planet(planet_id)
	if wp.is_empty():
		return
	var font := get_theme_default_font()
	var w := _orbital.size.x
	var bar_x := 150.0
	var bar_w := w - bar_x - 50.0
	var y := 6.0
	for f in WarInfo.faction_ids():
		var share := WarInfo.orbital(wp.system, f)
		var col := WarInfo.faction_color(f)
		_orbital.draw_string(font, Vector2(0, y + 13), WarInfo.faction_name(f), HORIZONTAL_ALIGNMENT_LEFT, bar_x - 8, 14, col)
		_orbital.draw_rect(Rect2(bar_x, y + 3, bar_w, 12), Color(1, 1, 1, 0.08))
		_orbital.draw_rect(Rect2(bar_x, y + 3, bar_w * share, 12), col)
		_orbital.draw_string(font, Vector2(bar_x + bar_w + 6, y + 13), "%d%%" % roundi(share * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.8))
		y += 24.0
	var line := bar_x + bar_w * WarInfo.carrier_share()
	_orbital.draw_line(Vector2(line, 2), Vector2(line, y), Color(1, 1, 1, 0.7), 1.5)
	_orbital.draw_string(font, Vector2(line - 30, y + 14), "%d%% to attack" % roundi(WarInfo.carrier_share() * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.7))
