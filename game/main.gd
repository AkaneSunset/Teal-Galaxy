extends Node
## Start screen. Picks Builder or Explorer mode, then connects to the galaxy server.
##
## Skip the screen with command-line options after `--`:
##   godot --path game -- --mode=builder --name=Akane --server=ws://192.168.1.20:8080
##   (add --account=<name> --password=<password> to sign in; a server that isn't in demo mode
##   needs it, and the first sign-in with a new account name opens that account)

const DEFAULT_SERVER := "ws://127.0.0.1:8080"
const START_PATH := "user://start.cfg" # the name, account and server last typed on the start screen (never the password)
const BuilderMode := preload("res://builder.gd")
const ExplorerMode := preload("res://explorer.gd")

var _name_edit: LineEdit
var _account_edit: LineEdit
var _password_edit: LineEdit
var _server_edit: LineEdit
var _key_edit: LineEdit
var _mode: Node # the Builder or Explorer, once started


func _ready() -> void:
	var opts := _parse_args()
	if opts.has("mode"):
		_start(opts.mode, opts.get("name", _default_name(opts.mode)), opts.get("server", DEFAULT_SERVER), opts.get("account", ""), opts.get("password", ""))
	else:
		var last := ConfigFile.new()
		last.load(START_PATH)
		_show_menu(opts.get("server", last.get_value("start", "server", DEFAULT_SERVER)), last.get_value("start", "name", ""), last.get_value("start", "account", ""))


## Android's back button: the mode closes what's open first (Builder: back_pressed()), else quit.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _mode == null or not _mode.has_method("back_pressed") or not _mode.back_pressed():
			get_tree().quit()


func _parse_args() -> Dictionary:
	var opts := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg:
			var kv := arg.substr(2).split("=", true, 1)
			opts[kv[0]] = kv[1]
	return opts


func _default_name(mode: String) -> String:
	return "Builder" if mode == "builder" else "Pilot %d" % (randi() % 900 + 100)


func _show_menu(server: String, last_name: String, last_account: String) -> void:
	var phone := OS.has_feature("mobile")
	if phone:
		# Finger-sized on a dense phone screen, as in the Builder.
		var win := get_window()
		win.content_scale_factor = clampf(mini(win.size.x, win.size.y) / 400.0, 1.0, 3.0)
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

	# Sign in once, play several characters: the account owns each character it has played.
	_account_edit = LineEdit.new()
	_account_edit.placeholder_text = "Account"
	_account_edit.text = last_account
	box.add_child(_account_edit)
	_password_edit = LineEdit.new()
	_password_edit.placeholder_text = "Password (a new account name opens an account)"
	_password_edit.secret = true
	box.add_child(_password_edit)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Character name"
	_name_edit.text = last_name
	box.add_child(_name_edit)
	_server_edit = LineEdit.new()
	_server_edit.text = server
	_server_edit.placeholder_text = "ws://<your computer's address>:8080"
	box.add_child(_server_edit)
	# The galaxy's admins only (the same key as in Settings on PC): saved for the server above,
	# and it never goes to any other.
	_key_edit = LineEdit.new()
	_key_edit.placeholder_text = "Admin key (only if you run this galaxy)"
	_key_edit.secret = true
	_key_edit.text = Net.saved_admin_key(server)
	box.add_child(_key_edit)
	_server_edit.text_changed.connect(func(t): _key_edit.text = Net.saved_admin_key(t))

	var builder := Button.new()
	builder.text = "Builder (phone)"
	builder.pressed.connect(func(): _start_from_menu("builder"))
	box.add_child(builder)
	if phone:
		builder.text = "Play"
		var hint := Label.new()
		hint.text = "Run the galaxy server on your computer, then type its address above.\nBoth devices need to be on the same Wi-Fi."
		hint.add_theme_font_size_override("font_size", 12)
		hint.modulate = Color(0.7, 0.85, 0.9)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(hint)
	else: # flying needs a keyboard and mouse: the phone only builds
		var explorer := Button.new()
		explorer.text = "Explorer (PC)"
		explorer.pressed.connect(func(): _start_from_menu("explorer"))
		box.add_child(explorer)


func _start_from_menu(mode: String) -> void:
	var n := _name_edit.text.strip_edges()
	var server := _server_edit.text.strip_edges()
	Net.save_admin_key(server, _key_edit.text) # an empty box forgets the key for that server
	var last := ConfigFile.new()
	last.set_value("start", "name", n)
	last.set_value("start", "account", _account_edit.text.strip_edges())
	last.set_value("start", "server", server)
	last.save(START_PATH)
	_start(mode, n if n != "" else _default_name(mode), server, _account_edit.text.strip_edges(), _password_edit.text)


func _start(mode: String, player_name: String, server: String, account := "", password := "") -> void:
	for child in get_children():
		child.queue_free()
	if mode == "builder" and not OS.has_feature("mobile"):
		# Phone-shaped window (held sideways) when testing the Builder on a PC.
		DisplayServer.window_set_size(Vector2i(1040, 480))
	get_window().title = "Teal Galaxy: %s (%s)" % [mode.capitalize(), player_name]
	Net.connect_to(server, mode, player_name, account, password)
	_mode = BuilderMode.new() if mode == "builder" else ExplorerMode.new()
	add_child(_mode)
