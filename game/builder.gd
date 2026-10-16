extends Control
## Builder mode (phone): a base-builder view of the home planet, like Clash of Clans.
## The base is a 3D scene seen from above at an angle: drag to pan, pinch or scroll to zoom,
## tap a pad to select it. Buildings sit on fixed pads around the command centre.
## The HUD sits around the edges: system and resources at the top, Jobs / Raids / Chat drawers
## bottom left, the Build shop bottom right, and the selected building's actions bottom centre.
## Facilities fill vaults with goods to ship home; Explorers can raid them, and the Builder
## watches the raid live and can sound the alarm.

const BaseModels := preload("res://base_models.gd")
const SiteView := preload("res://site_view.gd")
const ICONS := "res://ui/icons/"

const BUILDING_INFO := {
	"mine": {"name": "Mine", "cost": {"metal": 10}, "about": "Digs 12 metal a minute."},
	"extractor": {"name": "Ice Extractor", "cost": {"metal": 15}, "about": "Melts 2 ice a minute out of the crust. Pilots' ice jobs are faster."},
	"habitat": {"name": "Habitat", "cost": {"metal": 20}, "about": "Houses 50 people, who pay 12 credits a minute in rent."},
	"spaceport": {"name": "Spaceport", "cost": {"metal": 30}, "about": "Pilots land here. Post jobs for them to fly."},
	"hydroponics": {"name": "Hydroponics", "cost": {"metal": 20, "ice": 10}, "about": "Grows food and sells it: 24 credits a minute."},
	"refinery": {"name": "Mining Refinery", "cost": {"metal": 40}, "about": "Makes alloy, isotopes and exotics. A freighter brings them home every 5 minutes; pilots can raid the vault before then."},
	"lab": {"name": "Research Outpost", "cost": {"metal": 30, "ice": 10}, "about": "Makes plans and drives. A freighter brings them home every 5 minutes; pilots can raid the vault before then."},
	"spire": {"name": "Data Spire", "cost": {"metal": 50, "credits": 150}, "about": "Makes intel, sold for credits when the freighter brings it home every 5 minutes. Pilots can raid it."},
	"foundry": {"name": "Ship Foundry", "cost": {"metal": 60, "ice": 10}, "needs": "spaceport", "limit": 1,
		"about": "Builds warships for your navy. Open the Shipyard to queue them."},
}
const CARD_ICON := {"foundry": "ship_emblem", "extractor": "ice"} # shop icons for buildings without their own
const JOB := {"resource": "ice", "amount": 10, "reward": 100}

const PAD_RING := 34.0 # metres from the command centre to each pad
const PAD_RADIUS := 9.5
const YAW := deg_to_rad(45.0)
const PITCH := deg_to_rad(52.0)
const ZOOM_MIN := 45.0
const ZOOM_MAX := 170.0
const PAN_LIMIT := 60.0
const SITE_PAN_LIMIT := 26.0
const TAP_SLOP := 14.0 # pixels a finger can move and still count as a tap

const C_PANEL := Color(0.06, 0.1, 0.2, 0.86)
const C_TEAL := Color(0.36, 0.78, 0.78)
const C_AMBER := Color(1.0, 0.62, 0.15)
const C_RED := Color(0.9, 0.25, 0.22)

# --- 3D base ---
var _cam: Camera3D
var _home: Node3D # the home base's pads and buildings
var _site: Node3D # the satellite site being shown (site_view.gd)
var _view := "" # "" for the home base, or the id of the satellite site on screen
var _sel_piece := -1 # id of the defence or obstacle selected on a site, or -1
var _sel_is_obstacle := false
var _sites_btn: Button
var _jobs_btn: Button
var _home_btn: Button
var _sites_list: VBoxContainer
var _fleet_status: Label
var _fleet_targets: VBoxContainer
var _fleet_log: Label
var _fleet_key := ""
var _sites_key := ""
var _site_count := -1 # this Builder's sites at the last refresh, to follow a newly founded one
var _focus := Vector3(0, 0, 4)
var _zoom := 120.0
var _pads := [] # per slot: {"root", "pos", "key", "model", "label", "ring", "plus", "light"}
var _drag_from := Vector2.ZERO
var _drag_total := 0.0
var _dragging := false
var _touches := {} # finger index -> position, for pinch
var _pinch_dist := 0.0
var _clock := 0.0

# --- HUD ---
var _title: Label
var _subtitle: Label
var _stock := {} # resource -> Label
var _goods: Label
var _banner: Button
var _toasts: VBoxContainer
var _top_mid: VBoxContainer # banner and toasts; moves right while the drawer is open
var _raids_btn: Button
var _select_box: VBoxContainer
var _select_name: Label
var _actions: HBoxContainer
var _action_ids := []
var _place_bar: PanelContainer
var _place_label: Label
var _drawer: PanelContainer
var _drawer_title: Label
var _pages := {} # page name -> Control
var _page := ""
var _jobs: Label
var _post_job: Button
var _raids: Label
var _info: Label
var _yard_fleet: Label
var _yard_queue: Label
var _yard_cancel: Button
var _yard_ships: VBoxContainer
var _yard_buttons := {} # ship id -> Button
var _chat_log: Label
var _chat_lines := []
var _shop: PanelContainer
var _shop_hint: Label
var _shop_cards: HBoxContainer

# --- What the player is doing ---
var _selected := -1 # pad index, or -1
var _placing := "" # building type picked in the shop, waiting for a pad
var _last_feed_at := -1.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scale_for_screen()
	theme = _make_theme()
	_build_world()
	_build_hud()

	Net.state_changed.connect(_refresh)
	Net.chat_received.connect(_on_chat)
	Net.server_error.connect(func(reason): toast("Server: " + reason, C_RED))
	Net.connection_changed.connect(func(online): toast("Connected" if online else "Connection lost, retrying...", C_TEAL if online else C_RED))
	_title.text = "Connecting..."

	# Count down cooldowns and raid clocks between server updates.
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(func(): if not Net.state.is_empty(): _refresh(Net.state))
	add_child(timer)


## Phones have small, dense screens: scale the HUD so buttons stay finger-sized.
func _scale_for_screen() -> void:
	var win := get_window()
	var short_side := float(mini(win.size.x, win.size.y))
	win.content_scale_factor = clampf(short_side / 540.0, 1.0, 3.0)


# --- The 3D base ------------------------------------------------------------------------

func _build_world() -> void:
	var world := Node3D.new()
	world.name = "Base"
	add_child(world)

	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.02, 0.03, 0.09)
	sky_mat.sky_horizon_color = Color(0.12, 0.32, 0.38)
	sky_mat.ground_horizon_color = Color(0.12, 0.32, 0.38)
	sky_mat.ground_bottom_color = Color(0.05, 0.06, 0.1)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.65, 0.85)
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 300.0
	world.add_child(sun)

	_cam = Camera3D.new()
	_cam.fov = 38.0
	_cam.far = 2000.0
	world.add_child(_cam)
	_cam.current = true
	_place_camera()

	# Ground: dusty regolith, with the base plate and paths on top.
	var ground := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 700.0
	disc.bottom_radius = 700.0
	disc.height = 1.0
	disc.radial_segments = 48
	ground.mesh = disc
	ground.position.y = -0.5
	ground.material_override = _flat(Color(0.25, 0.23, 0.32))
	world.add_child(ground)
	var plate := MeshInstance3D.new()
	var plate_mesh := CylinderMesh.new()
	plate_mesh.top_radius = PAD_RING + 16.0
	plate_mesh.bottom_radius = PAD_RING + 17.5
	plate_mesh.height = 0.4
	plate_mesh.radial_segments = 6
	plate.mesh = plate_mesh
	plate.position.y = 0.2
	plate.rotation_degrees.y = 30
	plate.material_override = _flat(Color(0.2, 0.25, 0.35))
	_home = Node3D.new()
	world.add_child(_home)
	_home.add_child(plate)

	var hq := BaseModels.command_center()
	hq.rotation_degrees.y = 45
	_home.add_child(hq)

	var slots := 6
	for i in slots:
		var ang := deg_to_rad(-90.0 + 360.0 * i / slots)
		var pos := Vector3(cos(ang), 0, sin(ang)) * PAD_RING
		var path := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(3.0, 0.2, PAD_RING - 16.0)
		path.mesh = box
		path.material_override = _flat(Color(0.15, 0.19, 0.28))
		_home.add_child(path)
		path.position = pos * 0.5 + Vector3(0, 0.45, 0)
		path.look_at(Vector3(0, 0.45, 0), Vector3.UP)
		_pads.append(_make_pad(_home, pos))

	_site = SiteView.new()
	_site.position.y = SiteView.DECK_TOP # the site's deck stands clear of the ground, so the two never flicker
	_site.visible = false
	world.add_child(_site)

	# Scenery past the plate: boulders, ice crystals and beacons.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 26:
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(PAD_RING + 22.0, PAD_RING + 90.0)
		var p := Vector3(cos(ang), 0, sin(ang)) * dist
		var prop: Node3D
		if i % 4 == 0:
			prop = BaseModels.Models.ice_asteroid(rng.randf_range(2.0, 3.5), i)
			prop.position = p + Vector3(0, 0.5, 0)
		else:
			prop = BaseModels.boulder(rng.randf_range(2.0, 6.0), i)
			prop.position = p
		prop.rotation.y = rng.randf() * TAU
		world.add_child(prop)
	for a in 4:
		var beacon := BaseModels.Models.nav_beacon()
		var ang := deg_to_rad(a * 90.0)
		beacon.position = Vector3(cos(ang), 0, sin(ang)) * (PAD_RING + 18.0)
		beacon.scale = Vector3.ONE * 0.7
		world.add_child(beacon)


func _make_pad(world: Node3D, pos: Vector3) -> Dictionary:
	var root := Node3D.new()
	root.position = pos
	world.add_child(root)
	root.add_child(BaseModels.pad())

	# Selection / placement ring, shown when needed.
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = PAD_RADIUS + 0.2
	torus.outer_radius = PAD_RADIUS + 1.2
	torus.rings = 32
	ring.mesh = torus
	ring.position.y = 1.0
	ring.material_override = _glow(C_AMBER)
	ring.visible = false
	root.add_child(ring)

	var plus := Label3D.new()
	plus.text = "+"
	plus.font_size = 96
	plus.pixel_size = 0.06
	plus.outline_size = 12
	plus.modulate = Color(0.6, 1.0, 1.0, 0.75)
	plus.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	plus.position.y = 4.0
	root.add_child(plus)

	var label := Label3D.new()
	label.font_size = 40
	label.pixel_size = 0.07
	label.outline_size = 10
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position.y = 16.0
	label.visible = false
	root.add_child(label)

	var light := OmniLight3D.new()
	light.light_color = C_RED
	light.omni_range = 18.0
	light.position.y = 10.0
	light.visible = false
	root.add_child(light)
	return {"root": root, "pos": pos, "key": "", "model": null, "label": label, "ring": ring, "plus": plus, "light": light}


func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


func _glow(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 1.2
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _place_camera() -> void:
	var dir := Vector3(sin(YAW) * cos(PITCH), sin(PITCH), cos(YAW) * cos(PITCH))
	_cam.position = _focus + dir * _zoom
	_cam.look_at(_focus, Vector3.UP)


## Where a point on the screen lands on the ground (or on a level `height` above it), or null when it misses.
func _ground_at(screen: Vector2, height := 0.0) -> Variant:
	var from := _cam.project_ray_origin(screen)
	var dir := _cam.project_ray_normal(screen)
	if absf(dir.y) < 0.0001:
		return null
	var t := (height - from.y) / dir.y
	return from + dir * t if t > 0.0 else null


func _pan(from: Vector2, to: Vector2) -> void:
	var a = _ground_at(from)
	var b = _ground_at(to)
	if a == null or b == null:
		return
	_focus += a - b
	var flat := Vector2(_focus.x, _focus.z).limit_length(PAN_LIMIT if _view == "" else SITE_PAN_LIMIT)
	_focus = Vector3(flat.x, 0, flat.y)
	_place_camera()


func _zoom_by(factor: float) -> void:
	_zoom = clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	_place_camera()


## Moves the camera to look at a pad.
func focus_pad(i: int) -> void:
	_focus = _pads[i].pos
	_place_camera()


func _unhandled_input(event: InputEvent) -> void:
	# Pinch with two fingers. Single-finger drags arrive as mouse events (phones emulate them).
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		_pinch_dist = _touch_spread()
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() >= 2:
			var d := _touch_spread()
			if _pinch_dist > 0.0 and d > 0.0:
				_zoom_by(_pinch_dist / d)
			_pinch_dist = d
			_drag_total = INF # a pinch is never a tap
	elif event is InputEventMagnifyGesture:
		_zoom_by(1.0 / event.factor)
	elif event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_zoom_by(0.9)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_zoom_by(1.1)
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_dragging = true
					_drag_from = event.position
					_drag_total = 0.0
				elif _dragging:
					_dragging = false
					if _drag_total < TAP_SLOP:
						_tap(event.position)
	elif event is InputEventMouseMotion and _dragging:
		if _touches.size() < 2:
			_pan(_drag_from, event.position)
		_drag_total += event.relative.length()
		_drag_from = event.position


func _touch_spread() -> float:
	if _touches.size() < 2:
		return 0.0
	var pts := _touches.values()
	return (pts[0] as Vector2).distance_to(pts[1])


func _tap(screen: Vector2) -> void:
	var hit = _ground_at(screen, _site.position.y if _view != "" else 0.0)
	if _view != "":
		_tap_site(hit)
		return
	var pad := -1
	if hit != null:
		for i in _pads.size():
			if Vector2(hit.x - _pads[i].pos.x, hit.z - _pads[i].pos.z).length() < PAD_RADIUS + 3.0:
				pad = i
	if _placing != "":
		if pad >= 0 and _building_at(pad).is_empty():
			_build(pad, _placing)
			_set_placing("")
		return
	select_pad(pad if pad != _selected else -1)


## A tap on a satellite site: place the defence being placed, or select what's on the tile.
func _tap_site(hit) -> void:
	var tile: Vector2i = _site.tile_at(hit) if hit != null else Vector2i(-1, -1)
	if _placing != "":
		if tile.x >= 0:
			Net.send({"type": "place_piece", "planet": _view, "piece": _placing, "x": tile.x, "y": tile.y})
		return
	var what: Dictionary = _site.what_at(tile) if tile.x >= 0 else {}
	_sel_piece = -1
	_selected = -1
	if what.get("kind", "") == "core":
		_selected = 0
	elif what.get("kind", "") == "piece":
		_sel_piece = int(what.piece.id)
		_sel_is_obstacle = false
	elif what.get("kind", "") == "obstacle":
		_sel_piece = int(what.obstacle.id)
		_sel_is_obstacle = true
	select_pad(_selected)


## Switches between the home base ("") and one of this Builder's satellite sites.
func show_view(id: String) -> void:
	_view = id
	_home.visible = id == ""
	_site.visible = id != ""
	_selected = -1
	_sel_piece = -1
	_placing = ""
	_place_bar.visible = false
	_shop.visible = false
	_focus = Vector3(0, 0, 4) if id == "" else Vector3.ZERO
	_zoom = 120.0 if id == "" else 95.0
	_place_camera()
	_home_btn.visible = id != ""
	_jobs_btn.visible = id == "" # jobs are posted from the home Spaceport
	if _page == "info":
		_show_page("")
	if not Net.state.is_empty():
		_refresh(Net.state)


func _process(delta: float) -> void:
	_clock += delta
	var pulse := 0.5 + 0.5 * sin(_clock * 6.0)
	for p in _pads:
		if p.light.visible:
			p.light.light_energy = 1.0 + 4.0 * pulse
		if p.ring.visible:
			p.ring.scale = Vector3.ONE * (1.0 + 0.03 * pulse)
		if p.plus.visible:
			p.plus.position.y = 4.0 + 0.6 * sin(_clock * 2.0 + p.pos.x)


# --- HUD layout --------------------------------------------------------------------------

func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 17
	var panel := _box(C_PANEL, C_TEAL.darkened(0.3), 14)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("normal", "Button", _box(Color(0.12, 0.2, 0.34, 0.95), C_TEAL.darkened(0.2), 12))
	t.set_stylebox("hover", "Button", _box(Color(0.16, 0.28, 0.44, 0.95), C_TEAL, 12))
	t.set_stylebox("pressed", "Button", _box(Color(0.08, 0.14, 0.24, 0.95), C_TEAL, 12))
	t.set_stylebox("disabled", "Button", _box(Color(0.1, 0.13, 0.2, 0.8), Color(0.3, 0.35, 0.45), 12))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_disabled_color", "Button", Color(0.6, 0.65, 0.72))
	t.set_constant("icon_max_width", "Button", 30)
	t.set_constant("h_separation", "Button", 8)
	t.set_stylebox("normal", "LineEdit", _box(Color(0.03, 0.06, 0.12, 0.95), C_TEAL.darkened(0.4), 10))
	t.set_constant("outline_size", "Label", 0)
	return t


func _box(fill: Color, border: Color, radius: int, pad := 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad + 4
	s.content_margin_right = pad + 4
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	return s


func _build_hud() -> void:
	var hud := MarginContainer.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		hud.add_theme_constant_override("margin_" + side, 14)
	add_child(hud)
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(layer)

	# Top left: where you are.
	var where := PanelContainer.new()
	where.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(where)
	var where_col := VBoxContainer.new()
	where_col.add_theme_constant_override("separation", 0)
	where.add_child(where_col)
	_title = _label(where_col, 22)
	_subtitle = _label(where_col, 14)
	_subtitle.modulate = Color(0.7, 0.9, 0.95)
	_subtitle.text = "Planet Aster"

	# Top right: resources.
	var res_col := VBoxContainer.new()
	_pin(res_col, Control.PRESET_TOP_RIGHT)
	res_col.alignment = BoxContainer.ALIGNMENT_END
	res_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(res_col)
	var res_row := HBoxContainer.new()
	res_row.alignment = BoxContainer.ALIGNMENT_END
	res_row.add_theme_constant_override("separation", 8)
	res_col.add_child(res_row)
	for r in [["credits", "credits"], ["metal", "metal"], ["ice", "ice"], ["population", "group"], ["navy", "ship_emblem"]]:
		_stock[r[0]] = _pill(res_row, r[1])
	var navy_pill: Control = _stock.navy.get_parent().get_parent()
	navy_pill.mouse_filter = Control.MOUSE_FILTER_STOP
	navy_pill.tooltip_text = "Your navy: tap for the fleet"
	navy_pill.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT: _toggle_page("fleet"))
	_goods = _label(res_col, 14)
	_goods.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_goods.modulate = Color(0.85, 0.95, 1.0)

	# Top centre: raid banner, then toasts.
	var top_mid := VBoxContainer.new()
	_top_mid = top_mid
	_pin(top_mid, Control.PRESET_CENTER_TOP)
	top_mid.offset_top = 64
	top_mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_mid.add_theme_constant_override("separation", 6)
	layer.add_child(top_mid)
	_banner = Button.new()
	_banner.add_theme_stylebox_override("normal", _box(C_RED.darkened(0.15), Color(1, 0.6, 0.5), 18))
	_banner.add_theme_stylebox_override("hover", _box(C_RED, Color(1, 0.7, 0.6), 18))
	_banner.add_theme_stylebox_override("pressed", _box(C_RED.darkened(0.3), Color(1, 0.7, 0.6), 18))
	_banner.icon = load(ICONS + "alarm.png")
	_banner.visible = false
	_banner.pressed.connect(_on_banner)
	top_mid.add_child(_banner)
	_toasts = VBoxContainer.new()
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	top_mid.add_child(_toasts)

	# Bottom left: Jobs, Raids, Chat.
	var left := HBoxContainer.new()
	_pin(left, Control.PRESET_BOTTOM_LEFT)
	left.add_theme_constant_override("separation", 8)
	layer.add_child(left)
	_jobs_btn = _round_button(left, "Jobs", "mission_complete", func(): _toggle_page("jobs"))
	_raids_btn = _round_button(left, "Raids", "alarm", func(): _toggle_page("raids"))
	_round_button(left, "Chat", "chat", func(): _toggle_page("chat"))
	_sites_btn = _round_button(left, "Sites", "nav_map", func(): _toggle_page("sites"))
	_home_btn = _round_button(left, "Home", "waypoint", func(): show_view(""))
	_home_btn.visible = false

	# Bottom right: the shop.
	var build := Button.new()
	build.text = "Build"
	build.icon = load(ICONS + "launch.png")
	build.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	build.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	build.add_theme_constant_override("icon_max_width", 44)
	build.add_theme_font_size_override("font_size", 20)
	build.add_theme_color_override("font_color", Color(0.1, 0.08, 0.02))
	build.add_theme_color_override("font_hover_color", Color(0.1, 0.08, 0.02))
	build.add_theme_color_override("font_pressed_color", Color(0.1, 0.08, 0.02))
	build.add_theme_stylebox_override("normal", _box(C_AMBER, Color(1, 0.85, 0.5), 18))
	build.add_theme_stylebox_override("hover", _box(C_AMBER.lightened(0.15), Color(1, 0.9, 0.6), 18))
	build.add_theme_stylebox_override("pressed", _box(C_AMBER.darkened(0.2), Color(1, 0.9, 0.6), 18))
	build.custom_minimum_size = Vector2(96, 92)
	_pin(build, Control.PRESET_BOTTOM_RIGHT)
	build.pressed.connect(func(): open_shop())
	layer.add_child(build)

	# Bottom centre: the selected pad's name and actions.
	_select_box = VBoxContainer.new()
	_pin(_select_box, Control.PRESET_CENTER_BOTTOM)
	_select_box.offset_left = 80 # clear of the buttons bottom left
	_select_box.offset_right = 80
	_select_box.alignment = BoxContainer.ALIGNMENT_END
	_select_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_select_box.visible = false
	layer.add_child(_select_box)
	_select_name = _label(_select_box, 18)
	_select_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_select_name.add_theme_stylebox_override("normal", _box(C_PANEL, C_TEAL.darkened(0.4), 14, 4))
	_select_name.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_actions = HBoxContainer.new()
	_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_actions.add_theme_constant_override("separation", 8)
	_select_box.add_child(_actions)

	# Bottom centre while placing: what you're placing, and Cancel.
	_place_bar = PanelContainer.new()
	_pin(_place_bar, Control.PRESET_CENTER_BOTTOM)
	_place_bar.visible = false
	layer.add_child(_place_bar)
	var place_row := HBoxContainer.new()
	place_row.add_theme_constant_override("separation", 12)
	_place_bar.add_child(place_row)
	_place_label = _label(place_row, 17)
	_place_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var cancel := Button.new()
	cancel.text = "Done"
	cancel.pressed.connect(func(): _set_placing(""))
	place_row.add_child(cancel)

	_build_drawer(layer)
	_build_shop(layer)


## Left-hand drawer for Jobs, Raids, Chat and building info.
func _build_drawer(layer: Control) -> void:
	_drawer = PanelContainer.new()
	_drawer.anchor_top = 0.0
	_drawer.anchor_bottom = 1.0
	_drawer.offset_top = 70
	_drawer.offset_bottom = -90
	_drawer.custom_minimum_size = Vector2(340, 0)
	_drawer.visible = false
	layer.add_child(_drawer)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_drawer.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	_drawer_title = _label(head, 20)
	_drawer_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close := Button.new()
	close.text = "X"
	close.pressed.connect(func(): _show_page(""))
	head.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	var jobs := VBoxContainer.new()
	jobs.add_theme_constant_override("separation", 10)
	body.add_child(jobs)
	_post_job = Button.new()
	_post_job.icon = load(ICONS + "send.png")
	_post_job.text = "Post job: deliver %d %s for %d credits" % [JOB.amount, JOB.resource, JOB.reward]
	_post_job.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_post_job.pressed.connect(_send_job)
	jobs.add_child(_post_job)
	_jobs = _label(jobs, 15)
	_jobs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pages["jobs"] = jobs

	_raids = _label(body, 15)
	_raids.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pages["raids"] = _raids
	_info = _label(body, 15)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pages["info"] = _info

	# The Shipyard: the Foundry's queue, the navy, and a button per warship.
	var yard := VBoxContainer.new()
	yard.add_theme_constant_override("separation", 10)
	body.add_child(yard)
	_yard_fleet = _label(yard, 15)
	_yard_fleet.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_yard_queue = _label(yard, 15)
	_yard_queue.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_yard_cancel = Button.new()
	_yard_cancel.text = "Cancel last in queue (full refund)"
	_yard_cancel.pressed.connect(func(): Net.send({"type": "cancel_ship", "planet": _pid(), "slot": _foundry_slot()}))
	yard.add_child(_yard_cancel)
	var to_fleet := Button.new()
	to_fleet.text = "Fleet and attacks"
	to_fleet.icon = load(ICONS + "launch.png")
	to_fleet.pressed.connect(func(): _show_page("fleet"))
	yard.add_child(to_fleet)
	_yard_ships = VBoxContainer.new()
	_yard_ships.add_theme_constant_override("separation", 8)
	yard.add_child(_yard_ships)
	_pages["shipyard"] = yard

	# Sites: home and each satellite site, plus how to found more.
	_sites_list = VBoxContainer.new()
	_sites_list.add_theme_constant_override("separation", 8)
	body.add_child(_sites_list)
	_pages["sites"] = _sites_list

	# Fleet: ships out and coming home, fleets heading for your sites, and targets to attack.
	var fleet := VBoxContainer.new()
	fleet.add_theme_constant_override("separation", 10)
	body.add_child(fleet)
	_fleet_status = _label(fleet, 15)
	_fleet_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var targets_title := _label(fleet, 16)
	targets_title.text = "Targets: other Builders' satellite sites"
	_fleet_targets = VBoxContainer.new()
	_fleet_targets.add_theme_constant_override("separation", 8)
	fleet.add_child(_fleet_targets)
	_fleet_log = _label(fleet, 14)
	_fleet_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fleet_log.modulate = Color(0.8, 0.9, 0.95)
	_pages["fleet"] = fleet

	var chat := VBoxContainer.new()
	chat.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(chat)
	_chat_log = _label(chat, 15)
	_chat_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_log.text = "No messages yet."
	var chat_row := HBoxContainer.new()
	chat.add_child(chat_row)
	var chat_edit := LineEdit.new()
	chat_edit.placeholder_text = "Message pilots"
	chat_edit.max_length = 200
	chat_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_row.add_child(chat_edit)
	var send := Button.new()
	send.icon = load(ICONS + "send.png")
	chat_row.add_child(send)
	var send_chat := func(_text = ""):
		if chat_edit.text.strip_edges() != "":
			Net.send({"type": "chat", "text": chat_edit.text})
		chat_edit.text = ""
	send.pressed.connect(send_chat)
	chat_edit.text_submitted.connect(send_chat)
	_pages["chat"] = chat

	for p in _pages.values():
		p.visible = false


## Bottom sheet listing what can be built.
func _build_shop(layer: Control) -> void:
	_shop = PanelContainer.new()
	_pin(_shop, Control.PRESET_BOTTOM_WIDE)
	_shop.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_shop.visible = false
	layer.add_child(_shop)
	var col := VBoxContainer.new()
	_shop.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := _label(head, 20)
	title.text = "Build"
	_shop_hint = _label(head, 15)
	_shop_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shop_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_shop_hint.modulate = Color(0.75, 0.9, 0.95)
	var close := Button.new()
	close.text = "X"
	close.pressed.connect(func(): _shop.visible = false)
	head.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 176)
	col.add_child(scroll)
	_shop_cards = HBoxContainer.new()
	_shop_cards.add_theme_constant_override("separation", 10)
	scroll.add_child(_shop_cards)


## Pins a control to a corner or edge of its parent; it grows away from that edge as it fills.
func _pin(c: Control, preset: Control.LayoutPreset) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = 0
	c.offset_right = 0
	c.offset_top = 0
	c.offset_bottom = 0
	var right := preset in [PRESET_TOP_RIGHT, PRESET_BOTTOM_RIGHT, PRESET_CENTER_RIGHT]
	var bottom := preset in [PRESET_BOTTOM_LEFT, PRESET_BOTTOM_RIGHT, PRESET_CENTER_BOTTOM]
	var centre_h := preset in [PRESET_CENTER_TOP, PRESET_CENTER_BOTTOM]
	c.grow_horizontal = GROW_DIRECTION_BOTH if centre_h else (GROW_DIRECTION_BEGIN if right else GROW_DIRECTION_END)
	c.grow_vertical = GROW_DIRECTION_BEGIN if bottom else GROW_DIRECTION_END


func _label(parent: Node, font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


## A resource pill for the top bar: icon and number.
func _pill(parent: Node, icon: String) -> Label:
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", _box(C_PANEL, C_TEAL.darkened(0.4), 20, 4))
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(pill)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	pill.add_child(row)
	var pic := TextureRect.new()
	pic.texture = load(ICONS + icon + ".png")
	pic.custom_minimum_size = Vector2(26, 26)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(pic)
	var l := _label(row, 17)
	l.custom_minimum_size = Vector2(40, 0)
	l.text = "0"
	return l


func _round_button(parent: Node, text: String, icon: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.icon = load(ICONS + icon + ".png")
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_constant_override("icon_max_width", 34)
	b.add_theme_font_size_override("font_size", 14)
	b.custom_minimum_size = Vector2(72, 72)
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b


## A short message near the top of the screen that fades away.
func toast(text: String, color := Color.WHITE) -> void:
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", _box(C_PANEL, color.darkened(0.2), 16, 5))
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var l := _label(pill, 15)
	l.text = text
	_toasts.add_child(pill)
	var live := _toasts.get_children().filter(func(c): return not c.is_queued_for_deletion())
	for i in live.size() - 3:
		live[i].queue_free()
	var tw := create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(pill, "modulate:a", 0.0, 0.6)
	tw.tween_callback(pill.queue_free)


# --- HUD behaviour -----------------------------------------------------------------------

func _toggle_page(page: String) -> void:
	_show_page("" if _page == page else page)


func _show_page(page: String) -> void:
	_page = page
	for p in _pages:
		_pages[p].visible = p == page
	_drawer.visible = page != ""
	_top_mid.anchor_left = 0.68 if page != "" else 0.5
	_top_mid.anchor_right = _top_mid.anchor_left
	_drawer_title.text = {"jobs": "Jobs", "raids": "Raids", "chat": "Chat", "info": "Info", "shipyard": "Shipyard", "sites": "Your sites", "fleet": "Fleet"}.get(page, "")
	if page != "":
		_shop.visible = false
	if page == "info" and _selected >= 0:
		_drawer_title.text = _pad_name(_selected)
	if not Net.state.is_empty():
		_refresh(Net.state)


func select_pad(i: int) -> void:
	_selected = i
	if _page == "info" and i < 0:
		_show_page("")
	if not Net.state.is_empty():
		_refresh(Net.state)
	else:
		_refresh_selection({})


## Opens the shop. With an empty pad selected, a pick builds there; otherwise pick a pad next.
func open_shop() -> void:
	_set_placing("")
	_show_page("")
	_shop.visible = true
	if not Net.state.is_empty():
		_refresh(Net.state)


func _set_placing(type: String) -> void:
	_placing = type
	_place_bar.visible = type != ""
	if type != "":
		if _view == "":
			_place_label.text = "Tap a free pad to place the %s" % BUILDING_INFO[type].name
		else:
			_place_label.text = "Tap the grid to place a %s. Tap Done when finished." % Net.catalog.sites.pieces[type].name
		_selected = -1
		_sel_piece = -1
	if not Net.state.is_empty():
		_refresh(Net.state)


func _on_banner() -> void:
	var raids := _my_raids()
	if raids.is_empty():
		var incoming := _incoming()
		if not incoming.is_empty():
			show_view(incoming[0].target)
		return
	var r: Dictionary = raids[0]
	if Net.planet(r.planet).get("kind", "") == "satellite":
		show_view(r.planet)
	else:
		show_view("")
		focus_pad(int(r.slot))
	select_pad(int(r.slot))
	_show_page("info")


func _send_job() -> void:
	Net.send({"type": "post_job", "planet": _pid(), "resource": JOB.resource, "amount": JOB.amount, "reward": JOB.reward})


func _build(slot: int, type: String) -> void:
	Net.send({"type": "build", "planet": _pid(), "slot": slot, "building": type})


func _shop_pick(type: String) -> void:
	_shop.visible = false
	if _view != "":
		_set_placing(type) # a defence for this site
		return
	if _is_facility(type):
		Net.send({"type": "found_site", "facility": type})
		return
	if _selected >= 0 and _building_at(_selected).is_empty():
		_build(_selected, type)
	else:
		_set_placing(type)


# --- State -------------------------------------------------------------------------------

## The planet on screen: the home planet, or the satellite site being shown.
func _planet() -> Dictionary:
	return Net.planet(_view) if _view != "" else Net.my_planet()


## The id of the planet on screen.
func _pid() -> String:
	return str(_planet().get("id", "aster"))


## This Builder's economy: stock, credits, population, unlocks and navy.
func _econ() -> Dictionary:
	return Net.my_economy()


## Live raids on this Builder's planets and sites.
func _my_raids() -> Array:
	var owner = Net.my_planet().get("owner")
	return Net.state.get("raids", []).filter(func(r): return Net.planet(r.planet).get("owner") == owner)


## This Builder's satellite sites.
func _my_sites() -> Array:
	if Net.state.is_empty():
		return []
	var owner = Net.my_planet().get("owner")
	return Net.state.system.planets.filter(func(p): return p.get("kind", "") == "satellite" and owner != null and p.owner == owner)


func _building_at(slot: int) -> Dictionary:
	var planet := _planet()
	if planet.is_empty():
		return {}
	for b in planet.buildings:
		if int(b.slot) == slot:
			return b
	return {}


func _is_facility(type: String) -> bool:
	return Net.catalog.get("facilities", {}).has(type)


func _pad_name(slot: int) -> String:
	var b := _building_at(slot)
	if b.is_empty():
		return "Empty pad %d" % (slot + 1)
	var n: String = BUILDING_INFO.get(b.type, {"name": b.type}).name
	return "%s  (Tier %d)" % [n, int(b.security)] if _is_facility(b.type) else n


func _cost_text(cost: Dictionary) -> String:
	var parts := []
	for id in cost:
		parts.append("%d %s" % [cost[id], id if id in ["metal", "ice", "credits"] else Net.item_name(id)])
	return ", ".join(parts)


func _can_afford(cost: Dictionary) -> bool:
	for id in cost:
		var have := float(_econ().credits) if id == "credits" else float(_econ().stock.get(id, 0))
		if have < float(cost[id]):
			return false
	return true


func _refresh(state: Dictionary) -> void:
	var e := _econ()
	var stock: Dictionary = e.stock
	_title.text = state.system.name
	_subtitle.text = "Planet %s" % _planet().get("name", "")
	_stock.credits.text = str(int(e.credits))
	_stock.metal.text = str(int(stock.metal))
	_stock.ice.text = str(int(stock.get("ice", 0)))
	_stock.population.text = str(int(e.population))
	_stock.navy.text = str(_fleet_size(state))
	var goods := []
	for id in stock:
		if id not in ["metal", "ice"] and int(stock[id]) > 0:
			goods.append("%s %d" % [Net.item_name(id), stock[id]])
	var income := _income_text()
	_goods.text = "\n".join([income, "   ".join(goods)].filter(func(l): return l != ""))
	_goods.visible = _goods.text != ""

	_follow_new_site()
	if _view != "" and Net.planet(_view).is_empty():
		show_view("") # the site is gone
		return
	_subtitle.text = ("Satellite site off %s" % Net.my_planet().get("name", "")) if _view != "" else _subtitle.text
	if _view == "":
		_refresh_pads(state)
	else:
		_refresh_site(state)
	_refresh_selection(state)
	if _page == "sites":
		_refresh_sites(state)
	if _page == "fleet":
		_refresh_fleet(state)
	_refresh_raids(state)
	_refresh_jobs(state)
	if _page == "shipyard":
		_refresh_shipyard(state)
	if _shop.visible:
		_refresh_shop(state)
	if _page == "info":
		_refresh_info(state)
	_toast_feed(state)


func _refresh_pads(state: Dictionary) -> void:
	var tiers: Dictionary = Net.catalog.get("security", {})
	for i in _pads.size():
		var p: Dictionary = _pads[i]
		var b := _building_at(i)
		var raid := Net.raid_on(_pid(), i) if not b.is_empty() else {}
		var key := ""
		if not b.is_empty():
			key = "%s:%d" % [b.type, int(b.get("security", 0))]
			if b.type == "foundry":
				key += ":%d" % mini(_fleet_size(state), 3)
		if key != p.key:
			if p.model:
				p.model.queue_free()
				p.model = null
			if not b.is_empty():
				p.model = Node3D.new()
				p.model.position.y = 1.0
				p.model.rotation_degrees.y = 45.0 + 60.0 * i
				p.root.add_child(p.model)
				p.model.add_child(BaseModels.building(b.type))
				# Security turrets around a facility, one per turret its tier adds.
				var turrets := int(tiers.get(str(int(b.get("security", 0))), {}).get("turrets", 0))
				for t in turrets:
					var tur := BaseModels.turret()
					var ang := TAU * (t + 0.5) / maxf(turrets, 1) + 0.6
					tur.position = Vector3(cos(ang), 0, sin(ang)) * (PAD_RADIUS - 1.2)
					tur.rotation.y = -ang - PI / 2
					p.model.add_child(tur)
				# Up to three finished warships parked beside the Foundry.
				if b.type == "foundry":
					for s in mini(_fleet_size(state), 3):
						var ship := BaseModels.Models.starter_ship()
						ship.scale = Vector3.ONE * 0.38
						ship.position = Vector3(-6.0 + s * 3.2, 1.2, 5.6)
						ship.rotation_degrees.y = 180.0
						p.model.add_child(ship)
			p.key = key
		p.plus.visible = b.is_empty()
		p.plus.modulate = Color(0.5, 1.0, 0.6, 0.95) if _placing != "" else Color(0.6, 1.0, 1.0, 0.6)
		p.label.visible = not b.is_empty()
		if not b.is_empty():
			var n: String = BUILDING_INFO.get(b.type, {"name": b.type}).name
			if _is_facility(b.type):
				n += "  T%d" % int(b.security)
			p.label.text = ("RAID!  " + n) if not raid.is_empty() else n
			p.label.modulate = Color(1, 0.55, 0.45) if not raid.is_empty() else Color(1, 1, 1, 0.9)
		p.light.visible = not raid.is_empty()
		var placing_here := _placing != "" and b.is_empty()
		p.ring.visible = placing_here or _selected == i or not raid.is_empty()
		var ring_color := C_AMBER
		if placing_here:
			ring_color = Color(0.4, 1.0, 0.5)
		elif not raid.is_empty() and _selected != i:
			ring_color = C_RED
		(p.ring.material_override as StandardMaterial3D).albedo_color = ring_color
		(p.ring.material_override as StandardMaterial3D).emission = ring_color


## Name and action buttons for the selected pad.
func _refresh_selection(state: Dictionary) -> void:
	_select_box.visible = (_selected >= 0 or _sel_piece >= 0) and _placing == "" and not _shop.visible
	if not _select_box.visible:
		return
	if _sel_piece >= 0:
		var piece := _piece(_sel_piece)
		if piece.is_empty():
			_sel_piece = -1
			_select_box.visible = false
			return
		if _sel_is_obstacle:
			var od: Dictionary = Net.catalog.sites.obstacles[piece.type]
			var salvage := []
			for res in od.salvage:
				salvage.append("%d %s" % [od.salvage[res], Net.item_name(res) if res not in ["metal", "ice"] else res])
			_select_name.text = "%s  (clearing leaves %s)" % [od.name, ", ".join(salvage)]
			_set_actions([{"id": "clear", "text": "Clear  %d" % int(od.clear), "icon": "credits"}])
			return
		_select_name.text = Net.catalog.sites.pieces[piece.type].name
		_set_actions([{"id": "remove", "text": "Remove", "icon": "economy"}])
		return
	_select_name.text = _pad_name(_selected)
	var b := _building_at(_selected)
	var acts := []
	if b.is_empty():
		acts.append({"id": "build", "text": "Build here", "icon": "launch"})
	else:
		acts.append({"id": "info", "text": "Info", "icon": "notifications"})
		if b.type == "spaceport":
			acts.append({"id": "job", "text": "Post job", "icon": "send",
				"disabled": not Net.open_job(_pid()).is_empty()})
		if b.type == "foundry":
			var building: Array = b.get("queue", [])
			acts.append({"id": "shipyard", "icon": "ship_emblem",
				"text": "Shipyard" if building.is_empty() else "Shipyard (%d)" % building.size()})
		if _is_facility(b.type) and not state.is_empty():
			var now := Net.now_ms()
			var wait := (float(b.shipReadyAt) - now) / 1000.0
			var vault_empty := true
			for id in b.vault:
				if int(b.vault[id]) > 0:
					vault_empty = false
			acts.append({"id": "ship", "icon": "launch", "disabled": wait > 0 or vault_empty,
				"text": "Ship cargo" if wait <= 0 else "Freighter %ds" % ceili(wait)})
			var next: Dictionary = Net.catalog.security.get(str(int(b.security) + 1), {})
			if not next.is_empty():
				acts.append({"id": "upgrade", "icon": "rank", "text": "Tier %d" % (int(b.security) + 1),
					"disabled": not Net.raid_on(_pid(), _selected).is_empty() or not _can_afford(next.cost)})
			if not Net.raid_on(_pid(), _selected).is_empty():
				var alarm_wait := (float(b.alarmReadyAt) - now) / 1000.0
				acts.append({"id": "alarm", "icon": "alarm", "disabled": alarm_wait > 0, "danger": true,
					"text": "Alarm (%d cr)" % Net.catalog.alarmCost if alarm_wait <= 0 else "Alarm %ds" % ceili(alarm_wait)})
	_set_actions(acts)


## Updates the action buttons in place, so a button never vanishes under a finger.
func _set_actions(acts: Array) -> void:
	var ids := acts.map(func(a): return a.id)
	if ids != _action_ids:
		for c in _actions.get_children():
			c.queue_free()
		for a in acts:
			var btn := Button.new()
			btn.icon = load(ICONS + a.icon + ".png")
			btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			btn.add_theme_constant_override("icon_max_width", 32)
			btn.add_theme_font_size_override("font_size", 14)
			btn.custom_minimum_size = Vector2(86, 74)
			if a.get("danger", false):
				btn.add_theme_stylebox_override("normal", _box(C_RED.darkened(0.3), Color(1, 0.6, 0.5), 12))
			btn.pressed.connect(_on_action.bind(a.id))
			_actions.add_child(btn)
		_action_ids = ids
	var buttons := _actions.get_children().filter(func(c): return not c.is_queued_for_deletion())
	for i in acts.size():
		buttons[i].text = acts[i].text
		buttons[i].disabled = acts[i].get("disabled", false)


func _on_action(id: String) -> void:
	match id:
		"build":
			open_shop()
		"info":
			_toggle_page("info")
		"job":
			_send_job()
		"shipyard":
			_toggle_page("shipyard")
		"remove":
			Net.send({"type": "remove_piece", "planet": _view, "piece": _sel_piece})
			_sel_piece = -1
		"clear":
			Net.send({"type": "clear_obstacle", "planet": _view, "obstacle": _sel_piece})
			_sel_piece = -1
		"ship":
			Net.send({"type": "ship_cargo", "planet": _pid(), "slot": _selected})
		"upgrade":
			Net.send({"type": "upgrade_security", "planet": _pid(), "slot": _selected})
		"alarm":
			Net.send({"type": "sound_alarm", "planet": _pid(), "slot": _selected})


func _refresh_shop(state: Dictionary) -> void:
	for c in _shop_cards.get_children():
		c.queue_free()
	if _view != "":
		_refresh_defence_shop()
		return
	var target := _selected >= 0 and _building_at(_selected).is_empty()
	_shop_hint.text = "  Building on pad %d" % (_selected + 1) if target else "  Pick a building, then tap a free pad. Facilities get their own satellite site."
	var sites_full := _my_sites().size() >= int(Net.catalog.get("sites", {}).get("max", 3))
	for type in BUILDING_INFO:
		var info: Dictionary = BUILDING_INFO[type]
		var card := Button.new()
		card.custom_minimum_size = Vector2(150, 166)
		var icon: String = CARD_ICON.get(type, type)
		card.icon = load(ICONS + icon + ".png") if ResourceLoader.exists(ICONS + icon + ".png") else load(ICONS + "vault.png")
		card.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		card.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_theme_constant_override("icon_max_width", 72)
		card.add_theme_font_size_override("font_size", 14)
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var locked: bool = type not in _econ().unlocked
		var why := "Locked: needs ice in stock" if locked else ""
		if not locked and info.has("needs") and not Net.has_building(info.needs, _pid()):
			why = "Needs a %s" % BUILDING_INFO[info.needs].name
		if not locked and info.has("limit") and _count(type) >= int(info.limit):
			why = "Already built"
		if not locked and _is_facility(type) and sites_full:
			why = "All satellite sites used"
		locked = locked or why != ""
		var afford := _can_afford(info.cost)
		card.text = "%s\n%s" % [info.name, why if locked else _cost_text(info.cost) + ("\nNew satellite site" if _is_facility(type) else "")]
		card.disabled = locked or not afford
		if not locked and not afford:
			card.add_theme_color_override("font_disabled_color", Color(1, 0.6, 0.55))
		card.pressed.connect(_shop_pick.bind(type))
		_shop_cards.add_child(card)


## The site view's shop: defences to place on the grid.
func _refresh_defence_shop() -> void:
	_shop_hint.text = "  Defences for this site. Pick one, then tap the grid."
	var pieces: Dictionary = Net.catalog.get("sites", {}).get("pieces", {})
	var icons := {"turret": "rank", "wall": "vault", "guardpost": "pilot_arrow"}
	for type in pieces:
		var def: Dictionary = pieces[type]
		var card := Button.new()
		card.custom_minimum_size = Vector2(150, 166)
		card.icon = load(ICONS + icons.get(type, "vault") + ".png")
		card.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		card.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_theme_constant_override("icon_max_width", 64)
		card.add_theme_font_size_override("font_size", 14)
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.text = "%s  (%dx%d)\n%s\nAttack %d  Hull %d" % [def.name, def.w, def.h, _cost_text(def.cost), def.attack, def.hull]
		card.disabled = not _can_afford(def.cost)
		card.pressed.connect(_shop_pick.bind(type))
		_shop_cards.add_child(card)


## The selected defence, or obstacle when _sel_is_obstacle.
func _piece(id: int) -> Dictionary:
	for p in _planet().get("obstacles" if _sel_is_obstacle else "pieces", []):
		if int(p.id) == id:
			return p
	return {}


func _refresh_site(state: Dictionary) -> void:
	var site := _planet()
	var b: Dictionary = site.buildings[0] if site.get("buildings", []) else {}
	var tier := int(b.get("security", 1))
	var turrets := int(Net.catalog.get("security", {}).get(str(tier), {}).get("turrets", 0))
	var raid := not Net.raid_on(_view, 0).is_empty()
	_site.show_site(site, "%s  T%d" % [site.name, tier], raid, turrets)
	if _selected == 0:
		_site.highlight(_site.core)
	elif _sel_piece >= 0 and not _piece(_sel_piece).is_empty():
		var p := _piece(_sel_piece)
		var def: Dictionary = Net.catalog.sites.obstacles[p.type] if _sel_is_obstacle else Net.catalog.sites.pieces[p.type]
		_site.highlight(Rect2i(int(p.x), int(p.y), int(def.w), int(def.h)))
	else:
		_site.highlight(Rect2i())


## Opens a site the Builder has just founded.
func _follow_new_site() -> void:
	if Net.home == "":
		return # not welcomed yet, so which sites are ours isn't known
	var sites := _my_sites()
	var before := _site_count
	_site_count = sites.size() # before show_view, which refreshes and lands back here
	if before >= 0 and sites.size() > before:
		show_view(sites[-1].id)
		toast("New satellite site: tap Build to place defences", C_TEAL)


func _refresh_sites(state: Dictionary) -> void:
	var sites := _my_sites()
	var key := JSON.stringify([_view, sites.map(func(s): return [s.id, s.buildings[0].security if s.buildings else 0, s.get("pieces", []).size()]), _my_raids().size()])
	if key == _sites_key:
		return
	_sites_key = key
	for c in _sites_list.get_children():
		c.queue_free()
	var home := Button.new()
	home.text = "Home: Planet %s" % Net.my_planet().get("name", "")
	home.icon = load(ICONS + "waypoint.png")
	home.alignment = HORIZONTAL_ALIGNMENT_LEFT
	home.disabled = _view == ""
	home.pressed.connect(func(): show_view(""))
	_sites_list.add_child(home)
	for st in sites:
		var b: Dictionary = st.buildings[0] if st.buildings else {}
		var btn := Button.new()
		var raid := not Net.raid_on(st.id, 0).is_empty()
		btn.text = "%s\nTier %d, %d defences%s" % [st.name, int(b.get("security", 1)), st.get("pieces", []).size(), ", RAID!" if raid else ""]
		btn.icon = load(ICONS + ("alarm" if raid else "nav_map") + ".png")
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.disabled = _view == st.id
		var id: String = st.id
		btn.pressed.connect(func(): show_view(id))
		_sites_list.add_child(btn)
	var hint := _label(_sites_list, 14)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(0.75, 0.9, 0.95)
	hint.text = "Found a satellite site by buying a facility in the Build shop (up to %d)." % int(Net.catalog.get("sites", {}).get("max", 3))


## Fleets on their way to this Builder's sites.
func _incoming() -> Array:
	return Net.state.get("attacks", []).filter(func(a): return a.defender == Net.my_planet().get("owner") and a.status == "flying")


## A site's whole defence, worked out the same way as the server's siteDefence().
func _site_defence(site: Dictionary) -> Dictionary:
	var pieces: Dictionary = Net.catalog.get("sites", {}).get("pieces", {})
	var attack := 0
	var hull := 0
	for p in site.get("pieces", []):
		attack += int(pieces[p.type].attack)
		hull += int(pieces[p.type].hull)
	var tier := int(site.buildings[0].security) if site.get("buildings", []) else 1
	var s: Dictionary = Net.catalog.get("security", {}).get(str(tier), {"turrets": 0, "guards": 0})
	attack += int(s.turrets) * int(pieces.get("turret", {"attack": 0}).attack) + int(s.guards)
	hull += int(s.turrets) * int(pieces.get("turret", {"hull": 0}).hull) + 40 * tier
	return {"attack": attack, "hull": hull}


func _fleet_power() -> Dictionary:
	var ships: Dictionary = Net.catalog.get("ships", {})
	var navy: Dictionary = _econ().get("navy", {})
	var attack := 0
	var hull := 0
	for id in navy:
		attack += int(navy[id]) * int(ships.get(id, {"attack": 0}).attack)
		hull += int(navy[id]) * int(ships.get(id, {"hull": 0}).hull)
	return {"attack": attack, "hull": hull}


func _refresh_fleet(state: Dictionary) -> void:
	var me = Net.my_planet().get("owner")
	var now := Net.now_ms()
	var power := _fleet_power()
	var lines := ["In the hangar: %d ships, attack %d, hull %d" % [_fleet_size(state), power.attack, power.hull]]
	for a in state.get("attacks", []):
		var t := 0.0
		if a.status == "flying":
			t = (float(a.arriveAt) - now) / 1000.0
		else:
			t = (float(a.returnAt) - now) / 1000.0
		t = maxf(t, 0.0)
		if a.attacker == me:
			lines.append(("Your fleet reaches %s in %d:%02d" if a.status == "flying" else "Your fleet is flying home from %s, %d:%02d") % [a.siteName, int(t) / 60, int(t) % 60])
		elif a.defender == me and a.status == "flying":
			lines.append("INCOMING: %s's fleet reaches your %s in %d:%02d" % [a.attacker, a.siteName, int(t) / 60, int(t) % 60])
	_fleet_status.text = "\n".join(lines)

	var targets: Array = state.system.planets.filter(func(p): return p.get("kind", "") == "satellite" and p.get("owner") != null and p.owner != me)
	var key := JSON.stringify([targets.map(func(p): return [p.id, p.get("shieldUntil", 0) > now, _site_defence(p)]), _fleet_size(state)])
	if key != _fleet_key:
		_fleet_key = key
		for c in _fleet_targets.get_children():
			c.queue_free()
		if targets.is_empty():
			_label(_fleet_targets, 14).text = "No other Builder has a satellite site yet."
		for p in targets:
			var d := _site_defence(p)
			var shielded := float(p.get("shieldUntil", 0)) > now
			var btn := Button.new()
			btn.icon = load(ICONS + "launch.png")
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			btn.text = "%s (%s)\nDefence: attack %d, hull %d%s" % [p.name, p.owner, d.attack, d.hull, "\nShielded after an attack" if shielded else ("\nTap to send every ship" if _fleet_size(state) > 0 else "\nNo ships in the hangar")]
			btn.disabled = shielded or _fleet_size(state) == 0
			var id: String = p.id
			btn.pressed.connect(func(): Net.send({"type": "launch_attack", "target": id}))
			_fleet_targets.add_child(btn)

	var log_lines := []
	var history: Array = state.get("attackLog", [])
	for i in range(history.size() - 1, maxi(-1, history.size() - 6), -1):
		var e: Dictionary = history[i]
		if e.attacker != me and e.defender != me:
			continue
		var loot := []
		for item in e.loot:
			loot.append("%d %s" % [e.loot[item], Net.item_name(item)])
		var lost := 0
		for id in e.lost:
			lost += int(e.lost[id])
		if e.attacker == me:
			log_lines.append("%s at %s: %s, %d ships lost%s" % ["Won" if e.won else "Driven off", e.site, "took " + ", ".join(loot) if loot else "no loot", lost, ""])
		else:
			log_lines.append("%s attacked your %s: %s" % [e.attacker, e.site, ("they took " + ", ".join(loot)) if e.won else "your defences held"])
	_fleet_log.text = ("Recent battles\n" + "\n".join(log_lines)) if log_lines else ""


func _refresh_info(state: Dictionary) -> void:
	if _selected < 0:
		_info.text = ""
		return
	_drawer_title.text = _pad_name(_selected)
	var b := _building_at(_selected)
	if b.is_empty():
		_info.text = "An empty pad. Tap Build to put something here."
		return
	var lines: Array = [BUILDING_INFO.get(b.type, {}).get("about", "")]
	if _is_facility(b.type):
		var now := Net.now_ms()
		var vault := []
		for id in b.vault:
			if int(b.vault[id]) > 0:
				vault.append("%d %s" % [b.vault[id], Net.item_name(id)])
		lines.append("Vault: %s" % (", ".join(vault) if vault else "empty"))
		if b.has("autoShipAt"):
			var left := maxf(0.0, (float(b.autoShipAt) - now) / 1000.0)
			lines.append("Next freighter home in %d:%02d" % [int(left) / 60, int(left) % 60])
		var escrow := []
		for id in b.get("escrow", {}):
			escrow.append("%d %s" % [b.escrow[id], Net.item_name(id)])
		if escrow:
			lines.append("In the raid zone: %s" % ", ".join(escrow))
		var tier := int(b.security)
		var s: Dictionary = Net.catalog.security[str(tier)]
		lines.append("Security tier %d: %d guards, %d turrets, %d-minute raid clock" % [tier, s.guards, s.turrets, s.minutes])
		var next: Dictionary = Net.catalog.security.get(str(tier + 1), {})
		if not next.is_empty():
			lines.append("Tier %d costs %s" % [tier + 1, _cost_text(next.cost)])
		var raid := Net.raid_on(_pid(), _selected)
		if not raid.is_empty():
			lines.append("INTRUDER: %s is inside. Heat %d." % [raid.pilot, raid.heat])
		elif float(b.cooldownUntil) > now:
			lines.append("Guards on alert after a raid: no one can board for %d s" % ceili((float(b.cooldownUntil) - now) / 1000.0))
	_info.text = "\n\n".join(lines)


## What the home planet's buildings earn a minute, e.g. "+12 metal  +2 ice  +12 credits a minute".
func _income_text() -> String:
	var per_tick := {}
	var produces: Dictionary = Net.catalog.get("produces", {})
	for b in Net.my_planet().get("buildings", []):
		for res in produces.get(b.type, {}):
			per_tick[res] = per_tick.get(res, 0.0) + float(produces[b.type][res])
	var parts := []
	for res in ["metal", "ice", "credits"]:
		if per_tick.has(res):
			parts.append("+%s %s" % [str(snappedf(per_tick[res] * 12.0, 0.1)).trim_suffix(".0"), res])
	return ("  ".join(parts) + " a minute") if parts else ""


func _count(type: String) -> int:
	var n := 0
	for b in _planet().get("buildings", []):
		if b.type == type:
			n += 1
	return n


func _fleet_size(state: Dictionary) -> int:
	var n := 0
	var navy: Dictionary = _econ().get("navy", {})
	for id in navy:
		n += int(navy[id])
	return n


func _foundry_slot() -> int:
	var planet := _planet()
	if planet.is_empty():
		return -1
	for b in planet.buildings:
		if b.type == "foundry":
			return int(b.slot)
	return -1


func _refresh_shipyard(state: Dictionary) -> void:
	var ships: Dictionary = Net.catalog.get("ships", {})
	var slot := _foundry_slot()
	var queue: Array = _building_at(slot).get("queue", []) if slot >= 0 else []
	var navy: Dictionary = _econ().get("navy", {})
	var fleet := []
	for id in ships:
		fleet.append("%d %s" % [int(navy.get(id, 0)), ships[id].name + ("s" if int(navy.get(id, 0)) != 1 else "")])
	var hangar := int(Net.catalog.get("hangar", 10))
	_yard_fleet.text = "Navy: %s\nHangar: %d of %d berths used" % [", ".join(fleet), _fleet_size(state) + queue.size(), hangar]
	var lines := []
	var now := Net.now_ms()
	for i in queue.size():
		var q: Dictionary = queue[i]
		var name: String = ships.get(q.ship, {"name": q.ship}).name
		if i == 0 and q.doneAt != null:
			var left := maxf(0.0, (float(q.doneAt) - now) / 1000.0)
			lines.append("Building: %s, %d:%02d left" % [name, int(left) / 60, int(left) % 60])
		else:
			lines.append("Next: %s" % name)
	_yard_queue.text = "\n".join(lines) if lines else "Nothing building. Pick a warship below."
	_yard_cancel.visible = not queue.is_empty()

	var full := queue.size() >= int(Net.catalog.get("shipQueueMax", 5)) or _fleet_size(state) + queue.size() >= hangar
	for id in ships:
		var def: Dictionary = ships[id]
		if not _yard_buttons.has(id):
			var btn := Button.new()
			btn.icon = load(ICONS + "ship_emblem.png")
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			btn.pressed.connect(func(): Net.send({"type": "queue_ship", "planet": _pid(), "slot": _foundry_slot(), "ship": id}))
			_yard_ships.add_child(btn)
			_yard_buttons[id] = btn
		var btn: Button = _yard_buttons[id]
		btn.text = "%s   %s, %d:%02d\nAttack %d   Hull %d   Speed %d" % [def.name, _cost_text(def.cost),
			int(def.seconds) / 60, int(def.seconds) % 60, def.attack, def.hull, def.speed]
		btn.disabled = full or not _can_afford(def.cost)


func _refresh_jobs(state: Dictionary) -> void:
	_post_job.disabled = not Net.has_building("spaceport", _pid()) or not Net.open_job(_pid()).is_empty()
	var lines := []
	for job in state.jobs.filter(func(j): return j.get("planet", "aster") == _pid()):
		lines.append("#%d  %s %d/%d  (%d cr)  %s" % [job.id, job.resource, job.delivered, job.amount, job.reward, job.status])
	_jobs.text = "\n".join(lines) if lines else "No jobs yet. Build a Spaceport, then post one."


func _refresh_raids(state: Dictionary) -> void:
	var lines := []
	var levels: Array = Net.catalog.get("heatLevels", [])
	var live := _my_raids()
	for r in live:
		var left := maxf(0.0, (float(r.endsAt) - Net.now_ms()) / 1000.0)
		lines.append("INTRUDER: %s inside %s\nHeat %d (%s)%s, %d:%02d left" % [r.pilot, r.facility, r.heat,
			levels[int(r.level)].name if levels else "", ", vault open" if r.vaultOpen else "", int(left) / 60, int(left) % 60])
	var history: Array = state.get("raidLog", [])
	for i in range(history.size() - 1, maxi(-1, history.size() - 6), -1):
		var e: Dictionary = history[i]
		var stolen := []
		for id in e.stolen:
			stolen.append("%d %s" % [e.stolen[id], Net.item_name(id)])
		lines.append("%s at %s: %s%s" % [e.pilot, e.facility, e.outcome, (", took " + ", ".join(stolen)) if stolen else ""])
	_raids.text = "\n\n".join(lines) if lines else "No raids yet. Facilities you build can be raided by pilots."

	var incoming := _incoming()
	_banner.visible = not live.is_empty() or not incoming.is_empty()
	_raids_btn.modulate = Color(1, 0.6, 0.55) if not live.is_empty() else Color.WHITE
	if not live.is_empty():
		var r: Dictionary = live[0]
		var left := maxf(0.0, (float(r.endsAt) - Net.now_ms()) / 1000.0)
		_banner.text = "Raid at %s  %d:%02d  Heat %d" % [r.facility, int(left) / 60, int(left) % 60, r.heat]
	elif not incoming.is_empty():
		var a: Dictionary = incoming[0]
		var left := maxf(0.0, (float(a.arriveAt) - Net.now_ms()) / 1000.0)
		_banner.text = "Incoming: %s's fleet reaches %s in %d:%02d" % [a.attacker, a.siteName, int(left) / 60, int(left) % 60]


## New activity-feed entries pop up as toasts. The backlog at connect time is skipped.
func _toast_feed(state: Dictionary) -> void:
	var feed: Array = state.feed
	if _last_feed_at < 0.0:
		_last_feed_at = float(feed[-1].at) if feed else 0.0
		return
	for e in feed:
		if float(e.at) > _last_feed_at:
			toast(e.text)
	if feed:
		_last_feed_at = maxf(_last_feed_at, float(feed[-1].at))


func _on_chat(sender: String, _role: String, text: String) -> void:
	_chat_lines.append("%s: %s" % [sender, text])
	if _chat_lines.size() > 30:
		_chat_lines.pop_front()
	_chat_log.text = "\n".join(_chat_lines)
	if _page != "chat":
		toast("%s: %s" % [sender, text], C_TEAL)
