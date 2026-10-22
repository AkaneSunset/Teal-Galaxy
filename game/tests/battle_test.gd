extends Node
## A whole sector battle as a pilot plays it, from the pilot's chair, against a running DEMO galaxy
## server with fast battles:
##   cd server && SAVE_FILE=/tmp/battle.json DEMO=1 BATTLE_SPEED=20 npm start   (delete /tmp/battle.json first)
##   godot --headless --path game res://tests/battle_test.tscn
## "Battle Tester" joins the Ashen Collective and flies its fleet carrier into Cinder's orbit (the
## Terran Compact holds Cinder; the demo war gives every faction 25% of every system). It presses G
## to leave its seat, walks from the Bridge down the corridor to the Command Deck's holo table and
## presses F there: the Sector Battles screen for Cinder opens, and Attack sector puts it in the RTS
## view. It calls in tanks by drop pod, attack-moves them at the Command Node (A, then a left click
## on it), takes control of one (P) and drives it (D held), gives it back, and keeps the attack
## going (an engineer on the mass points, tanks and artillery called in) until the Command Node
## falls: "Sector taken", the war map shows the sector Ashen, and the view closes by itself, leaving
## the pilot on its feet at the holo table on the Command Deck. The Compact's AI must have fought
## back (fielded units, destroyed some of ours).
## Keys and clicks are sent as input events, as a player's would be.
## Add `-- --shots=/some/dir` and run with a display to save screenshots along the way, and
## `-- --server=ws://127.0.0.1:9000` for a server on another port. Prints PASS or FAIL and quits.

const ExplorerMode := preload("res://explorer.gd")
const Carrier := preload("res://carrier.gd")
const WarInfo := preload("res://war_info.gd")
const Units := preload("res://battle/battle_units.gd")
const PILOT := "Battle Tester"
const FACTION := "ashen"
const PLANET := "cinder"
## From the pilot's chair on the Bridge to the holo table: round the star map table, through the
## Bridge's door, down the corridor and into the Command Deck (carrier.gd's layout, metres).
const TO_HOLO := [Vector3(-3.2, 0, -50.0), Vector3(-3.2, 0, -44.2), Vector3(0, 0, -42.8), Vector3(0, 0, -36.5), Vector3(0, 0, -29.4)]

var _explorer: Node
var _server := "ws://127.0.0.1:8080"
var _shots := ""
var _step := "start"
var _wait := 1.0
var _clock := 0.0
var _step_clock := 0.0
var _done := false
var _path: Array = []
var _menu: Control
var _view: Node
var _sector := ""
var _tanks: Array = []
var _driven := -1
var _drive_from := Vector2.ZERO
var _moved_from := {}
var _end: Dictionary = {}
var _drop_at := 0.0
var _extractors := 0
var _generators := 0 # Power Generators the engineer was told to build
var _bought := 0
var _attacking := false
var _looked := false
var _started_ms := 0.0
var _states := 0
var _enemy_seen := {} # ids of the defender's units (not structures) seen on the field
var _lost := 0 # our units destroyed
var _shots_fired := 0
var _result := ""
var _fight_shot_at := -1.0 # when to take the shot of the fight at the enemy base


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--server="):
			_server = arg.substr(9)
		elif arg.begins_with("--shots="):
			_shots = arg.substr(8)
	get_window().size = Vector2i(1600, 900) # headless too: clicks land on a screen of this size
	Net.connect_to(_server, "explorer", PILOT)
	Net.message.connect(_on_message)
	Net.server_error.connect(func(r): print("server error: ", r))
	_explorer = ExplorerMode.new()
	add_child(_explorer)


func _on_message(msg: Dictionary) -> void:
	match str(msg.get("type", "")):
		"battle_state":
			_states += 1
			_shots_fired += msg.get("shots", []).size()
			if _view and is_instance_valid(_view):
				for row in msg.get("units", []):
					if str(row[2]) != _view.my_side and not (str(row[1]) in ["node", "turret", "extractor", "outpost", "factory"]):
						_enemy_seen[int(row[0])] = true
				for id in msg.get("dead", []):
					var u = _view.units.get(int(id))
					if u and u.mine:
						_lost += 1
		"battle_end":
			_end = msg


func _process(delta: float) -> void:
	_clock += delta
	_step_clock += delta
	if _done:
		return
	if _clock > 480.0:
		_finish(false, "timed out at step " + _step)
		return
	_walk_path()
	_wait -= delta
	if _wait > 0.0 or Net.state.is_empty():
		return
	_steps()


func _go(step: String, wait := 0.0) -> void:
	_step = step
	_wait = wait
	_step_clock = 0.0
	print("step: ", step)


func _steps() -> void:
	match _step:
		"start":
			if Net.catalog.get("carrier", false) != true:
				_finish(false, "the server isn't in demo mode (no carrier in the catalog): start it with DEMO=1")
				return
			if not _explorer._stations.has(PLANET):
				return
			Net.send({"type": "choose_faction", "faction": FACTION})
			_go("faction")
		"faction":
			if WarInfo.my_faction() != FACTION:
				if _step_clock > 8.0:
					_finish(false, "never joined the Ashen Collective")
				return
			if _explorer._panel_open():
				_explorer._close_panel()
			# In Cinder's orbit, 8 km out from Cinder Orbital, nose toward it.
			var st: Array = _explorer._stations[PLANET].pos
			_explorer.teleport(_explorer.System.offset(st, Vector3(1500, 900, 8000)))
			_explorer.flight.basis = Basis.looking_at(Vector3(-1500, -900, -8000).normalized(), Vector3.UP)
			_go("in orbit", 1.5)
		"in orbit":
			if not _explorer._carrier or _explorer._over_planet() != PLANET:
				_finish(false, "the carrier should be over Cinder (over '%s', carrier %s)" % [_explorer._over_planet(), _explorer._carrier])
				return
			_key(KEY_G) # Leave seat
			_go("bridge", 1.0)
		"bridge":
			var c = _explorer._station
			if not (c is Carrier) or c.seated or c._location() != "Bridge":
				_finish(false, "G should put the pilot on their feet on the carrier's Bridge (%s)" % [c._location() if c is Carrier else str(c)])
				return
			if _explorer._space_id != "ship:" + PILOT:
				_finish(false, "aboard, the pilot should be in their carrier's space, not '%s'" % _explorer._space_id)
				return
			_path = TO_HOLO.duplicate()
			_go("walking")
		"walking":
			var c = _explorer._station
			if not _path.is_empty():
				if _step_clock > 40.0:
					_finish(false, "couldn't walk to the holo table: stuck at %s in the %s" % [c._player.global_position, c._location()])
				return
			c._player.rotation.y = PI # facing the table, toward the stern
			c._pitch = 0.12
			c._camera.rotation.x = c._pitch
			_go("at the table", 0.5)
		"at the table":
			var c = _explorer._station
			if c._location() != "Command Deck" or not c._prompt.text.contains("Sector Battles on Cinder"):
				_finish(false, "at the holo table the prompt should offer Sector Battles on Cinder: '%s' (%s)" % [c._prompt.text, c._location()])
				return
			_shot("08-command-deck-at-the-holo-table")
			_action("interact") # F
			_go("menu", 0.8)
		"menu":
			_menu = _find_menu()
			if _menu == null:
				_finish(false, "F at the holo table should open the Sector Battles screen")
				return
			_sector = str(_menu._selected)
			if _sector == "" or not _menu._attack.visible or _menu._attack.disabled:
				_finish(false, "the Sector Battles screen should offer an attack on a sector of Cinder: '%s' (%s)" % [_sector, _menu._status.text])
				return
			_shot("09-sector-battles-cinder")
			_menu._attack.pressed.emit()
			_go("joining")
		"joining":
			for c in get_tree().root.get_children():
				if c is BattleView and not c.is_queued_for_deletion():
					_view = c
			if _view == null or _view.units.is_empty():
				if _step_clock > 8.0:
					_finish(false, "no battle after Attack sector (%s)" % (_menu._status.text if is_instance_valid(_menu) else "menu closed"))
				return
			_centre_mouse()
			if _shown(_explorer._station):
				_finish(false, "the carrier should be hidden while the RTS view is up")
				return
			if _find("node") == null:
				_finish(false, "the defenders should have a Command Node")
				return
			_started_ms = Net.now_ms()
			print("battle %s on %s, mass %d, %d units, sim rate %.1f" % [_view.battle_id, _view.info.sectorName, int(_view.mass), _view.units.size(), _view.sim_rate])
			_view.call_in("tank", 3)
			_go("drop")
		"drop":
			_tanks = _mine("tank")
			if _tanks.size() < 3:
				if _step_clock > 6.0:
					_finish(false, "3 tanks should be called in (mass %d)" % int(_view.mass))
				return
			if _tanks.any(func(u): return u.dropping()):
				return
			var mid := Vector2.ZERO
			for u in _tanks:
				mid += u.to / _tanks.size()
			_view.look_at_ground(mid)
			_view._dist_to = 45.0
			_go("close zoom", 1.5)
		"close zoom":
			_shot("10-rts-close-zoom")
			_go("frame the attack", 0.5) # the camera moves on only after the shot is taken
		"frame the attack":
			# Attack-move on the Command Node: select the tanks, A, then a left click on the node.
			_view.select(_tanks.map(func(u): return u.id))
			for u in _tanks:
				_moved_from[u.id] = u.to
			_view._dist_to = 420.0
			_view.look_at_ground(_find("node").to)
			_go("aim", 1.5)
		"aim":
			_key(KEY_A)
			_go("click", 0.1)
		"click":
			if _view.armed != "amove":
				_finish(false, "A (tapped) with tanks selected should arm an attack-move")
				return
			var node: Units.Unit = _find("node")
			var screen: Vector2 = _view.camera.unproject_position(node.pos + Vector3(30, 0, 30 if _view.my_side == "a" else -30))
			_click(screen)
			_centre_mouse()
			_go("moving", 2.0)
		"moving":
			var moved := 0
			for u in _tanks:
				if _view.units.has(u.id) and u.to.distance_to(_moved_from[u.id]) > 3.0 and u.state != "idle":
					moved += 1
			if moved < 3:
				if _step_clock > 6.0:
					_finish(false, "the tanks should move on the attack-move: %d of 3 did (armed '%s', states %s)" % [moved, _view.armed, _tanks.map(func(u): return u.state)])
				return
			# Take control of the first tank (P) and drive it with D held.
			var t: Units.Unit = _tanks[0]
			_view.select([t.id])
			_key(KEY_P)
			_driven = t.id
			_drive_from = t.to
			_go("drive", 0.6)
		"drive":
			if not _view.driving():
				_finish(false, "P with one tank selected should take control of it")
				return
			_hold(KEY_D, true)
			_drive_from = _view.units[_driven].to
			_go("driving", 2.5)
		"driving":
			var t: Units.Unit = _view.units.get(_driven)
			if t == null:
				_hold(KEY_D, false)
				_finish(false, "the driven tank died before it could be checked")
				return
			if t.state != "driven":
				_hold(KEY_D, false)
				_finish(false, "the tank should be driven (state %s)" % t.state)
				return
			if t.to.distance_to(_drive_from) < 4.0:
				if _step_clock < 4.0:
					return
				_hold(KEY_D, false)
				_finish(false, "holding D should drive the tank: moved %.1f m" % t.to.distance_to(_drive_from))
				return
			_shot("11-rts-taking-control-of-a-tank")
			_go("release", 0.4)
		"release":
			_hold(KEY_D, false)
			_key(KEY_P) # back to command
			_go("released", 1.0)
		"released":
			if _view.driving():
				_finish(false, "P again should give the tank back")
				return
			if _view.units.has(_driven):
				_view.order_units([_driven], "amove", _find("node").to, true)
			_view.call_in("engineer", 1)
			_view._dist_to = 1900.0
			_view.look_at_ground(Vector2(800, 800))
			_go("strategic", 2.0)
		"strategic":
			if not _view.strategic():
				return
			_shot("12-rts-strategic-zoom")
			_go("fight")
		"fight":
			_fight()
		"ended":
			_check_end()
		"home":
			_check_home()
		"war open":
			_explorer._open_war(PLANET)
			_go("war terminal", 0.6)
		"war terminal":
			# The War terminal's sector view also opens Sector Battles, and closing it leaves you walking.
			if not _explorer._war_panel.visible or not _explorer._war_panel._battles.visible:
				_finish(false, "the War terminal should offer Sector Battles for Cinder")
				return
			_explorer._war_panel._battles.pressed.emit()
			_go("war battles", 0.6)
		"war battles":
			var menu := _find_menu()
			if menu == null or menu.planet_id != PLANET or _explorer._war_panel.visible:
				_finish(false, "Sector Battles on the War terminal should open that screen for Cinder")
				return
			menu._close()
			_go("war closed", 0.6)
		"war closed":
			var c = _explorer._station
			if _find_menu() != null or c.menu_open or not c._walking():
				_finish(false, "closing Sector Battles should leave the pilot walking on the Command Deck")
				return
			_finish(true, _result)


## Keeps the attack going until the battle ends, as a player would against a dug-in base: the
## engineer takes the mass points near the landing zone, a Power Generator by the landing zone after
## each (units cost energy too), the mass and energy go on tanks and artillery
## gathered at the landing zone, and once the army is big enough (or nearly half the time is gone)
## it attack-moves on the Command Node as one, reinforcements following in groups.
func _fight() -> void:
	if not _end.is_empty():
		_check_end()
		return
	if _step_clock > 330.0:
		_finish(false, "the Command Node should fall in time (%d snapshots)" % _states)
		return
	if _clock - _drop_at < 0.5:
		return
	_drop_at = _clock
	var engineers := _mine("engineer").filter(func(u): return not u.dropping())
	# Every extractor needs five generators' worth of energy, and units need energy too: the generators go first.
	if not engineers.is_empty() and engineers[0].orders.is_empty() and _extractors < 5 and _generators >= 5 * _extractors + 2:
		var e: Units.Unit = engineers[0]
		var best = null
		for p in _view.mass_points:
			if _view._point_free(p) and (best == null or Vector2(p.x, p.z).distance_to(e.to) < Vector2(best.x, best.z).distance_to(e.to)):
				best = p
		if best and Vector2(best.x, best.z).distance_to(e.to) < 700.0:
			_view.order_units([e.id], "build", Vector2(best.x, best.z), false, -1, "extractor")
			_extractors += 1
	elif not engineers.is_empty() and engineers[0].orders.is_empty() and _generators < 5 * 5 + 10:
		# A row of generators behind the landing zone, on the side away from the enemy.
		var lz: Dictionary = _view.info.get("lz", {"x": 800, "z": 170})
		var back := -1.0 if float(lz.z) < 800.0 else 1.0
		# In rows either side of the landing zone (behind it can be the edge of the map).
		var side := 1.0 if _generators % 2 == 0 else -1.0
		var spot := Vector2(float(lz.x) + side * (150.0 + 28.0 * ((_generators / 2) % 6)), float(lz.z) - back * 28.0 * (_generators / 12))
		if _view._site("generator", spot) != null:
			_view.order_units([engineers[0].id], "build", spot, false, -1, "generator")
		_generators += 1
	var node: Units.Unit = _find("node")
	if node == null:
		return
	if _view.my_unit_count() < 110:
		var kind := "artillery" if _bought % 2 == 1 else "tank"
		var cost := float(_view.catalog[kind].cost)
		var energy := float(_view.catalog[kind].energy)
		if _view.mass >= cost and _view.energy >= energy:
			_view.call_in(kind, clampi(mini(int(_view.mass / cost), int(_view.energy / energy)), 1, 10))
			_bought += 1
	var army := 0.0
	var idle := []
	for u: Units.Unit in _view.units.values():
		if u.mine and u.kind != "structure" and u.type != "engineer" and u.type != "acu" and not u.dropping(): # the ACU stays home: losing it loses the battle
			army += float(_view.catalog[u.type].cost)
			if u.state == "idle":
				idle.append(u.id)
	var left := (float(_view.ends_at) - Net.now_ms()) / maxf(float(_view.ends_at) - _started_ms, 1.0)
	if not _attacking and (army >= 1800.0 or left < 0.55):
		_attacking = true
		print("attacking with an army worth %d mass" % int(army))
	if _attacking and idle.size() >= 4:
		_view.order_units(idle, "amove", node.to)
	if int(_step_clock * 2.0) % 30 == 0:
		print("t %.0f: mass %d, energy %d (+%d/s), %d of mine (worth %d), node hp %d, enemy units seen %d, ours lost %d" % [_step_clock, int(_view.mass), int(_view.energy), int(_view.energy_income), _view.my_unit_count(), int(army), int(node.hp), _enemy_seen.size(), _lost])
	if _attacking and not _looked:
		_looked = true
		_view._dist_to = 260.0
		_view.look_at_ground(node.to - Vector2(0, 160) * (1.0 if _view.my_side == "a" else -1.0))
	# Once the front reaches the enemy base, a closer look at the fight.
	if _attacking and _fight_shot_at < 0.0:
		var front: Units.Unit = null
		for u: Units.Unit in _view.units.values():
			if u.mine and u.kind != "structure" and (front == null or u.to.distance_to(node.to) < front.to.distance_to(node.to)):
				front = u
		if front and front.to.distance_to(node.to) < 230.0:
			_view.look_at_ground(front.to.lerp(node.to, 0.35))
			_view._dist_to = 130.0
			_fight_shot_at = _clock + 2.0
	elif _fight_shot_at > 0.0 and _clock > _fight_shot_at:
		_fight_shot_at = INF
		_shot("13-rts-the-fight")


func _check_end() -> void:
	if str(_end.get("side", "")) != "a":
		_finish(false, "the battle should end with the sector taken: " + str(_end))
		return
	if _step != "ended":
		_go("ended")
		_shot_later("14-rts-battle-end", 1.0)
	var wp := WarInfo.planet(PLANET)
	var sec: Array = wp.sectors.filter(func(s): return s.id == _sector)
	if str(sec[0].get("owner", "")) != FACTION:
		if _step_clock > 5.0:
			_finish(false, "the war map should show %s taken by the Ashen Collective" % _sector)
		return
	if BattleView.active or is_instance_valid(_view):
		if _step_clock > 10.0:
			_finish(false, "the battle view should close by itself after the banner")
		return
	_go("home", 1.0)


## Back from the battle: on your feet on the Command Deck, at the holo table, seeing and walking.
func _check_home() -> void:
	var c = _explorer._station
	if not (c is Carrier) or c.seated or c.menu_open or c._location() != "Command Deck":
		_finish(false, "after the battle the pilot should stand on the carrier's Command Deck (%s)" % [c._location() if c is Carrier else str(c)])
		return
	if not c._camera.current or not _shown(c):
		_finish(false, "the carrier's interior should be back on screen")
		return
	if _enemy_seen.size() < 4 or _lost < 1:
		_finish(false, "the defender's AI should fight back: it fielded %d units and destroyed %d of ours" % [_enemy_seen.size(), _lost])
		return
	_shot("15-back-at-the-holo-table")
	_result = "left the seat, walked to the holo table, attacked %s, dropped tanks, attack-moved, drove a tank, took the sector (%s); the AI fielded %d units and destroyed %d of ours; %d shots, %d snapshots; back on the Command Deck" % [
		_sector, _end.get("text", ""), _enemy_seen.size(), _lost, _shots_fired, _states] + "; the War terminal opens Sector Battles too"
	_go("war open", 1.0)


# --- Input, as a player's ------------------------------------------------------------------

## Walks the pilot along `_path` with the forward key held, turning toward each point.
func _walk_path() -> void:
	if _path.is_empty():
		return
	var c = _explorer._station
	if not (c is Carrier):
		return
	var p: Vector3 = c._player.global_position
	var to: Vector3 = _path[0]
	var d := Vector2(to.x - p.x, to.z - p.z)
	if d.length() < 0.5:
		_path.pop_front()
		if _path.is_empty():
			Input.action_release("foot_forward")
		return
	c._player.rotation.y = atan2(-d.x, -d.y)
	Input.action_press("foot_forward")


## A key tapped: down and up together (a tap, not a hold: A held pans the RTS camera, and a frame
## of software rendering can last longer than a tap).
func _key(code: Key) -> void:
	_hold(code, true)
	_hold(code, false)


func _hold(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = down
	Input.parse_input_event(e)


func _action(name: String) -> void:
	var e := InputEventAction.new()
	e.action = name
	e.pressed = true
	Input.parse_input_event(e)
	await get_tree().process_frame
	var up := InputEventAction.new()
	up.action = name
	up.pressed = false
	Input.parse_input_event(up)


## The mouse to the middle of the window (xvfb leaves it in a corner, where it would pan the RTS
## camera as a player's pointer at the screen's edge does).
func _centre_mouse() -> void:
	if DisplayServer.get_name() != "headless":
		Input.warp_mouse(get_viewport().get_visible_rect().size / 2.0)


func _click(at: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.position = at
	e.global_position = at
	e.pressed = true
	Input.parse_input_event(e)
	await get_tree().process_frame
	var up := e.duplicate()
	up.pressed = false
	Input.parse_input_event(up)


# --- Helpers ---------------------------------------------------------------------------------

## Whether a place's own rooms are on screen (place.gd hides them while the RTS view is up).
func _shown(place: Node) -> bool:
	for n in place._own:
		if is_instance_valid(n) and n is Node3D:
			return n.visible
	return true


func _find_menu() -> Control:
	for n in get_tree().root.find_children("*", "Control", true, false):
		if n is BattleMenu and not n.is_queued_for_deletion():
			return n
	return null


func _find(type: String) -> Units.Unit:
	for u: Units.Unit in _view.units.values():
		if u.type == type:
			return u
	return null


func _mine(type: String) -> Array:
	var out := []
	for u: Units.Unit in _view.units.values():
		if u.mine and u.type == type:
			out.append(u)
	return out


func _shot_later(name: String, after: float) -> void:
	await get_tree().create_timer(after).timeout
	_shot(name)


func _shot(name: String) -> void:
	if _shots == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_shots, name])
	print("saved ", name)


func _finish(ok: bool, what: String) -> void:
	if _done:
		return # the first result stands
	_done = true
	Input.action_release("foot_forward")
	print(("PASS " if ok else "FAIL ") + "battle: " + what)
	get_tree().quit(0 if ok else 1)
