extends Node
## Shared spaces and the fleet carrier, against a running DEMO galaxy server (every pilot flies a
## fleet carrier there):
##   cd server && SAVE_FILE=/tmp/spaces.json DEMO=1 BUILD_SPEED=0 npm start   (delete /tmp/spaces.json first)
##   godot --headless --path game res://tests/spaces_test.tscn
## Two pilots dock at Cinder Orbital: "Spaces A" over a second connection (it docks first and lies at
## its berth), and "Spaces B", the game itself, which flies the automated approach to its own berth.
## They get different berths in the same copy. B leaves the pilot's chair, walks the carrier
## (Bridge, Command Deck, Hangar Deck), goes through the airlock into the station, where A walks in
## too: each sees the other move. A goes back aboard its carrier, and B boards it through A's door in
## the Carrier Berths and finds A sitting in the Crew Lounge.
## Add `-- --shots=/some/dir` and run with a display to save screenshots along the way, and
## `-- --server=ws://127.0.0.1:9000` for a server on another port. Prints PASS or FAIL and quits.

const ExplorerMode := preload("res://explorer.gd")
const Carrier := preload("res://carrier.gd")
const WarInfo := preload("res://war_info.gd")
const STATION := "cinder"
const A_NAME := "Spaces A"

var _explorer: Node
var _a := WebSocketPeer.new() # the other pilot, over its own connection
var _a_id := -1
var _a_pad := {} # its dock_granted
var _a_seen := [] # where A saw B walk (positions in the station)
var _a_saw_b_aboard := false
var _a_ship_in := 0.0
var _server := "ws://127.0.0.1:8080"
var _shots := ""
var _step := "start"
var _wait := 1.0
var _clock := 0.0
var _seen_a := [] # where B saw A's figure in the station
var _t := 0.0
var _done := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--server="):
			_server = arg.substr(9)
		elif arg.begins_with("--shots="):
			_shots = arg.substr(8)
	if DisplayServer.get_name() != "headless":
		get_window().size = Vector2i(1600, 900)
	Net.connect_to(_server, "explorer", "Spaces B")
	_explorer = ExplorerMode.new()
	add_child(_explorer)
	_a.inbound_buffer_size = 4 * 1024 * 1024
	_a.connect_to_url(_server)
	Net.server_error.connect(func(r): print("server error (B): ", r))


func _process(delta: float) -> void:
	_clock += delta
	_poll_a(delta)
	if _done:
		return
	if _clock > 150.0:
		_finish(false, "timed out at step " + _step)
		return
	_wait -= delta
	if _wait > 0.0 or Net.state.is_empty():
		return
	_steps(delta)


func _steps(_delta: float) -> void:
	match _step:
		"start":
			if Net.catalog.get("carrier", false) != true:
				_finish(false, "the server isn't in demo mode (no carrier in the catalog): start it with DEMO=1")
				return
			if _a.get_ready_state() != WebSocketPeer.STATE_OPEN or not _explorer._stations.has(STATION):
				return
			_send_a({"type": "hello", "role": "explorer", "name": A_NAME})
			_send_a({"type": "choose_faction", "faction": "compact"})
			Net.send({"type": "choose_faction", "faction": "compact"})
			_send_a({"type": "dock_request", "station": STATION})
			_step = "a docked"
		"a docked":
			if _a_pad.is_empty() or WarInfo.my_faction() != "compact":
				return
			# A lies at its berth: it says so every half second (see _poll_a). B flies in.
			_explorer.teleport(_explorer.System.offset(_explorer._stations[STATION].pos, Vector3(600, 300, 2600)))
			_explorer.flight.basis = Basis.looking_at(Vector3(-0.2, -0.1, -1).normalized(), Vector3.UP)
			_explorer._set_outside(true)
			_wait = 1.5
			_step = "in space"
		"in space":
			if not _explorer._carrier or _explorer._hull == null:
				_finish(false, "B should be flying a fleet carrier in the demo")
				return
			if not _explorer._prompt.text.contains("request docking"):
				_finish(false, "no docking prompt near the station: '%s'" % _explorer._prompt.text)
				return
			_shot("01-carrier-in-space")
			_explorer._set_outside(false)
			_explorer._request_dock(STATION)
			_step = "approach"
		"approach":
			if _explorer._approach.is_empty():
				return
			if _explorer._approach.t < 7.0:
				return
			_shot("02-docking-approach")
			if not _explorer._prompt.text.begins_with("Automated docking"):
				_finish(false, "the approach should say so on the HUD: " + _explorer._prompt.text)
				return
			_explorer._clamp() # skip the rest of it
			_wait = 1.0
			_step = "clamped"
		"clamped":
			var berth: Dictionary = _explorer._berth
			var c = _explorer._station
			if not (c is Carrier) or not c.seated or not _explorer._dock_panel.visible:
				_finish(false, "after the clamps B should sit in the carrier's pilot's chair with the ship's menu up")
				return
			if berth.get("local", false) or int(berth.pad) == int(_a_pad.pad) or int(berth.copy) != int(_a_pad.copy):
				_finish(false, "B should have its own berth in A's copy: B %s, A %s" % [berth, _a_pad])
				return
			if not _explorer._dock_title.text.contains("Berth %d, Cinder Orbital (%d)" % [int(berth.pad), int(berth.copy)]):
				_finish(false, "the ship's menu should name the berth: " + _explorer._dock_title.text)
				return
			_explorer._leave_seat()
			_wait = 1.0
			_step = "bridge"
		"bridge":
			var c = _explorer._station
			if c.seated or c._location() != "Bridge" or _explorer._space_id != "ship:Spaces B":
				_finish(false, "B should stand on the Bridge, in its carrier's space: %s, %s" % [c._location(), _explorer._space_id])
				return
			c.view_at(c, Vector3(-3.0, 2.1, -50.0), Vector3(1.0, 1.4, -62.0))
			_wait = 1.0
			_step = "bridge shot"
		"bridge shot":
			_shot("03-bridge")
			var c = _explorer._station
			c.view_at(c, Vector3(1.5, 1.65, -16.0), Vector3(0, 2.4, -25.0))
			_wait = 1.0
			_step = "holo"
		"holo":
			_shot("04-command-deck-holo-table")
			var c = _explorer._station
			if c._location() != "Command Deck" or not c._boards.below.text.contains("CINDER"):
				_finish(false, "the Command Deck's planet-below screen should show Cinder: " + c._boards.below.text)
				return
			c.view_at(c, Vector3(14.0, -14.35, 40.0), Vector3(-6.0, -12.0, 0.0))
			_wait = 1.0
			_step = "hangar"
		"hangar":
			_shot("05-hangar-deck")
			var c = _explorer._station
			if c._location() != "Hangar Deck":
				_finish(false, "B should be on the Hangar Deck, not " + c._location())
				return
			# Through the airlock into the station.
			c._player.global_position = Vector3(-23.5, -15.95, 8.0)
			_wait = 0.6
			_step = "into station"
		"into station":
			var st = _explorer._station
			if st == null or st is Carrier or not st.carrier_mode or _explorer._space_id != "station:" + STATION:
				_finish(false, "the airlock should lead into Cinder Orbital's Carrier Berths: %s" % _explorer._space_id)
				return
			# A walks in too, beside B's gate, then walks up and down; B steps about.
			_send_a({"type": "enter_space", "space": "station:" + STATION, "pos": _hall(Vector3(14.0, 0.0, 16.0)), "yaw": 0.0, "anim": "idle"})
			_t = 0.0
			_wait = 0.5
			_step = "walk"
		"walk":
			_t += 0.25
			var st = _explorer._station
			_send_a({"type": "walk", "pos": _hall(Vector3(12.0 - _t, 0.0, 17.0)), "yaw": 1.2, "anim": "walk"})
			st._player.global_position = st._rooms[0].to_global(Vector3(15.5 - _t * 0.3, 0.05, 17.0))
			var fig: Node3D = st.walkers.figure_of(A_NAME)
			if fig:
				_seen_a.append(fig.position)
			_wait = 0.25
			if _t < 3.0:
				return
			var moved: bool = _seen_a.size() > 2 and _seen_a[0].distance_to(_seen_a[-1]) > 0.5
			var a_moved: bool = _a_seen.size() > 1 and (_a_seen[0] as Vector3).distance_to(_a_seen[-1]) > 0.2
			if not moved or not a_moved:
				_finish(false, "each should see the other walk: B saw A at %d spots, A saw B at %d" % [_seen_a.size(), _a_seen.size()])
				return
			st.view_at(st._rooms[0], Vector3(15.5, 1.65, 13.0), Vector3(9.0, 1.3, 17.5))
			_wait = 1.0
			_step = "station shot"
		"station shot":
			_shot("06-station-hangar-two-pilots")
			# A goes back aboard its own carrier and sits down in its lounge.
			_send_a({"type": "enter_space", "space": "ship:" + A_NAME, "pos": [-10.0, 0.0, 14.0], "yaw": -PI / 2.0, "anim": "sit"})
			_send_a({"type": "ship_open", "open": false}) # closed to visitors at first
			_wait = 2.0
			_step = "closed"
		"closed":
			var st = _explorer._station
			var gate := {}
			for g in st._gates:
				if g.name == A_NAME:
					gate = g
			if gate.is_empty():
				_finish(false, "the Carrier Berths should have a door onto A's carrier")
				return
			st._through_gate(gate)
			_wait = 1.5
			_step = "refused"
		"refused":
			var st = _explorer._station
			if st is Carrier or _explorer._boarding != "" or not st._message.text.contains("closed their carrier"):
				_finish(false, "with A's carrier closed, B should be refused at the door: '%s'" % st._message.text)
				return
			_send_a({"type": "ship_open", "open": true})
			_wait = 2.0 # past the door's own pause after the last try
			_step = "board"
		"board":
			var st = _explorer._station
			var gate := {}
			for g in st._gates:
				if g.name == A_NAME:
					gate = g
			if gate.is_empty():
				_finish(false, "the Carrier Berths should have a door onto A's carrier: %s" % [st._gates.map(func(x): return x.title.text + " " + x.body.text)])
				return
			st._through_gate(gate)
			_step = "aboard"
		"aboard":
			var c = _explorer._station
			if not (c is Carrier) or c.owner_name != A_NAME:
				return
			if _explorer._space_id != "ship:" + A_NAME:
				_finish(false, "B should be in A's carrier's space, not " + _explorer._space_id)
				return
			_wait = 1.5
			_step = "lounge"
		"lounge":
			var c = _explorer._station
			var fig: Node3D = c.walkers.figure_of(A_NAME)
			if fig == null or not _a_saw_b_aboard:
				_finish(false, "aboard A's carrier, each should see the other (B sees A: %s, A sees B: %s)" % [fig != null, _a_saw_b_aboard])
				return
			c.view_at(c, Vector3(-4.0, 1.75, 18.5), Vector3(-9.6, 0.9, 14.0)) # from the side, to see A sitting
			_wait = 1.0
			_step = "lounge shot"
		"lounge shot":
			_shot("07-crew-lounge-with-another-pilot")
			var c = _explorer._station
			if not c._boards.aboard.text.contains(A_NAME) or not c._boards.aboard.text.contains("Spaces B"):
				_finish(false, "the lounge's ABOARD screen should list both: " + c._boards.aboard.text)
				return
			_finish(true, "docked at different berths of one copy (%d and %d), walked the carrier and the station seeing each other, was refused at A's closed carrier, and boarded it once open" % [int(_explorer._berth.pad), int(_a_pad.pad)])


## A point in the station's Carrier Berths (the hangar compartment), in the station's space.
func _hall(local: Vector3) -> Array:
	var p: Vector3 = _explorer._station._rooms[0].to_global(local)
	return [p.x, p.y, p.z]


## The other pilot: answers, and while docked says where its carrier lies.
func _poll_a(delta: float) -> void:
	_a.poll()
	while _a.get_available_packet_count() > 0:
		var msg = JSON.parse_string(_a.get_packet().get_string_from_utf8())
		if not (msg is Dictionary):
			continue
		match str(msg.get("type", "")):
			"welcome":
				_a_id = int(msg.id)
			"dock_granted":
				_a_pad = msg
			"walker":
				if str(msg.get("name", "")) == "Spaces B":
					var p: Array = msg.pos
					_a_seen.append(Vector3(p[0], p[1], p[2]))
					if _step in ["board", "aboard", "lounge", "lounge shot"]:
						_a_saw_b_aboard = true
			"error":
				print("server error (A): ", msg.get("reason", ""))
	_a_ship_in -= delta
	if not _a_pad.is_empty() and _a_ship_in <= 0.0 and _explorer._stations.has(STATION):
		_a_ship_in = 0.5
		var b: Dictionary = _explorer._berth_frame(int(_a_pad.pad))
		var r: Vector3 = (b.basis as Basis).get_euler()
		_send_a({"type": "ship", "pos": _explorer._berth_pos(STATION, int(_a_pad.pad)), "rot": [r.x, r.y, r.z], "over": STATION})


func _send_a(msg: Dictionary) -> void:
	if _a.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_a.send_text(JSON.stringify(msg))


func _shot(name: String) -> void:
	if _shots == "" or DisplayServer.get_name() == "headless":
		return
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_shots, name])
	print("saved ", name)


func _finish(ok: bool, what: String) -> void:
	if _done:
		return # the first result stands
	_done = true
	print(("PASS " if ok else "FAIL ") + "spaces: " + what)
	get_tree().quit(0 if ok else 1)
