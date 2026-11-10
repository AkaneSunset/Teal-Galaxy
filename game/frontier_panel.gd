extends Control
## The Frontier: terraforming, a PC loop outside the war (server/frontier.ts). Five pages:
##   clusters     your leased star clusters, their systems and barren planets; lease one, survey a
##                planet (three scans from around its orbit), lease a Terraformer and aim it
##   terraformer  your faction's Terraformers: jump yours a lane at a time, establish it in orbit,
##                buy and fit engines, deliver to a stage's bar, escort the ones of your side
##   colony       your colonies: population, tier, how well crime, services and power are covered,
##                buildings to build, resettling after a collapse, exports to the galactic market
##   trade        every colony's goods: buy at the source, take Hauler missions to other stations
##                and deliver them, an auctioned cluster to lease
##   hunt         intel on other factions' Terraformers: decode a Data shard, scan the system
##                you're in for jump traces and Terraformers, intercept one your side has found
## A fleet carrier can also jump into the Frontier from here (travel, on the hunt page).

const WarInfo := preload("res://war_info.gd")

signal closed
signal jump_requested(system_id: String)

const PAGES := [["clusters", "Clusters"], ["terraformer", "Terraformer"], ["colony", "Colony"], ["trade", "Trade"], ["hunt", "Hunt and travel"]]
const STATE_TEXT := {"leased": "at the shipyard", "voyage": "under way", "orbit": "in orbit, terraforming", "world": "done: a living world", "destroyed": "destroyed", "lapsed": "lease lapsed"}

var colour := Color(0.5, 0.9, 0.6)
var page := "clusters"
var here_system := "teal-prime" # where your carrier is
var can_jump := false # flying your own fleet carrier

var _tabs: HBoxContainer
var _wallet: Label
var _body: VBoxContainer
var _status: Label
var _results: Array = [] # what the last scan, decode or survey said, shown on its page
var _haul_to := "cinder"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.03, 0.03, 0.95)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 40
	col.offset_top = 24
	col.offset_right = -40
	col.offset_bottom = -24
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	var head := Label.new()
	head.text = "THE FRONTIER · TERRAFORMING"
	head.add_theme_font_size_override("font_size", 30)
	col.add_child(head)
	_wallet = Label.new()
	_wallet.add_theme_color_override("font_color", Color(0.75, 0.85, 0.8))
	col.add_child(_wallet)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 8)
	col.add_child(_tabs)
	for p in PAGES:
		var b := Button.new()
		b.text = p[1]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(150, 38)
		var id: String = p[0]
		b.pressed.connect(func(): show_page(id))
		_tabs.add_child(b)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	scroll.add_child(_body)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	col.add_child(_status)
	var close := Button.new()
	close.text = "Close (Esc)"
	close.pressed.connect(func(): closed.emit())
	col.add_child(close)
	Net.state_changed.connect(_on_state_changed)
	Net.message.connect(_on_message)
	Net.server_error.connect(_on_server_error)


func _on_state_changed(_s) -> void:
	if visible:
		refresh()


func _on_server_error(reason) -> void:
	if visible:
		say(str(reason))


func _send(msg: Dictionary) -> void:
	Net.send(msg)
	say("...")


func _send_haul(msg: Dictionary) -> void:
	var m := msg.duplicate()
	m["to"] = _haul_to
	_send(m)


func open(at_system: String, jumpable: bool, first_page := "") -> void:
	here_system = at_system
	can_jump = jumpable
	_status.text = ""
	_results = []
	show_page(first_page if first_page != "" else page)


func show_page(id: String) -> void:
	if id != page:
		_results = []
	page = id
	for i in PAGES.size():
		(_tabs.get_child(i) as Button).button_pressed = PAGES[i][0] == id
	refresh()


func say(text: String) -> void:
	_status.text = text


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("menu")):
		closed.emit()
		get_viewport().set_input_as_handled()


## What the server said back to one of ours: grades, traces, leads, payments.
func _on_message(msg: Dictionary) -> void:
	if str(msg.get("type", "")) != "frontier_result" or not visible:
		return
	match str(msg.get("action", "")):
		"frontier_survey":
			if msg.get("grades") is Dictionary:
				say("Survey complete: %s." % _grades_text(msg.grades))
			else:
				say("Scan logged: %d of 3 points." % int(msg.get("points", 0)))
		"frontier_scan":
			_results = []
			for t in msg.get("traces", []):
				_results.append("A jump trace, %s old: it went to %s." % [_age(float(t.get("age", 0))), _sys_name(str(t.get("to", "")))])
			if not (msg.get("found", []) as Array).is_empty():
				_results.append("An enemy Terraformer is in this system. Your side can intercept it now.")
			if _results.is_empty():
				_results.append("Nothing here: no traces, no Terraformers.")
			say("Scanned %s." % _sys_name(here_system))
		"frontier_decode":
			_results = []
			for l in msg.get("leads", []):
				_results.append("%s has leased a Terraformer for cluster %s%s." % [str(l.get("owner", "")), str(l.get("cluster", "")), ", and it has set off" if bool(l.get("underway", false)) else ", still at the shipyard"])
			if _results.is_empty():
				_results.append("The shard holds nothing on Terraformers.")
			say("Intel decoded.")
		"frontier_deliver":
			say("Delivered %d%s." % [int(msg.get("delivered", 0)), (", paid %d credits" % int(msg.get("paid", 0))) if int(msg.get("paid", 0)) > 0 else ""] if not msg.has("fitted") else "Engine fitted.")
		"frontier_export", "frontier_haul_deliver":
			say("Paid %d credits." % int(msg.get("paid", 0)))
		"frontier_buy":
			say("Bought, for %d credits." % int(msg.get("cost", 0)))
		_:
			say("Done.")
	refresh()


# --- State --------------------------------------------------------------------------------

func _fr() -> Dictionary:
	var f = Net.state.get("frontier", {})
	return f if f is Dictionary else {}


func _me() -> Dictionary:
	return Net.state.get("pilots", {}).get(Net.my_name, {})


func _tun() -> Dictionary:
	return Net.catalog.get("tunables", {}).get("frontier", {})


func _have(item: String) -> int:
	var me := _me()
	return int(me.get("cargo", {}).get(item, 0)) + int(me.get("hold", {}).get(item, 0))


func _clusters(mine_only: bool) -> Array:
	var out: Array = []
	for c in _fr().get("clusters", {}).values():
		if not mine_only or str(c.get("owner", "")) == Net.my_name:
			out.append(c)
	return out


func _ships() -> Array:
	return _fr().get("ships", {}).values()


## Any system's name: the war map's, a Frontier region's, or a leased cluster's.
func _sys_name(id: String) -> String:
	var s := WarInfo.system(id)
	if not s.is_empty():
		return str(s.get("name", id))
	for r in _fr().get("regions", {}).values():
		if r.get("names", {}).has(id):
			return str(r.names[id])
	for c in _clusters(false):
		for sys in c.get("systems", []):
			if str(sys.id) == id:
				return str(sys.name)
	return id


func _planet_name(c: Dictionary, planet_id: String) -> String:
	for sys in c.get("systems", []):
		for p in sys.get("planets", []):
			if str(p.id) == planet_id:
				return str(p.name)
	return planet_id


## The systems one jump from `id`, as the server counts them: war-map lanes, the regions' links,
## and each leased cluster's chain off its anchor.
func neighbours(id: String) -> Array:
	var out: Array = []
	for l in WarInfo.system(id).get("lanes", []):
		out.append(str(l))
	for r in _fr().get("regions", {}).values():
		for n in r.get("links", {}).get(id, []):
			if not out.has(str(n)):
				out.append(str(n))
	for c in _clusters(false):
		var ids: Array = c.get("systems", []).map(func(s): return str(s.id))
		if ids.is_empty():
			continue
		var k := ids.find(id)
		if id == str(c.get("anchor", "")):
			out.append(ids[0])
		if k == 0:
			out.append(str(c.get("anchor", "")))
		if k > 0:
			out.append(ids[k - 1])
		if k >= 0 and k < ids.size() - 1:
			out.append(ids[k + 1])
	return out


func _age(ms: float) -> String:
	var h := ms / 3600_000.0
	return "%d min" % int(h * 60.0) if h < 1.0 else "%.1f h" % h


func _until(at_ms: float) -> String:
	var left := at_ms - Net.now_ms()
	if left <= 0.0:
		return "now"
	var h := left / 3600_000.0
	return "%d min" % ceili(h * 60.0) if h < 1.0 else ("%.1f h" % h if h < 48.0 else "%.1f days" % (h / 24.0))


func _grades_text(g: Dictionary) -> String:
	return "size %d, core %d, ice %d, atmosphere %d" % [int(g.get("size", 0)), int(g.get("core", 0)), int(g.get("ice", 0)), int(g.get("atmosphere", 0))]


func _item(id: String) -> String:
	if id.begins_with("engine_"):
		return str(Net.catalog.get("frontier", {}).get("engines", {}).get(id.substr(7), id))
	if id == "ice":
		return "Ice"
	return Net.item_name(id)


# --- Building blocks ----------------------------------------------------------------------------

func _clear() -> void:
	for c in _body.get_children():
		c.queue_free()


func _heading(text: String, tint := Color.WHITE) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", tint)
	_body.add_child(l)


func _note(text: String, tint := Color(1, 1, 1, 0.7), into: Control = null) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", tint)
	(into if into != null else _body).add_child(l)


func _button(text: String, msg: Dictionary, into: Control = null, enabled := true) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(_send.bind(msg))
	(into if into != null else _body).add_child(b)
	return b


func _row() -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 8)
	_body.add_child(r)
	return r


func refresh() -> void:
	if Net.state.is_empty():
		return
	_wallet.text = "%s · %d credits%s" % [Net.my_name, int(_me().get("credits", 0)), "" if WarInfo.my_faction() != "" else " · choose a faction to lease Frontier space"]
	_clear()
	match page:
		"clusters":
			_page_clusters()
		"terraformer":
			_page_terraformer()
		"colony":
			_page_colony()
		"trade":
			_page_trade()
		"hunt":
			_page_hunt()


# --- Clusters -----------------------------------------------------------------------------------

func _page_clusters() -> void:
	var t := _tun()
	_note("Your faction claims a region of Frontier space. A star cluster of 5 to 10 systems is a one-off lease, yours for good unless you sell it back or its colony collapses.")
	_button("Lease a star cluster (%d credits)" % int(t.get("clusterLease", 0)), {"type": "frontier_lease_cluster"}, null, WarInfo.my_faction() != "")
	var mine := _clusters(true)
	if mine.is_empty():
		_note("You have no star clusters yet.")
	for c in mine:
		var cid := str(c.id)
		var ship := _ship_for(cid)
		_heading("Cluster %s · %d systems%s" % [cid, (c.get("systems", []) as Array).size(), " · a living world" if c.get("colony") is Dictionary else ""], colour)
		if ship.is_empty() and not (c.get("colony") is Dictionary):
			_button("Lease a Terraformer for this cluster (%d credits)" % int(t.get("shipLease", 0)), {"type": "frontier_lease_ship", "cluster": cid})
		for sys in c.get("systems", []):
			_note("%s" % str(sys.name), Color(0.8, 0.95, 0.9))
			for p in sys.get("planets", []):
				_planet_row(c, ship, p)
		if ship.is_empty():
			_button("Sell this cluster back to the faction (nothing is paid back)", {"type": "frontier_sell_back", "cluster": cid})


func _ship_for(cluster_id: String) -> Dictionary:
	for s in _ships():
		if str(s.get("cluster", "")) == cluster_id and str(s.get("owner", "")) == Net.my_name and ["leased", "voyage", "orbit"].has(str(s.get("state", ""))):
			return s
	return {}


func _planet_row(c: Dictionary, ship: Dictionary, p: Dictionary) -> void:
	var pid := str(p.id)
	var survey: Dictionary = c.get("surveys", {}).get(pid, {})
	var row := _row()
	_note("    %s, %s" % [str(p.name), str(p.kind)], Color(1, 1, 1, 0.85), row)
	if not survey.is_empty():
		_note("· %s · surveyed by %s" % [_grades_text(survey.grades), str(survey.by)], Color(0.7, 1.0, 0.75), row)
		if not ship.is_empty() and ["leased", "voyage"].has(str(ship.state)) and str(ship.get("target", "")) != pid:
			_button("Aim the Terraformer here", {"type": "frontier_target", "ship": int(ship.id), "planet": pid}, row)
		elif str(ship.get("target", "")) == pid:
			_note("· the Terraformer's target", colour, row)
		return
	var done: Array = c.get("scans", {}).get(pid, {}).get("points", [])
	for k in 3:
		_button("Scan point %d%s" % [k + 1, " ✓" if done.has(k) else ""], {"type": "frontier_survey", "cluster": str(c.id), "planet": pid, "point": k}, row, not done.has(k))


# --- Terraformer -------------------------------------------------------------------------------

func _page_terraformer() -> void:
	var mine := WarInfo.my_faction()
	var any := false
	for s in _ships():
		if str(s.get("faction", "")) != mine or ["destroyed", "lapsed", "world"].has(str(s.get("state", ""))) and str(s.get("owner", "")) != Net.my_name:
			continue
		any = true
		_ship_block(s)
	if not any:
		_note("No Terraformers. Lease one for a cluster on the Clusters page.")


func _ship_block(s: Dictionary) -> void:
	var t := _tun()
	var id := int(s.id)
	var owner := str(s.owner)
	var mine := owner == Net.my_name
	var state := str(s.state)
	var c: Dictionary = _fr().get("clusters", {}).get(str(s.cluster), {})
	_heading("%s's Terraformer · cluster %s · %s" % [owner, str(s.cluster), STATE_TEXT.get(state, state)], colour)
	if s.get("interception") is Dictionary:
		_note("UNDER ATTACK: %s is intercepting it." % WarInfo.the(s.interception.faction), Color(1.0, 0.45, 0.4))
	if ["leased", "voyage"].has(state):
		_note("At %s. Target: %s. %d escorts." % [_sys_name(str(s.at)), _planet_name(c, str(s.target)) + " in " + _sys_name(str(s.targetSystem)) if s.get("target") != null else "none yet (pick a surveyed planet on the Clusters page)", (s.get("escorts", []) as Array).size()])
		_note("Renewal fee of %d credits in %s unless it's established in orbit by then." % [int(t.get("renewalFee", 0)), _until(float(s.dueAt))], Color(1.0, 0.85, 0.55))
		if mine and s.get("target") != null:
			var ready := float(s.get("jumpReadyAt", 0)) <= Net.now_ms()
			if str(s.at) == str(s.targetSystem):
				_button("Establish it in orbit: the start point, and the system's permanent hub", {"type": "frontier_establish", "ship": id})
			elif not ready:
				_note("The jump drive is cooling down: next jump in %s." % _until(float(s.jumpReadyAt)))
			var row := _row()
			for n in s.get("next", []):
				var label := "Jump to %s%s" % [_sys_name(str(n)), " (target)" if str(n) == str(s.targetSystem) else ""]
				_button(label, {"type": "frontier_jump", "ship": id, "system": str(n)}, row, ready)
			_note("Each jump leaves a trace for %d hours that shows enemy scanners which lane it took." % int(t.get("traceHours", 0)), Color(1, 1, 1, 0.5))
	elif state == "orbit":
		var stages: Array = Net.catalog.get("frontier", {}).get("stages", ["atmosphere", "water", "biosphere"])
		var stage := str(stages[int(s.stage)]) if int(s.stage) < stages.size() else ""
		var hours: float = float(t.get("stageHours", {}).get(stage, 0))
		var ends := float(s.stageStartedAt) + hours * 3600_000.0 * (1.0 / 336.0 if Net.catalog.get("carrier", false) else 1.0)
		_note("Over %s in %s. Stage %d of 3: %s (at least until %s from now)." % [_planet_name(c, str(s.target)), _sys_name(str(s.at)), int(s.stage) + 1, stage, _until(ends)])
		var engine := "engine_" + stage
		var has_engine: bool = (s.get("engines", []) as Array).has(stage)
		if not has_engine:
			_note("Needs the %s." % _item(engine), Color(1.0, 0.8, 0.5))
			if _have(engine) > 0:
				_button("Fit the %s" % _item(engine), {"type": "frontier_deliver", "ship": id, "item": engine, "qty": 1})
			elif mine:
				_button("Buy the %s at the shipyard (%d credits)" % [_item(engine), int(t.get("enginePrice", 0))], {"type": "frontier_engine", "ship": id, "stage": stage})
		var needs: Dictionary = s.get("needs", {})
		for item in needs:
			var want := int(needs[item])
			var have := _have(str(item))
			var row := _row()
			_note("%s: %d more%s" % [_item(str(item)), want, "" if want > 0 else " (full)"], Color(1, 1, 1, 0.85), row)
			if want > 0 and have > 0:
				var n := mini(want, have)
				_button("Deliver %d%s" % [n, "" if mine else " (paid by %s)" % owner], {"type": "frontier_deliver", "ship": id, "item": str(item), "qty": n}, row, has_engine)
	elif state == "world":
		_note("Its world is finished: see the Colony page.")
	if not mine and ["leased", "voyage"].has(state):
		var escorting := (s.get("escorts", []) as Array).has(Net.my_name)
		_button("Stop escorting" if escorting else "Escort it (adds to its defence in an interception)", {"type": "frontier_escort", "ship": id, "on": not escorting})


# --- Colony -------------------------------------------------------------------------------------

func _page_colony() -> void:
	var any := false
	for c in _clusters(true):
		if c.get("colony") is Dictionary:
			any = true
			_colony_block(c)
	if not any:
		_note("No colonies yet: a Terraformer's third stage makes one.")


func _colony_block(c: Dictionary) -> void:
	var col: Dictionary = c.colony
	var cid := str(c.id)
	var cat: Dictionary = Net.catalog.get("frontier", {}).get("buildings", {})
	var pop := int(col.get("pop", 0))
	_heading("%s · population %d · tier %d" % [_planet_name(c, str(col.planet)), pop, int(col.get("tier", 0))], colour)
	if col.get("collapseAt") != null:
		_note("COLLAPSED. Resettle it within %s or the cluster goes to auction." % _until(float(col.collapseAt)), Color(1.0, 0.45, 0.4))
		_button("Resettle (%d credits)" % int(_tun().get("colony", {}).get("resettleCost", 0)), {"type": "frontier_resettle", "cluster": cid})
	# How well each need is covered, the way the server counts it.
	var cover := {"crime": 0, "services": 0, "power": 0}
	var housing := 0
	for k in cat:
		var b: Dictionary = cat[k]
		var n := int(col.get("buildings", {}).get(k, 0))
		if b.has("covers"):
			cover[str(b.covers)] += n * int(b.per)
		housing += n * int(b.get("houses", 0))
	var parts: Array = []
	for need in cover:
		var share := 1.0 if pop <= 0 else minf(1.0, float(cover[need]) / float(pop))
		parts.append("%s %d%%" % [need, roundi(share * 100.0)])
	_note("Covered: %s · housing for %d · exports boosted %d%% by Hauler missions" % [", ".join(parts), housing, roundi(float(col.get("boost", 0)) * 100.0)], Color(0.8, 0.95, 0.85))
	_note("A need below 100% and the population shrinks; all covered, it grows to its housing.", Color(1, 1, 1, 0.5))
	for k in cat:
		var b: Dictionary = cat[k]
		var row := _row()
		var what: String = ("covers %s for %d" % [b.covers, int(b.per)]) if b.has("covers") else (("houses %d" % int(b.houses)) if b.has("houses") else "makes %s" % _item(str(b.get("makes", ""))))
		_note("%s ×%d · %s" % [str(b.name), int(col.get("buildings", {}).get(k, 0)), what], Color(1, 1, 1, 0.85), row)
		var open := int(col.get("tier", 0)) >= int(b.tier)
		_button(("Build (%d credits)" % int(b.cost)) if open else "Unlocks at tier %d" % int(b.tier), {"type": "frontier_build", "cluster": cid, "building": str(k)}, row, open)
	var stock: Dictionary = col.get("stock", {})
	if stock.is_empty():
		_note("Nothing in stock yet.")
	for item in stock:
		var n := int(stock[item])
		if n <= 0:
			continue
		var row := _row()
		_note("%s: %d" % [_item(str(item)), n], Color(1, 1, 1, 0.85), row)
		_button("Export all to the galactic market", {"type": "frontier_export", "cluster": cid, "item": str(item), "qty": n}, row)


# --- Trade --------------------------------------------------------------------------------------

func _page_trade() -> void:
	_note("Colonies sell what they make to pilots who fly there. A Hauler mission carries goods to a contested world's orbital station, where they sell at full value: half to you, half to the Founder.")
	var dest := OptionButton.new()
	var planets: Array = WarInfo.war().get("planets", []).filter(func(p): return not bool(p.get("capital", false)))
	for i in planets.size():
		dest.add_item(str(planets[i].name))
		if str(planets[i].id) == _haul_to:
			dest.select(i)
	dest.item_selected.connect(func(i): _haul_to = str(planets[i].id))
	var drow := _row()
	_note("Haul to:", Color(1, 1, 1, 0.85), drow)
	drow.add_child(dest)
	for c in _clusters(false):
		if c.get("auction") is Dictionary and str(c.get("faction", "")) == WarInfo.my_faction():
			_button("Cluster %s is at auction: lease it for %d credits (ruins and all)" % [str(c.id), int(c.auction.price)], {"type": "frontier_auction_buy", "cluster": str(c.id)})
		if not (c.get("colony") is Dictionary):
			continue
		var stock: Dictionary = c.colony.get("stock", {})
		_heading("%s's colony, cluster %s" % [str(c.owner), str(c.id)], WarInfo.faction_color(c.get("faction")))
		for item in stock:
			var n := int(stock[item])
			if n <= 0:
				continue
			var row := _row()
			_note("%s: %d" % [_item(str(item)), n], Color(1, 1, 1, 0.85), row)
			_button("Buy %d" % mini(10, n), {"type": "frontier_buy", "cluster": str(c.id), "item": str(item), "qty": mini(10, n)}, row)
			var haul := Button.new()
			haul.text = "Haul %d" % mini(20, n)
			var msg := {"type": "frontier_haul", "cluster": str(c.id), "item": str(item), "qty": mini(20, n)}
			haul.pressed.connect(_send_haul.bind(msg))
			row.add_child(haul)
	var missions: Array = _fr().get("missions", []).filter(func(m): return str(m.get("pilot", "")) == Net.my_name)
	if not missions.is_empty():
		_heading("Your Hauler missions")
	for m in missions:
		var row := _row()
		_note("%d %s to %s" % [int(m.qty), _item(str(m.item)), str(WarInfo.planet(str(m.to)).get("name", m.to))], Color(1, 1, 1, 0.85), row)
		_button("Deliver (at its orbital station)", {"type": "frontier_haul_deliver", "mission": int(m.id)}, row)


# --- Hunt and travel ----------------------------------------------------------------------------

func _page_hunt() -> void:
	var mine := WarInfo.my_faction()
	_heading("Your carrier is at %s" % _sys_name(here_system), colour)
	if can_jump:
		var row := _row()
		for n in neighbours(here_system):
			if str(n).begins_with("fr-") or here_system.begins_with("fr-"):
				var b := Button.new()
				b.text = "Jump to %s" % _sys_name(str(n))
				var to := str(n)
				b.pressed.connect(func(): jump_requested.emit(to))
				row.add_child(b)
		_note("The Frontier opens off Marrow Reach and The Drift; the galaxy map jumps you there first.", Color(1, 1, 1, 0.5))
	else:
		_note("Only a fleet carrier's captain jumps it, from aboard.", Color(1, 1, 1, 0.5))
	_button("Scan this system for jump traces and Terraformers", {"type": "frontier_scan"})
	for r in _results:
		_note("  " + str(r), Color(0.75, 0.95, 1.0))
	var shards := 0
	for it in _me().get("stash", []):
		if ["shard", "dossier"].has(str(it.get("item", ""))):
			shards += int(it.get("qty", 1))
	_heading("Intel")
	_note("Decoding a Data shard or Security dossier from your raids names a faction's leased Terraformers, never where they are. You have %d." % shards)
	var row2 := _row()
	for f in WarInfo.player_factions():
		if str(f) != mine:
			_button("Decode on %s" % WarInfo.faction_name(f), {"type": "frontier_decode", "faction": str(f)}, row2, shards > 0)
	_heading("Enemy Terraformers your side has found")
	var found := false
	for s in _ships():
		if str(s.get("faction", "")) == mine:
			continue
		found = true
		var row := _row()
		_note("%s's, %s, at %s, %d escorts%s" % [str(s.owner), WarInfo.the(s.faction), _sys_name(str(s.at)), int(s.get("escorts", 0)), " · under attack" if s.get("interception") is Dictionary else ""], WarInfo.faction_color(s.faction), row)
		_button("Intercept", {"type": "frontier_intercept", "ship": int(s.id)}, row, str(s.at) == here_system and not (s.get("interception") is Dictionary))
	if not found:
		_note("None. Scan the systems where traces lead.")
