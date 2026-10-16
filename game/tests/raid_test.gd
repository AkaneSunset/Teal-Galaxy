extends Node
## Plays a whole raid against a running galaxy server, the way a player would:
## a Builder founds a facility's satellite site and places defences on it, the pilot flies there,
## lands, blows up the power plant, walks in through the blast door, rides the lifts down to the
## deepest level, searches containers until the keycard turns up, opens the safe room's vault,
## takes something from it, rides back up before the self-destruct, and boards the ship.
## (Selling it is covered by the server tests.)
##   cd server && DEMO=1 BUILD_SPEED=0 npm start
##   godot --headless --path game res://tests/raid.tscn
## Add `-- --shots=/some/dir` and run with a display to save screenshots along the way.
## Prints PASS or FAIL and quits.

const ExplorerMode := preload("res://explorer.gd")

var _explorer: Node
var _raid: Node
var _step := "build"
var _clock := 0.0
var _wait := 0.0
var _queue: Array = [] # containers left to search
var _searching := ""
var _search_time := 0.0
var _result := {}
var _shots := ""
var _shot_n := 0
var _took_from_vault := false
var _builder := WebSocketPeer.new() # a second connection playing the Builder who owns the site
var _key := "" # the site's key in the explorer's facility list
var _laid_out := false
var _overview: Camera3D


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shots = arg.substr(8)
	Net.connect_to("ws://127.0.0.1:8080", "explorer", "Raid Tester")
	_explorer = ExplorerMode.new()
	add_child(_explorer)
	Net.server_error.connect(func(r): print("server: ", r))
	Net.raid_event.connect(func(m): if m.ev == "end": _result = m.result)


func _process(delta: float) -> void:
	_clock += delta
	_wait -= delta
	if _clock > 150:
		_finish(false, "timed out at step " + _step)
	if Net.state.is_empty() or _wait > 0:
		return
	match _step:
		"build":
			if _builder.get_ready_state() == WebSocketPeer.STATE_CLOSED:
				_builder.connect_to_url("ws://127.0.0.1:8080")
			_builder.poll()
			if _builder.get_ready_state() != WebSocketPeer.STATE_OPEN:
				return
			_builder.send_text(JSON.stringify({"type": "hello", "role": "builder", "name": "Raid Test Builder"}))
			_builder.send_text(JSON.stringify({"type": "found_site", "facility": "refinery"}))
			_step = "fly"
		"fly":
			_builder.poll()
			if _facility().is_empty() or not _explorer._facilities.has(_facility().planet):
				return
			_key = _facility().planet
			if not _laid_out:
				# The Builder lays out defences (trying a few spots, as obstacles may be in the way)
				# and upgrades the facility to level 3, so the raid has three levels below.
				_laid_out = true
				for spot in [["power", 0, 0], ["power", 10, 10], ["power", 0, 10], ["power", 10, 0],
						["turret", 2, 8], ["turret", 8, 2], ["guardpost", 9, 6], ["guardpost", 1, 4],
						["wall", 5, 1], ["wall", 6, 1], ["wall", 11, 5]]:
					_send_builder({"type": "place_piece", "planet": _key, "piece": spot[0], "x": spot[1], "y": spot[2]})
				for i in 2:
					_send_builder({"type": "upgrade_building", "planet": _key, "slot": 0})
				_wait = 1.5
				return
			if int(Net.planet(_key).buildings[0].get("level", 1)) < 3:
				_send_builder({"type": "upgrade_building", "planet": _key, "slot": 0})
				_wait = 0.5
				return
			_explorer.teleport(_explorer.System.offset(_explorer._facilities[_key].pos, Vector3(0, 0, 900)))
			_wait = 0.5
			_step = "board"
		"board":
			_shot("1-at-facility")
			if not _explorer._prompt.text.contains("board"):
				_finish(false, "no boarding prompt: " + _explorer._prompt.text)
			_explorer.board(_key)
			_step = "inside"
		"inside":
			_raid = _explorer._raid
			if _raid == null:
				return
			_raid.god_mode = true
			# The outside is the site exactly as the Builder laid it out, drawn by the Builder's own view.
			var placed: Array = Net.planet(_key).get("pieces", []).map(func(p): return [int(p.id), p.type, int(p.x), int(p.y)])
			var mirrored: Array = _raid.layout.view.pieces.map(func(p): return [int(p.id), p.type, int(p.x), int(p.y)])
			if placed.is_empty() or JSON.stringify(placed) != JSON.stringify(mirrored):
				_finish(false, "raid site %s is not the Builder's %s" % [mirrored, placed])
			for id in _raid._pieces:
				if _raid._pieces[id].model == null:
					_finish(false, "no Builder model for piece " + id)
			if _raid.floors != 3:
				_finish(false, "a level 3 facility should have 3 levels, not %d" % _raid.floors)
			for c in _raid.layout.containers:
				if c.type != "vault" and int(c.floor) == _raid.floors:
					_queue.append(c.id)
			_wait = 1.0
			_step = "overview"
		"overview":
			# A look from above, to compare with the Builder's view of the same site.
			_shot("1b-landed")
			_overview = Camera3D.new()
			_overview.far = 1500.0
			_raid.add_child(_overview)
			_overview.global_position = Vector3(0, 70, 60)
			_overview.look_at(Vector3(0, 0, 4), Vector3.UP)
			_overview.make_current()
			_wait = 0.3
			_step = "overview-shot"
		"overview-shot":
			_shot("0-overview")
			_raid._camera.make_current()
			_overview.queue_free()
			_wait = 0.2
			_step = "breach"
		"breach":

			var power := ""
			for id in _raid._pieces:
				if _raid._pieces[id].data.type == "power":
					power = id
			if power == "":
				_finish(false, "the Builder's power plant isn't in the raid")
			_raid.destroy_piece(power)
			_wait = 0.6
			_step = "door"
		"door":
			if not _raid.door_open:
				return
			_raid.teleport_to(_raid._door_outside())
			_shot("1c-blast-door-open")
			_raid._interact()
			_step = "inside-core"
		"inside-core":
			if not _raid.breached or _raid._floor != 1:
				return
			_step = "down"
		"down":
			if _raid._floor == _raid.floors:
				_shot("2-deepest-level")
				_step = "search"
				return
			for l in _raid._lifts:
				if _raid._floor_of(l.pos) == _raid._floor and int(l.to_floor) == _raid._floor + 1:
					_raid.teleport_to(l.pos)
					_raid._interact()
					_shot("2-level-%d" % (_raid._floor))
					_wait = 0.3
					return
			_finish(false, "no lift down from level %d" % _raid._floor)
		"search":
			_shot("2-inside")
			if _raid.vault_open or _raid._holding("keycard"):
				_step = "vault"
			elif _searching == "":
				if _queue.is_empty():
					_finish(false, "searched everything, no keycard")
				_searching = _queue.pop_front()
				_go_to_container(_searching)
				_raid.open_container(_searching)
				_search_time = 0.0
			else:
				_search_time += delta
				var slots: Array = _raid._inv._slots
				if _search_time > 0.5 and slots.all(func(s): return s.has("item")):
					for s in slots:
						if s.item == "keycard":
							Net.send({"type": "raid_take", "uid": s.uid, "to": "backpack"})
					_shot("3-searched")
					_wait = 0.4
					_raid._close_inventory()
					_searching = ""
				elif _search_time > 8.0:
					_finish(false, "search never finished")
		"vault":
			if not _raid.vault_open:
				var slab: Node3D = _raid._vault_doors[0]
				var centre: Vector3 = _raid._vault_room_centre
				_raid.teleport_to(slab.global_position + (slab.global_position - centre).normalized() * Vector3(1, 0, 1) * 1.2)
				_raid._interact()
				_wait = 0.6
				return
			var box := ""
			for c in _raid.layout.containers:
				if c.type == "vault":
					box = c.id
			if _raid.self_destruct < 0.0:
				_finish(false, "opening the vault didn't start the self-destruct")
			_go_to_container(box)
			_raid.open_container(box)
			_search_time = 0.0
			_step = "loot"
		"loot":
			_search_time += delta
			var slots: Array = _raid._inv._slots
			if _search_time > 0.5 and slots.all(func(s): return s.has("item")):
				_shot("4-vault")
				for s in slots:
					Net.send({"type": "raid_take", "uid": s.uid, "to": "backpack"})
					_took_from_vault = true
				_wait = 0.5
				_step = "extract"
			elif _search_time > 10.0:
				_finish(false, "vault search never finished")
		"extract":
			_raid._close_inventory()
			_shot("5-self-destruct")
			if _raid._floor == 0:
				_raid.teleport_to(_raid._extract_nodes["ship"].pos)
				_step = "extracting"
				return
			for l in _raid._lifts:
				if _raid._floor_of(l.pos) == _raid._floor and int(l.to_floor) == _raid._floor - 1:
					_raid.teleport_to(l.pos)
					_raid._interact()
					_wait = 0.3
					return
			_finish(false, "no lift up from level %d" % _raid._floor)
		"extracting":
			if not _result.is_empty():
				if _result.outcome != "extracted":
					_finish(false, "outcome " + _result.outcome)
				_wait = 0.5
				_step = "results"
		"results":
			_shot("6-results")
			_raid.finished.emit(_result)
			_wait = 0.5
			_step = "sell"
		"sell":
			if _explorer._raid != null:
				_finish(false, "still in the raid after leaving")
			if _explorer._info.text.contains("Raided loot"):
				_shot("7-back-in-the-ship")
				_finish(_took_from_vault, "raided the vault, extracted with %d stacks worth %d credits, back in the ship" % [_result.kept.size(), int(_result.value)])


func _send_builder(msg: Dictionary) -> void:
	_builder.send_text(JSON.stringify(msg))


func _facility() -> Dictionary:
	for f in Net.facilities():
		if Net.planet(f.planet).get("owner", "") == "Raid Test Builder":
			return f
	return {}


func _go_to_container(id: String) -> void:
	var node: Node3D = _raid._containers[id].node
	var c: Dictionary = _raid._containers[id].data
	var centre: Vector3 = _raid._room_centre(int(c.room))
	var flat := (centre - node.global_position) * Vector3(1, 0, 1)
	_raid.teleport_to(node.global_position + flat.normalized() * 1.3)


func _shot(name: String) -> void:
	if _shots == "" or DisplayServer.get_name() == "headless":
		return
	_shot_n += 1
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_shots, name])


func _finish(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + "raid: " + what)
	get_tree().quit(0 if ok else 1)
