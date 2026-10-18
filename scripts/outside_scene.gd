extends CanvasLayer

# Dışarı sahnesi: karakter evden süre içinde çıktı. Önden görülür, hareket ettirilemez; yalnız
# konuşma balonları ve monologla sunulan seçimler. Osman ya da eşi kurtarılamadıysa oyuncu
# döngüyü yeniden başlatmak ile bu sonu kabul etmek arasında seçim yapar.
# Ayrıca hikâyenin kullandığı iki küçük parça: ChoicePanel (iki seçenek) ve EndingScreen (son ekranı).

const Sfx = preload("res://scripts/sfx.gd")
const CatSprite = preload("res://scripts/cat_sprite.gd")

var story: Node
var cat_saved := false
var wife_safe := false
var canvas: Control
var time := 0.0
var fade := 1.0
var bubble := ""
var bubble_age := 0.0
var waiting := false
var sheet: Texture2D
var cat_tex: Texture2D
var dust: Array = []
var stars: Array = []
var skyline: Array = []
var windows: Array = []
var rubble: Array = []
var fg_rubble: Array = []
var glints: Array = []
var siren: AudioStreamPlayer
var car_engine: AudioStreamPlayer
var car_tex: Texture2D
var trash_tex: Texture2D
var amb_tex: Texture2D
signal advance


func _ready() -> void:
	layer = 60
	canvas = Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	canvas.draw.connect(_draw_scene)
	add_child(canvas)
	sheet = load("res://assets/player_sheet.png")
	amb_tex = load("res://assets/vehicles/ambulance.png")
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for i in 40:
		dust.append([Vector2(rng.randf(), rng.randf()), rng.randf_range(0.2, 0.6), rng.randf() * TAU])
	for i in 70:
		stars.append([Vector2(rng.randf(), rng.randf()), 0, rng.randf() * TAU])
	var x := -0.02
	while x < 1.0:
		var w := rng.randf_range(0.05, 0.1)
		var h := rng.randf_range(0.12, 0.3)
		var wins := []
		for k in rng.randi_range(2, 6):
			wins.append(Vector2(rng.randf_range(0.15, 0.75), rng.randf_range(0.1, 0.8)))
		skyline.append([x, h, w, wins])
		x += w + rng.randf_range(0.0, 0.02)
	for i in 36:
		var r := rng.randf()
		windows.append(1 if r < 0.25 else (2 if r < 0.55 else 0))
	for i in 26:
		rubble.append([Vector2(rng.randf_range(-170, 100), rng.randf_range(-60, 0)), Vector2(rng.randf_range(8, 26), rng.randf_range(6, 16)), rng.randf_range(0.3, 0.5)])
	for i in 30:
		fg_rubble.append([Vector2(rng.randf(), rng.randf_range(0.67, 0.78)), Vector2(rng.randf_range(8, 24), rng.randf_range(6, 14)), rng.randf_range(0.25, 0.42)])
	for i in 18:
		glints.append([Vector2(rng.randf(), rng.randf_range(0.67, 0.79)), rng.randf() * TAU])
	siren = AudioStreamPlayer.new()
	siren.stream = _siren()
	siren.volume_db = -60.0
	add_child(siren)
	siren.play()
	car_tex = load("res://assets/vehicles/red_car.png")
	trash_tex = load("res://assets/outside/trash_can.png")
	car_engine = AudioStreamPlayer.new()
	car_engine.stream = _engine()
	car_engine.volume_db = -60.0
	add_child(car_engine)
	car_engine.play()
	_run()


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _say(text: String) -> void:
	bubble = text
	bubble_age = 0.0
	if story != null:
		story.blip("man")
	waiting = true
	await advance
	bubble = ""


func _input(event: InputEvent) -> void:
	if not waiting:
		return
	# Konuşma balonu E/Enter/Boşluk ya da farenin sol tıkıyla ilerler.
	var click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if not click and (not (event is InputEventKey) or not event.pressed or event.echo):
		return
	if (click or event.physical_keycode in [KEY_E, KEY_ENTER, KEY_SPACE]) and bubble_age > 0.35:
		get_viewport().set_input_as_handled()
		waiting = false
		advance.emit()


func _run() -> void:
	var t := create_tween()
	t.tween_property(self, "fade", 0.0, 1.6)
	await t.finished
	await _say("Dışarıdayım... Başardım.")
	if cat_saved and wife_safe:
		await _say("Osman kucağımda. Karım güvende, açık alanda.")
		await _say("Bitti... Bu sefer gerçekten bitti.")
		story.show_ending(true, cat_saved, wife_safe, "outside")
		return
	if not cat_saved:
		await _say("Osman... Onu içeride bıraktım.")
		await _say("Her sabah patisiyle yüzüme dokunurdu. Mırlaması olmadan bu ev...")
		await _say("Onu kurtaramadım. Seni çok seviyordum, oğlum.")
	if not wife_safe:
		await _say("Ve karım... Telefonda beni dinlemedi. Onu ikna edemedim.")
	await _say("Bir dakika... Her öldüğümde aynı geceye dönüyorum.")
	await _say("Ölürsem döngü başa döner. Bir şansım daha olur.")
	story.offer_restart_or_accept(cat_saved, wife_safe, "outside")


func _process(delta: float) -> void:
	time += delta
	# Sirenler araç ekranın ortasına yaklaştıkça yükselir, uzaklaşınca söner (hafif Doppler).
	var view := canvas.size
	for v in [[siren, _amb_x(view), -1.0], [car_engine, _car_x(view), 1.0]]:
		var off: float = (v[1] - view.x * 0.5) / view.x
		var near := clampf(1.0 - absf(off) / 0.9, 0.0, 1.0)
		v[0].volume_db = lerpf(-42.0, -3.0, near * near) if near > 0.0 else -60.0
		# Yaklaşırken ince, uzaklaşırken kalın (yön: -1 sağdan sola, +1 soldan sağa).
		v[0].pitch_scale = 1.06 if off * v[2] < 0.0 else 0.94
	bubble_age += delta
	for d in dust:
		d[0].y += delta * 0.01 * d[1]
		d[0].x += sin(time + d[2]) * delta * 0.004
		if d[0].y > 1.0:
			d[0].y = 0.0
	canvas.queue_redraw()


# Dış atmosfer: gece, uzakta yanan ışıklı şehir silüeti, köşesi çökmüş apartman (duman ve içeriden
# turuncu yangın ışığı), acil durum araçları, battaniyeli komşular, sokak lambası, park etmiş araba,
# ağaç, moloz, cam kırıkları ve yerdeki su birikintisinde siren yansıması. Yıkık ama dolu bir sahne.
func _draw_scene() -> void:
	var view := canvas.size
	if view.x < 2.0 or view.y < 2.0:
		return # ilk karede boyut henüz sıfır; çokgenler bozulmasın
	var font := ThemeDB.fallback_font
	var px := view.x / 360.0
	var ground := view.y * GROUND
	var s := 0.5 + 0.5 * sin(time * 6.0)
	_sky(view, ground)
	_skyline(view, ground)
	_building(view, ground)
	_smoke(view)
	_street(view, ground, s)
	_foreground(view, ground, px)
	_trash(view, ground)
	_people(view, ground, px)
	# Karakter evin önündeki kaldırımda, önden; Osman kurtarıldıysa yanında oturur.
	var scale := 5.4
	var size := 32.0 * scale
	var feet := Vector2(view.x * 0.5, view.y * 0.785)
	var origin := feet - Vector2(size * 0.5, size)
	canvas.draw_set_transform(feet, 0.0, Vector2(2.6, 0.5))
	canvas.draw_circle(Vector2.ZERO, 32, Color(0, 0, 0, 0.35))
	canvas.draw_set_transform(Vector2.ZERO)
	canvas.draw_texture_rect_region(sheet, Rect2(origin, Vector2(size, size)), Rect2(0, 0, 32, 32))
	# Siren ışığı karakterin kenarına vurur.
	canvas.draw_rect(Rect2(origin + Vector2(size * 0.3, size * 0.1), Vector2(size * 0.08, size * 0.85)), Color(0.9, 0.15, 0.15, 0.12 * s))
	if cat_saved:
		CatSprite.draw(canvas, "sit", CatSprite.DOWN, minf(time, 0.95), 6.0, feet + Vector2(size * 0.42, -2), 3.5)
	# Yoldaki araçlar kaldırımın önünde (aşağıda) olduğu için en son çizilir.
	_vehicles(view, s)
	for d in dust:
		canvas.draw_rect(Rect2(Vector2(d[0].x * view.x, d[0].y * view.y), Vector2(3, 3)), Color(0.85, 0.8, 0.7, 0.3))
	# Kenar kararması ve siren tonu.
	canvas.draw_rect(Rect2(0, 0, view.x, view.y), Color(0.9, 0.1, 0.1, 0.035 * s))
	canvas.draw_rect(Rect2(0, 0, view.x, view.y), Color(0.15, 0.25, 0.95, 0.035 * (1.0 - s)))
	for k in 6:
		canvas.draw_rect(Rect2(0, 0, view.x, view.y).grow(-k * 26.0), Color(0, 0, 0, 0.05), false, 26.0)
	if bubble != "":
		var shown := bubble.substr(0, mini(bubble.length(), int(bubble_age * 45.0)))
		var box := Rect2(view.x * 0.5 - 280, origin.y - 112, 560, 84)
		canvas.draw_rect(box, Color(0.98, 0.97, 0.93, 0.95))
		canvas.draw_rect(box, Color(0.3, 0.25, 0.2), false, 2.0)
		canvas.draw_multiline_string(font, box.position + Vector2(20, 38), shown, HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 70, 26, -1, Color(0.15, 0.12, 0.1))
		if waiting and shown.length() >= bubble.length():
			var chip := Rect2(box.end - Vector2(40, 32), Vector2(26, 22))
			canvas.draw_rect(chip, Color(0.98, 0.9, 0.72))
			canvas.draw_rect(chip, Color(0.35, 0.22, 0.12), false, 2.0)
			canvas.draw_string(font, chip.position + Vector2(0, 17), "E", HORIZONTAL_ALIGNMENT_CENTER, chip.size.x, 16, Color(0.25, 0.15, 0.08))
	if fade > 0.0:
		canvas.draw_rect(Rect2(Vector2.ZERO, view), Color(0, 0, 0, fade))


func _sky(view: Vector2, ground: float) -> void:
	for i in 40:
		var t := float(i) / 39.0
		canvas.draw_rect(Rect2(0, ground * i / 40.0, view.x, ground / 40.0 + 1), Color(0.03, 0.04, 0.1).lerp(Color(0.32, 0.13, 0.12), pow(t, 1.6)))
	for st in stars:
		var tw := 0.5 + 0.5 * sin(time * 1.5 + st[2])
		canvas.draw_rect(Rect2(Vector2(st[0].x * view.x, st[0].y * view.y * 0.4), Vector2(2, 2)), Color(1, 1, 1, 0.2 + 0.4 * tw))
	canvas.draw_circle(Vector2(view.x * 0.84, view.y * 0.12), 30, Color(0.96, 0.93, 0.8, 0.85))
	canvas.draw_circle(Vector2(view.x * 0.84 + 11, view.y * 0.12 - 7), 27, Color(0.06, 0.06, 0.13, 0.92))


func _skyline(view: Vector2, ground: float) -> void:
	for b in skyline:
		var r := Rect2(b[0] * view.x, ground - b[1] * view.y, b[2] * view.x, b[1] * view.y)
		canvas.draw_rect(r, Color(0.09, 0.08, 0.13))
		for w in b[3]:
			var wr := Rect2(r.position + Vector2(w.x * r.size.x, w.y * r.size.y), Vector2(5, 6))
			canvas.draw_rect(wr, Color(1, 0.8, 0.45, 0.55))
	# Uzakta bir yangının turuncu ışıması.
	canvas.draw_circle(Vector2(view.x * 0.08, ground - 10), 90, Color(1, 0.45, 0.15, 0.06 + 0.02 * sin(time * 7.0)))


func _building(view: Vector2, ground: float) -> void:
	var bld := Rect2(view.x * 0.24, view.y * 0.1, view.x * 0.52, ground - view.y * 0.1)
	# Gövde: beton cephe, kat çizgileri.
	canvas.draw_rect(bld, Color(0.2, 0.19, 0.21))
	canvas.draw_rect(Rect2(bld.position, Vector2(14, bld.size.y)), Color(0.15, 0.14, 0.16))
	var floors := 6
	var cols := 6
	var fh := bld.size.y / floors
	for f in floors:
		canvas.draw_rect(Rect2(bld.position.x, bld.position.y + f * fh, bld.size.x, 5), Color(0.27, 0.25, 0.27))
		for c in cols:
			var idx := f * cols + c
			var win := Rect2(bld.position + Vector2(26 + c * (bld.size.x - 52) / cols, f * fh + 18), Vector2((bld.size.x - 52) / cols - 22, fh - 34))
			var kind: int = windows[idx]
			# Sağ üst köşe çöktü: o bölgede pencere yok.
			if c >= 4 and f <= 1:
				continue
			if kind == 0:
				canvas.draw_rect(win, Color(0.05, 0.05, 0.07))
			elif kind == 1:
				var flick := 0.75 + 0.25 * sin(time * 9.0 + idx)
				canvas.draw_rect(win, Color(1, 0.72, 0.38, 0.85 * flick))
			else:
				# Kırık cam: karanlık + kırık kenar.
				canvas.draw_rect(win, Color(0.05, 0.05, 0.07))
				canvas.draw_colored_polygon(PackedVector2Array([win.position, win.position + Vector2(win.size.x * 0.6, 0), win.position + Vector2(win.size.x * 0.2, win.size.y * 0.5)]), Color(0.55, 0.65, 0.75, 0.6))
			canvas.draw_rect(win, Color(0.12, 0.11, 0.12), false, 3.0)
			# Balkon korkulukları.
			if f % 2 == 1 and c % 2 == 0:
				canvas.draw_rect(Rect2(win.position.x - 6, win.end.y + 4, win.size.x + 12, 4), Color(0.32, 0.3, 0.32))
	# Çöken köşe: kırık dişli kenar, sarkan demir ve içeriden yangın ışığı.
	var corner := PackedVector2Array([Vector2(bld.position.x + bld.size.x * 0.62, bld.position.y - 2), Vector2(bld.end.x + 2, bld.position.y - 2),
		Vector2(bld.end.x + 2, bld.position.y + fh * 2.3), Vector2(bld.end.x - 40, bld.position.y + fh * 2.0),
		Vector2(bld.end.x - 90, bld.position.y + fh * 1.6), Vector2(bld.end.x - 120, bld.position.y + fh * 0.9),
		Vector2(bld.position.x + bld.size.x * 0.66, bld.position.y + fh * 0.4)])
	var sky := Color(0.13, 0.07, 0.11)
	canvas.draw_colored_polygon(corner, sky)
	canvas.draw_circle(Vector2(bld.end.x - 70, bld.position.y + fh * 1.9), 60 + 8 * sin(time * 5.0), Color(1, 0.45, 0.12, 0.18))
	for k in 5:
		var x := bld.end.x - 120 + k * 22
		canvas.draw_line(Vector2(x, bld.position.y + fh * (1.1 + k * 0.2)), Vector2(x + 8, bld.position.y + fh * (1.6 + k * 0.2)), Color(0.4, 0.3, 0.25), 3.0)
	# Cephe çatlakları.
	canvas.draw_polyline(PackedVector2Array([bld.position + Vector2(bld.size.x * 0.42, fh * 1.2), bld.position + Vector2(bld.size.x * 0.47, fh * 2.4),
		bld.position + Vector2(bld.size.x * 0.4, fh * 3.6), bld.position + Vector2(bld.size.x * 0.46, fh * 5.2)]), Color(0.08, 0.07, 0.08), 4.0)
	# Binanın dibinde moloz yığını (çöken köşeden).
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(bld.end.x - 170, ground), Vector2(bld.end.x - 90, ground - 70), Vector2(bld.end.x - 20, ground - 95),
		Vector2(bld.end.x + 60, ground - 40), Vector2(bld.end.x + 110, ground)]), Color(0.3, 0.28, 0.27))
	for r in rubble:
		canvas.draw_rect(Rect2(Vector2(bld.end.x + r[0].x, ground + r[0].y), r[1]), Color(r[2], r[2] * 0.95, r[2] * 0.9))


func _smoke(view: Vector2) -> void:
	for k in 9:
		var t := fmod(time * 0.06 + k * 0.11, 1.0)
		var p := Vector2(view.x * (0.68 + t * 0.05) + sin(time * 0.5 + k) * 20, view.y * (0.28 - t * 0.28))
		canvas.draw_circle(p, 40 + t * 70, Color(0.16, 0.14, 0.15, 0.32 * (1.0 - t)))


# Sahne katmanları (ekran yüksekliğine oran): bina tabanı = kaldırım başı, bordür, iki şerit.
const GROUND := 0.64
const CURB := 0.8
const LANE_UP := 0.87    # üst şerit (ambulans, sağdan sola)
const LANE_DOWN := 0.96  # alt şerit (gri otomobil, soldan sağa)


func _street(view: Vector2, ground: float, s: float) -> void:
	var curb := view.y * CURB
	# Kaldırım: evin önü, karo derzleri.
	canvas.draw_rect(Rect2(0, ground, view.x, curb - ground), Color(0.3, 0.29, 0.3))
	canvas.draw_line(Vector2(0, (ground + curb) * 0.5), Vector2(view.x, (ground + curb) * 0.5), Color(0.24, 0.23, 0.24), 2.0)
	var jx := 0.0
	while jx < view.x:
		canvas.draw_line(Vector2(jx, ground), Vector2(jx, curb), Color(0.24, 0.23, 0.24), 2.0)
		jx += 72.0
	# Bordür taşı.
	canvas.draw_rect(Rect2(0, curb, view.x, 12), Color(0.5, 0.49, 0.47))
	canvas.draw_rect(Rect2(0, curb + 9, view.x, 3), Color(0.32, 0.31, 0.3))
	# Asfalt ve iki şeridi ayıran kesik çizgi.
	canvas.draw_rect(Rect2(0, curb + 12, view.x, view.y - curb - 12), Color(0.12, 0.12, 0.13))
	var mid := view.y * (LANE_UP + 0.03)
	for k in 9:
		canvas.draw_rect(Rect2(k * view.x / 8.0 - 30, mid, 80, 7), Color(0.75, 0.7, 0.45, 0.35))
	# Su birikintisi (yolda): siren yansıması.
	var pud := Rect2(view.x * 0.1, view.y * 0.86, 260, 30)
	canvas.draw_set_transform(pud.get_center(), 0.0, Vector2(1.0, 0.22))
	canvas.draw_circle(Vector2.ZERO, pud.size.x * 0.5, Color(0.2, 0.25, 0.35, 0.7))
	canvas.draw_circle(Vector2(-40, 0), 50, Color(0.9, 0.15, 0.15, 0.35 * s))
	canvas.draw_circle(Vector2(50, 0), 50, Color(0.2, 0.35, 1.0, 0.35 * (1.0 - s)))
	canvas.draw_set_transform(Vector2.ZERO)
	# Sokak lambası (kaldırım kenarında, titrek) ve ışık konisi.
	var lx := view.x * 0.9
	canvas.draw_rect(Rect2(lx, view.y * 0.24, 8, curb - view.y * 0.24 - 4), Color(0.22, 0.22, 0.24))
	canvas.draw_rect(Rect2(lx - 26, view.y * 0.24, 34, 6), Color(0.22, 0.22, 0.24))
	var on := 1.0 if fmod(time, 3.7) > 0.25 else 0.2
	canvas.draw_circle(Vector2(lx - 24, view.y * 0.25 + 6), 10, Color(1, 0.86, 0.55, 0.9 * on))
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(lx - 24, view.y * 0.26), Vector2(lx - 150, view.y * 0.98), Vector2(lx + 90, view.y * 0.98)]), Color(1, 0.85, 0.5, 0.07 * on))
	# Ağaç (kaldırımda).
	var tx := view.x * 0.06
	var tb := ground + 70.0
	canvas.draw_rect(Rect2(tx, tb - 130, 14, 130), Color(0.2, 0.13, 0.08))
	for k in 5:
		canvas.draw_circle(Vector2(tx + 7 + sin(k * 2.0) * 34, tb - 160 - k * 14), 44 - k * 4, Color(0.08, 0.16, 0.1))
	# Emniyet şeridi: binanın önünü kaldırımdan ayırır.
	var tape_y := ground + 10
	canvas.draw_line(Vector2(view.x * 0.2, tape_y), Vector2(view.x * 0.8, tape_y + 6), Color(0.95, 0.8, 0.15), 4.0)
	for k in 12:
		var x := view.x * 0.2 + k * view.x * 0.05
		canvas.draw_line(Vector2(x, tape_y + k * 0.5 - 2), Vector2(x + 10, tape_y + k * 0.5 + 2), Color(0.1, 0.1, 0.1), 3.0)


func _vehicles(view: Vector2, s: float) -> void:
	# Ambulans üst şeritte sağdan sola hızla geçer; kırmızı otomobil karşı yönden, alt şeritte soldan sağa.
	var bump := sin(time * 34.0) * 1.2
	_draw_ambulance(Vector2(_amb_x(view), view.y * LANE_UP + bump), s)
	_draw_car(Vector2(_car_x(view), view.y * LANE_DOWN - bump))


const AMB_START := 1.2
const AMB_TIME := 3.4     # hızlı geçiş
const CAR_START := 2.6
const CAR_TIME := 5.0


func _pass(start: float, dur: float) -> float:
	return clampf((time - start) / dur, 0.0, 1.0)


# Ambulans: sağda ekran dışından başlar, solda çıkar.
func _amb_x(view: Vector2) -> float:
	return lerpf(view.x * 1.3, -view.x * 0.3, _pass(AMB_START, AMB_TIME))


# Kırmızı otomobil: solda ekran dışından başlar, sağda çıkar.
func _car_x(view: Vector2) -> float:
	return lerpf(-view.x * 0.3, view.x * 1.3, _pass(CAR_START, CAR_TIME))


# Ambulans (piksel görsel, zaten sola bakıyor: aynalamadan çizilir); tepe lambası kırmızı yanıp söner.
const AMB_REGION := Rect2(14, 54, 171, 88)
const AMB_SCALE := 1.6


func _draw_ambulance(base: Vector2, s: float) -> void:
	if amb_tex == null:
		return
	var size := AMB_REGION.size * AMB_SCALE
	var rect := Rect2(base - Vector2(size.x * 0.5, size.y), size)
	canvas.draw_set_transform(base + Vector2(0, 4), 0.0, Vector2(2.4, 0.4))
	canvas.draw_circle(Vector2.ZERO, size.x * 0.21, Color(0, 0, 0, 0.35))
	canvas.draw_set_transform(Vector2.ZERO)
	# Hız izi: arkasında (sağda) silik çizgiler.
	for k in 4:
		var y := rect.position.y + size.y * (0.3 + k * 0.15)
		canvas.draw_line(Vector2(rect.end.x + 10, y), Vector2(rect.end.x + 70 + k * 18, y), Color(1, 1, 1, 0.1), 2.0)
	canvas.draw_texture_rect_region(amb_tex, rect, AMB_REGION)
	# Tepe lambası (ön-üst) ve çevresine vuran siren ışığı.
	var lamp := rect.position + Vector2((72.0 - AMB_REGION.position.x) * AMB_SCALE, (62.0 - AMB_REGION.position.y) * AMB_SCALE)
	canvas.draw_circle(lamp, 7.0, Color(1.0, 0.15, 0.2, 0.35 + 0.65 * s))
	canvas.draw_circle(lamp, 100.0, Color(1.0, 0.15, 0.2, 0.12 * s))
	canvas.draw_circle(lamp + Vector2(60, 0), 80.0, Color(0.2, 0.35, 1.0, 0.08 * (1.0 - s)))
	# Far ışığı önüne (sola) düşer.
	var front := Vector2(rect.position.x, rect.end.y)
	canvas.draw_colored_polygon(PackedVector2Array([front + Vector2(0, -26), front + Vector2(-170, -46), front + Vector2(-170, 10)]), Color(1, 0.95, 0.75, 0.12))


# Kırmızı otomobil zaten sağa bakar; 4× tam sayı ölçeği piksel netliğini korur.
const CAR_SCALE := 4.0


func _draw_car(base: Vector2) -> void:
	if car_tex == null:
		return
	var size := Vector2(car_tex.get_size()) * CAR_SCALE
	var rect := Rect2(base - Vector2(size.x * 0.5, size.y), size)
	canvas.draw_set_transform(base + Vector2(0, 4), 0.0, Vector2(2.4, 0.4))
	canvas.draw_circle(Vector2.ZERO, size.x * 0.2, Color(0, 0, 0, 0.35))
	canvas.draw_set_transform(Vector2.ZERO)
	# Hız izi arkasında (solda).
	for k in 3:
		var y := rect.position.y + size.y * (0.35 + k * 0.17)
		canvas.draw_line(Vector2(rect.position.x - 10, y), Vector2(rect.position.x - 60 - k * 16, y), Color(1, 1, 1, 0.08), 2.0)
	# Kaynak görsel sağa bakıyor; geçiş yönüyle aynı yönde çizilir.
	canvas.draw_set_transform(base)
	canvas.draw_texture_rect(car_tex, Rect2(Vector2(-size.x * 0.5, -size.y), size), false)
	canvas.draw_set_transform(Vector2.ZERO)
	# Far ışığı önüne (sağa), arkada kırmızı stop lambası parıltısı.
	var front := Vector2(rect.end.x, rect.end.y)
	canvas.draw_colored_polygon(PackedVector2Array([front + Vector2(-4, -40), front + Vector2(150, -58), front + Vector2(150, -6)]), Color(1, 0.95, 0.75, 0.12))
	canvas.draw_circle(Vector2(rect.position.x + size.x * 0.04, rect.position.y + size.y * 0.45), 16.0, Color(1.0, 0.15, 0.1, 0.25))


# Kaldırımda iki çöp kovası: solda görsel olduğu gibi, binanın sağında aynalanmış (kapak sağda).
const TRASH_SCALE := 0.85


func _trash(view: Vector2, ground: float) -> void:
	if trash_tex == null:
		return
	var size := Vector2(trash_tex.get_size()) * TRASH_SCALE
	var left := Vector2(view.x * 0.24 - 72.0, ground + 74.0)
	var right := Vector2(view.x * 0.76 + 140.0, ground + 74.0)
	for spot in [[left, 1.0], [right, -1.0]]:
		var base: Vector2 = spot[0]
		canvas.draw_set_transform(base + Vector2(0, 2), 0.0, Vector2(2.0, 0.35))
		canvas.draw_circle(Vector2.ZERO, size.x * 0.28, Color(0, 0, 0, 0.3))
		canvas.draw_set_transform(base, 0.0, Vector2(spot[1], 1.0))
		canvas.draw_texture_rect(trash_tex, Rect2(Vector2(-size.x * 0.5, -size.y), size), false)
	canvas.draw_set_transform(Vector2.ZERO)


# Battaniyeli komşular: siluetler, biri hafifçe sallanıyor.
func _people(view: Vector2, ground: float, px: float) -> void:
	var spots := [Vector2(view.x * 0.25, ground + 56), Vector2(view.x * 0.285, ground + 64), Vector2(view.x * 0.74, ground + 60)]
	for k in spots.size():
		var p: Vector2 = spots[k] + Vector2(sin(time * 1.3 + k) * 1.5, 0)
		var h := 74.0 - k * 6.0
		canvas.draw_rect(Rect2(p - Vector2(13, h), Vector2(26, h)), Color(0.12, 0.11, 0.14))
		canvas.draw_circle(p - Vector2(0, h + 10), 11, Color(0.12, 0.11, 0.14))
		# Battaniye.
		canvas.draw_colored_polygon(PackedVector2Array([p - Vector2(18, h - 6), p - Vector2(-18, h - 6), p + Vector2(16, -4), p + Vector2(-16, -4)]), Color(0.55, 0.3, 0.2, 0.9) if k != 1 else Color(0.3, 0.4, 0.55, 0.9))


func _foreground(view: Vector2, ground: float, px: float) -> void:
	for r in fg_rubble:
		var p := Vector2(r[0].x * view.x, view.y * r[0].y)
		canvas.draw_rect(Rect2(p, r[1]), Color(r[2], r[2] * 0.95, r[2] * 0.9))
		canvas.draw_rect(Rect2(p, Vector2(r[1].x, 3)), Color(r[2] + 0.12, r[2] + 0.1, r[2] + 0.08))
	for g in glints:
		var tw := pow(maxf(0.0, sin(time * 2.0 + g[1])), 8.0)
		if tw > 0.05:
			var p := Vector2(g[0].x * view.x, view.y * g[0].y)
			canvas.draw_line(p - Vector2(4, 0) * tw, p + Vector2(4, 0) * tw, Color(1, 1, 1, tw), 1.5)
			canvas.draw_line(p - Vector2(0, 4) * tw, p + Vector2(0, 4) * tw, Color(1, 1, 1, tw), 1.5)


# Polis sireni: yükselip alçalan uzun ses (wail).
# Geçen otomobil: alçak motor uğultusu ve lastik hışırtısı (döngü; ses yakınlıkla yükselir).
func _engine() -> AudioStreamWAV:
	var rate := 22050
	var n := rate * 2
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var low := 0.0
	for i in n:
		var t := float(i) / rate
		var f := 62.0 + 3.0 * sin(TAU * 0.5 * t)
		var v := sin(TAU * f * t) * 0.45 + sin(TAU * f * 2.0 * t) * 0.25 + sin(TAU * f * 3.0 * t) * 0.1
		low += (rng.randf_range(-1, 1) - low) * 0.08
		v += low * 0.9
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 9000.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = rate
	st.data = data
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_end = n
	return st


func _siren() -> AudioStreamWAV:
	var rate := 22050
	var n := rate * 2
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t := float(i) / rate
		var f := 620.0 if fmod(t, 1.0) < 0.5 else 820.0
		phase += f / rate
		data.encode_s16(i * 2, int(sin(TAU * phase) * 6000.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = rate
	st.data = data
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_end = n
	return st


# İki seçenek: ↑/↓ (ya da 1/2) ile seç, E/Enter ile onayla.
class ChoicePanel extends CanvasLayer:
	signal picked(index: int)
	var options: Array = []
	var title := ""
	var cursor := 0
	var canvas: Control
	var age := 0.0

	func _ready() -> void:
		layer = 90
		canvas = Control.new()
		canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		canvas.mouse_filter = Control.MOUSE_FILTER_STOP
		canvas.draw.connect(_draw_panel)
		add_child(canvas)

	func _process(delta: float) -> void:
		age += delta
		canvas.queue_redraw()

	# Fare: satırın üstüne gelince seçilir, sol tıkla onaylanır.
	func _row_at(pos: Vector2) -> int:
		var view := canvas.size
		var h := 70.0 + options.size() * 58.0
		var box := Rect2(view.x * 0.5 - 480, view.y - h - 40, 960, h)
		for i in options.size():
			if Rect2(box.position + Vector2(18, 54 + i * 58), Vector2(box.size.x - 36, 50)).has_point(pos):
				return i
		return -1

	func _input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			var hover := _row_at(event.position)
			if hover >= 0:
				cursor = hover
			return
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			get_viewport().set_input_as_handled()
			if age < 0.3:
				return
			var row := _row_at(event.position)
			picked.emit(row if row >= 0 else cursor)
			queue_free()
			return
		if not (event is InputEventKey) or not event.pressed or event.echo:
			return
		get_viewport().set_input_as_handled()
		if age < 0.3:
			return
		match event.physical_keycode:
			KEY_UP, KEY_W:
				cursor = (cursor + options.size() - 1) % options.size()
			KEY_DOWN, KEY_S:
				cursor = (cursor + 1) % options.size()
			KEY_1:
				cursor = 0
			KEY_2:
				cursor = mini(1, options.size() - 1)
			KEY_E, KEY_ENTER, KEY_SPACE:
				picked.emit(cursor)
				queue_free()

	func _draw_panel() -> void:
		var view := canvas.size
		var font := ThemeDB.fallback_font
		var h := 70.0 + options.size() * 58.0
		var box := Rect2(view.x * 0.5 - 480, view.y - h - 40, 960, h)
		canvas.draw_rect(box, Color(0.08, 0.06, 0.05, 0.92))
		canvas.draw_rect(box, Color(0.95, 0.75, 0.45), false, 3.0)
		canvas.draw_string(font, box.position + Vector2(24, 38), title, HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 48, 22, Color(1, 0.86, 0.6))
		for i in options.size():
			var row := Rect2(box.position + Vector2(18, 54 + i * 58), Vector2(box.size.x - 36, 50))
			if i == cursor:
				canvas.draw_rect(row, Color(0.95, 0.75, 0.45, 0.25))
				canvas.draw_rect(row, Color(0.95, 0.75, 0.45), false, 2.0)
			canvas.draw_string(font, row.position + Vector2(16, 33), "%d)  %s" % [i + 1, options[i]], HORIZONTAL_ALIGNMENT_LEFT, row.size.x - 32, 21, Color(1, 0.97, 0.9))


# Son ekranı: başlık, Osman'ın ve eşinin durumu; R ile baştan.
class EndingScreen extends CanvasLayer:
	var story: Node
	var title := ""
	var lines: Array = []
	var canvas: Control
	var a := 0.0

	func _ready() -> void:
		layer = 95
		canvas = Control.new()
		canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		canvas.mouse_filter = Control.MOUSE_FILTER_STOP
		canvas.draw.connect(_draw_end)
		add_child(canvas)
		create_tween().tween_property(self, "a", 1.0, 2.0)

	func _process(_delta: float) -> void:
		canvas.queue_redraw()

	func _input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R and a > 0.9:
			get_viewport().set_input_as_handled()
			story.restart_all()

	func _draw_end() -> void:
		var view := canvas.size
		var font := ThemeDB.fallback_font
		canvas.draw_rect(Rect2(Vector2.ZERO, view), Color(0.04, 0.04, 0.05, a))
		canvas.draw_string(font, Vector2(0, view.y * 0.36), title, HORIZONTAL_ALIGNMENT_CENTER, view.x, 54, Color(0.96, 0.93, 0.86, a))
		for i in lines.size():
			canvas.draw_string(font, Vector2(0, view.y * 0.5 + i * 40), lines[i], HORIZONTAL_ALIGNMENT_CENTER, view.x, 24, Color(0.85, 0.82, 0.76, a))
		canvas.draw_string(font, Vector2(0, view.y - 40), "R  —  yeniden oyna", HORIZONTAL_ALIGNMENT_CENTER, view.x, 18, Color(1, 1, 1, 0.5 * a))
