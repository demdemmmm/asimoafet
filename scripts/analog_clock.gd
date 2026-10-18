extends CanvasLayer

# Küçük piksel duvar saati (sağ üst köşe). Oyunun tek saati olan game.clock_seconds'tan okur:
# 00:00'da başlar, gerçek zamanlı ilerler, döngüde sıfırlanır. Zaman atlamasında (enkazda uyku)
# akrep ve yelkovan hızla dönerek yeni saate gelir. Enkaz katmanının da üstünde durur.
const R := 34.0
const PIX := 2.0

var game: Node
var canvas: Control
var shown := 0.0


func _ready() -> void:
	layer = 45
	canvas = Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.draw.connect(_draw_clock)
	add_child(canvas)
	shown = game.clock_seconds


func _process(delta: float) -> void:
	var target: float = game.clock_seconds
	if target - shown > 5.0:
		# Atlama: kısa bir sürede ileri sarar.
		shown = minf(target, shown + maxf(3600.0 * 6.0 * delta, (target - shown) * delta * 1.6))
	else:
		shown = target
	canvas.queue_redraw()


# Piksel ızgarasına oturtulmuş kalın çizgi: kare piksellerle çizilir.
func _pixel_line(a: Vector2, b: Vector2, width: float, color: Color) -> void:
	var steps := int(a.distance_to(b) / PIX) + 1
	for i in steps + 1:
		var p := a.lerp(b, float(i) / steps)
		p = (p / PIX).floor() * PIX
		canvas.draw_rect(Rect2(p - Vector2(width, width) * 0.5, Vector2(width, width)), color)


func _draw_clock() -> void:
	var c := Vector2(canvas.size.x - 22.0 - R, 18.0 + R)
	c = (c / PIX).floor() * PIX
	# Gövde: koyu ahşap çerçeve, krem kadran, hafif gölge.
	canvas.draw_circle(c + Vector2(3, 4), R + 5, Color(0, 0, 0, 0.35))
	canvas.draw_circle(c, R + 5, Color("4a2e1a"))
	canvas.draw_circle(c, R + 2, Color("6b4428"))
	canvas.draw_circle(c, R - 1, Color("efe3c4"))
	canvas.draw_circle(c + Vector2(-6, -6), R * 0.55, Color(1, 1, 1, 0.12))
	for i in 12:
		var a := TAU * i / 12.0
		var dir := Vector2(sin(a), -cos(a))
		var big := i % 3 == 0
		var p := ((c + dir * (R - 7)) / PIX).floor() * PIX
		var s := 4.0 if big else 2.0
		canvas.draw_rect(Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), Color("3a2a1e"))
	var minutes := shown / 60.0
	var hours := fmod(minutes / 60.0, 12.0)
	var m_angle := TAU * fmod(minutes, 60.0) / 60.0
	var h_angle := TAU * hours / 12.0
	_pixel_line(c, c + Vector2(sin(h_angle), -cos(h_angle)) * (R * 0.5), 4.0, Color("2a1d14"))
	_pixel_line(c, c + Vector2(sin(m_angle), -cos(m_angle)) * (R * 0.78), 2.0, Color("2a1d14"))
	canvas.draw_rect(Rect2(c - Vector2(3, 3), Vector2(6, 6)), Color("c23a2a"))
	# Kadranın altında gece/gündüz göstergesi: 12 saatlik atlama da böylece görünür.
	var h24 := fmod(shown / 3600.0, 24.0)
	var day := h24 >= 6.0 and h24 < 18.0
	var badge := Rect2(c + Vector2(-12, R + 8), Vector2(24, 16))
	canvas.draw_rect(badge, Color("2a1d14"))
	canvas.draw_rect(badge.grow(-2), Color("8fc3e8") if day else Color("1b2140"))
	var mid := badge.get_center()
	if day:
		canvas.draw_rect(Rect2(mid - Vector2(4, 4), Vector2(8, 8)), Color("ffd24a"))
		for o in [Vector2(-7, 0), Vector2(5, 0), Vector2(0, -7), Vector2(0, 5)]:
			canvas.draw_rect(Rect2(mid + o - Vector2(1, 1), Vector2(2, 2)), Color("ffd24a"))
	else:
		canvas.draw_circle(mid, 5.0, Color("e8e4c8"))
		canvas.draw_circle(mid + Vector2(2.5, -1.5), 4.2, Color("1b2140"))
