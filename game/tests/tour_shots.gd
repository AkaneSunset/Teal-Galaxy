extends Node
## Screenshots of the fleet carrier, inside and out, for looking over its looks (needs a display and
## a running DEMO server):
##   cd server && SAVE_FILE=/tmp/tour.json DEMO=1 npm start
##   godot --path game res://tests/tour_shots.tscn -- --shots=/some/dir
## The pilot "Tour Guide" (Terran Compact) parks in Cinder's orbit, takes a few views of the carrier
## from outside, leaves the seat and stands at each VIEWS spot in turn. Add
## `-- --server=ws://127.0.0.1:9000` for a server on another port. Quits when done.

const ExplorerMode := preload("res://explorer.gd")
const Carrier := preload("res://carrier.gd")
const WarInfo := preload("res://war_info.gd")
## [name, where you stand (eye), what you look at], in the carrier's coordinates.
const VIEWS := [
	["tour-bridge", Vector3(-3.0, 2.1, -50.0), Vector3(1.0, 1.4, -62.0)],
	["tour-bridge-back", Vector3(4.0, 1.9, -59.0), Vector3(-2.0, 1.2, -44.0)],
	["tour-command-deck", Vector3(1.5, 1.65, -16.0), Vector3(0, 2.4, -25.0)],
	["tour-war-log", Vector3(2.0, 1.8, -25.0), Vector3(11.8, 3.0, -25.0)],
	["tour-holo-close", Vector3(0.0, 1.65, -29.4), Vector3(0, 2.6, -25.0)],
	["tour-lounge", Vector3(-1.0, 1.65, 11.0), Vector3(-9.5, 1.0, 14.0)],
	["tour-lounge-bar", Vector3(-6.0, 1.7, 21.0), Vector3(7.0, 1.2, 12.0)],
	["tour-hangar", Vector3(14.0, -14.35, 40.0), Vector3(-6.0, -12.0, 0.0)],
	["tour-hangar-2", Vector3(-12.0, -14.0, -2.0), Vector3(6.0, -12.0, 40.0)],
]

var _explorer: Node
var _server := "ws://127.0.0.1:8080"
var _shots := ""
var _step := 0
var _wait := 1.0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--server="):
			_server = arg.substr(9)
		elif arg.begins_with("--shots="):
			_shots = arg.substr(8)
	get_window().size = Vector2i(1600, 900)
	Net.connect_to(_server, "explorer", "Tour Guide")
	_explorer = ExplorerMode.new()
	add_child(_explorer)


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0 or Net.state.is_empty() or not _explorer._stations.has("cinder"):
		return
	_wait = 1.2
	var st: Array = _explorer._stations.cinder.pos
	var step := _step
	_step += 1
	match step:
		0:
			Net.send({"type": "choose_faction", "faction": "compact"})
		1:
			if _explorer._panel_open():
				_explorer._close_panel()
			_explorer.teleport(_explorer.System.offset(st, Vector3(1500, 900, 8000)))
			_explorer.flight.basis = Basis.looking_at(Vector3(-1500, -900, -8000).normalized(), Vector3.UP)
			_explorer._set_outside(true)
		2:
			await _shot("tour-outside-1")
			_explorer.flight.basis = Basis.looking_at(Vector3(1, -0.1, 0.3).normalized(), Vector3.UP)
		3:
			await _shot("tour-outside-2")
			_explorer.flight.basis = Basis.looking_at(Vector3(-0.3, 0.2, 1).normalized(), Vector3.UP)
		4:
			await _shot("tour-outside-3")
			_explorer._set_outside(false)
			_explorer._leave_helm()
		_:
			var i := step - 5
			if i > 0:
				await _shot(VIEWS[i - 1][0])
			if i >= VIEWS.size():
				get_tree().quit(0)
				return
			var c = _explorer._station
			c.view_at(c, VIEWS[i][1], VIEWS[i][2])


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_shots, name])
	print("saved ", name)
