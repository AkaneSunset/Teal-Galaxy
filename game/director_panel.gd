extends Control
## The Coma director, for the galaxy's admins: a page of the War terminal (war_panel.gd).
## Nobody can join the Coma Conglomerate. Admins play it, and the rest of the time the server's AI
## director does: it sends armadas to win orbits, and pushes hardest on the strongest player
## faction. Here an admin steers it with `director_set`: pause it, set the master scale (0 to 2),
## fix how hard it pushes a player faction (or leave it automatic), and set each contested
## system's posture. They can also send an armada of their own (`admin_armada`) and recall any
## armada (`admin_recall`). Players never see this: the server sends g.director only to admins.

const System := preload("res://teal_prime.gd")
const WarInfo := preload("res://war_info.gd")

## What the director does in a system under each posture (the phone's Director tab says the same).
const POSTURES := [["push", "Push", "Armadas match the strongest player faction here (times its intensity and the scale), and patrol when no player fleet is here."],
	["hold", "Hold", "Nothing new is sent here and nothing is recalled."],
	["withdraw", "Withdraw", "Every Coma armada here or on its way comes home."]]
const ARMADA_POWER := [10, 400] # the power an admin can send in one armada (server: admin_armada)
const TRAVEL_S := 120.0 # seconds for one lane at speed 1 (server: navy.js TRAVEL_S)

var colour := Color(0.35, 0.95, 0.88)

var _paused: CheckButton
var _next: Label
var _scale: HSlider
var _scale_value: Label
var _rows := {} # player faction -> {"strength", "auto", "use": Label, "fixed": CheckBox, "level": HSlider, "level_text": Label}
var _systems := {} # system id -> {"buttons": {posture: Button}, "about", "power": Label, "armadas": VBoxContainer, "armada_key": String, "amount": SpinBox, "preview": Label, "send": Button}
var _dragging := "" # the slider being dragged ("scale" or a faction), which state updates leave alone
var _status: Label
var _pending := "" # what to say once the state shows the last armada sent or recalled
var _grid: GridContainer # the player factions, once the catalog has them
var _list: VBoxContainer # the contested systems, once the war map has them


func _ready() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 24)
	add_child(row)

	# Left: the director as a whole, then the player factions.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(500, 0)
	left.add_theme_constant_override("separation", 8)
	row.add_child(left)
	var title := Label.new()
	title.text = "Coma director"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", WarInfo.faction_color("coma").lightened(0.2))
	left.add_child(title)
	left.add_child(_note("The Coma Conglomerate's AI. It sends armadas to win orbits, pushing hardest on the strongest player faction. Players see its armadas, never these settings."))

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	left.add_child(top)
	_paused = CheckButton.new()
	_paused.text = "Paused"
	_paused.toggled.connect(func(on): _steer({"paused": on}))
	top.add_child(_paused)
	_next = Label.new()
	_next.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_next.modulate = Color(1, 1, 1, 0.7)
	top.add_child(_next)

	var scale_row := HBoxContainer.new()
	scale_row.add_theme_constant_override("separation", 12)
	left.add_child(scale_row)
	var scale_name := Label.new()
	scale_name.text = "Master scale"
	scale_name.custom_minimum_size = Vector2(130, 0)
	scale_row.add_child(scale_name)
	_scale = _slider(0.0, float(Net.catalog.get("director", {}).get("scaleMax", 2)), 0.05, "scale",
		func(v): _scale_value.text = "x%.2f" % v,
		func(v): _steer({"scale": snappedf(v, 0.01)}))
	scale_row.add_child(_scale)
	_scale_value = Label.new()
	_scale_value.custom_minimum_size = Vector2(56, 0)
	scale_row.add_child(_scale_value)
	left.add_child(_note("0 sends nothing and calls its armadas home, 1 is normal, 2 is twice as hard."))

	left.add_child(_heading("Player factions"))
	left.add_child(_note("Strength: half the sectors held, three tenths orbital control, a fifth the players active in the last day. Automatic intensity gives the strongest faction 100% and eases the rest down to 15%. Untick Auto to fix a level."))
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 8)
	left.add_child(_grid)
	for h in ["", "Strength", "Automatic", "In use", "Override"]:
		var l := Label.new()
		l.text = h
		l.modulate = Color(1, 1, 1, 0.55)
		_grid.add_child(l)
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(gap)
	_status = Label.new()
	_status.modulate = Color(1, 1, 1, 0.7)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_status)

	# Right: every system that can be fought over.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	row.add_child(right)
	right.add_child(_heading("Contested systems"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)

	Net.server_error.connect(func(reason):
		_pending = ""
		if is_visible_in_tree():
			_status.text = "Server: " + reason)
	refresh()


## The rows for the player factions and the boxes for the contested systems, once the server's
## welcome has brought the catalog and the war map.
func _build_rows() -> void:
	for f in WarInfo.player_factions():
		var name_l := Label.new()
		name_l.text = WarInfo.faction_name(f)
		name_l.add_theme_color_override("font_color", WarInfo.faction_color(f).lightened(0.2))
		_grid.add_child(name_l)
		var r := {}
		for k in ["strength", "auto", "use"]:
			r[k] = Label.new()
			_grid.add_child(r[k])
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 8)
		_grid.add_child(cell)
		r.fixed = CheckBox.new()
		r.fixed.text = "Auto"
		var faction: String = f
		r.fixed.toggled.connect(func(auto):
			_steer({"overrides": {faction: null if auto else snappedf(_rows[faction].level.value, 0.01)}}))
		cell.add_child(r.fixed)
		r.level = _slider(0.0, 1.0, 0.05, f,
			func(v): _rows[faction].level_text.text = "%d%%" % roundi(v * 100.0),
			func(v): _steer({"overrides": {faction: snappedf(v, 0.01)}}))
		r.level.custom_minimum_size = Vector2(90, 0)
		cell.add_child(r.level)
		r.level_text = Label.new()
		r.level_text.custom_minimum_size = Vector2(44, 0)
		cell.add_child(r.level_text)
		_rows[f] = r
	for s in WarInfo.contested_systems():
		_list.add_child(_system_box(s))


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	return l


func _note(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.modulate = Color(1, 1, 1, 0.6)
	return l


## A slider that shows its value as it moves (`shown`) and tells the server once you let go, or
## at once for a click or a key (`chosen`).
func _slider(lo: float, hi: float, step: float, key: String, shown: Callable, chosen: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.drag_started.connect(func(): _dragging = key)
	s.drag_ended.connect(func(changed):
		_dragging = ""
		if changed:
			chosen.call(s.value))
	s.value_changed.connect(func(v):
		shown.call(v)
		if _dragging != key:
			chosen.call(v))
	return s


## One contested system: its posture, Coma's armada power there against the strongest player
## faction's, its armadas with Recall, and Send armada.
func _system_box(s: Dictionary) -> Control:
	var box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.08, 0.12, 0.95)
	style.border_color = Color(colour, 0.25)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(12)
	box.add_theme_stylebox_override("panel", style)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	box.add_child(col)
	var sid: String = s.id
	var r := {"buttons": {}, "armada_key": ""}
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	col.add_child(top)
	var name_l := Label.new()
	name_l.text = s.name
	name_l.add_theme_font_size_override("font_size", 18)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_l)
	var group := ButtonGroup.new()
	for p in POSTURES:
		var b := Button.new()
		b.text = p[1]
		b.toggle_mode = true
		b.button_group = group
		var posture: String = p[0]
		b.pressed.connect(func(): _steer({"posture": {sid: posture}}))
		top.add_child(b)
		r.buttons[posture] = b
	r.about = _note("")
	col.add_child(r.about)
	r.power = Label.new()
	r.power.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(r.power)
	r.armadas = VBoxContainer.new()
	r.armadas.add_theme_constant_override("separation", 4)
	col.add_child(r.armadas)
	var send_row := HBoxContainer.new()
	send_row.add_theme_constant_override("separation", 10)
	col.add_child(send_row)
	var power_l := Label.new()
	power_l.text = "Armada power"
	send_row.add_child(power_l)
	r.amount = SpinBox.new()
	r.amount.min_value = ARMADA_POWER[0]
	r.amount.max_value = ARMADA_POWER[1]
	r.amount.step = 10
	r.amount.value = 60
	r.amount.value_changed.connect(func(_v): _preview(sid))
	send_row.add_child(r.amount)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	send_row.add_child(gap)
	r.send = Button.new()
	r.send.text = "Send armada"
	r.send.pressed.connect(func():
		_status.text = "Sending an armada of power %d to %s..." % [int(r.amount.value), s.name]
		_pending = "An armada of power %d is on its way to %s." % [int(r.amount.value), s.name]
		Net.send({"type": "admin_armada", "system": sid, "power": int(r.amount.value)}))
	send_row.add_child(r.send)
	r.preview = _note("")
	col.add_child(r.preview)
	_systems[sid] = r
	return box


func _steer(change: Dictionary) -> void:
	_status.text = ""
	var msg := {"type": "director_set"}
	msg.merge(change)
	Net.send(msg)


func refresh() -> void:
	if not is_node_ready():
		return
	var d: Dictionary = Net.state.get("director", {}) if not Net.state.is_empty() else {}
	if d.is_empty():
		_next.text = "The server hasn't sent the director yet."
		return
	if _rows.is_empty() and _systems.is_empty():
		_build_rows()
	if _pending != "":
		_status.text = _pending
		_pending = ""
	_paused.set_pressed_no_signal(d.get("paused", false))
	if _dragging != "scale":
		_scale.set_value_no_signal(float(d.get("scale", 1)))
		_scale_value.text = "x%.2f" % float(d.get("scale", 1))
	for f in _rows:
		var r: Dictionary = _rows[f]
		r.strength.text = _pct(d.get("strength", {}).get(f, 0))
		r.auto.text = _pct(d.get("auto", {}).get(f, 0))
		r.use.text = _pct(d.get("intensity", {}).get(f, 0))
		var fixed = d.get("overrides", {}).get(f)
		r.fixed.set_pressed_no_signal(fixed == null)
		if _dragging != f:
			var level := float(fixed) if fixed != null else float(d.get("auto", {}).get(f, 0))
			r.level.set_value_no_signal(level)
			r.level_text.text = "%d%%" % roundi(level * 100.0) if fixed != null else "auto"
		r.level.modulate.a = 1.0 if fixed != null else 0.5 # dim while it only shows the automatic level
	for sid in _systems:
		_refresh_system(d, sid)
	_tick()


## The live parts: when the director next takes its turn.
func _tick() -> void:
	var d: Dictionary = Net.state.get("director", {}) if not Net.state.is_empty() else {}
	if d.is_empty():
		return
	if d.get("paused", false):
		_next.text = "Paused: it sends and recalls nothing until you start it again."
	else:
		_next.text = "Next turn in %s" % System.format_time(maxf(0.0, (float(d.get("runAt", 0)) - Net.now_ms()) / 1000.0))


func _process(_delta: float) -> void:
	if is_visible_in_tree() and Engine.get_process_frames() % 30 == 0:
		_tick()


func _refresh_system(d: Dictionary, sid: String) -> void:
	var r: Dictionary = _systems[sid]
	var posture := str(d.get("posture", {}).get(sid, "push"))
	for p in POSTURES:
		(r.buttons[p[0]] as Button).set_pressed_no_signal(p[0] == posture)
		if p[0] == posture:
			r.about.text = "%s: %s" % [p[1], p[2]]
	# Coma's armadas here against the strongest player faction's (in orbit or on the way, as the
	# director counts them), and what it aims for.
	var coma := 0.0
	var coming := 0.0
	var by := {}
	for fl in WarInfo.fleets_at(sid):
		if WarInfo.is_armada(fl):
			coma += WarInfo.power(fl.ships)
			if fl.status == "flying":
				coming += WarInfo.power(fl.ships)
		elif fl.faction in _rows:
			by[fl.faction] = by.get(fl.faction, 0.0) + WarInfo.power(fl.ships)
	var best := ""
	for f in by:
		if best == "" or by[f] > by[best]:
			best = f
	var text := "Coma armadas: power %d%s.   Strongest player faction: %s." % [roundi(coma), " (%d on the way)" % roundi(coming) if coming > 0.0 else "",
		"%s, power %d" % [WarInfo.faction_name(best), roundi(by[best])] if best != "" else "no player fleet here"]
	if posture == "push":
		text += "   It aims for power %d." % roundi(_target(d, by))
	r.power.text = text
	# The armadas, rebuilt only when they change.
	var armadas: Array = WarInfo.war().get("fleets", []).filter(func(fl): return WarInfo.is_armada(fl) and fl.system == sid)
	var key := JSON.stringify(armadas.map(func(fl): return [fl.id, fl.status, fl.ships]))
	if key != r.armada_key:
		r.armada_key = key
		for child in (r.armadas as VBoxContainer).get_children():
			child.queue_free()
		if armadas.is_empty():
			r.armadas.add_child(_note("No Coma armadas here."))
		for fl in armadas:
			r.armadas.add_child(_armada_row(fl))
	_refresh_armada_times(sid)
	r.send.disabled = posture == "withdraw"
	r.send.tooltip_text = "Set Push or Hold to send an armada here." if posture == "withdraw" else ""
	_preview(sid)


## One armada: its ships, where it is and when, and Recall.
func _armada_row(fl: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var text := Label.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_color_override("font_color", WarInfo.faction_color("coma").lightened(0.3))
	text.set_meta("fleet", fl)
	row.add_child(text)
	var recall := Button.new()
	recall.text = "Recall"
	recall.disabled = fl.status == "returning"
	var id := int(fl.id)
	recall.pressed.connect(func():
		_status.text = "Recalling armada %d..." % id
		_pending = "Armada %d is heading home." % id
		Net.send({"type": "admin_recall", "fleet": id}))
	row.add_child(recall)
	return row


## The armadas' lines with their times, which tick down.
func _refresh_armada_times(sid: String) -> void:
	var now := Net.now_ms()
	for row in (_systems[sid].armadas as VBoxContainer).get_children():
		if row.get_child_count() == 0 or not row.get_child(0).has_meta("fleet"):
			continue
		var fl: Dictionary = row.get_child(0).get_meta("fleet")
		var when := ""
		match str(fl.status):
			"flying":
				when = "arriving in %s" % System.format_time(maxf(0.0, (float(fl.arriveAt) - now) / 1000.0))
			"stationed":
				when = "in orbit"
			_:
				when = "heading home, back in %s" % System.format_time(maxf(0.0, (float(fl.get("returnAt", 0)) - now) / 1000.0))
		(row.get_child(0) as Label).text = "Armada %d: %s, power %d · %s%s" % [int(fl.id), WarInfo.ships_text(fl.ships), roundi(WarInfo.power(fl.ships)), when,
			" · sent by an admin" if fl.get("manual", false) else ""]


## What the director aims for in a system under Push: the strongest player faction's power there
## times that faction's intensity and the scale, or a patrol where no player fleet is.
func _target(d: Dictionary, by: Dictionary) -> float:
	var scale := float(d.get("scale", 1))
	if by.is_empty():
		var mean := 0.0
		for f in _rows:
			mean += float(d.get("intensity", {}).get(f, 0)) / _rows.size()
		return float(Net.catalog.get("director", {}).get("patrolPower", 30)) * scale * mean
	var best := 0.0
	for f in by:
		best = maxf(best, float(by[f]) * float(d.get("intensity", {}).get(f, 0)))
	return scale * best


## The ships an armada of the chosen power would have, as the server builds one (destroyers,
## then frigates, then enough corvettes for the rest), and how long it takes from Comae.
func _preview(sid: String) -> void:
	var r: Dictionary = _systems[sid]
	var left := float(r.amount.value)
	var ships := {}
	var defs: Dictionary = Net.catalog.get("ships", {})
	var types := ["destroyer", "frigate", "corvette"].filter(func(id): return defs.has(id))
	for i in types.size():
		var unit := WarInfo.power({types[i]: 1})
		var n := ceili(left / unit - 1e-6) if i == types.size() - 1 else floori(left / unit + 1e-6)
		if n > 0:
			ships[types[i]] = n
			left -= n * unit
	var home := str(WarInfo.factions().get("coma", {}).get("capital", "comae"))
	var jumps := maxi(1, WarInfo.route(home, sid).size() - 1)
	var slowest := INF
	for id in ships:
		slowest = minf(slowest, float(defs[id].get("speed", 1)))
	var travel := "" if slowest == INF else ", flying %s from %s" % [System.format_time(TRAVEL_S / slowest * jumps), WarInfo.system(home).get("name", "Comae")]
	r.preview.text = "That's " + WarInfo.ships_text(ships) + travel + "."


func _pct(v) -> String:
	return "%d%%" % roundi(float(v) * 100.0)
