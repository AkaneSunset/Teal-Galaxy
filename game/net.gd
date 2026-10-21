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
## Every message from the server, after the handling below (battles, walkers, docking...).
signal message(msg: Dictionary)

var state: Dictionary = {}
## Items, facilities and security tiers, from the server.
var catalog: Dictionary = {}
var my_id := 0
var my_name := ""
## A Builder's home planet id, from the server (empty for Explorers).
var home := ""
## The last ship position exactly as the server sent it (64-bit numbers, metres from the star).
var last_ship_pos: Array = []
## True when the server took our admin key: the Coma director's controls show.
var admin := false
## Admin keys typed into Settings, the start screen or the phone's refusal screen, one per server
## (server_key(url) -> key), saved with the settings (controls.gd). A saved key only ever goes to
## the server it was typed for. `--admin-key=` on the command line wins over it; see admin_key().
var admin_keys := {}
## Why the server turned away our hello on this connection (a Coma Conglomerate character
## without the admin key, say), or "" once it welcomes us.
var refused := ""

const INBOUND_BUFFER := 4 * 1024 * 1024 # bytes: room for the largest state message
## Where Settings live (controls.gd writes them); the admin keys are read from here.
const SETTINGS_PATH := "user://controls.cfg"
const Controls := preload("res://controls.gd")

var _socket := WebSocketPeer.new()
var _url := ""
var _role := ""
var _started := false
var _online := false
var _retry_in := 0.0
var _admin_key_arg := ""
var _welcomed := false # the server has welcomed us on this connection


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--admin-key="):
			_admin_key_arg = arg.trim_prefix("--admin-key=")
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		var keys = cfg.get_value("settings", "admin_keys", {})
		if keys is Dictionary:
			admin_keys = keys


## The admin key to say hello with: the command line's (it goes to the server given with it),
## else the one saved for this server (empty: none).
func admin_key() -> String:
	return _admin_key_arg if _admin_key_arg != "" else saved_admin_key(_url)


## The server this app connects to, as typed.
func server_url() -> String:
	return _url


## A server's address as its admin key is saved under it: the same however it was typed.
static func server_key(url: String) -> String:
	var u := url.strip_edges().to_lower().trim_suffix("/")
	return u if u.contains("://") else "ws://" + u


## The admin key saved for a server, or "".
func saved_admin_key(url: String) -> String:
	return str(admin_keys.get(server_key(url), ""))


## Saves the admin key for a server with the settings, or forgets it when `key` is empty.
func save_admin_key(url: String, key: String) -> void:
	if key.strip_edges() == saved_admin_key(url):
		return
	if key.strip_edges() == "":
		admin_keys.erase(server_key(url))
	else:
		admin_keys[server_key(url)] = key.strip_edges()
	Controls.save_admin_keys(admin_keys)


func connect_to(url: String, role: String, player_name: String) -> void:
	_url = url
	_role = role
	my_name = player_name
	_started = true
	_open()


## Drops the connection; it comes back in a moment with a fresh hello (a new admin key, say).
func reconnect() -> void:
	if _started:
		_socket.close()


func send(msg: Dictionary) -> void:
	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_socket.send_text(JSON.stringify(msg))


func _open() -> void:
	_welcomed = false
	refused = ""
	_socket = WebSocketPeer.new()
	# The galaxy state (the war map's sectors above all) is well over the default 64 KiB a message.
	_socket.inbound_buffer_size = INBOUND_BUFFER
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
				var hello := {"type": "hello", "role": _role, "name": my_name}
				if admin_key() != "":
					hello.admin_key = admin_key()
				send(hello)
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
			home = str(msg.get("home", "")) if msg.get("home") != null else ""
			admin = msg.get("admin", false) == true
			_welcomed = true
			refused = ""
			catalog = msg.get("catalog", {})
			state = msg.state
			state_changed.emit(state)
		"state":
			if not _welcomed:
				return # not ours to see: the server hasn't taken our hello (yet, or at all)
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
			# The first error before a welcome is the hello's refusal (later ones only say hello first).
			# After one, an admins-only reason means the server turned this character away: an admin
			# took it into the Coma Conglomerate while this app played it without the key.
			var reason := str(msg.reason)
			if (not _welcomed and refused == "") or (_welcomed and reason.ends_with(": admins only")):
				_welcomed = false
				refused = reason
			server_error.emit(msg.reason)
	message.emit(msg)


## True when any planet in the system (or just `planet_id`) has a building of this type.
func has_building(type: String, planet_id := "") -> bool:
	if state.is_empty():
		return false
	for planet in state.system.planets:
		if planet_id != "" and planet.id != planet_id:
			continue
		for b in planet.buildings:
			if b.type == type:
				return true
	return false


## The first open job (on `planet_id`, if given), or an empty Dictionary.
func open_job(planet_id := "") -> Dictionary:
	if state.is_empty():
		return {}
	for job in state.jobs:
		if job.status == "open" and (planet_id == "" or job.get("planet", "aster") == planet_id):
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


## This Builder's home planet: the one the server gave them, else the first.
func my_planet() -> Dictionary:
	if state.is_empty():
		return {}
	for planet in state.system.planets:
		if planet.id == home:
			return planet
	return state.system.planets[0]


## This Builder's economy (stock, credits, population, unlocked, navy). Before bases existed,
## or for a planet nobody has claimed, it is the galaxy's own top-level economy.
func my_economy() -> Dictionary:
	if state.is_empty():
		return {}
	var owner = my_planet().get("owner")
	return state.get("bases", {}).get(owner, state) if owner != null else state


## A planet or satellite site by id, or an empty Dictionary.
func planet(id: String) -> Dictionary:
	if state.is_empty():
		return {}
	for p in state.system.planets:
		if p.id == id:
			return p
	return {}
