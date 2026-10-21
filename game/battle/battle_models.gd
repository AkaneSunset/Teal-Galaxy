extends RefCounted
## The units and structures of a sector battle, built in code from boxes, cylinders and cones as
## single meshes (one draw call per type with a MultiMesh). Fronts face +Z (a unit's heading 0 on
## the server), origins sit on the ground.
##
## Every vertex colour's alpha says how a part is painted (see SHADER): PLAIN parts keep their
## colour, PAINT parts take the side's colour (the MultiMesh instance's custom data), SIDE_GLOW
## parts glow in it, and GLOW parts glow in their own colour (mass cores, lights). The custom
## data's alpha darkens a whole instance (wrecks) and turns its glow off.
##
## A type may have a `top` (a turret) that turns on its own: drawn with its own MultiMesh at
## `top_at` above the unit's origin, yawed toward what it shoots at.

const PLAIN := 0.0
const GLOW := 0.5
const SIDE_GLOW := 0.75
const PAINT := 1.0

const DARK := Color(0.27, 0.28, 0.3)
const GREY := Color(0.5, 0.52, 0.55)
const LIGHT := Color(0.74, 0.76, 0.78)
const WHITE := Color(0.9, 0.9, 0.88)
const GLASS := Color(0.08, 0.12, 0.16)
const MASS := Color(0.35, 1.0, 0.35)
const AMBER := Color(1.0, 0.6, 0.15)
const CYAN := Color(0.35, 0.95, 1.0)

## How high air units fly over the ground, metres.
const AIR_HEIGHT := 18.0

const SHADER := """
shader_type spatial;
render_mode cull_disabled;
varying vec4 tint;
void vertex() {
	tint = INSTANCE_CUSTOM;
}
void fragment() {
	float m = COLOR.a;
	vec3 base = COLOR.rgb;
	vec3 col = base;
	vec3 emit = vec3(0.0);
	if (m > 0.85) {
		col = tint.rgb * (0.75 + base.g * 1.6);
	} else if (m > 0.6) {
		col = tint.rgb;
		emit = tint.rgb * 2.4;
	} else if (m > 0.35) {
		emit = base * 2.6;
	}
	float alive = step(0.99, tint.a);
	ALBEDO = col * mix(0.22, 1.0, alive);
	// A little light of its own, so the side away from the sun still reads as painted.
	EMISSION = emit * alive + col * 0.12 * alive;
	ROUGHNESS = 0.55;
	METALLIC = 0.1;
}
"""

static var _cache := {}
static var _material: ShaderMaterial


## The material every unit MultiMesh draws with.
static func material() -> ShaderMaterial:
	if _material == null:
		var sh := Shader.new()
		sh.code = SHADER
		_material = ShaderMaterial.new()
		_material.shader = sh
	return _material


## How much bigger a unit of a higher tier is drawn: "tank_t3" is a Tank Mk III.
static func tier_scale(type: String) -> float:
	return pow(1.25, int(type.get_slice("_t", 1)) - 1) if type.contains("_t") else 1.0


## {"body": Mesh, "top": Mesh or null, "top_at": Vector3, "muzzle": metres from the top's pivot}
## for a unit type (or "pod", a drop pod).
static func model(type: String) -> Dictionary:
	if _cache.has(type):
		return _cache[type]
	if type.contains("_t"): # a higher tier ("tank_t2") looks like its base, drawn bigger (tier_scale)
		_cache[type] = model(type.get_slice("_t", 0))
		return _cache[type]
	var body := SurfaceTool.new()
	body.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top: SurfaceTool = null
	var top_at := Vector3.ZERO
	var muzzle := 2.0
	match type:
		"engineer":
			_tracks(body, 1.3, 3.8, 0.9)
			_box(body, Vector3(2.8, 1.1, 3.4), Vector3(0, 1.3, 0), GREY, PAINT)
			_box(body, Vector3(1.6, 0.9, 1.4), Vector3(0, 2.2, -0.7), LIGHT, PAINT)
			_box(body, Vector3(1.2, 0.5, 0.2), Vector3(0, 2.3, 0.0), GLASS, PLAIN)
			# The build arm: up from the back, out over the front, a glowing nozzle at its end.
			_box(body, Vector3(0.35, 0.35, 3.2), Vector3(0.7, 3.0, 0.5), DARK, PLAIN, Vector3(deg_to_rad(-22), 0, 0))
			_box(body, Vector3(0.5, 0.5, 0.6), Vector3(0.7, 3.6, 2.0), CYAN, GLOW)
			_box(body, Vector3(0.9, 0.2, 0.9), Vector3(-0.6, 2.75, -0.9), MASS, GLOW)
		"scout":
			_box(body, Vector3(2.2, 0.8, 4.0), Vector3(0, 1.1, 0), GREY, PAINT)
			_box(body, Vector3(1.6, 0.4, 1.2), Vector3(0, 1.5, 1.5), LIGHT, PAINT, Vector3(deg_to_rad(-12), 0, 0))
			_box(body, Vector3(1.5, 0.6, 1.4), Vector3(0, 1.75, -0.4), GLASS, PLAIN)
			for sx in [-1.25, 1.25]:
				for sz in [-1.3, 1.3]:
					_cyl(body, 0.6, 0.5, Vector3(sx, 0.6, sz), DARK, PLAIN, 8, Basis(Vector3.BACK, PI / 2.0))
			_box(body, Vector3(0.08, 2.4, 0.08), Vector3(-0.7, 2.6, -1.6), DARK, PLAIN)
			_box(body, Vector3(0.25, 0.25, 0.25), Vector3(-0.7, 3.8, -1.6), Color(1.0, 0.3, 0.2), GLOW)
			_box(body, Vector3(0.4, 0.2, 0.15), Vector3(0.6, 1.2, 2.0), WHITE, GLOW)
			_box(body, Vector3(0.4, 0.2, 0.15), Vector3(-0.6, 1.2, 2.0), WHITE, GLOW)
		"striker":
			for sx in [-0.85, 0.85]:
				_box(body, Vector3(0.7, 1.4, 0.8), Vector3(sx, 0.7, 0.15), DARK, PLAIN)
				_box(body, Vector3(0.75, 1.2, 0.85), Vector3(sx, 1.85, -0.1), GREY, PLAIN, Vector3(deg_to_rad(10), 0, 0))
				_box(body, Vector3(1.0, 0.3, 1.4), Vector3(sx, 0.15, 0.3), DARK, PLAIN)
			_box(body, Vector3(2.1, 0.55, 1.2), Vector3(0, 2.55, 0), DARK, PLAIN)
			_box(body, Vector3(2.4, 1.5, 1.8), Vector3(0, 3.5, 0), GREY, PAINT)
			_box(body, Vector3(1.8, 0.5, 1.2), Vector3(0, 4.35, -0.1), LIGHT, PAINT)
			_box(body, Vector3(1.1, 0.35, 0.2), Vector3(0, 3.8, 0.92), Color.WHITE, SIDE_GLOW)
			for sx in [-1.5, 1.5]:
				_box(body, Vector3(0.55, 0.6, 1.0), Vector3(sx, 3.6, 0), GREY, PAINT)
				_box(body, Vector3(0.3, 0.3, 2.0), Vector3(sx, 3.3, 1.1), DARK, PLAIN)
				_box(body, Vector3(0.24, 0.24, 0.12), Vector3(sx, 3.3, 2.12), Color.WHITE, SIDE_GLOW)
			muzzle = 2.2
		"tank":
			_tracks(body, 2.75, 7.2, 1.3)
			_box(body, Vector3(4.6, 1.4, 6.6), Vector3(0, 1.55, 0), GREY, PAINT)
			_box(body, Vector3(4.2, 0.8, 1.4), Vector3(0, 1.45, 3.6), GREY, PAINT, Vector3(deg_to_rad(28), 0, 0))
			_box(body, Vector3(5.6, 0.3, 7.4), Vector3(0, 2.25, 0), LIGHT, PLAIN) # the fenders over the tracks
			for sx in [-2.2, 2.2]:
				_box(body, Vector3(0.3, 0.1, 6.2), Vector3(sx, 2.44, 0), WHITE, SIDE_GLOW) # side-colour stripes
			_box(body, Vector3(0.5, 0.25, 0.15), Vector3(1.6, 1.9, 3.95), WHITE, GLOW)
			_box(body, Vector3(0.5, 0.25, 0.15), Vector3(-1.6, 1.9, 3.95), WHITE, GLOW)
			top = _begin()
			top_at = Vector3(0, 2.4, -0.3)
			_box(top, Vector3(3.0, 1.1, 3.4), Vector3(0, 0.55, 0), GREY, PAINT)
			_box(top, Vector3(2.4, 0.5, 2.2), Vector3(0, 1.25, -0.3), LIGHT, PAINT)
			_box(top, Vector3(0.45, 0.45, 4.4), Vector3(0, 0.6, 3.6), DARK, PLAIN)
			_box(top, Vector3(0.6, 0.6, 0.8), Vector3(0, 0.6, 5.6), DARK, PLAIN)
			_box(top, Vector3(0.6, 0.3, 0.6), Vector3(0.9, 1.4, -1.0), Color.WHITE, SIDE_GLOW)
			muzzle = 6.0
		"artillery":
			_tracks(body, 1.65, 5.4, 1.0)
			_box(body, Vector3(2.8, 1.2, 5.0), Vector3(0, 1.4, 0), GREY, PAINT)
			_box(body, Vector3(2.4, 0.6, 1.2), Vector3(0, 2.2, -1.8), LIGHT, PAINT)
			for sx in [-1.5, 1.5]:
				_box(body, Vector3(0.3, 0.3, 1.8), Vector3(sx, 0.4, -3.0), DARK, PLAIN, Vector3(deg_to_rad(20), 0, 0))
			top = _begin()
			top_at = Vector3(0, 2.0, 0.4)
			_box(top, Vector3(2.0, 1.0, 2.2), Vector3(0, 0.5, 0), GREY, PAINT)
			var barrel := Basis(Vector3.RIGHT, deg_to_rad(-38))
			_box(top, Vector3(0.6, 0.6, 7.0), Vector3(0, 0.7, 0) + barrel * Vector3(0, 0, 3.0), DARK, PLAIN, Vector3(deg_to_rad(-38), 0, 0))
			_box(top, Vector3(0.9, 0.9, 1.2), Vector3(0, 0.7, 0) + barrel * Vector3(0, 0, 0.2), GREY, PLAIN, Vector3(deg_to_rad(-38), 0, 0))
			muzzle = 6.0
		"aa":
			_tracks(body, 1.55, 4.6, 1.0)
			_box(body, Vector3(2.6, 1.1, 4.2), Vector3(0, 1.3, 0), GREY, PAINT)
			_box(body, Vector3(1.8, 0.5, 1.0), Vector3(0, 1.9, 1.5), GLASS, PLAIN)
			top = _begin()
			top_at = Vector3(0, 1.9, -0.6)
			_box(top, Vector3(1.4, 0.9, 1.4), Vector3(0, 0.45, 0), DARK, PLAIN)
			for sx in [-1.05, 1.05]:
				_box(top, Vector3(0.9, 1.0, 2.4), Vector3(sx, 1.4, 0.3), GREY, PAINT, Vector3(deg_to_rad(-40), 0, 0))
				var face := Basis(Vector3.RIGHT, deg_to_rad(-40)) * Vector3(0, 0, 1.22)
				_box(top, Vector3(0.7, 0.8, 0.1), Vector3(sx, 1.4, 0.3) + face, AMBER, GLOW, Vector3(deg_to_rad(-40), 0, 0))
			muzzle = 1.5
		"gunship":
			_box(body, Vector3(2.0, 1.6, 6.0), Vector3(0, 0, 0), GREY, PAINT)
			_box(body, Vector3(1.6, 0.9, 1.6), Vector3(0, 0.3, 3.4), GLASS, PLAIN, Vector3(deg_to_rad(18), 0, 0))
			_box(body, Vector3(0.9, 0.7, 4.2), Vector3(0, 0.3, -4.6), GREY, PAINT)
			_box(body, Vector3(3.4, 0.2, 1.0), Vector3(0, 0.6, -6.4), DARK, PLAIN)
			_box(body, Vector3(0.2, 1.6, 1.1), Vector3(0, 1.3, -6.3), GREY, PAINT)
			_box(body, Vector3(7.6, 0.3, 1.6), Vector3(0, 0.2, -0.3), DARK, PLAIN)
			for sx in [-4.0, 4.0]:
				_cyl(body, 0.85, 1.6, Vector3(sx, 0.2, -0.3), GREY, PAINT, 10)
				_cyl(body, 0.7, 0.2, Vector3(sx, -0.7, -0.3), Color.WHITE, SIDE_GLOW, 10)
			_box(body, Vector3(0.35, 0.35, 1.6), Vector3(0, -0.85, 3.0), DARK, PLAIN)
			muzzle = 3.8
		"extractor":
			_cyl(body, 6.2, 1.2, Vector3(0, 0.6, 0), DARK, PLAIN, 8)
			_cyl(body, 5.0, 0.4, Vector3(0, 1.4, 0), GREY, PAINT, 8)
			for k in 4:
				var a := PI / 4.0 + k * PI / 2.0
				_box(body, Vector3(1.0, 5.0, 1.0), Vector3(cos(a) * 3.6, 3.4, sin(a) * 3.6), GREY, PLAIN, Vector3(0, -a, 0))
			_cyl(body, 2.0, 6.5, Vector3(0, 4.4, 0), GREY, PAINT, 8)
			_cyl(body, 1.6, 1.4, Vector3(0, 8.3, 0), MASS, GLOW, 8)
			_cyl(body, 2.4, 0.5, Vector3(0, 9.2, 0), DARK, PLAIN, 8)
			_cyl(body, 3.0, 0.15, Vector3(0, 1.65, 0), MASS, GLOW, 16)
		"generator":
			_cyl(body, 5.6, 1.0, Vector3(0, 0.5, 0), DARK, PLAIN, 8)
			_cone(body, 4.2, 3.0, 5.5, Vector3(0, 3.7, 0), GREY, PAINT, 12)
			_cyl(body, 3.1, 0.5, Vector3(0, 6.7, 0), DARK, PLAIN, 12)
			_cyl(body, 2.2, 1.6, Vector3(0, 7.5, 0), AMBER, GLOW, 12)
			for k in 3:
				var a := k * TAU / 3.0
				_box(body, Vector3(1.2, 2.4, 1.2), Vector3(cos(a) * 4.6, 1.6, sin(a) * 4.6), LIGHT, PAINT, Vector3(0, -a, 0))
			_cyl(body, 4.5, 0.2, Vector3(0, 2.2, 0), AMBER, GLOW, 16)
		"turret":
			_cyl(body, 5.0, 2.6, Vector3(0, 1.3, 0), DARK, PLAIN, 8)
			_cyl(body, 4.4, 0.6, Vector3(0, 2.8, 0), GREY, PAINT, 8)
			_cyl(body, 5.3, 0.25, Vector3(0, 0.4, 0), Color.WHITE, SIDE_GLOW, 8)
			top = _begin()
			top_at = Vector3(0, 3.1, 0)
			_box(top, Vector3(4.2, 2.4, 4.6), Vector3(0, 1.2, 0), GREY, PAINT)
			_box(top, Vector3(3.2, 0.6, 3.0), Vector3(0, 2.6, -0.4), LIGHT, PAINT)
			for sx in [-0.9, 0.9]:
				_box(top, Vector3(0.55, 0.55, 5.6), Vector3(sx, 1.3, 4.6), DARK, PLAIN)
			_box(top, Vector3(2.6, 0.4, 0.15), Vector3(0, 1.9, 2.35), Color.WHITE, SIDE_GLOW)
			muzzle = 7.5
		"factory":
			_box(body, Vector3(22, 1.0, 20), Vector3(0, 0.5, 0), DARK, PLAIN)
			_box(body, Vector3(18, 8.0, 14), Vector3(0, 5.0, -1.5), GREY, PLAIN)
			_box(body, Vector3(18.6, 1.0, 14.6), Vector3(0, 9.3, -1.5), GREY, PAINT)
			for sx in [-6.0, 0.0, 6.0]:
				_box(body, Vector3(3.6, 1.2, 12.0), Vector3(sx, 10.2, -1.5), LIGHT, PAINT)
			_box(body, Vector3(9.0, 6.0, 0.4), Vector3(0, 4.0, 5.6), Color.WHITE, SIDE_GLOW)
			_box(body, Vector3(11.0, 7.2, 1.2), Vector3(0, 4.6, 5.9), DARK, PLAIN)
			_box(body, Vector3(9.0, 0.2, 4.0), Vector3(0, 1.05, 8.0), AMBER, GLOW)
			_cyl(body, 1.6, 7.0, Vector3(-7.0, 12.5, -6.0), DARK, PLAIN, 8)
			_cyl(body, 1.7, 0.6, Vector3(-7.0, 16.3, -6.0), AMBER, GLOW, 8)
			_box(body, Vector3(3.0, 3.0, 3.0), Vector3(7.5, 11.8, -6.0), GREY, PLAIN)
		"outpost":
			_cyl(body, 10.0, 1.0, Vector3(0, 0.5, 0), DARK, PLAIN, 10)
			_cyl(body, 8.2, 4.5, Vector3(0, 3.0, 0), GREY, PLAIN, 10)
			_cone(body, 8.4, 0.4, 4.5, Vector3(0, 5.25, 0), GREY, PAINT, 10)
			_cyl(body, 8.5, 0.5, Vector3(0, 3.6, 0), Color.WHITE, SIDE_GLOW, 10)
			_box(body, Vector3(0.5, 12.0, 0.5), Vector3(3.0, 11.0, 0), DARK, PLAIN)
			_box(body, Vector3(0.8, 0.8, 0.8), Vector3(3.0, 17.2, 0), Color(1.0, 0.3, 0.2), GLOW)
			_box(body, Vector3(4.0, 3.0, 2.0), Vector3(0, 1.5, 8.6), DARK, PLAIN)
		"node":
			_cyl(body, 14.0, 3.0, Vector3(0, 1.5, 0), DARK, PLAIN, 8)
			_cyl(body, 11.0, 1.0, Vector3(0, 3.5, 0), GREY, PAINT, 8)
			for k in 4:
				var a := k * PI / 2.0
				_box(body, Vector3(3.0, 12.0, 7.0), Vector3(cos(a) * 7.5, 8.0, sin(a) * 7.5), GREY, PLAIN, Vector3(0, -a, 0))
			_cyl(body, 6.0, 20.0, Vector3(0, 13.0, 0), GREY, PAINT, 8)
			_cyl(body, 6.5, 2.0, Vector3(0, 15.0, 0), Color.WHITE, SIDE_GLOW, 8)
			_cyl(body, 6.5, 1.0, Vector3(0, 21.0, 0), Color.WHITE, SIDE_GLOW, 8)
			_cone(body, 6.0, 0.0, 10.0, Vector3(0, 28.0, 0), LIGHT, PAINT, 8)
			_box(body, Vector3(1.4, 1.4, 1.4), Vector3(0, 34.0, 0), Color.WHITE, SIDE_GLOW, Vector3(0.6, 0.6, 0))
			muzzle = 4.0
		"pod":
			_cyl(body, 1.9, 3.6, Vector3(0, 2.4, 0), GREY, PLAIN, 8)
			_cone(body, 1.9, 0.4, 2.2, Vector3(0, 5.3, 0), LIGHT, PAINT, 8)
			_cone(body, 1.2, 2.0, 0.8, Vector3(0, 0.2, 0), DARK, PLAIN, 8)
			_cyl(body, 1.95, 0.3, Vector3(0, 3.2, 0), Color.WHITE, SIDE_GLOW, 8)
			for k in 4:
				var a := k * PI / 2.0 + PI / 4.0
				_box(body, Vector3(0.3, 2.4, 1.2), Vector3(cos(a) * 2.0, 1.6, sin(a) * 2.0), DARK, PLAIN, Vector3(0, -a, 0))
		_:
			_box(body, Vector3(3, 3, 3), Vector3(0, 1.5, 0), GREY, PAINT)
	var out := {"body": body.commit(), "top": top.commit() if top else null, "top_at": top_at, "muzzle": muzzle}
	_cache[type] = out
	return out


## A see-through copy of a structure for placing it (the build ghost), in one colour.
static func ghost(type: String) -> Mesh:
	return model(type).body


# --- Building meshes --------------------------------------------------------------------------

static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


## Colours go in linear space (the shader takes them as they are).
static func _c(colour: Color, mask: float) -> Color:
	var l := colour.srgb_to_linear()
	return Color(l.r, l.g, l.b, mask)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, colour: Color) -> void:
	var n := (b - a).cross(c - a).normalized()
	st.set_color(colour)
	st.set_normal(n)
	for v in [a, b, c, a, c, d]:
		st.add_vertex(v)


static func _box(st: SurfaceTool, size: Vector3, pos: Vector3, colour: Color, mask: float, rot := Vector3.ZERO) -> void:
	var b := Basis.from_euler(rot)
	var h := size * 0.5
	var c := _c(colour, mask)
	var p := func(x: float, y: float, z: float) -> Vector3: return pos + b * Vector3(x * h.x, y * h.y, z * h.z)
	_quad(st, p.call(-1, 1, -1), p.call(-1, 1, 1), p.call(1, 1, 1), p.call(1, 1, -1), c) # top
	_quad(st, p.call(-1, -1, 1), p.call(-1, -1, -1), p.call(1, -1, -1), p.call(1, -1, 1), c) # bottom
	_quad(st, p.call(-1, -1, 1), p.call(1, -1, 1), p.call(1, 1, 1), p.call(-1, 1, 1), c) # front (+z)
	_quad(st, p.call(1, -1, -1), p.call(-1, -1, -1), p.call(-1, 1, -1), p.call(1, 1, -1), c) # back
	_quad(st, p.call(1, -1, 1), p.call(1, -1, -1), p.call(1, 1, -1), p.call(1, 1, 1), c) # right
	_quad(st, p.call(-1, -1, -1), p.call(-1, -1, 1), p.call(-1, 1, 1), p.call(-1, 1, -1), c) # left


## A cylinder of `height` centred on `pos`, upright (or turned by `basis`).
static func _cyl(st: SurfaceTool, radius: float, height: float, pos: Vector3, colour: Color, mask: float, sides := 12, basis := Basis()) -> void:
	_cone(st, radius, radius, height, pos, colour, mask, sides, basis)


## A frustum from `r0` at the bottom to `r1` at the top, `height` tall, centred on `pos`.
static func _cone(st: SurfaceTool, r0: float, r1: float, height: float, pos: Vector3, colour: Color, mask: float, sides := 12, basis := Basis()) -> void:
	var c := _c(colour, mask)
	var y0 := -height * 0.5
	var y1 := height * 0.5
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var b0 := pos + basis * Vector3(cos(a0) * r0, y0, sin(a0) * r0)
		var b1 := pos + basis * Vector3(cos(a1) * r0, y0, sin(a1) * r0)
		var t0 := pos + basis * Vector3(cos(a0) * r1, y1, sin(a0) * r1)
		var t1 := pos + basis * Vector3(cos(a1) * r1, y1, sin(a1) * r1)
		_quad(st, b0, t0, t1, b1, c)
		var top := pos + basis * Vector3(0, y1, 0)
		var bottom := pos + basis * Vector3(0, y0, 0)
		if r1 > 0.0:
			st.set_color(c)
			st.set_normal(basis * Vector3.UP)
			for v in [top, t1, t0]:
				st.add_vertex(v)
		st.set_color(c)
		st.set_normal(basis * Vector3.DOWN)
		for v in [bottom, b0, b1]:
			st.add_vertex(v)


## Two tracks either side of a hull, `x` out from the middle, `length` long, `height` tall.
static func _tracks(st: SurfaceTool, x: float, length: float, height: float) -> void:
	for sx in [-x, x]:
		_box(st, Vector3(1.1, height, length), Vector3(sx, height * 0.5 + 0.05, 0), DARK, PLAIN)
		_box(st, Vector3(1.15, 0.25, length * 0.86), Vector3(sx, height * 0.62, 0), GREY, PLAIN)
