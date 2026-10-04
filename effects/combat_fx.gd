extends Node3D
## Reusable procedural combat effects. One script, selected by `mode`.
## Create effects through the static factories; use `call("set_charge", x)`,
## `call("set_radius", m)` and `call("finish")` on the returned Node3D.

enum Mode { CHARGE, BEAM, VORTEX, MARKER }

const SynthAudio = preload("res://audio/synth_audio.gd")
const SELF_PATH: String = "res://effects/combat_fx.gd"
const PLASMA: String = "res://effects/shaders/plasma.gdshader"
const ARC: String = "res://effects/shaders/arc.gdshader"
const MARKER: String = "res://effects/shaders/marker.gdshader"
const RING: String = "res://effects/shaders/ring.gdshader"

const BEAM_LIFETIME: float = 0.65
const BEAM_RADIUS: float = 2.5  # outer sheath radius (5 m across at full size)
const MARKER_LIFETIME: float = 0.9
const VORTEX_FADE: float = 0.3

const WHITE: Color = Color(1.0, 1.0, 1.0)
const BLUE: Color = Color(0.25, 0.6, 1.0)
const DEEP_BLUE: Color = Color(0.1, 0.3, 1.0)

var mode: int = Mode.CHARGE

var _t: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _arc_timer: float = 0.0
var _arcs: MeshInstance3D
var _arc_mat: ShaderMaterial
var _light: OmniLight3D

# charge
var _charge_target: float = 0.0
var _charge_cur: float = 0.0
var _core: MeshInstance3D
var _corona: MeshInstance3D
var _core_mat: ShaderMaterial
var _corona_mat: ShaderMaterial

# beam
var _staff: Node3D
var _target: Vector3 = Vector3.ZERO
var _start: Vector3 = Vector3.ZERO
var _len: float = 1.0
var _layers: Array[MeshInstance3D] = []
var _layer_mats: Array[ShaderMaterial] = []
var _layer_radius: Array[float] = []
var _flare: MeshInstance3D
var _burst: MeshInstance3D
var _burst_mat: ShaderMaterial
var _impact: Node3D

# vortex
var _radius: float = 2.5
var _shell: MeshInstance3D
var _inner: MeshInstance3D
var _shell_mat: ShaderMaterial
var _inner_mat: ShaderMaterial
var _disc: MeshInstance3D
var _disc_mat: ShaderMaterial
var _audio: AudioStreamPlayer3D
var _finishing: bool = false
var _fade_out: float = 1.0

# marker
var _arrow: Node3D
var _strokes: Array[MeshInstance3D] = []
var _stroke_mats: Array[ShaderMaterial] = []


# ---------------------------------------------------------------- factories

static func charge(parent: Node3D) -> Node3D:
	var fx: Node3D = _spawn(Mode.CHARGE)
	parent.add_child(fx)
	return fx


static func beam(parent: Node3D, staff: Node3D, target_position: Vector3) -> Node3D:
	var fx: Node3D = _spawn(Mode.BEAM)
	fx.set("_staff", staff)
	fx.set("_target", target_position)
	parent.add_child(fx)
	return fx


static func vortex(parent: Node3D, point: Vector3) -> Node3D:
	var fx: Node3D = _spawn(Mode.VORTEX)
	fx.position = point
	parent.add_child(fx)
	return fx


static func move_marker(parent: Node3D, point: Vector3) -> Node3D:
	var fx: Node3D = _spawn(Mode.MARKER)
	fx.position = point
	parent.add_child(fx)
	return fx


static func ring(parent: Node3D, color: Color, radius: float) -> MeshInstance3D:
	var plane: PlaneMesh = PlaneMesh.new()
	var size: float = 2.0 * (radius + 1.0)
	plane.size = Vector2(size, size)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = _shader_mat(RING, {
		"color": color, "size_m": size, "radius_m": radius,
		"thickness_m": 0.09 + radius * 0.02, "intensity": 1.2,
	})
	mi.position.y = 0.04
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


# ------------------------------------------------------------------ public

func set_charge(amount: float) -> void:
	_charge_target = clampf(amount, 0.0, 1.0)


func set_radius(radius_metres: float) -> void:
	_radius = maxf(radius_metres, 0.1)
	if _shell != null:
		_apply_vortex(1.0)


func finish() -> void:
	if _finishing:
		return
	_finishing = true
	if _audio != null:
		_audio.stop()


# ----------------------------------------------------------------- helpers

static func _spawn(m: int) -> Node3D:
	var fx: Node3D = Node3D.new()
	fx.set_script(load(SELF_PATH))
	fx.set("mode", m)
	fx.top_level = true
	return fx


static func _shader_mat(path: String, params: Dictionary) -> ShaderMaterial:
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = load(path) as Shader
	for key: Variant in params:
		m.set_shader_parameter(StringName(String(key)), params[key])
	return m


static func _cylinder(top: float, bottom: float) -> CylinderMesh:
	var c: CylinderMesh = CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = 1.0
	c.radial_segments = 28
	c.rings = 1
	c.cap_top = false
	c.cap_bottom = false
	return c


static func _sphere() -> SphereMesh:
	var s: SphereMesh = SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = 24
	s.rings = 12
	return s


static func _mesh_node(mesh: Mesh, mat: Material, parent: Node) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _plasma(core: Color, edge: Color, intensity: float, activity: float,
		rim_power: float, rim_invert: float, noise_scale: float, flow: Vector3,
		top_fade: float = 0.0) -> ShaderMaterial:
	return _shader_mat(PLASMA, {
		"core_color": core, "edge_color": edge, "intensity": intensity,
		"activity": activity, "rim_power": rim_power, "rim_invert": rim_invert,
		"noise_scale": noise_scale, "flow": flow, "top_fade": top_fade,
		"time_offset": randf() * 50.0,
	})


static func _arc_material(intensity: float) -> ShaderMaterial:
	return _shader_mat(ARC, {"core_color": WHITE, "edge_color": BLUE, "intensity": intensity})


static func _jagged(a: Vector3, b: Vector3, segs: int, jitter: float,
		rng: RandomNumberGenerator) -> PackedVector3Array:
	var pts: PackedVector3Array = PackedVector3Array()
	var dir: Vector3 = b - a
	var ref: Vector3 = Vector3.UP if absf(dir.normalized().y) < 0.9 else Vector3.RIGHT
	var u_axis: Vector3 = dir.cross(ref).normalized()
	var v_axis: Vector3 = dir.cross(u_axis).normalized()
	for i in segs + 1:
		var f: float = float(i) / segs
		var off: float = sin(PI * f) * jitter
		pts.append(a + dir * f + u_axis * rng.randf_range(-off, off) + v_axis * rng.randf_range(-off, off))
	return pts


static func _add_quad(verts: PackedVector3Array, uvs: PackedVector2Array, idx: PackedInt32Array,
		p0: Vector3, p1: Vector3, side: Vector3, hw0: float, hw1: float, u0: float, u1: float) -> void:
	var base: int = verts.size()
	verts.append(p0 - side * hw0)
	verts.append(p0 + side * hw0)
	verts.append(p1 - side * hw1)
	verts.append(p1 + side * hw1)
	uvs.append(Vector2(u0, 0.0))
	uvs.append(Vector2(u0, 1.0))
	uvs.append(Vector2(u1, 0.0))
	uvs.append(Vector2(u1, 1.0))
	idx.append_array(PackedInt32Array([base, base + 1, base + 2, base + 1, base + 3, base + 2]))


static func _finish_mesh(verts: PackedVector3Array, uvs: PackedVector2Array, idx: PackedInt32Array) -> ArrayMesh:
	var mesh: ArrayMesh = ArrayMesh.new()
	if verts.size() == 0:
		return mesh
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Each bolt is a PackedVector3Array; rendered as two crossed tapered ribbons.
static func _bolts_mesh(bolts: Array, width: float) -> ArrayMesh:
	var verts: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var idx: PackedInt32Array = PackedInt32Array()
	for bolt_v: Variant in bolts:
		var pts: PackedVector3Array = bolt_v
		var n: int = pts.size()
		for i in n - 1:
			var t: Vector3 = pts[i + 1] - pts[i]
			if t.length_squared() < 1e-8:
				continue
			t = t.normalized()
			var ref: Vector3 = Vector3.UP if absf(t.y) < 0.9 else Vector3.RIGHT
			var n1: Vector3 = t.cross(ref).normalized()
			var n2: Vector3 = t.cross(n1)
			var f0: float = float(i) / (n - 1)
			var f1: float = float(i + 1) / (n - 1)
			var hw0: float = width * 0.5 * (0.3 + 0.7 * sin(PI * f0))
			var hw1: float = width * 0.5 * (0.3 + 0.7 * sin(PI * f1))
			_add_quad(verts, uvs, idx, pts[i], pts[i + 1], n1, hw0, hw1, f0, f1)
			_add_quad(verts, uvs, idx, pts[i], pts[i + 1], n2, hw0, hw1, f0, f1)
	return _finish_mesh(verts, uvs, idx)


## Flat quad stroke in the XY plane (UV.x along the stroke).
static func _stroke_mesh(a: Vector2, b: Vector2, width: float) -> ArrayMesh:
	var verts: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var idx: PackedInt32Array = PackedInt32Array()
	var d: Vector2 = (b - a).normalized()
	var side: Vector3 = Vector3(-d.y, d.x, 0.0)
	_add_quad(verts, uvs, idx, Vector3(a.x, a.y, 0.0), Vector3(b.x, b.y, 0.0), side, width * 0.5, width * 0.5, 0.0, 1.0)
	return _finish_mesh(verts, uvs, idx)


## Flat circular stroke in the XZ plane (UV.x = angle fraction).
static func _ring_stroke_mesh(radius: float, width: float, segs: int) -> ArrayMesh:
	var verts: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var idx: PackedInt32Array = PackedInt32Array()
	for i in segs:
		var a0: float = TAU * float(i) / segs
		var a1: float = TAU * float(i + 1) / segs
		var p0: Vector3 = Vector3(cos(a0) * radius, 0.0, sin(a0) * radius)
		var p1: Vector3 = Vector3(cos(a1) * radius, 0.0, sin(a1) * radius)
		_add_quad(verts, uvs, idx, p0, p1, Vector3(cos(a0), 0.0, sin(a0)), width * 0.5, width * 0.5,
			float(i) / segs, float(i + 1) / segs)
	return _finish_mesh(verts, uvs, idx)


func _rand_dir() -> Vector3:
	var v: Vector3 = Vector3(_rng.randfn(), _rng.randfn(), _rng.randfn())
	return v.normalized() if v.length_squared() > 1e-6 else Vector3.UP


func _make_arcs(intensity: float) -> void:
	_arc_mat = _arc_material(intensity)
	_arcs = _mesh_node(ArrayMesh.new(), _arc_mat, self)


func _make_light(color: Color) -> OmniLight3D:
	var l: OmniLight3D = OmniLight3D.new()
	l.light_color = color
	l.shadow_enabled = false
	add_child(l)
	return l


# --------------------------------------------------------------- lifecycle

func _ready() -> void:
	_rng.randomize()
	process_priority = 1000  # after animation so staff-attached effects do not lag
	match mode:
		Mode.CHARGE:
			_build_charge()
		Mode.BEAM:
			_build_beam()
		Mode.VORTEX:
			_build_vortex()
		Mode.MARKER:
			_build_marker()


func _exit_tree() -> void:
	if _audio != null:
		_audio.stop()


func _process(delta: float) -> void:
	_t += delta
	match mode:
		Mode.CHARGE:
			_process_charge(delta)
		Mode.BEAM:
			_process_beam(delta)
		Mode.VORTEX:
			_process_vortex(delta)
		Mode.MARKER:
			_process_marker()


# ------------------------------------------------------------------ charge

func _build_charge() -> void:
	_core_mat = _plasma(WHITE, BLUE, 2.5, 1.0, 1.5, 0.0, 6.0, Vector3(0.0, -3.0, 0.0))
	_corona_mat = _plasma(Color(0.6, 0.85, 1.0), DEEP_BLUE, 1.2, 1.5, 1.8, 1.0, 3.0, Vector3(0.0, 2.0, 0.0))
	_core = _mesh_node(_sphere(), _core_mat, self)
	_corona = _mesh_node(_sphere(), _corona_mat, self)
	_make_arcs(3.0)
	_light = _make_light(Color(0.5, 0.75, 1.0))
	_light.omni_range = 7.0
	_set_charge_visible(false)


func _set_charge_visible(v: bool) -> void:
	_core.visible = v
	_corona.visible = v
	_arcs.visible = v
	_light.visible = v


func _process_charge(delta: float) -> void:
	var par: Node3D = get_parent() as Node3D
	if par != null:
		global_transform = Transform3D(Basis.IDENTITY, par.global_position)
	_charge_cur = lerpf(_charge_cur, _charge_target, 1.0 - exp(-delta * 14.0))
	var c: float = _charge_cur
	var charge_visible: bool = c > 0.01
	if _core.visible != charge_visible:
		_set_charge_visible(charge_visible)
	if not charge_visible:
		return
	var pulse: float = 1.0 + 0.08 * sin(_t * 45.0)
	var core_r: float = lerpf(0.1, 0.42, c) * pulse
	var corona_r: float = lerpf(0.25, 1.5, c) * (1.0 + 0.05 * sin(_t * 23.0))
	_core.scale = Vector3.ONE * core_r
	_corona.scale = Vector3.ONE * corona_r
	_core_mat.set_shader_parameter("activity", lerpf(0.6, 3.0, c))
	_corona_mat.set_shader_parameter("activity", lerpf(0.8, 3.5, c))
	_light.light_energy = lerpf(0.5, 6.0, c) * (0.85 + 0.15 * sin(_t * 61.0))
	_arc_timer -= delta
	if _arc_timer <= 0.0:
		_arc_timer = 0.05
		var bolts: Array = []
		var count: int = 1 + roundi(c * 6.0)
		var length: float = lerpf(0.4, 2.2, c)
		for i in count:
			var dir: Vector3 = _rand_dir()
			bolts.append(_jagged(dir * core_r * 0.6, dir * (core_r + length * _rng.randf_range(0.7, 1.2)),
				6, length * 0.18, _rng))
		_arcs.mesh = _bolts_mesh(bolts, 0.16 + 0.22 * c)


# -------------------------------------------------------------------- beam

func _build_beam() -> void:
	if is_instance_valid(_staff) and _staff.is_inside_tree():
		_start = _staff.global_position
	else:
		_start = _target + Vector3(0.0, 3.0, 0.0)
	# [mesh radius multiplier of BEAM_RADIUS, core, edge, intensity, activity, rim_power, rim_invert]
	var specs: Array = [
		[1.0, Color(0.6, 0.85, 1.0), DEEP_BLUE, 1.1, 2.0, 1.4, 0.7, 2.5],
		[0.5, Color(0.9, 0.97, 1.0), BLUE, 1.8, 1.5, 1.5, 0.0, 4.0],
		[0.18, WHITE, Color(0.8, 0.92, 1.0), 4.0, 0.6, 1.0, 0.0, 8.0],
	]
	for spec_v: Variant in specs:
		var spec: Array = spec_v
		var mat: ShaderMaterial = _plasma(spec[1], spec[2], spec[3], spec[4], spec[5], spec[6], spec[7],
			Vector3(0.0, -22.0, 0.0))
		_layer_mats.append(mat)
		_layer_radius.append(BEAM_RADIUS * float(spec[0]))
		_layers.append(_mesh_node(_cylinder(1.0, 1.0), mat, self))
	_flare = _mesh_node(_sphere(), _plasma(WHITE, BLUE, 2.5, 2.0, 1.2, 0.0, 1.5, Vector3(0.0, -8.0, 0.0)), self)
	_make_arcs(3.5)
	_impact = Node3D.new()
	_impact.top_level = true
	add_child(_impact)
	_impact.position = _target
	_burst_mat = _plasma(WHITE, BLUE, 2.0, 2.5, 1.3, 0.3, 1.0, Vector3(0.0, 6.0, 0.0))
	_burst = _mesh_node(_sphere(), _burst_mat, _impact)
	var l: OmniLight3D = OmniLight3D.new()
	l.light_color = Color(0.55, 0.78, 1.0)
	l.light_energy = 8.0
	l.omni_range = 18.0
	_impact.add_child(l)
	_play_blast()
	_update_beam(0.0)


func _play_blast() -> void:
	var host: Node = get_parent()
	var stream: AudioStreamWAV = SynthAudio.stream("blast")
	if host == null or stream == null:
		return
	var p: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	p.stream = stream
	p.unit_size = 25.0
	p.max_distance = 400.0
	p.top_level = true
	p.position = _target
	p.finished.connect(p.queue_free)
	host.add_child.call_deferred(p)
	p.play.call_deferred()


func _process_beam(delta: float) -> void:
	if _t >= BEAM_LIFETIME:
		queue_free()
		return
	_update_beam(delta)


func _update_beam(delta: float) -> void:
	if is_instance_valid(_staff) and _staff.is_inside_tree():
		_start = _staff.global_position
	var u: float = clampf(_t / BEAM_LIFETIME, 0.0, 1.0)
	var ramp: float = 1.0 - pow(1.0 - minf(u / 0.1, 1.0), 3.0)
	var tail: float = clampf((u - 0.6) / 0.4, 0.0, 1.0)
	var env: float = lerpf(0.25, 1.0, ramp) * (1.0 - 0.35 * tail)
	var alpha: float = 1.0 - pow(clampf((u - 0.55) / 0.45, 0.0, 1.0), 2.0)

	var dir: Vector3 = _target - _start
	_len = maxf(dir.length(), 0.1)
	var y: Vector3 = dir / _len if dir.length() > 0.001 else Vector3.DOWN
	var ref: Vector3 = Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT
	var x: Vector3 = ref.cross(y).normalized()
	var z: Vector3 = x.cross(y)
	transform = Transform3D(Basis(x, y, z), _start)

	for i in _layers.size():
		var r: float = _layer_radius[i] * env
		_layers[i].scale = Vector3(r, _len, r)
		_layers[i].position = Vector3(0.0, _len * 0.5, 0.0)
		_layer_mats[i].set_shader_parameter("fade", alpha)
	_flare.scale = Vector3.ONE * (1.1 * env * (1.0 + 0.1 * sin(_t * 50.0)))
	_burst.scale = Vector3.ONE * lerpf(1.0, 4.0, 1.0 - pow(1.0 - minf(u / 0.5, 1.0), 2.0)) * (1.0 - 0.4 * tail)
	_burst_mat.set_shader_parameter("fade", alpha)
	_arc_mat.set_shader_parameter("fade", alpha)

	_arc_timer -= delta
	if _arc_timer <= 0.0:
		_arc_timer = 0.04
		var bolts: Array = []
		var radius: float = BEAM_RADIUS * env
		for i in 3:
			var pts: PackedVector3Array = PackedVector3Array()
			var phase: float = _rng.randf() * TAU
			var turns: float = _rng.randf_range(1.5, 3.5) * maxf(_len / 12.0, 0.5)
			for k in 29:
				var f: float = float(k) / 28.0
				var ang: float = phase + f * turns * TAU
				var rr: float = radius * _rng.randf_range(0.35, 0.9)
				pts.append(Vector3(cos(ang) * rr, f * _len, sin(ang) * rr))
			bolts.append(pts)
		for i in 4:
			var a: Vector3 = Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)) * radius * 0.5
			var b: Vector3 = Vector3(_rng.randf_range(-1.0, 1.0), _len, _rng.randf_range(-1.0, 1.0)) * radius * 0.5
			bolts.append(_jagged(a, Vector3(b.x, _len, b.z), 20, 0.7, _rng))
		for i in 5:
			var rd: Vector3 = _rand_dir()
			bolts.append(_jagged(Vector3(0.0, _len, 0.0), Vector3(0.0, _len, 0.0) + rd * _rng.randf_range(2.5, 5.0),
				7, 0.5, _rng))
		_arcs.mesh = _bolts_mesh(bolts, 0.28 * env)


# ------------------------------------------------------------------ vortex

func _build_vortex() -> void:
	_shell_mat = _plasma(Color(0.8, 0.93, 1.0), DEEP_BLUE, 1.3, 2.0, 1.6, 1.0, 0.8, Vector3(0.0, 4.0, 0.0), 1.0)
	_inner_mat = _plasma(WHITE, BLUE, 1.6, 1.5, 1.4, 0.0, 1.2, Vector3(0.0, 7.0, 0.0), 1.0)
	_shell = _mesh_node(_cylinder(0.7, 1.0), _shell_mat, self)
	_inner = _mesh_node(_cylinder(0.7, 1.0), _inner_mat, self)
	_disc_mat = _shader_mat(RING, {
		"color": Color(0.4, 0.7, 1.0), "fill": 0.45, "spiral": 1.0, "spin": 3.0, "intensity": 1.5,
	})
	_disc = _mesh_node(PlaneMesh.new(), _disc_mat, self)
	_disc.position.y = 0.06
	_make_arcs(3.0)
	_light = _make_light(Color(0.5, 0.75, 1.0))
	_light.position.y = 1.5
	var stream: AudioStreamWAV = SynthAudio.stream("channel")
	if stream != null:
		_audio = AudioStreamPlayer3D.new()
		_audio.stream = stream
		_audio.unit_size = 12.0
		_audio.max_distance = 200.0
		_audio.volume_db = -4.0
		add_child(_audio)
		_audio.play()
	_apply_vortex(0.0)


func _apply_vortex(vis: float) -> void:
	var r: float = _radius
	var h: float = 1.4 + r * 0.18
	var grow: float = 0.3 + 0.7 * vis
	_shell.scale = Vector3(r * grow, h, r * grow)
	_shell.position = Vector3(0.0, h * 0.5, 0.0)
	var ir: float = clampf(r * 0.25, 0.5, 2.0) * grow
	_inner.scale = Vector3(ir, h, ir)
	_inner.position = Vector3(0.0, h * 0.5, 0.0)
	var size: float = 2.0 * (r + 1.0)
	(_disc.mesh as PlaneMesh).size = Vector2(size, size)
	_disc_mat.set_shader_parameter("size_m", size)
	_disc_mat.set_shader_parameter("radius_m", r)
	_disc_mat.set_shader_parameter("thickness_m", 0.15 + 0.05 * r)
	_light.omni_range = 8.0 + r * 2.0


func _process_vortex(delta: float) -> void:
	if _finishing:
		_fade_out -= delta / VORTEX_FADE
		if _fade_out <= 0.0:
			queue_free()
			return
	var vis: float = minf(_t / 0.3, 1.0)
	_apply_vortex(vis)
	var f: float = vis * clampf(_fade_out, 0.0, 1.0)
	_shell_mat.set_shader_parameter("fade", f)
	_inner_mat.set_shader_parameter("fade", f)
	_disc_mat.set_shader_parameter("fade", f)
	_arc_mat.set_shader_parameter("fade", f)
	_light.light_energy = (3.0 + _radius * 0.3) * f * (0.85 + 0.15 * sin(_t * 53.0))
	_shell.rotate_y(delta * 1.5)
	_inner.rotate_y(-delta * 2.5)
	_arc_timer -= delta
	if _arc_timer <= 0.0:
		_arc_timer = 0.06
		var r: float = _radius
		var h: float = 1.4 + r * 0.18
		var bolts: Array = []
		for i in 6 + roundi(r * 0.4):
			var ang: float = _rng.randf() * TAU
			var rr: float = r * _rng.randf_range(0.2, 1.0)
			var top_ang: float = ang + _rng.randf_range(0.5, 1.5)
			var top_r: float = r * 0.3
			bolts.append(_jagged(Vector3(cos(ang) * rr, 0.1, sin(ang) * rr),
				Vector3(cos(top_ang) * top_r, h * _rng.randf_range(0.4, 1.0), sin(top_ang) * top_r),
				10, 0.5 + 0.04 * r, _rng))
		for i in 3:
			var ang2: float = _rng.randf() * TAU
			bolts.append(_jagged(Vector3(cos(ang2) * r, 0.1, sin(ang2) * r), Vector3(0.0, 0.2, 0.0),
				12, 0.4 + 0.03 * r, _rng))
		_arcs.mesh = _bolts_mesh(bolts, (0.12 + 0.015 * r) * vis)


# ------------------------------------------------------------------ marker

func _build_marker() -> void:
	_arrow = Node3D.new()
	add_child(_arrow)
	var specs: Array = [
		[_ring_stroke_mesh(1.1, 0.14, 48), self],
		[_stroke_mesh(Vector2(0.0, 2.8), Vector2(0.0, 0.6), 0.28), _arrow],
		[_stroke_mesh(Vector2(-0.75, 1.35), Vector2(0.0, 0.6), 0.26), _arrow],
		[_stroke_mesh(Vector2(0.75, 1.35), Vector2(0.0, 0.6), 0.26), _arrow],
	]
	for spec_v: Variant in specs:
		var spec: Array = spec_v
		var mat: ShaderMaterial = _shader_mat(MARKER, {"color": Color(0.2, 1.0, 0.35), "progress": 0.0})
		_stroke_mats.append(mat)
		_strokes.append(_mesh_node(spec[0] as Mesh, mat, spec[1] as Node))
	_strokes[0].position.y = 0.05
	_process_marker()


func _process_marker() -> void:
	if _t >= MARKER_LIFETIME:
		queue_free()
		return
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		_arrow.global_basis = cam.global_basis
	var fade: float = 1.0 - clampf((_t - 0.5) / 0.4, 0.0, 1.0)
	var progress: Array[float] = [
		clampf(_t / 0.25, 0.0, 1.0),
		clampf((_t - 0.1) / 0.22, 0.0, 1.0),
		clampf((_t - 0.30) / 0.12, 0.0, 1.0),
		clampf((_t - 0.34) / 0.12, 0.0, 1.0),
	]
	for i in _stroke_mats.size():
		_stroke_mats[i].set_shader_parameter("progress", progress[i])
		_stroke_mats[i].set_shader_parameter("fade", fade)
