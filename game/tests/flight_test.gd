extends SceneTree
## Checks the flight model without a window or server:
##   godot --headless --path game --script res://tests/flight_test.gd
## Prints PASS or FAIL for each check and exits non-zero if any fail.

const Flight := preload("res://flight.gd")

var _failed := 0


func _init() -> void:
	_top_speed()
	_boost()
	_velocity_follows_nose()
	_drift_keeps_momentum()
	_pips()
	_phase_shift()
	_mass_lock()
	print("flight tests: %s" % ("FAIL" if _failed else "PASS"))
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failed += 1


func _fly(f, input: Dictionary, seconds: float, env := {"altitude": 1.0e9}) -> Array:
	var said := []
	var t := 0.0
	while t < seconds:
		said.append_array(f.step(input, env, 1.0 / 60.0))
		input.erase("boost")
		input.erase("phase")
		input.erase("stop")
		t += 1.0 / 60.0
	return said


func _top_speed() -> void:
	var f := Flight.new()
	f.pips = [2, 8, 2] # 4 pips to engines
	f.throttle = 1.0
	_fly(f, {}, 10.0)
	_check(absf(f.speed() - 280.0) < 1.0, "full throttle, 4 pips to engines: 280 m/s (got %.1f)" % f.speed())
	var g := Flight.new() # balanced power
	g.throttle = 1.0
	_fly(g, {}, 10.0)
	_check(g.speed() < 260.0 and g.speed() > 220.0, "balanced power is slower: %.1f m/s" % g.speed())


func _boost() -> void:
	var f := Flight.new()
	f.pips = [2, 8, 2]
	f.throttle = 1.0
	_fly(f, {}, 6.0)
	_fly(f, {"boost": true}, 1.0)
	_check(f.speed() > 380.0 and f.speed() <= 392.5, "boost reaches 392 m/s (got %.1f)" % f.speed())
	var said := _fly(f, {"boost": true}, 0.1)
	_check("Boost recharging" in said, "a second boost inside 5 seconds is refused")
	_fly(f, {}, 6.0)
	_check(absf(f.speed() - 280.0) < 2.0, "flight assist settles back to cruise after boost")
	_check(f.boost_ready(), "boost is ready again after 5 seconds")


func _velocity_follows_nose() -> void:
	var f := Flight.new()
	f.throttle = 1.0
	_fly(f, {}, 8.0)
	# Turn 90 degrees, then see where the ship is going.
	f.basis = Basis(Vector3.UP, PI / 2.0)
	_fly(f, {}, 1.0)
	var angle := rad_to_deg(f.velocity.angle_to(f.forward()))
	_check(angle < 5.0, "flight assist: velocity follows the nose within 1 s of a 90° turn (off by %.1f°)" % angle)


func _drift_keeps_momentum() -> void:
	var f := Flight.new()
	f.throttle = 1.0
	_fly(f, {}, 8.0)
	var before := f.velocity
	f.drift = true
	f.throttle = 0.0
	f.basis = Basis(Vector3.UP, PI / 2.0)
	_fly(f, {}, 2.0)
	_check(f.velocity.is_equal_approx(before), "drift: momentum carries on after turning with no thrust")


func _pips() -> void:
	var f := Flight.new()
	f.add_pip(Flight.ENG)
	_check(f.pips == [3, 6, 3], "one pip to engines takes half a pip from each other system")
	f.add_pip(Flight.ENG)
	f.add_pip(Flight.ENG)
	_check(f.pips[Flight.ENG] == 8 and f.pips[0] + f.pips[1] + f.pips[2] == 12, "engines cap at 4 pips and the total stays 6")
	f.reset_pips()
	_check(f.pips == [4, 4, 4], "balance power")


func _phase_shift() -> void:
	var f := Flight.new()
	f.throttle = 1.0
	var env := {"altitude": 6.0e7, "dest_distance": 6.0e10}
	var said := _fly(f, {"phase": true}, 4.5, env)
	_check("Phase-shift engaged" in said, "phase-shift engages after charging")
	# Fly for a minute with the destination 60 million km away: fast, but nowhere near instant.
	var travelled := 0.0
	for i in 3600:
		f.step({}, env, 1.0 / 60.0)
		travelled += f.speed() / 60.0
		env.altitude += f.speed() / 60.0
		env.dest_distance -= f.speed() / 60.0
	_check(travelled > 1.0e9 and env.dest_distance > 0.0, "a minute in phase-shift covers %.0f Mm, not the whole trip" % (travelled / 1.0e6))
	var near := Flight.new()
	near.throttle = 1.0
	var close := {"altitude": 1.0e9, "dest_distance": 50_000.0}
	_fly(near, {"phase": true}, 4.5, close)
	var arrived := false
	for i in 6000:
		for s in near.step({}, close, 1.0 / 60.0):
			arrived = arrived or s.begins_with("Arrived")
		close.dest_distance -= near.speed() / 60.0
		if arrived:
			break
	_check(arrived and close.dest_distance > 0.0, "phase-shift slows and drops before the destination, not past it")


func _mass_lock() -> void:
	var f := Flight.new()
	var said := f.step({"phase": true}, {"mass_locked": true, "altitude": 1.0e9}, 0.016)
	_check(f.mode == Flight.Mode.SUBLIGHT and said[0].begins_with("Mass locked"), "phase-shift refuses near a station")
