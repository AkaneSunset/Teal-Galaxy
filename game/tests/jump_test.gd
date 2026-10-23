extends Node
## A fleet carrier's FTL jump, as a pilot makes it, against a running DEMO galaxy server (fleet
## carriers for everyone):
##   cd server && SAVE_FILE=/tmp/jump.json DEMO=1 npm start   (delete /tmp/jump.json first)
##   godot --headless --path game res://tests/jump_test.tscn
## "Jump Tester" (Luminar Accord), aboard its carrier in Teal Prime, uses the GALAXY MAP terminal on
## the Command Deck: picks Marrow Reach and jumps into Scar's orbit. After the spool-up the carrier is
## there: Marrow Reach's star and planets in the sky, Scar Orbital off the bow, Teal Prime's stations
## gone, and the server has it over Scar (it queues for Scar's campaign from there). Then it jumps
## back to the Teal Prime system and Aster High Port is back.
## `-- --server=ws://127.0.0.1:9000` for a server on another port, and `-- --shots=/some/dir` with a
## display to save screenshots. Prints PASS or FAIL and quits.

const ExplorerMode := preload("res://explorer.gd")
const PILOT := "Jump Tester"
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
var _jumps := 0
var _queued := ""
var _panel: Control


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
		"carrier_jump":
			_jumps += 1
		"campaign_queued":
			_queued = str(msg.get("planet", ""))


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
			_go("terminal", 1.0)
		"terminal":
			if not _explorer._stations.has("aster") or _explorer.System.current != "teal-prime":
				_finish(false, "should start in Teal Prime, by Aster High Port")
				return
			# The GALAXY MAP terminal: F.
			_explorer._on_service("jump")
			_panel = _explorer._jump_panel
			if not _panel.visible or _panel.selected != "teal-prime":
				_finish(false, "the galaxy map should open on the carrier's system")
				return
			_panel.select("marrow")
			await _shot("jump-01-galaxy-map")
			var b := _buttons(_panel, "Jump into orbit of Scar")
			if b.is_empty():
				_finish(false, "Marrow Reach should list Scar to jump to")
				return
			b[0].pressed.emit()
			_go("jumping")
		"jumping":
			if _jumps == 0:
				if _step_clock > 5.0:
					_finish(false, "the server should clear the jump")
				return
			if _explorer._jump_veil.color.a <= 0.0 and _step_clock < 2.0:
				return
			_go("arrived")
		"arrived":
			if _explorer.System.current != "marrow" or not _explorer._jump.is_empty():
				if _step_clock > 12.0:
					_finish(false, "the carrier should come out in Marrow Reach")
				return
			var ids: Array = _explorer.System.planets().map(func(p): return p.id)
			if ids != ["scar", "rift", "cairn"]:
				_finish(false, "Marrow Reach's planets should be in the sky: %s" % str(ids))
				return
			if _explorer._stations.has("aster") or _explorer._stations.has("cinder") or not _explorer._stations.has("scar"):
				_finish(false, "Teal Prime's stations should be gone and Marrow Reach's there: %s" % str(_explorer._stations.keys()))
				return
			if _explorer._over_planet() != "scar":
				_finish(false, "the carrier should be in Scar's orbit")
				return
			await _shot("jump-02-scar")
			_go("queue", 1.5)
		"queue":
			# The server has the carrier over Scar: its campaign can be queued for from here.
			Net.send({"type": "campaign_queue", "planet": "scar", "mode": "sector"})
			_go("queued")
		"queued":
			if _queued != "scar":
				if _step_clock > 5.0:
					_finish(false, "aboard the carrier in Scar's orbit, the pilot should be able to queue there")
				return
			Net.send({"type": "campaign_unqueue"})
			_explorer._on_service("jump")
			_panel.select("teal-prime")
			_buttons(_panel, "Jump to the Teal Prime system")[0].pressed.emit()
			_go("home")
		"home":
			if _explorer.System.current != "teal-prime" or not _explorer._stations.has("aster") or not _explorer._jump.is_empty():
				if _step_clock > 15.0:
					_finish(false, "the jump home should bring back Teal Prime and Aster High Port")
				return
			_finish(true, "from the GALAXY MAP aboard the carrier, jumped into Scar's orbit in Marrow Reach (its star, planets and orbital station there, Teal Prime's gone), queued for Scar's campaign from its orbit, and jumped home to Teal Prime")


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
	print(("PASS " if ok else "FAIL ") + "jump: " + what)
	get_tree().quit(0 if ok else 1)
