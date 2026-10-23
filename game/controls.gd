extends Node
## Pilot controls: mouse and keyboard, gamepad, and HOTAS (any joystick, via rebinding).
## Every scheme reaches the same actions. Bindings and settings save to user://controls.cfg.
##
## The mouse works as a virtual joystick: move it away from the centre to turn, and the
## further out it is, the faster the ship turns. Small movements give small, precise turns.

const SAVE_PATH := "user://controls.cfg"
const STICK_DEADZONE := 0.08
const MOUSE_DEADZONE := 0.04
const RESPONSE_CURVE := 1.7 # >1 makes small deflections gentler, for precise flying

const HUD_COLOURS := [
	["Teal", Color(0.35, 0.95, 0.88)],
	["Amber", Color(1.0, 0.68, 0.2)],
	["Green", Color(0.5, 1.0, 0.45)],
	["White", Color(0.92, 0.95, 1.0)],
	["Blue", Color(0.45, 0.7, 1.0)],
]

# action, label, keyboard/mouse default, gamepad default (null: none until the player binds one).
# Keyboard: [physical key] or ["mouse", button]. Gamepad: ["button", index] or ["axis", axis, direction].
const ACTIONS := [
	["throttle_up", "Throttle up", [KEY_W], ["axis", JOY_AXIS_TRIGGER_RIGHT, 1]],
	["throttle_down", "Throttle down / reverse", [KEY_S], ["axis", JOY_AXIS_TRIGGER_LEFT, 1]],
	["stop", "All stop", [KEY_X], ["button", JOY_BUTTON_LEFT_STICK]],
	["pitch_up", "Pitch up (nose up)", [KEY_DOWN], ["axis", JOY_AXIS_RIGHT_Y, 1]],
	["pitch_down", "Pitch down (nose down)", [KEY_UP], ["axis", JOY_AXIS_RIGHT_Y, -1]],
	["yaw_left", "Yaw left", [KEY_LEFT], ["axis", JOY_AXIS_RIGHT_X, -1]],
	["yaw_right", "Yaw right", [KEY_RIGHT], ["axis", JOY_AXIS_RIGHT_X, 1]],
	["roll_left", "Roll left", [KEY_Q], ["button", JOY_BUTTON_LEFT_SHOULDER]],
	["roll_right", "Roll right", [KEY_E], ["button", JOY_BUTTON_RIGHT_SHOULDER]],
	["strafe_left", "Strafe left", [KEY_A], ["axis", JOY_AXIS_LEFT_X, -1]],
	["strafe_right", "Strafe right", [KEY_D], ["axis", JOY_AXIS_LEFT_X, 1]],
	["lift_up", "Thrust up", [KEY_SPACE], ["axis", JOY_AXIS_LEFT_Y, -1]],
	["lift_down", "Thrust down", [KEY_CTRL], ["axis", JOY_AXIS_LEFT_Y, 1]],
	["boost", "Boost", [KEY_SHIFT], ["button", JOY_BUTTON_B]],
	["phase", "Phase-shift drive", [KEY_J], ["button", JOY_BUTTON_Y]],
	["drift", "Drift (flight assist off)", [KEY_Z], ["button", JOY_BUTTON_X]],
	["interact", "Mine / deliver / board / use", [KEY_F], ["button", JOY_BUTTON_A]],
	["pip_sys", "Power to systems", [KEY_1], ["button", JOY_BUTTON_DPAD_LEFT]],
	["pip_eng", "Power to engines", [KEY_2], ["button", JOY_BUTTON_DPAD_UP]],
	["pip_wep", "Power to weapons", [KEY_3], ["button", JOY_BUTTON_DPAD_RIGHT]],
	["pip_reset", "Balance power", [KEY_4], ["button", JOY_BUTTON_DPAD_DOWN]],
	["nav_map", "Navigation map", [KEY_M], ["button", JOY_BUTTON_BACK]],
	["chat", "Chat", [KEY_ENTER], ["button", JOY_BUTTON_GUIDE]],
	["menu", "Settings", [KEY_ESCAPE], ["button", JOY_BUTTON_START]],
	# A fleet carrier (the demo's ship) is walkable: leave the pilot's chair and walk around it.
	["leave_seat", "Leave seat (walk your carrier)", [KEY_G], ["button", JOY_BUTTON_RIGHT_STICK]],
	["outside_view", "Outside view (carrier)", [KEY_V], null],
	# Space Battles: a starfighter's weapons.
	["ship_fire", "Space Battles: fire lasers", ["mouse", MOUSE_BUTTON_LEFT], null],
	["ship_secondary", "Space Battles: missile / torpedo", ["mouse", MOUSE_BUTTON_RIGHT], null],
	["ship_target", "Space Battles: target ahead", [KEY_T], null],
	# On foot, inside a facility.
	["foot_forward", "On foot: forward", [KEY_W], ["axis", JOY_AXIS_LEFT_Y, -1]],
	["foot_back", "On foot: back", [KEY_S], ["axis", JOY_AXIS_LEFT_Y, 1]],
	["foot_left", "On foot: step left", [KEY_A], ["axis", JOY_AXIS_LEFT_X, -1]],
	["foot_right", "On foot: step right", [KEY_D], ["axis", JOY_AXIS_LEFT_X, 1]],
	["foot_look_left", "On foot: look left", [KEY_LEFT], ["axis", JOY_AXIS_RIGHT_X, -1]],
	["foot_look_right", "On foot: look right", [KEY_RIGHT], ["axis", JOY_AXIS_RIGHT_X, 1]],
	["foot_look_up", "On foot: look up", [KEY_UP], ["axis", JOY_AXIS_RIGHT_Y, -1]],
	["foot_look_down", "On foot: look down", [KEY_DOWN], ["axis", JOY_AXIS_RIGHT_Y, 1]],
	["foot_sprint", "On foot: sprint", [KEY_SHIFT], ["button", JOY_BUTTON_LEFT_STICK]],
	["foot_crouch", "On foot: crouch (quiet)", [KEY_C], ["button", JOY_BUTTON_B]],
	["foot_jump", "On foot: jump", [KEY_SPACE], ["button", JOY_BUTTON_Y]],
	["foot_fire", "On foot: fire", ["mouse", MOUSE_BUTTON_LEFT], ["axis", JOY_AXIS_TRIGGER_RIGHT, 1]],
	["foot_aim", "On foot: aim down sights", ["mouse", MOUSE_BUTTON_RIGHT], ["axis", JOY_AXIS_TRIGGER_LEFT, 1]],
	["foot_reload", "On foot: reload", [KEY_R], ["button", JOY_BUTTON_X]],
	["foot_heal", "On foot: heal (tap: best item, hold: wheel)", [KEY_H], ["button", JOY_BUTTON_DPAD_UP]],
	# Weapons share 1, 2 and the D-pad with ship power: those only act on foot, the power keys only in flight.
	["foot_weapon_1", "On foot: rifle", [KEY_1], null],
	["foot_weapon_2", "On foot: grenade launcher", [KEY_2], null],
	["foot_weapon_next", "On foot: switch weapon", ["mouse", MOUSE_BUTTON_WHEEL_DOWN], ["button", JOY_BUTTON_DPAD_RIGHT]],
	["foot_weapon_prev", "On foot: switch weapon (back)", ["mouse", MOUSE_BUTTON_WHEEL_UP], null],
	["foot_inventory", "On foot: inventory", [KEY_TAB], ["button", JOY_BUTTON_BACK]],
]

# Names on a standard gamepad. A HOTAS shows up as its own buttons and axes, named by number past these.
const PAD_BUTTONS := ["A", "B", "X", "Y", "Back", "Guide", "Start", "Left stick click", "Right stick click",
	"LB", "RB", "D-pad up", "D-pad down", "D-pad left", "D-pad right"]
const PAD_AXES := [["Left stick left", "Left stick right"], ["Left stick up", "Left stick down"],
	["Right stick left", "Right stick right"], ["Right stick up", "Right stick down"], ["LT", "LT"], ["RT", "RT"]]

var drift_default := false
var drift_hold := false # drift only while the drift control is held, instead of toggling
var invert_mouse := false
var mouse_sensitivity := 1.0
var hud_colour := 0
var enabled := true # off while typing in chat or using a menu

var _mouse := Vector2.ZERO # virtual joystick, -1..1 on each axis


func _ready() -> void:
	_install_defaults()
	load_settings()


func _install_defaults() -> void:
	for a in ACTIONS:
		var action: String = a[0]
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action, 0.2)
		for spec in [a[2], a[3]]:
			if spec != null:
				InputMap.action_add_event(action, _make_event(spec))


func reset_to_defaults() -> void:
	_install_defaults()
	save_settings()


func hud_color() -> Color:
	return HUD_COLOURS[hud_colour][1]


func mouse_stick() -> Vector2:
	return _mouse


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and enabled:
		var rel: Vector2 = event.relative * mouse_sensitivity / 350.0
		if invert_mouse:
			rel.y = -rel.y
		_mouse = (_mouse + rel).limit_length(1.0)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_MIDDLE:
		_mouse = Vector2.ZERO # re-centre


func release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_mouse = Vector2.ZERO


func capture_mouse() -> void:
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## What the pilot is asking for this frame.
func read() -> Dictionary:
	if not enabled:
		return {}
	var m := Vector2(_shape(_mouse.x, MOUSE_DEADZONE), _shape(_mouse.y, MOUSE_DEADZONE))
	return {
		"pitch": clampf(_axis("pitch_down", "pitch_up") - m.y, -1.0, 1.0),
		"yaw": clampf(_axis("yaw_right", "yaw_left") - m.x, -1.0, 1.0),
		"roll": _axis("roll_left", "roll_right"),
		"strafe": _axis("strafe_left", "strafe_right"),
		"lift": _axis("lift_down", "lift_up"),
		"throttle_rate": _axis("throttle_down", "throttle_up") * 0.8,
		"boost": Input.is_action_just_pressed("boost"),
		"stop": Input.is_action_just_pressed("stop"),
		"phase": Input.is_action_just_pressed("phase"),
	}


func _axis(negative: String, positive: String) -> float:
	var v := Input.get_action_raw_strength(positive) - Input.get_action_raw_strength(negative)
	return _shape(v, STICK_DEADZONE)


func _shape(v: float, deadzone: float) -> float:
	var a := absf(v)
	if a < deadzone:
		return 0.0
	return signf(v) * pow((a - deadzone) / (1.0 - deadzone), RESPONSE_CURVE)


# --- Bindings ------------------------------------------------------------------

func _make_event(spec: Array) -> InputEvent:
	match spec[0]:
		"button":
			var b := InputEventJoypadButton.new()
			b.button_index = spec[1]
			return b
		"axis":
			var m := InputEventJoypadMotion.new()
			m.axis = spec[1]
			m.axis_value = spec[2]
			return m
		"mouse":
			var mb := InputEventMouseButton.new()
			mb.button_index = spec[1]
			return mb
	var k := InputEventKey.new()
	k.physical_keycode = spec[0]
	return k


static func is_pad_event(e: InputEvent) -> bool:
	return e is InputEventJoypadButton or e is InputEventJoypadMotion


## The binding for an action on one kind of device, as text.
func binding_text(action: String, pad: bool) -> String:
	for e in InputMap.action_get_events(action):
		if is_pad_event(e) == pad:
			return describe(e)
	return "-"


static func describe(e: InputEvent) -> String:
	if e is InputEventKey:
		return OS.get_keycode_string(e.physical_keycode)
	if e is InputEventMouseButton:
		var wheel := {MOUSE_BUTTON_WHEEL_UP: "Wheel up", MOUSE_BUTTON_WHEEL_DOWN: "Wheel down"}
		return wheel.get(e.button_index, "Mouse %d" % e.button_index)
	if e is InputEventJoypadButton:
		return PAD_BUTTONS[e.button_index] if e.button_index < PAD_BUTTONS.size() else "Button %d" % e.button_index
	if e is InputEventJoypadMotion:
		var names: Array = PAD_AXES[e.axis] if e.axis < PAD_AXES.size() else ["Axis %d-" % e.axis, "Axis %d+" % e.axis]
		return names[1] if e.axis_value > 0 else names[0]
	return "?"


## Binds `event` to `action`, replacing the old binding on that kind of device.
func rebind(action: String, event: InputEvent) -> void:
	var pad := is_pad_event(event)
	for e in InputMap.action_get_events(action):
		if is_pad_event(e) == pad:
			InputMap.action_erase_event(action, e)
	var clean: InputEvent
	if event is InputEventKey:
		clean = _make_event([event.physical_keycode])
	elif event is InputEventMouseButton:
		clean = _make_event(["mouse", event.button_index])
	elif event is InputEventJoypadButton:
		clean = _make_event(["button", event.button_index])
	elif event is InputEventJoypadMotion:
		clean = _make_event(["axis", event.axis, 1 if event.axis_value > 0 else -1])
	if clean:
		InputMap.action_add_event(action, clean)
	save_settings()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("settings", "drift_default", drift_default)
	cfg.set_value("settings", "drift_hold", drift_hold)
	cfg.set_value("settings", "invert_mouse", invert_mouse)
	cfg.set_value("settings", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("settings", "hud_colour", hud_colour)
	cfg.set_value("settings", "admin_keys", Net.admin_keys) # Net reads them back itself
	for a in ACTIONS:
		var specs := []
		for e in InputMap.action_get_events(a[0]):
			specs.append(_spec(e))
		cfg.set_value("bindings", a[0], specs)
	cfg.save(SAVE_PATH)


## Saves the admin keys (Net.admin_keys: server -> key) and leaves the rest of the settings file as
## it is. Net calls it when a key is typed, on the start screen and the phone too, where there are
## no controls to save.
static func save_admin_keys(keys: Dictionary) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH) # no file yet is fine: it starts empty
	cfg.set_value("settings", "admin_keys", keys)
	cfg.save(SAVE_PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	drift_default = cfg.get_value("settings", "drift_default", drift_default)
	drift_hold = cfg.get_value("settings", "drift_hold", drift_hold)
	invert_mouse = cfg.get_value("settings", "invert_mouse", invert_mouse)
	mouse_sensitivity = cfg.get_value("settings", "mouse_sensitivity", mouse_sensitivity)
	hud_colour = clampi(cfg.get_value("settings", "hud_colour", hud_colour), 0, HUD_COLOURS.size() - 1)
	for a in ACTIONS:
		var specs: Array = cfg.get_value("bindings", a[0], [])
		if specs.is_empty():
			continue
		InputMap.action_erase_events(a[0])
		for spec in specs:
			InputMap.action_add_event(a[0], _make_event(spec))


func _spec(e: InputEvent) -> Array:
	if e is InputEventJoypadButton:
		return ["button", e.button_index]
	if e is InputEventJoypadMotion:
		return ["axis", e.axis, 1 if e.axis_value > 0 else -1]
	if e is InputEventMouseButton:
		return ["mouse", e.button_index]
	return [e.physical_keycode]
