extends Node
## Planet campaigns and matchmaking, against a running DEMO galaxy server with a short queue wait:
##   cd server && SAVE_FILE=/tmp/campaign.json DEMO=1 QUEUE_WAIT=3 npm start   (delete /tmp/campaign.json first)
##   godot --headless --path game res://tests/campaign_test.tscn
## "Campaign Tester" (Ashen Collective) goes aboard its carrier over Cinder, opens the Sector Battles
## screen, checks the campaign there (the week's scoreboard with Ashen in it, the planet's bonus, a
## Queue button for Sector Battles and Sector Defense, and the modes still to come), queues, sees it's queued (in the
## screen), and with no opponents is matched against the holder's AI: the RTS view opens by itself.
## `-- --server=ws://127.0.0.1:9000` for a server on another port. Prints PASS or FAIL and quits.

const ExplorerMode := preload("res://explorer.gd")
const PILOT := "Campaign Tester"
const PLANET := "cinder"

var _server := "ws://127.0.0.1:8080"
var _explorer: Node
var _menu: Control
var _step := "start"
var _wait := 1.0
var _clock := 0.0
var _step_clock := 0.0
var _done := false
var _joined_space := false
var _joined := {}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--server="):
			_server = arg.substr(9)
	Net.connect_to(_server, "explorer", PILOT)
	Net.message.connect(_on_message)
	Net.server_error.connect(func(r): print("server error: ", r))
	_explorer = ExplorerMode.new()
	add_child(_explorer)


func _on_message(msg: Dictionary) -> void:
	match str(msg.get("type", "")):
		"space_joined":
			_joined_space = str(msg.get("space", "")) == "ship:" + PILOT
		"battle_joined":
			_joined = msg


func _process(delta: float) -> void:
	_clock += delta
	_step_clock += delta
	if _done:
		return
	if _clock > 90.0:
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
		"start":
			Net.send({"type": "choose_faction", "faction": "ashen"})
			Net.send({"type": "enter_space", "space": "ship:" + PILOT})
			_go("aboard")
		"aboard":
			if not _joined_space or str(Net.state.get("pilots", {}).get(PILOT, {}).get("faction", "")) != "ashen":
				if _step_clock > 10.0:
					_finish(false, "never got aboard ship:%s as an Ashen pilot" % PILOT)
				return
			_explorer._hide_panels()
			_go("orbit")
		"orbit":
			# Into Cinder's orbit, 10 km from its orbital station: the carrier reports it's over Cinder.
			if not _explorer._stations.has(PLANET):
				if _step_clock > 10.0:
					_finish(false, "Cinder's orbital station never showed up")
				return
			_explorer.teleport(_explorer.System.offset(_explorer._stations[PLANET].pos, Vector3(0, 0, 10_000)))
			if _explorer._over_planet() != PLANET:
				_finish(false, "10 km from Cinder Orbital, the carrier should be over Cinder")
				return
			_go("open", 1.0)
		"open":
			_menu = BattleMenu.open(self, PLANET)
			_go("campaign", 0.5)
		"campaign":
			var c: Dictionary = Net.state.get("war", {}).get("campaigns", {}).get(PLANET, {})
			if c.is_empty() or not c.get("entrants", []).has("ashen"):
				_finish(false, "Cinder should have a campaign with the Ashen Collective in it: %s" % str(c))
				return
			if not _menu._camp_head.text.contains("Ashen Collective 0") or not _menu._camp_head.text.contains("Planet bonus"):
				_finish(false, "the screen should show the scoreboard and the planet's bonus: " + _menu._camp_head.text)
				return
			if not _menu._camp_status.text.contains("left in this campaign"):
				_finish(false, "the screen should show the time left: " + _menu._camp_status.text)
				return
			if not _buttons(_menu, "coming soon").is_empty() or _buttons(_menu, "Queue: Sector Defense").is_empty() or _buttons(_menu, "Queue: Facility Battles").is_empty() or _buttons(_menu, "Queue: Supremacy").is_empty() or _buttons(_menu, "Queue: Space Battles").is_empty():
				_finish(false, "every mode should be open to queue for")
				return
			var q := _buttons(_menu, "Queue: Sector Battles")
			if q.is_empty() or q[0].disabled:
				_finish(false, "there should be a Queue button for Sector Battles")
				return
			q[0].pressed.emit()
			_go("queued", 0.3)
		"queued":
			if BattleMenu.queued.get("mode", "") != "sector":
				if not _joined.is_empty():
					_finish(false, "matched before the wait for opponents was up")
				elif _step_clock > 5.0:
					_finish(false, "the server should say we're queued")
				return
			if _buttons(_menu, "Leave the Sector Battles queue").is_empty() or not _menu._camp_status.text.contains("In the queue for Sector Battles"):
				return # the screen catches up on its next refresh
			if int(Net.state.get("queues", {}).get(PLANET, {}).get("sector", {}).get("ashen", 0)) != 1:
				_finish(false, "the queue counts should show one Ashen pilot waiting")
				return
			_go("matched")
		"matched":
			if _joined.is_empty():
				if _step_clock > 15.0:
					_finish(false, "with no opponents, the AI should take us on after the wait")
				return
			if str(_joined.get("defender", "")) != "compact" or str(_joined.get("side", "")) != "a":
				_finish(false, "we should attack the holder's (Compact) AI: %s / %s" % [_joined.get("defender"), _joined.get("side")])
				return
			if is_instance_valid(_menu) and _menu.is_inside_tree() and not _menu.is_queued_for_deletion():
				return
			_go("view", 1.0)
		"view":
			var view_script = load("res://battle/battle_view.gd")
			if not view_script.active:
				_finish(false, "the RTS view should have opened for the match")
				return
			var battles: Array = Net.state.get("battles", [])
			if battles.filter(func(b): return b.get("campaign", false) and b.planet == PLANET).is_empty():
				_finish(false, "the match should be listed as a campaign battle on Cinder")
				return
			if not BattleMenu.queued.is_empty():
				_finish(false, "in a match, we're out of the queue")
				return
			_finish(true, "Cinder's campaign shows its scoreboard, bonus and modes; queued for Sector Battles from the carrier's orbit and, with no opponents, was matched against the Compact's AI; the RTS view opened by itself")


## Visible buttons under `root` whose text contains `text`.
func _buttons(root: Node, text: String) -> Array:
	return root.find_children("*", "Button", true, false).filter(func(b): return b.is_visible_in_tree() and b.text.contains(text))


func _finish(ok: bool, what: String) -> void:
	if _done:
		return
	_done = true
	print(("PASS " if ok else "FAIL ") + "campaign: " + what)
	get_tree().quit(0 if ok else 1)
