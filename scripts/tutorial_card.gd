extends CanvasLayer

# Kısa Çök-Kapan-Tutun eğitimi: telefon kapandıktan sonra, deprem başlamadan önce gösterilir.
# Üç resimli adım (karakterin kendi piksel görseliyle) + kontroller. [E] ile kapanır.
signal closed

const SCALE := 5.0
const SKIN := Color(0.79, 0.59, 0.5)
const SHADE := Color(0.67, 0.49, 0.41)

var canvas: Control
var sheet: Texture2D
var time := 0.0
var closing := false
var appear := 0.0


func _ready() -> void:
	layer = 27
	sheet = load("res://assets/player_sheet.png")
	canvas = Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	canvas.draw.connect(_draw_card)
	add_child(canvas)


func _input(event: InputEvent) -> void:
	var click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if not click and (not (event is InputEventKey) or not event.pressed or event.echo):
		return
	get_viewport().set_input_as_handled()
	if time > 1.2 and (click or event.physical_keycode in [KEY_E, KEY_ENTER, KEY_SPACE]) and not closing:
		closing = true
		var tw := create_tween()
		tw.tween_property(self, "appear", 0.0, 0.3)
		await tw.finished
		closed.emit()
		queue_free()


func _process(delta: float) -> void:
	time += delta
	if not closing:
		appear = minf(1.0, appear + delta * 3.0)
	canvas.queue_redraw()


# Karakter karesi (çömelme = 8) ve isteğe bağlı eller / tutunan kol.
func _figure(pos: Vector2, pose: int, a: float) -> void:
	var size := 32.0 * SCALE
	var origin := pos - Vector2(size * 0.5, size)
	canvas.draw_texture_rect_region(sheet, Rect2(origin, Vector2(size, size)), Rect2(8 * 32, 0, 32, 32), Color(1, 1, 1, a))
	var px := func(fx: float, fy: float, w: float, h: float, c: Color) -> void:
		canvas.draw_rect(Rect2(origin + Vector2(fx, fy) * SCALE, Vector2(w, h) * SCALE), Color(c, a))
	if pose >= 2:
		px.call(9, 8, 4, 2, SKIN)
		px.call(17, 8, 4, 2, SKIN)
		px.call(9, 10, 1, 5, SHADE)
		px.call(20, 10, 1, 5, SHADE)
	if pose >= 3:
		px.call(21, 19, 6, 2, SKIN)
		px.call(26, 18, 2, 4, SHADE)


func _draw_card() -> void:
	var view := canvas.size
	var font := ThemeDB.fallback_font
	var k := 1.0 - pow(1.0 - appear, 3.0)
	canvas.draw_rect(Rect2(Vector2.ZERO, view), Color(0, 0, 0, 0.55 * k))
	var card := Rect2(view * 0.5 - Vector2(560, 330) + Vector2(0, (1.0 - k) * 40.0), Vector2(1120, 660))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.96, 0.92, 0.84, 0.98 * k)
	style.border_color = Color(0.55, 0.36, 0.2, k)
	style.set_border_width_all(5)
	style.set_corner_radius_all(18)
	style.shadow_color = Color(0, 0, 0, 0.35 * k)
	style.shadow_size = 14
	style.draw(canvas.get_canvas_item(), card)
	var ink := Color(0.22, 0.15, 0.1, k)
	canvas.draw_string(font, card.position + Vector2(0, 62), "DEPREM ANINDA:  ÇÖK  •  KAPAN  •  TUTUN", HORIZONTAL_ALIGNMENT_CENTER, card.size.x, 36, Color(0.6, 0.18, 0.12, k))
	canvas.draw_string(font, card.position + Vector2(0, 96), "Sarsıntı sırasında koşma, dışarı kaçmaya çalışma. Olduğun yerde kendini koru.", HORIZONTAL_ALIGNMENT_CENTER, card.size.x, 20, ink)
	var steps := [
		["1. ÇÖK", "Dizlerinin üstüne çök,\ndüşmeyi önle.", 1],
		["2. KAPAN", "Başını ve enseni\nkollarınla koru.", 2],
		["3. TUTUN", "Sağlam bir eşyaya tutun,\nsarsıntı bitene kadar bekle.", 3],
	]
	for i in 3:
		var panel := Rect2(card.position + Vector2(40 + i * 350, 130), Vector2(330, 330))
		canvas.draw_rect(panel, Color(1, 0.98, 0.93, 0.9 * k))
		canvas.draw_rect(panel, Color(0.7, 0.55, 0.38, k), false, 3.0)
		var floor_y := panel.position.y + 250
		canvas.draw_rect(Rect2(panel.position.x + 10, floor_y, panel.size.x - 20, 6), Color(0.6, 0.45, 0.3, 0.5 * k))
		var bob := sin(time * 3.0 + i) * 2.0
		if i == 2:
			# Masa: kolun tutunduğu sağlam eşya.
			var table := Rect2(panel.position.x + 190, floor_y - 70, 110, 14)
			canvas.draw_rect(table, Color(0.48, 0.3, 0.17, k))
			canvas.draw_rect(Rect2(table.position.x + 8, table.end.y, 10, 56), Color(0.4, 0.25, 0.14, k))
			canvas.draw_rect(Rect2(table.end.x - 18, table.end.y, 10, 56), Color(0.4, 0.25, 0.14, k))
		_figure(Vector2(panel.position.x + (130.0 if i == 2 else 165.0), floor_y + 10 + bob * (1.0 if i == 0 else 0.0)), steps[i][2], k)
		canvas.draw_string(font, Vector2(panel.position.x, panel.end.y - 50), steps[i][0], HORIZONTAL_ALIGNMENT_CENTER, panel.size.x, 28, Color(0.6, 0.18, 0.12, k))
		canvas.draw_multiline_string(font, Vector2(panel.position.x + 10, panel.end.y - 20), steps[i][1], HORIZONTAL_ALIGNMENT_CENTER, panel.size.x - 20, 17, -1, ink)
	var y := card.position.y + 560
	canvas.draw_string(font, Vector2(card.position.x, y), "Hafif öncü titremeyi hissedince bir eşyanın yanına geç ve  [C]  bas — basılı tut.", HORIZONTAL_ALIGNMENT_CENTER, card.size.x, 21, ink)
	canvas.draw_string(font, Vector2(card.position.x, y + 30), "Sehpa, sandalye gibi küçük eşyalarda iyice büzülmek için  [C]  'ye art arda iki kez bas.", HORIZONTAL_ALIGNMENT_CENTER, card.size.x, 19, ink)
	if time > 1.2:
		var pulse := 0.6 + 0.4 * sin(time * 5.0)
		canvas.draw_string(font, Vector2(card.position.x, card.end.y - 18), "[E] Anladım", HORIZONTAL_ALIGNMENT_CENTER, card.size.x, 24, Color(0.6, 0.18, 0.12, pulse * k))
