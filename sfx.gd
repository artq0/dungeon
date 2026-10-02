extends Node
## Autoload "Sfx": sons sintetizados por código (sem arquivos de áudio).
## Uso: Sfx.play("swing", volume_db, pitch, variacao_de_pitch)

const RATE: int = 22050
const POOL: int = 16
## Volume geral dos efeitos (dB). Mais negativo = mais baixo.
const MASTER_DB: float = -12.0

var sounds: Dictionary = {}   # nome -> Array de AudioStreamWAV (variantes)
var players: Array = []
var next_p: int = 0


func _ready() -> void:
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	_build()


func play(sound: String, vol_db: float = 0.0, pitch: float = 1.0, jitter: float = 0.06) -> void:
	if not sounds.has(sound):
		return
	var variants: Array = sounds[sound]
	var stream: AudioStream = variants[randi() % variants.size()]
	var p: AudioStreamPlayer = null
	for i in POOL:
		var cand: AudioStreamPlayer = players[(next_p + i) % POOL]
		if not cand.playing:
			p = cand
			next_p = (next_p + i + 1) % POOL
			break
	if p == null:
		p = players[next_p]
		next_p = (next_p + 1) % POOL
	p.stream = stream
	p.volume_db = vol_db + MASTER_DB
	p.pitch_scale = maxf(0.1, pitch * randf_range(1.0 - jitter, 1.0 + jitter))
	p.play()


# ---------------------------------------------------------------- catálogo

func _build() -> void:
	sounds["click"] = [_click()]
	sounds["step"] = [_step(0.12), _step(0.2)]
	sounds["swing"] = [_swing(0.10, 0.55), _swing(0.15, 0.65), _swing(0.08, 0.5)]
	sounds["hit"] = [_hit(260.0), _hit(200.0)]
	sounds["hurt"] = [_hurt()]
	sounds["pdie"] = [_player_die()]
	sounds["door_hit"] = [_door_hit(150.0), _door_hit(120.0), _door_hit(180.0)]
	sounds["die0"] = [_die_slime()]
	sounds["die1"] = [_die_bat()]
	sounds["die2"] = [_die_brute()]
	sounds["die3"] = [_die_skeleton(), _die_skeleton()]
	# quebra de porta: várias variantes geradas aleatoriamente + pitch aleatório ao tocar
	var breaks: Array = []
	for i in 4:
		breaks.append(_door_break())
	sounds["door_break"] = breaks


func _click() -> AudioStreamWAV:
	var b: Array = _buf(0.08)
	_tone(b, 0.0, 0.06, 900.0, 600.0, 0.5, 3.0)
	return _to_wav(b)


func _step(lp: float) -> AudioStreamWAV:
	var b: Array = _buf(0.07)
	_noise(b, 0.0, 0.06, 0.5, 2.0, lp, lp * 0.5)
	return _to_wav(b)


func _swing(lp0: float, lp1: float) -> AudioStreamWAV:
	var b: Array = _buf(0.24)
	_noise(b, 0.0, 0.22, 0.6, 1.0, lp0, lp1, true)
	_tone(b, 0.0, 0.2, 380.0, 700.0, 0.06, 0.5)
	return _to_wav(b)


func _hit(f: float) -> AudioStreamWAV:
	var b: Array = _buf(0.16)
	_noise(b, 0.0, 0.1, 0.8, 3.0, 0.5, 0.2)
	_tone(b, 0.0, 0.14, f, f * 0.35, 0.7, 2.5)
	return _to_wav(b)


func _hurt() -> AudioStreamWAV:
	var b: Array = _buf(0.32)
	_tone(b, 0.0, 0.3, 240.0, 70.0, 0.5, 1.5, 1)
	_noise(b, 0.0, 0.1, 0.6, 2.0, 0.5, 0.2)
	return _to_wav(b)


func _player_die() -> AudioStreamWAV:
	var b: Array = _buf(1.0)
	_tone(b, 0.0, 0.9, 330.0, 35.0, 0.55, 1.0, 2)
	_noise(b, 0.0, 0.5, 0.5, 1.5, 0.12, 0.05)
	return _to_wav(b)


func _door_hit(f: float) -> AudioStreamWAV:
	var b: Array = _buf(0.24)
	_noise(b, 0.0, 0.12, 0.9, 3.0, 0.3, 0.08)
	_tone(b, 0.0, 0.16, f, f * 0.45, 0.8, 2.5)
	_noise(b, 0.0, 0.015, 0.7, 1.0, 0.9, 0.9)
	return _to_wav(b)


func _die_slime() -> AudioStreamWAV:
	var b: Array = _buf(0.45)
	_tone(b, 0.0, 0.4, 380.0, 70.0, 0.6, 1.5)
	_tone(b, 0.03, 0.3, 190.0, 55.0, 0.4, 1.5)
	_noise(b, 0.0, 0.15, 0.4, 2.0, 0.2, 0.1)
	return _to_wav(b)


func _die_bat() -> AudioStreamWAV:
	var b: Array = _buf(0.35)
	_tone(b, 0.0, 0.3, 1500.0, 400.0, 0.3, 1.2, 1)
	_tone(b, 0.0, 0.25, 2000.0, 700.0, 0.2, 1.4, 1)
	_noise(b, 0.0, 0.08, 0.5, 2.0, 0.6, 0.3)
	return _to_wav(b)


func _die_brute() -> AudioStreamWAV:
	var b: Array = _buf(0.6)
	_tone(b, 0.0, 0.5, 130.0, 38.0, 0.8, 1.3, 2)
	_noise(b, 0.0, 0.3, 0.7, 2.0, 0.15, 0.06)
	_tone(b, 0.0, 0.1, 300.0, 100.0, 0.5, 2.0)
	return _to_wav(b)


func _die_skeleton() -> AudioStreamWAV:
	var b: Array = _buf(0.5)
	for k in 9:
		var st: float = k * 0.04 + randf() * 0.015
		_noise(b, st, 0.03, 0.8, 2.0, 0.6, 0.3)
		_tone(b, st, 0.03, randf_range(500.0, 900.0), 300.0, 0.2, 2.0)
	return _to_wav(b)


func _door_break() -> AudioStreamWAV:
	var b: Array = _buf(0.8)
	var f: float = randf_range(70.0, 110.0)
	_tone(b, 0.0, 0.35, f * 1.8, f * 0.4, 1.0, 1.6)                   # impacto grave
	_noise(b, 0.0, 0.25, 1.0, 2.0, randf_range(0.25, 0.5), 0.08)       # corpo do estalo
	_noise(b, 0.0, 0.03, 1.0, 1.0, 0.9, 0.9)                           # ataque seco
	for k in randi_range(6, 11):                                       # lascas
		var st: float = randf_range(0.02, 0.5)
		_noise(b, st, randf_range(0.02, 0.06), randf_range(0.3, 0.7), 2.0, randf_range(0.2, 0.7), 0.2)
		if randf() < 0.5:
			_tone(b, st, 0.05, randf_range(200.0, 600.0), 100.0, 0.25, 3.0)
	_noise(b, 0.1, 0.5, 0.35, 1.5, 0.05, 0.03)                         # rumor da queda
	return _to_wav(b)


# ---------------------------------------------------------------- síntese

func _buf(dur: float) -> Array:
	var a: Array = []
	a.resize(int(dur * RATE))
	a.fill(0.0)
	return a


## shape: 0 seno, 1 quadrada, 2 serra
func _tone(buf: Array, start: float, dur: float, f0: float, f1: float, vol: float, decay: float = 2.0, shape: int = 0) -> void:
	var s0: int = int(start * RATE)
	var n: int = mini(int(dur * RATE), buf.size() - s0)
	if n <= 0:
		return
	var ph: float = 0.0
	for i in n:
		var t: float = float(i) / float(n)
		var f: float = f0 * pow(f1 / f0, t)
		ph += f / RATE
		var w: float = sin(ph * TAU)
		if shape == 1:
			w = signf(w) * 0.5
		elif shape == 2:
			w = (2.0 * fmod(ph, 1.0) - 1.0) * 0.6
		var env: float = pow(1.0 - t, decay) * minf(1.0, float(i) / 40.0)
		buf[s0 + i] += w * vol * env


## ruído com filtro passa-baixa (lp0 -> lp1, 0.02..1). bell = envelope em sino (whoosh)
func _noise(buf: Array, start: float, dur: float, vol: float, decay: float, lp0: float, lp1: float, bell: bool = false) -> void:
	var s0: int = int(start * RATE)
	var n: int = mini(int(dur * RATE), buf.size() - s0)
	if n <= 0:
		return
	var lp: float = 0.0
	for i in n:
		var t: float = float(i) / float(n)
		var a: float = clampf(lerpf(lp0, lp1, t), 0.02, 1.0)
		lp += ((randf() * 2.0 - 1.0) - lp) * a
		var gain: float = 0.8 * sqrt((2.0 - a) / a)
		var env: float = sin(t * PI) if bell else pow(1.0 - t, decay) * minf(1.0, float(i) / 30.0)
		buf[s0 + i] += lp * gain * vol * env * 0.5


func _to_wav(buf: Array) -> AudioStreamWAV:
	var n: int = buf.size()
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var v: float = tanh(float(buf[i]))
		data.encode_s16(i * 2, int(v * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w
