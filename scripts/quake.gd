extends Node

# Periyodik sarsıntı: hikâye begin() çağırınca başlar (telefon konuşması); sonra her INTERVAL
# saniyede bir kamera sarsılır, ekran kenarlarından toz/moloz dökülür, lambalar titrer ve
# gerilim müziği çalar. Aradaki sürede hafif titreme (TREMOR) hiç durmaz.
signal quake_started(first: bool)
# Büyük sarsıntıdan WARN saniye önce hafif öncü titreme (habercisi).
signal foreshock_started(seconds: float)

const INTERVAL := 30.0
const WARN := 3.0
const DURATION := 3.0
const SHAKE_PIXELS := 10.0
const MIX_RATE := 22050
const TREMOR := 1.0

var game: Node2D
var count := 0
var timer: Timer
var layer: CanvasLayer
var emitters: Array[CPUParticles2D] = []
var music: AudioStreamPlayer


func _ready() -> void:
	timer = Timer.new()
	timer.wait_time = INTERVAL
	timer.timeout.connect(_foreshock)
	add_child(timer)
	_build_particles()
	music = AudioStreamPlayer.new()
	music.stream = _build_music()
	music.volume_db = -4.0
	add_child(music)
	get_viewport().size_changed.connect(_layout_particles)
	_layout_particles()


# warn: önce öncü titreme (habercisi), sonra büyük sarsıntı.
func begin(warn := false) -> void:
	if count > 0:
		return
	game.camera.tremor = TREMOR
	if warn:
		_foreshock()
	else:
		_on_tick()
	timer.start()


func stop() -> void:
	timer.stop()
	game.camera.tremor = 0.0
	music.stop()
	for emitter in emitters:
		emitter.emitting = false
	game.camera.stop_shake()


func _foreshock() -> void:
	if game.finished:
		return
	game.camera.shake(WARN, 3.5)
	foreshock_started.emit(WARN)
	get_tree().create_timer(WARN).timeout.connect(_on_tick)


func _on_tick() -> void:
	if game.finished:
		return
	# Mini oyun sırasında sarsıntı yaşanmaz; bu dalga atlanır.
	if count > 0 and game.story.minigame_active():
		return
	count += 1
	game.camera.shake(DURATION, SHAKE_PIXELS)
	_layout_particles()
	for emitter in emitters:
		emitter.restart()
		emitter.emitting = true
	get_tree().create_timer(DURATION * 0.85).timeout.connect(_stop_emitters)
	for item in get_tree().get_nodes_in_group("world_items"):
		if item.kind == "floor_lamp" or item.emits_light:
			item.flicker(DURATION + 0.4)
	music.play()
	quake_started.emit(count == 1)


func _stop_emitters() -> void:
	for emitter in emitters:
		emitter.emitting = false


func _build_particles() -> void:
	# Ekran uzayı: kamera sarsılsa da parçacıklar ekran kenarından dökülür.
	layer = CanvasLayer.new()
	layer.name = "quake_fx"
	layer.layer = 5
	add_child(layer)
	var soft := _soft_tex()
	var rock := _rock_tex()
	var dust_ramp := _ramp([Color(1, 1, 1, 0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)], [0.0, 0.15, 0.6, 1.0])
	var chunk_ramp := _ramp([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)], [0.0, 0.85, 1.0])
	# Beton/sıva/tuğla tonları: her parça rastgele birini alır.
	var stone_tones := _ramp([Color(0.62, 0.58, 0.52), Color(0.48, 0.45, 0.42), Color(0.7, 0.66, 0.6), Color(0.55, 0.36, 0.28), Color(0.4, 0.38, 0.36)], [0.0, 0.25, 0.5, 0.75, 1.0])
	# Tavan sıvası tozu: büyük, yumuşak, yavaş süzülen bulutçuklar.
	var p := _add_emitter("top_dust", 28, 4.6, soft, Vector2(0, 1), 35.0, Vector2(8, 34), 26.0, Vector2(1.6, 4.0), Color(0.86, 0.8, 0.7, 0.24), dust_ramp)
	p.scale_amount_curve = _curve(0.5, 1.6)
	p.angular_velocity_min = -20.0
	p.angular_velocity_max = 20.0
	# Düşen beton parçaları: dönen, farklı boy ve tonlarda.
	p = _add_emitter("top_chunks", 22, 1.8, rock, Vector2(0, 1), 10.0, Vector2(40, 160), 950.0, Vector2(3.0, 6.5), Color.WHITE, chunk_ramp)
	p.color_initial_ramp = stone_tones
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	# İnce kum/sıva kırıntısı yağmuru.
	p = _add_emitter("top_grit", 45, 1.4, rock, Vector2(0, 1), 6.0, Vector2(30, 90), 700.0, Vector2(0.9, 1.6), Color.WHITE, chunk_ramp)
	p.color_initial_ramp = stone_tones
	# Çatlaklardan dökülen kum şeritleri (her sarsıntıda yerleri değişir).
	for k in 2:
		p = _add_emitter("stream_%d" % k, 40, 1.3, rock, Vector2(0, 1), 3.0, Vector2(20, 50), 820.0, Vector2(0.8, 1.4), Color(0.8, 0.74, 0.64, 0.95), chunk_ramp)
		p.emission_rect_extents = Vector2(3, 2)
	# Yan duvarlardan içeri savrulan parçalar ve toz.
	for side in ["left", "right"]:
		var dir := Vector2(1, 0.2) if side == "left" else Vector2(-1, 0.2)
		p = _add_emitter(side + "_chunks", 12, 1.6, rock, dir, 20.0, Vector2(80, 200), 850.0, Vector2(2.6, 5.0), Color.WHITE, chunk_ramp)
		p.color_initial_ramp = stone_tones
		p.angular_velocity_min = -400.0
		p.angular_velocity_max = 400.0
		p = _add_emitter(side + "_dust", 10, 3.2, soft, dir + Vector2(0, 0.3), 30.0, Vector2(20, 60), 40.0, Vector2(1.8, 3.6), Color(0.86, 0.8, 0.7, 0.2), dust_ramp)
		p.scale_amount_curve = _curve(0.6, 1.5)


func _add_emitter(id: String, amount: int, lifetime: float, texture: Texture2D, direction: Vector2, spread: float,
	speed: Vector2, gravity: float, particle_scale: Vector2, color: Color, ramp: Gradient) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = id
	p.emitting = false
	p.amount = amount
	p.lifetime = lifetime
	p.randomness = 0.7
	p.texture = texture
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.direction = direction
	p.spread = spread
	p.initial_velocity_min = speed.x
	p.initial_velocity_max = speed.y
	p.gravity = Vector2(0, gravity)
	p.damping_min = 0.0
	p.damping_max = 18.0
	p.scale_amount_min = particle_scale.x
	p.scale_amount_max = particle_scale.y
	p.color = color
	p.color_ramp = ramp
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.add_child(p)
	emitters.append(p)
	return p


func _ramp(colors: Array, offsets: Array) -> Gradient:
	var g := Gradient.new()
	g.colors = PackedColorArray(colors)
	g.offsets = PackedFloat32Array(offsets)
	return g


func _curve(a: float, b: float) -> Curve:
	var c := Curve.new()
	c.max_value = maxf(2.0, maxf(a, b))
	c.add_point(Vector2(0, a))
	c.add_point(Vector2(1, b))
	return c


func _soft_tex() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 32
	t.height = 32
	return t


# Düzensiz piksel taş parçası (6x6): kenarları kırık, üst-solda ışık, alt-sağda gölge.
func _rock_tex() -> Texture2D:
	var img := Image.create(6, 6, false, Image.FORMAT_RGBA8)
	var shape := ["..##..", ".####.", "######", "#####.", ".####.", "..##.."]
	for y in 6:
		for x in 6:
			if shape[y][x] == "#":
				var shade := 1.0
				if x + y <= 3:
					shade = 1.18
				elif x + y >= 7:
					shade = 0.72
				img.set_pixel(x, y, Color(shade, shade, shade, 1.0))
	return ImageTexture.create_from_image(img)


func _layout_particles() -> void:
	var view := get_viewport().get_visible_rect().size
	for p in emitters:
		var id := String(p.name)
		if id.begins_with("top"):
			p.position = Vector2(view.x * 0.5, -8)
			p.emission_rect_extents = Vector2(view.x * 0.5, 4)
		elif id.begins_with("stream"):
			p.position = Vector2(randf_range(80.0, view.x - 80.0), -4)
		elif id.begins_with("left"):
			p.position = Vector2(-6, view.y * 0.3)
			p.emission_rect_extents = Vector2(4, view.y * 0.3)
		elif id.begins_with("right"):
			p.position = Vector2(view.x + 6, view.y * 0.3)
			p.emission_rect_extents = Vector2(4, view.y * 0.3)


func _build_music() -> AudioStreamWAV:
	# Prosedürel gerilim müziği: vuruşlu bas drone, yükselen tritone tremolo,
	# hızlanan kalp atışı ve alçak frekanslı yer gürültüsü.
	var length := DURATION + 0.8
	var total := int(length * MIX_RATE)
	var data := PackedByteArray()
	data.resize(total * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1999
	var brown := 0.0
	var low := 0.0
	var phase_a := 0.0
	var phase_b := 0.0
	var beat_next := 0.25
	var beat_time := -10.0
	var beat_gap := 0.62
	var lub := true
	for i in range(total):
		var t := float(i) / MIX_RATE
		var env := minf(t / 0.35, 1.0) * clampf((length - t) / 1.0, 0.0, 1.0)
		var drone := (sin(TAU * 49.0 * t) + sin(TAU * 51.8 * t) * 0.8 + sin(TAU * 98.0 * t) * 0.25) * 0.22
		brown = clampf(brown + rng.randf_range(-1.0, 1.0) * 0.06, -1.0, 1.0) * 0.995
		low += (brown - low) * 0.05
		var shake_env := minf(t / 0.5, 1.0) * clampf(1.0 - t / (DURATION + 0.3), 0.0, 1.0)
		var rumble := low * 1.6 * shake_env
		var rise := 1.0 + 0.09 * t
		phase_a += TAU * 233.1 * rise / MIX_RATE
		phase_b += TAU * 329.6 * rise / MIX_RATE
		var tremolo := 0.55 + 0.45 * sin(TAU * 9.0 * t)
		var strings := (sin(phase_a) + sin(phase_b) * 0.8 + sin(phase_a * 2.0) * 0.2) * 0.075 * tremolo * minf(t / 1.2, 1.0)
		if t >= beat_next:
			beat_time = beat_next
			beat_next += 0.16 if lub else beat_gap
			if not lub:
				beat_gap = maxf(beat_gap * 0.9, 0.34)
			lub = not lub
		var since := t - beat_time
		var thump := sin(TAU * 58.0 * since) * exp(-since * 16.0) * 0.55 if since < 0.3 else 0.0
		var sample := (drone + rumble + strings + thump) * env
		sample = sample / (1.0 + absf(sample))
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 30000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.data = data
	return stream
