extends Control
## Builder mode (phone): build on planet slots, post jobs, watch explorer activity.

const BUILDING_INFO := {
	"mine": {"name": "Mine", "cost": "10 metal"},
	"habitat": {"name": "Habitat", "cost": "20 metal"},
	"spaceport": {"name": "Spaceport", "cost": "30 metal"},
	"hydroponics": {"name": "Hydroponics", "cost": "20 metal, 10 ice"},
}
const JOB := {"resource": "ice", "amount": 10, "reward": 100}

var _header: Label
var _status: Label
var _slots: GridContainer
var _post_job: Button
var _jobs: Label
var _feed: Label
var _menu: PopupMenu
var _menu_slot := -1


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
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

	_post_job = Button.new()
	_post_job.text = "Post job: deliver %d %s for %d credits" % [JOB.amount, JOB.resource, JOB.reward]
	_post_job.pressed.connect(func(): Net.send({"type": "post_job", "resource": JOB.resource, "amount": JOB.amount, "reward": JOB.reward}))
	col.add_child(_post_job)

	_label(col, 16).text = "Jobs"
	_jobs = _label(col, 14)
	_label(col, 16).text = "Activity"
	_feed = _label(col, 13)
	_feed.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_menu = PopupMenu.new()
	_menu.id_pressed.connect(_on_build_chosen)
	add_child(_menu)

	Net.state_changed.connect(_refresh)
	Net.server_error.connect(func(reason): _status.text = "Server: " + reason)
	Net.connection_changed.connect(func(online): _status.text = "Connected" if online else "Connecting to server...")
	_header.text = "Connecting..."


func _label(parent: Node, font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


func _refresh(state: Dictionary) -> void:
	var stock: Dictionary = state.stock
	_header.text = "%s   |   %d credits" % [state.system.name, state.credits]
	_status.text = "Metal %d   Ice %d   Population %d" % [stock.metal, stock.get("ice", 0), state.population]

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
		if by_slot.has(slot):
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

	var feed := []
	for i in range(state.feed.size() - 1, max(-1, state.feed.size() - 9), -1):
		feed.append(state.feed[i].text)
	_feed.text = "\n".join(feed)


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
