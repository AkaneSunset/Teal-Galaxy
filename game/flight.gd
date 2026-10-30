extends RefCounted
## Flight model for one ship: sub-light flight, boost, phase-shift drive and the power distributor.
## Knows nothing about the scene, so tests can drive it directly.
##
## Sub-light flight is Newtonian underneath. With flight assist on (the default) the ship's velocity
## is steered toward where the nose points, so it flies where it points instead of sliding along its
## old path. Drift turns flight assist off: thrust adds to momentum and nothing cancels it.
##
## Speeds follow Elite Dangerous stock small ships: about 280 m/s cruise at full engine power and a
## 1.4x boost with a 5 second minimum between boosts.

# A small-class ship. Larger classes will fit bigger parts: more mass, power and shields, not more speed.
const SMALL_SHIP := {
	"class": "Small",
	"top_speed": 280.0, # m/s with full engine power (4 pips)
	"zero_pip_speed": 0.72, # fraction of top speed with no engine power
	"reverse": 0.5, # reverse speed as a fraction of forward
	"strafe": 0.45, # lateral and vertical speed as a fraction of forward
	"boost_speed": 392.0,
	"boost_time": 1.8, # seconds of boost thrust
	"boost_cooldown": 5.0, # minimum seconds between boosts
	"boost_energy": 12.0, # drawn from the engine capacitor
	"accel": 70.0, # m/s² forward
	"accel_lateral": 40.0, # m/s² on the other axes
	"align_rate": 3.2, # rad/s: how hard flight assist swings velocity onto the nose
	"pitch": 0.733, # rad/s at full deflection (42°/s)
	"yaw": 0.384, # 22°/s
	"roll": 1.92, # 110°/s
	"phase_charge": 4.0, # seconds to charge the phase-shift drive
	"phase_accel": 0.55, # how quickly phase speed climbs toward its limit (1/s); a better drive is higher
	"shields": 100.0,
	"hull": 100.0,
}

# A fleet carrier, the demo's ship: about 260 m of hull with a flight deck, hangars and a crew. It
# flies like the small ship but heavier: slower to turn and to get going, a gentler boost that
# lasts longer. Its phase-shift drive is the same, so trips across the system take as long.
const CARRIER := {
	"class": "Carrier",
	"top_speed": 220.0,
	"zero_pip_speed": 0.72,
	"reverse": 0.4,
	"strafe": 0.3,
	"boost_speed": 330.0,
	"boost_time": 3.5,
	"boost_cooldown": 8.0,
	"boost_energy": 12.0,
	"accel": 22.0, # 0 to cruise in about 10 s
	"accel_lateral": 10.0,
	"align_rate": 0.9, # the hull swings its momentum round slowly
	"pitch": 0.26, # 15 degrees a second
	"yaw": 0.17, # 10 degrees a second
	"roll": 0.45,
	"phase_charge": 6.0,
	"phase_accel": 0.55,
	"shields": 100.0,
	"hull": 100.0,
}

const PHASE_MIN := 1_000.0 # m/s
const PHASE_MAX := 2001.0 * 299_792_458.0
const PHASE_PER_ALTITUDE := 0.5 # phase speed limit per metre from the nearest body, per second
const PHASE_ARRIVE_SECONDS := 5.0 # slow so the destination is never less than this far ahead
const PHASE_DROP_DISTANCE := 2_000.0 # auto-drop this close to the destination
const MASS_LOCK_DISTANCE := 5_000.0

const HALF_PIPS := 12 # 6 pips in half steps, as in Elite
const MAX_HALF_PIPS := 8 # 4 pips
const SYS := 0
const ENG := 1
const WEP := 2
const CAPACITOR := [60.0, 24.0, 40.0] # SYS (shield recharge), ENG (boost), WEP (mining laser)

enum Mode { SUBLIGHT, CHARGING, PHASE }

var stats := SMALL_SHIP
var basis := Basis()
var velocity := Vector3.ZERO
var throttle := 0.0 # -1..1; negative is reverse
var drift := false
var mode := Mode.SUBLIGHT
var phase_speed := 0.0
var charge_left := 0.0
var boost_left := 0.0
var boost_cooldown := 0.0
var pips := [4, 4, 4] # half pips for SYS, ENG, WEP
var capacitor := [60.0, 24.0, 40.0]
var shields := 100.0
var hull := 100.0


func forward() -> Vector3:
	return -basis.z


func speed() -> float:
	return velocity.length()


func engine_factor() -> float:
	return lerpf(stats.zero_pip_speed, 1.0, pips[ENG] / float(MAX_HALF_PIPS))


func top_speed() -> float:
	return stats.top_speed * engine_factor()


func boost_ready() -> bool:
	return boost_cooldown <= 0.0 and capacitor[ENG] >= stats.boost_energy


## One frame of flight. `input` holds pitch, yaw, roll, strafe, lift (each -1..1),
## throttle_rate (-1..1, throttle change per second), and the one-shot flags boost, stop, phase.
## `env` holds mass_locked (bool), altitude (metres to the nearest body's surface) and
## dest_distance (metres to the route destination, or -1).
## Returns messages for the pilot.
func step(input: Dictionary, env: Dictionary, dt: float) -> Array:
	var said := []
	_recharge(dt)
	boost_cooldown = maxf(0.0, boost_cooldown - dt)

	# Turning. The phase-shift drive makes the ship sluggish, as supercruise does.
	var turn := engine_factor() * (0.6 if mode == Mode.PHASE else 1.0)
	basis = basis * Basis(Vector3.RIGHT, input.get("pitch", 0.0) * stats.pitch * turn * dt)
	basis = basis * Basis(Vector3.UP, input.get("yaw", 0.0) * stats.yaw * turn * dt)
	basis = basis * Basis(Vector3.BACK, -input.get("roll", 0.0) * stats.roll * turn * dt)
	basis = basis.orthonormalized()

	throttle = clampf(throttle + input.get("throttle_rate", 0.0) * dt, -1.0, 1.0)
	if input.get("stop", false):
		throttle = 0.0

	if input.get("phase", false):
		said.append(_toggle_phase(env))

	match mode:
		Mode.PHASE:
			said.append_array(_phase_step(env, dt))
		Mode.CHARGING:
			if env.get("mass_locked", false):
				mode = Mode.SUBLIGHT
				said.append("Phase-shift cancelled: mass locked")
			else:
				charge_left -= dt
				if charge_left <= 0.0:
					mode = Mode.PHASE
					phase_speed = maxf(speed(), PHASE_MIN)
					throttle = maxf(throttle, 0.5)
					said.append("Phase-shift engaged")
			_sublight_step(input, dt, said)
		_:
			_sublight_step(input, dt, said)
	return said


func _sublight_step(input: Dictionary, dt: float, said: Array) -> void:
	if input.get("boost", false):
		if boost_ready():
			capacitor[ENG] -= stats.boost_energy
			boost_left = stats.boost_time
			boost_cooldown = stats.boost_cooldown
		elif boost_cooldown > 0.0:
			said.append("Boost recharging")
		else:
			said.append("Not enough engine power to boost")
	boost_left = maxf(0.0, boost_left - dt)
	var boosting := boost_left > 0.0

	var top := top_speed()
	var forward_cmd: float = throttle * (top if throttle >= 0.0 else top * stats.reverse)
	var accel: float = stats.accel
	if boosting:
		forward_cmd = stats.boost_speed
		accel *= 3.0
	var lateral: float = top * stats.strafe
	var limit: float = stats.boost_speed if boosting else top

	if drift:
		# Flight assist off: thrusters push, nothing pulls the ship back onto its nose.
		var thrust := Vector3(input.get("strafe", 0.0) * stats.accel_lateral, input.get("lift", 0.0) * stats.accel_lateral, 0.0)
		if boosting:
			thrust.z = -accel
		else:
			thrust.z = -signf(forward_cmd) * accel if absf(forward_cmd) > 1.0 else 0.0
		if input.get("stop", false):
			velocity = velocity.move_toward(Vector3.ZERO, stats.accel_lateral * dt)
		velocity = (velocity + basis * thrust * dt).limit_length(maxf(limit, speed() - accel * dt))
		return

	# Flight assist on: the velocity we want, in ship space, from throttle and strafe.
	var want_local := Vector3(input.get("strafe", 0.0) * lateral, input.get("lift", 0.0) * lateral, -forward_cmd)
	var want := basis * want_local
	var have := speed()
	var want_speed := want.length()
	# Speed: speed up or slow down at the thrusters' rate.
	var rate: float = accel if want_speed >= have else accel * 1.2
	var new_speed := move_toward(have, want_speed, rate * dt)
	# Direction: swing the velocity onto the wanted direction. This is what makes the ship
	# fly where it points instead of carrying its old momentum.
	var dir := velocity.normalized() if have > 0.01 else want.normalized()
	if want_speed > 0.01 and have > 0.01:
		var angle := dir.angle_to(want / want_speed)
		if angle > 0.0001:
			dir = dir.slerp(want / want_speed, minf(1.0, stats.align_rate * dt / angle)).normalized()
	elif want_speed > 0.01:
		dir = want / want_speed
	velocity = dir * new_speed


func _toggle_phase(env: Dictionary) -> String:
	match mode:
		Mode.PHASE:
			_drop()
			return "Dropped to sub-light"
		Mode.CHARGING:
			mode = Mode.SUBLIGHT
			return "Phase-shift cancelled"
	if env.get("mass_locked", false):
		return "Mass locked: fly %d km clear of the station first" % int(MASS_LOCK_DISTANCE / 1000.0)
	mode = Mode.CHARGING
	charge_left = stats.phase_charge
	return "Phase-shift charging"


func _phase_step(env: Dictionary, dt: float) -> Array:
	var said := []
	var altitude: float = env.get("altitude", INF)
	var dest: float = env.get("dest_distance", -1.0)
	# The drive's limit grows with distance from gravity wells, so leaving a planet is a climb,
	# open space is fast, and arriving is a long deceleration. Distance sets the trip time.
	var limit := clampf(altitude * PHASE_PER_ALTITUDE, PHASE_MIN, PHASE_MAX)
	if dest >= 0.0:
		limit = minf(limit, maxf(PHASE_MIN, dest / PHASE_ARRIVE_SECONDS))
	var target := lerpf(PHASE_MIN, limit, clampf(throttle, 0.0, 1.0))
	# Acceleration tapers off as speed nears the limit; slowing down is quicker so arrivals don't overshoot.
	var k: float = stats.phase_accel if target > phase_speed else 1.5
	phase_speed += (target - phase_speed) * (1.0 - exp(-k * dt))
	velocity = forward() * phase_speed

	if dest >= 0.0 and dest < PHASE_DROP_DISTANCE:
		_drop()
		said.append("Arrived: dropped to sub-light")
	elif altitude < phase_speed * 2.0 and altitude < 200_000.0:
		_drop()
		damage(25.0)
		said.append("Emergency drop: too close to a body")
	return said


## Rough time to reach a destination `distance` metres away (past its standoff) in the phase-shift drive:
## cruise at the current speed until the arrival slowdown begins, then the slowdown itself.
func phase_eta(distance: float) -> float:
	var v := maxf(phase_speed, PHASE_MIN)
	var slow_from := v * PHASE_ARRIVE_SECONDS
	var cruise := maxf(0.0, distance - slow_from) / v
	var slowing := PHASE_ARRIVE_SECONDS * log(maxf(minf(distance, slow_from), PHASE_DROP_DISTANCE) / PHASE_DROP_DISTANCE)
	return cruise + slowing


func _drop() -> void:
	mode = Mode.SUBLIGHT
	phase_speed = 0.0
	velocity = forward() * top_speed() * 0.75
	throttle = 0.75
	boost_cooldown = maxf(boost_cooldown, 2.0)


func _recharge(dt: float) -> void:
	# Each capacitor refills at a rate set by its share of the power.
	for i in 3:
		var rate: float = 0.6 + 3.0 * (pips[i] / float(MAX_HALF_PIPS))
		if i == SYS:
			rate *= 2.0
		capacitor[i] = minf(CAPACITOR[i], capacitor[i] + rate * dt)
	# Shields draw from the SYS capacitor while they recover.
	if shields < stats.shields and capacitor[SYS] > 1.0:
		var amount := minf(stats.shields - shields, minf(capacitor[SYS], (1.0 + 4.0 * pips[SYS] / float(MAX_HALF_PIPS)) * dt))
		shields += amount
		capacitor[SYS] -= amount * 0.5


## Uses energy from a capacitor. Returns false when there isn't enough.
func draw(system: int, amount: float) -> bool:
	if capacitor[system] < amount:
		return false
	capacitor[system] -= amount
	return true


## Moves one pip to `system`, taking half a pip from each of the other two, as in Elite Dangerous.
func add_pip(system: int) -> void:
	var room := MAX_HALF_PIPS - int(pips[system])
	var want := mini(2, room)
	for n in want:
		var donor := -1
		for i in 3:
			if i != system and pips[i] > 0 and (donor < 0 or pips[i] > pips[donor]):
				donor = i
		if donor < 0:
			return
		pips[donor] -= 1
		pips[system] += 1


func reset_pips() -> void:
	pips = [4, 4, 4]


func damage(amount: float) -> void:
	var to_shields := minf(shields, amount)
	shields -= to_shields
	hull = maxf(0.0, hull - (amount - to_shields))


func repair() -> void:
	shields = stats.shields
	hull = stats.hull
	velocity = Vector3.ZERO
	throttle = 0.0
	mode = Mode.SUBLIGHT
	boost_left = 0.0
	capacitor = CAPACITOR.duplicate()
