extends Control

# Elektrik tesisat kutusu onarımı (800x480 panel, fareyle):
# 1) Önce şalteri indir: akım varken kabloya dokunan çarpılır (can gitmez), "şalteri kapatmalıyım" uyarısı çıkar.
# 2) Klemens bloğundaki kabloları (L/N/PE) kopuk uçlara renk koduna göre sürükleyip bağla.
#    Kahverengi = Faz (L), Mavi = Nötr (N), Sarı-Yeşil = Toprak (PE). Yanlış uç: kıvılcım.
#    Hepsi bağlanınca → solved (dünya şalteri geri kaldırır, elektrik gelir).
signal solved
signal failed
signal cancelled
# Şalter her an indirilebilir: elektriği keser (kaçak onarımından ayrı işlem).
signal breaker_pulled
# Akım varken kabloya dokunuldu: kısa elektrik çarpması (hasar yok).
signal shocked
var live := true

const SIZE := Vector2(800, 480)
const WIRES := [
	{"id": "L", "name": "Faz", "color": Color("8a4b22"), "stripe": Color(0, 0, 0, 0)},
	{"id": "N", "name": "Nötr", "color": Color("2f6fd6"), "stripe": Color(0, 0, 0, 0)},
	{"id": "PE", "name": "Toprak", "color": Color("e3cf2a"), "stripe": Color("2fa84a")},
]
const LEFT_X := 168.0
const RIGHT_X := 612.0
const ROW_Y := [178.0, 248.0, 318.0]
const HIT_RADIUS := 30.0
const BREAKER := Rect2(668, 352, 70, 96)

var right_order: Array = [0, 1, 2]
var connected: Array = [false, false, false]
var dragging := -1
var completed_wires := 0
var total_wires := 3
var puzzle_completed := false
var breaker_down := false
var solve_generation := 0
var time := 0.0
var shake := 0.0
var flash := 0.0
# "Şalteri kapatmalıyım" uyarısının görünürlüğü (1 → 0 söner).
var warn := 0.0
# Elektrik çarpması efekti (1 → 0) ve çarpılan uç.
var shock := 0.0
var shock_pos := Vector2.ZERO
var flash_pos := Vector2.ZERO
var screw_spin := [0.0, 0.0, 0.0]
var cancel_button: Button
var click_player: AudioStreamPlayer
var zap_player: AudioStreamPlayer
var clunk_player: AudioStreamPlayer
var crackle_player: AudioStreamPlayer


func _ready() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	for child in get_children():
		child.queue_free()
	cancel_button = Button.new()
	cancel_button.text = "Vazgeç [Esc]"
	cancel_button.position = Vector2(30, 424)
	cancel_button.size = Vector2(150, 36)
	cancel_button.pressed.connect(_on_cancel_pressed)
	add_child(cancel_button)
	click_player = _player(_tone(0.12, 1800.0, 60.0, 0.5))
	zap_player = _player(_tone(0.5, 60.0, 4.0, 1.0))
	clunk_player = _player(_tone(0.25, 140.0, 18.0, 0.3))
	crackle_player = _player(_crackle())
	reset_puzzle()


func reset_puzzle() -> void:
	cancel_drag()
	connected = [false, false, false]
	completed_wires = 0
	puzzle_completed = false
	breaker_down = not live
	right_order.shuffle()
	screw_spin = [0.0, 0.0, 0.0]
	queue_redraw()


func cancel_drag() -> void:
	dragging = -1
	solve_generation += 1


func _left_point(i: int) -> Vector2:
	return Vector2(LEFT_X, ROW_Y[i])


# Sağdaki kopuk uçlar karışık sıradadır: wire i'nin ucu right_order'daki yerinde durur.
func _right_point(i: int) -> Vector2:
	return Vector2(RIGHT_X, ROW_Y[right_order.find(i)])


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		_on_cancel_pressed()
		get_viewport().set_input_as_handled()
		return
	if puzzle_completed:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse := get_local_mouse_position()
		if event.pressed:
			if not breaker_down and BREAKER.grow(10).has_point(mouse):
				_pull_breaker()
				get_viewport().set_input_as_handled()
				return
			for i in total_wires:
				if not connected[i] and _left_point(i).distance_to(mouse) < HIT_RADIUS:
					get_viewport().set_input_as_handled()
					if not breaker_down:
						# Akım varken kabloya dokunan çarpılır: mavi-beyaz ark, sarsıntı, cızırtı; can gitmez.
						warn = 1.0
						shock = 1.0
						shock_pos = _left_point(i)
						shake = 0.9
						zap_player.play()
						shocked.emit()
						return
					dragging = i
					return
		elif dragging >= 0:
			_drop(mouse)
			get_viewport().set_input_as_handled()


func _drop(mouse: Vector2) -> void:
	var wire := dragging
	dragging = -1
	for target in total_wires:
		if _right_point(target).distance_to(mouse) >= HIT_RADIUS or connected[target]:
			continue
		if target == wire:
			connected[wire] = true
			completed_wires += 1
			screw_spin[wire] = 1.0
			click_player.play()
			if completed_wires == total_wires:
				puzzle_completed = true
				var generation := solve_generation
				get_tree().create_timer(0.8).timeout.connect(func() -> void:
					if generation == solve_generation and is_visible_in_tree() and puzzle_completed:
						solved.emit())
		else:
			# Yanlış uç: kısa devre kıvılcımı, panel sarsılır.
			flash = 1.0
			flash_pos = _right_point(target)
			shake = 1.0
			zap_player.play()
			# Akım varsa yanlış uç ölümcül; şalter inikse yalnız kıvılcım.
			if live:
				failed.emit()
		return


func _pull_breaker() -> void:
	breaker_down = true
	live = false
	clunk_player.play()
	breaker_pulled.emit()
	queue_redraw()


func _on_cancel_pressed() -> void:
	cancel_drag()
	cancelled.emit()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		if crackle_player.playing:
			crackle_player.stop()
		return
	time += delta
	shake = maxf(0.0, shake - delta * 3.0)
	warn = maxf(0.0, warn - delta * 0.45)
	shock = maxf(0.0, shock - delta * 2.2)
	flash = maxf(0.0, flash - delta * 2.5)
	for i in 3:
		screw_spin[i] = maxf(0.0, screw_spin[i] - delta * 2.0)
	var arcing := completed_wires < total_wires
	if arcing and not crackle_player.playing:
		crackle_player.play()
	elif not arcing and crackle_player.playing:
		crackle_player.stop()
	queue_redraw()


# --- Çizim ---------------------------------------------------------------------

func _draw() -> void:
	var font := ThemeDB.fallback_font
	var jolt := Vector2(sin(time * 90.0), cos(time * 70.0)) * 6.0 * shake
	# Arkadaki oyunu karart.
	draw_rect(Rect2(-3000, -3000, 6800, 6480), Color(0, 0, 0, 0.6))
	draw_set_transform(jolt)
	# Çelik kasa ve iç pano.
	_rounded(Rect2(Vector2.ZERO, SIZE), Color("3c4247"), Color("1e2226"), 4, 16)
	_rounded(Rect2(18, 18, 764, 444), Color("23282d"), Color("4f575e"), 2, 10)
	for p in [Vector2(30, 30), Vector2(770, 30), Vector2(30, 450), Vector2(770, 450)]:
		_screw(p, 7.0, 0.6)
	# Başlık ve uyarı etiketi.
	draw_string(font, Vector2(46, 58), "ELEKTRİK TESİSAT KUTUSU", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("e8edf0"))
	draw_string(font, Vector2(46, 82), "Önce şalteri indir, sonra kopan hatları renk koduna göre bağla.", HORIZONTAL_ALIGNMENT_LEFT, 500, 15, Color("9fb0bb"))
	var sticker := Rect2(560, 34, 200, 52)
	_rounded(sticker, Color("f2c230"), Color("141414"), 3, 6)
	var tri := PackedVector2Array([Vector2(586, 76), Vector2(602, 44), Vector2(618, 76)])
	draw_colored_polygon(tri, Color("141414"))
	draw_polyline(PackedVector2Array([Vector2(604, 50), Vector2(597, 62), Vector2(606, 62), Vector2(599, 73)]), Color("f2c230"), 2.5)
	draw_string(font, Vector2(628, 58), "TEHLİKE", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("141414"))
	draw_string(font, Vector2(628, 78), "220 V ~", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("141414"))
	_hazard_band(Rect2(18, 96, 764, 10))
	# Renk kodu efsanesi.
	var legend_x := 46.0
	for w in WIRES:
		_cable_segment(Vector2(legend_x, 128), Vector2(legend_x + 28, 128), w, 7.0)
		draw_string(font, Vector2(legend_x + 36, 133), "%s = %s (%s)" % [_color_name(w.id), w.name, w.id], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("c9d3da"))
		legend_x += 238.0
	# Klemens bloğu (sol) ve giriş kabloları.
	_rounded(Rect2(LEFT_X - 46, ROW_Y[0] - 32, 70, 204), Color("d7d9d6"), Color("8c918f"), 2, 4)
	for i in 3:
		var p := _left_point(i)
		_cable_segment(Vector2(18, p.y + 4), Vector2(LEFT_X - 40, p.y + 4), WIRES[i], 11.0)
		draw_rect(Rect2(LEFT_X - 46, p.y - 32, 70, 2), Color("8c918f"))
		draw_string(font, Vector2(LEFT_X - 40, p.y + 26), WIRES[i].id, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("2a2a2a"))
		_screw(p, 11.0, screw_spin[i] * TAU * 2.0)
		if not connected[i] and dragging < 0 and breaker_down:
			draw_arc(p, 18.0 + sin(time * 5.0) * 2.0, 0, TAU, 32, Color(1, 0.85, 0.3, 0.6), 2.0)
	# Kopuk uçlar (sağ): yalıtımı soyulmuş bakır, bağlı değilse ark yapar.
	for i in 3:
		var p := _right_point(i)
		_cable_segment(Vector2(782, p.y), Vector2(p.x + 22, p.y), WIRES[i], 11.0)
		draw_rect(Rect2(p.x, p.y - 3, 24, 6), Color("d98a3d"))
		draw_rect(Rect2(p.x, p.y - 3, 24, 2), Color("f5b971"))
		if not connected[i]:
			_sparks(p, i)
	# Bağlı ve sürüklenen kablolar (sarkık eğri).
	for i in 3:
		if connected[i]:
			_cable_curve(_left_point(i), _right_point(i), WIRES[i])
	if dragging >= 0:
		_cable_curve(_left_point(dragging), get_local_mouse_position() - jolt, WIRES[dragging])
	# Voltmetre LCD.
	var meter := Rect2(300, 364, 230, 84)
	_rounded(meter, Color("2b2f33"), Color("5d666d"), 3, 8)
	var lcd := Rect2(314, 376, 202, 44)
	var ok := completed_wires == total_wires
	_rounded(lcd, Color("0f1a12") if ok else Color("1a0f0f"), Color("0a0a0a"), 2, 4)
	var reading := ("0 V   GÜVENLİ" if breaker_down else "BAĞLANTI OK") if ok else ("KAÇAK!  220 V" if fmod(time, 0.8) < 0.55 else "")
	draw_string(font, Vector2(lcd.position.x, lcd.position.y + 30), reading, HORIZONTAL_ALIGNMENT_CENTER, lcd.size.x, 22, Color("6dff8a") if ok else Color("ff4d4d"))
	draw_string(font, Vector2(meter.position.x, meter.end.y - 8), "Bağlanan: %d / %d" % [completed_wires, total_wires], HORIZONTAL_ALIGNMENT_CENTER, meter.size.x, 13, Color("aab5bd"))
	# Şalter (DIN kesici): kablolara dokunmadan önce indirilmeli.
	_rounded(BREAKER, Color("ececea"), Color("8c918f"), 2, 4)
	draw_string(font, Vector2(BREAKER.position.x, BREAKER.position.y + 16), "C16", HORIZONTAL_ALIGNMENT_CENTER, BREAKER.size.x, 12, Color("333333"))
	var slot := Rect2(BREAKER.position.x + 24, BREAKER.position.y + 26, 22, 50)
	draw_rect(slot, Color("2b2b2b"))
	var lever_y := slot.position.y + (30.0 if breaker_down else 2.0)
	draw_rect(Rect2(slot.position.x + 2, lever_y, 18, 18), Color("1d6fd6") if not breaker_down else Color("5a5a5a"))
	draw_string(font, Vector2(BREAKER.position.x, BREAKER.end.y - 6), "0  OFF" if breaker_down else "I  ON", HORIZONTAL_ALIGNMENT_CENTER, BREAKER.size.x, 12, Color("333333"))
	if not breaker_down:
		var pulse := 0.5 + 0.5 * sin(time * 6.0)
		draw_rect(BREAKER.grow(6), Color(1, 0.85, 0.3, 0.4 + 0.5 * pulse), false, 3.0)
		draw_string(font, Vector2(BREAKER.position.x - 150, BREAKER.position.y - 10), "Elektriği kes: şalter (tıkla)", HORIZONTAL_ALIGNMENT_RIGHT, 210, 15, Color(1, 0.85, 0.3))
	if shock > 0.0:
		# Çarpılma: uçtan çıkan zikzak arklar ve kısa mavi-beyaz parlama.
		for a in 4:
			var pts := PackedVector2Array([shock_pos])
			var dir := Vector2.from_angle(TAU * a / 4.0 + time * 7.0)
			for k in 5:
				pts.append(shock_pos + dir * (k + 1) * 14.0 + dir.orthogonal() * randf_range(-9.0, 9.0))
			draw_polyline(pts, Color(0.75, 0.88, 1.0, shock), 2.5)
		draw_circle(shock_pos, 40.0 * shock, Color(0.8, 0.9, 1.0, 0.45 * shock))
		draw_rect(Rect2(Vector2.ZERO, SIZE), Color(0.75, 0.85, 1.0, 0.22 * shock))
	if warn > 0.0:
		# Minik uyarı (şalter etiketiyle çakışmaz).
		var wa := minf(1.0, warn * 1.5)
		draw_string(font, Vector2(240, 346), "Çarpıldım! Şalteri kapatmalıyım.", HORIZONTAL_ALIGNMENT_CENTER, 300, 19, Color(1, 0.55, 0.35, wa))
	# Kısa devre parlaması.
	if flash > 0.0:
		draw_circle(flash_pos, 90.0 * flash, Color(0.85, 0.92, 1.0, 0.55 * flash))
		draw_circle(flash_pos, 30.0 * flash, Color(1, 1, 1, flash))
		draw_string(font, Vector2(200, 352), "KISA DEVRE! Yanlış uç.", HORIZONTAL_ALIGNMENT_CENTER, 400, 22, Color(1, 0.4, 0.3, flash))
	draw_set_transform(Vector2.ZERO)


func _color_name(id: String) -> String:
	return {"L": "Kahverengi", "N": "Mavi", "PE": "Sarı-Yeşil"}[id]


func _rounded(rect: Rect2, fill: Color, border: Color, width: int, radius: int) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.draw(get_canvas_item(), rect)


func _screw(p: Vector2, r: float, angle: float) -> void:
	draw_circle(p, r + 1.5, Color("5c6166"))
	draw_circle(p, r, Color("b9bec2"))
	draw_circle(p + Vector2(-r * 0.25, -r * 0.25), r * 0.5, Color(1, 1, 1, 0.25))
	var d := Vector2(cos(angle + PI * 0.25), sin(angle + PI * 0.25)) * r * 0.75
	draw_line(p - d, p + d, Color("45494d"), 2.5)
	draw_line(p - d.orthogonal(), p + d.orthogonal(), Color("45494d"), 2.5)


func _hazard_band(rect: Rect2) -> void:
	draw_rect(rect, Color("f2c230"))
	var x := rect.position.x - rect.size.y
	while x < rect.end.x:
		var poly := PackedVector2Array([Vector2(x, rect.end.y), Vector2(x + 10, rect.position.y), Vector2(x + 20, rect.position.y), Vector2(x + 10, rect.end.y)])
		for i in poly.size():
			poly[i].x = clampf(poly[i].x, rect.position.x, rect.end.x)
		draw_colored_polygon(poly, Color("141414"))
		x += 24.0


func _cable_segment(a: Vector2, b: Vector2, w: Dictionary, width: float) -> void:
	draw_line(a, b, Color(0, 0, 0, 0.5), width + 3.0)
	draw_line(a, b, w.color, width)
	if w.stripe.a > 0.0:
		var length := a.distance_to(b)
		var dir := (b - a) / maxf(length, 0.001)
		var s := 0.0
		while s < length:
			draw_line(a + dir * s, a + dir * minf(s + 6.0, length), w.stripe, width * 0.55)
			s += 14.0
	draw_line(a + Vector2(0, -width * 0.25), b + Vector2(0, -width * 0.25), Color(1, 1, 1, 0.18), maxf(1.0, width * 0.2))


func _cable_curve(a: Vector2, b: Vector2, w: Dictionary) -> void:
	var sag := 40.0 + a.distance_to(b) * 0.08
	var c1 := a + Vector2(110, sag)
	var c2 := b + Vector2(-110, sag)
	var pts := PackedVector2Array()
	for k in 25:
		var t := k / 24.0
		var u := 1.0 - t
		pts.append(a * u * u * u + c1 * 3.0 * u * u * t + c2 * 3.0 * u * t * t + b * t * t * t)
	for k in pts.size() - 1:
		_cable_segment(pts[k], pts[k + 1], w, 9.0)
	draw_circle(b, 5.0, Color("d98a3d"))


func _sparks(p: Vector2, seed_offset: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(time * 20.0) * 7 + seed_offset * 131
	if rng.randf() < 0.35:
		return
	draw_circle(p, 10.0 + rng.randf() * 8.0, Color(0.7, 0.85, 1.0, 0.25))
	for k in 3:
		var q := p
		var bolt := PackedVector2Array([q])
		var dir := Vector2.from_angle(rng.randf_range(-PI, PI))
		for j in 4:
			q += dir * rng.randf_range(4, 9) + Vector2(rng.randf_range(-4, 4), rng.randf_range(-4, 4))
			bolt.append(q)
		draw_polyline(bolt, Color(1, 0.96, 0.6, 0.95), 2.0)


# --- Sesler ----------------------------------------------------------------------

func _player(stream: AudioStream) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = -6.0
	add_child(p)
	return p


func _tone(length: float, freq: float, decay: float, noise: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * length)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(freq)
	for i in n:
		var t := float(i) / rate
		var s := (sin(TAU * freq * t) * (1.0 - noise) + rng.randf_range(-1, 1) * noise) * exp(-t * decay)
		data.encode_s16(i * 2, int(clampf(s, -1, 1) * 26000))
	return _wav(data, rate, false)


func _crackle() -> AudioStreamWAV:
	var rate := 22050
	var n := rate
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var burst := 0.0
	for i in n:
		if rng.randf() < 0.0015:
			burst = rng.randf_range(0.3, 0.8)
		burst *= 0.993
		var hum := sin(TAU * 100.0 * float(i) / rate) * 0.08
		data.encode_s16(i * 2, int(clampf(rng.randf_range(-1, 1) * burst + hum, -1, 1) * 20000))
	return _wav(data, rate, true)


func _wav(data: PackedByteArray, rate: int, looping: bool) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	if looping:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = data.size() / 2
	return stream
