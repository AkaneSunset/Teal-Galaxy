class_name BattleMenu
extends Control
## The Sector Battles screen: opened from the carrier's holo table (and a station's War terminal)
## for the contested planet below. Shows the planet's sectors on a flat map and in a list, with
## their owners, which ones your faction can attack (the server's rules, war.js canAttack and
## capture, mirrored by war_info.gd), the battles running there (attacker, defender, pilots), and
## the buttons: Attack sector (battle_start) and Join battle (battle_join). Away from any planet it
## says where to fly. When the server puts the pilot in a battle (battle_joined), the RTS view
## (battle_view.gd) opens and this screen closes.

const WarInfo := preload("res://war_info.gd")

signal closed

const TEAL := Color(0.35, 0.95, 0.88)
const DIM := Color(0.7, 0.76, 0.8)
const BAD := Color(1.0, 0.5, 0.42)
const GOOD := Color(0.45, 1.0, 0.55)

var planet_id := ""
var host: Node

var _selected := ""
var _layer: CanvasLayer
var _title: Label
var _sub: Label
var _list: VBoxContainer
var _rows := {} # sector id -> Button
var _map: Control
var _detail: Label
var _attack: Button
var _join: Button
var _battles: VBoxContainer
var _status: Label
var _away: Label
var _body: Control
var _waiting := false # a battle_start or battle_join is on its way
var _pulse := 0.0


## Opens the screen over `host` for war planet `planet_id` ("" when the carrier is over no
## contested world). Returns it; it emits `closed` and frees itself when done.
static func open(host: Node, planet_id: String) -> Control:
	var layer := CanvasLayer.new()
	layer.layer = 20
	var menu := BattleMenu.new()
	menu.planet_id = planet_id
	menu.host = host
	menu._layer = layer
	layer.add_child(menu)
	host.add_child(layer)
	return menu


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = _theme()
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.02, 0.05, 0.9)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	margin.add_child(page)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	page.add_child(top)
	var heading := _label(top, "Sector Battles", 28, TEAL)
	heading.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_title = _label(top, "", 22, Color.WHITE)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close := Button.new()
	close.text = "Close (Esc)"
	close.pressed.connect(_close)
	top.add_child(close)
	_sub = _label(page, "", 15, DIM)
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_away = _label(page, "", 18, DIM)
	_away.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_away.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(row)
	_body = row

	# Left: the sectors, one row each.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(380, 0)
	row.add_child(left)
	_label(left, "Sectors", 18, TEAL)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_list)

	# Right: the sector map, the chosen sector and the battles.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	row.add_child(right)
	_map = SectorMap.new()
	_map.menu = self
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map.custom_minimum_size = Vector2(0, 260)
	right.add_child(_map)
	var detail_row := HBoxContainer.new()
	detail_row.add_theme_constant_override("separation", 16)
	right.add_child(detail_row)
	_detail = _label(detail_row, "", 15, Color(0.88, 0.92, 0.95))
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.custom_minimum_size = Vector2(0, 96)
	var buttons := VBoxContainer.new()
	buttons.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	detail_row.add_child(buttons)
	_attack = Button.new()
	_attack.text = "Attack sector"
	_attack.custom_minimum_size = Vector2(200, 40)
	_attack.pressed.connect(_start)
	buttons.add_child(_attack)
	_join = Button.new()
	_join.text = "Join battle"
	_join.custom_minimum_size = Vector2(200, 40)
	_join.pressed.connect(func(): _join_battle(_battle_on(_selected)))
	buttons.add_child(_join)
	_label(right, "Battles on this planet", 18, TEAL)
	_battles = VBoxContainer.new()
	_battles.add_theme_constant_override("separation", 4)
	right.add_child(_battles)
	_status = _label(page, "", 16, DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	Net.message.connect(_on_message)
	Net.state_changed.connect(_on_state)
	var wp := WarInfo.planet(planet_id)
	if not wp.is_empty():
		_selected = _first_target(wp)
	refresh()


func _exit_tree() -> void:
	if Net.message.is_connected(_on_message):
		Net.message.disconnect(_on_message)
	if Net.state_changed.is_connected(_on_state):
		Net.state_changed.disconnect(_on_state)


func _process(delta: float) -> void:
	_pulse += delta
	_map.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE):
		_close()
		get_viewport().set_input_as_handled()


func _close() -> void:
	if is_queued_for_deletion():
		return
	closed.emit()
	if _layer:
		_layer.queue_free()
	else:
		queue_free()


func _on_state(_s: Dictionary) -> void:
	refresh()


func _on_message(msg: Dictionary) -> void:
	match str(msg.get("type", "")):
		"battle_joined":
			# Into the battle: the RTS view takes over the screen (BattleView.active), then we go.
			_waiting = false
			BattleView.open(host if host and host.is_inside_tree() else self, msg)
			_close()
		"error":
			if _waiting or is_visible_in_tree():
				_waiting = false
				var r := str(msg.get("reason", ""))
				_status.text = r.substr(0, 1).to_upper() + r.substr(1) if r != "" else ""
				_status.add_theme_color_override("font_color", BAD)
				refresh()


# --- What the screen shows -------------------------------------------------------------------

func refresh() -> void:
	if not is_node_ready():
		return
	var wp := WarInfo.planet(planet_id)
	var mine := WarInfo.my_faction()
	_body.visible = not wp.is_empty()
	_away.visible = wp.is_empty()
	if wp.is_empty():
		_title.text = "No contested world below"
		_sub.text = "Your side: %s" % WarInfo.faction_name(mine) if mine != "" else "You haven't picked a side yet"
		_away.text = "Sector battles are fought from orbit. Fly your carrier to a contested planet's orbit (within 30 km of its orbital station) and the holo table will show its sectors.\n\n" + _battles_elsewhere()
		return
	var sys := WarInfo.system(wp.system)
	_title.text = "%s · %s" % [wp.name, sys.get("name", wp.system)]
	var bits := ["held by %s" % WarInfo.the(wp.owner) if wp.owner != null else "nobody holds it", WarInfo.contention(wp)]
	if mine != "":
		bits.append("%s holds %d of %d sectors here, %d%% of the orbit" % [WarInfo.faction_name(mine), WarInfo.held(wp, mine), wp.sectors.size(), floori(WarInfo.orbital(wp.system, mine) * 100.0 + 1e-9)])
	var lock := WarInfo.lock_left(wp)
	if lock != "":
		bits.append("locked for " + lock)
	var line := ", ".join(bits)
	_sub.text = line.substr(0, 1).to_upper() + line.substr(1) + ("  ·  demo war: every faction has 25% of the orbit" if Net.catalog.get("demo", false) else "")
	_refresh_list(wp)
	_refresh_detail(wp)
	_refresh_battles(wp)


func _refresh_list(wp: Dictionary) -> void:
	if _rows.is_empty() or _rows.size() != wp.sectors.size():
		for c in _list.get_children():
			c.queue_free()
		_rows.clear()
		for sec in wp.sectors:
			var b := Button.new()
			b.toggle_mode = true
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.custom_minimum_size = Vector2(0, 32)
			b.pressed.connect(select_sector.bind(sec.id))
			_list.add_child(b)
			_rows[sec.id] = b
	var mine := WarInfo.my_faction()
	for sec in wp.sectors:
		var b: Button = _rows[sec.id]
		var status := ""
		var battle := _battle_on(sec.id)
		if not battle.is_empty():
			var n: int = battle.get("pilots", []).size()
			status = "battle on: %s" % ("no pilots in it" if n == 0 else "%d pilot%s" % [n, "" if n == 1 else "s"])
		elif mine != "" and sec.owner == mine:
			status = "yours"
		elif problem(mine, wp, sec) == "":
			status = "can attack"
		b.text = "  %s%s   %s%s" % [sec.name, " (capital)" if sec.get("capital", false) else "", WarInfo.faction_name(sec.owner), "   · " + status if status != "" else ""]
		var c := WarInfo.faction_color(sec.owner)
		b.add_theme_color_override("font_color", c)
		b.add_theme_color_override("font_hover_color", c.lightened(0.25))
		b.add_theme_color_override("font_pressed_color", c.lightened(0.4))
		b.button_pressed = sec.id == _selected


func _refresh_detail(wp: Dictionary) -> void:
	var sec := WarInfo.sector(wp, _selected)
	_attack.visible = false
	_join.visible = false
	if sec.is_empty():
		_detail.text = "Pick a sector on the map or in the list."
		return
	var mine := WarInfo.my_faction()
	var lines := ["%s: %s%s" % [sec.name, "held by " + WarInfo.the(sec.owner) if sec.owner != null else "unclaimed (a militia defends it)", ", the capital sector" if sec.get("capital", false) else ""]]
	var near := []
	for id in sec.get("links", []):
		near.append(WarInfo.sector(wp, id).get("name", id))
	lines.append("Next to " + ", ".join(near))
	var here := []
	for site in WarInfo.outposts_on(wp.id):
		if site.get("sector", "") == sec.id:
			here.append("%s (%s)" % [WarInfo.short_site_name(site), site.get("owner", "")])
	if not here.is_empty():
		lines.append("Outposts (objectives): " + ", ".join(here))
	var battle := _battle_on(sec.id)
	if not battle.is_empty():
		lines.append(_battle_line(battle))
		var side := _side_in(battle, mine)
		_join.visible = true
		_join.disabled = side == "" or _waiting
		if side == "":
			lines.append("Only %s and %s fight in it." % [WarInfo.the(battle.get("attacker")), _defender_name(battle.get("defender"))])
	else:
		var why := problem(mine, wp, sec)
		_attack.visible = true
		_attack.disabled = why != "" or _waiting
		if why != "" and not (mine != "" and sec.owner == mine):
			lines.append("Can't attack it: " + why)
		elif why == "":
			lines.append("Your carrier can drop units here. Destroy the defenders' Command Node to take the sector.")
	_detail.text = "\n".join(lines)


func _refresh_battles(wp: Dictionary) -> void:
	for c in _battles.get_children():
		c.queue_free()
	var mine := WarInfo.my_faction()
	var any := false
	for b in Net.state.get("battles", []):
		if str(b.get("planet", "")) != wp.id:
			continue
		any = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		_battles.add_child(row)
		var l := _label(row, _battle_line(b), 15, Color(0.9, 0.93, 0.95))
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var j := Button.new()
		j.text = "Join battle"
		j.disabled = _side_in(b, mine) == "" or _waiting
		j.pressed.connect(_join_battle.bind(b))
		row.add_child(j)
	if not any:
		_label(_battles, "None right now.", 15, DIM)


func _battle_line(b: Dictionary) -> String:
	var a := []
	var d := []
	for p in b.get("pilots", []):
		(a if str(p.get("side", "")) == "a" else d).append(str(p.name))
	var left := maxf(0.0, (float(b.get("endsAt", 0)) - Net.now_ms()) / 60000.0)
	return "%s: %s attacking %s · %s · %d min left" % [str(b.get("sectorName", b.get("sector", ""))), WarInfo.faction_name(b.get("attacker")),
		_defender_name(b.get("defender")), "pilots: " + ", ".join(a + d) if not (a + d).is_empty() else "no pilots", ceili(left)]


func _defender_name(f) -> String:
	return WarInfo.faction_name(f) if f != null and str(f) != "" else "the militia"


func _battles_elsewhere() -> String:
	var lines := []
	for b in Net.state.get("battles", []):
		var wp := WarInfo.planet(str(b.get("planet", "")))
		lines.append("  %s, %s" % [wp.get("name", b.get("planet", "")), _battle_line(b)])
	if lines.is_empty():
		return "No sector battles are being fought anywhere right now."
	return "Battles being fought now:\n" + "\n".join(lines)


func select_sector(id: String) -> void:
	_selected = id
	_status.text = ""
	refresh()


# --- The rules ---------------------------------------------------------------------------------

## Why `faction` can't attack a sector now, or "" when it can: war_info.gd's take_problem, except
## that the demo war (the catalog's `demo`) waives the foothold rule as the server does.
static func problem(faction: String, wp: Dictionary, sec: Dictionary) -> String:
	var why := WarInfo.take_problem(faction, wp, sec)
	if not why.contains("no foothold") or not Net.catalog.get("demo", false):
		return why
	var share := WarInfo.orbital(wp.system, faction)
	if share + 1e-9 < WarInfo.carrier_share():
		return "you need %d%% orbital control of %s: you have %d%%" % [roundi(WarInfo.carrier_share() * 100.0), WarInfo.system(wp.system).get("name", wp.system), floori(share * 100.0 + 1e-9)]
	if sec.owner == faction:
		return "%s already holds %s" % [WarInfo.the(faction), sec.name]
	if WarInfo.held(wp, faction) > 0:
		for id in sec.get("links", []):
			if WarInfo.sector(wp, id).get("owner") == faction:
				return ""
		return "%s isn't next to a sector you hold" % sec.name
	return ""


## A good sector to show first: one you can attack (next to your ground), else the capital.
func _first_target(wp: Dictionary) -> String:
	var mine := WarInfo.my_faction()
	for sec in wp.sectors:
		if not _battle_on(sec.id).is_empty() and _side_in(_battle_on(sec.id), mine) != "":
			return sec.id
	for sec in wp.sectors:
		if problem(mine, wp, sec) == "":
			return sec.id
	return wp.sectors[0].id if not wp.sectors.is_empty() else ""


func _battle_on(sector_id: String) -> Dictionary:
	for b in Net.state.get("battles", []):
		if str(b.get("planet", "")) == planet_id and str(b.get("sector", "")) == sector_id:
			return b
	return {}


## "a" or "d" if `faction` fights in that battle, else "".
func _side_in(b: Dictionary, faction: String) -> String:
	if faction == "":
		return ""
	if b.get("attacker") == faction:
		return "a"
	if b.get("defender") == faction:
		return "d"
	return ""


func _start() -> void:
	if _selected == "":
		return
	_waiting = true
	Net.send({"type": "battle_start", "planet": planet_id, "sector": _selected})
	_status.text = "Calling the drop... "
	_status.add_theme_color_override("font_color", TEAL)
	refresh()


func _join_battle(b: Dictionary) -> void:
	if b.is_empty():
		return
	_waiting = true
	Net.send({"type": "battle_join", "battle": str(b.id)})
	_status.text = "Joining the battle for %s..." % str(b.get("sectorName", ""))
	_status.add_theme_color_override("font_color", TEAL)
	refresh()


# --- Building blocks --------------------------------------------------------------------------

func _label(parent: Node, text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	parent.add_child(l)
	return l


func _theme() -> Theme:
	var t := Theme.new()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var b := StyleBoxFlat.new()
		b.bg_color = {"normal": Color(0.06, 0.11, 0.15), "hover": Color(0.09, 0.19, 0.24), "pressed": Color(0.1, 0.3, 0.33),
			"disabled": Color(0.04, 0.06, 0.08), "focus": Color(0, 0, 0, 0)}[state]
		b.border_color = Color(0.3, 0.75, 0.8, 0.45 if state != "disabled" else 0.12)
		b.set_border_width_all(1 if state != "focus" else 0)
		b.set_corner_radius_all(2)
		b.content_margin_left = 10
		b.content_margin_right = 10
		b.content_margin_top = 4
		b.content_margin_bottom = 4
		t.set_stylebox(state, "Button", b)
	t.set_color("font_color", "Button", Color(0.88, 0.96, 0.96))
	t.set_color("font_disabled_color", "Button", Color(0.42, 0.47, 0.5))
	t.set_font_size("font_size", "Button", 15)
	return t


## The planet's sectors laid out flat (longitude across, latitude up), linked to their neighbours,
## in their owners' colours; the chosen one ringed, battles pulsing. Click a sector to choose it.
class SectorMap extends Control:
	var menu: Node

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true

	func _at(sec: Dictionary) -> Vector2:
		var pad := Vector2(30, 24)
		var lon := fposmod(float(sec.lon), 360.0) / 360.0
		var lat := 0.5 - float(sec.lat) / 180.0
		return pad + Vector2(lon, lat) * (size - pad * 2.0)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var wp := WarInfo.planet(menu.planet_id)
			var best := ""
			var best_d := 24.0
			for sec in wp.get("sectors", []):
				var d := _at(sec).distance_to(event.position)
				if d < best_d:
					best_d = d
					best = sec.id
			if best != "":
				menu.select_sector(best)
			accept_event()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.06, 0.09, 0.9), true)
		for k in range(1, 6):
			var y := size.y * k / 6.0
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.3, 0.75, 0.8, 0.07), 1.0)
		for k in range(1, 12):
			var x := size.x * k / 12.0
			draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0.3, 0.75, 0.8, 0.07), 1.0)
		var wp := WarInfo.planet(menu.planet_id)
		var secs: Array = wp.get("sectors", [])
		var mine := WarInfo.my_faction()
		for sec in secs:
			for id in sec.get("links", []):
				var o := WarInfo.sector(wp, id)
				if o.is_empty() or str(id) < str(sec.id):
					continue
				var a := _at(sec)
				var b := _at(o)
				if absf(a.x - b.x) > size.x * 0.5:
					continue # the link wraps round the back of the planet
				draw_line(a, b, Color(0.6, 0.75, 0.8, 0.25), 1.5)
		var font := get_theme_default_font()
		for sec in secs:
			var p := _at(sec)
			var c := WarInfo.faction_color(sec.owner)
			var battle: Dictionary = menu._battle_on(sec.id)
			if not battle.is_empty():
				var k := fmod(menu._pulse, 1.2) / 1.2
				draw_arc(p, 12.0 + 16.0 * k, 0, TAU, 32, Color(1.0, 0.45, 0.3, 1.0 - k), 2.0)
			var r := 9.0 if sec.get("capital", false) else 7.0
			draw_circle(p, r, c)
			if sec.get("capital", false):
				draw_arc(p, r + 3.0, 0, TAU, 24, c.lightened(0.3), 1.5)
			if mine != "" and sec.owner != mine and BattleMenu.problem(mine, wp, sec) == "" and battle.is_empty():
				draw_arc(p, r + 5.0, 0, TAU, 24, Color(0.45, 1.0, 0.55, 0.7), 1.5)
			if sec.id == menu._selected:
				draw_arc(p, r + 8.0, 0, TAU, 32, Color.WHITE, 2.0)
				draw_string(font, p + Vector2(14, -10), str(sec.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
		draw_string(font, Vector2(10, size.y - 8), "Green ring: you can attack  ·  red pulse: a battle is on", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.78, 0.82, 0.8))
