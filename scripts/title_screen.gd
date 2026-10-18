extends CanvasLayer

# Giriş ekranı: gece, piksel şehir silüeti, yerdeki çatlaklar ve sismograf çizgisi. Başlık "ONE MORE TIME"
# ara ara gelen sarsıntılarda titrer, harflerinden toz dökülür. [E] / Enter / Boşluk ile oyun başlar.
signal closed

const Sfx = preload("res://scripts/sfx.gd")
const TITLE := "ONE MORE TIME"

var canvas: Control
var time := 0.0
var appear := 0.0
var leaving := false
var fade_out := 0.0
var tremor := 0.0
var next_tremor := 2.2
var stars: Array = []
var buildings: Array = []
var dust: Array = []
var seismo: Array = []
var rumble: AudioStreamPlayer


func _ready() -> void:
	layer = 60
	canvas = Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	canvas.draw.connect(_draw_title)
	add_child(canvas)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2023
	for i in 90:
		stars.append([Vector2(rng.randf(), rng.randf() * 0.55), rng.randf_range(1.0, 2.5), rng.randf() * TAU])
	# Silüet: farklı yükseklikte bloklar, bazı pencereler yanık; biri çatlak ve eğik.
	var x := -0.02
	while x < 1.02:
		var w := rng.randf_range(0.05, 0.11)
		var h := rng.randf_range(0.12, 0.34)
		var lit := []
		for k in 14:
			lit.append(rng.randf() < 0.35)
		buildings.append({"x": x, "w": w, "h": h, "lit": lit, "tilt": (0.06 if rng.randf() < 0.18 else 0.0), "seed": rng.randi()})
		x += w + rng.randf_range(0.0, 0.015)
	for i in 160:
		seismo.append(0.0)
	rumble = AudioStreamPlayer.new()
	rumble.stream = Sfx.rumble()
	rumble.volume_db = -60.0
	add_child(rumble)
	rumble.play()


# Oyun yalnız PLAY düğmesine tıklanınca (düğmenin üstünde basıp bırakınca) ya da Enter ile başlar.
# Ekranın başka bir yerine tıklamak veya pencereye odaklanmak için tıklamak oyunu başlatmaz.
var press_on_button := false


func _input(event: InputEvent) -> void:
	if leaving or appear < 0.8:
		return
	var go := false
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER]:
		go = true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var local: Vector2 = canvas.make_input_local(event).position
		var inside := _play_rect(canvas.size).has_point(local)
		if event.pressed:
			press_on_button = inside
		else:
			go = press_on_button and inside
			press_on_button = false
	if not go:
		return
	get_viewport().set_input_as_handled()
	leaving = true
	tremor = 1.4
	var tw := create_tween()
	tw.tween_interval(0.5)
	tw.tween_property(self, "fade_out", 1.0, 1.0).set_ease(Tween.EASE_IN)
	await tw.finished
	closed.emit()
	queue_free()


func _play_rect(view: Vector2) -> Rect2:
	return Rect2(view.x * 0.5 - 110, view.y * 0.66, 220, 60)


func _process(delta: float) -> void:
	time += delta
	appear = minf(1.0, appear + delta * 0.7)
	next_tremor -= delta
	if next_tremor <= 0.0 and not leaving:
		next_tremor = randf_range(3.5, 5.5)
		tremor = 1.0
	tremor = maxf(0.0, tremor - delta * 0.9)
	rumble.volume_db = lerpf(-40.0, -8.0, minf(1.0, tremor)) if tremor > 0.02 else -40.0
	# Sismograf: sakin dalgalanma, sarsıntıda sert iğneler.
	seismo.pop_front()
	var amp := 0.06 + tremor * tremor * 0.9
	seismo.append(sin(time * 23.0) * amp * 0.5 + randf_range(-1.0, 1.0) * amp)
	# Sarsıntıda başlığın altından toz dökülür.
	if tremor > 0.3 and randf() < tremor * 0.8:
		dust.append({"pos": Vector2(randf_range(0.22, 0.78), 0.36), "v": randf_range(0.08, 0.2), "age": 0.0})
	for d in dust:
		d.age += delta
		d.pos.y += d.v * delta
	dust = dust.filter(func(d): return d.age < 2.5)
	canvas.queue_redraw()


func _jolt(scale: float) -> Vector2:
	var k := tremor * tremor * scale
	return Vector2(sin(time * 61.0) * k, cos(time * 47.0) * k * 0.6)


func _draw_title() -> void:
	var view := canvas.size
	var font := ThemeDB.fallback_font
	# Gökyüzü: üstte derin lacivert, ufukta kızıla çalan.
	var bands := 40
	for i in bands:
		var t := float(i) / (bands - 1)
		var col := Color(0.03, 0.04, 0.09).lerp(Color(0.2, 0.08, 0.1), pow(t, 1.8))
		canvas.draw_rect(Rect2(0, view.y * i / bands, view.x, view.y / bands + 1), col)
	for s in stars:
		var tw := 0.5 + 0.5 * sin(time * 1.7 + s[2])
		canvas.draw_rect(Rect2(Vector2(s[0].x * view.x, s[0].y * view.y), Vector2(s[1], s[1])), Color(1, 1, 1, 0.25 + 0.5 * tw))
	# Ay.
	canvas.draw_circle(Vector2(view.x * 0.82, view.y * 0.16), 34, Color(0.95, 0.92, 0.8, 0.9))
	canvas.draw_circle(Vector2(view.x * 0.82 + 12, view.y * 0.16 - 8), 30, Color(0.06, 0.06, 0.12, 0.95))
	# Şehir silüeti (sarsıntıda sallanır).
	var ground := view.y * 0.8
	var shake := _jolt(6.0)
	for b in buildings:
		var bx: float = b.x * view.x
		var bw: float = b.w * view.x
		var bh: float = b.h * view.y
		var tilt: float = b.tilt + (tremor * 0.015 * sin(time * 9.0 + b.seed) if tremor > 0.0 else 0.0)
		canvas.draw_set_transform(Vector2(bx + bw * 0.5, ground) + shake, tilt)
		canvas.draw_rect(Rect2(-bw * 0.5, -bh, bw, bh), Color(0.06, 0.05, 0.08))
		canvas.draw_rect(Rect2(-bw * 0.5, -bh, bw, 3), Color(0.12, 0.1, 0.14))
		var cols := 3
		var rows := 4
		for r in rows:
			for c in cols:
				var idx := r * cols + c
				if b.lit[idx % b.lit.size()]:
					var flick := 1.0 if tremor < 0.5 or fmod(time * 13.0 + idx, 1.0) > 0.3 else 0.2
					var wx := -bw * 0.5 + bw * (c + 0.5) / cols - 4
					var wy := -bh + 14 + r * (bh - 20) / rows
					canvas.draw_rect(Rect2(wx, wy, 8, 10), Color(1.0, 0.78, 0.4, 0.8 * flick))
		if b.tilt > 0.0:
			# Çatlak bina: gövdede kırık çizgi.
			canvas.draw_polyline(PackedVector2Array([Vector2(-bw * 0.2, -bh), Vector2(0, -bh * 0.7), Vector2(-bw * 0.1, -bh * 0.45), Vector2(bw * 0.15, -bh * 0.2)]), Color(0.35, 0.18, 0.15), 2.0)
	canvas.draw_set_transform(Vector2.ZERO)
	# Zemin ve çatlaklar (sarsıntıda kızıl ışık sızar).
	canvas.draw_rect(Rect2(0, ground, view.x, view.y - ground), Color(0.05, 0.04, 0.05))
	var glow := 0.25 + tremor * 0.75
	for k in 3:
		var sx := view.x * (0.2 + k * 0.3)
		var pts := PackedVector2Array()
		var p := Vector2(sx, ground + 4)
		for j in 7:
			pts.append(p + shake)
			p += Vector2(randf_range(-1, 1) * 0.0 + (18 if j % 2 == 0 else -14), 14)
		canvas.draw_polyline(pts, Color(0.9, 0.3, 0.15, 0.35 * glow), 6.0)
		canvas.draw_polyline(pts, Color(1.0, 0.6, 0.3, 0.8 * glow), 2.0)
	# Sismograf çizgisi.
	# Sismograf zeminde, şehrin altında akar.
	var sy := view.y * 0.885
	var line := PackedVector2Array()
	for i in seismo.size():
		line.append(Vector2(view.x * 0.18 + i * (view.x * 0.64) / (seismo.size() - 1), sy + clampf(seismo[i], -0.8, 0.8) * 40.0))
	canvas.draw_polyline(line, Color(0.95, 0.3, 0.25, 0.85), 2.0)
	canvas.draw_line(Vector2(view.x * 0.18, sy), Vector2(view.x * 0.82, sy), Color(1, 1, 1, 0.08), 1.0)
	# Başlık: harf harf, sarsıntıda her harf ayrı titrer; gölge + hafif kızıl kenar.
	var size := 92
	var total := font.get_string_size(TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := view.x * 0.5 - total * 0.5
	var y := view.y * 0.38
	var a := appear
	for i in TITLE.length():
		var ch := TITLE[i]
		var cw := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var j := Vector2(sin(time * 50.0 + i * 1.3), cos(time * 41.0 + i * 2.1)) * tremor * tremor * 7.0
		canvas.draw_string(font, Vector2(x, y) + j + Vector2(4, 5), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.7 * a))
		canvas.draw_string(font, Vector2(x, y) + j + Vector2(-1.5, 0), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.85, 0.2, 0.15, 0.6 * a))
		canvas.draw_string(font, Vector2(x, y) + j, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.96, 0.92, 0.84, a))
		x += cw
	for d in dust:
		var dp := Vector2(d.pos.x * view.x, d.pos.y * view.y)
		canvas.draw_rect(Rect2(dp, Vector2(3, 3)), Color(0.8, 0.75, 0.68, 0.7 * (1.0 - d.age / 2.5)))
	canvas.draw_string(font, Vector2(0, view.y * 0.46), "Bir kez daha... ta ki hazır olana dek.", HORIZONTAL_ALIGNMENT_CENTER, view.x, 24, Color(0.85, 0.82, 0.78, 0.8 * a))
	if appear >= 0.8 and not leaving:
		# PLAY düğmesi: piksel çerçeve, üstüne gelince parlar; tıkla ya da E/Enter/Boşluk.
		var btn := _play_rect(view)
		var hover := btn.has_point(canvas.get_local_mouse_position())
		var pulse := 0.5 + 0.5 * sin(time * 3.0)
		canvas.draw_rect(Rect2(btn.position + Vector2(0, 5), btn.size), Color(0, 0, 0, 0.55))
		canvas.draw_rect(btn, Color(0.75, 0.2, 0.15) if hover else Color(0.45, 0.12, 0.1))
		canvas.draw_rect(btn, Color(1, 0.85, 0.55, 0.6 + 0.4 * pulse), false, 3.0)
		for c in [btn.position, Vector2(btn.end.x - 6, btn.position.y), Vector2(btn.position.x, btn.end.y - 6), btn.end - Vector2(6, 6)]:
			canvas.draw_rect(Rect2(c, Vector2(6, 6)), Color(1, 0.85, 0.55))
		canvas.draw_string(font, Vector2(btn.position.x, btn.position.y + 42), "PLAY", HORIZONTAL_ALIGNMENT_CENTER, btn.size.x, 34, Color(1, 0.96, 0.88))
	canvas.draw_string(font, Vector2(0, view.y - 22), "Deprem anında: çömel, korun, hazırlıklı ol.", HORIZONTAL_ALIGNMENT_CENTER, view.x, 16, Color(1, 1, 1, 0.35 * a))
	if appear < 1.0:
		canvas.draw_rect(Rect2(Vector2.ZERO, view), Color(0, 0, 0, 1.0 - appear))
	if fade_out > 0.0:
		canvas.draw_rect(Rect2(Vector2.ZERO, view), Color(0, 0, 0, fade_out))
