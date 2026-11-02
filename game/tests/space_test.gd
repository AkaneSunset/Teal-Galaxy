extends Node
## Space Battles, as a pilot plays it, against a running DEMO galaxy server with a short queue wait:
##   cd server && SAVE_FILE=/tmp/space.json DEMO=1 QUEUE_WAIT=2 npm start   (delete /tmp/space.json first)
##   godot --headless --path game res://tests/space_test.tscn
## "Space Tester" (Luminar Accord) flies its carrier into Cinder's orbit and queues for Space Battles.
## Alone, it goes in after the wait against the holder's (Compact) AI, 12 pilots a side and more AI in
## the sky: the cockpit view opens with the ship class picker up. It picks a Bomber (it launches as
## one at once), flies at the enemy capital ship with the flight model (the server follows it), targets
## a shield generator, closes to torpedo range and fires a torpedo when it's locked on (the server
## accepts it), checks the HUD, then leaves and is back with the explorer.
## `-- --server=ws://127.0.0.1:9000` for a server on another port, and `-- --shots=/some/dir` with a
## display to save screenshots. Prints PASS or FAIL and quits.

const ExplorerMode := preload("res://explorer.gd")
const PILOT := "Space Tester"
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
var _start_z := 0.0


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
		"starfight_joined":
			_joined = msg


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
			var q := _buttons(_menu, "Queue: Space Battles")
			if q.is_empty() or q[0].disabled:
				_finish(false, "there should be a Queue button for Space Battles")
				return
			q[0].pressed.emit()
			_go("joined")
		"joined":
			if _joined.is_empty():
				if _step_clock > 15.0:
					_finish(false, "alone, the pilot should go in after the wait (the screen says: %s)" % (_menu._status.text if is_instance_valid(_menu) else "closed"))
				return
			if str(_joined.get("side", "")) != "a" or str(_joined.get("factions", {}).get("d", "")) != "compact":
				_finish(false, "Luminar should fight the holder (Compact): %s" % str(_joined.get("factions", {})))
				return
			_go("view", 1.0)
		"view":
			var sv = load("res://space/space_view.gd")
			if not sv.active:
				_finish(false, "the Space Battles view should open by itself")
				return
			_view = get_tree().root.get_children().filter(func(n): return n is SpaceView)[0]
			if not _explorer.Place.battle_active():
				_finish(false, "the explorer should know a battle has the screen")
				return
			if not _view._picker.visible or _buttons(_view._picker, "Bomber").is_empty():
				_finish(false, "the ship class picker should be up, with the Bomber")
				return
			var count := {"a": 0, "d": 0}
			for row in _view._state.get("craft", []):
				count[str(row[2])] += 1
			if count.a < 18 or count.d < 18:
				_finish(false, "12 pilots a side and AI in the sky: %s" % str(count))
				return
			await _shot("space-01-launch")
			_buttons(_view._picker, "Bomber")[0].pressed.emit()
			_go("bomber")
		"bomber":
			if str(_view._me.get("cls", "")) != "bomber":
				if _step_clock > 5.0:
					_finish(false, "picked right after launch, the Bomber should launch at once")
				return
			_start_z = float(_view._me.get("z", 0))
			_go("target", 0.5)
		"target":
			_view.cycle_target()
			if not _view.target.begins_with("d:gen"):
				_finish(false, "a bomber should target a shield generator first, not '%s'" % _view.target)
				return
			_go("fly")
		"fly":
			# Fly at the target, full throttle, boosting when we can.
			var at: Vector3 = _view._target_pos()
			var flight = _view.flight
			flight.basis = Basis.looking_at((at - _view._pos).normalized(), Vector3.UP)
			flight.throttle = 1.0
			if flight.boost_ready():
				flight.step({"boost": true}, {"mass_locked": true}, 0.0)
			if not _view._alive():
				if _step_clock > 90.0:
					_finish(false, "kept being shot down on the way in")
				return
			if _view._pos.distance_to(at) < 2200.0 and _view.locked():
				if float(_view._me.get("z", 0)) - _start_z < 500.0:
					_finish(false, "the server should follow the ship's flight: z %s from %s" % [_view._me.get("z"), _start_z])
					return
				_view.fire_secondary()
				_go("torpedo")
				return
			if _step_clock > 90.0:
				_finish(false, "never got into torpedo range and locked: %d m" % roundi(_view._pos.distance_to(at)))
		"torpedo":
			if int(_view._me.get("torpedoes", 6)) >= 6:
				if _step_clock > 5.0:
					_finish(false, "the server should accept the torpedo")
				return
			var top: String = _view._top.text
			if not top.contains("SPACE BATTLE") or not _view._capitals.text.contains("Shield generators"):
				_finish(false, "the HUD should show the damage, the clock and the capital ships: " + top)
				return
			await _shot("space-02-attack")
			_view.leave()
			_go("left", 1.0)
		"left":
			if load("res://space/space_view.gd").active or is_instance_valid(_view) and _view.is_inside_tree():
				_finish(false, "leaving should close the view")
				return
			_finish(true, "queued for Space Battles over Cinder, went in against the Compact's AI (12 pilots a side and AI in the sky), launched as a Bomber, flew at the enemy capital ship, targeted a shield generator, locked on and fired a torpedo; left the battle")


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
	print(("PASS " if ok else "FAIL ") + "space: " + what)
	get_tree().quit(0 if ok else 1)
