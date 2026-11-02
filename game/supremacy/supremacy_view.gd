class_name SupremacyView
extends FacilityView
## Supremacy, on foot in first person (server/supremacy.js runs it), built on the Facility Battles
## view: the same controls, classes and HUD. Two phases a round: on the ground, capture the control
## points to fill your bar; then the winners board the losers' capital ship (a shuttle at their drop
## ship and at each point they hold) and try to destroy its reactor, breaching blast doors on the way.
## First to 2 rounds. Earn battle credits (kills, captures) to come back as an elite trooper.
## Opened on supremacy_joined; the world is rebuilt when the fight moves to a ship and back.

var _current := "" # which map the world shows: "ground", "ship-a" or "ship-d"
var _shuttles: Array = [] # Node3D markers while boarding
var _breakables: Array = [] # [{"node", "label", "kind"}] aboard


## Opens the view for the match the server just put the pilot in (`joined`: supremacy_joined).
static func open(host: Node, joined: Dictionary) -> FacilityView:
	var v := SupremacyView.new()
	v.info = joined
	v.prefix = "supremacy"
	v.info["modeName"] = "Supremacy"
	active = true
	host.get_tree().root.add_child.call_deferred(v)
	return v


func _ready() -> void:
	_current = "ground"
	super._ready()
	var b: Dictionary = info.get("bonus", {}) if info.get("bonus") is Dictionary else {}
	if not b.is_empty():
		_say("Planet bonus for %s: %s. %s" % [_side_name(str(b.get("side", "d"))) if b.get("side") != null else "the holder", str(b.get("name", "")), str(b.get("text", ""))], Color(0.8, 0.85, 1.0))


func _map() -> Dictionary:
	var maps: Dictionary = info.get("maps", {})
	return maps.get(_current, info.get("map", {}))


func _floor_colour() -> Color:
	return Color(0.2, 0.21, 0.24) if _current.begins_with("ship") else Color(0.33, 0.31, 0.24)


func _snapshot(msg: Dictionary) -> void:
	var m := str(msg.get("map", "ground"))
	if m != _current:
		_current = m
		_shuttles = []
		_breakables = []
		rebuild_world()
		if m.begins_with("ship"):
			var aboard := m.substr(5)
			_say("Aboard %s: %s" % [str(info.get("shipNames", {}).get(aboard, "the ship")), "breach the blast doors and destroy the reactor" if aboard != side else "defend the reactor"], Color(1.0, 0.75, 0.4))
		else:
			_say("Back to the ground: the bars are reset", Color(1.0, 0.75, 0.4))
	super._snapshot(msg)


# --- The map --------------------------------------------------------------------------------------

func _build_objectives(m: Dictionary) -> void:
	if str(m.get("kind", "")) == "ship":
		# Blast doors (red, to breach) and the reactor (glowing), solid until destroyed.
		for d in m.get("blastDoors", []):
			var node := _box(_world, Vector3(float(d[2]), float(d[4]), float(d[3])), Vector3(float(d[0]), float(d[4]) / 2.0, float(d[1])), Color(0.7, 0.2, 0.18))
			_breakables.append({"node": node, "label": _tag(node, "BLAST DOOR", 2.2, Color(1.0, 0.5, 0.4), 40), "kind": "door"})
		var r: Array = m.get("reactor", [130, 18, 6, 6, 3])
		var core := _box(_world, Vector3(float(r[2]), float(r[4]), float(r[3])), Vector3(float(r[0]), float(r[4]) / 2.0, float(r[1])), Color(0.3, 0.8, 1.0), true, 2.5)
		_breakables.append({"node": core, "label": _tag(core, "REACTOR", 3.0, Color(0.5, 0.9, 1.0), 60), "kind": "reactor"})
		return
	# The ground: the control points, and each side's drop ship hovering at its end.
	var names := "ABCDE"
	var i := 0
	for p in m.get("points", []):
		var root := Node3D.new()
		root.position = Vector3(float(p[0]), 0, float(p[1]))
		_world.add_child(root)
		var disc := _disc(root, 6.0, Vector3(0, 0.04, 0), Color(0.9, 0.9, 0.9, 0.3))
		_box(root, Vector3(0.3, 8, 0.3), Vector3(0, 4, 0), Color(0.9, 0.9, 0.9), false, 2.0)
		_points.append({"node": root, "disc": disc, "label": _tag(root, names[i], 8.8, Color.WHITE, 110)})
		i += 1
	for s in ["a", "d"]:
		var at: Array = m.get("drop", {}).get(s, [80, 6])
		var ship := Node3D.new()
		ship.position = Vector3(float(at[0]), 9.0, float(at[1]))
		_world.add_child(ship)
		_box(ship, Vector3(10, 3, 16), Vector3.ZERO, _side_colour(s).darkened(0.5), false)
		_box(ship, Vector3(22, 0.5, 4), Vector3(0, 0.5, 2), _side_colour(s).darkened(0.3), false)
		_tag(ship, "DROP SHIP", 3.0, _side_colour(s), 60)


func _update_facility(msg: Dictionary) -> void:
	super._update_facility(msg)
	# Boarding shuttles, while the window's open.
	var shuttles: Array = msg.get("shuttles", []) if str(msg.get("phase", "")) == "boarding" else []
	if shuttles.size() != _shuttles.size():
		for n in _shuttles:
			(n as Node3D).queue_free()
		_shuttles = []
		var winner := str(msg.get("winner", ""))
		for p in shuttles:
			var root := Node3D.new()
			root.position = Vector3(float(p[0]), 0, float(p[1]))
			_world.add_child(root)
			_disc(root, 5.0, Vector3(0, 0.05, 0), Color(_side_colour(winner), 0.35))
			_box(root, Vector3(4, 2.5, 7), Vector3(0, 3.5, 0), _side_colour(winner).darkened(0.3), false, 0.5)
			_box(root, Vector3(0.2, 14, 0.2), Vector3(0, 7, 0), _side_colour(winner), false, 3.0)
			_tag(root, "SHUTTLE", 6.0, _side_colour(winner), 60)
			_shuttles.append(root)
	# Blast doors and the reactor: their health, and gone once destroyed.
	var br: Array = msg.get("breakables", [])
	for i in mini(br.size(), _breakables.size()):
		var hp := int(br[i][1])
		var node: Node3D = _breakables[i].node
		var label: Label3D = _breakables[i].label
		var gone := hp <= 0
		node.visible = not gone
		var shape: CollisionShape3D = node.get_child(0)
		shape.disabled = gone
		label.text = "%s  %d%%" % ["REACTOR" if str(br[i][0]) == "reactor" else "BLAST DOOR", roundi(100.0 * hp / maxf(1.0, float(br[i][2])))]


# --- Bodies: fodder bots in each faction's design, elite troopers with a gold band ---------------------

func _dress_body(root: Node3D, row: Array) -> void:
	var fodder := row.size() > 13 and int(row[13]) == 1
	var elite := row.size() > 12 and int(row[12]) == 1
	var tint := _side_colour(str(row[2]))
	if elite:
		_box(root, Vector3(0.9, 0.12, 0.9), Vector3(0, 1.25, 0), Color(1.0, 0.8, 0.25), false, 2.0)
	if not fodder:
		return
	# The capsule goes; a cheap bot stands in.
	(root.get_child(0) as Node3D).visible = false
	var f = _faction(str(row[2]))
	match str(f):
		"compact": # Drudge: a boxy walker
			_box(root, Vector3(0.7, 0.8, 0.5), Vector3(0, 1.0, 0), tint.darkened(0.4), false)
			_box(root, Vector3(0.15, 0.6, 0.15), Vector3(-0.2, 0.3, 0), Color(0.3, 0.3, 0.3), false)
			_box(root, Vector3(0.15, 0.6, 0.15), Vector3(0.2, 0.3, 0), Color(0.3, 0.3, 0.3), false)
		"ashen": # Skitter: low, on four legs
			_box(root, Vector3(0.9, 0.35, 0.9), Vector3(0, 0.6, 0), tint.darkened(0.4), false)
			for k in 4:
				_box(root, Vector3(0.1, 0.5, 0.1), Vector3(-0.45 if k % 2 == 0 else 0.45, 0.25, -0.45 if k < 2 else 0.45), Color(0.25, 0.2, 0.2), false)
		"luminar": # Wisp: a floating orb
			var orb := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.35
			sm.height = 0.7
			sm.material = _mat(tint.lightened(0.2), 1.5)
			orb.mesh = sm
			orb.position.y = 1.3
			root.add_child(orb)
		_: # Husk (Coma) and the militia's bots: tall and thin
			_box(root, Vector3(0.3, 1.8, 0.3), Vector3(0, 0.9, 0), tint.darkened(0.45), false)
			_box(root, Vector3(0.5, 0.25, 0.3), Vector3(0, 1.75, 0), tint.darkened(0.2), false)
	_box(root, Vector3(0.25, 0.1, 0.1), Vector3(0, 1.1, -0.3), Color(1.0, 0.3, 0.2), false, 3.0)


# --- HUD ----------------------------------------------------------------------------------------------

func _top_text() -> String:
	var s := _state
	var rounds: Dictionary = s.get("rounds", {"a": 0, "d": 0})
	var head := "SUPREMACY · %s   ·   Round %d   %s %d – %d %s (first to %d)" % [str(_map().get("name", "")), int(s.get("round", 1)), _side_name("a"), int(rounds.get("a", 0)), int(rounds.get("d", 0)), _side_name("d"), int(info.get("rounds", 2))]
	var phase := str(s.get("phase", "ground"))
	var left := _time(int(s.get("left", 0)))
	match phase:
		"boarding":
			return head + "   ·   BOARDING  %s" % left
		"ship":
			var br: Array = s.get("breakables", [])
			var reactor := 100
			for b in br:
				if str(b[0]) == "reactor":
					reactor = roundi(100.0 * float(b[1]) / maxf(1.0, float(b[2])))
			return head + "   ·   Reactor %d%%   ·   %s" % [reactor, left]
	var bars: Dictionary = s.get("bars", {"a": 0, "d": 0})
	return head + "   ·   Bars %d%% – %d%%   ·   %s" % [int(bars.get("a", 0)), int(bars.get("d", 0)), left]


func _objective_text() -> String:
	var s := _state
	var mine := str(s.get("winner", "")) == side
	match str(s.get("phase", "ground")):
		"boarding":
			return "Get to a shuttle: every pilot aboard adds 15 s to the attack" if mine else "They're boarding: get to the shuttles and stop them"
		"ship":
			var doors := 0
			for b in s.get("breakables", []):
				if str(b[0]) == "door" and int(b[1]) > 0:
					doors += 1
			return ("Breach the blast doors (%d left) and destroy the reactor" if mine else "Defend the reactor (%d blast doors left)") % doors
	var parts: Array = []
	var names := "ABCDE"
	var pts = s.get("points")
	if pts is Array:
		for i in pts.size():
			var o = pts[i][0]
			parts.append("%s: %s" % [names[i], "neutral" if o == null else ("yours" if str(o) == side else "theirs")])
	return "Hold more points to fill your bar   ·   " + "   ".join(parts)


func _update_vitals() -> void:
	super._update_vitals()
	var credits := int(_me.get("credits", 0))
	var cost := int(info.get("eliteCost", 150))
	_streak_label.text = ("ELITE TROOPER   ·   " if bool(_me.get("elite", false)) else "") + "Battle credits %d%s" % [credits, ("   ·   elite trooper ready (L)" if credits >= cost and not bool(_me.get("wantElite", false)) else ("   ·   elite next respawn" if bool(_me.get("wantElite", false)) else ""))] + ("   ·   " + _streak_label.text if (_me.get("earned", []) as Array).size() > 0 else "")


func _open_classes(first: bool) -> void:
	super._open_classes(first)
	var credits := int(_me.get("credits", 0))
	var cost := int(info.get("eliteCost", 150))
	var want := bool(_me.get("wantElite", false))
	var b := Button.new()
	b.text = ("Come back as an elite trooper (%d credits, you have %d)" % [cost, credits]) if not want else "Elite trooper next respawn (cancel)"
	b.disabled = credits < cost and not want
	b.tooltip_text = "Tougher (150 health, more shield) and better armed (30% more damage)"
	b.pressed.connect(func(): set_elite(not want))
	_class_list.add_child(b)
	_class_list.move_child(b, 1)


## Asks to come back as an elite trooper (or not) on the next respawn.
func set_elite(on: bool) -> void:
	Net.send({"type": "supremacy_elite", "match": match_id, "on": on})
	_me["wantElite"] = on
	_say("Elite trooper next respawn" if on else "No elite trooper next time", Color(1.0, 0.8, 0.3))
	_close_classes()


func _minimap_objectives(map_ctl: Control, k: float) -> void:
	var s := _state
	var pts = s.get("points")
	var j := 0
	for p in _map().get("points", []):
		var o = pts[j][0] if pts is Array and j < pts.size() else null
		map_ctl.draw_circle(Vector2(float(p[0]), float(p[1])) * k, 6.0 * k, Color(0.9, 0.9, 0.9, 0.35) if o == null else Color(_side_colour(str(o)), 0.5))
		j += 1
	if str(s.get("phase", "")) == "boarding":
		for p in s.get("shuttles", []):
			map_ctl.draw_circle(Vector2(float(p[0]), float(p[1])) * k, 5.0 * k, Color(_side_colour(str(s.get("winner", ""))), 0.7))
	var r = _map().get("reactor")
	if r is Array:
		map_ctl.draw_rect(Rect2(Vector2(float(r[0]) - float(r[2]) / 2, float(r[1]) - float(r[3]) / 2) * k, Vector2(float(r[2]), float(r[3])) * k), Color(0.3, 0.8, 1.0))
	var br: Array = s.get("breakables", [])
	var i := 0
	for d in _map().get("blastDoors", []):
		if i < br.size() and int(br[i][1]) > 0:
			map_ctl.draw_rect(Rect2(Vector2(float(d[0]) - float(d[2]) / 2, float(d[1]) - float(d[3]) / 2) * k, Vector2(float(d[2]), float(d[3])) * k), Color(0.9, 0.3, 0.25))
		i += 1
