extends Node
## Sector Defense, as a pilot plays it, against a running DEMO galaxy server with a short queue wait
## and fast matches:
##   cd server && SAVE_FILE=/tmp/defense.json DEMO=1 QUEUE_WAIT=2 BATTLE_SPEED=3 npm start   (delete /tmp/defense.json first)
##   godot --headless --path game res://tests/defense_test.tscn
## "Defense Tester" (Luminar Accord) flies its carrier into Cinder's orbit, opens the Sector Battles
## screen and queues for Sector Defense. Alone, its squad goes in after the wait: the first-person
## view opens by itself. When the first wave comes it turns to the nearest enemy and fires until it
## falls (the server counts the kill), checks the HUD shows the set, wave and lives, then leaves the
## match and is back with the explorer.
## `-- --server=ws://127.0.0.1:9000` for a server on another port, and `-- --shots=/some/dir` with a
## display to save a screenshot of the fight. Prints PASS or FAIL and quits.

const ExplorerMode := preload("res://explorer.gd")
const PILOT := "Defense Tester"
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
var _kills := 0


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
		"defense_joined":
			_joined = msg
		"defense_state":
			_kills = int(msg.get("kills", 0))


func _process(delta: float) -> void:
	_clock += delta
	_step_clock += delta
	if _done:
		return
	if _clock > 120.0:
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
			var q := _buttons(_menu, "Queue: Sector Defense")
			if q.is_empty() or q[0].disabled:
				_finish(false, "there should be a Queue button for Sector Defense")
				return
			q[0].pressed.emit()
			_go("joined")
		"joined":
			if _joined.is_empty():
				if _step_clock > 15.0:
					_finish(false, "alone, the squad should go in after the wait")
				return
			if str(_joined.get("enemy", "")) != "compact" or str(_joined.get("faction", "")) != "luminar":
				_finish(false, "a Luminar squad should hold off the holder's (Compact) troops: %s" % str(_joined))
				return
			_go("view", 1.0)
		"view":
			var dv = load("res://defense/defense_view.gd")
			if not dv.active:
				_finish(false, "the Sector Defense view should open by itself")
				return
			_view = get_tree().root.get_children().filter(func(n): return n is DefenseView)[0]
			if is_instance_valid(_menu) and _menu.is_inside_tree() and not _menu.is_queued_for_deletion():
				_finish(false, "the Sector Battles screen should close when the match starts")
				return
			if not _explorer.Place.battle_active():
				_finish(false, "the explorer should know a match has the screen")
				return
			_go("wave")
		"wave":
			if _view._enemies.is_empty():
				if _step_clock > 20.0:
					_finish(false, "the first wave should come after the break")
				return
			_go("fight", 0.5)
			await _shot("defense-01-first-wave")
		"fight":
			if _kills > 0:
				if not _view._top.text.contains("Set 1 of 3") or not _view._top.text.contains("Lives"):
					_finish(false, "the HUD should show the set, wave and lives: " + _view._top.text)
					return
				_view.leave()
				_go("left", 1.0)
				return
			if _step_clock > 40.0:
				_finish(false, "aiming at the nearest enemy and firing should bring it down")
				return
			_aim_and_fire()
		"left":
			if load("res://defense/defense_view.gd").active or is_instance_valid(_view) and _view.is_inside_tree():
				_finish(false, "leaving should close the view")
				return
			_finish(true, "queued for Sector Defense over Cinder, went in alone after the wait against the Compact's troops, the first wave came, aimed and fired until one fell (%d kill%s), left the match" % [_kills, "" if _kills == 1 else "s"])


## Turns to the nearest enemy (its chest) and pulls the trigger once, as a player would.
func _aim_and_fire() -> void:
	var cam: Camera3D = _view._camera
	var best := {}
	for id in _view._enemies:
		var e: Dictionary = _view._enemies[id]
		if best.is_empty() or e.node.global_position.distance_to(cam.global_position) < best.node.global_position.distance_to(cam.global_position):
			best = e
	if best.is_empty():
		return
	# Its chest, or a drone's body up in the air.
	var target: Vector3 = best.node.global_position + Vector3(0, 3.9 if best.type == "drone" else 1.1, 0)
	var to := target - cam.global_position
	_view._player.rotation.y = atan2(-to.x, -to.z)
	_view._pitch = atan2(to.y, Vector2(to.x, to.z).length())
	_view._camera.rotation.x = _view._pitch
	if _view._fire_cd <= 0.0 and _view._reload_left <= 0.0:
		if _view._mag <= 0:
			_view._reload()
		else:
			_view._fire()


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
	print(("PASS " if ok else "FAIL ") + "defense: " + what)
	get_tree().quit(0 if ok else 1)
