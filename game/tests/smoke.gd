extends Node
## Headless smoke test of the two modes against a running galaxy server.
## Run the server, then in two terminals:
##   godot --headless --path game res://tests/smoke.tscn -- --role=builder
##   godot --headless --path game res://tests/smoke.tscn -- --role=explorer
## Each prints PASS or FAIL and quits.

const ExplorerMode := preload("res://explorer.gd")
const BuilderMode := preload("res://builder.gd")

var _role := "builder"
var _mode: Node
var _step := 0
var _clock := 0.0
var _saw_mine_prompt := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			_role = arg.substr(7)
	Net.connect_to("ws://127.0.0.1:8080", _role, "Smoke " + _role)
	_mode = BuilderMode.new() if _role == "builder" else ExplorerMode.new()
	add_child(_mode)
	Net.server_error.connect(func(r): print("server error: ", r))


func _process(delta: float) -> void:
	_clock += delta
	if _clock > 20:
		_finish(false, "timed out at step %d" % _step)
	if Net.state.is_empty():
		return
	if _role == "builder":
		_builder_steps()
	else:
		_explorer_steps()


func _builder_steps() -> void:
	match _step:
		0:
			Net.send({"type": "build", "planet": "aster", "slot": 0, "building": "spaceport"})
			_step = 1
		1:
			if Net.has_building("spaceport"):
				Net.send({"type": "post_job", "resource": "ice", "amount": 10, "reward": 100})
				_step = 2
		2:
			if Net.state.jobs.size() > 0 and Net.state.jobs[0].status == "done":
				_finish("hydroponics" in Net.state.unlocked and int(Net.state.stock.ice) == 10, "job done, ice in stock")


func _explorer_steps() -> void:
	match _step:
		0:
			if _mode._port.visible and not Net.open_job().is_empty():
				_mode.teleport(_mode.System.offset(_mode.rock_position(0), Vector3(0, 0, _mode._rocks[0].radius + 40)))
				for i in 10:
					Net.send({"type": "collect", "resource": "ice", "amount": 1})
				_step = 1
		1:
			_saw_mine_prompt = _saw_mine_prompt or _mode._prompt.text.contains("mine ice")
			if _mode._cargo("ice") == 10:
				_mode.teleport(_mode.System.offset(_mode.System.PORT_POS, Vector3(0, 0, 900)))
				Net.send({"type": "deliver", "job": int(Net.open_job().id)})
				_step = 2
		2:
			if Net.open_job().is_empty() and int(_mode._me().get("credits", 0)) == 100:
				_step = 3 # the HUD redraws on the explorer's next frame
		3:
			_finish(_saw_mine_prompt and _mode._info.text.contains("Credits 100"), "mined at the field, delivered and paid")


func _finish(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + _role + ": " + what)
	get_tree().quit(0 if ok else 1)
