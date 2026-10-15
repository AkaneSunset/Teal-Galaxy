extends Node
## Start screen. Picks Builder or Explorer mode, then connects to the galaxy server.
##
## Skip the screen with command-line options after `--`:
##   godot --path game -- --mode=builder --name=Akane --server=ws://192.168.1.20:8080

const DEFAULT_SERVER := "ws://127.0.0.1:8080"
const BuilderMode := preload("res://builder.gd")
const ExplorerMode := preload("res://explorer.gd")

var _name_edit: LineEdit
var _server_edit: LineEdit


func _ready() -> void:
	var opts := _parse_args()
	if opts.has("mode"):
		_start(opts.mode, opts.get("name", _default_name(opts.mode)), opts.get("server", DEFAULT_SERVER))
	else:
		_show_menu(opts.get("server", DEFAULT_SERVER))


func _parse_args() -> Dictionary:
	var opts := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg:
			var kv := arg.substr(2).split("=", true, 1)
			opts[kv[0]] = kv[1]
	return opts


func _default_name(mode: String) -> String:
	return "Builder" if mode == "builder" else "Pilot %d" % (randi() % 900 + 100)


func _show_menu(server: String) -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(320, 0)
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	var title := Label.new()
	title.text = "Teal Galaxy"
	title.add_theme_font_size_override("font_size", 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Your name"
	box.add_child(_name_edit)
	_server_edit = LineEdit.new()
	_server_edit.text = server
	box.add_child(_server_edit)

	var builder := Button.new()
	builder.text = "Builder (phone)"
	builder.pressed.connect(func(): _start_from_menu("builder"))
	box.add_child(builder)
	var explorer := Button.new()
	explorer.text = "Explorer (PC)"
	explorer.pressed.connect(func(): _start_from_menu("explorer"))
	box.add_child(explorer)


func _start_from_menu(mode: String) -> void:
	var n := _name_edit.text.strip_edges()
	_start(mode, n if n != "" else _default_name(mode), _server_edit.text.strip_edges())


func _start(mode: String, player_name: String, server: String) -> void:
	for child in get_children():
		child.queue_free()
	if mode == "builder" and not OS.has_feature("mobile"):
		# Phone-shaped window (held sideways) when testing the Builder on a PC.
		DisplayServer.window_set_size(Vector2i(1040, 480))
	get_window().title = "Teal Galaxy: %s (%s)" % [mode.capitalize(), player_name]
	Net.connect_to(server, mode, player_name)
	add_child(BuilderMode.new() if mode == "builder" else ExplorerMode.new())
