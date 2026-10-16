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

# Every Builder's home planet has a High Port in orbit, placed off the planet like Aster's.
const STATION_OFFSET := Vector3(1_000_000.0, 2_000_000.0, 7_000_000.0)

## Builder home planets other than Aster (Brisa, Corvo, ...), added as Builders join.
static var homes: Array = []


## A Builder home planet other than Aster: the `index`th one founded gets its own orbit around the star.
static func home_planet(id: String, planet_name: String, index: int) -> Dictionary:
	var a := 1.1 + index * 2.4
	var r := (90.0 + index * 35.0) * 1_000_000_000.0
	var h := absi(hash(id))
	return {"id": id, "name": planet_name, "kind": "planet", "pos": [cos(a) * r, sin(index * 1.7) * 3_000_000_000.0, sin(a) * r],
		"radius": 4_000_000.0 + (h % 4) * 1_000_000.0, "color": Color.from_hsv(fposmod(h * 0.618034, 1.0), 0.45, 0.62), "bands": false}


## A Builder planet by id: Aster or one of the homes, else an empty Dictionary.
static func builder_planet(id: String) -> Dictionary:
	for p in PLANETS + homes:
		if p.id == id:
			return p
	return {}


## Where a Builder planet's High Port orbits. Aster's is PORT_POS.
static func station_pos(planet_id: String) -> Array:
	if planet_id == "aster":
		return PORT_POS
	var p := builder_planet(planet_id)
	return offset(p.pos, STATION_OFFSET) if not p.is_empty() else PORT_POS


static func station_name(planet_name: String) -> String:
	return "%s High Port" % planet_name


static func bodies() -> Array:
	return [STAR] + PLANETS + homes


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
