extends Node
## Faction orders, as a pilot sees them, against a running DEMO galaxy server:
##   cd server && SAVE_FILE=/tmp/orders.json DEMO=1 npm start   (delete /tmp/orders.json first)
##   godot --headless --path game res://tests/orders_test.tscn
## "Orders Tester" (Luminar Accord), aboard its carrier, waits for High Command's first order of the
## operation, then uses the HIGH COMMAND terminal on the Command Deck: the operation, the three order
## slots, the running order's briefing (in the Accord Council's voice, with how its targets scale),
## its tasks, deadline and reward, and the pilot's own part. The archive opens and closes, and the War
## terminal's Orders button opens the same screen.
## `-- --server=ws://127.0.0.1:9000` for a server on another port, and `-- --shots=/some/dir` with a
## display to save screenshots. Prints PASS or FAIL and quits.

const ExplorerMode := preload("res://explorer.gd")
const PILOT := "Orders Tester"
const PLANET := "cinder"

var _server := "ws://127.0.0.1:8080"
var _shots := ""
var _explorer: Node
var _menu: Control
var _view: Node
var _step := "start"
var _wait := 1.0
var _clock := 0.0
var _step_clock := 0.0
var _done := false
var _joined_space := false
var _joined := {}
var _order: Dictionary = {}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--server="):
			_server = arg.substr(9)
		elif arg.begins_with("--shots="):
			_shots = arg.substr(8)
	if DisplayServer.get_name() != "headless":
		get_window().size = Vector2i(1600, 900)
	Net.connect_to(_server, "explorer", PILOT)
	Net.message.connect(_on_message)
	Net.server_error.connect(func(r): print("server error: ", r))
	_explorer = ExplorerMode.new()
	add_child(_explorer)


func _on_message(msg: Dictionary) -> void:
	match str(msg.get("type", "")):
		"space_joined":
			_joined_space = str(msg.get("space", "")) == "ship:" + PILOT



func _process(delta: float) -> void:
	_clock += delta
	_step_clock += delta
	if _done:
		return
	if _clock > 240.0:
		_finish(false, "timed out at step " + _step)
		return
	_wait -= delta
	if _wait > 0.0 or Net.state.is_empty():
		return
	_steps()


func _go(step: String, wait := 0.0) -> void:
	_step = step
	_wait = wait
	_step_clock = 0.0
	print("step: ", step)


func _steps() -> void:
	match _step:
		"start":
			Net.send({"type": "choose_faction", "faction": "luminar"})
			Net.send({"type": "enter_space", "space": "ship:" + PILOT})
			_go("aboard")
		"aboard":
			if not _joined_space or str(Net.state.get("pilots", {}).get(PILOT, {}).get("faction", "")) != "luminar":
				if _step_clock > 10.0:
					_finish(false, "never got aboard ship:%s as a Luminar pilot" % PILOT)
				return
			_explorer._hide_panels()
			if _explorer._station == null or not ("mine" in _explorer._station):
				_explorer._enter_carrier(PILOT, "bridge")
			_go("order")
		"order":
			var op = Net.state.get("war", {}).get("orders", {}).get("op")
			var mine: Array = op.get("factions", {}).get("luminar", {}).get("orders", []) + op.get("coma", []) if op is Dictionary else []
			mine = mine.filter(func(o): return str(o.status) == "active")
			if mine.is_empty():
				if _step_clock > 30.0:
					_finish(false, "High Command should issue the operation's first order")
				return
			_order = mine[0]
			_go("terminal", 0.5)
		"terminal":
			# The HIGH COMMAND terminal: F.
			_explorer._on_service("orders")
			var panel: Control = _explorer._orders_panel
			if not panel.visible:
				_finish(false, "the HIGH COMMAND terminal should open the orders")
				return
			var text := _texts(panel)
			for want in ["HIGH COMMAND ORDERS", "Operation ", str(_order.title), str(_order.issuer).to_upper(), "Deadline in", "Reward if won", "Your part: nothing yet", "Order 1: running"]:
				if not text.contains(want):
					_finish(false, "the orders should show '%s':\n%s" % [want, text])
					return
			if str(_order.kind) != "coma" and not text.contains("for each of our"):
				_finish(false, "the briefing should say how the targets scale")
				return
			_go("busy") # (while this step awaits, _process mustn't run it again)
			await _shot("orders-01-high-command")
			_buttons(panel, "Archive")[0].pressed.emit()
			await get_tree().process_frame
			if not _texts(panel).contains("ORDERS ARCHIVE"):
				_finish(false, "the archive should open")
				return
			_buttons(panel, "Current orders")[0].pressed.emit()
			await get_tree().process_frame
			panel.closed.emit()
			_go("war", 0.3)
		"war":
			if _explorer._orders_panel.visible:
				_finish(false, "the orders should close")
				return
			_explorer._open_war("cinder")
			var b := _buttons(_explorer._war_panel, "Orders")
			if b.is_empty():
				_finish(false, "the War terminal should have an Orders button")
				return
			b[0].pressed.emit()
			if not _explorer._orders_panel.visible or _explorer._war_panel.visible:
				_finish(false, "the War terminal's Orders should open the orders")
				return
			_finish(true, "High Command issued the operation's first order (\"%s\", %s); the HIGH COMMAND terminal shows the operation, the slots, the briefing with its scaling, the tasks, deadline, reward and the pilot's part; the archive opens; the War terminal's Orders opens it too" % [_order.title, _order.issuer])


## Every Label's text under `root`, one per line.
func _texts(root: Node) -> String:
	var out: Array = []
	for l in root.find_children("*", "Label", true, false):
		out.append((l as Label).text)
	return "\n".join(out)


func _shot(name: String) -> void:
	if _shots == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_shots, name])


## Visible buttons under `root` whose text contains `text`.
func _buttons(root: Node, text: String) -> Array:
	return root.find_children("*", "Button", true, false).filter(func(b): return b.is_visible_in_tree() and b.text.contains(text))


func _finish(ok: bool, what: String) -> void:
	if _done:
		return
	_done = true
	print(("PASS " if ok else "FAIL ") + "orders: " + what)
	get_tree().quit(0 if ok else 1)
