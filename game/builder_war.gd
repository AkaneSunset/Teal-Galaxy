extends PanelContainer
## The War screen on the Builder's phone, opened with the War button (or from the Shipyard).
## Left: the galactic war map. Star systems are joined by lanes, each contested planet is a dot in
## its owner's colour (with a padlock while it's locked), a ring round each system shows the
## factions' shares of its orbital control, and a marker shows where your fleets are.
## Tap a system to see it on the right: its planets (owner, sectors each faction holds, lock,
## contention), orbital control with the 25% a faction needs before its carriers can attack there,
## your fleets with Recall, and Send fleet from the hangar to any system that isn't a capital.
## Coma armadas (the AI's fleets) show on the map and in each system like any fleet.
## The Supply tab gives goods from stock to your faction's war supply, for War Merit and rank.
## Admins also get the Director tab: the Coma Conglomerate's AI director (pause, scale, how hard it
## pushes each player faction, each system's posture, armadas, and taking sectors for Coma).
## builder.gd builds it, passes itself as `ui` (its UI helpers, colours and economy) and
## refreshes it with the rest of the HUD.

const R := 13.0 # a system's radius on the map, in pixels
const RING := 30.0 # how far from a system's centre its planets sit
const TRAVEL_S := 120.0 # seconds a jump takes at speed 1 (navy.js TRAVEL_S)
const HOME_JUMPS := 0.25 # a fleet crosses its own home system in a quarter of a jump (war.js)
## How hot a planet is, by how many factions can fight over it: quiet, front line, warzone.
const CONTENTION := [["Quiet", Color(0.62, 0.78, 0.82)], ["Front line", Color(1.0, 0.62, 0.15)], ["Warzone", Color(0.95, 0.35, 0.3)]]
## What the director does in a system, and what each posture means.
const POSTURES := [["push", "Push", "Armadas match the strongest player faction here (times its intensity and the scale), and patrol when no player fleet is here."],
	["hold", "Hold", "Nothing new is sent here and nothing is recalled."],
	["withdraw", "Withdraw", "Every Coma armada here or on its way comes home."]]
const ARMADA_POWER := [10, 400] # the power an admin can send in one armada (server: admin_armada)

var ui # the Builder screen (builder.gd)
var system_id := "teal-prime" # the system picked on the map

var _tab := "map" # "map" (the picked system), "supply" or "director" (admins only)
var _tab_buttons := {}
var _badge_name: Label
var _badge_rank: Label
var _map: Control
var _orbit: Control # the orbital control bars of the picked system
var _detail: VBoxContainer
var _supply: VBoxContainer
var _director: VBoxContainer
var _orders: VBoxContainer # your faction's orders from its High Command (orders_view.gd)
var _key := "" # what the right-hand side was built from; it's rebuilt only when that changes
var _ticks: Array[Callable] = [] # text that changes between rebuilds (ETAs, locks, stock)
var _send := {} # ship id -> how many to send
var _send_to := "" # the system a fleet goes to: the picked one, or home when that's a capital
var _send_for := "" # the picked system _send_to was chosen for
var _armada_power := 60
var _donate_item := ""
var _donate_qty := 10
var _lay_scale := 1.0 # map pixels per unit of a system's pos
var _lay_origin := Vector2.ZERO


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_theme_stylebox_override("panel", ui._box(Color(0.04, 0.07, 0.14, 0.98), ui.C_TEAL.darkened(0.3), 14))
	visible = false
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)
	var title: Label = ui._label(head, 22)
	title.text = "War"
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_badge_name = ui._label(head, 16)
	_badge_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_badge_rank = ui._label(head, 15)
	_badge_rank.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_badge_rank.modulate = Color(0.8, 0.88, 0.95)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	for t in [["map", "Map", "nav_map"], ["orders", "Orders", "mission_complete"], ["supply", "Supply", "vault"], ["director", "Director", "settings"]]:
		var b := Button.new()
		b.text = t[1]
		b.icon = load(ui.ICONS + t[2] + ".png")
		b.toggle_mode = true
		b.add_theme_stylebox_override("pressed", ui._box(ui.C_TEAL.darkened(0.45), ui.C_TEAL, 12))
		b.add_theme_stylebox_override("hover_pressed", ui._box(ui.C_TEAL.darkened(0.4), ui.C_TEAL, 12))
		var id: String = t[0]
		b.pressed.connect(func(): show_tab(id))
		head.add_child(b)
		_tab_buttons[id] = b
	_tab_buttons.director.visible = false # admins only: see refresh()
	var close := Button.new()
	close.text = "X"
	close.pressed.connect(func(): visible = false)
	head.add_child(close)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	col.add_child(body)
	_map = Control.new()
	_map.custom_minimum_size = Vector2(290, 0)
	_map.clip_contents = true
	_map.mouse_filter = Control.MOUSE_FILTER_STOP
	_map.draw.connect(_draw_map)
	_map.gui_input.connect(_on_map_input)
	body.add_child(_map)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(right)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 6)
	right.add_child(_detail)
	_supply = VBoxContainer.new()
	_supply.add_theme_constant_override("separation", 6)
	right.add_child(_supply)
	_director = VBoxContainer.new()
	_director.add_theme_constant_override("separation", 6)
	right.add_child(_director)
	_orders = preload("res://orders_view.gd").new()
	_orders.builder = true # with the controls to supply intelligence
	right.add_child(_orders)
	show_tab("map")


## Opens the screen, on `system` if given (else where it was left).
func open(system := "") -> void:
	visible = true
	if system != "":
		system_id = system
		show_tab("map")
	_key = ""
	if not Net.state.is_empty():
		refresh(Net.state)


func show_tab(id: String) -> void:
	_tab = id
	for t in _tab_buttons:
		_tab_buttons[t].set_pressed_no_signal(t == id)
	_detail.visible = id == "map"
	_supply.visible = id == "supply"
	_director.visible = id == "director"
	_orders.visible = id == "orders"
	_key = ""
	if not Net.state.is_empty():
		refresh(Net.state)


func refresh(state: Dictionary) -> void:
	if not visible or state.is_empty():
		return
	var war: Dictionary = state.get("war", {})
	var e: Dictionary = ui._econ()
	var faction = e.get("faction")
	_badge_name.text = ui._faction_name(faction) if faction != null else "No faction"
	_badge_name.modulate = ui._faction_colour(faction)
	var rank: Dictionary = ui._rank_of(float(e.get("merit", 0)))
	_badge_rank.text = "%s, %d War Merit" % [rank.get("name", ""), int(e.get("merit", 0))]
	if _system(war, system_id).is_empty() and not war.get("systems", []).is_empty():
		system_id = str(war.systems[0].id)
	_tab_buttons.director.visible = ui._admin()
	if _tab == "director" and not ui._admin():
		show_tab("map")
		return
	if _tab == "orders":
		# The orders keep their own key (they tick down every second).
		var f = e.get("faction")
		_orders.show_for(state, str(f) if f != null else "", Net.my_name)
		_map.queue_redraw()
		return
	var key := JSON.stringify({"map": _detail_key, "supply": _supply_key, "director": _director_key}[_tab].call(state, war))
	if key != _key:
		_key = key
		_ticks.clear()
		match _tab:
			"map":
				_build_detail(state, war)
			"supply":
				_build_supply(state, war)
			"director":
				_build_director(state, war)
	for t in _ticks:
		t.call()
	_map.queue_redraw()
	if is_instance_valid(_orbit):
		_orbit.queue_redraw()


# --- The galactic map --------------------------------------------------------------------

func _system(war: Dictionary, id: String) -> Dictionary:
	for s in war.get("systems", []):
		if s.id == id:
			return s
	return {}


func _planets_in(war: Dictionary, sid: String) -> Array:
	return war.get("planets", []).filter(func(p): return p.system == sid)


## Fits every system's pos into the map, with room round the edge for names.
func _layout(systems: Array) -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for s in systems:
		var p := Vector2(float(s.pos[0]), float(s.pos[1]))
		lo = lo.min(p)
		hi = hi.max(p)
	var margin := Vector2(0.75, 0.7)
	var span := hi - lo + margin * 2.0
	_lay_scale = minf(_map.size.x / maxf(span.x, 0.01), _map.size.y / maxf(span.y, 0.01))
	_lay_origin = _map.size / 2.0 - (lo + hi) / 2.0 * _lay_scale


func _pt(pos: Array) -> Vector2:
	return _lay_origin + Vector2(float(pos[0]), float(pos[1])) * _lay_scale


## Where a system's name goes: above it for a system at the top of the map, else below.
func _label_up(war: Dictionary, s: Dictionary) -> bool:
	var top := INF
	for x in war.systems:
		top = minf(top, float(x.pos[1]))
	return float(s.pos[1]) <= top


## Angles round a system for `n` markers (its planets, then your fleets), clear of its lanes and
## its name.
func _slots(war: Dictionary, s: Dictionary, n: int) -> Array:
	var used := [PI / 2 * (-1.0 if _label_up(war, s) else 1.0)]
	var here := _pt(s.pos)
	for id in s.lanes:
		var o := _system(war, str(id))
		if not o.is_empty():
			used.append((_pt(o.pos) - here).angle())
	var out := []
	for i in n:
		var best := 0.0
		var best_gap := -1.0
		for step in 72:
			var a := -PI + step * TAU / 72.0
			var gap := INF
			for u in used + out:
				gap = minf(gap, absf(angle_difference(a, u)))
			if gap > best_gap + 0.001:
				best_gap = gap
				best = a
		out.append(best)
	return out


func _draw_map() -> void:
	var area := _map.size
	_map.draw_rect(Rect2(Vector2.ZERO, area), Color(0.02, 0.035, 0.08, 0.95))
	# Faint stars, the same every time.
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 70:
		_map.draw_circle(Vector2(rng.randf() * area.x, rng.randf() * area.y), rng.randf_range(0.5, 1.3), Color(0.75, 0.88, 1.0, rng.randf_range(0.12, 0.4)))
	var war: Dictionary = Net.state.get("war", {})
	if war.get("systems", []).is_empty():
		return
	_layout(war.systems)
	var font := _map.get_theme_default_font()
	var factions: Dictionary = Net.catalog.get("factions", {})
	var my_faction = ui._econ().get("faction")

	for s in war.systems:
		for id in s.lanes:
			var o := _system(war, str(id))
			if not o.is_empty() and str(id) > str(s.id):
				_map.draw_line(_pt(s.pos), _pt(o.pos), Color(0.36, 0.78, 0.78, 0.32), 2.0, true)

	var now := Net.now_ms()
	for s in war.systems:
		var p := _pt(s.pos)
		var ring: Color = ui.C_TEAL if s.get("home", false) else (ui._faction_colour(s.capitalOf) if s.capitalOf != null else Color(0.55, 0.62, 0.72))
		# Orbital control: the ring split between the factions with fleets in orbit.
		var shares: Dictionary = war.get("orbital", {}).get(s.id, {})
		var a := -PI / 2
		for f in factions:
			var share := float(shares.get(f, 0))
			if share > 0.001:
				_map.draw_arc(p, R + 4.0, a, a + TAU * share, 40, ui._faction_colour(f), 3.0, true)
				a += TAU * share
		if s.id == system_id:
			_map.draw_arc(p, R + 9.0, 0, TAU, 48, ui.C_AMBER, 2.0, true)
		_map.draw_circle(p, R, Color(0.05, 0.09, 0.17))
		_map.draw_arc(p, R, 0, TAU, 40, ring, 2.0, true)
		if s.get("home", false):
			_map.draw_circle(p, 4.0, ui.C_TEAL)
		elif s.capitalOf != null:
			_map.draw_circle(p, 4.0, ui._faction_colour(s.capitalOf))

		var planets := _planets_in(war, s.id)
		var slots := _slots(war, s, planets.size())
		for i in planets.size():
			var wp: Dictionary = planets[i]
			var dir := Vector2.from_angle(slots[i])
			var d := p + dir * RING
			_map.draw_circle(d, 6.0, Color(0.02, 0.035, 0.08))
			_map.draw_circle(d, 4.8, ui._faction_colour(wp.owner))
			if float(wp.get("lockedUntil", 0)) > now:
				_padlock(d + dir * 11.0)

		var text: String = s.name
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var up := _label_up(war, s)
		var base := p + Vector2(-tw / 2.0, -(RING + 6.0) if up else RING + 14.0)
		_map.draw_rect(Rect2(base + Vector2(-4, -13), Vector2(tw + 8, 17)), Color(0.02, 0.035, 0.08, 0.8))
		var name_col := Color(1, 1, 1, 0.95) if s.id == system_id else Color(0.82, 0.9, 0.96, 0.9)
		if my_faction != null and s.capitalOf == my_faction:
			name_col = ui._faction_colour(my_faction).lightened(0.25)
		_map.draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, name_col)
		# Your fleets here: a ship marker after the name, dimmed while they're on the way or heading home.
		var mine: Array = war.get("fleets", []).filter(func(fl): return fl.owner == Net.my_name and fl.system == s.id)
		if mine:
			var at := base + Vector2(tw + 12, -5)
			var stationed: bool = mine.any(func(fl): return fl.status == "stationed")
			var col: Color = Color.WHITE if stationed else Color(1, 1, 1, 0.55)
			_ship_mark(at, col)
			if mine.size() > 1:
				_map.draw_string(font, at + Vector2(7, 5), str(mine.size()), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
		# Coma armadas here or on their way: a diamond in Coma's colour before the name.
		var armadas: Array = war.get("fleets", []).filter(func(fl): return _is_armada(fl) and fl.system == s.id and fl.status != "returning")
		if armadas:
			var at := base + Vector2(-12, -5)
			var col: Color = ui._faction_colour("coma").lightened(0.2)
			if not armadas.any(func(fl): return fl.status == "stationed"):
				col.a = 0.55
			_armada_mark(at, col)
			if armadas.size() > 1:
				_map.draw_string(font, at + Vector2(-16, 5), str(armadas.size()), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
	# A key for the markers in the bottom right corner, and the hint bottom left.
	var key_y := area.y - 8.0
	var key_x := area.x - 8.0 - font.get_string_size("Coma armada", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	if war.get("fleets", []).any(func(fl): return _is_armada(fl) and fl.status != "returning"):
		_armada_mark(Vector2(key_x - 10, key_y - 4), ui._faction_colour("coma").lightened(0.2))
		_map.draw_string(font, Vector2(key_x, key_y), "Coma armada", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.88, 0.95, 0.85))
		key_y -= 17.0
	if war.get("fleets", []).any(func(fl): return fl.owner == Net.my_name):
		_ship_mark(Vector2(key_x - 10, key_y - 4), Color.WHITE)
		_map.draw_string(font, Vector2(key_x, key_y), "Your fleets", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.88, 0.95, 0.85))
	_map.draw_string(font, Vector2(8, area.y - 8), "Tap a system", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.8, 0.9, 0.6))


## A fleet marker: a small ship pointing up.
func _ship_mark(at: Vector2, col: Color) -> void:
	_map.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -6), at + Vector2(5, 5), at + Vector2(-5, 5)]), col)


## A Coma armada's marker: a small diamond.
func _armada_mark(at: Vector2, col: Color) -> void:
	_map.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -6), at + Vector2(5, 0), at + Vector2(0, 6), at + Vector2(-5, 0)]), col)


## A small padlock: the planet is locked after changing hands.
func _padlock(c: Vector2) -> void:
	var col := Color(1.0, 0.85, 0.5)
	_map.draw_arc(c + Vector2(0, -1.5), 2.6, PI, TAU, 10, col, 1.6, true)
	_map.draw_rect(Rect2(c + Vector2(-4, -1.5), Vector2(8, 6)), col)


func _on_map_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var war: Dictionary = Net.state.get("war", {})
	var best := ""
	var best_d := R + 26.0
	for s in war.get("systems", []):
		var d := _pt(s.pos).distance_to(event.position)
		if d < best_d:
			best_d = d
			best = s.id
	if best != "":
		system_id = best
		if _tab == "supply":
			show_tab("map")
		else:
			_key = ""
			refresh(Net.state)


# --- The picked system --------------------------------------------------------------------

func _detail_key(state: Dictionary, war: Dictionary) -> Array:
	var planets := _planets_in(war, system_id).map(func(p): return [p.owner, p.lockedUntil, p.contenders, p.sectors.map(func(s): return s.owner)])
	var fleets: Array = war.get("fleets", []).filter(func(fl): return fl.system == system_id).map(func(fl): return [fl.id, fl.owner, fl.status, fl.ships])
	var e: Dictionary = ui._econ()
	var entries: Array = war.get("log", [])
	return ["map", system_id, e.get("faction"), e.get("navy", {}), planets, fleets, war.get("battleAt", {}).has(system_id), entries[-1].at if entries else 0]


## Lane jumps from system `from` to `to` (fleets pass through capital systems but never stop
## there), or -1 when no lane leads there.
func _jumps(war: Dictionary, from: String, to: String) -> int:
	var dist := {from: 0}
	var queue := [from]
	while queue:
		var at: String = queue.pop_front()
		if at == to:
			return dist[at]
		for id in _system(war, at).get("lanes", []):
			if not dist.has(str(id)):
				dist[str(id)] = dist[at] + 1
				queue.append(str(id))
	return -1


## Seconds a fleet whose slowest ship has `speed` takes from `from` to `to`: a jump a lane, and a
## quarter of a jump within the system it starts in (war.js).
func _flight_secs(war: Dictionary, from: String, to: String, speed: float) -> float:
	var jumps := _jumps(war, from, to)
	return TRAVEL_S / maxf(speed, 0.01) * (HOME_JUMPS if jumps == 0 else float(jumps))


## The systems fleets can be sent to: every one that isn't a faction's capital.
func _contested_systems(war: Dictionary) -> Array:
	return war.get("systems", []).filter(func(x): return x.capitalOf == null)


## A Coma armada: one of the AI director's fleets (or one an admin sent), with no Builder behind it.
func _is_armada(fl: Dictionary) -> bool:
	return fl.get("ai", false) or (fl.get("owner") == null and fl.get("faction") == "coma")


## "Coma armada", or "Bob (Ashen)".
func _fleet_name(fl: Dictionary) -> String:
	return "Coma armada" if _is_armada(fl) else "%s (%s)" % [fl.owner, str(fl.faction).capitalize()]


func _build_detail(state: Dictionary, war: Dictionary) -> void:
	_clear(_detail)
	var s := _system(war, system_id)
	if s.is_empty():
		_note(_detail, "The war hasn't reached this galaxy yet.")
		return
	var now := Net.now_ms()
	var title: Label = ui._label(_detail, 22)
	title.text = s.name
	var about := ""
	if s.get("home", false):
		about = "The Builders' home system. Every outpost stands on one of its contested planets."
	elif s.capitalOf != null:
		about = "Capital of the %s. Its worlds are never attacked." % ui._faction_name(s.capitalOf)
	else:
		about = "A contested system beyond the capitals."
	_note(_detail, about)
	if war.get("battleAt", {}).has(system_id):
		var battle := _note(_detail, "")
		battle.modulate = Color(1, 0.6, 0.55)
		_ticks.append(func():
			var at := float(Net.state.get("war", {}).get("battleAt", {}).get(system_id, 0))
			battle.text = "Battle: fleets of rival factions are in orbit. Next round in %s, then every %d minutes." % [
				ui._clock_text(maxf(0.0, (at - Net.now_ms()) / 1000.0)), int(Net.catalog.get("war", {}).get("battleMs", 120000)) / 60000])

	_section(_detail, "Planets")
	for wp in _planets_in(war, system_id):
		_planet_row(wp)

	var need := roundi(float(Net.catalog.get("war", {}).get("carrierShare", 0.25)) * 100)
	_section(_detail, "Orbital control")
	if s.capitalOf != null:
		_note(_detail, "Nobody fights over a capital's orbit.")
	else:
		_note(_detail, "Fleets in orbit win it. A faction needs %d%% before its carriers can attack the planets here; only holding the planets secures a system." % need)
		_orbit = Control.new()
		_orbit.custom_minimum_size = Vector2(0, 4 * 24 + 20)
		_orbit.draw.connect(_draw_orbit)
		_detail.add_child(_orbit)
	var others := []
	for fl in war.get("fleets", []):
		if fl.system == system_id and fl.owner != Net.my_name and fl.status != "returning":
			others.append("%s: %s%s" % [_fleet_name(fl), _ships_text(fl.ships), "" if fl.status == "stationed" else ", on the way"])
	if others:
		_note(_detail, "Other fleets: " + "; ".join(others))

	_section(_detail, "Your fleets here")
	var mine: Array = war.get("fleets", []).filter(func(fl): return fl.owner == Net.my_name and fl.system == system_id)
	if mine.is_empty():
		_note(_detail, "None.")
	for fl in mine:
		_fleet_row(fl)

	_section(_detail, "Send a fleet")
	if _send_for != system_id:
		_send_for = system_id
		_send_to = system_id if s.capitalOf == null else str(state.system.id)
	if ui._econ().get("faction") == null:
		_note(_detail, "Choose a faction first.")
	else:
		if s.capitalOf != null:
			_note(_detail, "Capital systems can't be contested: %s belongs to the %s for good. Fleets can go to any other system." % [s.name, ui._faction_name(s.capitalOf)])
		_build_send(state, war)

	var names := [s.name] + _planets_in(war, system_id).map(func(p): return p.name)
	var lines := []
	var entries: Array = war.get("log", [])
	for i in range(entries.size() - 1, -1, -1):
		if names.any(func(n): return str(entries[i].text).contains(n)):
			lines.append(str(entries[i].text))
		if lines.size() >= 5:
			break
	if lines:
		_section(_detail, "Latest")
		_note(_detail, "\n".join(lines))


func _planet_row(wp: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_detail.add_child(row)
	var dot: Label = ui._label(row, 18)
	dot.text = "●"
	dot.modulate = ui._faction_colour(wp.owner)
	var title: Label = ui._label(row, 17)
	title.text = wp.name
	var owner: Label = ui._label(row, 15)
	owner.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	owner.text = ui._faction_name(wp.owner) if wp.owner != null else "No owner"
	owner.modulate = ui._faction_colour(wp.owner).lightened(0.2)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gap)
	var heat: Label = ui._label(row, 15)
	heat.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if wp.get("capital", false):
		heat.text = "Capital world"
		heat.modulate = Color(0.7, 0.78, 0.86)
	else:
		var c: Array = CONTENTION[clampi(wp.get("contenders", []).size() - 1, 0, 2)]
		heat.text = c[0]
		heat.modulate = c[1]

	var held := {}
	for sec in wp.sectors:
		var k := str(sec.owner) if sec.owner != null else ""
		held[k] = held.get(k, 0) + 1
	var parts := []
	for f in Net.catalog.get("factions", {}):
		if held.has(f):
			parts.append("%s %d" % [f.capitalize(), held[f]])
	if held.has(""):
		parts.append("unheld %d" % held[""])
	var capital_owner = wp.sectors[0].owner if wp.sectors else null
	var line := _note(_detail, "")
	line.modulate = Color(0.78, 0.86, 0.93)
	var sectors_text := "%d sectors: %s. Capital sector: %s." % [wp.sectors.size(), ", ".join(parts), str(capital_owner).capitalize() if capital_owner != null else "unheld"]
	var id: String = wp.id
	_ticks.append(func():
		var left := float(_planet_now(id).get("lockedUntil", 0)) - Net.now_ms()
		line.text = sectors_text + ("  Locked for %s." % _span(left) if left > 0 else ""))


func _planet_now(id: String) -> Dictionary:
	for p in Net.state.get("war", {}).get("planets", []):
		if p.id == id:
			return p
	return {}


func _draw_orbit() -> void:
	var c := _orbit
	var font := c.get_theme_default_font()
	var shares: Dictionary = Net.state.get("war", {}).get("orbital", {}).get(system_id, {})
	var need := float(Net.catalog.get("war", {}).get("carrierShare", 0.25))
	var x0 := 92.0
	var w := maxf(40.0, c.size.x - x0 - 50.0)
	var y := 18.0
	for f in Net.catalog.get("factions", {}):
		var col: Color = ui._faction_colour(f)
		var share := float(shares.get(f, 0))
		c.draw_string(font, Vector2(0, y + 14), f.capitalize(), HORIZONTAL_ALIGNMENT_LEFT, x0 - 8, 15, col.lightened(0.2))
		c.draw_rect(Rect2(x0, y + 2, w, 15), Color(1, 1, 1, 0.08))
		if share > 0:
			c.draw_rect(Rect2(x0, y + 2, w * share, 15), col)
		c.draw_string(font, Vector2(x0 + w + 8, y + 14), "%d%%" % floori(share * 100.0 + 0.000001), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.9))
		y += 24
	# The share a faction needs before its carriers can attack here.
	var lx := x0 + w * need
	c.draw_dashed_line(Vector2(lx, 14), Vector2(lx, y), ui.C_AMBER, 2.0, 4.0)
	c.draw_string(font, Vector2(lx - 14, 11), "%d%%" % roundi(need * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ui.C_AMBER)


func _fleet_row(fl: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_detail.add_child(row)
	var text: Label = ui._label(row, 15)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var recall := Button.new()
	recall.text = "Recall"
	recall.icon = load(ui.ICONS + "waypoint.png")
	recall.disabled = fl.status == "returning"
	var id := int(fl.id)
	recall.pressed.connect(func(): Net.send({"type": "recall_fleet", "fleet": id}))
	row.add_child(recall)
	var ships := _ships_text(fl.ships)
	var upkeep: Dictionary = Net.catalog.get("war", {}).get("upkeep", {})
	var cells := 0
	for s in fl.ships:
		cells += int(upkeep.get(s, 0)) * int(fl.ships[s])
	_ticks.append(func():
		var f := _fleet_now(id)
		if f.is_empty():
			return
		var now := Net.now_ms()
		var status := ""
		match str(f.status):
			"flying":
				status = "On the way: arrives in %s" % ui._clock_text(maxf(0.0, (float(f.arriveAt) - now) / 1000.0))
			"stationed":
				status = "In orbit. Next supplies (%s) in %s" % [_cells(cells), ui._clock_text(maxf(0.0, (float(f.upkeepAt) - now) / 1000.0))]
				if f.get("joining", false):
					status += "\nNo say in orbital control until it has fought a round here."
			"returning":
				status = "Coming home: back in %s" % ui._clock_text(maxf(0.0, (float(f.returnAt) - now) / 1000.0))
		text.text = "%s\n%s" % [ships, status])


func _fleet_now(id: int) -> Dictionary:
	for f in Net.state.get("war", {}).get("fleets", []):
		if int(f.id) == id:
			return f
	return {}


## "3 Corvettes, 1 Frigate"
func _ships_text(ships: Dictionary) -> String:
	var defs: Dictionary = Net.catalog.get("ships", {})
	var parts := []
	for id in ships:
		var n := int(ships[id])
		if n > 0:
			parts.append("%d %s%s" % [n, defs.get(id, {}).get("name", id), "" if n == 1 else "s"])
	return ", ".join(parts) if parts else "no ships"


## Ship counts to send from the hangar (all of them to start with), where to (every system that
## isn't a capital, with its flight time), and Send.
func _build_send(state: Dictionary, war: Dictionary) -> void:
	var ships: Dictionary = Net.catalog.get("ships", {})
	var navy: Dictionary = ui._econ().get("navy", {})
	var total := 0
	for id in ships:
		total += int(navy.get(id, 0))
	if total == 0:
		_note(_detail, "Your hangar is empty. Build warships at a Ship Foundry (the Shipyard).")
		return
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	_detail.add_child(grid)
	for id in ships:
		var ship_id: String = id
		var have := int(navy.get(id, 0))
		_send[id] = clampi(int(_send.get(id, have)), 0, have)
		var label: Label = ui._label(grid, 15)
		label.text = "%ss (%d in the hangar)" % [ships[id].name, have]
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		grid.add_child(row)
		var count: Label
		for step in [-1, 1]:
			var b := Button.new()
			b.text = "-" if step < 0 else "+"
			b.custom_minimum_size = Vector2(44, 40)
			b.disabled = have == 0
			b.pressed.connect(func():
				_send[ship_id] = clampi(int(_send[ship_id]) + step, 0, have)
				refresh(Net.state))
			row.add_child(b)
			if step < 0:
				count = ui._label(row, 17)
				count.custom_minimum_size = Vector2(40, 0)
				count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_ticks.append(func(): count.text = str(_send.get(ship_id, 0)))

	# The slowest ship picked sets the pace.
	var slowest := func() -> float:
		var speed := INF
		for id in _send:
			if int(_send[id]) > 0:
				speed = minf(speed, float(ships[id].speed))
		return speed
	var home := str(state.system.id)
	var where := HBoxContainer.new()
	where.add_theme_constant_override("separation", 6)
	_detail.add_child(where)
	var group := ButtonGroup.new()
	for x in _contested_systems(war):
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 14)
		b.add_theme_stylebox_override("pressed", ui._box(ui.C_TEAL.darkened(0.45), ui.C_AMBER, 12))
		b.button_pressed = x.id == _send_to
		var to: String = x.id
		var to_name: String = x.name
		b.pressed.connect(func():
			_send_to = to
			refresh(Net.state))
		where.add_child(b)
		_ticks.append(func():
			var speed: float = slowest.call()
			b.text = to_name + ("\n%s" % ui._clock_text(_flight_secs(war, home, to, speed)) if speed < INF else ""))

	var info := _note(_detail, "")
	var war_rules: Dictionary = Net.catalog.get("war", {})
	_ticks.append(func():
		var cells := 0
		for id in _send:
			cells += int(war_rules.get("upkeep", {}).get(id, 0)) * int(_send[id])
		if cells == 0:
			info.text = "Pick the ships to send."
			return
		info.text = "Flight %s. It needs %s as it takes station and every %d minutes in orbit (you have %d; %d credits for each one short), or it comes home." % [
			ui._clock_text(_flight_secs(war, home, _send_to, slowest.call())), _cells(cells), int(war_rules.get("upkeepMs", 600000)) / 60000,
			int(ui._econ().stock.get("fuel", 0)), int(war_rules.get("fuelCredits", 20))])
	var send := Button.new()
	send.icon = load(ui.ICONS + "launch.png")
	send.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	send.pressed.connect(func(): Net.send({"type": "send_fleet", "system": _send_to, "ships": _send.duplicate()}))
	_detail.add_child(send)
	_ticks.append(func():
		send.text = "Send fleet to %s" % _system(Net.state.get("war", {}), _send_to).get("name", "")
		send.disabled = _send.values().all(func(n): return int(n) == 0))


# --- Faction supply ---------------------------------------------------------------------

func _supply_key(state: Dictionary, war: Dictionary) -> Array:
	var e: Dictionary = ui._econ()
	var stocked := []
	for id in e.get("stock", {}):
		if int(e.stock[id]) > 0:
			stocked.append(id)
	return ["supply", e.get("faction"), war.get("supply", {}).get(state.system.id, {}).get(str(e.get("faction")), {}), stocked]


func _build_supply(state: Dictionary, war: Dictionary) -> void:
	_clear(_supply)
	var e: Dictionary = ui._econ()
	var faction = e.get("faction")
	if faction == null:
		_note(_supply, "Choose a faction first.")
		return
	var merit_line: Label = ui._label(_supply, 18)
	var next_line := _note(_supply, "")
	_ticks.append(func():
		var merit := float(ui._econ().get("merit", 0))
		var rank: Dictionary = ui._rank_of(merit)
		merit_line.text = "War Merit %d: %s" % [int(merit), rank.get("name", "")]
		var bonus := roundi(float(rank.get("bonus", 0)) * 100)
		var next: Dictionary = {}
		for r in Net.catalog.get("ranks", []):
			if float(r.from) > merit:
				next = r
				break
		next_line.text = ("Your outposts make %d%% more. " % bonus if bonus > 0 else "") + \
			("Next: %s at %d merit (%d to go, outposts +%d%%)." % [next.name, int(next.from), int(float(next.from) - merit), roundi(float(next.bonus) * 100)] if not next.is_empty() else "The top rank."))

	_section(_supply, "%s supply in %s" % [ui._faction_name(faction), state.system.name])
	var pile: Dictionary = war.get("supply", {}).get(state.system.id, {}).get(str(faction), {})
	var parts := []
	for id in pile:
		if int(pile[id]) > 0:
			parts.append(ui._amount_of(id, int(pile[id])))
	_note(_supply, ", ".join(parts) if parts else "Nothing yet.")
	_note(_supply, "Your faction's sector battles draw on this supply.").modulate = Color(0.7, 0.8, 0.88)

	_section(_supply, "Donate from your stock")
	var values: Dictionary = Net.catalog.get("meritValue", {})
	var stocked := []
	for id in e.stock:
		if int(e.stock[id]) > 0 and values.has(id):
			stocked.append(id)
	if stocked.is_empty():
		_note(_supply, "Nothing in stock to give.")
		return
	if _donate_item not in stocked:
		_donate_item = "fuel" if "fuel" in stocked else stocked[0]
	var group := ButtonGroup.new()
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	_supply.add_child(grid)
	for id in stocked:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 14)
		b.add_theme_stylebox_override("pressed", ui._box(ui.C_TEAL.darkened(0.45), ui.C_AMBER, 12))
		b.button_pressed = id == _donate_item
		var item: String = id
		b.pressed.connect(func():
			_donate_item = item
			refresh(Net.state))
		grid.add_child(b)
		_ticks.append(func(): b.text = "%s: %d  (%d merit each)" % [_item_name(item), int(ui._econ().stock.get(item, 0)), int(values.get(item, 0))])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_supply.add_child(row)
	var amount: Label = ui._label(row, 15)
	amount.text = "Amount"
	amount.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var edit: LineEdit = ui._qty_picker(row, _donate_qty, func(): return int(ui._econ().stock.get(_donate_item, 0)), func(n): _donate_qty = n)
	var give := Button.new()
	give.icon = load(ui.ICONS + "send.png")
	give.pressed.connect(func(): Net.send({"type": "donate", "item": _donate_item, "qty": ui._qty(edit)}))
	row.add_child(give)
	_ticks.append(func():
		var n: int = ui._qty(edit)
		give.text = "Donate: +%d merit" % (n * int(values.get(_donate_item, 0)))
		give.disabled = n < 1 or n > int(ui._econ().stock.get(_donate_item, 0)))


# --- The Coma director (admins only) ---------------------------------------------------------

## The player factions the director weighs up: every faction a player can choose.
func _player_factions() -> Array:
	var factions: Dictionary = Net.catalog.get("factions", {})
	return factions.keys().filter(func(f): return factions[f].get("playable", true))


## A fleet's fighting power, as war.js counts it: each ship's attack plus a fifth of its hull.
func _power(ships: Dictionary) -> float:
	var defs: Dictionary = Net.catalog.get("ships", {})
	var p := 0.0
	for id in ships:
		if defs.has(id):
			p += int(ships[id]) * (float(defs[id].attack) + float(defs[id].hull) / 5.0)
	return p


func _director_key(state: Dictionary, war: Dictionary) -> Array:
	var d: Dictionary = state.get("director", {})
	var armadas: Array = war.get("fleets", []).filter(func(fl): return _is_armada(fl) and fl.system == system_id).map(func(fl): return [fl.id, fl.status, fl.ships])
	var planets := _planets_in(war, system_id).map(func(p): return [p.owner, p.lockedUntil, p.contenders, p.sectors.map(func(x): return x.owner)])
	var need := float(Net.catalog.get("war", {}).get("carrierShare", 0.25))
	var orbit_ok := float(war.get("orbital", {}).get(system_id, {}).get("coma", 0)) >= need
	return ["director", system_id, d.is_empty(), d.get("paused"), d.get("scale"), d.get("overrides"), d.get("posture"), armadas, planets, orbit_ok]


## The director's controls: pause and the master scale; per player faction its strength, the
## automatic intensity, the one in use and an override; then for the picked system its posture,
## Coma's armada power against the strongest player faction's, its armadas with Recall, Send
## armada, and the sectors Coma can take there.
func _build_director(state: Dictionary, war: Dictionary) -> void:
	_clear(_director)
	var d: Dictionary = state.get("director", {})
	if d.is_empty():
		_note(_director, "The director hasn't reported yet. It shows here once the server sends it.")
		return
	var title: Label = ui._label(_director, 22)
	title.text = "Coma director"
	_note(_director, "The Coma Conglomerate's AI. It sends armadas to win orbits, pushing hardest on the strongest player faction. Players see the armadas, never these settings.")
	# Game Master: faction orders by hand (server admin_order), in place of the ones running.
	var orders := HBoxContainer.new()
	orders.add_theme_constant_override("separation", 6)
	_director.add_child(orders)
	var ol: Label = ui._label(orders, 15)
	ol.text = "Orders:"
	for f in ["compact", "ashen", "luminar", "all"]:
		var b := Button.new()
		b.text = "Coma offensive (all)" if f == "all" else "New %s order" % ui._faction_name(f).get_slice(" ", 1 if f == "compact" else 0)
		b.tooltip_text = "Issue a fresh order in place of the one running" if f != "all" else "One order for all three factions: beat the Coma"
		var fid: String = f
		b.pressed.connect(func(): Net.send({"type": "admin_order", "faction": fid}))
		orders.add_child(b)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	_director.add_child(top)
	var pause := CheckButton.new()
	pause.text = "Paused"
	pause.button_pressed = bool(d.get("paused", false))
	pause.toggled.connect(func(on): Net.send({"type": "director_set", "paused": on}))
	top.add_child(pause)
	var run: Label = ui._label(top, 14)
	run.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	run.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	run.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	run.modulate = Color(0.78, 0.86, 0.93)
	_ticks.append(func():
		var now_d: Dictionary = Net.state.get("director", {})
		if now_d.get("paused", false):
			run.text = "Paused: it sends and recalls nothing until you start it again."
		else:
			run.text = "Next run in %s" % ui._clock_text(maxf(0.0, (float(now_d.get("runAt", 0)) - Net.now_ms()) / 1000.0)))

	var scale_row := HBoxContainer.new()
	scale_row.add_theme_constant_override("separation", 10)
	_director.add_child(scale_row)
	var scale_name: Label = ui._label(scale_row, 15)
	scale_name.text = "Master scale"
	scale_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var scale_max := float(Net.catalog.get("director", {}).get("scaleMax", 2))
	var scale_value: Label = ui._label(scale_row, 15)
	scale_value.custom_minimum_size = Vector2(54, 0)
	scale_value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	scale_value.text = "x%.2f" % float(d.get("scale", 1))
	_slider(scale_row, 0.0, scale_max, 0.05, float(d.get("scale", 1)),
		func(v): Net.send({"type": "director_set", "scale": snappedf(v, 0.01)}),
		func(v): scale_value.text = "x%.2f" % v)
	scale_row.move_child(scale_value, -1)
	_note(_director, "0 sends nothing and calls the armadas home, 1 is normal, %s is twice as hard." % str(scale_max).trim_suffix(".0")).modulate = Color(0.7, 0.8, 0.88)

	_section(_director, "Player factions")
	_note(_director, "Strength mixes sectors held, orbital control and active players. Automatic intensity gives the strongest faction 100% and eases off the rest; set a fixed level to override it.").modulate = Color(0.7, 0.8, 0.88)
	var overrides: Dictionary = d.get("overrides", {})
	for f in _player_factions():
		_faction_dial(f, overrides.get(f))

	_section(_director, "Systems")
	var pick := HBoxContainer.new()
	pick.add_theme_constant_override("separation", 6)
	_director.add_child(pick)
	var group := ButtonGroup.new()
	for x in _contested_systems(war):
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 14)
		b.add_theme_stylebox_override("pressed", ui._box(ui.C_TEAL.darkened(0.45), ui.C_AMBER, 12))
		b.button_pressed = x.id == system_id
		var sid: String = x.id
		b.text = "%s\n%s" % [x.name, _posture_name(str(d.get("posture", {}).get(sid, "push")))]
		b.pressed.connect(func():
			system_id = sid
			_key = ""
			refresh(Net.state))
		pick.add_child(b)
	var s := _system(war, system_id)
	if s.capitalOf != null:
		_note(_director, "%s is the %s's capital: nobody fights there. Pick a system above or on the map." % [s.name, ui._faction_name(s.capitalOf)])
		return
	_build_director_system(d, war, s)


## One player faction's row: strength, automatic intensity and the one in use, then Auto or a
## fixed level.
func _faction_dial(f: String, fixed) -> void:
	var line: Label = ui._label(_director, 15)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ticks.append(func():
		var now_d: Dictionary = Net.state.get("director", {})
		line.text = "%s: strength %d%%, automatic %d%%, in use %d%%" % [ui._faction_name(f),
			roundi(float(now_d.get("strength", {}).get(f, 0)) * 100), roundi(float(now_d.get("auto", {}).get(f, 0)) * 100),
			roundi(float(now_d.get("intensity", {}).get(f, 0)) * 100)])
	line.modulate = ui._faction_colour(f).lightened(0.3)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_director.add_child(row)
	var auto := Button.new()
	auto.text = "Auto"
	auto.toggle_mode = true
	auto.button_pressed = fixed == null
	auto.custom_minimum_size = Vector2(76, 0)
	auto.add_theme_stylebox_override("pressed", ui._box(ui.C_TEAL.darkened(0.45), ui.C_AMBER, 12))
	auto.pressed.connect(func():
		if fixed == null:
			auto.set_pressed_no_signal(true) # already automatic
		else:
			Net.send({"type": "director_set", "overrides": {f: null}}))
	row.add_child(auto)
	var start := float(fixed) if fixed != null else float(Net.state.get("director", {}).get("auto", {}).get(f, 0))
	var level: Label = ui._label(row, 15)
	level.custom_minimum_size = Vector2(54, 0)
	level.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	level.text = ("%d%%" % roundi(start * 100)) if fixed != null else "auto"
	var dial := _slider(row, 0.0, 1.0, 0.05, start,
		func(v): Net.send({"type": "director_set", "overrides": {f: snappedf(v, 0.01)}}),
		func(v): level.text = "%d%%" % roundi(v * 100))
	dial.modulate.a = 1.0 if fixed != null else 0.55 # dimmed while it only shows the automatic level
	row.move_child(level, -1)


## The picked system: posture, power, armadas, Send armada and Take for Coma.
func _build_director_system(d: Dictionary, war: Dictionary, s: Dictionary) -> void:
	var sid: String = s.id
	var posture := str(d.get("posture", {}).get(sid, "push"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_director.add_child(row)
	var name_l: Label = ui._label(row, 17)
	name_l.text = s.name
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var group := ButtonGroup.new()
	for p in POSTURES:
		var b := Button.new()
		b.text = p[1]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = p[0] == posture
		b.add_theme_stylebox_override("pressed", ui._box(ui.C_TEAL.darkened(0.45), ui.C_AMBER, 12))
		var id: String = p[0]
		b.pressed.connect(func(): Net.send({"type": "director_set", "posture": {sid: id}}))
		row.add_child(b)
	for p in POSTURES:
		if p[0] == posture:
			_note(_director, "%s: %s" % [p[1], p[2]]).modulate = Color(0.7, 0.8, 0.88)

	# Coma's armada power here against the strongest player faction's (in orbit or on the way, as
	# the director counts them), and what it aims for.
	var power := _note(_director, "")
	_ticks.append(func():
		var coma := 0.0
		var coming := 0.0
		var by := {}
		for fl in Net.state.get("war", {}).get("fleets", []):
			if fl.system != sid or fl.status == "returning":
				continue
			if fl.get("ai", false):
				coma += _power(fl.ships)
				if fl.status == "flying":
					coming += _power(fl.ships)
			elif fl.faction in _player_factions():
				by[fl.faction] = by.get(fl.faction, 0.0) + _power(fl.ships)
		var best := ""
		for f in by:
			if best == "" or by[f] > by[best]:
				best = f
		var now_d: Dictionary = Net.state.get("director", {})
		var text := "Coma armadas: power %d%s. Strongest player faction: %s." % [roundi(coma),
			" (%d on the way)" % roundi(coming) if coming > 0 else "",
			"the %s, power %d" % [ui._faction_name(best), roundi(by[best])] if best != "" else "none here"]
		if str(now_d.get("posture", {}).get(sid, "push")) == "push":
			text += " The director aims for power %d." % roundi(_target(now_d, by))
		power.text = text)

	var armadas: Array = war.get("fleets", []).filter(func(fl): return _is_armada(fl) and fl.system == sid)
	if armadas.is_empty():
		_note(_director, "No armadas here.")
	for fl in armadas:
		_armada_row(fl)

	# Send armada: a power to send from Comae.
	var send_row := HBoxContainer.new()
	send_row.add_theme_constant_override("separation", 10)
	_director.add_child(send_row)
	var power_l: Label = ui._label(send_row, 15)
	power_l.custom_minimum_size = Vector2(92, 0)
	power_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var send := Button.new()
	send.text = "Send armada"
	send.icon = load(ui.ICONS + "launch.png")
	send.disabled = posture == "withdraw"
	send.pressed.connect(func(): Net.send({"type": "admin_armada", "system": sid, "power": _armada_power}))
	send_row.add_child(send)
	var capital := ""
	for x in war.get("systems", []):
		if x.capitalOf == "coma":
			capital = x.id
	var from: String = _system(war, capital).get("name", "Comae")
	var what := _note(_director, "")
	what.modulate = Color(0.7, 0.8, 0.88)
	var show := func(v: float) -> void:
		power_l.text = "Power %d" % int(v)
		if posture == "withdraw":
			what.text = "The director is withdrawing from %s: set it to Push or Hold to send an armada." % s.name
			return
		var ships := _compose(v)
		var speed := INF
		for id in ships:
			speed = minf(speed, float(Net.catalog.get("ships", {})[id].speed))
		what.text = "%s, from %s in %s. The director leaves an armada you send alone unless the system withdraws." % [
			_ships_text(ships), from, ui._clock_text(_flight_secs(war, capital, sid, speed))]
	var dial := _slider(send_row, ARMADA_POWER[0], ARMADA_POWER[1], 10, _armada_power, func(_v): pass, func(v):
		_armada_power = int(v)
		show.call(v))
	send_row.move_child(dial, 0)
	show.call(float(_armada_power))

	_section(_director, "Take for Coma")
	_note(_director, "Flip a sector to Coma by hand, as if Coma had won a battle there: every rule applies. Amber border: the planet's capital sector.").modulate = Color(0.7, 0.8, 0.88)
	for wp in _planets_in(war, sid):
		_take_row(war, s, wp)


## An armada in the picked system: its ships, where it is and when, and Recall.
func _armada_row(fl: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_director.add_child(row)
	var text: Label = ui._label(row, 15)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var recall := Button.new()
	recall.text = "Recall"
	recall.icon = load(ui.ICONS + "waypoint.png")
	recall.disabled = fl.status == "returning"
	var id := int(fl.id)
	recall.pressed.connect(func(): Net.send({"type": "admin_recall", "fleet": id}))
	row.add_child(recall)
	var head := "Armada %d%s: %s, power %d" % [id, " (sent by an admin)" if fl.get("manual", false) else "", _ships_text(fl.ships), roundi(_power(fl.ships))]
	_ticks.append(func():
		var f := _fleet_now(id)
		if f.is_empty():
			return
		var now := Net.now_ms()
		var status := ""
		match str(f.status):
			"flying":
				status = "On the way: arrives in %s" % ui._clock_text(maxf(0.0, (float(f.arriveAt) - now) / 1000.0))
			"stationed":
				status = "In orbit"
			"returning":
				status = "Going home to disband: gone in %s" % ui._clock_text(maxf(0.0, (float(f.returnAt) - now) / 1000.0))
		text.text = "%s\n%s" % [head, status])


## A planet of the picked system: the sectors Coma can take there, or why it can't.
func _take_row(war: Dictionary, s: Dictionary, wp: Dictionary) -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	_director.add_child(head)
	var name_l: Label = ui._label(head, 16)
	name_l.text = wp.name
	var owner: Label = ui._label(head, 14)
	owner.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	owner.text = ui._faction_name(wp.owner) if wp.owner != null else "No owner"
	owner.modulate = ui._faction_colour(wp.owner).lightened(0.2)
	var why := _coma_block(war, s, wp)
	if why != "":
		_note(_director, why).modulate = Color(0.75, 0.8, 0.88)
		return
	var held: Array = wp.sectors.filter(func(x): return x.owner == "coma").map(func(x): return x.id)
	var open: Array = wp.sectors.filter(func(x): return x.owner != "coma" and (held.is_empty() or x.links.any(func(l): return l in held)))
	if open.is_empty():
		_note(_director, "Coma holds every sector.")
		return
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	_director.add_child(grid)
	for sec in open:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(58, 50)
		btn.add_theme_font_size_override("font_size", 13)
		btn.text = "%s\n%s" % [str(sec.name).trim_prefix(str(wp.name) + " "), str(sec.owner).capitalize() if sec.owner != null else "unheld"]
		var col: Color = ui._faction_colour(sec.owner)
		btn.add_theme_stylebox_override("normal", ui._box(col.darkened(0.7), ui.C_AMBER if sec.capital else col.darkened(0.2), 10, 4))
		var planet_id: String = wp.id
		var sector_id: String = sec.id
		btn.pressed.connect(func(): Net.send({"type": "admin_capture", "planet": planet_id, "sector": sector_id}))
		grid.add_child(btn)


## Why Coma can't take sectors on planet `wp` now, or "" (war.js canAttack, from Coma's side).
func _coma_block(war: Dictionary, s: Dictionary, wp: Dictionary) -> String:
	if wp.get("capital", false):
		return "Capital worlds can't be attacked."
	var left := float(wp.get("lockedUntil", 0)) - Net.now_ms()
	if left > 0:
		return "Locked for %s after changing hands." % _span(left)
	var need := float(Net.catalog.get("war", {}).get("carrierShare", 0.25))
	var share := float(war.get("orbital", {}).get(s.id, {}).get("coma", 0))
	if share < need:
		return "Coma needs %d%% orbital control of %s: it has %d%%." % [roundi(need * 100), s.name, floori(share * 100.0 + 0.000001)]
	if wp.owner != "coma" and not "coma" in wp.get("contenders", []):
		return "Coma has no foothold near %s." % wp.name
	return ""


## The power the director aims for in a system it pushes in, given each player faction's power
## there: the strongest faction's times its intensity and the scale, or a patrol (director.js run).
func _target(d: Dictionary, by: Dictionary) -> float:
	var intensity: Dictionary = d.get("intensity", {})
	var best := 0.0
	for f in by:
		if by[f] > 0:
			best = maxf(best, float(by[f]) * float(intensity.get(f, 0)))
	if best > 0:
		return float(d.get("scale", 1)) * best
	var mean := 0.0
	var players := _player_factions()
	for f in players:
		mean += float(intensity.get(f, 0)) / maxf(players.size(), 1)
	return float(Net.catalog.get("director", {}).get("patrolPower", 30)) * float(d.get("scale", 1)) * mean


## The ships of an armada of about `power`, as the server makes one: as many of the biggest ship as
## fit, then the next, then enough of the smallest to cover the rest (director.js compose).
func _compose(power: float) -> Dictionary:
	var defs: Dictionary = Net.catalog.get("ships", {})
	var types := defs.keys()
	types.sort_custom(func(a, b): return _power({a: 1}) > _power({b: 1}))
	var out := {}
	var left := power
	for i in types.size():
		var unit := _power({types[i]: 1})
		var n := ceili(left / unit - 1e-9) if i == types.size() - 1 else floori(left / unit + 1e-9)
		if n > 0:
			out[types[i]] = n
			left -= n * unit
	return out


func _posture_name(id: String) -> String:
	for p in POSTURES:
		if p[0] == id:
			return p[1]
	return id.capitalize()


## A slider for the director: `changed` hears every value while it moves, `done` the value once a
## finger lets go (only then is anything sent).
func _slider(parent: Node, lo: float, hi: float, step: float, value: float, done: Callable, changed: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.scrollable = false # a scroll over the panel never nudges it
	s.focus_mode = Control.FOCUS_NONE
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(120, 36)
	s.value_changed.connect(func(v): changed.call(v))
	s.drag_ended.connect(func(moved): if moved: done.call(s.value))
	parent.add_child(s)
	return s


## "1 fuel cell", "11 fuel cells"
func _cells(n: int) -> String:
	return "%d fuel cell%s" % [n, "" if n == 1 else "s"]


func _item_name(id: String) -> String:
	return id.capitalize() if id in ["metal", "ice"] else Net.item_name(id)


# --- Little helpers --------------------------------------------------------------------------

func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _section(box: Node, text: String) -> void:
	var l: Label = ui._label(box, 17)
	l.text = text
	l.modulate = Color(0.6, 0.95, 0.95)


func _note(box: Node, text: String) -> Label:
	var l: Label = ui._label(box, 14)
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## How long until `ms` from now: "6 d 23 h", "5 h 12 min" or "4:05".
func _span(ms: float) -> String:
	var s := int(ms / 1000.0)
	if s >= 86400:
		return "%d d %d h" % [s / 86400, (s % 86400) / 3600]
	if s >= 3600:
		return "%d h %d min" % [s / 3600, (s % 3600) / 60]
	return ui._clock_text(float(s))
