extends Node
## Connection to the galaxy server. Autoloaded as `Net`.
## Holds the latest galaxy state and turns server messages into signals.

signal state_changed(state: Dictionary)
signal ship_moved(id: int, pilot_name: String, pos: Vector3, rot: Vector3)
signal ship_left(id: int)
signal chat_received(sender: String, role: String, text: String)
signal server_error(reason: String)
signal connection_changed(online: bool)
## Raid events for the raider: begin, container, reveal, inventory, heat, extracting, end, ...
signal raid_event(msg: Dictionary)

var state: Dictionary = {}
## Items, facilities and security tiers, from the server.
var catalog: Dictionary = {}
var my_id := 0
var my_name := ""
## The last ship position exactly as the server sent it (64-bit numbers, metres from the star).
var last_ship_pos: Array = []

var _socket := WebSocketPeer.new()
var _url := ""
var _role := ""
var _started := false
var _online := false
var _retry_in := 0.0


func connect_to(url: String, role: String, player_name: String) -> void:
	_url = url
	_role = role
	my_name = player_name
	_started = true
	_open()


func send(msg: Dictionary) -> void:
	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_socket.send_text(JSON.stringify(msg))


func _open() -> void:
	_socket = WebSocketPeer.new()
	var err := _socket.connect_to_url(_url)
	if err != OK:
		server_error.emit("Could not reach %s" % _url)
		_retry_in = 2.0


func _process(delta: float) -> void:
	if not _started:
		return
	_socket.poll()
	match _socket.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _online:
				_online = true
				connection_changed.emit(true)
				send({"type": "hello", "role": _role, "name": my_name})
			while _socket.get_available_packet_count() > 0:
				var msg = JSON.parse_string(_socket.get_packet().get_string_from_utf8())
				if msg is Dictionary:
					_handle(msg)
		WebSocketPeer.STATE_CLOSED:
			if _online:
				_online = false
				connection_changed.emit(false)
				_retry_in = 2.0
			_retry_in -= delta
			if _retry_in <= 0.0:
				_retry_in = 2.0
				_open()


func _handle(msg: Dictionary) -> void:
	match msg.get("type", ""):
		"welcome":
			my_id = int(msg.id)
			my_name = msg.name
			catalog = msg.get("catalog", {})
			state = msg.state
			state_changed.emit(state)
		"state":
			state = msg.state
			state_changed.emit(state)
		"ship":
			var p: Array = msg.pos
			last_ship_pos = p
			var r: Array = msg.rot
			ship_moved.emit(int(msg.id), msg.name, Vector3(p[0], p[1], p[2]), Vector3(r[0], r[1], r[2]))
		"chat":
			chat_received.emit(str(msg.name), str(msg.get("role", "")), str(msg.text))
		"left":
			ship_left.emit(int(msg.id))
		"raid":
			raid_event.emit(msg)
		"error":
			server_error.emit(msg.reason)


## True when any planet in the system has a building of this type.
func has_building(type: String) -> bool:
	if state.is_empty():
		return false
	for planet in state.system.planets:
		for b in planet.buildings:
			if b.type == type:
				return true
	return false


## The first open job, or an empty Dictionary.
func open_job() -> Dictionary:
	if state.is_empty():
		return {}
	for job in state.jobs:
		if job.status == "open":
			return job
	return {}


## Every facility in the system: {"planet", "slot", "type", "name", "building"}.
func facilities() -> Array:
	var out := []
	if state.is_empty() or catalog.is_empty():
		return out
	for planet in state.system.planets:
		for b in planet.buildings:
			if catalog.facilities.has(b.type):
				out.append({"planet": planet.id, "slot": int(b.slot), "type": b.type, "building": b,
					"name": "%s %s %d" % [planet.name, catalog.facilities[b.type].name, int(b.slot) + 1]})
	return out


## The live raid on a facility, or an empty Dictionary.
func raid_on(planet_id: String, slot: int) -> Dictionary:
	for r in state.get("raids", []):
		if r.planet == planet_id and int(r.slot) == slot:
			return r
	return {}


func item_name(id: String) -> String:
	return catalog.get("items", {}).get(id, {}).get("name", id)


## Server timestamps are milliseconds since 1970.
func now_ms() -> float:
	return Time.get_unix_time_from_system() * 1000.0
