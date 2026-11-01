class_name BattleMenu
extends Control
## The Sector Battles screen: opened from the carrier's holo table (and a station's War terminal)
## for the contested planet below. There are no fixed sectors to pick: battles pop up at random
## places on the planet while pilots sit at a holo table over it (campaign.js match sites), and the
## screen shows them on a globe you can spin, Helldivers-style, each marker the game mode fought
## there. Pick one and Drop in (campaign_queue with its site): alone you fight the AI there after a
## short wait, and pilots of your faction who drop in too join you; one already being fought takes
## you into it on your side. Round the globe, the campaign's control bar: each faction's share of
## the campaign points, live; whoever leads when the week ends takes the planet. The quick-queue
## buttons put you in any match of a mode. Away from any planet it says where to fly. When
## matchmaking puts the pilot in a match the view for that mode opens and this screen closes.

const WarInfo := preload("res://war_info.gd")
const Icons := preload("res://battle/battle_icons.gd")

signal closed

const TEAL := Color(0.35, 0.95, 0.88)
const DIM := Color(0.7, 0.76, 0.8)
const BAD := Color(1.0, 0.5, 0.42)
const GOOD := Color(0.45, 1.0, 0.55)
const PING_S := 2.0 # campaign_sites this often while the screen is open (it keeps sites popping up)
## The picture on each mode's markers (battle_icons.gd).
const MODE_ICON := {"sector": "tank", "supremacy": "acu", "space": "fighter", "facility": "striker", "defense": "shield"}

var planet_id := ""
var host: Node

var _selected := "" # the chosen site's id
var _layer: CanvasLayer
var _title: Label
var _sub: Label
var _globe: Control
var _list: VBoxContainer
var _rows := {} # site id -> Button
var _rows_key := ""
var _detail: Label
var _drop: Button
var _status: Label
var _away: Label
var _body: Control
var _waiting := false # a campaign_queue is on its way
var _pulse := 0.0
var _ping := 0.0
var _camp_head: Label
var _camp_modes: HFlowContainer
var _camp_status: Label
var _modes_key := "" # what the mode buttons were drawn for

## The pilot's place in a matchmaking queue (campaign_queued): {"planet", "mode", "since", "site"}, or {}.
## The explorer keeps it current whether or not this screen is open.
static var queued := {}
## The match sites last heard of (campaign_sites), by planet: {"sites": [...], "at": when (ms)}.
## The carrier's holo table shows them too.
static var sites := {}


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


## The match sites of `planet` last heard of (campaign_sites).
static func sites_of(planet: String) -> Array:
	return sites.get(planet, {}).get("sites", [])


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = _theme()
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.02, 0.05, 0.92)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
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
	row.add_theme_constant_override("separation", 20)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(row)
	_body = row

	# Left: the globe, with the control bar round it.
	_globe = Globe.new()
	_globe.menu = self
	_globe.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_globe.size_flags_stretch_ratio = 1.3
	_globe.custom_minimum_size = Vector2(360, 300)
	row.add_child(_globe)

	# Right: the campaign, the battles on the planet, the chosen one, and the quick queues.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	row.add_child(right)
	var camp := PanelContainer.new()
	right.add_child(camp)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 4)
	camp.add_child(cv)
	_camp_head = _label(cv, "", 14, Color(0.9, 0.94, 0.97))
	_camp_head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_camp_status = _label(cv, "", 14, TEAL)
	_camp_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(right, "Battles on this planet", 18, TEAL)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 120)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_list)
	var detail_row := HBoxContainer.new()
	detail_row.add_theme_constant_override("separation", 12)
	right.add_child(detail_row)
	_detail = _label(detail_row, "", 14, Color(0.88, 0.92, 0.95))
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.custom_minimum_size = Vector2(0, 72)
	_drop = Button.new()
	_drop.text = "Drop in"
	_drop.custom_minimum_size = Vector2(170, 44)
	_drop.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_drop.pressed.connect(_drop_pressed)
	detail_row.add_child(_drop)
	_label(right, "Or queue for any match of a mode:", 14, DIM)
	_camp_modes = HFlowContainer.new()
	_camp_modes.add_theme_constant_override("h_separation", 6)
	_camp_modes.add_theme_constant_override("v_separation", 6)
	right.add_child(_camp_modes)
	_status = _label(page, "", 16, DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	Net.message.connect(_on_message)
	Net.state_changed.connect(_on_state)
	_ask_sites()
	refresh()


func _exit_tree() -> void:
	if Net.message.is_connected(_on_message):
		Net.message.disconnect(_on_message)
	if Net.state_changed.is_connected(_on_state):
		Net.state_changed.disconnect(_on_state)


func _process(delta: float) -> void:
	_pulse += delta
	_ping -= delta
	if _ping <= 0.0:
		_ask_sites()
	_globe.queue_redraw()
	_refresh_campaign_clock()
	_refresh_detail()


## Sitting at the globe: ask for the planet's sites (and keep them popping up there).
func _ask_sites() -> void:
	_ping = PING_S
	if planet_id != "" and not WarInfo.planet(planet_id).is_empty() and not campaign(planet_id).is_empty():
		Net.send({"type": "campaign_sites", "planet": planet_id})


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
		"campaign_sites":
			sites[str(msg.get("planet", ""))] = {"sites": msg.get("sites", []), "at": Net.now_ms()}
			if str(msg.get("planet", "")) == planet_id:
				if _selected == "" or site(_selected).is_empty():
					_selected = _first_site()
					if _selected != "":
						_globe.look_at_site(site(_selected))
				refresh()
		"battle_joined":
			# Into the battle: the RTS view takes over the screen (BattleView.active), then we go.
			# (The explorer may have opened it already.)
			_waiting = false
			if not BattleView.active:
				BattleView.open(host if host and host.is_inside_tree() else self, msg)
			_close()
		"campaign_queued":
			_waiting = false
			_modes_key = ""
			refresh()
		"defense_joined", "facility_joined", "supremacy_joined", "starfight_joined":
			_waiting = false
			_close() # the explorer opens that mode's view
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
		_away.text = "Battles are fought from orbit. Fly your carrier to a contested planet's orbit (within 30 km of its orbital station) and the holo table will show the battles popping up on it.\n\n" + _battles_elsewhere()
		return
	var sys := WarInfo.system(wp.system)
	_title.text = "%s · %s" % [wp.name, sys.get("name", wp.system)]
	var bits := ["held by %s" % WarInfo.the(wp.owner) if wp.owner != null else "nobody holds it", WarInfo.contention(wp)]
	if mine != "":
		bits.append("%s has %d%% of the orbit" % [WarInfo.faction_name(mine), floori(WarInfo.orbital(wp.system, mine) * 100.0 + 1e-9)])
	var lock := WarInfo.lock_left(wp)
	if lock != "":
		bits.append("locked for " + lock)
	var line := ", ".join(bits)
	_sub.text = line.substr(0, 1).to_upper() + line.substr(1) + ("  ·  demo war: every faction has 25% of the orbit" if Net.catalog.get("demo", false) else "")
	_refresh_campaign(wp)
	_refresh_list()
	_refresh_detail()


# --- The planet's campaign ------------------------------------------------------------------

static func campaign(planet: String) -> Dictionary:
	return Net.state.get("war", {}).get("campaigns", {}).get(planet, {})


## Each faction's share of the planet's campaign points so far: [[faction, share], ...], largest
## first; empty while nobody has any. The control bar.
static func control(planet: String) -> Array:
	var c := campaign(planet)
	var pts: Dictionary = c.get("points", {})
	var total := 0.0
	for f in pts:
		total += maxf(0.0, float(pts[f]))
	if total <= 0.0:
		return []
	var out := []
	for f in pts:
		if float(pts[f]) > 0.0:
			out.append([f, float(pts[f]) / total])
	out.sort_custom(func(a, b): return a[1] > b[1])
	return out


## This pilot's points toward each of `planet`'s titles this campaign: "Ghost of Cinder 120/500".
static func title_lines(planet: String) -> Array:
	var out := []
	for t in Net.titles:
		if t is Dictionary and str(t.get("planet", "")) == planet:
			out.append("%s %d/%d" % [str(t.get("title", "")), int(t.get("points", 0)), int(t.get("need", 0))])
	return out


static func time_text(ms: float) -> String:
	var s := maxi(0, int(ms / 1000.0))
	if s >= 86400:
		return "%dd %dh" % [s / 86400, (s % 86400) / 3600]
	if s >= 3600:
		return "%dh %02dm" % [s / 3600, (s % 3600) / 60]
	return "%d:%02d" % [s / 60, s % 60]


static func mode_name(mode: String) -> String:
	return str(Net.catalog.get("campaign", {}).get("modes", {}).get(mode, {}).get("name", mode.capitalize()))


func _refresh_campaign(wp: Dictionary) -> void:
	var c := campaign(str(wp.get("id", "")))
	_camp_head.get_parent().get_parent().visible = not c.is_empty()
	if c.is_empty():
		return
	var mine := WarInfo.my_faction()
	var cat: Dictionary = Net.catalog.get("campaign", {})
	var parts := []
	var entrants: Array = c.get("entrants", [])
	for f in entrants:
		parts.append("%s %d" % [WarInfo.faction_name(f), int(c.points.get(f, 0))])
	var bonus: Dictionary = cat.get("bonuses", {}).get(str(c.get("bonus", "")), {})
	var bonus_line := "Planet bonus, %s: %s" % [str(bonus.get("name", "")), str(bonus.get("text", ""))] if not bonus.is_empty() else "Planet bonus: none here (only a storied world in each system has one)"
	_camp_head.text = "Campaign for %s: %s\n%s" % [wp.get("name", ""), "   ·   ".join(parts) if not parts.is_empty() else "no factions in it", bonus_line]
	# The front's war supply (the ledger): by faction and source, and your side's multiplier.
	var supply := WarInfo.supply_lines(str(wp.get("id", "")))
	var shares: Dictionary = Net.catalog.get("ledger", {}).get("shares", {})
	var share_note := "the arena at most %d%%, the Frontier at most %d%% of a side's" % [roundi(float(shares.get("arena", 0.15)) * 100.0), roundi(float(shares.get("frontier", 0.4)) * 100.0)]
	_camp_head.text += "\nWar supply this campaign: %s  (%s)" % ["   ·   ".join(supply) if not supply.is_empty() else "none yet", share_note]
	if mine != "" and not is_equal_approx(WarInfo.supply_multiplier(mine), 1.0):
		_camp_head.text += "\n%s's war supply counts x%.2f (underdog multiplier)" % [WarInfo.faction_name(mine), WarInfo.supply_multiplier(mine)]
	# Your points toward this planet's titles, by mode (titles.ts).
	var titles := title_lines(str(wp.get("id", "")))
	var need := int(Net.catalog.get("tunables", {}).get("titles", {}).get("points", 500))
	_camp_head.text += "\nYour titles here: %s" % ("   ·   ".join(titles) if not titles.is_empty() else "win %d points in one mode for the side that takes or holds %s to earn that mode's title" % [need, wp.get("name", "")])
	# The quick-queue buttons: any match of a mode, or leave the queue you're in.
	var key := "%s/%s/%s/%s/%s" % [wp.id, mine, queued.get("planet", ""), queued.get("mode", ""), queued.get("site", "")]
	if key != _modes_key:
		_modes_key = key
		for b in _camp_modes.get_children():
			b.free()
		var modes: Dictionary = cat.get("modes", {})
		for m in modes:
			var md: Dictionary = modes[m]
			var b := Button.new()
			b.custom_minimum_size = Vector2(0, 32)
			if not bool(md.get("open", false)):
				b.text = "%s: coming soon" % md.name
				b.disabled = true
			elif str(queued.get("planet", "")) == str(wp.id) and str(queued.get("mode", "")) == m and queued.get("site") == null:
				b.text = "Leave the %s queue" % md.name
				b.pressed.connect(func(): Net.send({"type": "campaign_unqueue"}))
			else:
				b.text = "Queue: %s (%d pts)" % [md.name, int(md.points)]
				b.disabled = mine == "" or not entrants.has(mine)
				b.pressed.connect(func(): Net.send({"type": "campaign_queue", "planet": wp.id, "mode": m}))
			b.tooltip_text = "%s: %s, about %d minutes. A win scores %d campaign points (half against AI, double in the final push)." % [md.name, md.kind, int(md.minutes), int(md.points)]
			_camp_modes.add_child(b)
	_refresh_campaign_clock()


func _refresh_campaign_clock() -> void:
	if _camp_status == null:
		return
	var wp := WarInfo.planet(planet_id)
	var c := campaign(planet_id)
	if c.is_empty() or wp.is_empty():
		return
	var t := Net.now_ms()
	var lines := ["%s left in this campaign%s" % [time_text(float(c.endsAt) - t), "  ·  FINAL PUSH: wins count double" if t >= float(c.finalAt) else "  ·  final push in " + time_text(float(c.finalAt) - t)]]
	var lead := control(planet_id)
	if not lead.is_empty():
		lines.append("Control: %s leads with %d%%; whoever leads when the week ends takes %s" % [WarInfo.faction_name(lead[0][0]), roundi(lead[0][1] * 100.0), wp.name])
	var mine := WarInfo.my_faction()
	if mine != "" and not c.get("entrants", []).has(mine):
		lines.append("%s isn't in this campaign: it needs 25%% of the orbit when the week starts." % WarInfo.faction_name(mine))
	if str(queued.get("planet", "")) == planet_id:
		var where := ""
		var at := site(str(queued.get("site", ""))) if queued.get("site") != null else {}
		if not at.is_empty():
			where = " at " + str(at.name)
		var waiting: Dictionary = at.get("queued", {}) if not at.is_empty() else Net.state.get("queues", {}).get(planet_id, {}).get(str(queued.get("mode", "sector")), {})
		var who := []
		for f in waiting:
			who.append("%d %s" % [int(waiting[f]), WarInfo.faction_name(f)])
		lines.append((("Dropping in for %s%s: %s" if where != "" else "In the queue for %s%s: %s") + "  ·  waiting: %s. " + ("Squads of up to 4 go in together, or on their own after a short wait." if str(queued.mode) == "defense" else "With no opponents, you fight the AI after a short wait.")) % [mode_name(str(queued.mode)), where, time_text(t - float(queued.since)), ", ".join(who)])
	_camp_status.text = "\n".join(lines)


# --- The sites --------------------------------------------------------------------------------

func site(id: String) -> Dictionary:
	for s in sites_of(planet_id):
		if str(s.id) == id:
			return s
	return {}


func select_site(id: String) -> void:
	_selected = id
	_status.text = ""
	_globe.look_at_site(site(id))
	refresh()


## A site worth showing first: one being fought on your side, else the newest open one.
func _first_site() -> String:
	var mine := WarInfo.my_faction()
	var best := ""
	var best_born := -1.0
	for s in sites_of(planet_id):
		if s.get("ended", false):
			continue
		if s.has("match") and _side_in(s.match.get("sides", {}), mine) != "":
			return str(s.id)
		if not s.has("match") and float(s.get("until", 0)) > best_born:
			best_born = float(s.get("until", 0))
			best = str(s.id)
	return best


## "Sector Battles at Ash Ridge · open 3:12" or "... · Ashen Collective against the militia".
func site_line(s: Dictionary) -> String:
	var line := "%s at %s" % [mode_name(str(s.mode)), str(s.name)]
	if s.get("ended", false):
		return line + "  ·  over"
	if s.has("match"):
		var sides: Dictionary = s.match.get("sides", {})
		line += "  ·  %s against %s" % [WarInfo.faction_name(sides.get("a")), _defender_name(sides.get("d"))]
		var n := _pilots_in(s)
		if n > 0:
			line += ", %d pilot%s" % [n, "" if n == 1 else "s"]
		return line
	line += "  ·  open %s" % time_text(float(s.get("until", 0)) - Net.now_ms())
	var q: Dictionary = s.get("queued", {})
	if not q.is_empty():
		var who := []
		for f in q:
			who.append("%d %s" % [int(q[f]), WarInfo.faction_name(f)])
		line += "  ·  dropping in: " + ", ".join(who)
	return line


## Pilots in a site's Sector Battle (the state's battles list), or 0 for the other modes.
func _pilots_in(s: Dictionary) -> int:
	for b in Net.state.get("battles", []):
		if str(b.get("site", "")) == str(s.id):
			return b.get("pilots", []).size()
	return 0


func _refresh_list() -> void:
	var list := sites_of(planet_id)
	var key := ",".join(list.map(func(s): return str(s.id)))
	if key != _rows_key:
		_rows_key = key
		for c in _list.get_children():
			c.free()
		_rows.clear()
		for s in list:
			var b := Button.new()
			b.toggle_mode = true
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.custom_minimum_size = Vector2(0, 30)
			b.clip_text = true
			b.pressed.connect(select_site.bind(str(s.id)))
			_list.add_child(b)
			_rows[str(s.id)] = b
		if list.is_empty():
			_label(_list, "Nothing yet: battles pop up here while pilots sit at the table.", 14, DIM)
	for s in list:
		var b: Button = _rows[str(s.id)]
		b.text = "  " + site_line(s)
		b.button_pressed = str(s.id) == _selected
		var c := Color(1.0, 0.6, 0.45) if s.has("match") and not s.get("ended", false) else (DIM if s.get("ended", false) else Color(0.88, 0.96, 0.96))
		b.add_theme_color_override("font_color", c)
		b.add_theme_color_override("font_pressed_color", c.lightened(0.4))


func _refresh_detail() -> void:
	if _detail == null:
		return
	var s := site(_selected)
	var mine := WarInfo.my_faction()
	var c := campaign(planet_id)
	if s.is_empty():
		_detail.text = "Pick a battle on the globe or in the list." if not sites_of(planet_id).is_empty() else "Watching for battles..."
		_drop.visible = false
		return
	_drop.visible = true
	var md: Dictionary = Net.catalog.get("campaign", {}).get("modes", {}).get(str(s.mode), {})
	var lines := [site_line(s), "%s: %s, about %d minutes. A win scores %d campaign points (half against AI)." % [mode_name(str(s.mode)), str(md.get("kind", "")), int(md.get("minutes", 0)), int(md.get("points", 0))]]
	var here := str(queued.get("planet", "")) == planet_id and str(queued.get("site", "")) == str(s.id)
	var why := ""
	if s.get("ended", false):
		why = "this battle is over"
	elif mine == "":
		why = "pick a side first"
	elif not c.get("entrants", []).has(mine):
		why = "%s isn't in this campaign" % WarInfo.faction_name(mine)
	elif s.has("match") and _side_in(s.match.get("sides", {}), mine) == "":
		why = "only %s and %s fight in it" % [WarInfo.the(s.match.sides.get("a")), _defender_name(s.match.sides.get("d"))]
	if why != "":
		lines.append(why.substr(0, 1).to_upper() + why.substr(1) + ".")
	_drop.text = "Leave" if here else ("Join battle" if s.has("match") else "Drop in")
	_drop.disabled = (why != "" and not here) or _waiting
	_detail.text = "\n".join(lines)


func _drop_pressed() -> void:
	var s := site(_selected)
	if s.is_empty():
		return
	if str(queued.get("site", "")) == str(s.id):
		Net.send({"type": "campaign_unqueue"})
		return
	_waiting = true
	Net.send({"type": "campaign_queue", "planet": planet_id, "mode": str(s.mode), "site": str(s.id)})
	_status.text = ("Joining the battle at %s..." if s.has("match") else "Calling the drop at %s...") % str(s.name)
	_status.add_theme_color_override("font_color", TEAL)
	refresh()


func _defender_name(f) -> String:
	return WarInfo.faction_name(f) if f != null and str(f) != "" else "the militia"


func _battles_elsewhere() -> String:
	var lines := []
	for b in Net.state.get("battles", []):
		var wp := WarInfo.planet(str(b.get("planet", "")))
		lines.append("  %s, %s: %s against %s" % [wp.get("name", b.get("planet", "")), str(b.get("sectorName", "")), WarInfo.faction_name(b.get("attacker")), _defender_name(b.get("defender"))])
	if lines.is_empty():
		return "No battles are being fought anywhere right now."
	return "Battles being fought now:\n" + "\n".join(lines)


## "a" or "d" if `faction` fights on that side of a match ({"a", "d"}), else "".
static func _side_in(sides: Dictionary, faction: String) -> String:
	if faction == "":
		return ""
	if sides.get("a") == faction:
		return "a"
	if sides.get("d") == faction:
		return "d"
	return ""


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


## The planet as a globe you can spin (drag; it turns slowly by itself), its battles as markers
## where they're fought: each the picture of its mode, a new one growing in as it pops up, one
## being fought pulsing red. Round it, the control bar: each faction's share of the campaign
## points. Click a marker to choose it.
class Globe extends Control:
	var menu: Node
	var yaw := 0.0 # the longitude facing us (degrees)
	var yaw_to := 0.0
	var tilt := 18.0 # degrees the north pole leans toward us
	var _drag := false
	var _idle := 0.0
	var _land := [] # [lat, lon, radius (degrees)] blobs of land, from the planet's id
	var _land_for := ""

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true

	func look_at_site(s: Dictionary) -> void:
		if s.is_empty():
			return
		var lon := float(s.get("lon", 0.0))
		yaw_to = yaw + wrapf(lon - yaw, -180.0, 180.0)
		_idle = 0.0

	func _process(delta: float) -> void:
		_idle += delta
		if not _drag and _idle > 4.0:
			yaw_to += 4.0 * delta # a slow turn while nobody touches it
		yaw = lerpf(yaw, yaw_to, clampf(delta * 4.0, 0.0, 1.0))

	func _centre() -> Vector2:
		return size * 0.5

	func _radius() -> float:
		return maxf(40.0, minf(size.x, size.y) * 0.5 - 46.0)

	## A point on the globe to the screen, and how far it faces us (z > 0: this side).
	func project(lat: float, lon: float) -> Vector3:
		var la := deg_to_rad(lat)
		var lo := deg_to_rad(lon - yaw)
		var x := cos(la) * sin(lo)
		var y := sin(la)
		var z := cos(la) * cos(lo)
		var t := deg_to_rad(tilt)
		var y2 := y * cos(t) - z * sin(t)
		var z2 := y * sin(t) + z * cos(t)
		var p := _centre() + Vector2(x, -y2) * _radius()
		return Vector3(p.x, p.y, z2)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var best := ""
				var best_d := 24.0
				for s in BattleMenu.sites_of(menu.planet_id):
					var p := project(float(s.lat), float(s.lon))
					if p.z < 0.05:
						continue
					var d := Vector2(p.x, p.y).distance_to(event.position)
					if d < best_d:
						best_d = d
						best = str(s.id)
				if best != "":
					menu.select_site(best)
				else:
					_drag = true
			else:
				_drag = false
			_idle = 0.0
			accept_event()
		elif event is InputEventMouseMotion and _drag:
			yaw_to -= event.relative.x * 0.4
			yaw = yaw_to
			tilt = clampf(tilt + event.relative.y * 0.2, -60.0, 60.0)
			accept_event()

	func _build_land() -> void:
		_land_for = menu.planet_id
		_land.clear()
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(menu.planet_id)
		for i in 26:
			var lat := rad_to_deg(asin(rng.randf_range(-0.95, 0.95)))
			var lon := rng.randf_range(-180.0, 180.0)
			for j in rng.randi_range(2, 5): # a continent: a few overlapping blobs
				_land.append([clampf(lat + rng.randf_range(-12, 12), -85, 85), lon + rng.randf_range(-16, 16), rng.randf_range(6.0, 15.0)])

	## A circle of `r` degrees round (lat, lon) on the globe, as screen points on this side.
	func _cap(lat: float, lon: float, r: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		var la := deg_to_rad(lat)
		var lo := deg_to_rad(lon)
		var c := Vector3(cos(la) * sin(lo), sin(la), cos(la) * cos(lo))
		var axis := c.cross(Vector3.UP).normalized() if absf(c.y) < 0.99 else Vector3.RIGHT
		var edge := c.rotated(axis, deg_to_rad(r))
		for k in 14:
			var q := edge.rotated(c, TAU * k / 14.0)
			var qlat := rad_to_deg(asin(clampf(q.y, -1.0, 1.0)))
			var qlon := rad_to_deg(atan2(q.x, q.z))
			var p := project(qlat, qlon)
			if p.z < 0.0:
				return PackedVector2Array()
			pts.append(Vector2(p.x, p.y))
		return pts

	func _draw() -> void:
		if menu == null:
			return
		var wp := WarInfo.planet(menu.planet_id)
		if wp.is_empty():
			return
		if _land_for != menu.planet_id:
			_build_land()
		var c := _centre()
		var r := _radius()
		var hue := fposmod(float(hash(menu.planet_id) % 1000) / 1000.0, 1.0)
		var sea := Color.from_hsv(0.5 + hue * 0.15, 0.55, 0.32)
		var land := Color.from_hsv(fposmod(0.08 + hue * 0.3, 1.0), 0.35, 0.5)
		# The holo-glow behind, the sea, shading toward the rim.
		for k in 6:
			draw_circle(c, r + 10.0 + k * 5.0, Color(0.35, 0.75, 1.0, 0.035))
		draw_circle(c, r, sea)
		for blob in _land:
			var pts := _cap(blob[0], blob[1], blob[2])
			if pts.size() >= 3:
				draw_colored_polygon(pts, land)
		# The grid: parallels and meridians every 30 degrees, this side only.
		var grid := Color(0.6, 0.9, 1.0, 0.16)
		for lat in [-60, -30, 0, 30, 60]:
			_line(func(t): return [float(lat), t * 360.0 - 180.0], grid)
		for lon in range(-180, 180, 30):
			_line(func(t): return [t * 180.0 - 90.0, float(lon)], grid)
		for k in 10:
			draw_arc(c, r - k * 1.6, 0, TAU, 64, Color(0, 0, 0, 0.05 * k * 0.4), 2.0)
		draw_arc(c, r, 0, TAU, 96, Color(0.55, 0.9, 1.0, 0.7), 2.0)
		# The control bar: each faction's share of the campaign points.
		var share := BattleMenu.control(menu.planet_id)
		var ring := r + 20.0
		draw_arc(c, ring, 0, TAU, 96, Color(0.3, 0.4, 0.45, 0.5), 9.0)
		var from := -PI / 2.0
		for f in share:
			var to: float = from + TAU * float(f[1])
			draw_arc(c, ring, from, to, maxi(4, int(96 * float(f[1]))), WarInfo.faction_color(f[0]), 9.0)
			from = to
		var font := get_theme_default_font()
		var cap := "No campaign points yet: win a battle here to start the control bar" if share.is_empty() else "  ·  ".join(share.map(func(f): return "%s %d%%" % [WarInfo.faction_name(f[0]), roundi(f[1] * 100.0)]))
		draw_string(font, Vector2(0, size.y - 8), cap, HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, Color(0.8, 0.88, 0.92))
		# The battles.
		for s in BattleMenu.sites_of(menu.planet_id):
			var p := project(float(s.lat), float(s.lon))
			if p.z < 0.0:
				continue
			var at := Vector2(p.x, p.y)
			var fade := clampf(p.z * 3.0, 0.25, 1.0)
			var fought: bool = s.has("match") and not s.get("ended", false)
			var ended: bool = s.get("ended", false)
			var ring_c := Color(1.0, 0.45, 0.3) if fought else (Color(0.5, 0.55, 0.6) if ended else TEAL)
			if fought:
				var k := fmod(menu._pulse, 1.2) / 1.2
				draw_arc(at, 15.0 + 14.0 * k, 0, TAU, 28, Color(1.0, 0.45, 0.3, (1.0 - k) * fade), 2.0)
			elif not ended:
				var k := fmod(menu._pulse + float(hash(str(s.id)) % 100) / 100.0, 2.0) / 2.0
				draw_arc(at, 15.0 + 8.0 * k, 0, TAU, 28, Color(TEAL.r, TEAL.g, TEAL.b, (1.0 - k) * 0.6 * fade), 1.5)
			draw_circle(at, 14.0, Color(0.02, 0.06, 0.09, 0.85 * fade))
			draw_arc(at, 14.0, 0, TAU, 28, Color(ring_c.r, ring_c.g, ring_c.b, fade), 2.0)
			Icons.draw(self, MODE_ICON.get(str(s.mode), "tank"), Rect2(at - Vector2(10, 10), Vector2(20, 20)), Color(1, 1, 1, fade * (0.5 if ended else 1.0)))
			if str(s.id) == menu._selected:
				draw_arc(at, 19.0, 0, TAU, 32, Color.WHITE, 2.0)
				draw_string(font, at + Vector2(22, -8), str(s.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
				draw_string(font, at + Vector2(22, 8), BattleMenu.mode_name(str(s.mode)), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.75, 0.85, 0.9))
		draw_string(font, Vector2(8, 18), "Drag to turn · click a battle", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.78, 0.82, 0.7))

	## A line along the globe (`f(t)` gives [lat, lon] for t in 0..1), drawn where it faces us.
	func _line(f: Callable, colour: Color) -> void:
		var run := PackedVector2Array()
		for k in 73:
			var ll: Array = f.call(k / 72.0)
			var p := project(ll[0], ll[1])
			if p.z >= 0.0:
				run.append(Vector2(p.x, p.y))
			else:
				if run.size() >= 2:
					draw_polyline(run, colour, 1.0)
				run = PackedVector2Array()
		if run.size() >= 2:
			draw_polyline(run, colour, 1.0)
