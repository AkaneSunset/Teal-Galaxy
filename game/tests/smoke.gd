extends Node
## Headless smoke test of the two modes against a running galaxy server with a fresh galaxy.
## Run the server with instant buildings and a new save file:
##   cd server && SAVE_FILE=/tmp/smoke.json BUILD_SPEED=0 npm start   (delete /tmp/smoke.json first)
## then in two terminals, at the same time:
##   godot --headless --path game res://tests/smoke.tscn -- --role=builder
##   godot --headless --path game res://tests/smoke.tscn -- --role=explorer
## The Builder joins the Terran Compact, posts the ice job, checks outposts wait for Command Centre
## level 2 and opens the War screen. The pilot joins the Ashen Collective, mines and
## delivers the ice, and opens the war map and the War terminal.
## The admin check: start the server with ADMIN_KEY=<key> too and add `--admin-key=<key>` after
## `--role=`, and both check the Coma Conglomerate is on the faction cards and the Coma director's
## controls show; without a key (one saved for this server counts as one), that neither does.
## Add `--server=ws://127.0.0.1:9000` for a server on another port.
## Each prints PASS or FAIL and quits.

const ExplorerMode := preload("res://explorer.gd")
const BuilderMode := preload("res://builder.gd")
const WarInfo := preload("res://war_info.gd")

var _role := "builder"
var _server := "ws://127.0.0.1:8080"
var _mode: Node
var _step := 0
var _clock := 0.0
var _saw_mine_prompt := false
var _admin := false # run with an admin key: the director's controls should show
var _outpost := "" # the outpost the Builder founded
var _done := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			_role = arg.substr(7)
		elif arg.begins_with("--server="):
			_server = arg.substr(9)
	Net.connect_to(_server, _role, "Smoke " + _role)
	_admin = Net.admin_key() != "" # Net reads --admin-key= itself, or the key saved for this server
	_mode = BuilderMode.new() if _role == "builder" else ExplorerMode.new()
	add_child(_mode)
	Net.server_error.connect(func(r): print("server error: ", r))


func _process(delta: float) -> void:
	_clock += delta
	if _done:
		return
	if _clock > 40:
		_finish(false, "timed out at step %d" % _step)
	if Net.state.is_empty():
		return
	if _role == "builder":
		_builder_steps()
	else:
		_explorer_steps()


func _builder_steps() -> void:
	match _step:
		0:
			# First the faction choice: the three player factions, and Coma too for an admin.
			if Net.home == "" or not _admin_as_expected():
				return
			var offered: Array = _mode._faction_cards.keys()
			if not _mode._faction_overlay.visible or offered != _factions():
				_finish(false, "the faction choice should offer %s, not %s" % [_factions(), offered])
				return
			_mode._faction_cards.compact.pressed.emit() # the first tap arms Join, the second joins
			_mode._faction_cards.compact.pressed.emit()
			_step = 1
		1:
			if _mode._econ().get("faction") != "compact":
				return
			if _mode._faction_overlay.visible or _mode._badge_name.text != "Terran Compact":
				_finish(false, "the overlay should close and the badge say Terran Compact, not '%s'" % _mode._badge_name.text)
				return
			Net.send({"type": "build", "planet": Net.home, "slot": 0, "building": "spaceport"})
			_step = 2
		2:
			if Net.has_building("spaceport", Net.home):
				Net.send({"type": "post_job", "planet": Net.home, "resource": "ice", "amount": 10, "reward": 100})
				_step = 3
		3:
			var jobs: Array = Net.state.jobs.filter(func(j): return j.get("planet", "aster") == Net.home)
			if jobs.is_empty() or jobs[0].status != "done":
				return
			var e: Dictionary = _mode._econ()
			if not "hydroponics" in e.unlocked or int(e.stock.get("ice", 0)) != 10:
				_finish(false, "the job is done but Hydroponics isn't unlocked or the ice isn't in stock")
				return
			_mode._toggle_page("jobs")
			_step = 4
		4:
			# The Jobs page lists the job, and pilots' supply contracts under it.
			if not _mode._jobs.text.contains("done") or _mode._contracts.get_child_count() == 0:
				_finish(false, "the Jobs page should list the done job and the contracts")
				return
			# A new base's Command Centre (level 1) founds no outposts: the shop says to upgrade it.
			_mode._refresh_shop(Net.state)
			if not _mode._shop_hint.text.contains("Command Centre to level 2"):
				_finish(false, "the outpost shop should ask for Command Centre level 2, not '%s'" % _mode._shop_hint.text)
				return
			_outpost = "no outposts before Command Centre level 2"
			_mode.open_war()
			_step = 7
		7:
			var war: Control = _mode._war
			if not war.visible or war._badge_name.text != "Terran Compact" or war._detail.get_child_count() == 0:
				_finish(false, "the War screen should open on Teal Prime with the faction badge")
				return
			if not _director_as_expected(war._tab_buttons.director.visible):
				return
			if _admin:
				war.show_tab("director")
				if war._director.get_child_count() == 0:
					_finish(false, "the Director tab opened empty")
					return
			_finish(true, "joined the Terran Compact, job done, %s, War screen open, %s" % [_outpost, _director_said()])


func _explorer_steps() -> void:
	match _step:
		0:
			# A pilot with no side is asked to pick one: three cards, and Coma too for an admin.
			if not _admin_as_expected():
				return
			var cards: Array = _mode._picker._cards.get_children().filter(func(c): return not c.is_queued_for_deletion())
			var coma := not _buttons(_mode._picker, "Play the Coma Conglomerate").is_empty()
			if not _mode._picker.visible or cards.size() != _factions().size() or coma != _admin:
				_finish(false, "the faction overlay should offer %s, not %d cards" % [_factions(), cards.size()])
				return
			var join := _buttons(_mode._picker, "Join the Ashen Collective")
			if join.is_empty():
				_finish(false, "no Join button for the Ashen Collective")
				return
			join[0].pressed.emit()
			_step = 1
		1:
			if _mode._me().get("faction") != "ashen":
				return
			if _mode._picker.visible:
				_finish(false, "the faction overlay should close once you've joined")
				return
			_step = 2
		2:
			if Net.has_building("spaceport") and not Net.open_job().is_empty():
				_mode.teleport(_mode.System.offset(_mode.rock_position(0), Vector3(0, 0, _mode._rocks[0].radius + 40)))
				for i in 10:
					Net.send({"type": "collect", "resource": "ice", "amount": 1})
				_step = 3
		3:
			_saw_mine_prompt = _saw_mine_prompt or _mode._prompt.text.contains("mine ice")
			if _mode._cargo("ice") == 10:
				_mode.teleport(_mode.System.offset(_mode.System.PORT_POS, Vector3(0, 0, 900)))
				Net.send({"type": "deliver", "job": int(Net.open_job().id)})
				_step = 4
		4:
			if Net.open_job().is_empty() and int(_mode._me().get("credits", 0)) == 100:
				_step = 5 # the HUD redraws on the explorer's next frame
		5:
			var head: String = _mode._info.text.get_slice("\n", 0)
			if not _saw_mine_prompt or not _mode._info.text.contains("Credits 100") or not head.contains("Ashen Collective") or head.contains("admin") != _admin:
				_finish(false, "the HUD should show the pay, the faction and (only for an admin) 'admin': " + head)
				return
			# The nav map's Galactic level is the war map: every contested planet is marked on it.
			_mode._nav.visible = true
			_mode._nav.set_level(_mode._nav.Level.GALACTIC)
			_mode._refresh_focus()
			_step = 6
		6:
			var marked: Array = _mode._nav._war_hits.map(func(h): return h[1])
			var missing: Array = Net.state.war.planets.filter(func(p): return not marked.has(p.id)).map(func(p): return p.id)
			if marked.is_empty() or not missing.is_empty():
				_finish(false, "the war map should mark every contested planet, not %s" % [missing if marked else "none"])
				return
			_mode._nav.visible = false
			_mode._open_war("cinder")
			var panel: Control = _mode._war_panel
			if not panel.visible or not panel._title.text.begins_with("Cinder") or panel._side.text != "Your side: Ashen Collective":
				_finish(false, "the War terminal should open on Cinder with your side: '%s', '%s'" % [panel._title.text, panel._side.text])
				return
			if not _director_as_expected(panel._pages.visible):
				return
			if _admin:
				panel._director_page.pressed.emit()
				if not panel._director.visible or panel._director._systems.size() != 3:
					_finish(false, "the Coma director page should open with Teal Prime, Marrow Reach and The Drift")
					return
			_finish(true, "joined the Ashen Collective, mined at the field, delivered and paid, war map and War terminal open, %s" % _director_said())


## The factions a character may join: the three player factions, and the Coma Conglomerate for an admin.
func _factions() -> Array:
	return ["compact", "ashen", "luminar"] + (["coma"] if _admin else [])


## With an admin key the server knows us as an admin and sends the director; without one, neither.
func _admin_as_expected() -> bool:
	if Net.admin != _admin or Net.state.has("director") != _admin:
		_finish(false, "admin %s and director %s, but the run was %s an admin key" % [Net.admin, Net.state.has("director"), "with" if _admin else "without"])
		return false
	return true


## The way into the Coma director: shown to an admin, hidden from everyone else.
func _director_as_expected(shown: bool) -> bool:
	if shown != _admin:
		_finish(false, "the Director should be %s" % ("shown to an admin" if _admin else "hidden from players"))
		return false
	return true


func _director_said() -> String:
	return "Director shown to the admin" if _admin else "no Director for a player"


## Visible buttons under `root` whose text contains `text`.
func _buttons(root: Node, text: String) -> Array:
	return root.find_children("*", "Button", true, false).filter(func(b): return b.is_visible_in_tree() and b.text.contains(text))


func _finish(ok: bool, what: String) -> void:
	if _done:
		return # the first result stands
	_done = true
	print(("PASS " if ok else "FAIL ") + _role + ": " + what)
	get_tree().quit(0 if ok else 1)
