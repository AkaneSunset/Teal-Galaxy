extends Control
## Builder mode (phone): build on planet slots, post jobs, watch explorer activity.
## Facilities fill vaults with goods to ship home; Explorers can raid them, and the Builder
## watches the raid live and can sound the alarm.

const BUILDING_INFO := {
	"mine": {"name": "Mine", "cost": "10 metal"},
	"habitat": {"name": "Habitat", "cost": "20 metal"},
	"spaceport": {"name": "Spaceport", "cost": "30 metal"},
	"hydroponics": {"name": "Hydroponics", "cost": "20 metal, 10 ice"},
	"refinery": {"name": "Mining Refinery", "cost": "40 metal"},
	"lab": {"name": "Research Outpost", "cost": "30 metal, 10 ice"},
	"spire": {"name": "Data Spire", "cost": "50 metal, 150 credits"},
}
const JOB := {"resource": "ice", "amount": 10, "reward": 100}

var _header: Label
var _status: Label
var _slots: GridContainer
var _post_job: Button
var _jobs: Label
var _feed: Label
var _chat_log: Label
var _chat_lines := []
var _menu: PopupMenu
var _menu_slot := -1
var _fac_box: VBoxContainer
var _fac_slot := -1 # the facility shown in the panel, or -1
var _raids: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	scroll.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	_header = _label(col, 22)
	_status = _label(col, 14)
	_label(col, 16).text = "Planet Aster"
	_slots = GridContainer.new()
	_slots.columns = 2
	_slots.add_theme_constant_override("h_separation", 8)
	_slots.add_theme_constant_override("v_separation", 8)
	col.add_child(_slots)

	# The facility tapped in the grid above: its vault, security and any raid in progress.
	_fac_box = VBoxContainer.new()
	_fac_box.add_theme_constant_override("separation", 6)
	_fac_box.visible = false
	col.add_child(_fac_box)

	_post_job = Button.new()
	_post_job.text = "Post job: deliver %d %s for %d credits" % [JOB.amount, JOB.resource, JOB.reward]
	_post_job.pressed.connect(func(): Net.send({"type": "post_job", "resource": JOB.resource, "amount": JOB.amount, "reward": JOB.reward}))
	col.add_child(_post_job)

	_label(col, 16).text = "Jobs"
	_jobs = _label(col, 14)
	_label(col, 16).text = "Raids"
	_raids = _label(col, 14)
	_label(col, 16).text = "Activity"
	_feed = _label(col, 13)
	_feed.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Chat with pilots in flight.
	_label(col, 16).text = "Chat"
	_chat_log = _label(col, 13)
	var chat_row := HBoxContainer.new()
	col.add_child(chat_row)
	var chat_edit := LineEdit.new()
	chat_edit.placeholder_text = "Message pilots"
	chat_edit.max_length = 200
	chat_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_row.add_child(chat_edit)
	var send := Button.new()
	send.text = "Send"
	chat_row.add_child(send)
	var send_chat := func(_text = ""):
		if chat_edit.text.strip_edges() != "":
			Net.send({"type": "chat", "text": chat_edit.text})
		chat_edit.text = ""
	send.pressed.connect(send_chat)
	chat_edit.text_submitted.connect(send_chat)
	Net.chat_received.connect(_on_chat)

	_menu = PopupMenu.new()
	_menu.id_pressed.connect(_on_build_chosen)
	add_child(_menu)

	Net.state_changed.connect(_refresh)
	Net.server_error.connect(func(reason): _status.text = "Server: " + reason)
	Net.connection_changed.connect(func(online): _status.text = "Connected" if online else "Connecting to server...")
	_header.text = "Connecting..."

	# Count down cooldowns and raid clocks between server updates.
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(func(): if not Net.state.is_empty(): _refresh(Net.state))
	add_child(timer)


func _label(parent: Node, font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


func _refresh(state: Dictionary) -> void:
	var stock: Dictionary = state.stock
	_header.text = "%s   |   %d credits" % [state.system.name, state.credits]
	var goods := []
	for id in stock:
		if id not in ["metal", "ice"] and int(stock[id]) > 0:
			goods.append("%s %d" % [Net.item_name(id), stock[id]])
	_status.text = "Metal %d   Ice %d   Population %d" % [stock.metal, stock.get("ice", 0), state.population]
	if goods:
		_status.text += "\n" + "   ".join(goods)

	var planet: Dictionary = state.system.planets[0]
	var by_slot := {}
	for b in planet.buildings:
		by_slot[int(b.slot)] = b.type
	for child in _slots.get_children():
		child.queue_free()
	for slot in int(planet.slots):
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 64)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if by_slot.has(slot) and Net.catalog.get("facilities", {}).has(by_slot[slot]):
			var raid := Net.raid_on("aster", slot)
			var b: Dictionary = planet.buildings.filter(func(x): return int(x.slot) == slot)[0]
			btn.text = "%s  T%d\n%s" % [BUILDING_INFO[by_slot[slot]].name, int(b.security), "RAID IN PROGRESS" if not raid.is_empty() else "Vault: %d items" % _vault_count(b)]
			if not raid.is_empty():
				btn.modulate = Color(1.0, 0.55, 0.45)
			btn.pressed.connect(func(): _fac_slot = -1 if _fac_slot == slot else slot; _refresh(Net.state))
		elif by_slot.has(slot):
			btn.text = BUILDING_INFO[by_slot[slot]].name
			btn.disabled = true
		else:
			btn.text = "+ Build"
			btn.pressed.connect(_open_menu.bind(slot, state.unlocked))
		_slots.add_child(btn)

	_post_job.disabled = not Net.has_building("spaceport") or not Net.open_job().is_empty()

	var lines := []
	for job in state.jobs:
		lines.append("#%d  %s %d/%d  (%d cr)  %s" % [job.id, job.resource, job.delivered, job.amount, job.reward, job.status])
	_jobs.text = "\n".join(lines) if lines else "No jobs yet. Build a Spaceport, then post one."

	_refresh_facility(state)
	_refresh_raids(state)

	var feed := []
	for i in range(state.feed.size() - 1, max(-1, state.feed.size() - 9), -1):
		feed.append(state.feed[i].text)
	_feed.text = "\n".join(feed)


func _vault_count(b: Dictionary) -> int:
	var n := 0
	for id in b.vault:
		n += int(b.vault[id])
	return n


func _refresh_facility(state: Dictionary) -> void:
	for child in _fac_box.get_children():
		child.queue_free()
	var fac := {}
	for f in Net.facilities():
		if f.planet == "aster" and f.slot == _fac_slot:
			fac = f
	_fac_box.visible = not fac.is_empty()
	if fac.is_empty():
		return
	var b: Dictionary = fac.building
	var now := Net.now_ms()
	_label(_fac_box, 18).text = fac.name
	var vault := []
	for id in b.vault:
		if int(b.vault[id]) > 0:
			vault.append("%d %s" % [b.vault[id], Net.item_name(id)])
	var escrow := []
	for id in b.get("escrow", {}):
		escrow.append("%d %s" % [b.escrow[id], Net.item_name(id)])
	_label(_fac_box, 14).text = "Vault: %s%s" % [", ".join(vault) if vault else "empty",
		("\nIn the raid zone: %s" % ", ".join(escrow)) if escrow else ""]

	var ship := Button.new()
	var wait := (float(b.shipReadyAt) - now) / 1000.0
	ship.text = "Ship cargo to HQ" if wait <= 0 else "Freighter back in %d s" % ceili(wait)
	ship.disabled = wait > 0 or vault.is_empty()
	ship.pressed.connect(func(): Net.send({"type": "ship_cargo", "planet": "aster", "slot": _fac_slot}))
	_fac_box.add_child(ship)

	var tier := int(b.security)
	var info: Dictionary = Net.catalog.security[str(tier)]
	_label(_fac_box, 14).text = "Security tier %d: %d guards, %d turrets, %d-minute raid clock" % [tier, info.guards, info.turrets, info.minutes]
	var next: Dictionary = Net.catalog.security.get(str(tier + 1), {})
	if not next.is_empty():
		var cost := []
		for id in next.cost:
			cost.append("%d %s" % [next.cost[id], "credits" if id == "credits" else Net.item_name(id)])
		var up := Button.new()
		up.text = "Upgrade to tier %d (%s)" % [tier + 1, ", ".join(cost)]
		up.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		up.pressed.connect(func(): Net.send({"type": "upgrade_security", "planet": "aster", "slot": _fac_slot}))
		_fac_box.add_child(up)

	var raid := Net.raid_on("aster", _fac_slot)
	if not raid.is_empty():
		var alarm := Button.new()
		var alarm_wait := (float(b.alarmReadyAt) - now) / 1000.0
		alarm.text = "Sound the alarm (%d credits)" % Net.catalog.alarmCost if alarm_wait <= 0 else "Alarm ready in %d s" % ceili(alarm_wait)
		alarm.disabled = alarm_wait > 0
		alarm.pressed.connect(func(): Net.send({"type": "sound_alarm", "planet": "aster", "slot": _fac_slot}))
		_fac_box.add_child(alarm)
	elif float(b.cooldownUntil) > now:
		_label(_fac_box, 14).text = "Guards on alert after a raid: no one can board for %d s" % ceili((float(b.cooldownUntil) - now) / 1000.0)


func _refresh_raids(state: Dictionary) -> void:
	var lines := []
	var levels: Array = Net.catalog.get("heatLevels", [])
	for r in state.get("raids", []):
		var left := maxf(0.0, (float(r.endsAt) - Net.now_ms()) / 1000.0)
		var where := "breaching the perimeter"
		if r.get("stage", "") == "loot":
			where = "inside, on level %d of %d" % [maxi(1, int(r.get("floor", 1))), int(r.get("floors", 1))]
		elif r.get("stage", "") == "escape":
			var boom := maxf(0.0, (float(r.selfDestructAt) - Net.now_ms()) / 1000.0)
			where = "in the safe room: self-destruct in %d:%02d" % [int(boom) / 60, int(boom) % 60]
		lines.append("INTRUDER: %s at %s, %s\nHeat %d (%s), %d:%02d left" % [r.pilot, r.facility, where, r.heat,
			levels[int(r.level)].name if levels else "", int(left) / 60, int(left) % 60])
	var history: Array = state.get("raidLog", [])
	for i in range(history.size() - 1, maxi(-1, history.size() - 4), -1):
		var e: Dictionary = history[i]
		var stolen := []
		for id in e.stolen:
			stolen.append("%d %s" % [e.stolen[id], Net.item_name(id)])
		lines.append("%s at %s: %s%s" % [e.pilot, e.facility, {"destroyed": "caught in the self-destruct"}.get(e.outcome, e.outcome), (", took " + ", ".join(stolen)) if stolen else ""])
	_raids.text = "\n".join(lines) if lines else "No raids yet. Facilities you build can be raided by pilots."


func _on_chat(sender: String, _role: String, text: String) -> void:
	_chat_lines.append("%s: %s" % [sender, text])
	if _chat_lines.size() > 5:
		_chat_lines.pop_front()
	_chat_log.text = "\n".join(_chat_lines)


func _open_menu(slot: int, unlocked: Array) -> void:
	_menu_slot = slot
	_menu.clear()
	var i := 0
	for type in BUILDING_INFO:
		if type in unlocked:
			_menu.add_item("%s  (%s)" % [BUILDING_INFO[type].name, BUILDING_INFO[type].cost], i)
			_menu.set_item_metadata(_menu.get_item_index(i), type)
		i += 1
	_menu.popup_centered()


func _on_build_chosen(id: int) -> void:
	var type: String = _menu.get_item_metadata(_menu.get_item_index(id))
	Net.send({"type": "build", "planet": "aster", "slot": _menu_slot, "building": type})
