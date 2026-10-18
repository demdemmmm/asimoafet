extends CanvasLayer

# Yangın tüpü mini oyunu: büyük tüp görseli + uyarı baloncuğu.
# 1) "Pimi çekmelisin" uyarısı → E: pim animasyonla fırlar.  2) Hazır → E (veya süre) ile kapanır.
signal finished

const TEX_PIN := "res://assets/furniture/extinguisher_pin.png"
const TEX_NOPIN := "res://assets/furniture/extinguisher_nopin.png"
const ART_SCALE := 4.2

var tex_body: Texture2D
var pin_tex: Texture2D
var pin_rect := Rect2()
var stage := 0
var t := 0.0
var canvas: Control
var click: AudioStreamPlayer


func _ready() -> void:
	layer = 28
	tex_body = load(TEX_NOPIN)
	_extract_pin(load(TEX_PIN), tex_body)
	canvas = Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	canvas.draw.connect(_draw_ui)
	add_child(canvas)
	click = AudioStreamPlayer.new()
	click.stream = _build_click()
	add_child(click)


# Pim = iki karenin farklı pikselleri; ayrı doku olarak çıkarılır ve hareket ettirilir.
func _extract_pin(with_pin: Texture2D, without_pin: Texture2D) -> void:
	var a := with_pin.get_image()
	var b := without_pin.get_image()
	if a.is_compressed():
		a.decompress()
	if b.is_compressed():
		b.decompress()
	var pin := Image.create(a.get_width(), a.get_height(), false, Image.FORMAT_RGBA8)
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x, y)
			if not ca.is_equal_approx(b.get_pixel(x, y)) and ca.a > 0.0:
				pin.set_pixel(x, y, ca)
	pin_rect = Rect2(pin.get_used_rect())
	if pin_rect.has_area():
		pin_tex = ImageTexture.create_from_image(pin.get_region(Rect2i(pin_rect)))


func _input(event: InputEvent) -> void:
	if (event.is_action_pressed("interact") and not event.is_echo()) or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		get_viewport().set_input_as_handled()
		if stage == 0:
			stage = 1
			t = 0.0
			click.play()
		elif stage == 2 and t > 0.4:
			_close()


func _process(delta: float) -> void:
	t += delta
	if stage == 1 and t >= 0.8:
		stage = 2
		t = 0.0
	elif stage == 2 and t >= 4.0:
		_close()
	canvas.queue_redraw()


func _close() -> void:
	if stage == 3:
		return
	stage = 3
	finished.emit()
	queue_free()


func _draw_ui() -> void:
	var view := canvas.size
	var font := ThemeDB.fallback_font
	canvas.draw_rect(Rect2(Vector2.ZERO, view), Color(0.02, 0.01, 0.0, 0.72))
	var center := view * 0.5
	canvas.draw_string(font, Vector2(0, center.y - 300), "YANGIN TÜPÜ", HORIZONTAL_ALIGNMENT_CENTER, view.x, 40, Color(1, 0.85, 0.6))
	# Tüp gövdesi (pimsiz kare) + üstünde hareket eden pim.
	var art_size := Vector2(tex_body.get_size()) * ART_SCALE
	var art_pos := center + Vector2(-art_size.x - 10, -art_size.y * 0.5)
	if stage == 0:
		art_pos.x += sin(t * 30.0) * 1.5 * (0.5 + 0.5 * sin(t * 3.0))
	canvas.draw_texture_rect(tex_body, Rect2(art_pos, art_size), false)
	if pin_tex != null and stage < 3:
		var k := 0.0 if stage == 0 else (minf(t / 0.6, 1.0) if stage == 1 else 1.0)
		var ease_k := 1.0 - pow(1.0 - k, 3.0)
		var pin_size := pin_rect.size * ART_SCALE
		var pin_center := art_pos + (pin_rect.position + pin_rect.size * 0.5) * ART_SCALE
		pin_center += Vector2(-150, -40) * ease_k + Vector2(0, 220) * k * k * 0.6
		var alpha := 1.0 - clampf((k - 0.7) / 0.3, 0.0, 1.0)
		if stage == 0:
			# Pim parlayarak dikkat çeker.
			canvas.draw_circle(pin_center, pin_size.length() * 0.6, Color(1, 0.9, 0.3, 0.18 + 0.12 * sin(t * 6.0)))
		canvas.draw_set_transform(pin_center, -2.5 * ease_k)
		canvas.draw_texture_rect(pin_tex, Rect2(-pin_size * 0.5, pin_size), false, Color(1, 1, 1, alpha))
		canvas.draw_set_transform(Vector2.ZERO)
		if stage == 1:
			canvas.draw_string(font, pin_center + Vector2(-30, -40), "ÇIT!", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(1, 1, 1, 1.0 - k))
	# Uyarı / hazır baloncuğu.
	var ready := stage >= 2
	var title := "HAZIR!" if ready else "UYARI!"
	var body := "Pim çekildi. E tuşunu BASILI tutarak hortumu alevlerin dibine doğrult ve sık. Bütün alevler sönene kadar tüp bitmez." if ready \
		else "Yangın tüpünü kullanmak istiyorsan önce emniyet pimini (anahtarı) çekip çıkarman gerekiyor!"
	var hint := "[E / sol tık] Devam" if ready else "[E / sol tık] Pimi çek"
	var box := Rect2(center + Vector2(40, -170), Vector2(470, 300))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.97)
	style.border_color = Color("3f9b52") if ready else Color("c0392b")
	style.set_border_width_all(5)
	style.set_corner_radius_all(18)
	style.draw(canvas.get_canvas_item(), box)
	var tail := PackedVector2Array([box.position + Vector2(5, 70), box.position + Vector2(5, 120), box.position + Vector2(-40, 70)])
	canvas.draw_colored_polygon(tail, style.border_color)
	canvas.draw_string(font, box.position + Vector2(28, 54), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, style.border_color)
	canvas.draw_multiline_string(font, box.position + Vector2(28, 100), body, HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 56, 22, -1, Color("1b1b1f"))
	var pulse := 0.6 + 0.4 * sin(t * 6.0)
	canvas.draw_string(font, box.position + Vector2(28, box.size.y - 26), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(style.border_color, pulse))


func _build_click() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.25)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in n:
		var tt := float(i) / rate
		var s := (sin(TAU * 2400.0 * tt) * 0.5 + rng.randf_range(-1, 1) * 0.5) * exp(-tt * 40.0)
		s += sin(TAU * 900.0 * tt) * 0.4 * exp(-maxf(tt - 0.08, 0.0) * 30.0) * (1.0 if tt > 0.08 else 0.0)
		data.encode_s16(i * 2, int(clampf(s, -1, 1) * 28000))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	return stream
