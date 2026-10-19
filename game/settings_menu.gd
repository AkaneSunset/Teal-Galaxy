extends Control
## Settings: drift default, mouse, HUD colour, the admin key, and rebinding every control for
## keyboard and mouse or for gamepad and HOTAS. Changes save straight away.

signal closed

var controls: Node # controls.gd

var _list: GridContainer
var _waiting_action := ""
var _waiting_pad := false
var _waiting_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.02, 0.05, 0.9)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(640, 0)
	col.add_theme_constant_override("separation", 10)
	center.add_child(col)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 10)
	col.add_child(title_row)
	var pic := TextureRect.new()
	pic.texture = preload("res://ui/hud_icons/settings.png")
	pic.custom_minimum_size = Vector2(32, 32)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.modulate = controls.hud_color()
	title_row.add_child(pic)
	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 26)
	title_row.add_child(title)

	var drift := CheckBox.new()
	drift.text = "Start with drift on (flight assist off)"
	drift.button_pressed = controls.drift_default
	drift.toggled.connect(func(on): controls.drift_default = on; controls.save_settings())
	col.add_child(drift)
	var hold := CheckBox.new()
	hold.text = "Drift only while the drift control is held"
	hold.button_pressed = controls.drift_hold
	hold.toggled.connect(func(on): controls.drift_hold = on; controls.save_settings())
	col.add_child(hold)
	var invert := CheckBox.new()
	invert.text = "Invert mouse up and down"
	invert.button_pressed = controls.invert_mouse
	invert.toggled.connect(func(on): controls.invert_mouse = on; controls.save_settings())
	col.add_child(invert)

	var sens_row := HBoxContainer.new()
	var sens_label := Label.new()
	sens_label.text = "Mouse sensitivity"
	sens_label.custom_minimum_size = Vector2(180, 0)
	sens_row.add_child(sens_label)
	var sens := HSlider.new()
	sens.min_value = 0.25
	sens.max_value = 3.0
	sens.step = 0.05
	sens.value = controls.mouse_sensitivity
	sens.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sens.value_changed.connect(func(v): controls.mouse_sensitivity = v; controls.save_settings())
	sens_row.add_child(sens)
	col.add_child(sens_row)

	var hud_row := HBoxContainer.new()
	var hud_label := Label.new()
	hud_label.text = "HUD colour"
	hud_label.custom_minimum_size = Vector2(180, 0)
	hud_row.add_child(hud_label)
	var hud := OptionButton.new()
	for c in controls.HUD_COLOURS:
		hud.add_item(c[0])
	hud.selected = controls.hud_colour
	hud.item_selected.connect(func(i): controls.hud_colour = i; controls.save_settings())
	hud_row.add_child(hud)
	col.add_child(hud_row)

	# Only the galaxy's admins have a key: it lets this app run the Coma Conglomerate.
	var admin_row := HBoxContainer.new()
	var admin_label := Label.new()
	admin_label.text = "Admin key"
	admin_label.custom_minimum_size = Vector2(180, 0)
	admin_row.add_child(admin_label)
	var admin_key := LineEdit.new()
	admin_key.text = Net.saved_admin_key(Net.server_url())
	admin_key.secret = true
	admin_key.placeholder_text = "Leave empty unless you run this galaxy"
	admin_key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Saved for this server only: it never goes to another one.
	admin_key.text_changed.connect(func(t): Net.save_admin_key(Net.server_url(), t))
	admin_key.text_submitted.connect(func(_t): admin_key.release_focus(); Net.reconnect())
	admin_row.add_child(admin_key)
	col.add_child(admin_row)
	var admin_note := Label.new()
	admin_note.modulate = Color(1, 1, 1, 0.6)
	col.add_child(admin_note)
	var note_admin := func():
		admin_note.text = ("The server knows you as an admin. " if Net.admin else "") + "The key is kept for %s only. Press Enter in the key box to reconnect with it." % Net.server_url()
	note_admin.call()
	visibility_changed.connect(note_admin)

	var keys_title := Label.new()
	keys_title.text = "Controls (click a binding, then press the new key, button or axis)"
	col.add_child(keys_title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 270) # short enough that the whole menu fits a 720-high window
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED # the column widens to fit the bindings
	col.add_child(scroll)
	_list = GridContainer.new()
	_list.columns = 3
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	_fill_list()

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	col.add_child(buttons)
	var reset := Button.new()
	reset.text = "Reset controls to defaults"
	reset.pressed.connect(func(): controls.reset_to_defaults(); _fill_list())
	buttons.add_child(reset)
	var done := Button.new()
	done.text = "Back to flying (Esc)"
	done.pressed.connect(func(): closed.emit())
	buttons.add_child(done)


func _fill_list() -> void:
	for child in _list.get_children():
		child.queue_free()
	for header in ["Control", "Keyboard / mouse", "Gamepad / HOTAS"]:
		var h := Label.new()
		h.text = header
		h.modulate = Color(1, 1, 1, 0.6)
		_list.add_child(h)
	for a in controls.ACTIONS:
		var name_label := Label.new()
		name_label.text = a[1]
		name_label.custom_minimum_size = Vector2(240, 0)
		_list.add_child(name_label)
		for pad in [false, true]:
			var b := Button.new()
			b.text = controls.binding_text(a[0], pad)
			b.custom_minimum_size = Vector2(170, 0)
			b.pressed.connect(_start_rebind.bind(a[0], pad, b))
			_list.add_child(b)


func _start_rebind(action: String, pad: bool, button: Button) -> void:
	_waiting_action = action
	_waiting_pad = pad
	_waiting_button = button
	button.text = "Press a button or move an axis..." if pad else "Press a key..."


func is_rebinding() -> bool:
	return _waiting_action != ""


func _input(event: InputEvent) -> void:
	if not visible or _waiting_action == "":
		return
	var usable := false
	if _waiting_pad:
		usable = event is InputEventJoypadButton and event.pressed \
			or event is InputEventJoypadMotion and absf(event.axis_value) > 0.6
	else:
		usable = event is InputEventKey and event.pressed and not event.echo \
			or event is InputEventMouseButton and event.pressed and event.button_index > MOUSE_BUTTON_RIGHT
	if not usable:
		return
	get_viewport().set_input_as_handled()
	controls.rebind(_waiting_action, event)
	_waiting_button.text = controls.binding_text(_waiting_action, _waiting_pad)
	_waiting_action = ""
