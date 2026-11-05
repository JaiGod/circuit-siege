extends Node
## Circuit Siege - every sound is synthesised at startup into AudioStreamWAV
## buffers (no audio files). WAV samples work on the single-threaded Web export.

const RATE := 22050
var enabled := true
var streams := {}
var players: Array[AudioStreamPlayer] = []
var music: AudioStreamPlayer
var next := 0
var last := {}


func _ready() -> void:
	for i in 12:
		var p := AudioStreamPlayer.new()
		p.volume_db = -8.0
		add_child(p)
		players.append(p)
	#                       dur   f0    f1   wave noise vol
	streams["build"] = _tone(0.12, 520, 880, 3, 0.0, 0.45)
	streams["wall"] = _tone(0.07, 300, 220, 1, 0.1, 0.30)
	streams["sell"] = _tone(0.18, 900, 400, 3, 0.0, 0.40)
	streams["upgrade"] = _tone(0.32, 440, 1500, 3, 0.0, 0.50)
	streams["deny"] = _tone(0.16, 180, 140, 1, 0.1, 0.40)
	streams["bullet"] = _tone(0.06, 1300, 700, 1, 0.0, 0.16)
	streams["virus"] = _tone(0.10, 400, 900, 0, 0.3, 0.22)
	streams["flak"] = _tone(0.07, 600, 200, 1, 0.7, 0.22)
	streams["bomb"] = _tone(0.14, 260, 520, 0, 0.0, 0.30)
	streams["zap"] = _tone(0.10, 1800, 500, 2, 0.6, 0.22)
	streams["rail"] = _tone(0.30, 2200, 120, 2, 0.35, 0.45)
	streams["boom"] = _tone(0.28, 160, 40, 2, 0.8, 0.50)
	streams["kill"] = _tone(0.12, 900, 1600, 1, 0.1, 0.20)
	streams["shield"] = _tone(0.18, 1600, 2600, 0, 0.3, 0.28)
	streams["leak"] = _tone(0.45, 220, 60, 2, 0.3, 0.60)
	streams["wave"] = _tone(0.45, 330, 660, 3, 0.0, 0.50)
	streams["clear"] = _tone(0.55, 520, 1560, 3, 0.0, 0.45)
	streams["boss"] = _tone(1.1, 70, 45, 2, 0.3, 0.70)
	streams["bossdie"] = _tone(1.2, 300, 30, 2, 0.6, 0.70)
	streams["blink"] = _tone(0.16, 1500, 300, 0, 0.4, 0.25)
	streams["win"] = _tone(1.0, 330, 1320, 3, 0.0, 0.55)
	streams["lose"] = _tone(1.2, 260, 40, 2, 0.4, 0.65)
	streams["click"] = _tone(0.05, 900, 900, 1, 0.0, 0.22)
	music = AudioStreamPlayer.new()
	music.volume_db = -17.0
	music.stream = _music()
	add_child(music)


func set_enabled(on: bool) -> void:
	enabled = on
	if music == null:
		return
	if on and not music.playing:
		music.play()
	elif not on:
		music.stop()


func play(id: String, pitch_var := 0.06, min_gap := 0.0) -> void:
	if not enabled or not streams.has(id):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if min_gap > 0.0 and now - float(last.get(id, -9.0)) < min_gap:
		return
	last[id] = now
	var p := players[next]
	next = (next + 1) % players.size()
	p.stream = streams[id]
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()


func _tone(dur: float, f0: float, f1: float, wave: int, noise: float, vol: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var ph := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / float(n)
		var f := lerpf(f0, f1, t)
		ph += f / RATE
		var fr := fmod(ph, 1.0)
		var s := 0.0
		match wave:
			0: s = sin(ph * TAU)
			1: s = 1.0 if fr < 0.5 else -1.0
			2: s = fr * 2.0 - 1.0
			_: s = absf(fr * 4.0 - 2.0) - 1.0
		lp = lerpf(lp, randf() * 2.0 - 1.0, 0.4)
		s = lerpf(s, lp * 1.6, noise)
		var env := (1.0 - t) * (1.0 - t)
		var att := minf(1.0, float(i) / (RATE * 0.004))
		data.encode_s16(i * 2, int(clampf(s * env * att * vol, -1.0, 1.0) * 32767.0))
	return _wav(data, RATE, false)


## A short looping synthwave bassline + arpeggio (4 bars, generated once).
func _music() -> AudioStreamWAV:
	var rate := 16000
	var bpm := 112.0
	var step := 60.0 / bpm / 4.0           # 16th notes
	var steps := 64
	var n := int(step * steps * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var roots := [45, 45, 41, 43]          # A, A, F, G (midi)
	var arp := [0, 7, 12, 15, 12, 7, 3, 7]
	var ph_b := 0.0
	var ph_a := 0.0
	for i in n:
		var tt := float(i) / rate
		var si := int(tt / step)
		var st := fmod(tt, step) / step
		var root: int = roots[(si / 16) % 4]
		var fb := 440.0 * pow(2.0, (root - 12 - 69) / 12.0)
		var fa := 440.0 * pow(2.0, (root + 12 + arp[si % 8] - 69) / 12.0)
		ph_b += fb / rate
		ph_a += fa / rate
		var bass := (fmod(ph_b, 1.0) * 2.0 - 1.0) * (1.0 - st * 0.6) * 0.45
		var a := (absf(fmod(ph_a, 1.0) * 4.0 - 2.0) - 1.0) * pow(1.0 - st, 2.0) * 0.28
		var kick := 0.0
		if si % 4 == 0:
			kick = sin(TAU * 55.0 * tt * (1.0 + (1.0 - st) * 2.0)) * pow(1.0 - st, 3.0) * 0.5
		var s := clampf(bass + a + kick, -1.0, 1.0)
		data.encode_s16(i * 2, int(s * 26000.0))
	var w := _wav(data, rate, true)
	w.loop_end = n
	return w


func _wav(data: PackedByteArray, rate: int, loop: bool) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
	return w
