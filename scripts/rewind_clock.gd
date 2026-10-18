extends CanvasLayer

# Ölümden sonra zaman geri sarılır: ekran kararır, sıcak bir lamba ışığında piksel bir duvar saati belirir,
# akrep ve yelkovan geriye doğru hızla döner, yavaşlayıp durur; yumuşak tıkırtılar ve çan sesi.
# Saat 64x64 bir görüntüye piksel piksel çizilir (oyunun piksel diliyle uyumlu), büyük ölçekte gösterilir.
signal done

const Sfx = preload("res://scripts/sfx.gd")
const SIZE := 64
const SCALE := 6.0
const DURATION := 3.6

var canvas: Control
var image: Image
var texture: ImageTexture
var time := 0.0
var angle := 0.0
var spin := 0.0
var tick_acc := 0.0
var last_tick := 0
var tick_player: AudioStreamPlayer
var chime_player: AudioStreamPlayer
var chimed := false
var face: Image
var start_hour := 0.0
var deaths := 1
var finished := false


func _ready() -> void:
	layer = 60
	canvas = Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	canvas.draw.connect(_draw_ui)
	add_child(canvas)
	tick_player = AudioStreamPlayer.new()
	tick_player.stream = Sfx.tick()
	tick_player.volume_db = -8.0
	tick_player.max_polyphony = 4
	add_child(tick_player)
	chime_player = AudioStreamPlayer.new()
	chime_player.stream = Sfx.chime()
	chime_player.volume_db = -6.0
	add_child(chime_player)
	face = _build_face()
	image = face.duplicate()
	texture = ImageTexture.create_from_image(image)
	start_hour = randf() * TAU


func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < SIZE and y < SIZE:
		img.set_pixel(x, y, c)


func _build_face() -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var c := Vector2(31.5, 31.5)
	for y in SIZE:
		for x in SIZE:
			var d := Vector2(x, y).distance_to(c)
			if d <= 30.5:
				var col := Color("5a3620")                        # ahşap kasa
				if d <= 29.0:
					col = Color("7a4a2a")
				if d <= 27.0:
					col = Color("3e2414")                         # iç kenar gölgesi
				if d <= 26.0:
					# Krem kadran: hafif üstten aydınlatma.
					col = Color("efe2c4").lerp(Color("d9c8a2"), clampf((y - 6) / 52.0, 0.0, 1.0))
				# Kasada üst-sol parlama.
				if d > 27.0 and d <= 29.5 and x + y < 40:
					col = Color("9a6438")
				img.set_pixel(x, y, col)
	# Saat çizgileri: 12 çentik, 3-6-9-12 kalın.
	for h in 12:
		var a := TAU * h / 12.0 - PI * 0.5
		var long := 4 if h % 3 == 0 else 2
		for r in range(24 - long, 25):
			_px(img, int(round(c.x + cos(a) * r)), int(round(c.y + sin(a) * r)), Color("4a3020"))
		if h % 3 == 0:
			_px(img, int(round(c.x + cos(a) * 24)) + 1, int(round(c.y + sin(a) * 24)), Color("4a3020"))
	# Göbek.
	for y in range(-2, 3):
		for x in range(-2, 3):
			if x * x + y * y <= 4:
				_px(img, int(c.x) + x, int(c.y) + y, Color("2a1a10"))
	return img


func _hand(img: Image, a: float, length: float, color: Color, width: int) -> void:
	var c := Vector2(31.5, 31.5)
	var steps := int(length * 2.0)
	for i in steps:
		var p := c + Vector2(cos(a), sin(a)) * (float(i) / 2.0)
		for w in width:
			var off := Vector2(-sin(a), cos(a)) * (w - (width - 1) * 0.5)
			_px(img, int(round(p.x + off.x)), int(round(p.y + off.y)), color)


func _process(delta: float) -> void:
	time += delta
	var k := clampf(time / DURATION, 0.0, 1.0)
	# Hız eğrisi: hızla başlar, sonunda yumuşakça durur (ease-out). Ölüm arttıkça daha uzun geri sarar.
	spin = lerpf(14.0 + deaths * 1.5, 0.0, pow(k, 0.6))
	angle -= spin * delta
	tick_acc += absf(spin) * delta
	var ticks := int(tick_acc / (TAU / 60.0))
	if ticks != last_tick:
		last_tick = ticks
		if not tick_player.playing or randf() < 0.5:
			tick_player.pitch_scale = randf_range(0.95, 1.08)
			tick_player.play()
	if k > 0.82 and not chimed:
		chimed = true
		chime_player.play()
	image.copy_from(face)
	_hand(image, start_hour + angle / 12.0 - PI * 0.5, 13.0, Color("2a1a10"), 2)
	_hand(image, angle - PI * 0.5, 21.0, Color("2a1a10"), 1)
	_hand(image, angle * 3.0 - PI * 0.5, 22.0, Color("b0302a"), 1)
	texture.update(image)
	canvas.queue_redraw()
	if time >= DURATION + 0.5 and not finished:
		finished = true
		done.emit()


func _draw_ui() -> void:
	var view := canvas.size
	var k := clampf(time / DURATION, 0.0, 1.0)
	var fade_in := clampf(time / 0.5, 0.0, 1.0)
	var fade_out := clampf((time - DURATION) / 0.5, 0.0, 1.0)
	canvas.draw_rect(Rect2(Vector2.ZERO, view), Color(0.05, 0.035, 0.03))
	var center := view * 0.5
	# Sıcak lamba ışığı halesi.
	for i in 18:
		canvas.draw_circle(center, 340.0 - i * 16.0, Color(1.0, 0.68, 0.35, 0.018 * fade_in))
	# Asılı toz zerreleri.
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for i in 40:
		var p := Vector2(rng.randf_range(0, view.x), rng.randf_range(0, view.y))
		p.y = fmod(p.y - time * rng.randf_range(6, 16), view.y)
		canvas.draw_rect(Rect2(p, Vector2(3, 3)), Color(1, 0.85, 0.6, 0.18 * fade_in))
	var s := SIZE * SCALE
	var rect := Rect2(center - Vector2(s, s) * 0.5 + Vector2(0, sin(time * 1.5) * 3.0), Vector2(s, s))
	canvas.draw_rect(Rect2(rect.position + Vector2(10, 12), rect.size), Color(0, 0, 0, 0))
	# Saatin duvara düşen gölgesi.
	canvas.draw_circle(rect.get_center() + Vector2(14, 16), s * 0.47, Color(0, 0, 0, 0.35 * fade_in))
	canvas.draw_texture_rect(texture, rect, false, Color(1, 1, 1, fade_in))
	var font := ThemeDB.fallback_font
	canvas.draw_string(font, Vector2(0, rect.end.y + 60), "zaman geri sarılıyor...", HORIZONTAL_ALIGNMENT_CENTER, view.x, 24, Color(1, 0.85, 0.65, 0.6 * fade_in * (0.7 + 0.3 * sin(time * 3.0))))
	if fade_out > 0.0:
		canvas.draw_rect(Rect2(Vector2.ZERO, view), Color(0, 0, 0, fade_out))
	if fade_in < 1.0:
		canvas.draw_rect(Rect2(Vector2.ZERO, view), Color(0, 0, 0, 1.0 - fade_in))
