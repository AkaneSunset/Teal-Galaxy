extends Node
## Supremacy, as a pilot plays it, against a running DEMO galaxy server with a short queue wait and
## fast battles:
##   cd server && SAVE_FILE=/tmp/supremacy.json DEMO=1 QUEUE_WAIT=2 BATTLE_SPEED=10 npm start   (delete /tmp/supremacy.json first)
##   godot --headless --path game res://tests/supremacy_test.tscn
## "Supremacy Tester" (Luminar Accord) flies its carrier into Cinder's orbit and queues for Supremacy.
## Alone, it goes in after the wait against the holder's (Compact) AI, 16 a side with fodder bots: the
## first-person view opens with the class menu up, offering the elite trooper. On the ground the HUD
## shows the round, the bars and the control points. At ten times speed the AI soon wins the ground
## for one side, the shuttles land, and the fight moves aboard a capital ship: the world is rebuilt
## with its blast doors and reactor. Then it leaves and is back with the explorer.
## `-- --server=ws://127.0.0.1:9000` for a server on another port, and `-- --shots=/some/dir` with a
## display to save screenshots. Prints PASS or FAIL and quits.

const ExplorerMode := preload("res://explorer.gd")
const PILOT := "Supremacy Tester"
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
var _saw_boarding := false
var _ship_name := ""


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
		"supremacy_joined":
			_joined = msg
		"supremacy_state":
			if str(msg.get("phase", "")) == "boarding":
				_saw_boarding = true


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
			_go("orbit")
		"orbit":
			if not _explorer._stations.has(PLANET):
				if _step_clock > 10.0:
					_finish(false, "Cinder's orbital station never showed up")
				return
			_explorer.teleport(_explorer.System.offset(_explorer._stations[PLANET].pos, Vector3(0, 0, 10_000)))
			_go("open", 1.0)
		"open":
			_menu = BattleMenu.open(self, PLANET)
			_go("queue", 0.5)
		"queue":
			var q := _buttons(_menu, "Queue: Supremacy")
			if q.is_empty() or q[0].disabled:
				_finish(false, "there should be a Queue button for Supremacy")
				return
			q[0].pressed.emit()
			_go("joined")
		"joined":
			if _joined.is_empty():
				if _step_clock > 15.0:
					_finish(false, "alone, the pilot should go in after the wait")
				return
			if str(_joined.get("side", "")) != "a" or str(_joined.get("factions", {}).get("d", "")) != "compact":
				_finish(false, "Luminar should fight the holder (Compact): %s" % str(_joined.get("factions", {})))
				return
			_go("view", 1.0)
		"view":
			var sv = load("res://supremacy/supremacy_view.gd")
			if not sv.active:
				_finish(false, "the Supremacy view should open by itself")
				return
			_view = get_tree().root.get_children().filter(func(n): return n is SupremacyView)[0]
			if not _explorer.Place.battle_active():
				_finish(false, "the explorer should know a match has the screen")
				return
			if _buttons(_view._classes, "elite trooper").is_empty():
				_finish(false, "the class menu should offer the elite trooper")
				return
			var count := {"a": 0, "d": 0, "fodder": 0}
			for row in _view._state.get("bodies", []):
				if int(row[13]) == 1:
					count.fodder += 1
				else:
					count[str(row[2])] += 1
			if count.a < 16 or count.d < 16 or count.fodder < 10:
				_finish(false, "16 a side and fodder bots: %s" % str(count))
				return
			_view._close_classes()
			await _shot("supremacy-01-ground")
			_go("ground")
		"ground":
			var top: String = _view._top.text
			if not top.contains("SUPREMACY") or not top.contains("Round 1") or not top.contains("Bars"):
				_finish(false, "the HUD should show the round and the bars: " + top)
				return
			if not _view._objective.text.contains("A:") or _view._points.size() < 3:
				_finish(false, "the control points should be on the map and the HUD: " + _view._objective.text)
				return
			_go("ship")
		"ship":
			if not _view._current.begins_with("ship"):
				if _step_clock > 150.0:
					_finish(false, "the AI should win the ground and board a ship")
				return
			if not _saw_boarding:
				_finish(false, "there should have been a boarding window")
				return
			_go("aboard_ship", 0.5)
		"aboard_ship":
			if _view._breakables.size() < 2 or not _view._top.text.contains("Reactor"):
				_finish(false, "aboard, the blast doors and reactor should be up: " + _view._top.text)
				return
			await _shot("supremacy-02-ship")
			_ship_name = str(_view._map().get("name", ""))
			_view.leave()
			_go("left", 1.0)
		"left":
			if load("res://supremacy/supremacy_view.gd").active or is_instance_valid(_view) and _view.is_inside_tree():
				_finish(false, "leaving should close the view")
				return
			_finish(true, "queued for Supremacy over Cinder, went in against the Compact's AI on %s, 16 a side with fodder bots, the elite trooper on offer, the ground's bars and points on the HUD, the boarding window, then aboard %s with its blast doors and reactor; left the match" % [str(_joined.get("map", {}).get("name", "")), _ship_name])


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
	print(("PASS " if ok else "FAIL ") + "supremacy: " + what)
	get_tree().quit(0 if ok else 1)
