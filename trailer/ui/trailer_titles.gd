extends CanvasLayer

# Sinematik yazılar: ortada beliren başlıklar, logo, siyah ekranda konuşma altyazısı ve sahne
# oynarken sol alt köşede küçük açıklama kutusu (bölünmüş ekranda her panelin üstünde etiket).
# Görünme/kaybolma Tween ile; konuşma altyazısı harf harf yazılır (ses: TrailerAudio.blip).

var audio: Node
var canvas: Control
var title := ""
var title_size := 54
var title_a := 0.0
var title_rise := 0.0
var title_y := 0.5
var logo_a := 0.0
var tagline_a := 0.0
var ready_a := 0.0
var line := ""
var line_age := 0.0
var line_voice := ""
var line_a := 0.0
var line_spoken := 0
var t := 0.0
var title_tween: Tween
var line_tween: Tween
var cap_head := ""
var cap_text := ""
var cap_a := 0.0
var cap_slide := 0.0
var cap_tween: Tween
var panel_texts: Array = []
var panel_a := 0.0
var panel_tween: Tween


func _ready() -> void:
	layer = 110
	canvas = $Canvas
	canvas.draw.connect(_draw_titles)


# Ortada yazı: fade in → bekle → fade out (hold < 0: kalır).
func show_title(text: String, fade_in := 0.6, hold := 1.2, fade_out := 0.5, size := 54, y_frac := 0.5) -> void:
	title = text
	title_size = size
	title_y = y_frac
	if title_tween != null and title_tween.is_valid():
		title_tween.kill()
	title_a = 0.0
	title_rise = 1.0
	title_tween = create_tween().set_parallel(true)
	title_tween.tween_property(self, "title_a", 1.0, fade_in).set_trans(Tween.TRANS_SINE)
	title_tween.tween_property(self, "title_rise", 0.0, fade_in + 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if hold >= 0.0:
		title_tween.chain().tween_interval(hold)
		title_tween.chain().tween_property(self, "title_a", 0.0, fade_out)


# Anlık yazı (döngü işareti): yükselme ve geçiş yok, verilen sürede kaybolur.
func flash_title(text: String, seconds: float, size := 54) -> void:
	title = text
	title_size = size
	title_y = 0.5
	if title_tween != null and title_tween.is_valid():
		title_tween.kill()
	title_a = 1.0
	title_rise = 0.0
	title_tween = create_tween()
	title_tween.tween_interval(seconds)
	title_tween.tween_property(self, "title_a", 0.0, 0.03)


func hide_title(seconds := 0.4) -> void:
	if title_tween != null and title_tween.is_valid():
		title_tween.kill()
	title_tween = create_tween()
	title_tween.tween_property(self, "title_a", 0.0, seconds)


func show_logo(seconds := 1.2) -> void:
	create_tween().tween_property(self, "logo_a", 1.0, seconds).set_trans(Tween.TRANS_SINE)


func show_tagline(seconds := 0.8) -> void:
	create_tween().tween_property(self, "tagline_a", 1.0, seconds)


func show_ready(seconds := 0.8) -> void:
	create_tween().tween_property(self, "ready_a", 1.0, seconds)


func clear_all(seconds := 0.8) -> void:
	var tw := create_tween().set_parallel(true)
	for p in ["logo_a", "tagline_a", "ready_a", "title_a", "line_a", "cap_a", "panel_a"]:
		tw.tween_property(self, p, 0.0, seconds)


# Siyah ekranda konuşma: harf harf yazılan, hafif titrek altyazı (konuşan sesi blip ile).
func say(text: String, voice := "man", seconds := 2.0) -> void:
	line = text
	line_age = 0.0
	line_spoken = 0
	line_voice = voice
	if line_tween != null and line_tween.is_valid():
		line_tween.kill()
	line_a = 1.0
	line_tween = create_tween()
	line_tween.tween_interval(seconds)
	line_tween.tween_property(self, "line_a", 0.0, 0.5)


# Köşe açıklaması: soldan kayarak gelir, bekler, söner. Yenisi gelince eskisinin yerini alır.
func caption(head: String, text: String, seconds := 1.5) -> void:
	cap_head = head
	cap_text = text
	if cap_tween != null and cap_tween.is_valid():
		cap_tween.kill()
	cap_a = 0.0
	cap_slide = 1.0
	var fade := minf(0.2, seconds * 0.2)
	cap_tween = create_tween().set_parallel(true)
	cap_tween.tween_property(self, "cap_a", 1.0, fade)
	cap_tween.tween_property(self, "cap_slide", 0.0, fade + 0.15).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	cap_tween.chain().tween_interval(maxf(0.05, seconds - fade * 2.0))
	cap_tween.chain().tween_property(self, "cap_a", 0.0, fade)


# Bölünmüş ekran etiketleri: her üçte birlik panelin üst ortasında.
func panel_labels(texts: Array, seconds := 3.0) -> void:
	panel_texts = texts
	if panel_tween != null and panel_tween.is_valid():
		panel_tween.kill()
	panel_a = 0.0
	panel_tween = create_tween()
	panel_tween.tween_property(self, "panel_a", 1.0, 0.25)
	panel_tween.tween_interval(maxf(0.05, seconds - 0.5))
	panel_tween.tween_property(self, "panel_a", 0.0, 0.25)


func _draw_caption(font: Font) -> void:
	var view := canvas.size
	var head_size := 17
	var text_size := 25
	var tw := font.get_string_size(cap_text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x
	var hw := font.get_string_size(cap_head, HORIZONTAL_ALIGNMENT_LEFT, -1, head_size).x
	var w := maxf(tw, hw) + 40.0
	var h := 66.0 if cap_head != "" else 46.0
	var pos := Vector2(40.0 - cap_slide * 24.0, view.y - 44.0 - h)
	canvas.draw_rect(Rect2(pos, Vector2(w, h)), Color(0.04, 0.03, 0.03, 0.62 * cap_a))
	canvas.draw_rect(Rect2(pos, Vector2(4, h)), Color(0.95, 0.55, 0.22, 0.95 * cap_a))
	var y := pos.y + 26.0
	if cap_head != "":
		canvas.draw_string(font, Vector2(pos.x + 20, y), cap_head, HORIZONTAL_ALIGNMENT_LEFT, -1, head_size, Color(1.0, 0.72, 0.38, cap_a))
		y += 27.0
	canvas.draw_string(font, Vector2(pos.x + 21, y + 2), cap_text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, Color(0, 0, 0, 0.6 * cap_a))
	canvas.draw_string(font, Vector2(pos.x + 20, y), cap_text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, Color(0.97, 0.94, 0.88, cap_a))


func _draw_panel_labels(font: Font) -> void:
	var view := canvas.size
	var n := panel_texts.size()
	for i in n:
		var text: String = panel_texts[i]
		var size := 22
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var cx := view.x / n * (i + 0.5)
		var r := Rect2(cx - tw * 0.5 - 16.0, 30.0, tw + 32.0, 38.0)
		canvas.draw_rect(r, Color(0.04, 0.03, 0.03, 0.62 * panel_a))
		canvas.draw_rect(Rect2(r.position + Vector2(0, r.size.y - 3), Vector2(r.size.x, 3)), Color(0.95, 0.55, 0.22, 0.95 * panel_a))
		canvas.draw_string(font, Vector2(cx - tw * 0.5, 57.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.97, 0.94, 0.88, panel_a))


func _process(delta: float) -> void:
	t += delta
	if line != "" and line_a > 0.0:
		line_age += delta
		var shown := mini(int(line_age * 26.0), line.length())
		if shown / 2 > line_spoken and audio != null:
			line_spoken = shown / 2
			if line[shown - 1] != " ":
				audio.blip(line_voice)
	canvas.queue_redraw()


func _centered(font: Font, text: String, y: float, size: int, color: Color, spacing := 0.0) -> void:
	var view := canvas.size
	if spacing <= 0.0:
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		canvas.draw_string(font, Vector2((view.x - w) * 0.5 + 3, y + 3), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, color.a * 0.7))
		canvas.draw_string(font, Vector2((view.x - w) * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
		return
	# Harf aralıklı yazı (logo).
	var widths: Array = []
	var total := 0.0
	for ch in text:
		var cw := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		widths.append(cw)
		total += cw + spacing
	total -= spacing
	var x := (view.x - total) * 0.5
	for i in text.length():
		canvas.draw_string(font, Vector2(x + 4, y + 4), text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, color.a * 0.75))
		canvas.draw_string(font, Vector2(x, y), text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
		x += widths[i] + spacing


func _draw_titles() -> void:
	var font := ThemeDB.fallback_font
	var view := canvas.size
	if cap_a > 0.0 and cap_text != "":
		_draw_caption(font)
	if panel_a > 0.0:
		_draw_panel_labels(font)
	if title_a > 0.0:
		_centered(font, title, view.y * title_y + title_size * 0.35 + title_rise * 14.0, title_size, Color(0.96, 0.92, 0.84, title_a))
	if logo_a > 0.0:
		# Logo (oyunun adı "ONE MORE TIME"): harf aralıklı büyük başlık, altında ince çizgi; sarsıntı izi gibi hafif kayık gölge.
		var y := view.y * 0.44
		_centered(font, "ONE MORE TIME", y, 96, Color(0.98, 0.94, 0.86, logo_a), 14.0)
		var half := 330.0 * logo_a
		canvas.draw_line(Vector2(view.x * 0.5 - half, y + 34), Vector2(view.x * 0.5 + half, y + 34), Color(0.85, 0.35, 0.25, 0.8 * logo_a), 3.0)
	if tagline_a > 0.0:
		_centered(font, "ZAMAN. SEÇİM. VİCDAN.", view.y * 0.44 + 92, 30, Color(0.85, 0.82, 0.76, tagline_a), 6.0)
	if ready_a > 0.0:
		var pulse := 0.85 + 0.15 * sin(t * 2.4)
		_centered(font, "HAZIR MISIN?", view.y * 0.78, 36, Color(1.0, 0.78, 0.5, ready_a * pulse))
	if line != "" and line_a > 0.0:
		var shown := line.substr(0, int(line_age * 26.0))
		_centered(font, shown, view.y * 0.82, 34, Color(1.0, 0.95, 0.85, line_a))
