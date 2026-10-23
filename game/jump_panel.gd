extends Control
## The fleet carrier's galaxy map (the GALAXY MAP terminal on its Command Deck): every system of the
## war map with its lanes, and where the carrier is. Pick a system to see its planets (who holds
## each, its campaign), then jump the carrier there, to the system or straight into a planet's orbit,
## as in Helldivers 2. Only a fleet carrier can jump; the server checks (carrier_jump).

const WarInfo := preload("res://war_info.gd")

signal closed
signal jump_requested(system_id: String, planet_id: String)

var colour := Color(0.36, 0.78, 0.78)
var here_system := "teal-prime" # where the carrier is
var here_planet := "" # the planet whose orbit it's in, if any
var selected := ""

var _map: Control
var _title: Label
var _info: Label
var _list: VBoxContainer
var _status: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.02, 0.05, 0.94)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 32
	row.offset_top = 24
	row.offset_right = -32
	row.offset_bottom = -24
	row.add_theme_constant_override("separation", 24)
	add_child(row)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var head := Label.new()
	head.text = "GALAXY MAP · FTL JUMP"
	head.add_theme_font_size_override("font_size", 30)
	left.add_child(head)
	var sub := Label.new()
	sub.text = "Pick a system, then where in it to jump the carrier. Only a fleet carrier can make the jump."
	sub.add_theme_color_override("font_color", Color(0.7, 0.78, 0.85))
	left.add_child(sub)
	_map = Control.new()
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map.custom_minimum_size = Vector2(520, 420)
	_map.draw.connect(_draw_map)
	_map.gui_input.connect(_on_map_input)
	left.add_child(_map)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(520, 0)
	right.add_theme_constant_override("separation", 10)
	row.add_child(right)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 26)
	right.add_child(_title)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	right.add_child(_info)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	right.add_child(_status)
	var close := Button.new()
	close.text = "Close (Esc)"
	close.pressed.connect(func(): closed.emit())
	right.add_child(close)


## Opens on the system the carrier is in.
func open(system_id: String, planet_id: String) -> void:
	here_system = system_id
	here_planet = planet_id
	_status.text = ""
	select(system_id)


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("menu")):
		closed.emit()
		get_viewport().set_input_as_handled()


func say(text: String) -> void:
	_status.text = text


## Shows a system's planets and the jumps there.
func select(system_id: String) -> void:
	selected = system_id
	var s := WarInfo.system(system_id)
	_title.text = str(s.get("name", system_id)).to_upper() + ("   ·   THE CARRIER IS HERE" if system_id == here_system else "")
	var cap = s.get("capitalOf")
	var planets := WarInfo.planets_in(system_id)
	_info.text = ("Capital system of %s." % WarInfo.faction_name(cap) if cap != null else "Contested system.") + "  %d planet%s." % [planets.size(), "" if planets.size() == 1 else "s"]
	for c in _list.get_children():
		c.free()
	if system_id != here_system:
		var b := Button.new()
		b.text = "Jump to the %s system" % str(s.get("name", system_id))
		b.custom_minimum_size = Vector2(0, 40)
		b.pressed.connect(func(): jump_requested.emit(system_id, ""))
		_list.add_child(b)
	for wp in planets:
		var box := VBoxContainer.new()
		_list.add_child(box)
		var l := Label.new()
		var owner = wp.get("owner")
		var camp: Dictionary = WarInfo.war().get("campaigns", {}).get(str(wp.id), {})
		l.text = "%s   ·   %s%s" % [str(wp.name), "held by %s" % WarInfo.faction_name(owner) if owner != null else "unclaimed", ("   ·   campaign on" if not camp.is_empty() else "") + ("   ·   capital world" if bool(wp.get("capital", false)) else "")]
		l.add_theme_color_override("font_color", WarInfo.faction_color(owner) if owner != null else Color(0.85, 0.85, 0.85))
		box.add_child(l)
		var b := Button.new()
		var here := system_id == here_system and str(wp.id) == here_planet
		b.text = "In orbit of %s" % str(wp.name) if here else "Jump into orbit of %s" % str(wp.name)
		b.disabled = here
		b.custom_minimum_size = Vector2(0, 36)
		b.pressed.connect(func(): jump_requested.emit(system_id, str(wp.id)))
		box.add_child(b)
	_map.queue_redraw()


func _layout() -> Dictionary:
	# The war map's grid: x from -1 to 1, y from -2 to 2.
	var out := {}
	var r := _map.size
	var cell := minf(r.x / 3.4, r.y / 5.2)
	var mid := r / 2.0
	for s in WarInfo.war().get("systems", []):
		var p: Array = s.get("pos", [0, 0])
		out[str(s.id)] = mid + Vector2(float(p[0]), float(p[1])) * cell
	return out


func _draw_map() -> void:
	var at := _layout()
	var font := ThemeDB.fallback_font
	for s in WarInfo.war().get("systems", []):
		for l in s.get("lanes", []):
			if at.has(str(l)) and str(s.id) < str(l):
				_map.draw_line(at[str(s.id)], at[str(l)], Color(0.4, 0.55, 0.7, 0.6), 2.0)
	for s in WarInfo.war().get("systems", []):
		var id := str(s.id)
		var p: Vector2 = at[id]
		var cap = s.get("capitalOf")
		var col := WarInfo.faction_color(cap) if cap != null else Color(0.85, 0.85, 0.75)
		_map.draw_circle(p, 18.0, Color(col, 0.85))
		if id == selected:
			_map.draw_arc(p, 26.0, 0, TAU, 48, Color(1.0, 0.85, 0.4), 3.0)
		if id == here_system:
			_map.draw_arc(p, 33.0, 0, TAU, 48, colour, 2.0)
			_map.draw_string(font, p + Vector2(-70, -40), "YOU ARE HERE", HORIZONTAL_ALIGNMENT_CENTER, 140, 12, colour)
		_map.draw_string(font, p + Vector2(-70, 40), str(s.name), HORIZONTAL_ALIGNMENT_CENTER, 140, 16, Color.WHITE)


func _on_map_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var at := _layout()
		for id in at:
			if (at[id] as Vector2).distance_to(event.position) < 28.0:
				select(id)
				return
