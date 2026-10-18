extends CanvasLayer

# Geçişler: kararma/açılma, hızlı kesme, yumuşak beyazlama ve zaman döngüsü geçişi.
# Hepsi tek bir tam ekran çizimden yönetilir; yönetmen zaman çizelgesinden çağırır.

var canvas: Control
var black := 1.0
var white := 0.0
var loop_k := -1.0
# Göz kapakları (1: kapalı, 0: açık) ve geri sarma efekti (VHS çizgileri, ◀◀).
var lids := 0.0
var rewind := 0.0
var t := 0.0
var fade_tween: Tween
var white_tween: Tween


func _ready() -> void:
	layer = 100
	canvas = Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.draw.connect(_draw_fx)
	add_child(canvas)


func fade_in(seconds: float) -> void:
	_fade(0.0, seconds)


func fade_out(seconds: float) -> void:
	_fade(1.0, seconds)


# Hızlı kesme: tek karelik siyah (göz kırpması), görüntü değişimini keskinleştirir.
func quick_cut() -> void:
	if fade_tween != null and fade_tween.is_valid():
		fade_tween.kill()
	black = 1.0
	fade_tween = create_tween()
	fade_tween.tween_interval(1.0 / 30.0)
	fade_tween.tween_property(self, "black", 0.0, 1.0 / 30.0)


# Kısa süreli kararma ve geri açılma (deprem anı).
func dip(seconds: float) -> void:
	if fade_tween != null and fade_tween.is_valid():
		fade_tween.kill()
	fade_tween = create_tween()
	fade_tween.tween_property(self, "black", 1.0, seconds * 0.35)
	fade_tween.tween_interval(seconds * 0.3)
	fade_tween.tween_property(self, "black", 0.0, seconds * 0.35)


# Yumuşak beyazlama: en fazla %45, rahatsız edici flaş olmaz.
func white_flash(seconds: float, strength := 0.45) -> void:
	if white_tween != null and white_tween.is_valid():
		white_tween.kill()
	white = strength
	white_tween = create_tween()
	white_tween.tween_property(self, "white", 0.0, seconds).set_ease(Tween.EASE_OUT)


# Zaman döngüsü geçişi: kenarlardan içe kapanan halkalar, ekran siyaha çekilir.
func time_loop(seconds: float) -> void:
	loop_k = 0.0
	var tw := create_tween()
	tw.tween_property(self, "loop_k", 1.0, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): loop_k = -1.0; black = 1.0)


# Göz açılışı: üst ve alt siyah kapaklar yavaşça çekilir (iki kez kırpar).
func eyes_open(seconds: float) -> void:
	black = 0.0
	lids = 1.0
	var tw := create_tween()
	tw.tween_property(self, "lids", 0.55, seconds * 0.35).set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "lids", 0.85, seconds * 0.2)
	tw.tween_property(self, "lids", 0.0, seconds * 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func set_rewind(on: bool) -> void:
	rewind = 1.0 if on else 0.0


func _fade(to: float, seconds: float) -> void:
	if fade_tween != null and fade_tween.is_valid():
		fade_tween.kill()
	fade_tween = create_tween()
	fade_tween.tween_property(self, "black", to, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _process(delta: float) -> void:
	t += delta
	canvas.queue_redraw()


func _draw_fx() -> void:
	var view := canvas.size
	if loop_k >= 0.0:
		var c := view * 0.5
		var r_max := view.length() * 0.6
		var inner := lerpf(r_max, 0.0, loop_k)
		# İçe kapanan karanlık: dış bölge siyah, sınırda saat yönünde dönen ince halkalar.
		for i in 26:
			var r := inner + i * 18.0
			canvas.draw_arc(c, r, 0.0, TAU, 96, Color(0, 0, 0, clampf(0.25 + i * 0.05, 0.0, 1.0)), 20.0)
		for k in 3:
			var rr := inner + 8.0 + k * 22.0
			var a0 := -t * (2.0 + k) - k
			canvas.draw_arc(c, rr, a0, a0 + PI * 1.2, 48, Color(1.0, 0.85, 0.6, 0.18 * (1.0 - loop_k)), 2.0)
	if rewind > 0.0:
		# Geri sarma: soğuk ton, kayan tarama çizgileri, köşede ◀◀ işareti.
		canvas.draw_rect(Rect2(Vector2.ZERO, view), Color(0.35, 0.5, 0.8, 0.12))
		var y := 0.0
		while y < view.y:
			canvas.draw_rect(Rect2(0, y, view.x, 2), Color(0, 0, 0, 0.18))
			y += 6.0
		var band := fmod(t * 520.0, view.y + 80.0) - 40.0
		canvas.draw_rect(Rect2(0, view.y - band, view.x, 26), Color(1, 1, 1, 0.07))
		var font := ThemeDB.fallback_font
		canvas.draw_string(font, Vector2(48, 78), "◀◀", HORIZONTAL_ALIGNMENT_LEFT, -1, 46, Color(1, 1, 1, 0.85))
	if lids > 0.0:
		var hh := view.y * 0.5 * lids
		canvas.draw_rect(Rect2(0, 0, view.x, hh), Color.BLACK)
		canvas.draw_rect(Rect2(0, view.y - hh, view.x, hh), Color.BLACK)
	if white > 0.0:
		canvas.draw_rect(Rect2(Vector2.ZERO, view), Color(1.0, 0.97, 0.9, white))
	if black > 0.0:
		canvas.draw_rect(Rect2(Vector2.ZERO, view), Color(0, 0, 0, black))
