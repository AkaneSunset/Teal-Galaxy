extends RefCounted
## The Teal Prime system at roughly real scale, plus distance and speed formatting.
##
## Positions are metres from the star, kept as plain GDScript floats (64-bit) in [x, y, z] arrays.
## Godot's Vector3 is 32-bit, which can't place a ship precisely 60 million km from the star, so the
## explorer keeps the ship at the scene origin and draws everything relative to it.

const C := 299_792_458.0 # speed of light, m/s
const LS := C # one light second, m
const AU := 149_597_870_700.0

const STAR := {
	"id": "teal-prime", "name": "Teal Prime", "kind": "star",
	"pos": [0.0, 0.0, 0.0], "radius": 696_000_000.0, "color": Color(1.0, 0.85, 0.55),
}
const PLANETS := [
	{"id": "cinder", "name": "Cinder", "kind": "planet", "pos": [41_000_000_000.0, 2_000_000_000.0, 18_000_000_000.0],
		"radius": 2_400_000.0, "color": Color(0.75, 0.42, 0.28), "bands": false},
	{"id": "aster", "name": "Aster", "kind": "planet", "pos": [0.0, 0.0, -60_000_000_000.0],
		"radius": 6_000_000.0, "color": Color(0.15, 0.55, 0.55), "bands": false},
	{"id": "vesper", "name": "Vesper", "kind": "planet", "pos": [-150_000_000_000.0, -9_000_000_000.0, -120_000_000_000.0],
		"radius": 58_000_000.0, "color": Color(0.78, 0.66, 0.5), "bands": true},
]

# Places near Aster. The Spaceport orbits about 1,400 km above the surface.
const PORT_POS := [1_000_000.0, 2_000_000.0, -60_000_000_000.0 + 7_000_000.0]
const FIELD_POS := [1_000_000.0 + 12_000.0, 2_000_000.0 + 1_500.0, -60_000_000_000.0 + 7_000_000.0 - 6_000.0]
const SPAWN_POS := [1_000_000.0, 2_000_000.0 + 300.0, -60_000_000_000.0 + 7_000_000.0 + 4_000.0]

const PORT_NAME := "Aster High Port"
const FIELD_NAME := "Aster Ice Field"


## Facilities a Builder builds on Aster orbit in a ring 25 km around the Spaceport, one per slot.
static func facility_pos(slot: int) -> Array:
	var a := slot * TAU / 6.0
	return [PORT_POS[0] + cos(a) * 25_000.0, PORT_POS[1] + (slot % 2) * 1_500.0, PORT_POS[2] + sin(a) * 25_000.0]


## Satellite sites off Aster orbit in a wider ring, 40 km around the Spaceport, one per orbit slot.
static func site_pos(orbit: int) -> Array:
	var a := (orbit + 0.5) * TAU / 8.0
	return [PORT_POS[0] + cos(a) * 40_000.0, PORT_POS[1] + (orbit % 2) * 2_000.0 - 1_000.0, PORT_POS[2] + sin(a) * 40_000.0]


static func bodies() -> Array:
	return [STAR] + PLANETS


static func diff(a: Array, b: Array) -> Vector3:
	## a - b as a 32-bit vector. Only precise when the result is small, or used as a direction.
	return Vector3(a[0] - b[0], a[1] - b[1], a[2] - b[2])


static func distance(a: Array, b: Array) -> float:
	var dx: float = a[0] - b[0]
	var dy: float = a[1] - b[1]
	var dz: float = a[2] - b[2]
	return sqrt(dx * dx + dy * dy + dz * dz)


static func offset(a: Array, v: Vector3) -> Array:
	return [a[0] + v.x, a[1] + v.y, a[2] + v.z]


static func format_distance(m: float) -> String:
	if m < 1_000.0:
		return "%d m" % m
	if m < 1_000_000.0:
		return "%.1f km" % (m / 1_000.0)
	if m < 0.1 * LS:
		return "%.1f Mm" % (m / 1_000_000.0)
	if m < 0.1 * AU:
		return "%.1f ls" % (m / LS)
	return "%.2f AU" % (m / AU)


static func format_speed(mps: float) -> String:
	if mps < 1_000.0:
		return "%d m/s" % mps
	if mps < 0.1 * C:
		return "%.1f km/s" % (mps / 1_000.0)
	return "%.2f c" % (mps / C)


static func format_time(seconds: float) -> String:
	if seconds < 0 or seconds > 359_999:
		return "--:--"
	var s := int(seconds)
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]
