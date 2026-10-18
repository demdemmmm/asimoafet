extends RefCounted

# Basit formant sentezi: bant sınırlı testere kaynağı + 3 rezonatör (F1-F3).
# Perde ve ünlü (formant) eğrileri anahtar karelerle verilir; kedi miyavı ve insan çığlığı üretir.

const RATE := 22050


static func meow(variant := 0) -> AudioStreamWAV:
	# Doğal kedi miyavı "mi-yaaa-uv": nazal "m", parlak "i", geniş "a", kapanan "u"; kedi formantları
	# insandan yüksektir. Varyantlar perde eğrisini ve süreyi değiştirir (her miyav aynı olmasın).
	var lift: float = [1.0, 1.12, 0.92][variant % 3]
	var length: float = [0.85, 0.65, 1.05][variant % 3]
	return _voice(length,
		[[0.0, 620.0 * lift], [0.15, 760.0 * lift], [0.38, 1020.0 * lift], [0.62, 880.0 * lift], [0.85, 640.0 * lift], [1.0, 520.0 * lift]],
		[[0.0, 420.0, 1800.0, 3200.0, 0.2], [0.08, 520.0, 2900.0, 3900.0, 0.8], [0.3, 900.0, 2400.0, 3700.0, 1.0],
			[0.55, 1250.0, 2100.0, 3500.0, 1.0], [0.8, 700.0, 1300.0, 3000.0, 0.6], [1.0, 520.0, 1000.0, 2800.0, 0.0]],
		0.02, 7.5, 0.05, 0.0, 17 + variant)


static func scream() -> AudioStreamWAV:
	# Erkek çığlığı "AaaAAh!": hızlı perde sıçraması, zorlanmış ses (alt armonik + nefes).
	return _voice(1.45,
		[[0.0, 230.0], [0.1, 400.0], [0.45, 430.0], [0.8, 380.0], [1.0, 280.0]],
		[[0.0, 600.0, 1100.0, 2500.0, 0.3], [0.08, 850.0, 1250.0, 2600.0, 1.0], [0.75, 820.0, 1220.0, 2550.0, 0.9],
			[1.0, 700.0, 1150.0, 2500.0, 0.0]],
		0.035, 7.0, 0.22, 0.25, 41)


static func female_scream() -> AudioStreamWAV:
	# Kadın çığlığı "İmdaaat!": yüksek perde, titrek, "i-a" ünlüsü.
	return _voice(1.6,
		[[0.0, 420.0], [0.08, 760.0], [0.5, 820.0], [0.85, 700.0], [1.0, 560.0]],
		[[0.0, 450.0, 2400.0, 3300.0, 0.4], [0.12, 500.0, 2300.0, 3200.0, 0.9], [0.3, 950.0, 1600.0, 3000.0, 1.0],
			[0.85, 900.0, 1500.0, 2900.0, 0.9], [1.0, 800.0, 1400.0, 2800.0, 0.0]],
		0.045, 8.0, 0.18, 0.0, 63)


static func groan() -> AudioStreamWAV:
	# Acı içinde inleme "ıııhh... ahh": alçak, kırık perde, nefesli.
	return _voice(2.2,
		[[0.0, 140.0], [0.2, 175.0], [0.45, 130.0], [0.6, 160.0], [1.0, 105.0]],
		[[0.0, 400.0, 1000.0, 2400.0, 0.2], [0.15, 450.0, 1100.0, 2450.0, 0.85], [0.45, 600.0, 1100.0, 2500.0, 0.5],
			[0.6, 750.0, 1200.0, 2500.0, 0.9], [1.0, 500.0, 1000.0, 2300.0, 0.0]],
		0.04, 5.0, 0.35, 0.3, 88)


static func ah() -> AudioStreamWAV:
	# Kısa acı bağırışı "AH!": ani yükselen ve hızla düşen perde.
	return _voice(0.5,
		[[0.0, 260.0], [0.12, 420.0], [0.5, 330.0], [1.0, 200.0]],
		[[0.0, 700.0, 1200.0, 2600.0, 0.5], [0.1, 900.0, 1300.0, 2700.0, 1.0], [0.7, 800.0, 1200.0, 2600.0, 0.7], [1.0, 600.0, 1100.0, 2500.0, 0.0]],
		0.04, 9.0, 0.25, 0.3, 91)


static func pain_scream() -> AudioStreamWAV:
	# Ezilme anı: ani yüksek "AAH!" sonra boğuk, alçalan inilti "ııh...".
	return _voice(1.9,
		[[0.0, 300.0], [0.06, 560.0], [0.3, 500.0], [0.5, 260.0], [1.0, 150.0]],
		[[0.0, 700.0, 1200.0, 2600.0, 0.4], [0.05, 900.0, 1300.0, 2700.0, 1.0], [0.35, 820.0, 1200.0, 2600.0, 0.9],
			[0.55, 500.0, 1000.0, 2400.0, 0.55], [1.0, 400.0, 900.0, 2300.0, 0.0]],
		0.05, 9.0, 0.3, 0.35, 77)


static func _key(keys: Array, u: float, index: int) -> float:
	for i in range(1, keys.size()):
		if u <= keys[i][0]:
			var a: Array = keys[i - 1]
			var b: Array = keys[i]
			var k := smoothstep(0.0, 1.0, (u - a[0]) / maxf(b[0] - a[0], 0.0001))
			return lerpf(a[index], b[index], k)
	return keys[-1][index]


static func _voice(duration: float, pitch_keys: Array, formant_keys: Array, vibrato_depth: float,
	vibrato_rate: float, breath: float, strain: float, seed: int) -> AudioStreamWAV:
	var count := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var phase := 0.0
	var jitter := 0.0
	var y := [[0.0, 0.0], [0.0, 0.0], [0.0, 0.0]]
	var bandwidths := [110.0, 170.0, 260.0]
	var gains := [1.0, 0.65, 0.35]
	var peak := 0.0001
	for i in count:
		var t := float(i) / RATE
		var u := t / duration
		jitter += (rng.randf_range(-1.0, 1.0) - jitter) * 0.002
		var f0 := _key(pitch_keys, u, 1) * (1.0 + sin(TAU * vibrato_rate * t) * vibrato_depth + jitter * vibrato_depth * 2.0)
		phase += f0 / RATE
		# Bant sınırlı testere: Nyquist altındaki armonikler, 1/k genlik.
		var source := 0.0
		var harmonics := mini(int(9000.0 / f0), 24)
		for k in range(1, harmonics + 1):
			source += sin(TAU * phase * k) / k
		if strain > 0.0:
			source += sin(PI * phase) * strain
		var loud := _key(formant_keys, u, 4)
		var x := source * loud + rng.randf_range(-1.0, 1.0) * breath * (0.4 + loud)
		var sample := 0.0
		for f in 3:
			var freq := _key(formant_keys, u, f + 1)
			var r := exp(-PI * bandwidths[f] / RATE)
			var c := 2.0 * r * cos(TAU * freq / RATE)
			var v: float = (1.0 - r) * x + c * y[f][0] - r * r * y[f][1]
			y[f][1] = y[f][0]
			y[f][0] = v
			sample += v * gains[f]
		var env := smoothstep(0.0, 0.04, u) * (1.0 - smoothstep(0.82, 1.0, u))
		out[i] = sample * env
		peak = maxf(peak, absf(out[i]))
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		data.encode_s16(i * 2, int(clampf(out[i] / peak * 0.85, -1.0, 1.0) * 30000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	return stream
