extends Node
## A Builder's Star Port, against a running galaxy server (not in demo mode: pilots fly ships):
##   cd server && SAVE_FILE=/tmp/starport.json BUILD_SPEED=0 npm start   (delete /tmp/starport.json first)
##   godot --headless --path game res://tests/starport_test.tscn
## "Port B", a Builder over its own connection, builds a Star Port (level 1: 2 berths) and posts a
## buy order for ice. Two pilots over their own connections land on both berths. "Port P", the game
## itself, docks at the High Port: the Star Port refuses it a berth, so it takes the shuttle down and
## sells ice less the High Port's tariff. One of the others flies away; P takes the shuttle back up,
## flies its ship down onto the free berth and sells ice again, at full price; then the Builder lists
## ice for sale and P buys it back.
## Add `-- --server=ws://127.0.0.1:9000` for a server on another port. Prints PASS or FAIL and quits.

const ExplorerMode := preload("res://explorer.gd")
const Surface := preload("res://surface.gd")
const BUILDER := "Port B"
const PRICE := 5

var _explorer: Node
var _peers := {} # name -> WebSocketPeer: the Builder and the two other pilots
var _server := "ws://127.0.0.1:8080"
var _home := ""
var _step := "start"
var _wait := 1.0
var _clock := 0.0
var _done := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--server="):
			_server = arg.substr(9)
	Net.connect_to(_server, "explorer", "Port P", "Port P", "port-test") # signed in: not a demo server
	_explorer = ExplorerMode.new()
	add_child(_explorer)
	for name in [BUILDER, "Port A1", "Port A2"]:
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = 4 * 1024 * 1024
		ws.connect_to_url(_server)
		_peers[name] = ws
	Net.server_error.connect(func(r): print("server error (P): ", r))


func _process(delta: float) -> void:
	_clock += delta
	for name in _peers:
		_poll(name)
	if _done:
		return
	if _clock > 60.0:
		_finish(false, "timed out at step " + _step)
		return
	_wait -= delta
	if _wait > 0.0 or Net.state.is_empty():
		return
	_steps()


func _steps() -> void:
	match _step:
		"start":
			if Net.catalog.get("carrier", false) == true:
				_finish(false, "the server is in demo mode (pilots fly carriers): start it without DEMO=1")
				return
			for name in _peers:
				if _peers[name].get_ready_state() != WebSocketPeer.STATE_OPEN:
					return
			_send(BUILDER, {"type": "hello", "role": "builder", "name": BUILDER, "account": BUILDER, "password": "port-test"})
			for name in ["Port A1", "Port A2"]:
				_send(name, {"type": "hello", "role": "explorer", "name": name, "account": name, "password": "port-test"})
			_collect(10)
			_step = "home"
		"home":
			for p in Net.state.system.planets:
				if p.get("owner") == BUILDER and p.get("kind", "") != "satellite":
					_home = p.id
			if _home == "":
				return
			_send(BUILDER, {"type": "build", "planet": _home, "slot": 0, "building": "spaceport"})
			_step = "star port"
		"star port":
			if not Net.has_building("spaceport", _home):
				return
			_send(BUILDER, {"type": "set_bid", "item": "ice", "price": PRICE, "want": 100})
			for name in ["Port A1", "Port A2"]:
				_send(name, {"type": "dock_request", "station": _home})
				_send(name, {"type": "land_request", "base": _home})
			_step = "berths full"
		"berths full":
			var taken: Array = Net.state.get("berths", {}).get(_home, [])
			if taken.filter(func(n): return n != null).size() < 2 or not _bids().has("ice") or not _explorer._stations.has(_home):
				return
			_explorer.dock(_home)
			_step = "fly down"
			_wait = 0.5
		"fly down":
			var fly := _button("Fly down to %s's base and land at the Star Port (0 of 2 berths free)" % BUILDER)
			if not fly:
				_finish(false, "the High Port menu should offer the Star Port with 0 of 2 berths free: %s" % [_texts()])
				return
			if not _button("High Port's tariff takes 10"):
				_finish(false, "the High Port should offer the ice sale less its tariff: %s" % [_texts()])
				return
			fly.pressed.emit()
			_step = "refused"
		"refused":
			if not _explorer._land_problem.contains("berths at the Star Port are taken"):
				return
			var shuttle := _button("Take the shuttle down")
			if not shuttle:
				_finish(false, "full berths: the menu should offer the shuttle: %s" % [_texts()])
				return
			shuttle.pressed.emit()
			_step = "shuttled"
			_wait = 0.5
		"shuttled":
			var place = _explorer._station
			if not (place and place.get_script() == Surface and place.shuttle and _explorer._space_id == "surface:" + _home):
				return
			_explorer._open_standing_menu()
			var sell := _button("Sell 10 Ice to %s for 40 credits (the High Port's tariff takes 10)" % BUILDER)
			if not sell:
				_finish(false, "the shuttle stop should sell less the tariff: %s" % [_texts()])
				return
			sell.pressed.emit()
			_step = "sold tariffed"
		"sold tariffed":
			if _credits() != 40:
				return
			_collect(10)
			_peers["Port A1"].close() # flies away: a berth frees up
			var up := _button("Take the shuttle back up")
			if not up:
				_finish(false, "the shuttle stop should take you back up: %s" % [_texts()])
				return
			up.pressed.emit()
			_step = "back up"
			_wait = 1.0
		"back up":
			var fly := _button("land at the Star Port (1 of 2 berths free)")
			if not fly or _explorer._at_spaceport:
				return
			fly.pressed.emit()
			_step = "landed"
		"landed":
			var place = _explorer._station
			if not (_explorer._at_spaceport and place and place.get_script() == Surface and not place.shuttle):
				return
			if place.berth != 0:
				_finish(false, "the ship should land on the freed berth 1, not %d" % (place.berth + 1))
				return
			var sell := _button("Sell 10 Ice to %s for 50 credits" % BUILDER)
			if not sell or sell.text.contains("tariff"):
				_finish(false, "landed on a berth: the sale should be at full price: %s" % [_texts()])
				return
			sell.pressed.emit()
			_step = "sold"
		"sold":
			if _credits() != 90:
				return
			var b: Dictionary = Net.state.bases.get(BUILDER, {})
			if int(b.get("stock", {}).get("ice", 0)) != 20 or int(b.bids.ice.want) != 80:
				_finish(false, "the Builder should have the 20 ice and want 80 more")
				return
			_send(BUILDER, {"type": "set_ask", "item": "ice", "price": 3})
			_step = "listed"
		"listed":
			var buy := _button("Buy 10 Ice from %s for 30 credits" % BUILDER)
			if not buy:
				return
			buy.pressed.emit()
			_step = "bought"
		"bought":
			if _credits() != 60 or _explorer._cargo("ice") != 10:
				return
			_finish(true, "berths full: shuttled down and sold less the tariff; a berth freed: landed on it, sold at full price and bought from the Star Port's listings")


func _collect(n: int) -> void:
	while n > 0:
		Net.send({"type": "collect", "resource": "ice", "amount": mini(n, 5)})
		n -= 5


func _bids() -> Dictionary:
	return Net.state.get("bases", {}).get(BUILDER, {}).get("bids", {})


func _credits() -> int:
	return int(_explorer._me().get("credits", 0))


## The ship's menu button whose text contains `part`, or null.
func _button(part: String) -> Button:
	for c in _explorer._dock_list.get_children():
		if c is Button and not c.is_queued_for_deletion() and c.text.contains(part):
			return c
	return null


func _texts() -> Array:
	return _explorer._dock_list.get_children().filter(func(c): return not c.is_queued_for_deletion() and (c is Button or c is Label)).map(func(c): return c.text)


func _poll(name: String) -> void:
	var ws: WebSocketPeer = _peers[name]
	ws.poll()
	while ws.get_available_packet_count() > 0:
		var msg = JSON.parse_string(ws.get_packet().get_string_from_utf8())
		if msg is Dictionary and msg.get("type", "") == "error":
			print("server error (%s): %s" % [name, msg.get("reason", "")])


func _send(name: String, msg: Dictionary) -> void:
	if _peers[name].get_ready_state() == WebSocketPeer.STATE_OPEN:
		_peers[name].send_text(JSON.stringify(msg))


func _finish(ok: bool, what: String) -> void:
	if _done:
		return
	_done = true
	print(("PASS " if ok else "FAIL ") + "star port: " + what)
	get_tree().quit(0 if ok else 1)
