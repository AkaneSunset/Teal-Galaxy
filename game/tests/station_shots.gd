extends Node
## Saves screenshots of a High Port: the approach, the docking prompt, and the transit menu.
##   godot --path game res://tests/station_shots.tscn -- --server=ws://127.0.0.1:9000 --shots=/some/dir

const ExplorerMode := preload("res://explorer.gd")

var _explorer: Node
var _server := "ws://127.0.0.1:8080"
var _shots := "/tmp"
var _plan := []
var _wait := 1.0


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
	if _plan.is_empty():
		_plan = [
			func(): return _view("aster", 3_200.0, 0.25, "1-aster-high-port-approach"),
			func(): return _view("aster", 900.0, 0.1, "2-aster-high-port-dock-prompt"),
			func(): _explorer.dock("aster"); return "3-aster-transit-menu",
			func(): _explorer._fly_to_base(); return "4-aster-base",
			func(): _explorer.undock(); return _view("brisa", 2_600.0, -0.35, "5-brisa-high-port-with-planet"),
			func(): _explorer.dock("brisa"); return "6-brisa-transit-menu",
			func(): get_tree().quit(),
		]
		_plan.append(null)
	var step = _plan.pop_front()
	if step == null:
		return
	var name = step.call()
	_wait = 1.5
	if name is String:
		await get_tree().create_timer(1.2).timeout
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_shots, name])
		print("saved ", name)


## Puts the ship `dist` metres from a High Port, on the side away from its planet, looking at it.
func _view(planet: String, dist: float, lift: float, name: String) -> String:
	var st: Dictionary = _explorer._stations[planet]
	var away: Vector3 = _explorer.System.diff(st.pos, _explorer.System.builder_planet(planet).pos).normalized()
	var from := (away + Vector3(0.6, lift, 0.0)).normalized() * dist
	_explorer.teleport(_explorer.System.offset(st.pos, from))
	_explorer.flight.basis = Basis.looking_at(-from, Vector3.UP)
	return name
