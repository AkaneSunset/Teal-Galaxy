extends Node3D
## Draws a sector battle's units and structures: one MultiMesh per type and side for the bodies,
## one per turreted type and side for the turrets, drop pods coming down, wrecks where units fell,
## and selection rings. Smooth with hundreds of units: nothing here is a node per unit. A side has
## its own batches because each side's units wear its faction's textures (side_looks).
##
## The units themselves (Unit below) live in the battle view, which fills them from the server's
## snapshots; update() places every one of them each frame, between its last two snapshots.

const Models := preload("res://battle/battle_models.gd")

const POD_FALL := 2.6 # real seconds a drop pod is seen falling before it lands
const POD_HEIGHT := 420.0 # metres up a pod is first seen
const WRECK_S := 30.0 # how long wrecks lie on the field (they sink at the end)
const SQUAD_RING := 7.0 # selection ring radius round a squad (metres)
const MAN_GAP := 1.9 # metres between soldiers in a wedge or a line

## One unit or structure as the client knows it.
class Unit:
	var id := 0
	var type := ""
	var side := "a"
	var owner := ""
	var kind := "land" # land, air or structure
	var radius := 3.0
	var hp := 1.0
	var max_hp := 1.0
	var state := "idle"
	var progress := 1.0 # a structure's build progress
	var name := ""
	var mine := false # the pilot's own
	var friend := false # on the pilot's side
	# Where the last two snapshots put it, and its heading in the latest.
	var from := Vector2.ZERO
	var to := Vector2.ZERO
	var heading := 0.0
	# Drawn this frame:
	var pos := Vector3.ZERO
	var yaw := 0.0
	var top_yaw := 0.0
	var aim_until := 0.0 # real time until which the turret keeps facing `aim`
	var aim := Vector2.ZERO
	var tilt := Basis()
	var tilt_to := Basis()
	var tilt_at := Vector2(-1000, -1000)
	var seen_drop := -1.0 # real time a drop pod was first seen for it
	var pod_down := false # its pod has hit the ground
	var landed_at := -1.0 # real time it came out of its pod
	var last_shot := -100.0 # real time it last fired (for the reload bar)
	var orders: Array = [] # [{"order": "move", "p": Vector2}] the pilot gave it, for the waypoint lines
	var idle_for := 0.0
	var hit_at := -100.0 # real time it last lost health
	var vet := 0 # veterancy stars
	var shield := -1.0 # a shield generator's dome strength (-1: not one)
	var tier := 1 # a factory's, extractor's or generator's tier
	# An infantry squad (Company of Heroes style): drawn as its soldiers, each finding its own place.
	var squad := 0 # soldiers at full strength (0: not a squad)
	var cover := "" # what it stands in: h, l, n, x (heavy, light, none, negative)
	var supp := 0.0 # suppression, 0 to 1
	var retreating := false
	var pinned := false
	var reinforcing := false
	var men: Array = [] # each soldier drawn: {"p": Vector2, "yaw": float, "seed": float}
	var shot_k := 0 # which soldier fires next

	## Soldiers left: one for each share of its hit points it still has (as the server counts them).
	func soldiers() -> int:
		if squad <= 0:
			return 1
		return clampi(ceili(hp / (max_hp / squad) - 1e-6), 0, squad)

	func ground() -> Vector2:
		return Vector2(pos.x, pos.z)

	func dropping() -> bool:
		return state == "drop"


class Batch:
	var inst: MultiMeshInstance3D
	var count := 0


var terrain: Node3D # battle_terrain.gd
var side_colours := {"a": Color.WHITE, "d": Color.WHITE} # linear
var side_looks := {"a": "", "d": ""} # each side's faction ("militia" for none): the textures its units wear
var show_units := true

var _bodies := {} # "type/side" -> Batch
var _tops := {} # "type/side" -> Batch
var _pods := {} # side -> Batch
var _rings: Batch
var _wrecks: Array = [] # {"type", "side", "xform", "top", "t"}
var _clock := 0.0


func _ready() -> void:
	var ring_mat := ShaderMaterial.new()
	ring_mat.shader = load("res://battle/battle_fx.gd").glow_shader()
	_rings = _batch(_ring_mesh(), ring_mat)


func _batch(mesh: Mesh, mat: Material) -> Batch:
	var b := Batch.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = true # the GL Compatibility renderer only passes custom data with colours on
	mm.mesh = mesh
	mm.instance_count = 64
	mm.visible_instance_count = 0
	_whiten(mm, 0)
	b.inst = MultiMeshInstance3D.new()
	b.inst.multimesh = mm
	b.inst.material_override = mat
	b.inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	b.inst.extra_cull_margin = 4000.0 # instances spread over the whole map: never cull the batch
	add_child(b.inst)
	return b


## The material a side's units draw with: its faction's textures (a unit type's own, if it has any).
func _material(side: String, type := "") -> ShaderMaterial:
	return Models.material(look(side), type)


## The faction whose models and textures a side's units wear.
func look(side: String) -> String:
	return str(side_looks.get(side, ""))


## A unit type's model as a side draws it: its faction's own, or the shared one.
func _model(type: String, side: String) -> Dictionary:
	return Models.model(type, look(side))


func _body(type: String, side: String) -> Batch:
	var key := type + "/" + side
	if not _bodies.has(key):
		_bodies[key] = _batch(_model(type, side).body, _material(side, type))
	return _bodies[key]


func _top(type: String, side: String) -> Batch:
	var key := type + "/" + side
	if not _tops.has(key):
		_tops[key] = _batch(_model(type, side).top, _material(side, type))
	return _tops[key]


func _pod_batch(side: String) -> Batch:
	if not _pods.has(side):
		_pods[side] = _batch(Models.model("pod").body, _material(side))
	return _pods[side]


func _put(b: Batch, xform: Transform3D, custom: Color) -> void:
	var mm := b.inst.multimesh
	if b.count >= mm.instance_count:
		var keep := mm.visible_instance_count
		var old := []
		for i in b.count:
			old.append([mm.get_instance_transform(i), mm.get_instance_custom_data(i)])
		mm.instance_count = mm.instance_count * 2
		_whiten(mm, 0)
		for i in old.size():
			mm.set_instance_transform(i, old[i][0])
			mm.set_instance_custom_data(i, old[i][1])
		mm.visible_instance_count = keep
	mm.set_instance_transform(b.count, xform)
	mm.set_instance_custom_data(b.count, custom)
	b.count += 1


## Instance colours stay white (the paint masks are in the vertex colours' alpha, which the
## instance colour multiplies): set once, when the buffer is made or grows.
func _whiten(mm: MultiMesh, from: int) -> void:
	for i in range(from, mm.instance_count):
		mm.set_instance_color(i, Color.WHITE)


## Places every unit for this frame. `alpha` is how far it is from the previous snapshot to the
## latest (0 to 1), `now` the real time, `selected` the ids picked.
func update(units: Dictionary, alpha: float, now: float, delta: float, selected: Dictionary) -> void:
	_clock += delta
	for b in _bodies.values():
		b.count = 0
	for b in _tops.values():
		b.count = 0
	for b in _pods.values():
		b.count = 0
	_rings.count = 0
	var turn := 1.0 - exp(-9.0 * delta)
	for u: Unit in units.values():
		var g := u.from.lerp(u.to, alpha)
		var h: float = terrain.height(g.x, g.y)
		if u.dropping():
			if u.seen_drop < 0.0:
				u.seen_drop = now
			u.pos = Vector3(g.x, h, g.y)
			_pod(u, now)
			continue
		if u.kind == "air":
			h += Models.AIR_HEIGHT + sin(_clock * 1.7 + u.id) * 0.8
		u.pos = Vector3(g.x, h, g.y)
		if u.kind == "structure":
			u.yaw = 0.0
		else:
			u.yaw = lerp_angle(u.yaw, u.heading, turn)
		var want_top := u.yaw if now > u.aim_until else atan2(u.aim.x - g.x, u.aim.y - g.y)
		u.top_yaw = lerp_angle(u.top_yaw, want_top, 1.0 - exp(-7.0 * delta))
		if not show_units:
			continue
		var basis := Basis(Vector3.UP, u.yaw)
		if u.kind == "land":
			if g.distance_squared_to(u.tilt_at) > 0.25: # the slope under it, looked up again only once it has moved
				u.tilt_at = g
				u.tilt_to = _ground_tilt(g)
			u.tilt = u.tilt.slerp(u.tilt_to, turn)
			basis = u.tilt * basis
		elif u.kind == "air":
			basis = basis * Basis(Vector3.RIGHT, 0.08 if u.state == "move" else 0.0)
		var scale := Models.tier_scale(u.type, look(u.side))
		if u.landed_at > 0.0 and now - u.landed_at < 0.35: # out of the pod with a little bounce
			scale *= 0.85 + 0.15 * (now - u.landed_at) / 0.35
		var y_scale := 1.0
		if u.kind == "structure" and u.progress < 1.0:
			y_scale = 0.12 + 0.88 * u.progress
		var xf := Transform3D(basis.scaled(Vector3(scale, scale * y_scale, scale)), u.pos)
		var custom: Color = side_colours.get(u.side, Color.WHITE)
		if now - u.hit_at < 0.08: # a flash of white when hit
			custom = custom.lerp(Color(2, 2, 2), 0.5)
		if u.squad > 0:
			_squad(u, g, now, delta, scale, custom)
			if selected.has(u.id):
				_put(_rings, Transform3D(Basis().scaled(Vector3(SQUAD_RING, 1, SQUAD_RING)), Vector3(g.x, h + 0.4, g.y)), Color(0.35, 1.0, 0.45, 0.9) if u.friend else Color(1.0, 0.35, 0.3, 0.9))
			continue
		_put(_body(u.type, u.side), xf, custom)
		var m: Dictionary = _model(u.type, u.side)
		if m.top:
			var top_basis := basis * Basis(Vector3.UP, u.top_yaw - u.yaw)
			_put(_top(u.type, u.side), Transform3D(top_basis.scaled(Vector3(scale, scale * y_scale, scale)), xf * (m.top_at as Vector3)), custom)
		if selected.has(u.id):
			var r := u.radius * (1.5 if u.kind != "structure" else 1.2)
			var ring_at := Vector3(u.pos.x, terrain.height(g.x, g.y) + 0.4, u.pos.z)
			_put(_rings, Transform3D(Basis().scaled(Vector3(r, 1, r)), ring_at), Color(0.35, 1.0, 0.45, 0.9) if u.friend else Color(1.0, 0.35, 0.3, 0.9))
	_draw_wrecks()
	for b in _bodies.values():
		b.inst.multimesh.visible_instance_count = b.count
	for b in _tops.values():
		b.inst.multimesh.visible_instance_count = b.count
	for b in _pods.values():
		b.inst.multimesh.visible_instance_count = b.count
	_rings.inst.multimesh.visible_instance_count = _rings.count


## Where a unit's drop pod is: falling fast from high up, slowing just before it lands.
func pod_height(u: Unit, now: float) -> float:
	var k := clampf((now - u.seen_drop) / POD_FALL, 0.0, 1.0)
	return POD_HEIGHT * pow(1.0 - k, 1.6)


func _pod(u: Unit, now: float) -> void:
	if not show_units:
		return
	var up := pod_height(u, now)
	var xf := Transform3D(Basis(Vector3.UP, _clock * 2.0 + u.id), u.pos + Vector3(0, up, 0))
	_put(_pod_batch(u.side), xf, side_colours.get(u.side, Color.WHITE))


## A land unit leans with the slope it stands on.
func _ground_tilt(g: Vector2) -> Basis:
	var dx: float = terrain.height(g.x + 2.0, g.y) - terrain.height(g.x - 2.0, g.y)
	var dz: float = terrain.height(g.x, g.y + 2.0) - terrain.height(g.x, g.y - 2.0)
	var n := Vector3(-dx, 4.0, -dz).normalized()
	var axis := Vector3.UP.cross(n)
	if axis.length() < 1e-4:
		return Basis()
	return Basis(axis.normalized(), Vector3.UP.angle_to(n))


## Draws a squad as its soldiers, each walking to its own place: a wedge behind the leader on the
## move, a line across its front when it stops (tighter, crouched, in cover), flat on the ground when
## pinned. Each soldier keeps to its own pace, so they lag and drift a little and never move as one
## block. Soldiers the squad has lost fall where they stood; new ones join where it is.
func _squad(u: Unit, g: Vector2, now: float, delta: float, scale: float, custom: Color) -> void:
	var n := u.soldiers()
	while u.men.size() > n:
		_fall(u, u.men.pop_back())
	while u.men.size() < n:
		var jitter := Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5))
		u.men.append({"p": g + jitter, "yaw": u.yaw, "seed": randf() * TAU})
	var moving := u.from.distance_squared_to(u.to) > 0.04 and not u.pinned
	var in_cover := u.cover == "h" or u.cover == "l"
	var fwd := Vector2(sin(u.yaw), cos(u.yaw))
	var right := Vector2(fwd.y, -fwd.x)
	var aiming := now < u.aim_until
	for i in n:
		var m: Dictionary = u.men[i]
		var seed: float = m.seed
		var slot := Vector2.ZERO
		if moving: # a wedge: the leader in front, the rest fanned out behind
			var row := (i + 1) / 2
			var side := 1.0 if i % 2 == 1 else -1.0
			slot = -fwd * row * MAN_GAP * 1.2 + right * side * row * MAN_GAP
		else: # a line across its front, staggered in the open, shoulder to shoulder in cover
			var gap := MAN_GAP * (0.85 if in_cover else 1.3)
			slot = right * (i - (n - 1) * 0.5) * gap
			if not in_cover:
				slot += fwd * (0.6 if i % 2 == 0 else -0.6)
		if not u.pinned:
			slot += Vector2(sin(_clock * 0.6 + seed), cos(_clock * 0.8 + seed * 1.7)) * 0.3
		var want := g + slot
		var p: Vector2 = m.p
		if p.distance_squared_to(want) > 900.0: # out of a carrier or far behind: just be there
			p = want
		var pace := 2.6 + fmod(seed, 1.0) * 1.6 # each soldier keeps up at his own rate
		if u.retreating:
			pace *= 1.6
		var was := p
		p = p.lerp(want, 1.0 - exp(-pace * delta))
		var yaw: float = m.yaw
		var face := u.yaw
		if aiming and not u.retreating:
			face = atan2(u.aim.x - p.x, u.aim.y - p.y)
		elif p.distance_squared_to(was) > 0.0004 * maxf(delta * 60.0, 1.0):
			face = atan2(p.x - was.x, p.y - was.y)
		yaw = lerp_angle(yaw, face, 1.0 - exp(-8.0 * delta))
		m.p = p
		m.yaw = yaw
		var basis := Basis(Vector3.UP, yaw)
		var lift := 0.0
		if u.pinned: # flat on his front
			basis = basis * Basis(Vector3.RIGHT, PI * 0.47)
			lift = 0.25
		elif in_cover and not moving: # crouched behind it
			basis = basis * Basis(Vector3.RIGHT, 0.2)
			basis = basis.scaled(Vector3(1, 0.8, 1))
		var h: float = terrain.height(p.x, p.y) + lift
		_put(_body(u.type, u.side), Transform3D(basis.scaled(Vector3.ONE * scale), Vector3(p.x, h, p.y)), custom)


## Where one of a squad's soldiers is now (its centre if it has none drawn), for its shots.
func soldier_at(u: Unit, k: int) -> Vector3:
	if u.men.is_empty():
		return u.pos
	var m: Dictionary = u.men[posmod(k, u.men.size())]
	var p: Vector2 = m.p
	return Vector3(p.x, terrain.height(p.x, p.y), p.y)


## A soldier falls: he lies where he stood, on his back, with the wrecks.
func _fall(u: Unit, m: Dictionary) -> void:
	var p: Vector2 = m.p
	var basis := Basis(Vector3.UP, float(m.yaw)) * Basis(Vector3.RIGHT, -PI * 0.48)
	basis = basis.scaled(Vector3.ONE * Models.tier_scale(u.type, look(u.side)))
	var at := Vector3(p.x, terrain.height(p.x, p.y) + 0.2, p.y)
	_wrecks.append({"type": u.type, "side": u.side, "xform": Transform3D(basis, at), "top": Transform3D(), "t": _clock})
	if _wrecks.size() > 240:
		_wrecks.pop_front()


## A unit died: its wreck lies where it fell, dark, for a while.
func add_wreck(u: Unit) -> void:
	if u.dropping():
		return
	if u.squad > 0: # what was left of the squad
		for m in u.men:
			_fall(u, m)
		u.men.clear()
		return
	var basis := Basis(Vector3.UP, u.yaw)
	var at := u.pos
	if u.kind == "air": # gunships come down where they were
		at.y = terrain.height(at.x, at.z) + 0.6
		basis = basis * Basis(Vector3.FORWARD, 0.5) * Basis(Vector3.RIGHT, 0.2)
	elif u.kind == "land":
		basis = u.tilt * basis * Basis(Vector3.FORWARD, 0.12)
	else:
		basis = basis.scaled(Vector3(1, 0.45, 1)) # a broken stump of a building
	var m: Dictionary = _model(u.type, u.side)
	basis = basis.scaled(Vector3.ONE * Models.tier_scale(u.type, look(u.side)))
	var xf := Transform3D(basis, at)
	var top := Transform3D()
	if m.top:
		top = Transform3D(basis * Basis(Vector3.UP, u.top_yaw - u.yaw + 0.6), xf * (m.top_at as Vector3))
	_wrecks.append({"type": u.type, "side": u.side, "xform": xf, "top": top, "t": _clock})
	if _wrecks.size() > 240:
		_wrecks.pop_front()


func _draw_wrecks() -> void:
	while not _wrecks.is_empty() and _clock - float(_wrecks[0].t) > WRECK_S:
		_wrecks.pop_front()
	if not show_units:
		return
	for w in _wrecks:
		var age: float = _clock - float(w.t)
		var sink := maxf(0.0, age - (WRECK_S - 5.0)) * 0.8
		var xf: Transform3D = w.xform
		xf.origin.y -= sink
		_put(_body(w.type, w.side), xf, Color(0.35, 0.33, 0.3, 0.5))
		if _model(w.type, w.side).top:
			var t: Transform3D = w.top
			t.origin.y -= sink
			_put(_top(w.type, w.side), t, Color(0.35, 0.33, 0.3, 0.5))


## A flat ring one metre across, for the selection rings.
func _ring_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 32
	for k in n:
		var a0 := TAU * k / n
		var a1 := TAU * (k + 1) / n
		var i0 := Vector3(cos(a0), 0, sin(a0)) * 0.86
		var o0 := Vector3(cos(a0), 0, sin(a0))
		var i1 := Vector3(cos(a1), 0, sin(a1)) * 0.86
		var o1 := Vector3(cos(a1), 0, sin(a1))
		for v in [i0, o0, o1, i0, o1, i1]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	return st.commit()
