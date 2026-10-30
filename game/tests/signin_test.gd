extends Node
## Accounts, side locks, war-supply receipts and the admins' dashboard, against a running galaxy
## server that requires sign-in (not a demo server), with an admin key:
##   cd server && SAVE_FILE=/tmp/signin.json ADMIN_KEY=k3y npm start   (delete /tmp/signin.json first)
##   godot --headless --path game res://tests/signin_test.tscn -- --admin-key=k3y
## The pilot "Sign P" signs in to the account "Sign Tester" through Net, opening it. Beside it, raw
## connections: a guest is refused, a wrong password is refused, and the account's Builder "Sign B"
## signs in, joins the Terran Compact and donates metal to the front at Cinder: its receipt comes
## back, and the pilot sees the front's war supply. The pilot then joins the Ashen Collective and
## tries to fight on Cinder: refused, the account took the Compact's side there. Last, the War
## terminal's dashboard page (admins) shows the fronts. `-- --server=ws://127.0.0.1:9000` for a
## server on another port. Prints PASS or FAIL and quits.

const WarInfo := preload("res://war_info.gd")
const DashboardPanel := preload("res://dashboard_panel.gd")
const ACCOUNT := "Sign Tester"
const PASSWORD := "secret1"

var _server := "ws://127.0.0.1:8080"
var _peers := {} # guest, wrong, builder -> WebSocketPeer
var _heard := {} # peer -> [messages]
var _errors: Array[String] = [] # the pilot's
var _step := "start"
var _clock := 0.0
var _wait := 0.5
var _done := false
var _dash: Control


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--server="):
			_server = arg.substr(9)
	Net.connect_to(_server, "explorer", "Sign P", ACCOUNT, PASSWORD)
	Net.server_error.connect(func(r):
		print("server error: ", r)
		_errors.append(r))
	for p in ["guest", "wrong", "builder"]:
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = 4 * 1024 * 1024
		ws.connect_to_url(_server)
		_peers[p] = ws
		_heard[p] = []


func _send(peer: String, msg: Dictionary) -> void:
	_peers[peer].send_text(JSON.stringify(msg))


func _got(peer: String, type: String) -> Dictionary:
	for m in _heard[peer]:
		if str(m.get("type", "")) == type:
			return m
	return {}


func _process(delta: float) -> void:
	for p in _peers:
		var ws: WebSocketPeer = _peers[p]
		ws.poll()
		while ws.get_available_packet_count() > 0:
			var m = JSON.parse_string(ws.get_packet().get_string_from_utf8())
			if m is Dictionary and str(m.get("type", "")) != "state":
				_heard[p].append(m)
	_clock += delta
	if _done:
		return
	if _clock > 60.0:
		_finish(false, "timed out at step " + _step)
		return
	_wait -= delta
	if _wait > 0.0:
		return
	_steps()


func _go(step: String, wait := 0.0) -> void:
	_step = step
	_wait = wait
	print("step: ", step)


func _steps() -> void:
	match _step:
		"start":
			if Net.state.is_empty():
				return
			if str(Net.account_info.get("name", "")) != ACCOUNT or not Net.account_info.get("characters", []).has("explorer/Sign P"):
				return _finish(false, "the welcome didn't carry the account: %s" % Net.account_info)
			if not Net.admin:
				return _finish(false, "run with -- --admin-key=<the server's ADMIN_KEY>")
			for p in _peers:
				if _peers[p].get_ready_state() != WebSocketPeer.STATE_OPEN:
					return
			_send("guest", {"type": "hello", "role": "explorer", "name": "Sign Guest"})
			_send("wrong", {"type": "hello", "role": "explorer", "name": "Sign P", "account": ACCOUNT, "password": "not it"})
			_send("builder", {"type": "hello", "role": "builder", "name": "Sign B", "account": ACCOUNT, "password": PASSWORD})
			_go("refusals", 0.5)
		"refusals":
			var guest := _got("guest", "error")
			var wrong := _got("wrong", "error")
			var welcome := _got("builder", "welcome")
			if guest.is_empty() or wrong.is_empty() or welcome.is_empty():
				return
			if str(guest.reason) != "sign in with an account to play on this server":
				return _finish(false, "the guest wasn't refused for signing in: " + str(guest.reason))
			if not str(wrong.reason).begins_with("wrong password for the account " + ACCOUNT):
				return _finish(false, "the wrong password wasn't refused: " + str(wrong.reason))
			if welcome.get("account", {}).get("characters", []).size() != 2:
				return _finish(false, "the Builder isn't the account's second character: %s" % welcome.get("account"))
			_send("builder", {"type": "choose_faction", "faction": "compact"})
			_go("donate", 0.5)
		"donate":
			_send("builder", {"type": "donate", "item": "metal", "qty": 50, "planet": "cinder"})
			_go("receipt", 0.3)
		"receipt":
			var r := _got("builder", "war_receipt")
			var err := _got("builder", "error")
			if not err.is_empty():
				return _finish(false, "the donation was refused: " + str(err.reason))
			if r.is_empty():
				return
			if str(r.receipt.planet) != "cinder" or float(r.receipt.base) != 5.0:
				return _finish(false, "the receipt is wrong: %s" % r.receipt)
			_go("front", 0.2)
		"front":
			var lines := WarInfo.supply_lines("cinder")
			if lines.is_empty():
				return
			if not str(lines[0]).begins_with("Terran Compact ") or not str(lines[0]).contains("Builder donations"):
				return _finish(false, "the front's war supply reads wrong: %s" % [lines])
			print("front: ", lines[0])
			Net.send({"type": "choose_faction", "faction": "ashen"})
			_go("side", 0.5)
		"side":
			_errors.clear()
			Net.send({"type": "battle_start", "planet": "cinder", "sector": "cinder-2"})
			_go("refused", 0.3)
		"refused":
			if _errors.is_empty():
				return
			if not _errors[0].begins_with("your account took the Terran Compact's side on Cinder this campaign (Sign B)"):
				return _finish(false, "the side lock didn't refuse the battle: " + _errors[0])
			_dash = DashboardPanel.new()
			_dash.size = Vector2(1200, 800)
			add_child(_dash)
			_go("dashboard", 0.2)
		"dashboard":
			var d: Dictionary = _dash.last()
			if d.is_empty():
				return
			if d.get("fronts", []).is_empty() or _dash._fronts.get_child_count() == 0:
				return _finish(false, "the dashboard shows no fronts")
			if not _dash._head.text.begins_with("Online: 1 pilots and 1 Builders, on 1 accounts and 0 as guests."):
				return _finish(false, "the dashboard's head reads: " + _dash._head.text)
			var cinder: Dictionary = {}
			for f in d.fronts:
				if str(f.planet) == "cinder":
					cinder = f
			if float(cinder.get("supply", {}).get("factions", {}).get("compact", {}).get("total", 0)) <= 0.0:
				return _finish(false, "the dashboard has no war supply on Cinder")
			print("dashboard: ", _dash._head.text.get_slice("\n", 0))
			_finish(true, "accounts, side locks, receipts and the dashboard work")


func _finish(ok: bool, why: String) -> void:
	_done = true
	print(("PASS: " if ok else "FAIL: ") + why)
	get_tree().quit(0 if ok else 1)
