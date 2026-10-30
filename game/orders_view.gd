extends VBoxContainer
## Your faction's orders from its High Command (server/orders.js), as the HIGH COMMAND terminal on a
## carrier, the War terminal and the Builder's War screen show them: the operation, its three orders
## (won, failed, running, to come), the running order's briefing and tasks with their progress, the
## deadline and reward, your own part in it, and the archive of past operations.
## Call show_for(state, faction, me) whenever the state changes (and every second or so, for the clock).
## Orders are secret: you see your own faction's, and an enemy's running order only once your
## Builders' intelligence has revealed it (Intelligence, below). A Builder (`builder` true) can supply
## intelligence there, or sell it.

const WarInfo := preload("res://war_info.gd")

var _archive := false
var _key := ""
## A Builder's view: with the controls to supply intelligence (or sell it).
var builder := false


func _init() -> void:
	add_theme_constant_override("separation", 8)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _label(text: String, size := 16, colour := Color(0.88, 0.92, 0.96), wrap := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(l)
	return l


func _time(ms: float) -> String:
	var s := maxi(0, int(ms / 1000.0))
	if s >= 86400:
		return "%dd %dh" % [s / 86400, (s % 86400) / 3600]
	if s >= 3600:
		return "%dh %02dm" % [s / 3600, (s % 3600) / 60]
	return "%d:%02d" % [s / 60, s % 60]


## The orders of the operation running, for `faction` (a faction id; "" before choosing one).
func show_for(state: Dictionary, faction: String, me: String) -> void:
	var orders: Dictionary = state.get("war", {}).get("orders", {}) if state.get("war") is Dictionary else {}
	var stock: Dictionary = state.get("bases", {}).get(me, {}).get("stock", {}) if builder else {}
	var key := JSON.stringify([orders, faction, _archive, int(Net.now_ms() / 1000.0), stock.get("shard", 0), stock.get("dossier", 0)])
	if key == _key:
		return
	_key = key
	for c in get_children():
		c.free()
	var head := HBoxContainer.new()
	add_child(head)
	var title := Label.new()
	title.text = "ORDERS ARCHIVE" if _archive else "HIGH COMMAND ORDERS"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var flip := Button.new()
	flip.text = "Current orders" if _archive else "Archive"
	flip.pressed.connect(func():
		_archive = not _archive
		_key = ""
		show_for.call_deferred(state, faction, me)) # deferred: this button is rebuilt too
	head.add_child(flip)
	if _archive:
		_show_archive(orders.get("archive", []), faction)
		return
	if faction == "" or not ["compact", "ashen", "luminar"].has(faction):
		_label("Choose a faction to take its orders.")
		return
	var op: Dictionary = orders.get("op", {}) if orders.get("op") is Dictionary else {}
	if op.is_empty():
		_label("No operation yet: High Command is drawing up its plans.")
		return
	var rec: Dictionary = op.get("factions", {}).get(faction, {})
	var now := Net.now_ms()
	_label("%s   ·   %s left   ·   orders won %d of 3 (win 2 for the operation)" % [str(op.get("name", "")), _time(float(op.endsAt) - now), int(rec.get("won", 0))], 18, WarInfo.faction_color(faction).lightened(0.3))
	var list: Array = rec.get("orders", []).duplicate()
	list.append_array(op.get("coma", []))
	list.sort_custom(func(a, b): return int(a.slot) < int(b.slot))
	# The three slots: done, running, to come.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	add_child(row)
	for slot in 3:
		var o: Dictionary = {}
		for x in list:
			if int(x.slot) == slot:
				o = x
		var l := Label.new()
		var state_text := "to come"
		var col := Color(0.6, 0.65, 0.7)
		if not o.is_empty():
			match str(o.status):
				"won":
					state_text = "won"
					col = Color(0.45, 1.0, 0.6)
				"failed":
					state_text = "failed"
					col = Color(1.0, 0.45, 0.38)
				_:
					state_text = "running"
					col = Color(1.0, 0.85, 0.4)
		l.text = "Order %d: %s%s" % [slot + 1, state_text, "" if o.is_empty() else "\n" + str(o.title)]
		l.add_theme_color_override("font_color", col)
		row.add_child(l)
	var running := list.filter(func(x): return str(x.status) == "active")
	if running.is_empty():
		_label("No order running right now. The next comes with the next slot.")
	for o in running:
		_show_order(o, faction, me, now)
	# The ones done this operation.
	for o in list:
		if str(o.status) != "active":
			_label("%s: \"%s\" %s. %s" % [str(o.issuer), str(o.title), "accomplished" if str(o.status) == "won" else "failed", str(o.get("outcome", ""))], 14, Color(0.75, 0.8, 0.85))
	_show_intel(orders, op, faction, stock, now)


## What intelligence has revealed of the enemy's orders, and (for a Builder) supplying more.
func _show_intel(orders: Dictionary, op: Dictionary, faction: String, stock: Dictionary, now: float) -> void:
	_label("INTELLIGENCE", 20, Color(0.75, 0.85, 1.0))
	_label("Enemy orders are secret. Builders' intelligence (Data shards, Security dossiers) reveals an enemy's running order until its deadline: %d intelligence a reveal." % 300, 14, Color(0.7, 0.76, 0.82))
	var intel: Dictionary = orders.get("intel", {})
	for f in ["compact", "ashen", "luminar"]:
		if f == faction:
			continue
		var rec: Dictionary = op.get("factions", {}).get(f, {})
		if rec.get("intel", false):
			for o in rec.get("orders", []):
				_label("%s's running order (deadline in %s):" % [WarInfo.faction_name(f), _time(float(o.endsAt) - now)], 16, WarInfo.faction_color(f).lightened(0.2))
				_label("\"%s\": %s" % [str(o.title), str(o.briefing)], 14, Color(0.85, 0.88, 0.92))
				for t in o.get("tasks", []):
					var have := "   %d / %d" % [int(t.get("have", 0)), int(t.get("need", 1))] if str(t.type) in ["wins", "donate", "coma_wins"] else ""
					_label(("✓ " if bool(t.get("done", false)) else "• ") + str(t.get("label", t.type)) + have, 14, Color(0.8, 0.84, 0.9))
		else:
			var p: Dictionary = intel.get(f, {})
			_label("%s: unknown%s" % [WarInfo.faction_name(f), ("   (%d of %d intelligence gathered)" % [int(p.points), int(p.of)]) if not p.is_empty() else ""], 15, Color(0.7, 0.74, 0.8))
		if builder:
			var row := HBoxContainer.new()
			add_child(row)
			for item in [["shard", "Data shard", 300], ["dossier", "Security dossier", 650]]:
				var b := Button.new()
				var have := int(stock.get(item[0], 0))
				b.text = "Spy on the %s: a %s (%d) · you have %d" % [WarInfo.faction_name(f).get_slice(" ", 1 if f == "compact" else 0), item[1], item[2], have]
				b.disabled = have <= 0 or rec.get("intel", false)
				var target: String = f
				var it: String = item[0]
				b.pressed.connect(func(): Net.send({"type": "intel_supply", "target": target, "item": it}))
				row.add_child(b)
	if builder:
		var sell := HBoxContainer.new()
		add_child(sell)
		for item in [["shard", "Data shard", 300], ["dossier", "Security dossier", 650]]:
			var b := Button.new()
			b.text = "Sell a %s (%d credits)" % [item[1], item[2]]
			b.disabled = int(stock.get(item[0], 0)) <= 0
			var it: String = item[0]
			b.pressed.connect(func(): Net.send({"type": "intel_sell", "item": it}))
			sell.add_child(b)


func _show_order(o: Dictionary, faction: String, me: String, now: float) -> void:
	var coma := str(o.get("kind", "")) == "coma"
	_label("%s%s" % ["ALL FACTIONS · " if coma else "", str(o.issuer).to_upper()], 14, Color(1.0, 0.5, 0.42) if coma else WarInfo.faction_color(faction))
	_label(str(o.title), 24, Color.WHITE)
	_label(str(o.briefing), 15, Color(0.82, 0.86, 0.9))
	for t in o.get("tasks", []):
		var box := VBoxContainer.new()
		add_child(box)
		var l := Label.new()
		var done := bool(t.get("done", false))
		var type := str(t.type)
		var status := ""
		if type in ["wins", "donate", "coma_wins"]:
			status = "   %d / %d" % [int(t.get("have", 0)), int(t.get("need", 1))]
		elif t.get("standing") != null:
			status = "   (%s leads now)" % WarInfo.faction_name(t.standing)
		else:
			status = "   (nobody leads yet)"
		l.text = ("✓ " if done else "• ") + str(t.get("label", type)) + status
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6) if done else Color(0.92, 0.94, 0.96))
		box.add_child(l)
		if type in ["wins", "donate", "coma_wins"]:
			var bar := ProgressBar.new()
			bar.max_value = maxf(1.0, float(t.get("need", 1)))
			bar.value = float(t.get("have", 0))
			bar.show_percentage = false
			bar.custom_minimum_size = Vector2(0, 10)
			box.add_child(bar)
	var mine := int(o.get("contrib", {}).get(me, 0))
	var everyone := (o.get("contrib", {}) as Dictionary).size()
	_label("Deadline in %s   ·   Reward if won: %d credits to everyone who took part, and %d to every member" % [_time(float(o.endsAt) - now), int(o.get("reward", 250)), 50], 15, Color(1.0, 0.85, 0.5))
	_label("Your part: %s   ·   %d %s taken part so far" % [("%d (wins, or donations by the 10 War Merit)" % mine) if mine > 0 else "nothing yet", everyone, "has" if everyone == 1 else "have"], 15, Color(0.6, 0.9, 1.0))


func _show_archive(archive: Array, faction: String) -> void:
	if archive.is_empty():
		_label("No operation has ended yet.")
		return
	for op in archive:
		var f: Dictionary = op.get("factions", {}).get(faction, {}) if faction != "" else {}
		_label("%s: %s" % [str(op.get("name", "")), ("%s, %d of 3 orders won" % ["won" if str(f.get("status", "")) == "won" else "failed", int(f.get("won", 0))]) if not f.is_empty() else ""], 18, Color(0.9, 0.92, 0.95))
		var fac: Dictionary = op.get("factions", {})
		var parts: Array = []
		for k in fac:
			parts.append("%s %d/3" % [WarInfo.faction_name(k), int(fac[k].get("won", 0))])
		_label("   " + "   ·   ".join(parts), 14, Color(0.7, 0.75, 0.8))
		for o in f.get("orders", []):
			_label("   %s \"%s\": %s" % ["✓" if str(o.status) == "won" else "✗", str(o.title), str(o.get("outcome", ""))], 14, Color(0.78, 0.82, 0.86))
