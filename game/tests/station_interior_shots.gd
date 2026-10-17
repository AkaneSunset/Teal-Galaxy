extends Node
## Walks into a High Port and saves a screenshot of every compartment.
##   godot --path game res://tests/station_interior_shots.tscn -- --server=ws://127.0.0.1:9000 --shots=/some/dir
## Add `--planet=brisa` for another planet's High Port.

const ExplorerMode := preload("res://explorer.gd")

# [file name, slot (-1 = station centre), eye position, point looked at], in each slot's own space.
const SPOTS := [
	["01-hangar", 0, Vector3(-6, 1.65, 3), Vector3(6, 1.0, 24)],
	["01b-hangar-your-ship-ramp", 0, Vector3(8.5, 1.65, 18.0), Vector3(13, 1.4, 27)],
	["01c-hangar-open-and-locked-ships", 0, Vector3(-1.0, 1.65, 9.0), Vector3(-13, 2.5, 26)],
	["01d-ring-by-hangar-door", -1, Vector3(25.5, 1.65, 12.0), Vector3(29, 1.5, -4)],
	["02-hangar-pad-board", 0, Vector3(4, 1.65, 4), Vector3(-17, 3.5, 12)],
	["03-concourse-ring", -1, Vector3(25.5, 1.65, -3.5), Vector3(19, 1.6, 16)],
	["04-terminal-hall", -1, Vector3(-3, 1.65, -15), Vector3(0, 3.6, 0)],
	["05-ship-services", 2, Vector3(3.5, 1.65, 1.5), Vector3(-1, 1.8, 11)],
	["06-supply-shop", 3, Vector3(3.5, 1.65, 1.2), Vector3(-3, 1.4, 6)],
	["07-commodity-exchange", 4, Vector3(4.5, 1.65, 1.0), Vector3(-2, 2.6, 12)],
	["08-job-board", 5, Vector3(-1.5, 1.65, 1.2), Vector3(1, 2.4, 10)],
	["09-cantina", 6, Vector3(5.5, 1.65, 1.2), Vector3(-4, 1.2, 9)],
	["10-fence-noodles", 7, Vector3(3.5, 1.65, 1.0), Vector3(-2, 1.4, 6)],
	["11-fence-back-room", 7, Vector3(0, 1.65, 6.0), Vector3(1.5, 1.4, 15)],
	["12-security-office", 8, Vector3(3.5, 1.65, 1.0), Vector3(-1, 2.2, 10)],
	["13-crew-cabins", 9, Vector3(0, 1.65, 1.0), Vector3(0, 1.4, 30)],
	["14-observation-lounge", 10, Vector3(3.0, 1.65, 2.0), Vector3(-3.5, 1.3, 12)],
	["15-observation-console", 10, Vector3(-2.0, 1.65, 6.0), Vector3(-4.5, 1.2, 4.0)],
]

var _explorer: Node
var _server := "ws://127.0.0.1:8080"
var _shots := "/tmp"
var _planet := "aster"
var _i := -1
var _wait := 2.0
var _flown := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shots = arg.substr(8)
		elif arg.begins_with("--server="):
			_server = arg.substr(9)
		elif arg.begins_with("--planet="):
			_planet = arg.substr(9)
	get_window().size = Vector2i(1600, 900)
	Net.connect_to(_server, "explorer", "Photographer")
	_explorer = ExplorerMode.new()
	add_child(_explorer)


func _process(delta: float) -> void:
	_wait -= delta
	if Net.state.is_empty() or _wait > 0:
		return
	if _i == -1:
		if not _explorer._stations.has(_planet):
			return
		_explorer.dock(_planet)
		_explorer._leave_seat()
		_i = 0
		_wait = 2.0
		return
	if _i == SPOTS.size():
		# Walk onto your own ship's ramp, which should sit you back down in it.
		var st = _explorer._station
		for sh in st._ships:
			if sh.mine:
				st._player.global_position = sh.entry.global_position + Vector3(0, -0.2, 0)
		_i += 1
		_wait = 1.5
		return
	if _i == SPOTS.size() + 1:
		print("PASS ramp seats you in your ship" if _explorer._station.seated and _explorer._dock_panel.visible else "FAIL ramp did not seat you")
		_save("16-seated-in-your-ship-hangar")
		_i += 1
		_wait = 1.5
		return
	if _i == SPOTS.size() + 2 and not _flown:
		_flown = true
		_explorer._fly_to_base()
		_wait = 3.0
		return
	if _i == SPOTS.size() + 2:
		_save("20-base-seated-in-your-ship")
		_explorer._leave_seat()
		_i += 1
		_wait = 1.5
		return
	if _i == SPOTS.size() + 3:
		_save("21-base-on-foot")
		_explorer._station.view_at(_explorer._station, Vector3(-20, 1.65, -30), Vector3(0, 6, 0))
		_i += 1
		_wait = 1.5
		return
	if _i == SPOTS.size() + 4:
		_save("22-base-from-the-plate-edge")
		_i += 1
		_wait = 1.5
		return
	if _i > SPOTS.size() + 4:
		get_tree().quit()
		return
	var spot: Array = SPOTS[_i]
	_explorer._station.view(spot[1], spot[2], spot[3])
	_i += 1
	_wait = 1.0
	await get_tree().create_timer(0.7).timeout
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_shots, spot[0]])
	print("saved ", spot[0])


func _save(name: String) -> void:
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_shots, name])
	print("saved ", name)
