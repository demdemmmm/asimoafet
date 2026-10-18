extends RefCounted

# Prosedürel ses efektleri (hepsi AudioStreamWAV, 22050 Hz mono).

const RATE := 22050


static func _wav(samples: PackedFloat32Array, looping := false) -> AudioStreamWAV:
	var peak := 0.0001
	for s in samples:
		peak = maxf(peak, absf(s))
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	var gain := 0.9 / peak if peak > 0.9 else 1.0
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i] * gain, -1.0, 1.0) * 30000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	if looping:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = samples.size()
	return stream


static func _buf(seconds: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(seconds * RATE))
	return s


# Konuşma efekti: kısa, yumuşak "bip" (pitch_scale ile ses tonu değişir).
static func blip() -> AudioStreamWAV:
	var s := _buf(0.07)
	for i in s.size():
		var t := float(i) / RATE
		var tone := signf(sin(TAU * 180.0 * t)) * 0.5 + sin(TAU * 360.0 * t) * 0.3
		s[i] = tone * exp(-t * 45.0) * smoothstep(0.0, 0.004, t)
	return _wav(s)


static func zipper() -> AudioStreamWAV:
	# Fermuar: hızlanan diş tıkırtıları.
	var s := _buf(0.9)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var next := 0.0
	var gap := 0.03
	var tick := 0.0
	for i in s.size():
		var t := float(i) / RATE
		if t >= next and t < 0.8:
			tick = 1.0
			next = t + gap
			gap = maxf(0.008, gap * 0.95)
		tick *= 0.9
		s[i] = rng.randf_range(-1.0, 1.0) * tick * 0.8
	return _wav(s)


static func growl() -> AudioStreamWAV:
	# Mide guruldaması: alçak perde kayması + baloncuklu genlik.
	var s := _buf(1.8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var phase := 0.0
	var low := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var f := 70.0 + 40.0 * sin(TAU * 0.7 * t) + 25.0 * sin(TAU * 3.1 * t)
		phase += f / RATE
		low += (rng.randf_range(-1, 1) - low) * 0.05
		var bubble := 0.5 + 0.5 * sin(TAU * (6.0 + 4.0 * sin(t * 2.0)) * t)
		var env := smoothstep(0.0, 0.2, t) * (1.0 - smoothstep(1.4, 1.8, t))
		s[i] = (sin(TAU * phase) * 0.6 + signf(sin(TAU * phase * 2.0)) * 0.15 + low * 1.5) * bubble * env
	return _wav(s)


static func eat() -> AudioStreamWAV:
	# Konserve: kapak halkası "çıt", kapak açılırken metal sürtme + "pşşt", sonra ağız kapalı ıslak
	# çiğneme (çene ritmiyle boğuk hışırtı, ara ara çıtırtı) ve sonunda yutkunma.
	var s := _buf(3.4)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var low := 0.0
	var mid := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var v := 0.0
		var n := rng.randf_range(-1, 1)
		low += (n - low) * 0.08
		mid += (n - mid) * 0.35
		if t < 0.05:
			v += n * exp(-t * 90.0) + sin(TAU * 2300.0 * t) * exp(-t * 70.0) * 0.7
		elif t < 0.55:
			var h := t - 0.05
			# Metal kapak sıyrılır: titreşen tiz ton + hava kaçışı.
			v += sin(TAU * (1300.0 + 400.0 * sin(TAU * 9.0 * h)) * h) * 0.12 * exp(-h * 3.0)
			v += mid * 0.35 * exp(-h * 6.0)
		elif t < 3.0:
			var h := t - 0.55
			var jaw := fmod(h, 0.42)
			var open := sin(PI * clampf(jaw / 0.42, 0.0, 1.0))
			v += low * 2.2 * open * open
			if jaw < 0.05 and rng.randf() < 0.3:
				v += mid * 0.5
		else:
			# Yutkunma: aşağı kayan boğuk "glk".
			var h := t - 3.0
			v += sin(TAU * lerpf(260.0, 120.0, minf(1.0, h / 0.12)) * h) * exp(-h * 16.0) * 0.8 + low * exp(-h * 12.0)
		s[i] = v
	return _wav(s)


static func drink() -> AudioStreamWAV:
	# Şişe kapağı çevrilir, sonra 4 yudum: her yudumda sıvı çalkalanması + gırtlaktan boğuk "glk",
	# en sonda rahatlamış bir nefes ("ahh").
	var s := _buf(3.1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var low := 0.0
	var band := 0.0
	var phase := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var n := rng.randf_range(-1, 1)
		low += (n - low) * 0.05
		band += (n - band) * 0.3
		var v := 0.0
		if t < 0.25:
			# Plastik kapak: kısa tık tık sürtme.
			var k := fmod(t, 0.06)
			v += band * exp(-k * 120.0) * 0.6
		elif t < 2.45:
			var g := fmod(t - 0.25, 0.55)
			# Sıvı akışı (çalkalanan alçak gürültü) yudum başında.
			v += low * 1.6 * exp(-g * 7.0)
			# Gırtlak: 300 Hz'den inen kısa rezonans.
			var gg := g - 0.22
			if gg > 0.0:
				var f := lerpf(330.0, 140.0, minf(1.0, gg / 0.1))
				phase += f / RATE
				v += sin(TAU * phase) * exp(-gg * 22.0) * 0.9
		else:
			var h := t - 2.45
			# "Ahh": nefesli, kısık.
			v += band * 0.35 * sin(PI * clampf(h / 0.6, 0.0, 1.0))
		s[i] = v
	return _wav(s)


static func cloth() -> AudioStreamWAV:
	var s := _buf(0.28)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	var low := 0.0
	for i in s.size():
		var t := float(i) / RATE
		low += (rng.randf_range(-1, 1) - low) * 0.35
		s[i] = low * sin(PI * t / 0.28)
	return _wav(s)


static func whistle() -> AudioStreamWAV:
	# Bilyeli düdük: tiz ton + bilye titreşimi (trill), döngü.
	var s := _buf(1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6
	var phase := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var trill := 0.5 + 0.5 * sin(TAU * 40.0 * t)
		phase += (2900.0 + 120.0 * trill) / RATE
		s[i] = sin(TAU * phase) * (0.6 + 0.4 * trill) + rng.randf_range(-1, 1) * 0.08
	return _wav(s, true)


static func dig() -> AudioStreamWAV:
	# Kazma: metalik vuruşlar + taş döküntüsü (döngü).
	var s := _buf(1.1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 15
	for i in s.size():
		var t := float(i) / RATE
		var v := 0.0
		for hit in [0.0, 0.55]:
			var h: float = t - hit
			if h >= 0.0:
				v += (sin(TAU * 3100.0 * h) * 0.5 + sin(TAU * 4700.0 * h) * 0.3) * exp(-h * 30.0)
				v += rng.randf_range(-1, 1) * 0.5 * exp(-h * 9.0)
		s[i] = v
	return _wav(s, true)


static func machine() -> AudioStreamWAV:
	# Kırıcı/iş makinesi: motor uğultusu + hızlı darbeler (döngü).
	var s := _buf(1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	for i in s.size():
		var t := float(i) / RATE
		var hum := sin(TAU * 90.0 * t) * 0.3 + signf(sin(TAU * 45.0 * t)) * 0.15
		var hammer := rng.randf_range(-1, 1) * exp(-fmod(t, 0.04) * 120.0) * 0.6
		s[i] = hum + hammer
	return _wav(s, true)


static func crash() -> AudioStreamWAV:
	# Çöküş: derin gümbürtü, çatırtılar, düşen moloz.
	var s := _buf(3.2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var low := 0.0
	var crack := 0.0
	for i in s.size():
		var t := float(i) / RATE
		low += (rng.randf_range(-1, 1) - low) * 0.02
		if rng.randf() < 0.003 * exp(-t * 0.6):
			crack = rng.randf_range(0.5, 1.0)
		crack *= 0.992
		var boom := sin(TAU * 38.0 * t) * exp(-t * 1.6) * 0.8
		s[i] = (low * 4.0 + boom) * exp(-t * 0.7) + rng.randf_range(-1, 1) * crack * 0.7
	return _wav(s)


static func drill() -> AudioStreamWAV:
	# Matkap: yükselen motor vızıltısı, vida sıkışınca zorlanma.
	var s := _buf(1.3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var phase := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var f := lerpf(380.0, 820.0, smoothstep(0.0, 0.3, t)) - (180.0 * smoothstep(0.8, 1.1, t))
		phase += f / RATE
		var saw := fmod(phase, 1.0) * 2.0 - 1.0
		var env := smoothstep(0.0, 0.05, t) * (1.0 - smoothstep(1.15, 1.3, t))
		s[i] = (saw * 0.5 + rng.randf_range(-1, 1) * 0.15) * env
	return _wav(s)


static func drill_loop() -> AudioStreamWAV:
	# Matkap motoru (döngü): testere dalga vızıltı + dişli hışırtısı.
	var s := _buf(0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 43
	for i in s.size():
		var t := float(i) / RATE
		var saw := fmod(t * 700.0, 1.0) * 2.0 - 1.0
		s[i] = saw * 0.45 + sin(TAU * 1400.0 * t) * 0.1 + rng.randf_range(-1, 1) * 0.12
	return _wav(s, true)


static func sink_crack() -> AudioStreamWAV:
	# Seramik lavabonun çatlaması: keskin çıtırtılar + kırılan parça şıkırtısı.
	var s := _buf(1.1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 61
	for i in s.size():
		var t := float(i) / RATE
		var v := 0.0
		for hit in [0.0, 0.07, 0.16, 0.42]:
			var h: float = t - hit
			if h >= 0.0:
				v += (sin(TAU * 2600.0 * h) * 0.4 + sin(TAU * 4100.0 * h) * 0.3 + rng.randf_range(-1, 1) * 0.6) * exp(-h * 38.0)
		s[i] = v
	return _wav(s)


static func water_rush() -> AudioStreamWAV:
	# Patlak borudan fışkıran su (döngü): renkli gürültü + şırıltı.
	var s := _buf(1.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 64
	var low := 0.0
	for i in s.size():
		var t := float(i) / RATE
		low += (rng.randf_range(-1, 1) - low) * 0.18
		var gurgle := sin(TAU * (300.0 + 120.0 * sin(TAU * 3.0 * t)) * t) * 0.15 * (0.5 + 0.5 * sin(TAU * 5.0 * t))
		var edge := minf(1.0, minf(float(i), float(s.size() - i)) / 600.0)
		s[i] = (low * 1.2 + rng.randf_range(-1, 1) * 0.25 + gurgle) * edge
	return _wav(s, true)


static func tick() -> AudioStreamWAV:
	# Ahşap duvar saati tıkırtısı (yumuşak).
	var s := _buf(0.09)
	for i in s.size():
		var t := float(i) / RATE
		s[i] = (sin(TAU * 1900.0 * t) * 0.5 + sin(TAU * 950.0 * t) * 0.4) * exp(-t * 70.0)
	return _wav(s)


static func chime() -> AudioStreamWAV:
	# Sıcak, yumuşak saat çanı (iki nota).
	var s := _buf(2.6)
	for i in s.size():
		var t := float(i) / RATE
		var v := 0.0
		for note in [[0.0, 523.25], [0.35, 392.0]]:
			var h: float = t - note[0]
			if h >= 0.0:
				var f: float = note[1]
				v += (sin(TAU * f * h) + sin(TAU * f * 2.01 * h) * 0.35 + sin(TAU * f * 3.0 * h) * 0.12) * exp(-h * 1.6)
		s[i] = v * 0.5
	return _wav(s)


static func squeak() -> AudioStreamWAV:
	# Lastik ördek "vaak": hızla yükselip inen ince ses.
	var s := _buf(0.35)
	var phase := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var f := 900.0 + 900.0 * sin(PI * t / 0.35)
		phase += f / RATE
		var v := signf(sin(TAU * phase)) * 0.3 + sin(TAU * phase * 2.0) * 0.3
		s[i] = v * sin(PI * t / 0.35)
	return _wav(s)


# Derin tek kalp atışı ("güm-güm"): göğüsten gelen boğuk vuruş. lub: 62→36 Hz'e kayan alçak ton,
# alt oktav ve boğuk bir darbe; dub: 0.17 sn sonra daha kısa ve hafif. Yumuşak doyum (tanh) gövde katar.
static func heart_thump() -> AudioStreamWAV:
	var s := _buf(0.55)
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	var thud := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var v := 0.0
		for beat in [[0.0, 1.0, 62.0, 36.0, 15.0], [0.17, 0.62, 54.0, 40.0, 22.0]]:
			var h: float = t - beat[0]
			if h < 0.0:
				continue
			var f: float = lerpf(beat[2], beat[3], minf(1.0, h / 0.09))
			var env := minf(1.0, h / 0.006) * exp(-h * beat[4])
			v += (sin(TAU * f * h) + 0.55 * sin(TAU * f * 0.5 * h)) * env * beat[1]
		# Boğuk darbe: alçak geçiren gürültü, yalnız ilk birkaç ms.
		thud += (rng.randf_range(-1.0, 1.0) - thud) * 0.06
		v += thud * exp(-t * 60.0) * 1.4 + thud * exp(-maxf(t - 0.17, 0.0) * 70.0) * (0.8 if t >= 0.17 else 0.0)
		s[i] = tanh(v * 1.6) * 0.9
	return _wav(s, false)


static func heartbeat() -> AudioStreamWAV:
	# Döngülü kalp atışı (~70 BPM) aynı derin vuruştan kurulur.
	var one := heart_thump()
	var beat := one.data
	var count := int(RATE * 0.86)
	var s := _buf(0.86)
	for i in mini(count, beat.size() / 2):
		s[i] = beat.decode_s16(i * 2) / 30000.0
	return _wav(s, true)


static func rumble() -> AudioStreamWAV:
	# Deprem uğultusu (döngü): çok alçak geçiren kahverengi gürültü + derin titreşim; motor/matkap gibi
	# tonal vızıltı içermez.
	var s := _buf(2.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 71
	var brown := 0.0
	var low := 0.0
	for i in s.size():
		var t := float(i) / RATE
		brown = clampf(brown + rng.randf_range(-1.0, 1.0) * 0.04, -1.0, 1.0) * 0.998
		low += (brown - low) * 0.02
		var swell := 0.75 + 0.25 * sin(TAU * 0.5 * t)
		var edge := minf(1.0, minf(float(i), float(s.size() - i)) / 1500.0)
		s[i] = low * 3.0 * swell * edge
	return _wav(s, true)


static func grunt() -> AudioStreamWAV:
	# Zorlanma iniltisi "hıııh!".
	var s := _buf(0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 51
	var phase := 0.0
	for i in s.size():
		var t := float(i) / RATE
		phase += (130.0 + 30.0 * sin(PI * t / 0.5)) / RATE
		var env := smoothstep(0.0, 0.05, t) * (1.0 - smoothstep(0.35, 0.5, t))
		var v := 0.0
		for k in range(1, 8):
			v += sin(TAU * phase * k) / k * (1.0 if k < 4 else 0.4)
		s[i] = (v * 0.5 + rng.randf_range(-1, 1) * 0.2) * env
	return _wav(s)
