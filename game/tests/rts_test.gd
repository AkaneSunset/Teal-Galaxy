extends Node
## Sector battles and the RTS view, against a running DEMO galaxy server with fast battles:
##   cd server && SAVE_FILE=/tmp/rts.json DEMO=1 BATTLE_SPEED=10 npm start   (delete /tmp/rts.json first)
##   godot --headless --path game res://tests/rts_test.tscn
## The pilot "RTS Tester" (Terran Compact) goes aboard its own carrier (ship:RTS Tester), says it
## is over Scar (a contested world of Marrow Reach that nobody holds: a militia defends it), opens
## the Sector Battles screen for Scar and attacks a sector. In the RTS view it calls in tanks by
## drop pod, attack-moves them at the Command Node, takes control of one and drives it, checks the
## snapshots move the units, leaves the battle and joins it again from the Sector Battles screen
## (its units and mass still there), and keeps calling in units (an engineer takes mass points,
## builds a factory, then Power Generators) until the Command Node falls. Meanwhile, through the HUD,
## it upgrades the factory to tier 2 and has it make a Tank Mk II: the battle ends with the sector taken and the war map shows it
## the Compact's. Then the view closes by itself.
## Add `-- --shots=/some/dir` and run with a display to save screenshots along the way, and
## `-- --server=ws://127.0.0.1:9000` for a server on another port. Prints PASS or FAIL and quits.

const PILOT := "RTS Tester"
const PLANET := "scar"
const Units := preload("res://battle/battle_units.gd")

var _server := "ws://127.0.0.1:8080"
var _shots := ""
var _step := "perf"
var _wait := 0.5
var _clock := 0.0
var _step_clock := 0.0
var _done := false
var _joined_space := false
var _menu: Control
var _view: Node
var _sector := ""
var _tanks: Array = []
var _driven := -1
var _drive_from := Vector2.ZERO
var _moved_from := {} # id -> where it was when the attack-move went out
var _end: Dictionary = {}
var _drop_at := 0.0
var _extractors := 0
var _generators := 0 # Power Generators the engineer was told to build
var _factory_stage := 0 # 0 none yet, 1 being built, 2 upgrading to tier 2, 3 making a Tank Mk II, 4 done
var _factory := -1
var _bought := 0
var _attacking := false
var _looked := false
var _started_ms := 0.0
var _frames := 0
var _slowest := 0.0
var _states := 0
var _mass_left := 0.0
var _perf_view: Node
var _perf_frames := 0
## The battle view's own work a frame with PERF_UNITS units on the field must stay under this.
const PERF_UNITS := 360
const PERF_BUDGET_MS := 12.0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--server="):
			_server = arg.substr(9)
		elif arg.begins_with("--shots="):
			_shots = arg.substr(8)
	if DisplayServer.get_name() != "headless":
		get_window().size = Vector2i(1600, 900)
	Net.connect_to(_server, "explorer", PILOT)
	Net.message.connect(_on_message)
	Net.server_error.connect(func(r): print("server error: ", r))
	# Something to look at behind the menu, as the carrier's Command Deck would be.
	var cam := Camera3D.new()
	add_child(cam)


func _on_message(msg: Dictionary) -> void:
	match str(msg.get("type", "")):
		"space_joined":
			_joined_space = str(msg.get("space", "")) == "ship:" + PILOT
		"battle_state":
			_states += 1
		"battle_end":
			_end = msg


func _process(delta: float) -> void:
	_clock += delta
	_step_clock += delta
	if _view and is_instance_valid(_view):
		_frames += 1
		if _frames > 30:
			_slowest = maxf(_slowest, delta)
	if _done:
		return
	if _clock > 420.0:
		_finish(false, "timed out at step " + _step)
		return
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
		"perf":
			_perf()
		"start":
			if Net.catalog.get("carrier", false) != true:
				_finish(false, "the server isn't in demo mode (no carrier in the catalog): start it with DEMO=1")
				return
			Net.send({"type": "choose_faction", "faction": "compact"})
			Net.send({"type": "enter_space", "space": "ship:" + PILOT})
			_go("aboard")
		"aboard":
			if not _joined_space or str(Net.state.get("pilots", {}).get(PILOT, {}).get("faction", "")) != "compact":
				if _step_clock > 10.0:
					_finish(false, "never got aboard ship:%s as a Compact pilot" % PILOT)
				return
			# In orbit over Scar: the carrier's position is relayed with `over`.
			Net.send({"type": "ship", "pos": [0.0, 0.0, 0.0], "rot": [0.0, 0.0, 0.0], "over": PLANET})
			_go("menu", 0.5)
		"menu":
			if not ResourceLoader.exists("res://battle/battle_menu.gd"):
				_finish(false, "no Sector Battles screen")
				return
			_menu = BattleMenu.open(self, PLANET)
			_go("menu open", 1.0)
		"menu open":
			var wp: Dictionary = Net.state.war.planets.filter(func(p): return p.id == PLANET)[0]
			_sector = str(_menu._selected)
			if _sector == "" or BattleMenu.problem("compact", wp, wp.sectors.filter(func(s): return s.id == _sector)[0]) != "":
				_finish(false, "the Sector Battles screen should pick a sector the Compact can attack on Scar (demo war): got '%s'" % _sector)
				return
			if not _menu._attack.visible or _menu._attack.disabled:
				_finish(false, "Attack sector should be on for " + _sector)
				return
			_shot("rts-01-sector-battles-screen")
			_go("attack", 0.5)
		"attack":
			_menu._attack.pressed.emit()
			_go("joining")
		"joining":
			if not BattleView.active or not load("res://battle/battle_view.gd").get("active"):
				if _step_clock > 8.0:
					_finish(false, "no battle_joined after Attack sector (status: %s)" % _menu._status.text if is_instance_valid(_menu) else "no battle view")
				return
			for c in get_tree().root.get_children():
				if c is BattleView:
					_view = c
			if _view == null:
				return
			_go("first state", 0.5)
		"first state":
			if is_instance_valid(_menu):
				_finish(false, "the Sector Battles screen should close when the battle view opens")
				return
			if _view.units.is_empty():
				if _step_clock > 5.0:
					_finish(false, "no battle_state snapshots")
				return
			var node := _find("node")
			if node == null:
				_finish(false, "the defenders should have a Command Node")
				return
			_started_ms = Net.now_ms()
			if DisplayServer.get_name() != "headless":
				Input.warp_mouse(get_viewport().get_visible_rect().size / 2.0) # not at the edge, where it pans
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
				if _step_clock > 0.9 and _step_clock < 1.2:
					_view.look_at_ground(_tanks[0].to)
					_view._dist_to = 90.0
				return
			_go("landed", 1.0)
		"landed":
			var mid := Vector2.ZERO
			for u in _tanks:
				mid += u.to / _tanks.size()
			_view.look_at_ground(mid)
			_view._dist_to = 45.0
			_go("close zoom", 1.2)
		"close zoom":
			_shot("rts-02-close-zoom")
			_go("attack-move", 0.4)
		"attack-move":
			var node := _find("node")
			_view.select(_tanks.map(func(u): return u.id))
			for u in _tanks:
				_moved_from[u.id] = u.to
			_view.order_units(_view._my_selected(), "amove", node.to)
			_go("moving", 2.0)
		"moving":
			var moved := 0
			for u in _tanks:
				if is_instance_valid_unit(u) and u.to.distance_to(_moved_from[u.id]) > 3.0:
					moved += 1
			if moved < 3:
				if _step_clock > 6.0:
					_finish(false, "the tanks should move on the attack-move: %d of 3 did" % moved)
				return
			# Take control of the first tank and drive it to the side.
			var t: Units.Unit = _tanks[0]
			_view.select([t.id])
			_view.take_control()
			_driven = t.id
			_drive_from = t.to
			_view.drive_override = {"move": Vector2(1, 0), "fire": true, "aim": t.to + Vector2(0, 50)}
			_go("driving", 2.5)
		"driving":
			var t: Units.Unit = _view.units.get(_driven)
			if t == null:
				_finish(false, "the driven tank died before it could be checked")
				return
			if t.state != "driven" or not _view.driving():
				_finish(false, "the tank should be driven (state %s)" % t.state)
				return
			var d: Vector2 = t.to - _drive_from
			if d.x < 4.0 or absf(d.y) > d.x * 0.6 + 6.0:
				if _step_clock < 4.0:
					return
				_finish(false, "driving +x should move the tank that way: moved %s" % d)
				return
			_shot("rts-03-taking-control-of-a-tank")
			_go("release", 0.4)
		"release":
			_view.drive_override = null
			_view.take_control() # P again: back to command
			_go("released", 1.0)
		"released":
			if _view.driving():
				_finish(false, "P should give the tank back")
				return
			var t: Units.Unit = _view.units.get(_driven)
			if t and t.state == "driven":
				if _step_clock < 3.0:
					return
				_finish(false, "the server should hand the tank back")
				return
			_view.order_units([_driven], "amove", _find("node").to, true)
			_view.call_in("engineer", 1)
			_view._dist_to = 1900.0
			_view.look_at_ground(Vector2(800, 800))
			_go("strategic", 2.0)
		"strategic":
			if not _view.strategic():
				return
			_shot("rts-04-strategic-zoom")
			_go("leave", 0.5)
		"leave":
			# Leave battle, then back in through the Sector Battles screen's Join battle.
			_mass_left = _view.mass
			_view.leave()
			_go("left", 1.0)
		"left":
			if BattleView.active or is_instance_valid(_view):
				_finish(false, "Leave battle should close the battle view")
				return
			var listed: Array = Net.state.get("battles", []).filter(func(b): return str(b.get("sector", "")) == _sector)
			if listed.is_empty() or not listed[0].get("pilots", []).is_empty():
				if _step_clock > 4.0:
					_finish(false, "the battle should still run, with nobody in it, after Leave battle: %s" % [listed])
				return
			_menu = BattleMenu.open(self, PLANET)
			_go("rejoin", 0.5)
		"rejoin":
			_menu.select_sector(_sector)
			if not _menu._join.visible or _menu._join.disabled:
				_finish(false, "Join battle should be on for the running battle on " + _sector)
				return
			_shot("rts-06-sector-battles-running")
			_go("join", 0.6)
		"join":
			_menu._join.pressed.emit()
			_view = null
			_go("rejoining")
		"rejoining":
			for c in get_tree().root.get_children():
				if c is BattleView and not c.is_queued_for_deletion():
					_view = c
			if _view == null or _view.units.is_empty():
				if _step_clock > 8.0:
					_finish(false, "Join battle should put the pilot back in the battle")
					return
				return
			if _mine("tank").is_empty() or _view.mass < _mass_left - 1.0:
				_finish(false, "back in the battle, the tanks and the mass should still be there (mass %d, was %d)" % [int(_view.mass), int(_mass_left)])
				return
			_go("fight")
		"fight":
			_fight()
		"ended":
			_check_end()


## Before the real battle: a battle view fed made-up snapshots of PERF_UNITS units of every type
## moving and shooting (both sides, half of them the pilot's), close up and then zoomed out to the
## strategic icons, to check the view's own work a frame (units, effects, icons) stays small.
func _perf() -> void:
	if _perf_view == null:
		var cat := {}
		for t in ["engineer", "scout", "striker", "tank", "artillery", "aa", "gunship", "extractor", "turret", "factory", "node"]:
			cat[t] = {"name": t.capitalize(), "kind": "air" if t == "gunship" else ("structure" if t in ["extractor", "turret", "factory", "node"] else "land"),
				"hp": 500, "radius": 8 if t in ["extractor", "turret", "factory", "node"] else 3, "cost": 100, "reload": 1}
		_perf_view = BattleView.open(self, {"type": "battle_joined", "battle": "perf-check", "planet": PLANET, "sector": "perf", "sectorName": "Perf",
			"planetName": "Scar", "size": 1600, "seed": 7, "attacker": "compact", "defender": null, "side": "a", "lz": {"x": 800, "z": 170, "r": 120},
			"enemyLz": {"x": 800, "z": 1430, "r": 120}, "massPoints": [{"id": 1, "x": 700, "z": 400}], "units": cat, "endsAt": Net.now_ms() + 600000.0, "mass": 400, "names": {}})
		return
	if not _perf_view.is_inside_tree():
		return
	_perf_frames += 1
	if _perf_frames == 1:
		_perf_view.look_at_ground(Vector2(800, 520))
		_perf_view._dist_to = 160.0
	if _perf_frames == 60:
		_perf_view._dist_to = 1600.0
	if _perf_frames % 6 == 1: # a snapshot every 6 frames (200 ms at 30 fps)
		var types := ["tank", "striker", "artillery", "aa", "gunship", "scout", "engineer"]
		var rows := []
		var shots := []
		for k in PERF_UNITS:
			var side := "a" if k % 2 == 0 else "d"
			rows.append([5000 + k, types[k % 7], side, PILOT if side == "a" else "", 500.0 + (k % 24) * 25.0 + sin(_perf_frames * 0.05 + k) * 8.0,
				300.0 + floorf(k / 24.0) * 30.0 + _perf_frames * 0.4, 300.0, 0.3 * k, "move"])
			if k % 6 == 0:
				shots.append([5000 + k, 560.0 + (k % 9) * 40.0, 600.0, types[k % 7]])
		Net.message.emit({"type": "battle_state", "battle": "perf-check", "t": _perf_frames * 0.1, "mass": 400, "income": 2, "units": rows,
			"dead": [], "shots": shots, "build": [], "pilots": [{"name": PILOT, "side": "a"}], "endsAt": Net.now_ms() + 600000.0, "feed": []})
	if _perf_frames == 59 or _perf_frames == 119:
		var ms: float = _perf_view.work_ms + _perf_view._fx.work_ms + _perf_view._overlay.draw_ms
		print("perf (%s, %d units): view %.2f ms, effects %.2f ms, icons and bars %.2f ms a frame" % ["close" if _perf_frames < 60 else "strategic",
			_perf_view.units.size(), _perf_view.work_ms, _perf_view._fx.work_ms, _perf_view._overlay.draw_ms])
		if _perf_view.units.size() < PERF_UNITS or ms > PERF_BUDGET_MS:
			_finish(false, "the battle view should draw %d units in under %.0f ms a frame: %.1f ms" % [PERF_UNITS, PERF_BUDGET_MS, ms])
			return
	if _perf_frames >= 120:
		_perf_view.close()
		_perf_view = null
		_states = 0
		_go("start", 0.3)


## Keeps the attack going until the battle ends, as a player would against a dug-in base: the
## engineer takes the mass points near the landing zone, all the mass goes on tanks and artillery
## (one for one) gathered at the landing zone, and once the army is big enough (or nearly half the
## time is gone) it attack-moves on the Command Node as one, reinforcements following.
func _fight() -> void:
	if not _end.is_empty():
		_check_end()
		return
	if _step_clock > 300.0:
		_finish(false, "the Command Node should fall in time (%d snapshots)" % _states)
		return
	if _clock - _drop_at < 0.5:
		return
	_drop_at = _clock
	var all_engineers := _mine("engineer").filter(func(u): return not u.dropping())
	_factory_steps(all_engineers)
	# Three engineers, as a player would: every extractor needs five generators built first.
	if _mine("engineer").size() < 3 and _view.mass >= 50.0 and _view.energy >= 125.0:
		_view.call_in("engineer", 1)
	# Each pass gives one idle engineer a job (the list holds just that one).
	var engineers := all_engineers.filter(func(u): return u.orders.is_empty())
	var lz: Dictionary = _view.info.get("lz", {"x": 800, "z": 170})
	var back := -1.0 if float(lz.z) < 800.0 else 1.0
	if not engineers.is_empty() and engineers[0].orders.is_empty() and _factory_stage == 0 and _extractors >= 5:
		# A factory beside the landing zone: built on the planet, its units cost half.
		for dx in [70.0, -70.0, 110.0, -110.0]:
			var spot := Vector2(float(lz.x) + dx, float(lz.z) + back * 60.0)
			if _view._site("factory", spot) != null:
				_view.order_units([engineers[0].id], "build", spot, false, -1, "factory")
				_factory_stage = 1
				break
	elif not engineers.is_empty() and engineers[0].orders.is_empty() and (_generators < 5 * _extractors + 3 or (_extractors >= 5 and _factory_stage > 0)) and _generators < 35:
		# Every extractor needs five generators' worth of energy, and units need energy too: rows of
		# Power Generators either side of the landing zone (behind it can be the edge of the map).
		var side := 1.0 if _generators % 2 == 0 else -1.0
		var spot := Vector2(float(lz.x) + side * (150.0 + 28.0 * ((_generators / 2) % 6)), float(lz.z) - back * 28.0 * (_generators / 12))
		if _view._site("generator", spot) != null:
			_view.order_units([engineers[0].id], "build", spot, false, -1, "generator")
		_generators += 1
	elif not engineers.is_empty() and engineers[0].orders.is_empty() and _extractors < 5:
		var e: Units.Unit = engineers[0]
		var best = null
		for p in _view.mass_points:
			if _view._point_free(p) and (best == null or Vector2(p.x, p.z).distance_to(e.to) < Vector2(best.x, best.z).distance_to(e.to)):
				best = p
		if best and Vector2(best.x, best.z).distance_to(e.to) < 700.0:
			_view.select([e.id])
			_view.order_units([e.id], "build", Vector2(best.x, best.z), false, -1, "extractor")
			_extractors += 1
			print("engineer %d builds an extractor at %s" % [e.id, Vector2(best.x, best.z)])
	var node: Units.Unit = _find("node")
	if node == null:
		return
	if _view.my_unit_count() < 110:
		var kind := "artillery" if _bought % 2 == 1 else "tank"
		var cost := float(_view.catalog[kind].cost)
		var energy := float(_view.catalog[kind].energy)
		if _view.mass >= cost and _view.energy >= energy:
			var n := clampi(mini(int(_view.mass / cost), int(_view.energy / energy)), 1, 10)
			_view.call_in(kind, n)
			_bought += 1
	var army := 0.0
	var idle := []
	var guns := []
	for u: Units.Unit in _view.units.values():
		if u.mine and u.kind != "structure" and u.type != "engineer" and u.type != "acu" and not u.dropping(): # the ACU stays home: losing it loses the battle
			army += float(_view.catalog[u.type].cost)
			if u.state == "idle":
				(guns if u.type == "artillery" else idle).append(u.id)
	var left := (float(_view.ends_at) - Net.now_ms()) / (float(_view.ends_at) - _started_ms)
	if not _attacking and (army >= 1800.0 or left < 0.55):
		_attacking = true
		print("attacking with an army worth %d mass" % int(army))
	# The army attack-moves on the Command Node, fighting its way through; reinforcements follow
	# in groups of four or more.
	if _attacking and idle.size() + guns.size() >= 4:
		_view.order_units(idle + guns, "amove", node.to)
	if int(_step_clock * 2.0) % 30 == 0:
		print("t %.0f: mass %d, energy %d (%+d/s), %d of mine (worth %d), node hp %d, %d snapshots, slowest frame %.0f ms" % [_step_clock, int(_view.mass), int(_view.energy), int(_view.energy_income), _view.my_unit_count(), int(army), int(node.hp), _states, _slowest * 1000.0])
	if _attacking and not _looked and DisplayServer.get_name() != "headless":
		_looked = true
		_view._dist_to = 300.0
		_view.look_at_ground(node.to - Vector2(0, 200) * (1.0 if _view.my_side == "a" else -1.0))


## The factory, through the HUD as a player would: select it when it's built, press its upgrade
## button, and once it's tier 2 its Tank Mk II button; done when the Mk II rolls out.
func _factory_steps(_engineers: Array) -> void:
	var hud: Control = _view._hud
	match _factory_stage:
		1:
			var built := _mine("factory").filter(func(u): return u.progress >= 1.0)
			if built.is_empty():
				return
			_factory = built[0].id
			_view.select([_factory])
			var up := _buttons(hud, "Upgrade to tier 2")
			if up.is_empty():
				return # the panel is drawn on the HUD's next frame
			if _buttons(hud, "Tank Mk II").size() > 0 or _buttons(hud, "Tank ").is_empty():
				_finish(false, "a tier 1 factory should offer tier 1 units only, at half price")
				return
			up[0].pressed.emit()
			_factory_stage = 2
		2:
			if int(_view.factories.get(_factory, {}).get("tier", 1)) < 2:
				return
			_view.select([_factory])
			var mk2 := _buttons(hud, "Tank Mk II")
			if mk2.is_empty():
				return
			_shot("rts-04b-tier-2-factory")
			mk2[0].pressed.emit()
			_factory_stage = 3
		3:
			if not _mine("tank_t2").is_empty():
				_factory_stage = 4
				print("the tier 2 factory made a Tank Mk II")


func _check_end() -> void:
	if OS.get_environment("RTS_DEBUG") != "":
		print("check_end %.1f valid=%s active=%s" % [_step_clock, is_instance_valid(_view), BattleView.active])
	if str(_end.get("side", "")) != "a":
		_finish(false, "the battle should end with the sector taken: " + str(_end))
		return
	if _step != "ended":
		_go("ended")
		_shot_later("rts-05-battle-end", 1.0)
	var wp: Array = Net.state.war.planets.filter(func(p): return p.id == PLANET)
	var sec: Array = wp[0].sectors.filter(func(s): return s.id == _sector)
	if str(sec[0].get("owner", "")) != "compact":
		if _step_clock > 5.0:
			_finish(false, "the war map should show %s taken by the Compact" % _sector)
		return
	if _step_clock < 8.0:
		return
	if BattleView.active or is_instance_valid(_view):
		_finish(false, "the battle view should close by itself after the banner")
		return
	if _factory_stage != 4:
		_finish(false, "the factory should have been built, upgraded to tier 2 and made a Tank Mk II (got to stage %d)" % _factory_stage)
		return
	_finish(true, "%d units drawn in budget; attacked %s from the carrier, dropped units, attack-moved, drove a tank, left and rejoined, built a factory, upgraded it to tier 2 and made a Tank Mk II, took the sector (%s); %d snapshots, slowest frame %.0f ms" % [PERF_UNITS, _sector, _end.get("text", ""), _states, _slowest * 1000.0])


func is_instance_valid_unit(u: Units.Unit) -> bool:
	return _view.units.has(u.id)


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
	print(("PASS " if ok else "FAIL ") + "rts: " + what)
	get_tree().quit(0 if ok else 1)


## Visible buttons under `root` whose text contains `text`.
func _buttons(root: Node, text: String) -> Array:
	return root.find_children("*", "Button", true, false).filter(func(b): return b.is_visible_in_tree() and b.text.contains(text))
