extends Node
## Plays a whole raid against a running galaxy server, the way a player would:
## build a facility, fly to it, board, search containers until the keycard turns up,
## open the vault, take something from it, extract at the Shuttle Pad, and fly on with the loot.
## (Selling it is covered by the server tests.)
##   cd server && npm start
##   godot --headless --path game res://tests/raid.tscn
## Add `-- --shots=/some/dir` and run with a display to save screenshots along the way.
## Prints PASS or FAIL and quits.

const ExplorerMode := preload("res://explorer.gd")
const SLOT := 3

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
			Net.send({"type": "build", "planet": "aster", "slot": SLOT, "building": "refinery"})
			_step = "fly"
		"fly":
			if _facility().is_empty():
				return
			_explorer.teleport(_explorer.System.offset(_explorer.System.facility_pos(SLOT), Vector3(0, 0, 900)))
			_wait = 0.5
			_step = "board"
		"board":
			_shot("1-at-facility")
			if not _explorer._prompt.text.contains("board"):
				_finish(false, "no boarding prompt: " + _explorer._prompt.text)
			_explorer.board(SLOT)
			_step = "inside"
		"inside":
			_raid = _explorer._raid
			if _raid == null:
				return
			_raid.god_mode = true
			for c in _raid.layout.containers:
				if c.type != "vault":
					_queue.append(c.id)
			_wait = 1.0
			_step = "search"
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
			_raid.teleport_to(_raid._extract_nodes["shuttle"].pos)
			_step = "extracting"
		"extracting":
			if _clock > 0 and int(_clock * 10) % 50 == 0:
				_shot("5-extracting")
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


func _facility() -> Dictionary:
	for f in Net.facilities():
		if f.slot == SLOT:
			return f
	return {}


func _go_to_container(id: String) -> void:
	var node: Node3D = _raid._containers[id].node
	var c: Dictionary = _raid._containers[id].data
	var centre: Vector3 = _raid._room_centre(int(c.room))
	_raid.teleport_to(node.global_position + (centre - node.global_position).normalized() * Vector3(1, 0, 1) * 1.3)


func _shot(name: String) -> void:
	if _shots == "" or DisplayServer.get_name() == "headless":
		return
	_shot_n += 1
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_shots, name])


func _finish(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + "raid: " + what)
	get_tree().quit(0 if ok else 1)
