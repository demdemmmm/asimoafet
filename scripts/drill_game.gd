extends CanvasLayer

# Dolap vidalama mini oyunu: dolabın üst köşesini duvara bağlayan iki L-plakada 4 delik.
# Her vida: yumuşakça gidip gelen matkap ucu deliğin üstündeyken (yeşil halka) E'ye bas → uç deliğe
# kayar; E'yi basılı tut → mandren döner, talaş saçılır, vida gömülür (deliğin çevresinde dolum halkası).
# Iska: uç kayar, ahşapta çizik kalır. Her vidada uç biraz hızlanır.
signal screw_done(count: int)
signal finished

const Sfx = preload("res://scripts/sfx.gd")
const SIZE := Vector2(860, 520)
# İki L-köşebent yan yana ve paralel: her birinin bir kanadı duvarda, diğeri dolabın üstünde;
# kanatlar dolap–duvar birleşim çizgisinde (y 290) bitişir. Delikler aynı hizada.
const HOLES := [Vector2(330, 250), Vector2(330, 332), Vector2(530, 250), Vector2(530, 332)]
const HIT := 18.0
const DRIVE_TIME := 1.1
const SWEEP := 160.0

var canvas: Control
var time := 0.0
var hole := 0
var aligned := false
var snap := 0.0
var progress := 0.0
var spin := 0.0
var sweep_phase := 0.0
var tip_x := 0.0
var tip_vel := 0.0
var trail: Array = []
var scratches: Array = []
var dust: Array = []
var pops: Array = []
var shake := 0.0
var message := ""
var message_time := 0.0
var done_time := -1.0
var appear := 0.0
var motor: AudioStreamPlayer
var click: AudioStreamPlayer
var slip: AudioStreamPlayer


func _ready() -> void:
	layer = 28
	canvas = Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.draw.connect(_draw_ui)
	add_child(canvas)
	motor = _player(Sfx.drill_loop(), -6.0)
	click = _player(Sfx.blip(), -2.0)
	slip = _player(Sfx.cloth(), 0.0)
	tip_x = HOLES[0].x - SWEEP


func _player(stream: AudioStream, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	add_child(p)
	return p


func _origin() -> Vector2:
	return (canvas.size - SIZE) * 0.5 + Vector2(0, (1.0 - _ease(appear)) * 60.0)


func _ease(k: float) -> float:
	return 1.0 - pow(1.0 - clampf(k, 0.0, 1.0), 3.0)


func _input(event: InputEvent) -> void:
	var confirm: bool = (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_E) \
		or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if not confirm:
		return
	get_viewport().set_input_as_handled()
	if done_time >= 0.0 or aligned or appear < 0.6:
		return
	var target: Vector2 = HOLES[hole]
	if absf(tip_x - target.x) <= HIT:
		aligned = true
		snap = 0.0
		click.pitch_scale = 1.6
		click.play()
		pops.append({"pos": target, "age": 0.0, "color": Color(0.5, 1.0, 0.5)})
		_say("Hizalandı! Şimdi E veya sol tık BASILI tut.")
	else:
		scratches.append([Vector2(tip_x, target.y), randf_range(-0.6, 0.6)])
		shake = 1.0
		slip.play()
		for k in 6:
			dust.append({"pos": Vector2(tip_x, target.y), "vel": Vector2(randf_range(-120, 120), randf_range(-160, -40)), "age": 0.0})
		_say("Kaydı! Uç deliğin tam üstündeyken bas.")


func _say(text: String) -> void:
	message = text
	message_time = 1.8


func _process(delta: float) -> void:
	time += delta
	appear = minf(1.0, appear + delta * 3.0)
	shake = maxf(0.0, shake - delta * 4.0)
	message_time = maxf(0.0, message_time - delta)
	for d in dust:
		d.age += delta
		d.vel.y += 520.0 * delta
		d.pos += d.vel * delta
	dust = dust.filter(func(d): return d.age < 0.9)
	for p in pops:
		p.age += delta
	pops = pops.filter(func(p): return p.age < 0.6)
	if done_time >= 0.0:
		if time - done_time > 1.3:
			finished.emit()
			queue_free()
		canvas.queue_redraw()
		return
	var target: Vector2 = HOLES[hole]
	var prev := tip_x
	if not aligned:
		# Yumuşak gidip gelme (sinüs), her vidada biraz daha hızlı.
		sweep_phase += delta * (1.7 + hole * 0.4)
		tip_x = target.x + sin(sweep_phase) * SWEEP
		if motor.playing:
			motor.stop()
	else:
		# Uç deliğe yumuşakça kayar, sonra basılı tutunca vida döner ve gömülür.
		snap = minf(1.0, snap + delta * 8.0)
		tip_x = lerpf(tip_x, target.x, _ease(snap))
		var holding := (Input.is_physical_key_pressed(KEY_E) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)) and snap >= 1.0
		if holding:
			progress += delta / DRIVE_TIME
			spin += delta * 38.0
			if not motor.playing:
				motor.play()
			motor.pitch_scale = 0.8 + progress * 0.5
			if randf() < 0.7:
				dust.append({"pos": target + Vector2(randf_range(-6, 6), 0), "vel": Vector2(randf_range(-170, 170), randf_range(-220, -60)), "age": 0.0})
			shake = maxf(shake, 0.15)
		elif motor.playing:
			motor.stop()
		if progress >= 1.0:
			motor.stop()
			click.pitch_scale = 0.9
			click.play()
			pops.append({"pos": target, "age": 0.0, "color": Color(1.0, 0.85, 0.3)})
			hole += 1
			screw_done.emit(hole)
			aligned = false
			progress = 0.0
			if hole >= HOLES.size():
				done_time = time
				_say("Dolap duvara sabitlendi!")
			else:
				_say("Vida %d / 4 tamam." % hole)
				sweep_phase = -PI * 0.5
	tip_vel = lerpf(tip_vel, (tip_x - prev) / maxf(delta, 0.001), 0.2)
	trail.push_front(tip_x)
	if trail.size() > 8:
		trail.pop_back()
	canvas.queue_redraw()


func _draw_ui() -> void:
	var view := canvas.size
	var font := ThemeDB.fallback_font
	canvas.draw_rect(Rect2(Vector2.ZERO, view), Color(0, 0, 0, 0.72 * _ease(appear)))
	var o := _origin() + Vector2(sin(time * 80.0), cos(time * 60.0)) * 4.0 * shake
	var panel := Rect2(o, SIZE)
	canvas.draw_rect(panel.grow(6), Color(0, 0, 0, 0.4))
	canvas.draw_rect(panel, Color("2a2420"))
	# Duvar: çizgili duvar kâğıdı.
	var wall := Rect2(o + Vector2(20, 70), Vector2(SIZE.x - 40, 220))
	canvas.draw_rect(wall, Color("ddd2bd"))
	for i in int(wall.size.x / 26.0):
		canvas.draw_rect(Rect2(wall.position + Vector2(i * 26 + 8, 0), Vector2(8, wall.size.y)), Color(0.75, 0.68, 0.55, 0.25))
	canvas.draw_rect(Rect2(wall.position.x, wall.end.y - 8, wall.size.x, 8), Color(0, 0, 0, 0.15))
	# Dolabın üst yüzü: ahşap damarlı.
	var wood := Rect2(o + Vector2(160, 290), Vector2(SIZE.x - 180, 210))
	canvas.draw_rect(wood, Color("8a5a34"))
	for i in 14:
		var y := wood.position.y + 8 + i * 15
		var pts := PackedVector2Array()
		for k in 12:
			var x := wood.position.x + k * wood.size.x / 11.0
			pts.append(Vector2(x, y + sin(k * 0.9 + i) * 2.5))
		canvas.draw_polyline(pts, Color("74482a"), 1.5)
	canvas.draw_rect(Rect2(wood.position, Vector2(wood.size.x, 10)), Color("a86f44"))
	canvas.draw_rect(Rect2(wood.position + Vector2(0, 10), Vector2(wood.size.x, 3)), Color(0, 0, 0, 0.25))
	# L-köşebentler: duvar kanadı + dolap kanadı, büküm çizgisi birleşim yerinde.
	for x in [330.0, 530.0]:
		var wall_leaf := Rect2(o + Vector2(x - 30, 214), Vector2(60, 76))
		var top_leaf := Rect2(o + Vector2(x - 30, 290), Vector2(60, 76))
		canvas.draw_rect(Rect2(wall_leaf.position + Vector2(4, 4), Vector2(60, 152)), Color(0, 0, 0, 0.25))
		canvas.draw_rect(wall_leaf, Color("aeb7bc"))
		canvas.draw_rect(top_leaf, Color("9aa4a9"))
		canvas.draw_rect(Rect2(wall_leaf.position, Vector2(60, 8)), Color("cdd4d8"))
		canvas.draw_rect(Rect2(top_leaf.position, Vector2(60, 5)), Color("c2cacd"))
		canvas.draw_rect(wall_leaf, Color("5d666c"), false, 2.5)
		canvas.draw_rect(top_leaf, Color("5d666c"), false, 2.5)
	for sc in scratches:
		var p: Vector2 = o + sc[0]
		canvas.draw_line(p - Vector2(16, 0).rotated(sc[1]), p + Vector2(16, 0).rotated(sc[1]), Color("4a2f18"), 2.0)
	# Delikler, vidalar ve dolum halkası.
	for i in HOLES.size():
		var c: Vector2 = o + HOLES[i]
		if i < hole:
			_screw(c, 11.0, 0.3, 1.0)
			continue
		canvas.draw_circle(c, 8.0, Color("161616"))
		canvas.draw_circle(c + Vector2(-2, -2), 3.0, Color(1, 1, 1, 0.08))
		if i == hole:
			var in_range := not aligned and absf(tip_x - HOLES[i].x) <= HIT
			var ring_col := Color(0.4, 1.0, 0.45, 0.95) if in_range else Color(1, 0.85, 0.3, 0.6 + 0.3 * sin(time * 6.0))
			canvas.draw_arc(c, 17.0 + (0.0 if in_range else sin(time * 6.0) * 2.0), 0, TAU, 40, ring_col, 3.0)
			if aligned:
				_screw(c, 11.0 + (1.0 - progress) * 8.0, spin, 0.5 + progress * 0.5)
				canvas.draw_arc(c, 26.0, -PI * 0.5, -PI * 0.5 + TAU * progress, 48, Color("e0b020"), 5.0)
	for p in pops:
		var k: float = p.age / 0.6
		canvas.draw_arc(o + p.pos, 14.0 + k * 34.0, 0, TAU, 40, Color(p.color, 1.0 - k), 4.0 * (1.0 - k) + 1.0)
	for d in dust:
		canvas.draw_rect(Rect2(o + d.pos, Vector2(3, 3)), Color(0.92, 0.8, 0.56, 1.0 - d.age / 0.9))
	if done_time < 0.0:
		_draw_drill(o)
	canvas.draw_rect(panel, Color("e0b020"), false, 4.0)
	canvas.draw_string(font, o + Vector2(0, 44), "DOLABI DUVARA VİDALA", HORIZONTAL_ALIGNMENT_CENTER, SIZE.x, 30, Color("ffe7a8"))
	for i in HOLES.size():
		var dot := o + Vector2(SIZE.x * 0.5 - 45 + i * 30, 60)
		canvas.draw_circle(dot, 7.0, Color("e0b020") if i < hole else Color(1, 1, 1, 0.2))
	var help := "Uç YEŞİL halkadayken [E / sol tık] bas → sonra BASILI tut." if not aligned else "[E / sol tık] BASILI tut: vidayı sık!"
	canvas.draw_string(font, o + Vector2(0, SIZE.y + 38), help, HORIZONTAL_ALIGNMENT_CENTER, SIZE.x, 22, Color.WHITE)
	if message_time > 0.0:
		canvas.draw_string(font, o + Vector2(0, -16), message, HORIZONTAL_ALIGNMENT_CENTER, SIZE.x, 24, Color(1, 0.85, 0.55, minf(1.0, message_time * 2.0)))


# Akülü matkap: hareket yönüne hafif eğilir, iz bırakır; mandren dönerken çizgiler kayar.
func _draw_drill(o: Vector2) -> void:
	var target: Vector2 = HOLES[hole]
	for i in trail.size():
		var a := 0.18 * (1.0 - float(i) / trail.size())
		canvas.draw_circle(o + Vector2(trail[i], target.y), 4.0, Color(1, 1, 1, a))
	var holding := aligned and (Input.is_physical_key_pressed(KEY_E) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
	var vib := Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5)) if holding else Vector2.ZERO
	var tip := o + Vector2(tip_x, target.y) + vib
	var tilt := clampf(-tip_vel / 900.0, -0.25, 0.25)
	canvas.draw_set_transform(tip, tilt)
	canvas.draw_circle(Vector2(0, 2), 10.0, Color(0, 0, 0, 0.2))
	canvas.draw_line(Vector2.ZERO, Vector2(0, -34), Color("cfd4d7"), 4.0)
	for k in 4:
		var y := -6.0 - fmod(k * 8.0 + spin * 6.0, 32.0)
		canvas.draw_line(Vector2(-2, y), Vector2(2, y - 3), Color("7d8285"), 1.5)
	canvas.draw_rect(Rect2(-11, -58, 22, 24), Color("6f7478"))
	for k in 3:
		var x := -9.0 + fmod(k * 7.0 + spin * 4.0, 18.0)
		canvas.draw_line(Vector2(x, -56), Vector2(x, -36), Color("4b4f52"), 2.0)
	var body := PackedVector2Array([Vector2(-26, -112), Vector2(46, -112), Vector2(52, -100), Vector2(46, -62), Vector2(-26, -62)])
	canvas.draw_colored_polygon(body, Color("e0b020"))
	canvas.draw_polyline(PackedVector2Array([Vector2(-26, -112), Vector2(46, -112), Vector2(52, -100), Vector2(46, -62), Vector2(-26, -62), Vector2(-26, -112)]), Color("5a4510"), 3.0)
	canvas.draw_rect(Rect2(-20, -106, 60, 8), Color("f2d060"))
	canvas.draw_rect(Rect2(24, -62, 20, 50), Color("2a2a2a"))
	canvas.draw_rect(Rect2(18, -18, 32, 14), Color("3a3a3a"))
	canvas.draw_rect(Rect2(16, -58, 8, 10), Color("c0392b") if holding else Color("8a2a20"))
	canvas.draw_set_transform(Vector2.ZERO)


func _screw(c: Vector2, r: float, angle: float, alpha: float) -> void:
	canvas.draw_circle(c + Vector2(2, 2), r + 2.0, Color(0, 0, 0, 0.25 * alpha))
	canvas.draw_circle(c, r + 2.0, Color(0.25, 0.27, 0.29, alpha))
	canvas.draw_circle(c, r, Color(0.82, 0.85, 0.87, alpha))
	canvas.draw_circle(c + Vector2(-r * 0.3, -r * 0.3), r * 0.35, Color(1, 1, 1, 0.35 * alpha))
	var d := Vector2.from_angle(angle + PI * 0.25) * r * 0.7
	canvas.draw_line(c - d, c + d, Color(0.25, 0.27, 0.29, alpha), 3.0)
	canvas.draw_line(c - d.orthogonal(), c + d.orthogonal(), Color(0.25, 0.27, 0.29, alpha), 3.0)
