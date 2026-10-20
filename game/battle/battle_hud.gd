extends Control
## The sector battle's HUD: the top bar (sector, mass and income, units, time left, Leave battle),
## the pilots by side, the battle feed, the minimap, the command panel for what's selected (orders,
## engineers' build buttons, a factory's production) and the call-in panel (every unit by drop
## pod, its cost and how many). While driving a unit: its health and reload. At the end: the banner.
## Buttons call the battle view (`view`); _process reads it to keep the numbers current.

const Units := preload("res://battle/battle_units.gd")

const TEAL := Color(0.35, 0.95, 0.88)
const MASS := Color(0.45, 1.0, 0.45)
const PANEL_BG := Color(0.02, 0.05, 0.08, 0.86)
const DROPPABLE := ["engineer", "scout", "striker", "tank", "artillery", "aa", "gunship"]
const BUILDABLE := ["extractor", "turret", "factory"]
const PRODUCIBLE := ["engineer", "scout", "striker", "tank", "artillery", "aa"]

var view: Node # battle_view.gd
var drop_count := 1

var _title: Label
var _mass: Label
var _mass_bar: ProgressBar
var _units: Label
var _clock: Label
var _pilots: Label
var _feed: VBoxContainer
var _notice: Label
var _notice_t := 0.0
var _selection: Label
var _orders: HBoxContainer
var _build: HBoxContainer
var _produce: HBoxContainer
var _command: PanelContainer
var _drop_buttons := {} # type -> Button
var _count_buttons: Array[Button] = []
var _drive: PanelContainer
var _drive_name: Label
var _drive_hp: ProgressBar
var _drive_reload: ProgressBar
var _banner: PanelContainer
var _banner_title: Label
var _banner_text: Label
var _banner_back: Label
var _help: Label
var _minimap: Control
var _panels: Array[Control] = [] # hidden while driving
var _take: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = _theme()

	# Top bar.
	var top := _panel(Control.PRESET_CENTER_TOP)
	top.offset_top = 8
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	top.add_child(row)
	_title = _label(row, "", 17, TEAL)
	var mass_box := VBoxContainer.new()
	mass_box.add_theme_constant_override("separation", 0)
	row.add_child(mass_box)
	_mass = _label(mass_box, "", 17, MASS)
	_mass_bar = ProgressBar.new()
	_mass_bar.custom_minimum_size = Vector2(150, 5)
	_mass_bar.show_percentage = false
	_mass_bar.max_value = 5000
	var fill := StyleBoxFlat.new()
	fill.bg_color = MASS
	_mass_bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.15, 0.12)
	_mass_bar.add_theme_stylebox_override("background", bg)
	mass_box.add_child(_mass_bar)
	_units = _label(row, "", 17, Color(0.85, 0.9, 0.95))
	_clock = _label(row, "", 17, Color(0.85, 0.9, 0.95))
	var leave := Button.new()
	leave.text = "Leave battle"
	leave.pressed.connect(func(): view.leave())
	row.add_child(leave)
	_panels.append(top)

	# Pilots by side (top left) and the feed (top right).
	var pilots := _panel(Control.PRESET_TOP_LEFT)
	pilots.offset_left = 10
	pilots.offset_top = 10
	_pilots = _label(pilots, "", 14, Color(0.85, 0.9, 0.95))
	_pilots.custom_minimum_size = Vector2(190, 0)
	_panels.append(pilots)
	_feed = VBoxContainer.new()
	_feed.add_theme_constant_override("separation", 2)
	_feed.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_feed.offset_left = -420
	_feed.offset_right = -12
	_feed.offset_top = 64
	_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_feed)

	# The minimap (bottom left).
	var mini := _panel(Control.PRESET_BOTTOM_LEFT)
	mini.offset_left = 10
	mini.offset_bottom = -10
	_minimap = Minimap.new()
	_minimap.view = view
	_minimap.custom_minimum_size = Vector2(230, 230)
	mini.add_child(_minimap)
	mini.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panels.append(mini)

	# The command panel (bottom middle): what's selected, its orders and buttons.
	_command = _panel(Control.PRESET_CENTER_BOTTOM)
	_command.offset_bottom = -10
	_command.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var cmd := VBoxContainer.new()
	cmd.add_theme_constant_override("separation", 6)
	_command.add_child(cmd)
	_selection = _label(cmd, "", 14, Color(0.85, 0.9, 0.95))
	_selection.custom_minimum_size = Vector2(520, 0)
	_selection.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_orders = HBoxContainer.new()
	cmd.add_child(_orders)
	_button(_orders, "Attack-move (A)", func(): view.arm("amove"))
	_button(_orders, "Stop (S)", func(): view.order_stop())
	_take = _button(_orders, "Take control (P)", func(): view.take_control())
	_build = HBoxContainer.new()
	cmd.add_child(_build)
	_produce = HBoxContainer.new()
	cmd.add_child(_produce)
	_panels.append(_command)

	# The call-in panel (bottom right).
	var drop := _panel(Control.PRESET_BOTTOM_RIGHT)
	drop.offset_right = -10
	drop.offset_bottom = -10
	drop.grow_vertical = Control.GROW_DIRECTION_BEGIN
	drop.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 6)
	drop.add_child(dv)
	var dh := HBoxContainer.new()
	dv.add_child(dh)
	_label(dh, "Call in by drop pod", 15, TEAL).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for n in [1, 5, 10]:
		var b := _button(dh, "x%d" % n, _set_count.bind(n))
		b.toggle_mode = true
		b.button_pressed = n == 1
		_count_buttons.append(b)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	dv.add_child(grid)
	for t in DROPPABLE:
		var b := _button(grid, "", func(): view.call_in(t, drop_count))
		b.custom_minimum_size = Vector2(150, 30)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_drop_buttons[t] = b
	_panels.append(drop)

	# Driving a unit.
	_drive = _panel(Control.PRESET_BOTTOM_LEFT)
	_drive.offset_left = 16
	_drive.offset_bottom = -16
	_drive.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var drv := VBoxContainer.new()
	_drive.add_child(drv)
	_drive_name = _label(drv, "", 18, TEAL)
	_drive_hp = _bar(drv, Color(0.35, 0.95, 0.4))
	_drive_reload = _bar(drv, Color(1.0, 0.75, 0.3))
	_label(drv, "WASD drive  ·  mouse aim  ·  left mouse fire  ·  P or Esc: back to command", 13, Color(0.75, 0.8, 0.85))
	_drive.visible = false

	_notice = Label.new()
	_notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_notice.offset_top = 150
	_notice.offset_left = -400
	_notice.offset_right = 400
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.add_theme_font_size_override("font_size", 18)
	_notice.add_theme_constant_override("outline_size", 6)
	_notice.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_notice)

	_help = Label.new()
	_help.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_help.offset_top = 56
	_help.offset_left = -500
	_help.offset_right = 500
	_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_help.add_theme_font_size_override("font_size", 12)
	_help.add_theme_color_override("font_color", Color(0.7, 0.78, 0.82, 0.8))
	_help.add_theme_constant_override("outline_size", 4)
	_help.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help.text = "Drag or click to select · right click: move / attack · A: attack-move · S: stop · Shift: queue · Ctrl+1-9: group · Space: your units · wheel: zoom · Q/E or middle drag: turn"
	add_child(_help)
	_panels.append(_help)

	_banner = PanelContainer.new()
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.0, 0.03, 0.05, 0.9)
	bs.border_color = TEAL
	bs.set_border_width_all(0)
	bs.border_width_top = 3
	bs.border_width_bottom = 3
	bs.content_margin_left = 80
	bs.content_margin_right = 80
	bs.content_margin_top = 26
	bs.content_margin_bottom = 26
	_banner.add_theme_stylebox_override("panel", bs)
	var bv := VBoxContainer.new()
	bv.alignment = BoxContainer.ALIGNMENT_CENTER
	_banner.add_child(bv)
	_banner_title = _label(bv, "", 64, TEAL)
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_text = _label(bv, "", 20, Color(0.9, 0.93, 0.95))
	_banner_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_back = _label(bv, "", 14, Color(0.6, 0.7, 0.75))
	_banner_back.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.visible = false
	add_child(_banner)


func _set_count(n: int) -> void:
	drop_count = n
	for b in _count_buttons:
		b.button_pressed = b.text == "x%d" % n


func _process(delta: float) -> void:
	if view == null:
		return
	var info: Dictionary = view.info
	_title.text = "%s  ·  %s" % [str(info.get("planetName", "")), str(info.get("sectorName", ""))]
	_mass.text = "Mass %d  (+%.1f/s)" % [int(view.mass), view.income]
	_mass_bar.value = view.mass
	_units.text = "Units %d / %d" % [view.my_unit_count(), 120]
	var left := maxf(0.0, (float(view.ends_at) - Net.now_ms()) / 1000.0)
	_clock.text = "%02d:%02d left" % [int(left) / 60, int(left) % 60]
	_pilots.text = _pilots_text()
	_notice_t -= delta
	_notice.modulate.a = clampf(_notice_t, 0.0, 1.0)
	for i in _feed.get_child_count():
		var l: Label = _feed.get_child(i)
		var age: float = l.get_meta("t") + delta
		l.set_meta("t", age)
		l.modulate.a = clampf(12.0 - age, 0.0, 1.0)
	while _feed.get_child_count() > 8:
		_feed.get_child(0).free()
	var cat: Dictionary = view.catalog
	for t in _drop_buttons:
		var cost := int(cat.get(t, {}).get("cost", 0)) * drop_count
		var b: Button = _drop_buttons[t]
		b.text = "%s  %d" % [str(cat.get(t, {}).get("name", t)), cost]
		b.disabled = view.mass + 0.01 < cost or view.ended
		b.tooltip_text = _unit_tip(t)
	var driving: bool = view.driving()
	for p in _panels:
		p.visible = not driving and not view.ended
	_drive.visible = driving and not view.ended
	if driving:
		var u: Units.Unit = view.units.get(view.drive_id)
		if u:
			_drive_name.text = "Driving: %s" % str(cat.get(u.type, {}).get("name", u.type))
			_drive_hp.value = u.hp / u.max_hp * 100.0
			var reload := float(cat.get(u.type, {}).get("reload", 1.0)) / maxf(view.sim_rate, 0.1)
			_drive_reload.value = clampf((view.clock - u.last_shot) / maxf(reload, 0.01), 0.0, 1.0) * 100.0
	_update_command()
	if _banner.visible:
		_banner_back.text = "Back to your carrier in %d s" % ceili(view.end_left())


func _pilots_text() -> String:
	var info: Dictionary = view.info
	var lines := []
	for side in ["a", "d"]:
		var who := []
		for p in view.pilots:
			if str(p.get("side", "")) == side:
				who.append(str(p.name))
		var faction = info.get("attacker") if side == "a" else info.get("defender")
		var label: String = view.side_name(side)
		if side == "d" and faction == null:
			label = "Militia"
		var tag := " (you)" if side == view.my_side else ""
		lines.append("%s%s" % [label, tag])
		if side == "d":
			who.push_front("AI command")
		lines.append("  " + (", ".join(who) if not who.is_empty() else "none"))
	return "\n".join(lines)


func _unit_tip(t: String) -> String:
	var c: Dictionary = view.catalog.get(t, {})
	var s := "%s: %d hp, %s m/s" % [str(c.get("name", t)), int(c.get("hp", 0)), str(c.get("speed", 0))]
	if float(c.get("damage", 0)) > 0.0:
		s += ", %d damage every %ss, range %d m" % [int(c.damage), str(c.reload), int(c.range)]
	if t == "aa":
		s += " (hits air only)"
	if t == "engineer":
		s += ". Builds extractors, turrets and factories"
	return s


## The command panel follows the selection: counts by type, and build or production buttons for
## engineers and factories.
func _update_command() -> void:
	var counts := {}
	var engineers := false
	var factory := -1
	var mine := 0
	for id in view.selected:
		var u: Units.Unit = view.units.get(id)
		if u == null:
			continue
		counts[u.type] = int(counts.get(u.type, 0)) + 1
		if u.mine:
			mine += 1
			if u.type == "engineer":
				engineers = true
			if u.type == "factory" and u.progress >= 1.0:
				factory = u.id
	if counts.is_empty():
		_selection.text = "Nothing selected. Call units in from the right; they land in your landing zone."
	else:
		var parts := []
		for t in counts:
			parts.append("%d %s" % [counts[t], str(view.catalog.get(t, {}).get("name", t))])
		_selection.text = "Selected: " + ", ".join(parts)
		if view.armed != "":
			_selection.text += "    ·    " + view.armed_text()
	_orders.visible = mine > 0
	_take.disabled = view.selected.size() != 1
	var want_build := engineers
	if _build.visible != want_build or (want_build and _build.get_child_count() == 0):
		_build.visible = want_build
		if want_build and _build.get_child_count() == 0:
			_label(_build, "Build:", 14, Color(0.8, 0.85, 0.9))
			for s in BUILDABLE:
				var c: Dictionary = view.catalog.get(s, {})
				_button(_build, "%s %d" % [str(c.get("name", s)), int(c.get("cost", 0))], func(): view.arm("build:" + s))
	var want_produce := factory >= 0
	_produce.visible = want_produce
	if want_produce and _produce.get_child_count() == 0:
		_label(_produce, "Produce:", 14, Color(0.8, 0.85, 0.9))
		for t in PRODUCIBLE:
			var c: Dictionary = view.catalog.get(t, {})
			_button(_produce, "%s %d" % [str(c.get("name", t)), int(c.get("cost", 0))], func(): view.produce(t, drop_count))


# --- What the view tells the pilot ------------------------------------------------------------

## A line in the battle feed (top right), fading after a while.
func feed(text: String, colour := Color(0.85, 0.9, 0.95)) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.set_meta("t", 0.0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed.add_child(l)


## A message in the middle of the screen for a few seconds (a refusal, a hint).
func notice(text: String, colour := Color(1.0, 0.85, 0.5)) -> void:
	_notice.text = text
	_notice.add_theme_color_override("font_color", colour)
	_notice_t = 4.0


## The big banner at the end: "Sector taken" or "Attack failed".
func banner(title: String, text: String, good: bool) -> void:
	_banner_title.text = title
	_banner_title.add_theme_color_override("font_color", Color(0.45, 1.0, 0.6) if good else Color(1.0, 0.42, 0.35))
	_banner_text.text = text
	_banner.visible = true


func banner_shown() -> bool:
	return _banner.visible


## True when the mouse is over one of the HUD's panels (the view leaves such clicks alone).
func over_panel(p: Vector2) -> bool:
	for c in _panels + [_drive]:
		if c.visible and c is PanelContainer and c.get_global_rect().has_point(p):
			return true
	return false


# --- Building blocks --------------------------------------------------------------------------

func _theme() -> Theme:
	var t := Theme.new()
	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL_BG
	panel.border_color = Color(0.25, 0.7, 0.75, 0.45)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(3)
	panel.content_margin_left = 12
	panel.content_margin_right = 12
	panel.content_margin_top = 8
	panel.content_margin_bottom = 8
	t.set_stylebox("panel", "PanelContainer", panel)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var b := StyleBoxFlat.new()
		b.bg_color = {"normal": Color(0.07, 0.13, 0.17), "hover": Color(0.1, 0.22, 0.27), "pressed": Color(0.12, 0.38, 0.4),
			"disabled": Color(0.05, 0.07, 0.09), "focus": Color(0, 0, 0, 0)}[state]
		b.border_color = Color(0.3, 0.75, 0.8, 0.5 if state != "disabled" else 0.15)
		b.set_border_width_all(1 if state != "focus" else 0)
		b.set_corner_radius_all(2)
		b.content_margin_left = 10
		b.content_margin_right = 10
		b.content_margin_top = 4
		b.content_margin_bottom = 4
		t.set_stylebox(state, "Button", b)
	t.set_color("font_color", "Button", Color(0.85, 0.95, 0.95))
	t.set_color("font_disabled_color", "Button", Color(0.45, 0.5, 0.52))
	t.set_color("font_pressed_color", "Button", Color(1, 1, 1))
	t.set_font_size("font_size", "Button", 14)
	return t


func _panel(preset: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.set_anchors_and_offsets_preset(preset)
	if preset == Control.PRESET_CENTER_TOP or preset == Control.PRESET_CENTER_BOTTOM:
		p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(p)
	return p


func _label(parent: Node, text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(l)
	return l


func _button(parent: Node, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _bar(parent: Node, colour: Color) -> ProgressBar:
	var p := ProgressBar.new()
	p.custom_minimum_size = Vector2(320, 10)
	p.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = colour
	p.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.1, 0.12)
	p.add_theme_stylebox_override("background", bg)
	parent.add_child(p)
	return p


## The minimap: the field, mass points, landing zones, every unit as a dot, the camera's view.
## Click or drag on it to move the camera there.
class Minimap extends Control:
	var view: Node
	var _tex: Texture2D
	var _drag := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true

	func _process(_delta: float) -> void:
		queue_redraw()

	## Map metres to the minimap, turned as the camera starts: the pilot's own landing zone at the
	## bottom (the attacker looks toward +z, the defender toward -z).
	func _to(p: Vector2) -> Vector2:
		var f := p / 1600.0
		if not view.flipped():
			f = Vector2(1.0 - f.x, 1.0 - f.y)
		return f * size

	func _from(s: Vector2) -> Vector2:
		var f := s / size
		if not view.flipped():
			f = Vector2(1.0 - f.x, 1.0 - f.y)
		return f * 1600.0

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			_drag = event.pressed
			if event.pressed:
				view.look_at_ground(_from(event.position))
			accept_event()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			view.order_to(_from(event.position))
			accept_event()
		elif event is InputEventMouseMotion and _drag:
			view.look_at_ground(_from(event.position))
			accept_event()

	func _draw() -> void:
		if view == null or view.terrain == null:
			return
		if _tex == null:
			_tex = view.minimap_texture()
		if _tex:
			# The picture has x across and z down; the attacker sees it turned half round.
			if not view.flipped():
				draw_set_transform(size, 0.0, Vector2(-1, -1))
			draw_texture_rect(_tex, Rect2(Vector2.ZERO, size), false)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for lz in [view.info.get("lz", {}), view.info.get("enemyLz", {})]:
			if lz.is_empty():
				continue
			var c: Color = view.side_colour(view.my_side if lz == view.info.get("lz") else view.enemy_side())
			draw_arc(_to(Vector2(lz.x, lz.z)), float(lz.r) / 1600.0 * size.x, 0, TAU, 32, Color(c.r, c.g, c.b, 0.7), 1.5)
		for p in view.mass_points:
			draw_rect(Rect2(_to(Vector2(p.x, p.z)) - Vector2(2, 2), Vector2(4, 4)), Color(0.45, 1.0, 0.45), false, 1.0)
		for u: Units.Unit in view.units.values():
			var c: Color = view.side_colour(u.side)
			var s := 3.0 if u.kind != "structure" else 5.0
			if view.selected.has(u.id):
				c = Color.WHITE
			draw_rect(Rect2(_to(Vector2(u.pos.x, u.pos.z)) - Vector2(s, s) * 0.5, Vector2(s, s)), c, true)
		var quad: Array = view.view_quad()
		if quad.size() == 4:
			var pts := PackedVector2Array()
			for q in quad:
				pts.append(_to(q))
			pts.append(pts[0])
			draw_polyline(pts, Color(1, 1, 1, 0.8), 1.0)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.3, 0.75, 0.8, 0.5), false, 1.0)
