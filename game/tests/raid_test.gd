extends Node
## Plays a whole raid against a running galaxy server, the way a player would:
## a Builder of the Luminar Accord founds an Extractor outpost on a sector of Halcyon the Luminar
## Accord holds and places defences on it, and a pilot of the Ashen Collective docks at Halcyon
## Orbital, picks the outpost in the ship's menu and a landing spot from overhead (out
## of the turrets' reach), is dropped off, blows up the power plant, walks in
## through the blast door, rides the lifts down to the deepest level, searches containers until the
## keycard turns up, opens the safe room's vault, takes something from it, rides back up before the
## self-destruct, knocks out every outside defence so the ship comes back, and boards it, ending back
## in the pilot's seat in the hangar.
## On level 1 it also checks the combat kit: armour soaking damage, healing from the pouch (a tap
## and the wheel, and cancelling), the grenade launcher (swap, rounds, blast falloff, walls,
## damage to yourself) and picking up supplies.
## (Selling it is covered by the server tests.)
## Use a fresh galaxy (a new save file):
##   cd server && SAVE_FILE=/tmp/raid.json DEMO=1 BUILD_SPEED=0 npm start   (delete /tmp/raid.json first)
##   godot --headless --path game res://tests/raid.tscn
## Add `-- --shots=/some/dir` and run with a display to save screenshots along the way,
## and `-- --server=ws://127.0.0.1:9000` to use a server on another port.
## Prints PASS or FAIL and quits.

const ExplorerMode := preload("res://explorer.gd")
const BUILDER := "Raid Test Builder"

var _explorer: Node
var _raid: Node
var _step := "build"
var _clock := 0.0
var _wait := 0.0
var _queue: Array = [] # containers left to search
var _searching := ""
var _search_time := 0.0
var _result := {}
var _shots := ""
var _shot_n := 0
var _took_from_vault := false
var _builder := WebSocketPeer.new() # a second connection playing the Builder who owns the site
var _server := "ws://127.0.0.1:8080"
var _key := "" # the site being raided
var _port := "" # the planet whose High Port the pilot docks at
var _laid_out := false
var _sector := "" # the sector of Halcyon the outpost goes on
var _overview: Camera3D
var _t := 0.0 # time in the current combat check
var _pouch_before := {}
var _pick := "" # the loose supply being picked up
var _tried: Array = [] # loose supplies whose pick-up went wrong
var _done := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shots = arg.substr(8)
		elif arg.begins_with("--server="):
			_server = arg.substr(9)
	Net.connect_to(_server, "explorer", "Raid Tester")
	_explorer = ExplorerMode.new()
	add_child(_explorer)
	Net.server_error.connect(func(r): print("server: ", r))
	Net.raid_event.connect(func(m): if m.ev == "end": _result = m.result)


func _process(delta: float) -> void:
	_clock += delta
	_wait -= delta
	if _done:
		return
	if _clock > 150:
		_finish(false, "timed out at step " + _step)
	if Net.state.is_empty() or _wait > 0:
		return
	match _step:
		"build":
			if _builder.get_ready_state() == WebSocketPeer.STATE_CLOSED:
				_builder.inbound_buffer_size = 4 * 1024 * 1024 # the welcome is over the default 64 KiB
				_builder.connect_to_url(_server)
			_builder.poll()
			if _builder.get_ready_state() != WebSocketPeer.STATE_OPEN:
				return
			# Both pick sides: the outpost goes in a sector of Halcyon the Luminar Accord holds, with
			# no outposts yet, and an Ashen pilot raids it. (Luminar, so the raid's numbers aren't
			# scaled: Compact defences are tougher, and Heat builds faster in Ashen outposts.)
			var used := []
			for p in Net.state.system.planets:
				used.append(p.get("sector", ""))
			var sector := ""
			for sec in _war_planet("halcyon").get("sectors", []):
				if sec.owner == "luminar" and not used.has(sec.id) and sector == "":
					sector = sec.id
			if sector == "":
				_finish(false, "no free sector of Halcyon held by the Luminar Accord")
				return
			Net.send({"type": "choose_faction", "faction": "ashen"})
			_send_builder({"type": "hello", "role": "builder", "name": BUILDER})
			_send_builder({"type": "choose_faction", "faction": "luminar"})
			_sector = sector
			_step = "command"
		"command":
			# A new base's Command Centre (level 1) founds no outposts: the Builder takes it to level 2
			# first, then founds the outpost.
			_builder.poll()
			var home := {}
			for p in Net.state.system.planets:
				if p.get("owner", "") == BUILDER and p.get("kind", "") != "satellite":
					home = p
			if home.is_empty():
				return
			var level := 1
			for b in home.get("buildings", []):
				if b.get("type", "") == "command":
					level = int(b.get("level", 1))
			if level < 2:
				_send_builder({"type": "upgrade_building", "planet": home.id, "slot": 8})
				_wait = 0.5
				return
			_send_builder({"type": "found_site", "facility": "refinery", "planet": "halcyon", "sector": _sector})
			_step = "fly"
		"fly":
			_builder.poll()
			if _facility().is_empty():
				return
			_key = _facility().planet
			var site := Net.planet(_key)
			if site.get("faction") != "luminar" or site.get("parent") != "halcyon" or site.get("dormant", true):
				_finish(false, "the outpost should stand awake on Halcyon for the Luminar Accord: %s" % [[site.get("faction"), site.get("sector"), site.get("dormant")]])
				return
			if _explorer._me().get("faction") != "ashen":
				return # the pilot's side is on its way
			if not _laid_out:
				# The Builder lays out defences (trying a few spots, as obstacles may be in the way)
				# and upgrades the facility to level 3, so the raid has three levels below.
				_laid_out = true
				for spot in [["power", 0, 0], ["power", 10, 10], ["power", 0, 10], ["power", 10, 0],
						["turret", 2, 8], ["turret", 8, 2], ["turret", 0, 4], ["turret", 10, 5], ["turret", 5, 10], ["guardpost", 9, 6], ["guardpost", 1, 4],
						["wall", 5, 1], ["wall", 6, 1], ["wall", 11, 5]]:
					_send_builder({"type": "place_piece", "planet": _key, "piece": spot[0], "x": spot[1], "y": spot[2]})
				for i in 2:
					_send_builder({"type": "upgrade_building", "planet": _key, "slot": 0})
				_wait = 1.5
				return
			if int(Net.planet(_key).buildings[0].get("level", 1)) < 3:
				_send_builder({"type": "upgrade_building", "planet": _key, "slot": 0})
				_wait = 0.5
				return
			_port = Net.planet(_key).get("parent", _key)
			if not _explorer._stations.has(_port):
				return
			_explorer.teleport(_explorer.System.offset(_explorer._stations[_port].pos, Vector3(0, 0, 900)))
			_wait = 0.5
			_step = "dock"
		"dock":
			_shot("1-at-high-port")
			if not _explorer._prompt.text.contains("dock"):
				_finish(false, "no docking prompt: " + _explorer._prompt.text)
			_explorer.dock(_port)
			_wait = 0.3
			_step = "board"
		"board":
			var raid_button: Array = _explorer._dock_list.get_children().filter(func(c): return c is Button and c.text.contains(Net.planet(_facility().planet).name))
			if raid_button.is_empty():
				_finish(false, "no raid option in the transit menu")
			raid_button[0].pressed.emit()
			_step = "inside"
		"inside":
			_raid = _explorer._raid
			if _raid == null:
				return
			_raid.god_mode = true
			# The outside is the site exactly as the Builder laid it out, drawn by the Builder's own view.
			var placed: Array = Net.planet(_key).get("pieces", []).map(func(p): return [int(p.id), p.type, int(p.x), int(p.y)])
			var mirrored: Array = _raid.layout.view.pieces.map(func(p): return [int(p.id), p.type, int(p.x), int(p.y)])
			if placed.is_empty() or JSON.stringify(placed) != JSON.stringify(mirrored):
				_finish(false, "raid site %s is not the Builder's %s" % [mirrored, placed])
			for id in _raid._pieces:
				if _raid._pieces[id].model == null:
					_finish(false, "no Builder model for piece " + id)
			if _raid.floors != 3:
				_finish(false, "a level 3 facility should have 3 levels, not %d" % _raid.floors)
			for c in _raid.layout.containers:
				if c.type != "vault" and int(c.floor) == _raid.floors:
					_queue.append(c.id)
			_wait = 0.5
			_step = "choose"
		"choose":
			# From overhead: no landing on the site or in a turret's reach.
			if _raid.phase != "choose" or _raid.ship_state != "carrying":
				_finish(false, "a raid should start overhead, picking a landing spot")
			_shot("0a-pick-landing")
			if _raid.landing_problem(0, 0) == "":
				_finish(false, "landing on the site itself should be refused")
			var spot := Vector3.INF
			for a in range(0, 360, 5):
				var p := Vector3(cos(deg_to_rad(a)), 0, sin(deg_to_rad(a))) * 90.0
				if spot == Vector3.INF and _raid.landing_problem(p.x, p.z) == "":
					spot = p
			if spot == Vector3.INF:
				_finish(false, "nowhere to land")
			_raid.choose_landing(spot)
			_wait = 0.3
			_step = "confirm"
		"confirm":
			_shot("0b-landing-chosen")
			_raid.confirm_landing()
			_t = 0.0
			_step = "dropping"
		"dropping":
			_t += delta
			if _t > 1.5 and _t < 1.6:
				_shot("0c-flying-in")
			if _raid.phase != "play":
				if _t > 10.0:
					_finish(false, "the ship never set you down")
				return
			# You land well out of the site's turret range, beside your ship, facing the site.
			var me: Vector3 = _raid._player.position
			for id in _raid._pieces:
				var pc: Dictionary = _raid._pieces[id]
				if pc.data.type == "turret" and Vector2(me.x - pc.data.pos[0], me.z - pc.data.pos[1]).length() < 34.0:
					_finish(false, "spawned within reach of turret %s" % id)
			if _raid._ship.position.distance_to(me) > 10.0 or (-_raid._player.global_basis.z).dot(-me.normalized()) < 0.8:
				_finish(false, "not beside the ship facing the site: %s" % me)
			if _raid.armor != 50.0 or _raid.vest_item != "vest50" or _raid.grenades != 7 or _raid.health != 100.0:
				_finish(false, "should start with 100 health, a 50 vest and 7 grenades")
			if _counts(_raid.pouch) != _counts({"syringe": 2, "medkit": 1, "cell": 2, "battery": 1}):
				_finish(false, "a new raider gets the starter pouch, not %s" % _raid.pouch)
			_wait = 1.0
			_step = "overview"
		"overview":
			# A look from above, to compare with the Builder's view of the same site.
			_shot("1b-landed")
			_overview = Camera3D.new()
			_overview.far = 1500.0
			_raid.add_child(_overview)
			_overview.global_position = Vector3(0, 70, 60)
			_overview.look_at(Vector3(0, 0, 4), Vector3.UP)
			_overview.make_current()
			_wait = 0.3
			_step = "overview-shot"
		"overview-shot":
			_shot("0-overview")
			_raid._camera.make_current()
			_overview.queue_free()
			_wait = 0.2
			_step = "breach"
		"breach":

			var power := ""
			for id in _raid._pieces:
				if _raid._pieces[id].data.type == "power":
					power = id
			if power == "":
				_finish(false, "the Builder's power plant isn't in the raid")
			# A grenade does three times the damage to the site's defences. It goes off 2 m out from
			# the middle of the turret's side that faces the core, so its nearest point is 2 m away
			# wherever the turret stands (pieces are square to the grid).
			for id in _raid._pieces:
				var pc: Dictionary = _raid._pieces[id]
				if pc.data.type == "turret" and not pc.dead and not pc.data.get("ring", false):
					var body: StaticBody3D = pc.node
					var inward := -body.global_position * Vector3(1, 0, 1)
					var side := Vector3(signf(inward.x), 0, 0) if absf(inward.x) >= absf(inward.z) else Vector3(0, 0, signf(inward.z))
					var half: float = (body.get_child(0).shape.size as Vector3).dot(side.abs()) / 2.0
					var before: float = pc.health
					_raid.burst(body.global_position * Vector3(1, 0, 1) + Vector3(0, 1.0, 0) + side * (half + 2.0))
					var want: float = _raid.blast_damage(2.0) * 3.0
					if absf(before - pc.health - want) > 1.0:
						_finish(false, "a grenade 2 m from turret %s did %.0f, expected %.0f" % [id, before - pc.health, want])
					break
			_raid.destroy_piece(power)
			_wait = 0.6
			_step = "door"
		"door":
			if not _raid.door_open:
				return
			_raid.teleport_to(_raid._door_outside())
			_shot("1c-blast-door-open")
			_raid._interact()
			_step = "inside-core"
		"inside-core":
			if not _raid.breached or _raid._floor != 1:
				return
			_step = "armour"
		"armour":
			# Armour soaks damage first; nothing grows back.
			_raid.god_mode = false
			_raid._hurt(30.0, Vector3.ZERO)
			var after_one := [_raid.armor, _raid.health]
			_raid._hurt(30.0, Vector3.ZERO)
			_raid.god_mode = true
			if after_one != [20.0, 100.0] or _raid.armor != 0.0 or _raid.health != 90.0:
				_finish(false, "armour should soak first: %s then %s" % [after_one, [_raid.armor, _raid.health]])
			# A tap of the heal key picks armour before health, and the big item for an empty bar.
			if _raid.best_item() != "battery":
				_finish(false, "with no armour left a tap should use the battery, not " + _raid.best_item())
			_raid.use_best()
			_t = 0.0
			_step = "heal"
		"heal":
			_t += delta
			if _t > 0.5 and _t < 0.6:
				_shot("8-using-battery")
				if _raid._using.is_empty():
					_finish(false, "using the battery didn't start")
			if _raid.armor >= 50.0:
				if _t < 4.5:
					_finish(false, "the battery took %.1f s, not 5" % _t)
				_t = 0.0
				_step = "healed"
			elif _t > 9.0:
				_finish(false, "the battery never finished")
		"healed":
			# The pouch comes in its own message just after the armour, maybe a frame later.
			_t += delta
			if int(_raid.pouch.get("battery", 0)) != 0:
				if _t > 1.5:
					_finish(false, "the server should have counted the battery off: %s" % _raid.pouch)
				return
			if _raid.best_item() != "syringe":
				_finish(false, "10 health down should pick the syringe, not " + _raid.best_item())
			_step = "radial"
		"radial":
			# Hold for the wheel: point at a slice, the centre cancels.
			_raid.open_radial()
			_raid._radial_vec = Vector2(80, -60)
			_wait = 0.2
			_step = "radial-shot"
		"radial-shot":
			_shot("9-heal-wheel")
			var picks := []
			for v in [Vector2(-80, -60), Vector2(80, -60), Vector2(80, 60), Vector2(-80, 60), Vector2(10, 5)]:
				_raid._radial_vec = v
				picks.append(_raid.radial_choice())
			if picks != ["syringe", "cell", "battery", "medkit", ""]:
				_finish(false, "wheel slices: %s" % [picks])
			_raid.close_radial(true) # in the middle: cancelled
			if _raid._use_asked != "" or not _raid._using.is_empty():
				_finish(false, "letting go in the middle should cancel")
			# Starting a syringe and swapping weapons stops it without using one.
			_pouch_before = _raid.pouch.duplicate()
			_raid.use_item("syringe")
			_t = 0.0
			_step = "cancel"
		"cancel":
			_t += delta
			if _raid._using.is_empty():
				if _t > 3.0:
					_finish(false, "the syringe never started")
				return
			_raid.select_weapon("launcher")
			_wait = 0.8
			_step = "launcher"
		"launcher":
			if not _raid._using.is_empty() or _counts(_raid.pouch) != _counts(_pouch_before):
				_finish(false, "swapping should cancel the syringe without using it: %s" % _raid.pouch)
			if _raid.weapon != "launcher" or _raid._swap_left > 0.0 or not _raid._launcher_model.visible:
				_finish(false, "the swap to the launcher didn't finish")
			Input.action_press("foot_aim")
			_wait = 0.4
			_step = "launcher-shot"
		"launcher-shot":
			_shot("10-launcher-aiming")
			Input.action_release("foot_aim")
			if _raid.grenade_path().size() < 3:
				_finish(false, "no arc for the launcher")
			_raid.fire_grenade()
			_t = 0.0
			_step = "grenade"
		"grenade":
			_t += delta
			if _t < 1.0:
				return
			if _raid.grenades != 6 or not _raid._flying.is_empty():
				_finish(false, "the grenade should be gone and 6 rounds left, not %d" % _raid.grenades)
			if not _blast_checks():
				return
			_raid.select_weapon("rifle")
			_step = "pickup"
		"pickup":
			# Supplies lying about go in the pouch with F. Prefer one nothing else is in reach of from where we
			# stand (another loose item or a lift would take the F instead), and try another if a pick goes wrong.
			var pick := ""
			for id in _raid._loose:
				var l: Dictionary = _raid._loose[id].data
				if _tried.has(id) or int(l.floor) != _raid._floor or not (l.item in ["syringe", "cell"]) or int(_raid.pouch.get(l.item, 0)) >= 4:
					continue
				var clear := _clear_pick(id)
				if pick == "" or clear:
					pick = id
				if clear:
					break
			if pick == "":
				_finish(false, "no loose syringe or shield cell on level 1" if _tried.is_empty() else "picking up %d loose supplies never reached the pouch" % _tried.size())
				return
			_pick = pick
			_pouch_before = _raid.pouch.duplicate()
			_pouch_before["item"] = _raid._loose[pick].data.item
			var spot: Vector3 = _raid._loose[pick].pos
			_raid.teleport_to(_pick_spot(pick))
			_raid._player.look_at(Vector3(spot.x, _raid._player.position.y, spot.z))
			_raid._pitch = -0.5
			_wait = 0.2
			_step = "pickup-go"
		"pickup-go":
			_shot("11-loose-supplies")
			_raid._interact()
			_t = 0.0
			_step = "picked"
		"picked":
			_t += delta
			var item: String = _pouch_before.item
			if int(_raid.pouch.get(item, 0)) > int(_pouch_before.get(item, 0)):
				_step = "cabinet"
			elif _t > 3.0:
				_tried.append(_pick)
				if _tried.size() >= 3:
					_finish(false, "picking up the %s didn't reach the pouch" % item)
				else:
					_step = "pickup"
		"cabinet":
			# Every med cabinet is a container on a wall with a green cross.
			var cabs := 0
			for id in _raid._containers:
				if _raid._containers[id].data.type == "medcab":
					cabs += 1
					var cab: Node3D = _raid._containers[id].node
					if cab.global_position.y + _raid.floor_depth * int(_raid._containers[id].data.floor) < 1.0:
						_finish(false, "med cabinet %s isn't on the wall" % id)
			if cabs == 0:
				_finish(false, "no med cabinets anywhere in a three-level facility")
			for id in _raid._containers:
				if _raid._containers[id].data.type == "medcab" and int(_raid._containers[id].data.floor) == _raid._floor:
					_go_to_container(id)
					_raid._player.look_at(_raid._containers[id].node.global_position * Vector3(1, 0, 1) + Vector3(0, _raid._player.position.y, 0))
					_wait = 0.3
					_step = "cabinet-shot"
					return
			_step = "down"
		"cabinet-shot":
			_shot("12-med-cabinet")
			_step = "down"
		"down":
			if _raid._floor == _raid.floors:
				_shot("2-deepest-level")
				_step = "search"
				return
			for l in _raid._lifts:
				if _raid._floor_of(l.pos) == _raid._floor and int(l.to_floor) == _raid._floor + 1:
					_raid.teleport_to(l.pos)
					_raid._interact()
					_shot("2-level-%d" % (_raid._floor))
					_wait = 0.3
					return
			_finish(false, "no lift down from level %d" % _raid._floor)
		"search":
			_shot("2-inside")
			if _raid.vault_open or _raid._holding("keycard"):
				_step = "vault"
			elif _searching == "":
				if _queue.is_empty():
					_finish(false, "searched everything, no keycard")
				_searching = _queue.pop_front()
				_go_to_container(_searching)
				_raid.open_container(_searching)
				_search_time = 0.0
			else:
				_search_time += delta
				var slots: Array = _raid._inv._slots
				if _search_time > 0.5 and slots.all(func(s): return s.has("item")):
					for s in slots:
						if s.item == "keycard":
							Net.send({"type": "raid_take", "uid": s.uid, "to": "backpack"})
					_shot("3-searched")
					_wait = 0.4
					_raid._close_inventory()
					_searching = ""
				elif _search_time > 8.0:
					_finish(false, "search never finished")
		"vault":
			if not _raid.vault_open:
				var slab: Node3D = _raid._vault_doors[0]
				var centre: Vector3 = _raid._vault_room_centre
				_raid.teleport_to(slab.global_position + (slab.global_position - centre).normalized() * Vector3(1, 0, 1) * 1.2)
				_raid._interact()
				_wait = 0.6
				return
			var box := ""
			for c in _raid.layout.containers:
				if c.type == "vault":
					box = c.id
			if _raid.self_destruct < 0.0:
				_finish(false, "opening the vault didn't start the self-destruct")
			_go_to_container(box)
			_raid.open_container(box)
			_search_time = 0.0
			_step = "loot"
		"loot":
			_search_time += delta
			var slots: Array = _raid._inv._slots
			if _search_time > 0.5 and slots.all(func(s): return s.has("item")):
				_shot("4-vault")
				for s in slots:
					Net.send({"type": "raid_take", "uid": s.uid, "to": "backpack"})
					_took_from_vault = true
				_wait = 0.5
				_step = "extract"
			elif _search_time > 10.0:
				_finish(false, "vault search never finished")
		"extract":
			_raid._close_inventory()
			_shot("5-self-destruct")
			if _raid._floor == 0:
				# The ship is away until every outside defence is down.
				if _raid.ship_state != "away":
					_finish(false, "the ship should still be away, not " + _raid.ship_state)
				for id in _raid._pieces:
					var pc: Dictionary = _raid._pieces[id]
					if pc.data.type in ["turret", "guardpost", "power"] and not pc.dead:
						_raid.destroy_piece(id)
				_t = 0.0
				_step = "ship-back"
				return
			for l in _raid._lifts:
				if _raid._floor_of(l.pos) == _raid._floor and int(l.to_floor) == _raid._floor - 1:
					_raid.teleport_to(l.pos)
					_raid._interact()
					_wait = 0.3
					return
			_finish(false, "no lift up from level %d" % _raid._floor)
		"ship-back":
			_t += delta
			if _raid.ship_state != "back":
				if _t > 5.0:
					_finish(false, "the ship didn't come back with %d defences left" % _raid.defences_left)
				return
			if _t < 2.0:
				return
			_shot("5b-ship-returning")
			_raid.teleport_to(_raid._extract_nodes["ship"].pos)
			_step = "extracting"
		"extracting":
			if not _result.is_empty():
				if _result.outcome != "extracted":
					_finish(false, "outcome " + _result.outcome)
				_wait = 0.5
				_step = "results"
		"results":
			_shot("6-results")
			_raid.finished.emit(_result)
			_wait = 0.5
			_step = "sell"
		"sell":
			if _explorer._raid != null:
				_finish(false, "still in the raid after leaving")
			if _explorer._station != null and _explorer._station.seated and not _explorer._me().get("stash", []).is_empty():
				_shot("7-back-in-the-ship")
				_finish(_took_from_vault, "raided the vault, extracted with %d stacks worth %d credits, back in your ship in the hangar" % [_result.kept.size(), int(_result.value)])


## Where to stand to pick up loose supply `id`: a little way from it, towards the middle of its room.
func _pick_spot(id: String) -> Vector3:
	var spot: Vector3 = _raid._loose[id].pos
	var room_c: Vector3 = _raid._room_centre(int(_raid._loose[id].data.room))
	return spot + (room_c - spot).normalized() * 1.2


## True when, standing at `id`'s pick spot, F would pick up `id` and nothing else.
func _clear_pick(id: String) -> bool:
	var stand := _pick_spot(id)
	var flat := func(p: Vector3) -> Vector2: return Vector2(p.x, p.z)
	var reach: float = (flat.call(_raid._loose[id].pos) - flat.call(stand)).length()
	for other in _raid._loose:
		if other != id and int(_raid._loose[other].data.floor) == _raid._floor \
				and (flat.call(_raid._loose[other].pos) - flat.call(stand)).length() < reach + 0.3:
			return false
	for l in _raid._lifts:
		if _raid._floor_of(l.pos) == _raid._floor and (flat.call(l.pos) - flat.call(stand)).length() < _raid.LIFT_REACH + 0.5:
			return false
	return true


# Blast falloff, walls and your own grenade, with grenades set off by hand on level 1.
func _blast_checks() -> bool:
	var r := _raid
	# Two neighbouring rooms with a wall (no door) between them.
	var a := -1
	var b := -1
	for id in r.rooms:
		var room: Dictionary = r.rooms[id]
		var lv: Dictionary = r._level(int(room.floor))
		if int(room.floor) == r._floor and int(room.x) + 1 < int(lv.cols) and r._door_between(id, id + 1).is_empty():
			a = id
			b = id + 1
			break
	if a < 0:
		return true # every pair has a door: nothing to check here
	var wall_x: float = r._room_centre(a).x + r.room / 2.0
	var at := Vector3(wall_x + 1.5, r._room_centre(b).y + 1.0, r._room_centre(b).z)
	var g: Dictionary = r._spawn_guard("blast-test", [a], Vector3(wall_x - 1.5, r._room_centre(a).y, r._room_centre(a).z), false)
	g.body.position = Vector3(wall_x - 1.5, r._room_centre(a).y + 0.05, r._room_centre(a).z)
	r.burst(at)
	if g.health != r.GUARD_HEALTH:
		_finish(false, "a blast went through a wall (guard at %d)" % g.health)
		return false
	var near := Vector3(wall_x - 4.0, at.y, at.z)
	var d := near.distance_to(g.body.global_position + Vector3(0, 0.9, 0))
	r.burst(near)
	if absf((r.GUARD_HEALTH - g.health) - r.blast_damage(d)) > 0.5:
		_finish(false, "blast damage %.1f at %.1f m, expected %.1f" % [r.GUARD_HEALTH - g.health, d, r.blast_damage(d)])
		return false
	if r.blast_damage(0) != 120.0 or r.blast_damage(6.0) != 0.0:
		_finish(false, "the blast should do 120 at the centre, nothing at 6 m")
		return false
	# Your own grenade: half damage, armour first.
	r.teleport_to(r._room_centre(a))
	r.health = 100.0
	r.armor = 10.0
	r.god_mode = false
	var mine: Vector3 = r._player.position + Vector3(2.0, 0.9, 0)
	r.burst(mine)
	r.god_mode = true
	var taken: float = 110.0 - r.health - r.armor
	if absf(taken - r.blast_damage(2.0) * 0.5) > 0.5 or r.armor != 0.0:
		_finish(false, "your own grenade did %.1f (armour %.0f), expected %.1f" % [taken, r.armor, r.blast_damage(2.0) * 0.5])
		return false
	return true


func _counts(d: Dictionary) -> String:
	var out := []
	for k in ["syringe", "medkit", "cell", "battery"]:
		out.append(int(d.get(k, 0)))
	return str(out)


func _send_builder(msg: Dictionary) -> void:
	_builder.send_text(JSON.stringify(msg))


func _facility() -> Dictionary:
	for f in Net.facilities():
		if Net.planet(f.planet).get("owner", "") == BUILDER:
			return f
	return {}


func _war_planet(id: String) -> Dictionary:
	for p in Net.state.get("war", {}).get("planets", []):
		if p.id == id:
			return p
	return {}


func _go_to_container(id: String) -> void:
	var node: Node3D = _raid._containers[id].node
	var c: Dictionary = _raid._containers[id].data
	var centre: Vector3 = _raid._room_centre(int(c.room))
	var flat := (centre - node.global_position) * Vector3(1, 0, 1)
	_raid.teleport_to(node.global_position + flat.normalized() * 1.3)


func _shot(name: String) -> void:
	if _shots == "" or DisplayServer.get_name() == "headless":
		return
	_shot_n += 1
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_shots, name])


func _finish(ok: bool, what: String) -> void:
	if _done:
		return # the first result stands
	_done = true
	print(("PASS " if ok else "FAIL ") + "raid: " + what)
	get_tree().quit(0 if ok else 1)
