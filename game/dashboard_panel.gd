extends Control
## The server dashboard, for the galaxy's admins: a page of the War terminal (war_panel.gd), next to
## the Coma director. While it's open it asks the server for `admin_dashboard` every few seconds and
## shows what comes back: who's online and how they signed in, every front (campaign points, pilots
## there and in its matches, war supply by faction with its rate over the last hour), the server's
## loops against their tick budget, and telemetry's alerts and latest events (telemetry.ts).

const WarInfo := preload("res://war_info.gd")
const ASK_S := 3.0 # how often to ask while the page is open

var colour := Color(0.35, 0.95, 0.88)

var _head: Label
var _ticks: Label
var _fronts: VBoxContainer
var _alerts: Label
var _events: Label
var _wait := 0.0
var _last: Dictionary = {}


func _ready() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	scroll.add_child(col)
	var title := Label.new()
	title.text = "Server dashboard"
	title.add_theme_font_size_override("font_size", 24)
	col.add_child(title)
	_head = _text(col, "Asking the server...")
	col.add_child(_heading("Fronts"))
	_fronts = VBoxContainer.new()
	_fronts.add_theme_constant_override("separation", 6)
	col.add_child(_fronts)
	col.add_child(_heading("Loops (p99 against the tick budget)"))
	_ticks = _text(col, "")
	col.add_child(_heading("Alerts"))
	_alerts = _text(col, "")
	col.add_child(_heading("Latest events"))
	_events = _text(col, "")
	_events.add_theme_font_size_override("font_size", 13)
	Net.message.connect(func(msg):
		if msg.get("type", "") == "dashboard":
			_last = msg
			_show(msg))


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		_wait = 0.0
		return
	_wait -= delta
	if _wait <= 0.0:
		_wait = ASK_S
		Net.send({"type": "admin_dashboard"})


## The dashboard's latest answer from the server ({} before the first).
func last() -> Dictionary:
	return _last


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", colour)
	return l


func _text(parent: Node, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 15)
	parent.add_child(l)
	return l


func _ms_text(ms: float) -> String:
	var m := maxi(0, int(ms / 60000.0))
	if m >= 1440:
		return "%dd %dh" % [m / 1440, (m % 1440) / 60]
	if m >= 60:
		return "%dh %02dm" % [m / 60, m % 60]
	return "%dm" % m


func _show(d: Dictionary) -> void:
	var on: Dictionary = d.get("online", {})
	_head.text = "Online: %d pilots and %d Builders, on %d accounts and %d as guests. Sign-in is %s on this server." % [int(on.get("pilots", 0)), int(on.get("builders", 0)), int(on.get("accounts", 0)), int(on.get("guests", 0)), str(d.get("signIn", "?"))]
	var mult: Dictionary = d.get("multipliers", {})
	var m := []
	for f in mult:
		m.append("%s x%.2f" % [WarInfo.faction_name(f), float(mult[f])])
	if not m.is_empty():
		_head.text += "\nUnderdog multipliers on war supply: " + ", ".join(m)

	for c in _fronts.get_children():
		c.queue_free()
	for f in d.get("fronts", []):
		var pts := []
		for k in f.get("points", {}):
			pts.append("%s %s" % [WarInfo.faction_name(k), WarInfo._num(float(f.points[k]))])
		var matches := []
		for mode in f.get("inMatches", {}):
			matches.append("%d in %s" % [int(f.inMatches[mode]), Net.catalog.get("campaign", {}).get("modes", {}).get(mode, {}).get("name", mode)])
		var supply := []
		var by: Dictionary = (f.get("supply") if f.get("supply") is Dictionary else {}).get("factions", {})
		for k in by:
			supply.append("%s %s (%s an hour)" % [WarInfo.faction_name(k), WarInfo._num(float(by[k].get("total", 0))), WarInfo._num(float(by[k].get("perHour", 0)))])
		var l := _text(_fronts, "%s, held by %s, ends in %s.  Points: %s.\n    Pilots over it %d, queued %d%s.  War supply: %s." % [
			f.get("name", f.get("planet", "")), WarInfo.faction_name(f.get("holder")), _ms_text(float(f.get("endsAt", 0)) - float(d.get("at", 0))),
			", ".join(pts) if not pts.is_empty() else "none", int(f.get("over", 0)), int(f.get("queued", 0)),
			(", " + ", ".join(matches)) if not matches.is_empty() else "", ", ".join(supply) if not supply.is_empty() else "none yet"])
		l.add_theme_color_override("font_color", WarInfo.faction_color(f.get("holder")).lightened(0.35))

	var tel: Dictionary = d.get("telemetry", {})
	var loops := []
	var ticks: Dictionary = tel.get("ticks", {})
	for loop in ticks:
		var t: Dictionary = ticks[loop]
		loops.append("%s: p50 %.1f ms, p99 %.1f ms, max %.1f ms over %d ticks%s%s" % [loop, float(t.get("p50", 0)), float(t.get("p99", 0)), float(t.get("max", 0)), int(t.get("n", 0)),
			"  OVER BUDGET" if t.get("over", false) else "", "  (this window so far)" if t.get("filling", false) else ""])
	_ticks.text = "\n".join(loops) if not loops.is_empty() else "No loop has ticked yet."
	var alerts := []
	for a in tel.get("alerts", []).slice(-10):
		alerts.append("%s ago: %s" % [_ms_text(float(d.get("at", 0)) - float(a.get("at", 0))), a.get("text", "")])
	_alerts.text = "\n".join(alerts) if not alerts.is_empty() else "None."
	_alerts.add_theme_color_override("font_color", Color(1.0, 0.62, 0.15) if not alerts.is_empty() else Color(1, 1, 1, 0.7))
	var events := []
	for e in tel.get("events", []).slice(-15):
		if e.get("kind", "") == "tick":
			continue
		var bits := []
		for k in ["account", "character", "planet", "faction", "source", "credited", "capped", "reason", "text"]:
			if e.has(k) and e[k] != null:
				bits.append("%s %s" % [k, str(e[k])])
		events.append("%s  %s" % [e.get("kind", ""), ", ".join(bits)])
	events.reverse()
	_events.text = "\n".join(events) if not events.is_empty() else "None yet."
