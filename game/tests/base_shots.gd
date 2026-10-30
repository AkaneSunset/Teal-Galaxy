extends Node
## Screenshots of a Builder's home base, on the phone and landed on PC, for looking over the layout
## (needs a display and a running server with instant buildings and demo stock):
##   cd server && SAVE_FILE=/tmp/base.json DEMO=1 BUILD_SPEED=0 npm start
##   godot --path game res://tests/base_shots.tscn -- --shots=/some/dir
## The Builder "Planner" starts at Command Centre level 1 with the first nodes built, then levels
## it to 5 and builds everything. Add `-- --server=ws://127.0.0.1:9000` for another port.

const BuilderMode := preload("res://builder.gd")

var _server := "ws://127.0.0.1:8080"
var _shots := "."
var _builder: Node
var _plan := []
var _wait := 1.0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shots = arg.substr(8)
		if arg.begins_with("--server="):
			_server = arg.substr(9)
	get_window().size = Vector2i(1560, 720)
	Net.connect_to(_server, "builder", "Planner")
	_builder = BuilderMode.new()
	add_child(_builder)


func _process(delta: float) -> void:
	_wait -= delta
	if Net.state.is_empty() or Net.home == "" or _wait > 0:
		return
	if _plan.is_empty():
		_plan = [
			func(): Net.send({"type": "choose_faction", "faction": "compact"}),
			func(): _build(["spaceport", "extractor", "habitat"]),
			func(): return "1-base-level-1",
			func(): _builder.select_pad(8); _builder._show_page("info"); return "2-command-centre-info",
			func(): Net.send({"type": "set_bid", "item": "ice", "price": 6, "want": 40}),
			func(): _builder._show_page(""); _builder.select_pad(0); _builder._show_page("port"); return "2b-star-port",
			func(): _builder._show_page(""); _builder.select_pad(4); return "3-locked-node",
			func(): for i in 4: Net.send({"type": "upgrade_building", "planet": Net.home, "slot": 8}),
			func(): _build(["hydroponics", "warehouse", "power", "foundry", "dock"]); _builder.select_pad(-1),
			func(): return "4-base-level-5",
			func(): Net.send({"type": "set_ask", "item": "alloy", "price": 30}); for i in 2: Net.send({"type": "upgrade_building", "planet": Net.home, "slot": 1}),
			func(): _builder.select_pad(1); _builder._show_page("refinery"); return "4b-refineries",
			func(): _builder._show_page(""); _builder.select_pad(0); _builder._show_page("port"); _builder._port.get_parent().get_parent().scroll_vertical = 2400; return "4c-star-port-sell",
			func(): _builder._show_page(""); _builder.select_pad(-1),
			func(): _builder._zoom = 170.0; _builder._focus = Vector3(40, 0, 60); _builder._place_camera(); return "5-close-up",
			func(): get_tree().quit(),
		]
		_plan.append(null)
	var step = _plan.pop_front()
	if step == null:
		return
	var name = step.call()
	_wait = 1.5
	if name is String:
		await get_tree().create_timer(1.0).timeout
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_shots, name])
		print("saved ", name)


func _build(types: Array) -> void:
	for type in types:
		Net.send({"type": "build", "planet": Net.home, "slot": _builder.Layout.NODES.find(type), "building": type})
