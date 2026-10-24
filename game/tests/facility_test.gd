extends Node
## Facility Battles, as a pilot plays it, against a running DEMO galaxy server with a short queue
## wait:
##   cd server && SAVE_FILE=/tmp/facility.json DEMO=1 QUEUE_WAIT=2 npm start   (delete /tmp/facility.json first)
##   godot --headless --path game res://tests/facility_test.tscn
## "Facility Tester" (Luminar Accord) flies its carrier into Cinder's orbit, opens the Sector Battles
## screen and queues for Facility Battles. Alone, it goes in after the wait against the holder's
## (Compact) AI troopers, its own side filled with AI: the first-person view opens by itself with the
## class menu up. It builds a class of its own in the Pick 10 editor (the server keeps it on its
## record), heads for the fight, aims at enemies it can see and fires until it hurts one, checks the
## HUD (rule, score, reinforcements) and the minimap, then leaves and is back with the explorer.
## `-- --server=ws://127.0.0.1:9000` for a server on another port, and `-- --shots=/some/dir` with a
## display to save screenshots. Prints PASS or FAIL and quits.

const ExplorerMode := preload("res://explorer.gd")
const PILOT := "Facility Tester"
const PLANET := "cinder"
const CLASS_ITEMS := ["rifle", "scope", "extmag", "pistol", "armor", "lightweight", "frag"]

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
var _fired_at := {} # enemy id -> its health when we fired at it
var _hurt := ""
var _last_pos := Vector3.ZERO
var _stuck_t := 0.0
var _side_step := 0.0


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
		"facility_joined":
			_joined = msg
		"facility_state":
			# Did an enemy we fired at lose health?
			for row in msg.get("bodies", []):
				var id := str(row[0])
				if _fired_at.has(id) and int(row[6]) < int(_fired_at[id]):
					_hurt = id


func _process(delta: float) -> void:
	_clock += delta
	_step_clock += delta
	if _done:
		return
	if _clock > 180.0:
		_finish(false, "timed out at step " + _step)
		return
	_wait -= delta
	if _wait > 0.0 or Net.state.is_empty():
		return
	_steps(delta)


func _go(step: String, wait := 0.0) -> void:
	_step = step
	_wait = wait
	_step_clock = 0.0
	print("step: ", step)


func _steps(delta: float) -> void:
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
			var q := _buttons(_menu, "Queue: Facility Battles")
			if q.is_empty() or q[0].disabled:
				_finish(false, "there should be a Queue button for Facility Battles")
				return
			q[0].pressed.emit()
			_go("joined")
		"joined":
			if _joined.is_empty():
				if _step_clock > 15.0:
					_finish(false, "alone, the pilot should go in after the wait")
				return
			if str(_joined.get("side", "")) != "a" or str(_joined.get("factions", {}).get("d", "")) != "compact":
				_finish(false, "Luminar should attack the holder (Compact): %s" % str(_joined.get("factions", {})))
				return
			_go("view", 1.0)
		"view":
			var fv = load("res://facility/facility_view.gd")
			if not fv.active:
				_finish(false, "the Facility Battles view should open by itself")
				return
			_view = get_tree().root.get_children().filter(func(n): return n is FacilityView)[0]
			if not _explorer.Place.battle_active():
				_finish(false, "the explorer should know a match has the screen")
				return
			if not _view._classes.visible:
				_finish(false, "the class menu should be up when the match starts")
				return
			# Both sides at 4 or more: AI troopers fill the slots.
			var sides := {"a": 0, "d": 0}
			for row in _view._state.get("bodies", []):
				sides[str(row[2])] += 1
			if sides.a < 4 or sides.d < 4:
				_finish(false, "AI troopers should fill both sides to 4: %s" % str(sides))
				return
			await _shot("facility-01-classes")
			_go("build")
		"build":
			# The Pick 10 editor: tick the class's items and save it.
			_view._open_editor(0)
			for item in _view._editor_checks:
				(_view._editor_checks[item] as CheckBox).button_pressed = CLASS_ITEMS.has(item)
			_view._editor_name.text = "Tester"
			_view._editor_count()
			if not _view._editor_points.text.begins_with("%d of 10" % CLASS_ITEMS.size()):
				_finish(false, "the editor should count the points: " + _view._editor_points.text)
				return
			await _shot("facility-02-pick10")
			_view.save_class()
			_go("saved", 0.5)
		"saved":
			var loadouts: Array = Net.state.get("pilots", {}).get(PILOT, {}).get("loadouts", [])
			var got: Array = loadouts[0].items.duplicate() if not loadouts.is_empty() and loadouts[0] is Dictionary else []
			var want: Array = CLASS_ITEMS.duplicate()
			got.sort()
			want.sort()
			if got != want:
				if _step_clock > 5.0:
					_finish(false, "the server should keep the class on the pilot: %s" % str(loadouts))
				return
			if str(_view._me.get("want", "")) != "custom:0":
				if _step_clock > 5.0:
					_finish(false, "the saved class should be the one to come back with")
				return
			_go("fight")
		"fight":
			if _hurt != "":
				if not _view._top.text.contains(str(_joined.get("ruleName", "?")).to_upper()) or not _view._top.text.contains("Reinforcements"):
					_finish(false, "the HUD should show the rule, score and reinforcements: " + _view._top.text)
					return
				await _shot("facility-03-fight")
				_go("halo")
				return
			if _step_clock > 120.0:
				_finish(false, "heading for the fight and firing at enemies in sight should hurt one")
				return
			_hunt(delta)
		"halo":
			# The Halo pass: power pads with timers, racks and callouts on the map, melee, medals,
			# the motion tracker's range, and the Postgame Carnage Report.
			if _view._pads.is_empty() or not _view._power_line.text.begins_with("Power:"):
				_finish(false, "the power pads should be on the map with their timers: '%s'" % _view._power_line.text)
				return
			if _view._where.text == "":
				_finish(false, "the HUD should name where you are (the nearest callout)")
				return
			if float(_view.info.get("trackerRange", 0)) <= 0.0 or not _view.info.get("gear", {}).has("wall"):
				_finish(false, "the match should send the motion tracker's range and the equipment")
				return
			_view.strike()
			if _view._clock - _view._jab_t > 0.01:
				_finish(false, "V should strike (melee)")
				return
			_view.show_medal("double")
			if _view._medal.text != "DOUBLE KILL":
				_finish(false, "a medal should show big on screen: " + _view._medal.text)
				return
			_view._show_report({"planet": PLANET, "mode": "facility", "rows": [
				{"name": PILOT, "side": "a", "ai": false, "kills": 3, "deaths": 1, "caps": 1, "medals": {"double": 1, "beatdown": 2}},
				{"name": "Trooper", "side": "d", "ai": true, "kills": 1, "deaths": 3, "caps": 0, "medals": {}}]})
			if _view._report_box.find_child("QueueAgain", true, false) == null or _view._report_box.get_child(1).get_child_count() != 15:
				_finish(false, "the Postgame Carnage Report should list everyone, with Queue again")
				return
			_view._banner.visible = true
			await _shot("facility-04-carnage")
			_view._banner.visible = false
			_view.leave()
			_go("left", 1.0)
		"left":
			if load("res://facility/facility_view.gd").active or is_instance_valid(_view) and _view.is_inside_tree():
				_finish(false, "leaving should close the view")
				return
			_finish(true, "queued for Facility Battles over Cinder, went in against the Compact's AI on %s (%s), AI filled both sides, built and saved a Pick 10 class, hurt an enemy it could see, saw the power pads, callouts, melee, a medal and the Carnage Report, left the match" % [str(_joined.get("map", {}).get("name", "")), str(_joined.get("ruleName", ""))])


## Heads for the nearest enemy (sliding along walls, stepping aside when stuck), and fires at the
## nearest one in sight.
func _hunt(delta: float) -> void:
	var cam: Camera3D = _view._camera
	var player: CharacterBody3D = _view._player
	var space := cam.get_world_3d().direct_space_state
	var best := ""
	var target := Vector3.ZERO
	var nearest := Vector3.ZERO
	var nd := INF
	for id in _view._bodies:
		var b: Dictionary = _view._bodies[id]
		if str(b.side) == _view.side or not bool(b.get("alive", true)):
			continue
		var at: Vector3 = (b.node as Node3D).global_position + Vector3(0, 1.1, 0)
		var d := at.distance_to(cam.global_position)
		if d < nd:
			nd = d
			nearest = at
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, at, 0xFFFFFFFF, [player.get_rid()])
		if not space.intersect_ray(q).is_empty() or d > 60.0:
			continue
		if best == "" or d < target.distance_to(cam.global_position):
			best = id
			target = at
	if not _view._alive():
		_view._close_classes()
		return
	if best != "":
		var to := target - cam.global_position
		player.rotation.y = atan2(-to.x, -to.z)
		_view._pitch = atan2(to.y, Vector2(to.x, to.z).length())
		cam.rotation.x = _view._pitch
		player.velocity = Vector3.ZERO
		if _view._fire_cd <= 0.0:
			for row in _view._state.get("bodies", []):
				if str(row[0]) == best and not _fired_at.has(best):
					_fired_at[best] = int(row[6])
			_view.fire()
		return
	if nd == INF:
		return
	# Walk: the view moves the player with W held; steer by turning, and step aside when stuck.
	var dir := Vector3(nearest.x - player.position.x, 0, nearest.z - player.position.z).normalized()
	if _side_step > 0.0:
		_side_step -= delta
		dir = dir.rotated(Vector3.UP, PI / 2)
	player.rotation.y = atan2(-dir.x, -dir.z)
	player.velocity = Vector3(dir.x, player.velocity.y, dir.z) * 5.0
	player.move_and_slide()
	_stuck_t += delta
	if _stuck_t > 1.0:
		if player.position.distance_to(_last_pos) < 1.5:
			_side_step = 1.2
		_last_pos = player.position
		_stuck_t = 0.0


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
	print(("PASS " if ok else "FAIL ") + "facility: " + what)
	get_tree().quit(0 if ok else 1)
