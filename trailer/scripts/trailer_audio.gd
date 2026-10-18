extends Node

# Fragman sesi: dört kanal (MUSIC, DIALOGUE, AMBIENCE, SFX) çalışma anında oluşturulan bus'lara
# bağlıdır; projenin bus düzeni değişmez. Müzik ve efektlerin hepsi burada prosedürel üretilir
# (dış kaynaklı/lisanslı ses yok). Saat tıkırtısı yönetmenin saatiyle ilerler (ayrı Timer yok).

const Sfx = preload("res://scripts/sfx.gd")
const VoiceSynth = preload("res://scripts/voice_synth.gd")
const RATE := 22050
const BUSES := {"MUSIC": -5.0, "DIALOGUE": 0.0, "AMBIENCE": -3.0, "SFX": -2.0}
# Üçlü bölümdeki oyun örneklerinin kendi sesleri (aynı deprem üç kez) karışıma girmez.
const SILENT_BUS := "TRAILER_SILENT"

var stems := {}
var fx := {}
var music_a: AudioStreamPlayer
var music_b: AudioStreamPlayer
var current_music: AudioStreamPlayer
var ticking := false
var tick_clock := 0.0
var tick_flip := false
var tick_player: AudioStreamPlayer
var blip_player: AudioStreamPlayer
var sfx_pool: Array = []
var duck := 0.0
var duck_tween: Tween


func _ready() -> void:
	for name in BUSES:
		if AudioServer.get_bus_index(name) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, name)
			AudioServer.set_bus_send(i, &"Master")
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(name), BUSES[name])
	if AudioServer.get_bus_index(SILENT_BUS) == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, SILENT_BUS)
	AudioServer.set_bus_mute(AudioServer.get_bus_index(SILENT_BUS), true)
	# Ana çıkışta tepe sınırlayıcı (yalnız bu süreçte): üst üste binen efektler kırpılmasın.
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -1.0
	AudioServer.add_bus_effect(0, limiter)
	music_a = _player("MUSIC")
	music_b = _player("MUSIC")
	tick_player = _player("AMBIENCE")
	tick_player.stream = Sfx.tick()
	tick_player.max_polyphony = 2
	blip_player = _player("DIALOGUE")
	blip_player.stream = Sfx.blip()
	blip_player.max_polyphony = 4
	for i in 6:
		sfx_pool.append(_player("SFX"))
	_build()


func _player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p


# --- Oynatma -----------------------------------------------------------------------

func play_music(stem: String, fade := 0.6, db := 0.0) -> void:
	var next := music_b if current_music == music_a else music_a
	next.stream = stems[stem]
	next.volume_db = -40.0 if fade > 0.0 else db
	next.play()
	create_tween().tween_property(next, "volume_db", db, maxf(fade, 0.01))
	if current_music != null and current_music.playing:
		var old := current_music
		var tw := create_tween()
		tw.tween_property(old, "volume_db", -50.0, maxf(fade, 0.01))
		tw.tween_callback(old.stop)
	current_music = next


func stop_music(fade := 0.0) -> void:
	for p in [music_a, music_b]:
		if not p.playing:
			continue
		if fade <= 0.0:
			p.stop()
		else:
			var tw := create_tween()
			tw.tween_property(p, "volume_db", -50.0, fade)
			tw.tween_callback(p.stop)


# Tek seferlik efekt. Döngülü akışlar (deprem uğultusu, düdük) verilen sürede yumuşakça susar;
# süre verilmezse akışın bir turu kadar çalar (hiçbir efekt sonsuza dek açık kalmaz).
func sfx(name: String, db := 0.0, pitch := 1.0, bus := "SFX", seconds := -1.0) -> void:
	var p: AudioStreamPlayer = null
	for q in sfx_pool:
		if not q.playing:
			p = q
			break
	if p == null:
		p = sfx_pool[0]
	p.bus = bus
	p.stream = fx[name]
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()
	var stream: AudioStream = fx[name]
	if seconds < 0.0 and stream is AudioStreamWAV and stream.loop_mode != AudioStreamWAV.LOOP_DISABLED:
		seconds = stream.get_length() / pitch
	if seconds > 0.0:
		var tw := p.create_tween()
		tw.tween_interval(maxf(0.0, seconds - 0.4))
		tw.tween_property(p, "volume_db", -60.0, 0.4)
		tw.tween_callback(p.stop)


func set_ticking(on: bool) -> void:
	ticking = on
	tick_clock = 0.0


func tick_once() -> void:
	tick_player.pitch_scale = 1.0
	tick_player.play()


# Diyalog altındayken müzik kısılır.
func set_duck(on: bool) -> void:
	if duck_tween != null and duck_tween.is_valid():
		duck_tween.kill()
	duck_tween = create_tween()
	duck_tween.tween_method(func(v: float):
		duck = v
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("MUSIC"), BUSES["MUSIC"] + v), duck, -7.0 if on else 0.0, 0.3)


func blip(voice: String) -> void:
	var base: float = {"man": 0.8, "wife": 1.55}.get(voice, 1.0)
	blip_player.pitch_scale = base * randf_range(0.9, 1.1)
	blip_player.play()


# Yönetmen her karede çağırır: saat tıkırtısı aynı merkezi zamanla ilerler.
func update(delta: float) -> void:
	if not ticking:
		return
	tick_clock -= delta
	if tick_clock <= 0.0:
		tick_clock += 1.0
		tick_flip = not tick_flip
		tick_player.pitch_scale = 1.0 if tick_flip else 0.86
		tick_player.play()


# --- Üretim ------------------------------------------------------------------------

func _build() -> void:
	stems["calm"] = _calm(9.8)
	stems["tension"] = _tension(5.0)
	stems["loop"] = _loop(10.5)
	stems["choices"] = _choices(6.0)
	stems["emotional"] = _emotional(11.4)
	fx["tick"] = Sfx.tick()
	fx["chime"] = Sfx.chime()
	fx["rumble"] = Sfx.rumble()
	fx["crash"] = Sfx.crash()
	fx["whistle"] = Sfx.whistle()
	fx["zipper"] = Sfx.zipper()
	fx["drill"] = Sfx.drill()
	fx["squeak"] = Sfx.squeak()
	fx["cloth"] = Sfx.cloth()
	fx["meow"] = VoiceSynth.meow(0)
	fx["meow2"] = VoiceSynth.meow(2)
	fx["static"] = _static(1.4)
	fx["power_out"] = _power_out()
	fx["click"] = _click()
	fx["creak"] = _creak(1.3)
	fx["boom"] = _boom()
	fx["ring"] = _ring()
	fx["zap"] = _zap()
	fx["buzz"] = _buzz(1.6)


func _buf(seconds: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(seconds * RATE))
	return s


# Akorlar: Am, F, C, G (Hz, üç ses).
const CHORDS := [[220.0, 261.63, 329.63], [174.61, 220.0, 261.63], [196.0, 261.63, 329.63], [196.0, 246.94, 293.66]]


func _calm(dur: float) -> AudioStreamWAV:
	# Sakin gece: yumuşak pad + uzaktan müzik kutusu arpeji; yavaş açılır, sonda söner.
	var s := _buf(dur)
	for i in s.size():
		var t := float(i) / RATE
		var v := 0.0
		var c := int(t / 3.0)
		for k in [c, c - 1]:
			if k < 0:
				continue
			var u: float = t - k * 3.0
			var env := minf(u / 0.9, 1.0) * clampf((3.5 - u) / 0.5, 0.0, 1.0)
			if env <= 0.0:
				continue
			for f in CHORDS[k % 4]:
				v += (sin(TAU * f * t) + 0.35 * sin(TAU * f * 2.003 * t)) * env * 0.06
		var n := int(t / 0.5)
		var age := t - n * 0.5
		var tone: float = CHORDS[int(n * 0.5 / 3.0) % 4][n % 3] * 2.0
		v += (sin(TAU * tone * age) * 0.18 + sin(TAU * tone * 3.0 * age) * 0.04) * exp(-age * 4.5)
		var master := minf(t / 3.0, 1.0) * clampf((dur - t) / 1.5, 0.0, 1.0)
		s[i] = v * master
	return Sfx._wav(s)


func _tension(dur: float) -> AudioStreamWAV:
	# Gerilim: vuruşlu alçak drone, yükselen rüzgâr gürültüsü, düzensiz derin darbeler.
	var s := _buf(dur)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var low := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var v := (sin(TAU * 55.0 * t) + 0.8 * sin(TAU * 58.3 * t) + 0.3 * sin(TAU * 110.0 * t)) * 0.22
		low += (rng.randf_range(-1, 1) - low) * 0.02
		v += low * 1.6 * minf(t / dur, 1.0)
		for hit in [0.4, 2.6, 4.1, 5.3, 6.2]:
			var h: float = t - hit
			if h >= 0.0 and h < 1.2:
				v += sin(TAU * (40.0 + 60.0 * exp(-h * 18.0)) * h) * exp(-h * 3.5) * 0.7
		var tremolo := 0.6 + 0.4 * sin(TAU * (3.0 + t) * t)
		v += sin(TAU * 311.1 * t) * 0.05 * tremolo * minf(t / 3.0, 1.0)
		s[i] = v * minf(t / 0.3, 1.0) * clampf((dur - t) / 0.4, 0.0, 1.0)
	return Sfx._wav(s)


func _loop(dur: float) -> AudioStreamWAV:
	# Zaman döngüsü: 100 BPM ritim — kick, tik-tak saat tıkı, bas ostinato ve artan pad.
	var s := _buf(dur)
	var beat := 0.6
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var bass_notes := [55.0, 55.0, 65.41, 49.0]
	for i in s.size():
		var t := float(i) / RATE
		var b := int(t / beat)
		var age := t - b * beat
		var v := sin(TAU * (45.0 + 80.0 * exp(-age * 25.0)) * age) * exp(-age * 7.0) * 0.9
		var off := age - beat * 0.5
		if off >= 0.0:
			v += rng.randf_range(-1, 1) * exp(-off * 45.0) * 0.18
			var tick_f := 1900.0 if b % 2 == 0 else 1600.0
			v += sin(TAU * tick_f * off) * exp(-off * 70.0) * 0.22
		var bf: float = bass_notes[b % 4]
		v += (sin(TAU * bf * t) + 0.3 * sin(TAU * bf * 3.0 * t)) * 0.28 * minf(age / 0.02, 1.0) * exp(-age * 1.5)
		var build := minf(t / dur, 1.0)
		v += sin(TAU * 220.0 * t) * sin(TAU * 0.5 * t) * 0.06 * build
		v += sin(TAU * 329.63 * t) * 0.04 * build
		s[i] = v * minf(t / 0.05, 1.0)
	return Sfx._wav(s)


func _choices(dur: float) -> AudioStreamWAV:
	# Kararlar: 96 BPM sekizlik arpej + yumuşak nabız; 9. saniyeden sonra yalnız kalp atışı kalır.
	var s := _buf(dur)
	var eighth := 0.3125
	for i in s.size():
		var t := float(i) / RATE
		var v := 0.0
		var arp_gain := clampf((dur - 2.0 - t) / 0.8, 0.0, 1.0)
		if arp_gain > 0.0:
			var n := int(t / eighth)
			var age := t - n * eighth
			var chord: Array = CHORDS[int(t / 2.5) % 4]
			var f: float = chord[[0, 1, 2, 1][n % 4]] * (2.0 if n % 8 >= 4 else 1.0)
			v += (sin(TAU * f * age) + 0.4 * sin(TAU * f * 2.0 * age)) * exp(-age * 6.0) * 0.32 * arp_gain
			var bt := fmod(t, eighth * 2.0)
			v += sin(TAU * (50.0 + 50.0 * exp(-bt * 30.0)) * bt) * exp(-bt * 9.0) * 0.5 * arp_gain
		# Kalp atışı (lub-dub) bütün bölüm boyunca, sona doğru öne çıkar.
		var hb := fmod(t, 1.0)
		for d in [0.0, 0.22]:
			var h: float = hb - d
			if h >= 0.0:
				v += sin(TAU * 52.0 * h) * exp(-h * 18.0) * (0.35 + 0.35 * (1.0 - arp_gain))
		s[i] = v * minf(t / 0.4, 1.0) * clampf((dur - t) / 0.6, 0.0, 1.0)
	return Sfx._wav(s)


func _emotional(dur: float) -> AudioStreamWAV:
	# Son umut: F–G–Am–C üzerinde kabaran yaylı pad ve yükselen melodi; sonda aniden kesilir.
	var s := _buf(dur)
	var prog := [[174.61, 220.0, 261.63], [196.0, 246.94, 293.66], [220.0, 261.63, 329.63], [261.63, 329.63, 392.0]]
	var melody := [440.0, 523.25, 587.33, 523.25, 659.25, 587.33, 698.46, 783.99]
	var step := dur / melody.size()
	for i in s.size():
		var t := float(i) / RATE
		var cresc := 0.35 + 0.65 * minf(t / (dur - 0.6), 1.0)
		var c := int(t / 2.45) % 4
		var u := fmod(t, 2.45)
		var env := minf(u / 0.6, 1.0)
		var v := 0.0
		for f in prog[c]:
			for det in [0.997, 1.0, 1.004]:
				v += sin(TAU * f * det * t) * 0.035 * env
			v += sin(TAU * f * 0.5 * t) * 0.03 * env
		var m := mini(int(t / step), melody.size() - 1)
		var mu := t - m * step
		var mf: float = melody[m] * (1.0 + 0.004 * sin(TAU * 5.0 * t))
		v += (sin(TAU * mf * t) + 0.25 * sin(TAU * mf * 2.0 * t)) * 0.16 * minf(mu / 0.15, 1.0) * (0.7 + 0.3 * exp(-mu * 1.5))
		s[i] = v * cresc * minf(t / 0.5, 1.0)
	return Sfx._wav(s)


func _static(dur: float) -> AudioStreamWAV:
	# Televizyon paraziti: cızırtı + kesik çatırtılar.
	var s := _buf(dur)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var prev := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var n := rng.randf_range(-1, 1)
		var hp := n - prev
		prev = n
		var gate := 1.0 if fmod(t * 13.0, 1.0) < 0.75 else 0.3
		s[i] = hp * 0.35 * gate * minf(t / 0.05, 1.0) * clampf((dur - t) / 0.3, 0.0, 1.0)
	return Sfx._wav(s)


func _power_out() -> AudioStreamWAV:
	# Elektrik kesintisi: kısa çat sesi, ardından aşağı inen trafo uğultusu.
	var s := _buf(1.2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for i in s.size():
		var t := float(i) / RATE
		var f := 120.0 * exp(-t * 2.2) + 25.0
		var v := sin(TAU * f * t) * 0.5 * exp(-t * 1.8)
		v += rng.randf_range(-1, 1) * exp(-t * 30.0) * 0.6
		s[i] = v
	return Sfx._wav(s)


func _click() -> AudioStreamWAV:
	# Fener düğmesi: iki kısa tık.
	var s := _buf(0.12)
	for i in s.size():
		var t := float(i) / RATE
		var v := sin(TAU * 2600.0 * t) * exp(-t * 120.0)
		if t > 0.05:
			v += sin(TAU * 1800.0 * (t - 0.05)) * exp(-(t - 0.05) * 110.0) * 0.8
		s[i] = v * 0.7
	return Sfx._wav(s)


func _creak(dur: float) -> AudioStreamWAV:
	# Ahşap dolap gıcırtısı: titreşen perde ve sürtünme.
	var s := _buf(dur)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var ph := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var f := 180.0 + 70.0 * sin(TAU * 0.7 * t) + 30.0 * sin(TAU * 7.0 * t)
		ph += TAU * f / RATE
		var saw := fmod(ph / TAU, 1.0) * 2.0 - 1.0
		var grain := 1.0 if fmod(t * 31.0, 1.0) < 0.6 else 0.4
		s[i] = (saw * 0.25 + rng.randf_range(-1, 1) * 0.08) * grain * sin(PI * t / dur)
	return Sfx._wav(s)


func _boom() -> AudioStreamWAV:
	# Logo darbesi: derin, yumuşak alt frekans.
	var s := _buf(2.4)
	for i in s.size():
		var t := float(i) / RATE
		s[i] = (sin(TAU * (32.0 + 40.0 * exp(-t * 6.0)) * t) * 0.9 + sin(TAU * 64.0 * t) * 0.2) * exp(-t * 1.6) * minf(t / 0.01, 1.0)
	return Sfx._wav(s)


func _zap() -> AudioStreamWAV:
	# Elektrik arkı: keskin çatırtı patlamaları + 100 Hz şebeke vızıltısı, hızla söner.
	var s := _buf(0.7)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var prev := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var n := rng.randf_range(-1, 1)
		var crack := (n - prev) * (1.0 if rng.randf() < 0.35 else 0.15)
		prev = n
		var hum := signf(sin(TAU * 100.0 * t)) * 0.25 + sin(TAU * 200.0 * t) * 0.15
		s[i] = (crack * 0.9 + hum) * exp(-t * 5.0) * minf(t / 0.004, 1.0)
	return Sfx._wav(s)


func _buzz(dur: float) -> AudioStreamWAV:
	# Elektrikli su uğultusu: titreşen 50/100 Hz ve ara ara cızırtı.
	var s := _buf(dur)
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	for i in s.size():
		var t := float(i) / RATE
		var v := sin(TAU * 100.0 * t) * 0.35 + signf(sin(TAU * 50.0 * t)) * 0.12
		if fmod(t * 9.0, 1.0) < 0.12:
			v += rng.randf_range(-1, 1) * 0.5
		s[i] = v * minf(t / 0.05, 1.0) * clampf((dur - t) / 0.3, 0.0, 1.0)
	return Sfx._wav(s)


func _ring() -> AudioStreamWAV:
	# Telefon zili: iki tonlu kısa çalış (bir kez).
	var s := _buf(1.3)
	for i in s.size():
		var t := float(i) / RATE
		var on := 1.0 if t < 1.0 and fmod(t * 20.0, 1.0) < 0.5 else 0.0
		s[i] = (sin(TAU * 440.0 * t) + sin(TAU * 480.0 * t)) * 0.3 * on * clampf((1.3 - t) / 0.3, 0.0, 1.0)
	return Sfx._wav(s)
