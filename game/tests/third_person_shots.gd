extends Node
## Walks on foot in third person (the default) and first person, and saves pictures of each: aboard
## your carrier (Bridge, Hangar Deck), in a High Port and on a Builder's base.
##   godot --path game res://tests/third_person_shots.tscn -- --server=ws://127.0.0.1:9000 --shots=/some/dir
## Prints PASS or FAIL lines for: your own figure shows only in third person, the camera sits behind
## your head in third person and at your eyes in first, V switches, and a wall pulls the camera in.

const ExplorerMode := preload("res://explorer.gd")
const Station := preload("res://station.gd")
const Surface := preload("res://surface.gd")

var _explorer: Node
var _server := "ws://127.0.0.1:8080"
var _shots := "/tmp"
var _wait := 2.0
var _step := 0
var _joined := false
var _fails := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shots = arg.substr(8)
		elif arg.begins_with("--server="):
			_server = arg.substr(9)
	get_window().size = Vector2i(1600, 900)
	Net.connect_to(_server, "explorer", "Photographer")
	_explorer = ExplorerMode.new()
	add_child(_explorer)


func _process(delta: float) -> void:
	_wait -= delta
	if Net.state.is_empty() or _wait > 0:
		return
	if _explorer._me().get("faction") == null:
		if not _joined:
			_joined = true
			Net.send({"type": "choose_faction", "faction": "compact"})
		return
	var p = _explorer._station
	_wait = 1.2
	match _step:
		0: # docked at Aster in your carrier, then up out of the pilot's chair
			if not _explorer._stations.has("aster"):
				_wait = 0.5
				return
			_explorer.controls.foot_third_person = true
			_explorer.dock("aster")
		1:
			_explorer._leave_seat()
			p.arrive("bridge")
		2:
			_check_third(p, "carrier bridge")
			_save("1-carrier-bridge-third-person")
			p._look(PI * 0.9, 0.0)
		3:
			_save("2-carrier-bridge-turned")
			p.arrive("hangar")
		4:
			_save("3-carrier-hangar-third-person")
			# Walk forward a while: the figure's legs should swing.
			Input.action_press("foot_forward")
			_wait = 0.8
		5:
			_save("4-carrier-hangar-walking")
			Input.action_release("foot_forward")
			_key_v(p)
		6:
			_check_first(p, "after V")
			_save("5-carrier-hangar-first-person")
			_key_v(p)
		7:
			_check_third(p, "after V again")
			_explorer._land_in(Station.new("aster"), false)
		8:
			_explorer._leave_seat()
		9:
			p = _explorer._station
			p.view(-1, Vector3(25.5, 1.65, -3.5), Vector3(19, 1.6, 16))
		10:
			_check_third(p, "station")
			_save("6-station-concourse-third-person")
			# The cantina's doorway, the wall close behind you: the camera must stay in the room.
			p.view(6, Vector3(5.5, 1.65, 1.2), Vector3(-4, 1.2, 9))
		11:
			_wall_test(p)
			_save("7-station-cantina-wall-behind")
			p.view(-1, Vector3(-3, 1.65, -15), Vector3(0, 3.6, 0))
		12:
			_save("8-station-terminal-hall-third-person")
			_explorer._land_in(Surface.new("aster"), true)
		13:
			_explorer._leave_seat()
		14:
			_check_third(_explorer._station, "base")
			_save("9-base-on-foot-third-person")
		_:
			print("DONE third person: %d failed" % _fails)
			get_tree().quit(1 if _fails > 0 else 0)
			return
	_step += 1


func _key_v(p: Node) -> void:
	var e := InputEventAction.new()
	e.action = "foot_camera"
	e.pressed = true
	p._unhandled_input(e)


func _check_third(p: Node, where: String) -> void:
	var cam: Camera3D = p._camera
	var behind: float = (cam.global_position - p._player.to_global(Vector3(0, p.EYE, 0))).length()
	_expect(p._self.visible, "your own figure shows in third person (%s)" % where)
	_expect(behind > 0.5, "the camera sits behind your head in third person (%s): %.2f m" % [where, behind])
	_expect(not p._prompt.get_parent().get_node("Crosshair").visible, "no crosshair in third person (%s)" % where)


func _check_first(p: Node, where: String) -> void:
	var cam: Camera3D = p._camera
	var off: float = (cam.global_position - p._player.to_global(Vector3(0, p.EYE, 0))).length()
	_expect(not p._self.visible, "your own figure is hidden in first person (%s)" % where)
	_expect(off < 0.01, "the camera is at your eyes in first person (%s): %.2f m" % [where, off])


## With a wall close behind you, the camera is pulled in short of it: nothing between it and your head.
func _wall_test(p: Node) -> void:
	var space: PhysicsDirectSpaceState3D = p.get_world_3d().direct_space_state
	var cam: Camera3D = p._camera
	var head: Vector3 = p._player.to_global(Vector3(0, p.EYE, 0))
	_expect(head.distance_to(cam.global_position) < p.THIRD_BACK, "the wall behind you pulls the camera in")
	var q2 := PhysicsRayQueryParameters3D.create(head, cam.global_position)
	q2.exclude = [p._player.get_rid()]
	_expect(space.intersect_ray(q2).is_empty(), "the camera stays this side of the wall (%.2f m behind your head)" % head.distance_to(cam.global_position))


func _expect(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _save(name: String) -> void:
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_shots, name])
	print("saved ", name)
