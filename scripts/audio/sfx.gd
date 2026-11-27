class_name Sfx
extends Node
## Procedurally generated sound effects (no audio assets needed) and a pool
## of positional players.

const RATE := 22050

var streams := {}
var pool: Array = []
var pool_i := 0
var ui_player: AudioStreamPlayer
var ambient: AudioStreamPlayer
var _frame_count := 0
var _frame := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for b in ["SFX", "Ambient", "UI"]:
		Game._bus(b)
	streams["rifle"] = _burst(0.35, 17.0, 0.35, 150.0, 0.25, 0.8, 1)
	streams["mg"] = _burst(0.28, 20.0, 0.4, 120.0, 0.3, 0.7, 2)
	streams["hmg"] = _burst(0.45, 13.0, 0.28, 85.0, 0.5, 0.8, 3)
	streams["cannon"] = _burst(0.7, 8.5, 0.22, 70.0, 0.6, 0.9, 4)
	streams["gun"] = _burst(1.3, 4.5, 0.14, 52.0, 0.8, 0.9, 5)
	streams["explosion"] = _burst(2.4, 2.6, 0.07, 38.0, 0.9, 0.6, 6)
	streams["small_expl"] = _burst(1.3, 4.2, 0.11, 58.0, 0.7, 0.6, 7)
	streams["rocket"] = _whoosh(1.0, 8)
	streams["whistle"] = _whistle(1.4)
	streams["engine"] = _engine_loop()
	streams["fpv"] = _buzz_loop()
	streams["wind"] = _wind_loop()
	streams["click"] = _blip(0.05, 1500.0)
	streams["radio"] = _radio()
	streams["thud"] = _burst(0.25, 18.0, 0.1, 90.0, 0.4, 0.0, 9)
	for i in 28:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 22.0
		p.max_db = 4.0
		p.max_distance = 420.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.bus = "SFX"
		add_child(p)
		pool.append(p)
	ui_player = AudioStreamPlayer.new()
	ui_player.volume_db = -10.0
	ui_player.bus = "UI"
	add_child(ui_player)
	ambient = AudioStreamPlayer.new()
	ambient.stream = streams["wind"]
	ambient.volume_db = -20.0
	ambient.bus = "Ambient"
	add_child(ambient)
	ambient.play()


func _process(_delta: float) -> void:
	if not Prof.on:
		_process_body(_delta)
		return
	var t0 := Time.get_ticks_usec()
	_process_body(_delta)
	Prof.add("sfx", t0)


func _process_body(_delta: float) -> void:
	_frame += 1
	_frame_count = 0


func play(sname: String, pos: Vector3, vol: float = 0.0, pitch_var: float = 0.08) -> void:
	if not streams.has(sname):
		return
	_frame_count += 1
	if _frame_count > 6:
		return
	var p: AudioStreamPlayer3D = pool[pool_i]
	pool_i = (pool_i + 1) % pool.size()
	p.stream = streams[sname]
	p.volume_db = vol
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.global_position = pos
	p.play()


func ui(sname: String = "click") -> void:
	if streams.has(sname):
		ui_player.stream = streams[sname]
		ui_player.play()


func make_loop(sname: String, parent: Node3D, vol: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = streams[sname]
	p.bus = "Ambient" if sname == "engine" else "SFX"
	p.unit_size = 18.0
	p.volume_db = vol
	p.max_distance = 300.0
	parent.add_child(p)
	p.play()
	return p


# ------------------------------------------------------------------ synthesis
func _wav(data: PackedByteArray, loop: bool = false) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = data.size() / 2
	return w


func _burst(dur: float, decay: float, lp: float, thump_f: float, thump_amt: float, crack: float, seed: int) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var y := 0.0
	var y2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * decay) * minf(1.0, t / 0.0015)
		var nz := rng.randf_range(-1.0, 1.0)
		y += (nz - y) * lp
		y2 += (y - y2) * lp
		var s := y2 * 2.4 * env
		s += sin(TAU * thump_f * t * (1.0 - t * 0.4)) * thump_amt * exp(-t * decay * 0.6)
		if t < 0.012:
			s += nz * crack * (1.0 - t / 0.012)
		s = clampf(s, -1.0, 1.0)
		data.encode_s16(i * 2, int(s * 30000.0))
	return _wav(data)


func _whoosh(dur: float, seed: int) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := sin(PI * t / dur) * (1.0 if t > 0.03 else t / 0.03 + 0.8)
		y += (rng.randf_range(-1, 1) - y) * 0.25
		var s := clampf(y * 1.8 * env, -1.0, 1.0)
		data.encode_s16(i * 2, int(s * 26000.0))
	return _wav(data)


func _whistle(dur: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := lerpf(1500.0, 650.0, t / dur)
		ph += TAU * f / RATE
		var env := minf(1.0, t / dur * 1.6) * 0.35
		data.encode_s16(i * 2, int(sin(ph) * env * 26000.0))
	return _wav(data)


func _engine_loop() -> AudioStreamWAV:
	var n := RATE
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		var saw := fmod(t * 44.0, 1.0) * 2.0 - 1.0
		y += (rng.randf_range(-1, 1) - y) * 0.05
		var s := saw * 0.25 + y * 0.9 + sin(TAU * 88.0 * t) * 0.15
		s *= 0.8 + 0.2 * sin(TAU * 11.0 * t)
		data.encode_s16(i * 2, int(clampf(s, -1, 1) * 18000.0))
	return _wav(data, true)


func _buzz_loop() -> AudioStreamWAV:
	var n := RATE / 2
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		var s := (fmod(t * 186.0, 1.0) * 2.0 - 1.0) * 0.35 + sin(TAU * 372.0 * t) * 0.2
		data.encode_s16(i * 2, int(s * 18000.0))
	return _wav(data, true)


func _wind_loop() -> AudioStreamWAV:
	var n := RATE * 4
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var y := 0.0
	var y2 := 0.0
	for i in n:
		var t := float(i) / RATE
		y += (rng.randf_range(-1, 1) - y) * 0.03
		y2 += (y - y2) * 0.03
		var env := 0.6 + 0.4 * sin(TAU * t / 4.0)
		data.encode_s16(i * 2, int(clampf(y2 * 6.0 * env, -1, 1) * 20000.0))
	return _wav(data, true)


func _blip(dur: float, f: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		data.encode_s16(i * 2, int(sin(TAU * f * t) * (1.0 - t / dur) * 14000.0))
	return _wav(data)


func _radio() -> AudioStreamWAV:
	var dur := 0.32
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		if t < 0.06:
			s = sin(TAU * 1250.0 * t) * 0.4
		elif t > 0.1:
			y += (rng.randf_range(-1, 1) - y) * 0.5
			s = y * 0.5 * (1.0 - (t - 0.1) / (dur - 0.1))
		data.encode_s16(i * 2, int(s * 20000.0))
	return _wav(data)
