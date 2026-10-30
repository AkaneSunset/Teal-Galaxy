extends Node3D
## A sector battle's effects: tracers and bolts for every shot, muzzle flashes and sparks, the
## arcing shells of artillery, fireballs, smoke and shockwaves when things die, scorch marks on
## the ground, drop pods' flames, engineers' build beams. All drawn with a handful of MultiMeshes
## (glowing additive ones and a smoke one), refilled each frame.

const MAX := 4096 # the most of one kind of effect drawn at once

var terrain: Node3D # battle_terrain.gd

var _bolts: Array = [] # {"a", "b", "t", "dur", "len", "w", "c", "spark"}
var _shells: Array = [] # {"a", "b", "t", "dur", "apex", "c", "big"}
var _flashes: Array = [] # {"p", "t", "dur", "size", "c", "rise"}
var _smoke: Array = [] # {"p", "t", "dur", "size", "v"}
var _rings: Array = [] # {"p", "t", "dur", "size", "c"}
var _scorch: Array = [] # Transform3D
var _beams: Array = [] # this frame only: [a, b, colour, width]
var _clock := 0.0
## How long a frame's effects take (ms, smoothed), for the performance checks.
var work_ms := 0.0

var _glow_box: MultiMeshInstance3D
var _glow_ball: MultiMeshInstance3D
var _smoke_ball: MultiMeshInstance3D
var _ring: MultiMeshInstance3D
var _scorch_mm: MultiMeshInstance3D
var _scorch_dirty := false


static func glow_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
varying vec4 c;
void vertex() { c = INSTANCE_CUSTOM; }
void fragment() { ALBEDO = c.rgb * c.a; ALPHA = 1.0; }
"""
	return sh


static func smoke_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, shadows_disabled;
varying vec4 c;
void vertex() { c = INSTANCE_CUSTOM; }
void fragment() {
	float rim = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = c.rgb;
	ALPHA = c.a * rim;
	ROUGHNESS = 1.0;
}
"""
	return sh


func _ready() -> void:
	var glow := ShaderMaterial.new()
	glow.shader = glow_shader()
	var box := BoxMesh.new()
	box.size = Vector3(1, 1, 1)
	_glow_box = _multi(box, glow)
	var ball := SphereMesh.new()
	ball.radius = 1.0
	ball.height = 2.0
	ball.radial_segments = 12
	ball.rings = 6
	_glow_ball = _multi(ball, glow)
	var smoke := ShaderMaterial.new()
	smoke.shader = smoke_shader()
	_smoke_ball = _multi(ball, smoke)
	_ring = _multi(_ring_mesh(), glow)
	var scorch := StandardMaterial3D.new()
	scorch.albedo_color = Color(0.03, 0.025, 0.02, 0.6)
	scorch.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	scorch.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.05
	disc.radial_segments = 14
	_scorch_mm = _multi(disc, scorch)


func _multi(mesh: Mesh, mat: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = true # the GL Compatibility renderer only passes custom data with colours on
	mm.mesh = mesh
	mm.instance_count = MAX
	mm.visible_instance_count = 0
	for i in MAX:
		mm.set_instance_color(i, Color.WHITE)
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.extra_cull_margin = 4000.0
	add_child(inst)
	return inst


# --- Effects ----------------------------------------------------------------------------------

## A shot from `a` (the muzzle) to `b` by a unit of `type`. `colour` is its side's colour, `rate`
## how fast the battle runs (simulated seconds a real one), for how long shells fly.
func shot(a: Vector3, b: Vector3, type: String, colour: Color, rate: float) -> void:
	var hot := colour.lerp(Color.WHITE, 0.45)
	match type:
		"artillery":
			var d := Vector2(b.x - a.x, b.z - a.z).length()
			_shells.append({"a": a, "b": b, "t": _clock, "dur": clampf(d / 160.0 / maxf(rate, 0.1), 0.25, 3.0), "apex": d * 0.32, "c": Color(1.0, 0.75, 0.4), "big": true})
			flash(a, 2.6, Color(1.0, 0.7, 0.35), 0.18)
			puff(a, 2.0)
		"aa":
			_shells.append({"a": a, "b": b, "t": _clock, "dur": 0.35, "apex": 6.0, "c": Color(1.0, 0.65, 0.25), "big": false})
			flash(a, 0.9, Color(1.0, 0.6, 0.3), 0.1)
		"tank":
			_bolt(a, b, 0.16, 7.0, 0.55, hot, true)
			flash(a, 1.6, hot, 0.1)
		"turret":
			_bolt(a + Vector3(0.5, 0, 0), b, 0.15, 8.0, 0.6, hot, true)
			_bolt(a - Vector3(0.5, 0, 0), b, 0.17, 8.0, 0.6, hot, false)
			flash(a, 2.0, hot, 0.1)
		"node":
			_bolt(a, b, 0.2, 9999.0, 1.0, hot, true) # a beam: the whole way at once
			flash(a, 3.0, hot, 0.2)
		"gunship":
			_bolt(a, b, 0.1, 5.0, 0.35, hot, true)
			flash(a, 0.8, hot, 0.06)
		"scout":
			_bolt(a, b, 0.08, 3.0, 0.2, Color(1.0, 0.9, 0.6), true)
		_:
			_bolt(a, b, 0.12, 5.0, 0.35, hot, true)
			flash(a, 0.8, hot, 0.06)


func _bolt(a: Vector3, b: Vector3, dur: float, length: float, width: float, colour: Color, spark: bool) -> void:
	if _bolts.size() < MAX:
		_bolts.append({"a": a, "b": b, "t": _clock, "dur": dur, "len": length, "w": width, "c": colour, "spark": spark})


## A short bright flash of light.
func flash(p: Vector3, size: float, colour: Color, dur := 0.12, rise := 0.0) -> void:
	if _flashes.size() < MAX:
		_flashes.append({"p": p, "t": _clock, "dur": dur, "size": size, "c": colour, "rise": rise})


## A puff of smoke that drifts up and fades.
func puff(p: Vector3, size: float, dur := 1.6) -> void:
	if _smoke.size() < MAX:
		_smoke.append({"p": p, "t": _clock, "dur": dur, "size": size, "v": Vector3(randf_range(-1, 1), 2.5 + randf() * 2.0, randf_range(-1, 1))})


## Something blew up: a fireball, sparks, a shockwave on the ground, smoke, and a scorch mark.
## `size` is about the thing's radius.
func explode(p: Vector3, size: float, colour := Color(1.0, 0.55, 0.2), on_ground := true) -> void:
	flash(p + Vector3(0, size * 0.4, 0), size * 2.2, Color(1.0, 0.9, 0.7), 0.14)
	for k in 5:
		var off := Vector3(randf_range(-1, 1), randf_range(0.2, 1.2), randf_range(-1, 1)) * size * 0.7
		flash(p + off, size * randf_range(0.8, 1.5), colour, randf_range(0.35, 0.6), size * 0.8)
	for k in 4:
		puff(p + Vector3(randf_range(-1, 1), randf_range(0.5, 1.5), randf_range(-1, 1)) * size * 0.6, size * randf_range(0.9, 1.6), randf_range(1.6, 2.8))
	if on_ground:
		var g := Vector3(p.x, terrain.height(p.x, p.z) + 0.3, p.z)
		_rings.append({"p": g, "t": _clock, "dur": 0.45, "size": size * 3.0, "c": colour})
		scorch(g, size * 1.3)


## A pod landing: a ring of dust and a flash.
func dust(p: Vector3) -> void:
	_rings.append({"p": p + Vector3(0, 0.3, 0), "t": _clock, "dur": 0.5, "size": 12.0, "c": Color(0.9, 0.75, 0.5)})
	for k in 5:
		var a := TAU * k / 5.0
		puff(p + Vector3(cos(a) * 3.0, 0.6, sin(a) * 3.0), 2.4, 1.4)
	flash(p + Vector3(0, 1, 0), 3.0, Color(1.0, 0.7, 0.4), 0.18)


func scorch(p: Vector3, r: float) -> void:
	_scorch.append(Transform3D(Basis(Vector3.UP, randf() * TAU).scaled(Vector3(r, 1, r)), p))
	if _scorch.size() > 300:
		_scorch.pop_front()
	_scorch_dirty = true


## A glowing line drawn this frame only (build beams, pod flames, the aim line).
func beam(a: Vector3, b: Vector3, colour: Color, width := 0.3) -> void:
	_beams.append([a, b, colour, width])


# --- Each frame -------------------------------------------------------------------------------

func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_frame(delta)
	work_ms = lerpf(work_ms, (Time.get_ticks_usec() - t0) / 1000.0, 0.1)


func _frame(delta: float) -> void:
	_clock += delta
	var boxes := 0
	var balls := 0
	var smokes := 0
	var rings := 0
	var bm := _glow_box.multimesh
	var gm := _glow_ball.multimesh
	var sm := _smoke_ball.multimesh
	var rm := _ring.multimesh
	# Bolts: a bright streak flying from the muzzle to the target, a spark where it lands.
	var keep: Array = []
	for b in _bolts:
		var k: float = (_clock - b.t) / b.dur
		if k >= 1.0:
			if b.spark:
				flash(b.b, b.w * 2.5, b.c, 0.1)
			continue
		keep.append(b)
		var a: Vector3 = b.a
		var to: Vector3 = b.b
		var full := a.distance_to(to)
		var head := a.lerp(to, k if b.len < full else 1.0)
		var tail := a.lerp(to, maxf(0.0, k - b.len / maxf(full, 0.01)) if b.len < full else 0.0)
		if boxes < MAX:
			bm.set_instance_transform(boxes, _segment(tail, head, b.w))
			bm.set_instance_custom_data(boxes, Color(b.c.r, b.c.g, b.c.b, 1.0 if b.len < full else 1.0 - k))
			boxes += 1
	_bolts = keep
	# Shells: up in an arc and down, with a short trail.
	keep = []
	for s in _shells:
		var k: float = (_clock - s.t) / s.dur
		if k >= 1.0:
			if s.big:
				explode(s.b, 4.0, Color(1.0, 0.6, 0.25))
			else:
				flash(s.b, 2.2, s.c, 0.18)
				puff(s.b, 1.6, 1.0)
			continue
		keep.append(s)
		var p := _arc(s, k)
		var back := _arc(s, maxf(0.0, k - 0.06))
		if boxes < MAX:
			bm.set_instance_transform(boxes, _segment(back, p, 0.5 if s.big else 0.25))
			bm.set_instance_custom_data(boxes, Color(s.c.r, s.c.g, s.c.b, 0.9))
			boxes += 1
		if balls < MAX:
			gm.set_instance_transform(balls, Transform3D(Basis().scaled(Vector3.ONE * (0.9 if s.big else 0.4)), p))
			gm.set_instance_custom_data(balls, Color(1.0, 0.9, 0.7, 1.0))
			balls += 1
	_shells = keep
	for b in _beams:
		if boxes < MAX:
			bm.set_instance_transform(boxes, _segment(b[0], b[1], b[3]))
			bm.set_instance_custom_data(boxes, b[2])
			boxes += 1
	_beams.clear()
	# Flashes and fireballs grow and fade.
	keep = []
	for f in _flashes:
		var k: float = (_clock - f.t) / f.dur
		if k >= 1.0:
			continue
		keep.append(f)
		if balls < MAX:
			var s: float = f.size * (0.6 + 0.6 * k)
			gm.set_instance_transform(balls, Transform3D(Basis().scaled(Vector3.ONE * s), f.p + Vector3(0, f.rise * k, 0)))
			var c: Color = f.c
			gm.set_instance_custom_data(balls, Color(c.r, c.g, c.b, (1.0 - k) * (1.0 - k) * 1.4))
			balls += 1
	_flashes = keep
	keep = []
	for p in _smoke:
		var k: float = (_clock - p.t) / p.dur
		if k >= 1.0:
			continue
		keep.append(p)
		if smokes < MAX:
			var s: float = p.size * (0.7 + 1.1 * k)
			smokes += 1
			sm.set_instance_transform(smokes - 1, Transform3D(Basis().scaled(Vector3.ONE * s), p.p + p.v * k * p.dur))
			sm.set_instance_custom_data(smokes - 1, Color(0.16, 0.15, 0.14, 0.55 * (1.0 - k)))
	_smoke = keep
	keep = []
	for r in _rings:
		var k: float = (_clock - r.t) / r.dur
		if k >= 1.0:
			continue
		keep.append(r)
		if rings < MAX:
			var s: float = r.size * (0.2 + k)
			rm.set_instance_transform(rings, Transform3D(Basis().scaled(Vector3(s, 1, s)), r.p))
			var c: Color = r.c
			rm.set_instance_custom_data(rings, Color(c.r, c.g, c.b, 1.0 - k))
			rings += 1
	_rings = keep
	bm.visible_instance_count = boxes
	gm.visible_instance_count = balls
	sm.visible_instance_count = smokes
	rm.visible_instance_count = rings
	if _scorch_dirty:
		_scorch_dirty = false
		var mm := _scorch_mm.multimesh
		for i in _scorch.size():
			mm.set_instance_transform(i, _scorch[i])
		mm.visible_instance_count = _scorch.size()


func _arc(s: Dictionary, k: float) -> Vector3:
	var p: Vector3 = (s.a as Vector3).lerp(s.b, k)
	p.y += s.apex * 4.0 * k * (1.0 - k)
	return p


## A box stretched from `a` to `b`, `w` thick.
func _segment(a: Vector3, b: Vector3, w: float) -> Transform3D:
	var d := b - a
	var l := d.length()
	if l < 0.01:
		return Transform3D(Basis().scaled(Vector3(w, w, w)), a)
	var z := d / l
	var up := Vector3.UP if absf(z.y) < 0.95 else Vector3.RIGHT
	var x := up.cross(z).normalized()
	var y := z.cross(x)
	return Transform3D(Basis(x * w, y * w, z * l), (a + b) * 0.5)


func _ring_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 28
	for k in n:
		var a0 := TAU * k / n
		var a1 := TAU * (k + 1) / n
		var i0 := Vector3(cos(a0), 0, sin(a0)) * 0.8
		var o0 := Vector3(cos(a0), 0, sin(a0))
		var i1 := Vector3(cos(a1), 0, sin(a1)) * 0.8
		var o1 := Vector3(cos(a1), 0, sin(a1))
		for v in [i0, o0, o1, i0, o1, i1]:
			st.add_vertex(v)
	return st.commit()
